#!/usr/bin/env bash
# Drain queue (TASK-005): consumes .gsd-recipe/sync-queue.jsonl rows produced by
# sync-reconcile.sh (TASK-003) and closes the loop it deliberately left open.
#
# Like sync-reconcile.sh, this script has no MCP tool-calling access -- only an
# agent turn can call `addCommentToJiraIssue`. So it does everything AROUND the
# post (re-verify against the ledger, re-draft the comment body, record the
# outcome afterwards) and leaves the actual Jira call to the caller (the
# gsd-jira-sync skill's "Drain mode" -- see reference/skills/gsd-jira-sync/SKILL.md).
#
# Workflow:
#   1. `list`        -- read queued/failed rows, self-heal anything already
#                        posted out-of-band (ledger already has the key), and
#                        re-draft comment bodies for what's genuinely pending.
#                        Prints a JSON work list. No MCP call happens here.
#   2. (agent turn)   -- for each work item, read MCP tool schemas and call
#                        addCommentToJiraIssue with issue_key + body.
#   3. `mark-done`    -- on success: append `posted` to sync-ledger.jsonl,
#                        flip the queue row to `done`, emit the KPI stamp
#                        configured for that event_id in jira-events.json.
#      `mark-failed`  -- on failure: flip the queue row to `failed` + error,
#                        so the next `list` run retries it.
#
# The queue row itself never stores comment body text (DATA-CONTRACTS.md's
# sync-queue.jsonl schema has no `body` field) -- `list` always re-drafts via
# draft-jira-comment.sh from event_id/issue_key/phase_id, which is the intended
# design, not a gap: it reflects the *current* state of `.planning/` at drain
# time rather than a possibly-stale snapshot from whenever reconcile ran.
#
# Usage:
#   sync-drain-queue.sh list [--queue PATH] [--ledger PATH]
#   sync-drain-queue.sh mark-done <key> --external-id ID [--arm recipe] [--run run-01] [--actor agent] [--queue PATH] [--ledger PATH] [--events PATH]
#   sync-drain-queue.sh mark-failed <key> --error MSG [--queue PATH]
#
# Examples:
#   bench/runners/sync-drain-queue.sh list
#   bench/runners/sync-drain-queue.sh mark-done "gsd-recipe:plan_complete:phase=1:issue=PROJ-101" --external-id 10091 --run pilot-01
#   bench/runners/sync-drain-queue.sh mark-failed "gsd-recipe:plan_complete:phase=1:issue=PROJ-101" --error "MCP auth expired"
set -euo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

DEFAULT_QUEUE="$REPO_ROOT/.gsd-recipe/sync-queue.jsonl"
DEFAULT_LEDGER="$REPO_ROOT/.gsd-recipe/sync-ledger.jsonl"
DEFAULT_EVENTS="$BENCH_ROOT/recipe/trackers/jira-events.json"
SYNC_LEDGER="$BENCH_ROOT/lib/sync-ledger.sh"
DRAFT="$BENCH_ROOT/runners/draft-jira-comment.sh"
EMIT_STAMP="$BENCH_ROOT/runners/emit-stamp.sh"

usage() {
  cat >&2 <<'EOF'
Usage:
  sync-drain-queue.sh list [--queue PATH] [--ledger PATH]
  sync-drain-queue.sh mark-done <key> --external-id ID [--arm recipe] [--run run-01] [--actor agent] [--queue PATH] [--ledger PATH] [--events PATH]
  sync-drain-queue.sh mark-failed <key> --error MSG [--queue PATH]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  list)
    QUEUE="$DEFAULT_QUEUE"; LEDGER="$DEFAULT_LEDGER"
    while [ $# -gt 0 ]; do
      case "$1" in
        --queue) QUEUE="${2:?--queue requires a value}"; shift 2 ;;
        --ledger) LEDGER="${2:?--ledger requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    QUEUE="$QUEUE" LEDGER="$LEDGER" SYNC_LEDGER="$SYNC_LEDGER" DRAFT="$DRAFT" \
    python3 - <<'PY'
import json, os, subprocess, sys

QUEUE = os.environ["QUEUE"]
LEDGER = os.environ["LEDGER"]
SYNC_LEDGER = os.environ["SYNC_LEDGER"]
DRAFT = os.environ["DRAFT"]


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def ledger_has(key):
    r = sh([SYNC_LEDGER, "has", key, "--ledger", LEDGER])
    return r.returncode == 0


rows = []
if os.path.isfile(QUEUE):
    with open(QUEUE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                continue

work = []
healed = []
errors = []
changed = False

for row in rows:
    if row.get("status") not in ("queued", "failed"):
        continue
    key = row.get("key")
    if not key:
        errors.append({"row": row, "error": "queue row missing 'key'"})
        continue

    if ledger_has(key):
        # Something else already posted this (e.g. a manual gsd-jira-sync
        # call happened between reconcile and drain) -- self-heal rather
        # than hand a duplicate to the agent.
        row["status"] = "done"
        row["result"] = "duplicate_skipped"
        row.pop("error", None)
        healed.append({"key": key, "event_id": row.get("event_id"), "issue_key": row.get("issue_key")})
        changed = True
        continue

    if row.get("target", "jira") != "jira":
        errors.append({"key": key, "error": f"target '{row.get('target')}' not supported yet (TASK-006)"})
        continue

    cmd = [DRAFT, row["event_id"], row["issue_key"]]
    if row.get("phase_id") is not None:
        cmd += ["--phase", str(row["phase_id"])]
    r = sh(cmd)
    if r.returncode != 0:
        errors.append({"key": key, "error": f"draft-jira-comment.sh failed: {r.stderr.strip()}"})
        continue

    work.append({
        "key": key,
        "event_id": row["event_id"],
        "issue_key": row["issue_key"],
        "phase_id": row.get("phase_id"),
        "target": row.get("target", "jira"),
        "body": r.stdout,
    })

if changed:
    with open(QUEUE, "w") as f:
        for row in rows:
            f.write(json.dumps(row) + "\n")

print(json.dumps({"work": work, "self_healed": healed, "errors": errors}, indent=2))
if errors:
    sys.exit(1)
PY
    ;;

  mark-done)
    [ $# -ge 1 ] || usage
    KEY="$1"; shift
    EXTERNAL_ID=""; ARM="recipe"; RUN_ID="run-01"; ACTOR="agent"
    QUEUE="$DEFAULT_QUEUE"; LEDGER="$DEFAULT_LEDGER"; EVENTS="$DEFAULT_EVENTS"
    while [ $# -gt 0 ]; do
      case "$1" in
        --external-id) EXTERNAL_ID="${2:?--external-id requires a value}"; shift 2 ;;
        --arm) ARM="${2:?--arm requires a value}"; shift 2 ;;
        --run) RUN_ID="${2:?--run requires a value}"; shift 2 ;;
        --actor) ACTOR="${2:?--actor requires a value}"; shift 2 ;;
        --queue) QUEUE="${2:?--queue requires a value}"; shift 2 ;;
        --ledger) LEDGER="${2:?--ledger requires a value}"; shift 2 ;;
        --events) EVENTS="${2:?--events requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    [ -n "$EXTERNAL_ID" ] || { echo "ERROR: --external-id is required" >&2; exit 2; }

    KEY="$KEY" EXTERNAL_ID="$EXTERNAL_ID" ARM="$ARM" RUN_ID="$RUN_ID" ACTOR="$ACTOR" \
    QUEUE="$QUEUE" LEDGER="$LEDGER" EVENTS="$EVENTS" \
    SYNC_LEDGER="$SYNC_LEDGER" EMIT_STAMP="$EMIT_STAMP" \
    python3 - <<'PY'
import json, os, subprocess, sys

key = os.environ["KEY"]
external_id = os.environ["EXTERNAL_ID"]
arm = os.environ["ARM"]
run_id = os.environ["RUN_ID"]
actor = os.environ["ACTOR"]
queue_path = os.environ["QUEUE"]
ledger_path = os.environ["LEDGER"]
events_path = os.environ["EVENTS"]
sync_ledger = os.environ["SYNC_LEDGER"]
emit_stamp = os.environ["EMIT_STAMP"]

if not os.path.isfile(queue_path):
    sys.exit(f"ERROR: queue file not found: {queue_path}")

rows = []
with open(queue_path) as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

target_row = next((r for r in rows if r.get("key") == key), None)
if target_row is None:
    sys.exit(f"ERROR: no queue row found for key: {key}")
if target_row.get("status") == "done":
    sys.exit(f"ERROR: queue row for key '{key}' is already marked done")

event_id = target_row["event_id"]
issue_key = target_row["issue_key"]

# 1. Ledger append first -- this is the real idempotency source of truth.
r = subprocess.run(
    [sync_ledger, "append", key, "jira", "--external-id", external_id,
     "--result", "posted", "--ledger", ledger_path],
    capture_output=True, text=True,
)
if r.returncode != 0:
    sys.exit(f"ERROR: sync-ledger.sh append failed: {r.stderr.strip()}")

# 2. Flip the queue row to done.
target_row["status"] = "done"
target_row["result"] = "posted"
target_row["external_id"] = external_id
target_row.pop("error", None)
with open(queue_path, "w") as f:
    for row in rows:
        f.write(json.dumps(row) + "\n")

# 3. Emit the KPI stamp configured for this event, if any (some events, e.g.
#    execute_wave / verify_complete, deliberately have stamp: null).
stamp_note = "(no stamp configured for this event)"
events = json.loads(open(events_path).read())
match = next((e for e in events["events"] if e["id"] == event_id), None)
stamp = match.get("stamp") if match else None
if stamp:
    r = subprocess.run(
        [emit_stamp, arm, run_id, stamp["status"], stamp["step"], issue_key, actor, "jira"],
        capture_output=True, text=True,
    )
    if r.returncode != 0:
        sys.exit(f"ERROR: emit-stamp.sh failed: {r.stderr.strip()}")
    stamp_note = r.stdout.strip()

print(json.dumps({
    "key": key, "event_id": event_id, "issue_key": issue_key,
    "ledger": "posted", "queue": "done", "stamp": stamp_note,
}, indent=2))
PY
    ;;

  mark-failed)
    [ $# -ge 1 ] || usage
    KEY="$1"; shift
    ERROR_MSG=""; QUEUE="$DEFAULT_QUEUE"
    while [ $# -gt 0 ]; do
      case "$1" in
        --error) ERROR_MSG="${2:?--error requires a value}"; shift 2 ;;
        --queue) QUEUE="${2:?--queue requires a value}"; shift 2 ;;
        --ledger) shift 2 ;; # accepted for CLI symmetry with list/mark-done; unused here
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    [ -n "$ERROR_MSG" ] || { echo "ERROR: --error is required" >&2; exit 2; }

    QUEUE="$QUEUE" KEY="$KEY" ERROR_MSG="$ERROR_MSG" python3 - <<'PY'
import json, os, sys

key = os.environ["KEY"]
path = os.environ["QUEUE"]
error_msg = os.environ["ERROR_MSG"]

if not os.path.isfile(path):
    sys.exit(f"ERROR: queue file not found: {path}")

rows = []
with open(path) as f:
    for line in f:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

found = False
for row in rows:
    if row.get("key") == key:
        row["status"] = "failed"
        row["error"] = error_msg
        found = True

if not found:
    sys.exit(f"ERROR: no queue row found for key: {key}")

with open(path, "w") as f:
    for row in rows:
        f.write(json.dumps(row) + "\n")

print(f"Marked {key} as failed: {error_msg}")
PY
    ;;

  *)
    usage
    ;;
esac
