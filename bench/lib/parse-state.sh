#!/usr/bin/env bash
# Parser/validator for .planning/STATE.md — the tracker-linkage file that routes
# GSD milestone events to the right Jira epic or phase task (TASK-002).
#
# Contract (normative source: docs/netapp-recipe/contracts/DATA-CONTRACTS.md#state-md):
#   Fixed path   : .planning/STATE.md
#   ## Tracker   : key-value list, required fields epic/system/run_id/arm/url,
#                  optional legacy field `issue`. Must appear exactly once.
#   ## Phase tasks : markdown table, columns phase_id (unique) / issue_key (non-empty).
#                    Optional section — only required when a phase-routed event
#                    actually needs to resolve a phase_id (enforced by resolve-issue,
#                    not by validate).
#   Event routing (DATA-CONTRACTS.md rule 7 — carried in-code, no separate file):
#     Epic-routed  : intake_started, discuss_complete
#     Phase-routed : plan_complete, plan_revised, execute_started, execute_wave,
#                    execute_complete, verify_complete, review_complete,
#                    learning_stored, settled, reopened
#   Rule 8: resolving a phase-routed event with no matching phase_id fails
#           non-zero with an actionable error (never silently no-ops).
#
# Usage:
#   parse-state.sh get-tracker [--state PATH]
#   parse-state.sh get-phase-issue <phase_id> [--state PATH]
#   parse-state.sh resolve-issue <event_id> [--phase N] [--state PATH]
#   parse-state.sh add-phase-task <phase_id> <issue_key> [--state PATH]
#   parse-state.sh validate [--state PATH]
#   parse-state.sh dump [--state PATH]
#
# add-phase-task (TASK-007 dependent — bench/runners/create-phase-tasks.sh):
#   Writes/appends a phase_id -> issue_key row into '## Phase tasks'. Creates the
#   section (right after '## Tracker') if it doesn't exist yet. Refuses to run
#   (non-zero, actionable error) if phase_id already has a row — idempotency is
#   enforced here, not left to callers, same fail-fast posture as resolve-issue.
#
# init-tracker (TASK-033 dependent — recipe-create-epic / draft-jira-epic.sh):
#   Writes/overwrites the '## Tracker' section's 5 required fields
#   (epic/system/url/run_id/arm — DATA-CONTRACTS.md copy-paste example order,
#   `issue` omitted since it's optional/legacy). Creates STATE.md from
#   scratch (both sections) if it doesn't exist yet; inserts a '## Tracker'
#   section (preserving everything else byte-for-byte, including an existing
#   '## Phase tasks' table) if the file exists but has none yet. If a
#   '## Tracker' section already exists with a non-empty `epic`: identical
#   fields is a no-op (idempotent); different fields without --force fails
#   non-zero naming the existing epic key; different fields with --force
#   overwrites all 5 fields, leaving '## Phase tasks' and every other section
#   untouched.
#
# Examples:
#   bench/lib/parse-state.sh get-tracker --state .planning/STATE.md
#   bench/lib/parse-state.sh resolve-issue plan_complete --phase 1
#   bench/lib/parse-state.sh resolve-issue settled
#   bench/lib/parse-state.sh add-phase-task 4 PROJ-104 --state .planning/STATE.md
#   bench/lib/parse-state.sh init-tracker --epic PROJ-100 --system jira \
#     --url https://your-org.atlassian.net/browse/PROJ-100 --run-id pilot-01 --arm recipe
#   bench/lib/parse-state.sh validate || echo "STATE.md has problems, see stderr"
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DEFAULT_STATE="$REPO_ROOT/.planning/STATE.md"

usage() {
  cat >&2 <<'EOF'
Usage:
  parse-state.sh get-tracker [--state PATH]
  parse-state.sh get-phase-issue <phase_id> [--state PATH]
  parse-state.sh resolve-issue <event_id> [--phase N] [--state PATH]
  parse-state.sh add-phase-task <phase_id> <issue_key> [--state PATH]
  parse-state.sh init-tracker --epic KEY --system SYSTEM --url URL --run-id ID --arm ARM [--state PATH] [--force]
  parse-state.sh validate [--state PATH]
  parse-state.sh dump [--state PATH]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

STATE_FILE="$DEFAULT_STATE"
PHASE_ID=""
EVENT_ID=""
LOOKUP_PHASE_ID=""
ADD_PHASE_ID=""
ADD_ISSUE_KEY=""
INIT_EPIC=""
INIT_SYSTEM=""
INIT_URL=""
INIT_RUN_ID=""
INIT_ARM=""
INIT_FORCE="0"

case "$CMD" in
  get-tracker)
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  get-phase-issue)
    [ $# -ge 1 ] || usage
    LOOKUP_PHASE_ID="$1"; shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  resolve-issue)
    [ $# -ge 1 ] || usage
    EVENT_ID="$1"; shift
    while [ $# -gt 0 ]; do
      case "$1" in
        --phase) PHASE_ID="${2:?--phase requires a value}"; shift 2 ;;
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  add-phase-task)
    [ $# -ge 2 ] || usage
    ADD_PHASE_ID="$1"; ADD_ISSUE_KEY="$2"; shift 2
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  init-tracker)
    while [ $# -gt 0 ]; do
      case "$1" in
        --epic) INIT_EPIC="${2:?--epic requires a value}"; shift 2 ;;
        --system) INIT_SYSTEM="${2:?--system requires a value}"; shift 2 ;;
        --url) INIT_URL="${2:?--url requires a value}"; shift 2 ;;
        --run-id) INIT_RUN_ID="${2:?--run-id requires a value}"; shift 2 ;;
        --arm) INIT_ARM="${2:?--arm requires a value}"; shift 2 ;;
        --force) INIT_FORCE="1"; shift ;;
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  validate|dump)
    while [ $# -gt 0 ]; do
      case "$1" in
        --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    ;;

  *)
    usage
    ;;
esac

CMD="$CMD" STATE_FILE="$STATE_FILE" EVENT_ID="$EVENT_ID" PHASE_ID="$PHASE_ID" \
LOOKUP_PHASE_ID="$LOOKUP_PHASE_ID" ADD_PHASE_ID="$ADD_PHASE_ID" ADD_ISSUE_KEY="$ADD_ISSUE_KEY" \
INIT_EPIC="$INIT_EPIC" INIT_SYSTEM="$INIT_SYSTEM" INIT_URL="$INIT_URL" \
INIT_RUN_ID="$INIT_RUN_ID" INIT_ARM="$INIT_ARM" INIT_FORCE="$INIT_FORCE" \
python3 - <<'PY'
import json
import os
import re
import sys

STATE_FILE = os.environ["STATE_FILE"]
CMD = os.environ["CMD"]

REQUIRED_TRACKER_FIELDS = ["epic", "system", "run_id", "arm", "url"]
OPTIONAL_TRACKER_FIELDS = ["issue"]
SUPPORTED_SYSTEMS = {"jira"}

# DATA-CONTRACTS.md rule 7 — event routing vocabulary, carried in-code.
EPIC_ROUTED_EVENTS = {"intake_started", "discuss_complete"}
PHASE_ROUTED_EVENTS = {
    "plan_complete", "plan_revised", "execute_started", "execute_wave",
    "execute_complete", "verify_complete", "review_complete",
    "learning_stored", "settled", "reopened",
}

TRACKER_HEADING = re.compile(r"^##\s+Tracker\s*$")
PHASE_TASKS_HEADING = re.compile(r"^##\s+Phase tasks\s*$")
ANY_HEADING = re.compile(r"^##\s+")
KV_LINE = re.compile(r"^-\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*(.*)$")
TABLE_ROW = re.compile(r"^\|(.+)\|\s*$")
TABLE_SEPARATOR = re.compile(r"^\|[\s:|-]+\|\s*$")


def parse_state(path):
    """Structural parse only — no field-level enforcement here, that's validate()'s job."""
    result = {
        "found": False,
        "tracker_sections_found": 0,
        "tracker": {},
        "phase_tasks_table_present": False,
        "phase_tasks": [],
        "parse_errors": [],
    }
    if not os.path.isfile(path):
        result["parse_errors"].append(f"STATE.md not found at {path}")
        return result
    result["found"] = True

    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]

    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if TRACKER_HEADING.match(line):
            result["tracker_sections_found"] += 1
            i += 1
            tracker = {}
            while i < n and not ANY_HEADING.match(lines[i]):
                m = KV_LINE.match(lines[i])
                if m:
                    tracker[m.group(1)] = m.group(2).strip()
                i += 1
            if not result["tracker"]:
                result["tracker"] = tracker
            continue
        if PHASE_TASKS_HEADING.match(line):
            i += 1
            rows = []
            saw_table = False
            while i < n and not ANY_HEADING.match(lines[i]):
                row_line = lines[i]
                if TABLE_ROW.match(row_line) and not TABLE_SEPARATOR.match(row_line):
                    cells = [c.strip() for c in row_line.strip().strip("|").split("|")]
                    if cells and cells[0].lower() != "phase_id":
                        saw_table = True
                        phase_id = cells[0] if len(cells) > 0 else ""
                        issue_key = cells[1] if len(cells) > 1 else ""
                        rows.append({"phase_id": phase_id, "issue_key": issue_key})
                    elif cells and cells[0].lower() == "phase_id":
                        saw_table = True
                i += 1
            if saw_table:
                result["phase_tasks_table_present"] = True
            result["phase_tasks"] = rows
            continue
        i += 1

    return result


def fail(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)


def cmd_get_tracker(state):
    if state["parse_errors"]:
        fail(state["parse_errors"][0])
    if state["tracker_sections_found"] == 0:
        fail(f"no '## Tracker' section found in {STATE_FILE}")
    print(json.dumps(state["tracker"]))


def cmd_get_phase_issue(state):
    lookup = os.environ["LOOKUP_PHASE_ID"]
    if state["parse_errors"]:
        fail(state["parse_errors"][0])
    for row in state["phase_tasks"]:
        if row["phase_id"] == lookup:
            if not row["issue_key"]:
                fail(f"phase_id '{lookup}' has an empty issue_key in {STATE_FILE}")
            print(row["issue_key"])
            return
    fail(f"phase_id '{lookup}' not found in '## Phase tasks' table in {STATE_FILE}")


def cmd_resolve_issue(state):
    event_id = os.environ["EVENT_ID"]
    phase_id = os.environ["PHASE_ID"]
    if state["parse_errors"]:
        fail(state["parse_errors"][0])

    if event_id in EPIC_ROUTED_EVENTS:
        epic = state["tracker"].get("epic", "")
        if not epic:
            fail(f"event_id '{event_id}' is epic-routed but tracker.epic is missing/empty in {STATE_FILE}")
        print(epic)
        return

    if event_id in PHASE_ROUTED_EVENTS:
        if not phase_id:
            fail(f"event_id '{event_id}' is phase-routed and requires --phase N")
        for row in state["phase_tasks"]:
            if row["phase_id"] == phase_id:
                if not row["issue_key"]:
                    fail(f"phase_id '{phase_id}' has an empty issue_key in {STATE_FILE}")
                print(row["issue_key"])
                return
        fail(
            f"unresolved phase-routed event: phase_id '{phase_id}' for event_id "
            f"'{event_id}' has no matching row in '## Phase tasks' in {STATE_FILE}"
        )

    fail(
        f"unknown event_id '{event_id}' — not in the epic-routed or phase-routed "
        f"vocabulary (see DATA-CONTRACTS.md#state-md rule 7)"
    )


def cmd_add_phase_task(state):
    phase_id = os.environ["ADD_PHASE_ID"]
    issue_key = os.environ["ADD_ISSUE_KEY"]
    if not phase_id:
        fail("add-phase-task requires a non-empty phase_id")
    if not issue_key:
        fail("add-phase-task requires a non-empty issue_key")
    if state["parse_errors"]:
        fail(state["parse_errors"][0])
    if state["tracker_sections_found"] == 0:
        fail(
            f"no '## Tracker' section found in {STATE_FILE} — cannot add a phase "
            "task before the tracker section exists"
        )

    for row in state["phase_tasks"]:
        if row["phase_id"] == phase_id:
            fail(
                f"phase_id '{phase_id}' already has issue_key '{row['issue_key']}' in "
                "'## Phase tasks' — refusing to overwrite (idempotency); remove the "
                "row manually first if this is an intentional correction"
            )

    with open(STATE_FILE) as f:
        text = f.read()
    lines = text.split("\n")
    n = len(lines)
    new_row = f"| {phase_id} | {issue_key} |"

    phase_heading_idx = next(
        (idx for idx, ln in enumerate(lines) if PHASE_TASKS_HEADING.match(ln)), None
    )

    if phase_heading_idx is not None:
        # Section exists — insert after the last table-shaped line inside it
        # (header/separator/rows all match TABLE_ROW), so a header-only table
        # gets its first row placed correctly instead of ahead of the header.
        last_table_line_idx = None
        i = phase_heading_idx + 1
        while i < n and not ANY_HEADING.match(lines[i]):
            if TABLE_ROW.match(lines[i]):
                last_table_line_idx = i
            i += 1
        if last_table_line_idx is not None:
            insert_at = last_table_line_idx + 1
            new_lines = lines[:insert_at] + [new_row] + lines[insert_at:]
        else:
            insert_at = phase_heading_idx + 1
            block = ["| phase_id | issue_key |", "|----------|-----------|", new_row]
            new_lines = lines[:insert_at] + block + lines[insert_at:]
    else:
        # No '## Phase tasks' section at all — create it right after '##
        # Tracker' (DATA-CONTRACTS.md's required section order), not blindly
        # at EOF, so files with trailing content stay well-formed.
        tracker_heading_idx = next(
            (idx for idx, ln in enumerate(lines) if TRACKER_HEADING.match(ln)), None
        )
        if tracker_heading_idx is None:
            fail(f"no '## Tracker' section found in {STATE_FILE}")
        i = tracker_heading_idx + 1
        while i < n and not ANY_HEADING.match(lines[i]):
            i += 1
        insert_at = i
        already_blank = insert_at > 0 and lines[insert_at - 1] == ""
        section_lines = (["" ] if not already_blank else []) + [
            "## Phase tasks", "| phase_id | issue_key |", "|----------|-----------|", new_row,
        ]
        new_lines = lines[:insert_at] + section_lines + lines[insert_at:]

    with open(STATE_FILE, "w") as f:
        f.write("\n".join(new_lines))

    print(f"Added phase_id '{phase_id}' -> '{issue_key}' to '## Phase tasks' in {STATE_FILE}")


TRACKER_FIELD_ORDER = ["epic", "system", "url", "run_id", "arm"]


def cmd_init_tracker(state):
    new_fields = {
        "epic": os.environ["INIT_EPIC"],
        "system": os.environ["INIT_SYSTEM"],
        "url": os.environ["INIT_URL"],
        "run_id": os.environ["INIT_RUN_ID"],
        "arm": os.environ["INIT_ARM"],
    }
    force = os.environ["INIT_FORCE"] == "1"

    for field in TRACKER_FIELD_ORDER:
        if not new_fields[field]:
            fail(f"init-tracker requires a non-empty --{field.replace('_', '-')}")

    # Unlike every other subcommand, a missing STATE.md is init-tracker's own
    # "create fresh" case, not an error -- so parse_errors (which only ever
    # holds the "not found" message) is deliberately not checked here.
    tracker_block = ["## Tracker"] + [f"- {k}: {new_fields[k]}" for k in TRACKER_FIELD_ORDER]

    if not state["found"]:
        os.makedirs(os.path.dirname(STATE_FILE) or ".", exist_ok=True)
        lines = tracker_block + ["", "## Phase tasks", "| phase_id | issue_key |", "|----------|-----------|"]
        with open(STATE_FILE, "w") as f:
            f.write("\n".join(lines) + "\n")
        print(
            f"Created {STATE_FILE} with a new '## Tracker' section (epic '{new_fields['epic']}') "
            "and an empty '## Phase tasks' section."
        )
        return

    with open(STATE_FILE) as f:
        lines = f.read().split("\n")

    if state["tracker_sections_found"] == 0:
        # No '## Tracker' at all yet -- insert right before '## Phase tasks'
        # (required section order) if that section exists, else at the top of
        # the file, and leave every other line byte-for-byte untouched.
        phase_idx = next((i for i, ln in enumerate(lines) if PHASE_TASKS_HEADING.match(ln)), None)
        block = tracker_block + [""]
        new_lines = (lines[:phase_idx] + block + lines[phase_idx:]) if phase_idx is not None else (block + lines)
        with open(STATE_FILE, "w") as f:
            f.write("\n".join(new_lines))
        print(f"Inserted a new '## Tracker' section (epic '{new_fields['epic']}') into {STATE_FILE}.")
        return

    existing = state["tracker"]
    existing_epic = existing.get("epic", "")

    if existing_epic:
        if all(existing.get(k, "") == new_fields[k] for k in TRACKER_FIELD_ORDER):
            print(f"'## Tracker' in {STATE_FILE} already has epic '{new_fields['epic']}' with matching fields -- no-op.")
            return
        if not force:
            fail(
                f"'## Tracker' in {STATE_FILE} is already linked to epic '{existing_epic}' with "
                f"different field(s) than requested for epic '{new_fields['epic']}' -- pass --force "
                "if you really mean to relink it"
            )

    # Either the epic slot was empty (nothing to conflict with -- treat as a
    # fill-in, no --force needed) or --force was passed for a genuine
    # conflict. Either way: replace only the '## Tracker' block's own lines,
    # leaving '## Phase tasks' and everything else untouched.
    tracker_idx = next(i for i, ln in enumerate(lines) if TRACKER_HEADING.match(ln))
    end_idx = tracker_idx + 1
    n = len(lines)
    while end_idx < n and not ANY_HEADING.match(lines[end_idx]):
        end_idx += 1
    # Preserve any blank separator line(s) immediately before the next
    # heading (or EOF) -- only the '- key: value' lines themselves get
    # replaced, so the file's existing spacing/formatting survives intact.
    keep_from = end_idx
    while keep_from > tracker_idx + 1 and lines[keep_from - 1] == "":
        keep_from -= 1
    new_lines = lines[:tracker_idx] + tracker_block + lines[keep_from:]
    with open(STATE_FILE, "w") as f:
        f.write("\n".join(new_lines))

    if existing_epic:
        print(f"Overwrote '## Tracker' in {STATE_FILE}: epic '{existing_epic}' -> '{new_fields['epic']}' (--force).")
    else:
        print(f"Filled in the empty '## Tracker' section in {STATE_FILE} with epic '{new_fields['epic']}'.")


def cmd_validate(state):
    errors = list(state["parse_errors"])

    if not errors:
        if state["tracker_sections_found"] == 0:
            errors.append("no '## Tracker' section found (required exactly once)")
        else:
            if state["tracker_sections_found"] > 1:
                errors.append(
                    f"'## Tracker' section appears {state['tracker_sections_found']} times "
                    "(required exactly once)"
                )

            tracker = state["tracker"]
            for field in REQUIRED_TRACKER_FIELDS:
                if not tracker.get(field):
                    errors.append(f"'## Tracker' is missing required field '{field}'")

            system = tracker.get("system", "")
            if system and system not in SUPPORTED_SYSTEMS:
                errors.append(
                    f"'## Tracker' system '{system}' is not supported in v1 "
                    f"(supported: {', '.join(sorted(SUPPORTED_SYSTEMS))})"
                )

        seen_phase_ids = {}
        for idx, row in enumerate(state["phase_tasks"]):
            pid = row["phase_id"]
            if pid in seen_phase_ids:
                errors.append(
                    f"duplicate phase_id '{pid}' in '## Phase tasks' "
                    f"(rows {seen_phase_ids[pid]} and {idx})"
                )
            else:
                seen_phase_ids[pid] = idx
            if not row["issue_key"]:
                errors.append(f"phase_id '{pid}' has an empty issue_key in '## Phase tasks'")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print("OK")


def cmd_dump(state):
    if state["parse_errors"]:
        fail(state["parse_errors"][0])
    print(json.dumps({
        "tracker": state["tracker"],
        "phase_tasks": state["phase_tasks"],
    }, indent=2))


state = parse_state(STATE_FILE)

dispatch = {
    "get-tracker": cmd_get_tracker,
    "get-phase-issue": cmd_get_phase_issue,
    "resolve-issue": cmd_resolve_issue,
    "add-phase-task": cmd_add_phase_task,
    "init-tracker": cmd_init_tracker,
    "validate": cmd_validate,
    "dump": cmd_dump,
}
dispatch[CMD](state)
PY
