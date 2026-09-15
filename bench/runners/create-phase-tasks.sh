#!/usr/bin/env bash
# Tracker epic + phase tasks (TASK-007): reads ROADMAP.md's declared phases, reads
# .planning/STATE.md via parse-state.sh to see which phases already have a Jira
# sub-task (idempotency), and for every phase WITHOUT one, drafts a sub-task
# summary/description and queues it for creation.
#
# RUNTIME-LLD.md § "1.d Tracker epic + tasks [C]" spec: "Epic + one task per
# phase" via adapter ops `create_subissue` + `link` (TRACEABILITY-LLD.md §
# Tracker adapter). Same "bash has no MCP tool-calling access" constraint as
# sync-reconcile.sh: this script can DETECT + DRAFT + QUEUE, but the actual
# `createJiraIssue` (create_subissue) and native Parent/Epic Link verification
# (link) must happen in an agent turn. So, mirroring sync-reconcile.sh's split
# from its drain step:
#
#   detect       -- (this script, no MCP) enumerate ROADMAP.md phases, skip any
#                    phase that already has an issue_key in STATE.md's
#                    '## Phase tasks' table, draft a summary/description for
#                    the rest from _phase_task.template.md, and queue them.
#   (agent turn) -- for each queued phase: call createJiraIssue (project
#                    inferred from the epic key's prefix, parent = epic via
#                    the issue type's writable native Parent field (preferred)
#                    or its legacy Epic Link custom field), then verify that
#                    hierarchy via getJiraIssue), matching the
#                    exact MCP call shape proven live in
#                    bench/report/gsd-jira-sync-live-test-report.md.
#   list         -- (this script, no MCP; TASK-034) mirrors
#                    sync-drain-queue.sh's own `list`: re-verifies every
#                    queued/failed row against parse-state.sh's `dump` (i.e.
#                    STATE.md's '## Phase tasks' table) FIRST. If a phase_id
#                    already has a linked issue_key there (e.g. someone ran
#                    `add-phase-task` manually in between, or a previous
#                    `list`+create pass got interrupted after mark-done's
#                    STATE.md write but before this script's own queue-file
#                    write), self-heal that row in place (status -> done,
#                    issue_key recorded, no MCP call, counted under
#                    self_healed) rather than handing a duplicate-create to
#                    the agent. Everything genuinely still pending is
#                    returned in a `work` array, reusing the exact fields
#                    `detect` already stored per row (phase_id/epic_key/
#                    phase_title/phase_goal/drafted_summary/
#                    drafted_description/target/key) -- never re-derived from
#                    ROADMAP.md again. No MCP call happens here; the agent
#                    turn that consumes `work` is the one that calls
#                    createJiraIssue/getJiraIssue (see
#                    recipe-create-phase-tasks-SKILL.md, TASK-034).
#   mark-done    -- (this script, no MCP) record the created issue_key: writes
#                    it into STATE.md via `parse-state.sh add-phase-task`, and
#                    flips the queue row to done.
#   mark-failed  -- (this script, no MCP) flip the queue row to failed + error,
#                    so the next `detect` run retries it (per FAILURE-MATRIX.md
#                    "Tracker API fail -> continue GSD work; queue sync
#                    retries").
#
# Queue file — deliberately NOT .gsd-recipe/sync-queue.jsonl:
#   sync-queue.jsonl's schema (DATA-CONTRACTS.md) requires `event_id` (must
#   exist in jira-events.json's *comment* event vocabulary) and a non-empty
#   `issue_key` (the target to comment on). `create_subissue` work items are
#   the opposite shape: there IS no issue_key yet -- that's what's being
#   created -- and "create a phase task" is an adapter op, not a jira-events.json
#   comment event. Shoehorning this in would mean either making sync-queue.jsonl's
#   issue_key optional (weakens a field every existing consumer, including
#   sync-drain-queue.sh, currently treats as required) or inventing a fake
#   event_id not in jira-events.json (breaks sync-drain-queue.sh's `list`
#   validation path, which drafts via draft-jira-comment.sh keyed on event_id).
#   Both require touching sync-drain-queue.sh's established schema/behavior --
#   explicitly out of scope for this task. So this script uses its own queue
#   file, .gsd-recipe/phase-tasks-queue.jsonl, with its own schema (see below).
#   Idempotency keys still reuse sync-ledger.sh's `key` subcommand for format
#   consistency (event_id slot = "create_subissue", issue_key slot = the EPIC
#   key, since no phase issue exists yet): gsd-recipe:create_subissue:phase={N}:issue={EPIC_KEY}
#
# .gsd-recipe/phase-tasks-queue.jsonl row shape:
#   {queued_at, phase_id, phase_title, phase_goal, epic_key, key, status,
#    target: "jira", drafted_summary, drafted_description, issue_key?, error?}
#   status: queued | done | failed
#
# Usage:
#   create-phase-tasks.sh detect [--dry-run] [--roadmap PATH] [--state PATH]
#                                 [--queue PATH] [--arm recipe] [--run RUN_ID]
#   create-phase-tasks.sh list [--queue PATH] [--state PATH]
#   create-phase-tasks.sh mark-done <phase_id> <issue_key> [--state PATH] [--queue PATH]
#   create-phase-tasks.sh mark-failed <phase_id> --error MSG [--queue PATH]
#
# Examples:
#   bench/runners/create-phase-tasks.sh detect --dry-run          # CI-safe: no writes
#   bench/runners/create-phase-tasks.sh detect --run pilot-01      # writes queue rows
#   bench/runners/create-phase-tasks.sh list                       # self-heal + return pending work
#   bench/runners/create-phase-tasks.sh mark-done 2 PROJ-102       # after a real createJiraIssue+link
#   bench/runners/create-phase-tasks.sh mark-failed 2 --error "Jira API 500"
set -euo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

DEFAULT_ROADMAP="$REPO_ROOT/.planning/ROADMAP.md"
DEFAULT_STATE="$REPO_ROOT/.planning/STATE.md"
DEFAULT_QUEUE="$REPO_ROOT/.gsd-recipe/phase-tasks-queue.jsonl"
TEMPLATE="$BENCH_ROOT/recipe/templates/jira-phase-tasks/_phase_task.template.md"
PARSE_STATE="$BENCH_ROOT/lib/parse-state.sh"
SYNC_LEDGER="$BENCH_ROOT/lib/sync-ledger.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  create-phase-tasks.sh detect [--dry-run] [--roadmap PATH] [--state PATH]
                                [--queue PATH] [--arm recipe] [--run RUN_ID]
  create-phase-tasks.sh list [--queue PATH] [--state PATH]
  create-phase-tasks.sh mark-done <phase_id> <issue_key> [--state PATH] [--queue PATH]
  create-phase-tasks.sh mark-failed <phase_id> --error MSG [--queue PATH]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  detect)
    DRY_RUN=0
    ROADMAP_FILE="$DEFAULT_ROADMAP"
    STATE_FILE="$DEFAULT_STATE"
    QUEUE_FILE="$DEFAULT_QUEUE"
    ARM="recipe"
    RUN_ID="run-01"
    while [ $# -gt 0 ]; do
      case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --roadmap) ROADMAP_FILE="${2:?--roadmap requires a value}"; shift 2 ;;
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        --queue) QUEUE_FILE="${2:?--queue requires a value}"; shift 2 ;;
        --arm) ARM="${2:?--arm requires a value}"; shift 2 ;;
        --run) RUN_ID="${2:?--run requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done

    REPO_ROOT="$REPO_ROOT" DRY_RUN="$DRY_RUN" ROADMAP_FILE="$ROADMAP_FILE" \
    STATE_FILE="$STATE_FILE" QUEUE_FILE="$QUEUE_FILE" ARM="$ARM" RUN_ID="$RUN_ID" \
    TEMPLATE="$TEMPLATE" PARSE_STATE="$PARSE_STATE" SYNC_LEDGER="$SYNC_LEDGER" \
    python3 - <<'PY'
import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone

DRY_RUN = os.environ["DRY_RUN"] == "1"
ROADMAP_FILE = pathlib.Path(os.environ["ROADMAP_FILE"])
STATE_FILE = os.environ["STATE_FILE"]
QUEUE_FILE = pathlib.Path(os.environ["QUEUE_FILE"])
ARM = os.environ["ARM"]
RUN_ID = os.environ["RUN_ID"]
TEMPLATE = pathlib.Path(os.environ["TEMPLATE"])
PARSE_STATE = os.environ["PARSE_STATE"]
SYNC_LEDGER = os.environ["SYNC_LEDGER"]


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


if not ROADMAP_FILE.is_file():
    fail(f"ROADMAP.md not found at {ROADMAP_FILE}")

r = sh([PARSE_STATE, "get-tracker", "--state", STATE_FILE])
if r.returncode != 0:
    fail(
        f"could not resolve tracker epic from {STATE_FILE}: {r.stderr.strip()} "
        "-- run tracker intake (1.a/1.b) before creating phase tasks"
    )
tracker = json.loads(r.stdout)
epic_key = tracker.get("epic", "")
if not epic_key:
    fail(f"'## Tracker' in {STATE_FILE} has no 'epic' value")

r = sh([PARSE_STATE, "dump", "--state", STATE_FILE])
if r.returncode != 0:
    fail(f"could not dump {STATE_FILE}: {r.stderr.strip()}")
dumped = json.loads(r.stdout)
linked = {
    row["phase_id"]: row["issue_key"]
    for row in dumped.get("phase_tasks", [])
    if row.get("issue_key")
}

# ROADMAP.md phase enumeration. RUNTIME-LLD.md gives no fixed grammar beyond
# "ROADMAP phases". Two dialects exist in practice:
#   - This repo's own .planning/ROADMAP.md (and the bench/ test fixtures) use
#     '## Phase N — Title' (H2, em-dash/hyphen separator).
#   - GSD's actual gsd-new-project/gsd-plan-phase output (see
#     get-shit-done/templates/roadmap.md's "## Phase Details" section, and any
#     real GSD-managed .planning/ROADMAP.md) uses '### Phase N: Title' (H3,
#     colon separator, nested under a '## Phase Details' H2). The comment that
#     used to live here claiming GSD produces the H2/em-dash form was wrong --
#     verified wrong against the actual GSD template and against a real GSD
#     sandbox ROADMAP.md, which this regex previously failed to parse at all.
# Accept both: level is H2 or H3 ('#{2,3}'), separator is em-dash, hyphen, or
# colon (or omitted entirely). Phase 0 ("Done", "harness", etc.) is
# intentionally included -- RUNTIME-LLD.md's "one task per phase" doesn't
# carve out phase 0, and a repo choosing to track it in Jira should get a
# phase-0 sub-task too.
PHASE_HEADING = re.compile(r"^#{2,3}\s+Phase\s+(\d+)\b\s*[—\-:]?\s*(.*)$")
# Goal line similarly has two dialects: '**Goal:** ...' (colon inside the bold)
# and GSD's actual '**Goal**: ...' (colon outside the bold). Accept both.
GOAL_LINE = re.compile(r"^\*\*Goal(?::\*\*|\*\*:)\s*(.*)$")
# Must match the same heading levels as PHASE_HEADING so the goal-line scan
# stops at the next phase heading (H2 or H3) instead of reading into it.
ANY_HEADING = re.compile(r"^#{2,3}\s+")

text = ROADMAP_FILE.read_text(errors="replace")
lines = text.splitlines()
phases = []  # [{phase_id, title, goal}]
i = 0
n = len(lines)
while i < n:
    m = PHASE_HEADING.match(lines[i])
    if m:
        phase_id = m.group(1)
        title = m.group(2).strip() or f"Phase {phase_id}"
        goal = ""
        j = i + 1
        while j < n and not ANY_HEADING.match(lines[j]):
            gm = GOAL_LINE.match(lines[j].strip())
            if gm:
                goal = gm.group(1).strip()
                break
            j += 1
        phases.append({"phase_id": phase_id, "title": title, "goal": goal})
    i += 1

if not phases:
    fail(
        f"no '## Phase N — Title' or '### Phase N: Title' headings found in "
        f"{ROADMAP_FILE}"
    )

template_body = TEMPLATE.read_text()


def render(phase):
    body = template_body
    goal = phase["goal"] or "(no goal declared in ROADMAP.md)"
    for k, v in {
        "{{EPIC_KEY}}": epic_key,
        "{{PHASE_ID}}": phase["phase_id"],
        "{{PHASE_TITLE}}": phase["title"],
        "{{PHASE_GOAL}}": goal,
        "{{ARM}}": ARM,
        "{{RUN_ID}}": RUN_ID,
    }.items():
        body = body.replace(k, v)
    return body


def ledger_key(phase_id):
    r = sh([SYNC_LEDGER, "key", "create_subissue", epic_key, "--phase", str(phase_id)])
    if r.returncode != 0:
        raise RuntimeError(f"sync-ledger.sh key failed: {r.stderr}")
    return r.stdout.strip()


existing_rows = []
if QUEUE_FILE.is_file():
    with open(QUEUE_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                existing_rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue

by_key = {row["key"]: row for row in existing_rows if "key" in row}

to_create = []
already_linked = []
already_queued = []
requeued = []
errors = []
rows_changed = False

for phase in sorted(phases, key=lambda p: int(p["phase_id"])):
    phase_id = phase["phase_id"]
    if phase_id in linked:
        already_linked.append({"phase_id": phase_id, "issue_key": linked[phase_id]})
        continue

    try:
        key = ledger_key(phase_id)
    except RuntimeError as e:
        errors.append({"phase_id": phase_id, "error": str(e)})
        continue

    existing = by_key.get(key)
    if existing is not None and existing.get("status") in ("queued", "done"):
        already_queued.append({"phase_id": phase_id, "key": key, "status": existing["status"]})
        continue

    summary = f"[GSD Recipe] Phase {phase_id}: {phase['title']}"
    description = render(phase)

    if existing is not None and existing.get("status") == "failed":
        # Retryable -- reset the existing row in place rather than duplicating
        # a second queue line for the same phase (FAILURE-MATRIX.md: "queue
        # sync retries").
        existing["status"] = "queued"
        existing["queued_at"] = datetime.now(timezone.utc).isoformat()
        existing["drafted_summary"] = summary
        existing["drafted_description"] = description
        existing.pop("error", None)
        rows_changed = True
        requeued.append({"phase_id": phase_id, "key": key})
        to_create.append({"phase_id": phase_id, "key": key, "drafted_summary": summary})
        continue

    entry = {
        "queued_at": datetime.now(timezone.utc).isoformat(),
        "phase_id": phase_id,
        "phase_title": phase["title"],
        "phase_goal": phase["goal"],
        "epic_key": epic_key,
        "key": key,
        "status": "queued",
        "target": "jira",
        "drafted_summary": summary,
        "drafted_description": description,
    }
    existing_rows.append(entry)
    by_key[key] = entry
    rows_changed = True
    to_create.append({
        "phase_id": phase_id,
        "key": key,
        "drafted_summary": summary,
        "drafted_description": description,
    })

if not DRY_RUN and rows_changed:
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(QUEUE_FILE, "w") as f:
        for row in existing_rows:
            f.write(json.dumps(row) + "\n")

print(json.dumps({
    "dry_run": DRY_RUN,
    "epic_key": epic_key,
    "to_create": to_create,
    "already_linked": already_linked,
    "already_queued": already_queued,
    "requeued": requeued,
    "errors": errors,
}, indent=2))

if errors:
    sys.exit(1)
PY
    ;;

  list)
    STATE_FILE="$DEFAULT_STATE"
    QUEUE_FILE="$DEFAULT_QUEUE"
    while [ $# -gt 0 ]; do
      case "$1" in
        --queue) QUEUE_FILE="${2:?--queue requires a value}"; shift 2 ;;
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done

    QUEUE_FILE="$QUEUE_FILE" STATE_FILE="$STATE_FILE" PARSE_STATE="$PARSE_STATE" \
    python3 - <<'PY'
import json, os, subprocess, sys

QUEUE_FILE = os.environ["QUEUE_FILE"]
STATE_FILE = os.environ["STATE_FILE"]
PARSE_STATE = os.environ["PARSE_STATE"]


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


rows = []
if os.path.isfile(QUEUE_FILE):
    with open(QUEUE_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue

pending = [r for r in rows if r.get("status") in ("queued", "failed")]

work = []
healed = []
errors = []
changed = False

# Only pay the parse-state.sh dump cost (and only risk its failure mode) when
# there's actually at least one pending row to re-verify -- an empty/all-done
# queue must never require a working STATE.md to return cleanly.
linked = {}
if pending:
    r = sh([PARSE_STATE, "dump", "--state", STATE_FILE])
    if r.returncode != 0:
        print(json.dumps({
            "work": [],
            "self_healed": [],
            "errors": [{
                "error": f"parse-state.sh dump failed: {r.stderr.strip()} "
                         "-- cannot self-heal or list phase-task work until "
                         f"{STATE_FILE} is valid",
            }],
        }, indent=2))
        sys.exit(1)
    dumped = json.loads(r.stdout)
    linked = {
        row["phase_id"]: row["issue_key"]
        for row in dumped.get("phase_tasks", [])
        if row.get("issue_key")
    }

for row in pending:
    key = row.get("key")
    if not key:
        errors.append({"row": row, "error": "queue row missing 'key'"})
        continue

    phase_id = row.get("phase_id")
    if phase_id in linked:
        # Something else already linked this phase (e.g. a manual
        # add-phase-task call happened between detect and list, or a prior
        # create+mark-done pass got interrupted after STATE.md was written
        # but before this queue row was flipped) -- self-heal rather than
        # handing a duplicate createJiraIssue to the agent.
        row["status"] = "done"
        row["issue_key"] = linked[phase_id]
        row.pop("error", None)
        healed.append({"phase_id": phase_id, "issue_key": linked[phase_id], "key": key})
        changed = True
        continue

    if row.get("target", "jira") != "jira":
        errors.append({"key": key, "error": f"target '{row.get('target')}' not supported yet"})
        continue

    work.append({
        "phase_id": phase_id,
        "key": key,
        "epic_key": row.get("epic_key"),
        "phase_title": row.get("phase_title"),
        "phase_goal": row.get("phase_goal"),
        "drafted_summary": row.get("drafted_summary"),
        "drafted_description": row.get("drafted_description"),
        "target": row.get("target", "jira"),
    })

if changed:
    with open(QUEUE_FILE, "w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

print(json.dumps({"work": work, "self_healed": healed, "errors": errors}, indent=2))
if errors:
    sys.exit(1)
PY
    ;;

  mark-done)
    [ $# -ge 2 ] || usage
    PHASE_ID="$1"; ISSUE_KEY="$2"; shift 2
    STATE_FILE="$DEFAULT_STATE"
    QUEUE_FILE="$DEFAULT_QUEUE"
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        --queue) QUEUE_FILE="${2:?--queue requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done

    PHASE_ID="$PHASE_ID" ISSUE_KEY="$ISSUE_KEY" STATE_FILE="$STATE_FILE" QUEUE_FILE="$QUEUE_FILE" \
    PARSE_STATE="$PARSE_STATE" python3 - <<'PY'
import json, os, subprocess, sys

phase_id = os.environ["PHASE_ID"]
issue_key = os.environ["ISSUE_KEY"]
state_file = os.environ["STATE_FILE"]
queue_path = os.environ["QUEUE_FILE"]
parse_state = os.environ["PARSE_STATE"]

if not os.path.isfile(queue_path):
    sys.exit(f"ERROR: queue file not found: {queue_path}")

rows = []
with open(queue_path) as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

target_row = next(
    (r for r in rows if str(r.get("phase_id")) == str(phase_id) and r.get("status") in ("queued", "failed")),
    None,
)
if target_row is None:
    sys.exit(
        f"ERROR: no queued/failed row for phase_id '{phase_id}' found in {queue_path} "
        "-- run 'detect' first"
    )

# Ledger-equivalent write first: STATE.md's '## Phase tasks' table is the real
# idempotency source of truth (same principle as sync-drain-queue.sh appending
# to sync-ledger.jsonl before flipping its queue row).
r = subprocess.run(
    [parse_state, "add-phase-task", str(phase_id), issue_key, "--state", state_file],
    capture_output=True, text=True,
)
if r.returncode != 0:
    sys.exit(f"ERROR: parse-state.sh add-phase-task failed: {r.stderr.strip()}")

target_row["status"] = "done"
target_row["issue_key"] = issue_key
target_row.pop("error", None)
with open(queue_path, "w") as f:
    for row in rows:
        f.write(json.dumps(row) + "\n")

print(json.dumps({
    "phase_id": phase_id, "issue_key": issue_key,
    "state": "updated", "queue": "done",
}, indent=2))
PY
    ;;

  mark-failed)
    [ $# -ge 1 ] || usage
    PHASE_ID="$1"; shift
    ERROR_MSG=""
    QUEUE_FILE="$DEFAULT_QUEUE"
    while [ $# -gt 0 ]; do
      case "$1" in
        --error) ERROR_MSG="${2:?--error requires a value}"; shift 2 ;;
        --queue) QUEUE_FILE="${2:?--queue requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    [ -n "$ERROR_MSG" ] || { echo "ERROR: --error is required" >&2; exit 2; }

    PHASE_ID="$PHASE_ID" ERROR_MSG="$ERROR_MSG" QUEUE_FILE="$QUEUE_FILE" python3 - <<'PY'
import json, os, sys

phase_id = os.environ["PHASE_ID"]
error_msg = os.environ["ERROR_MSG"]
queue_path = os.environ["QUEUE_FILE"]

if not os.path.isfile(queue_path):
    sys.exit(f"ERROR: queue file not found: {queue_path}")

rows = []
with open(queue_path) as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

found = False
for row in rows:
    if str(row.get("phase_id")) == str(phase_id) and row.get("status") == "queued":
        row["status"] = "failed"
        row["error"] = error_msg
        found = True

if not found:
    sys.exit(f"ERROR: no queued row found for phase_id: {phase_id}")

with open(queue_path, "w") as f:
    for row in rows:
        f.write(json.dumps(row) + "\n")

print(f"Marked phase_id '{phase_id}' as failed: {error_msg}")
PY
    ;;

  *)
    usage
    ;;
esac
