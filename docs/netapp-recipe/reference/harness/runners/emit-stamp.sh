#!/usr/bin/env bash
# Append one immutable SDLC stage stamp (JSONL) for any arm.
#
# Usage:
#   emit-stamp.sh <arm> <run_id> <status> <step> [issue_key] [actor] [tracker_system]
#
# Examples:
#   # vanilla GSD, no tracker, agent advanced the stage
#   emit-stamp.sh gsd run-01 started build agent
#   # recipe arm linked to a Jira issue, human approved
#   emit-stamp.sh recipe run-01 approved review PROJ-123 human jira
#
# arm     : baseline | gsd | recipe
# status  : started | prd-approved | engineering-ready | build-started |
#           build-done | review-ready | approved | settled | reopened | kb-updated
# step    : intake | prd | prd-to-stories | story-to-tasks | design | tests | build | review
# issue_key (optional): tracker id; omit for arms with no live tracker
# actor     (optional): human | agent  (default: agent)
# tracker_system (optional): jira | github | none (default: jira if issue_key set, else none)
set -euo pipefail

ARM="${1:?arm required: baseline|gsd|recipe}"
RUN_ID="${2:?run_id required, e.g. run-01}"
STATUS="${3:?status required}"
STEP="${4:?step required}"
ISSUE_KEY="${5:-}"
ACTOR="${6:-agent}"
TRACKER_SYS="${7:-}"

valid_arm="baseline gsd recipe"
valid_status="started prd-approved engineering-ready build-started build-done review-ready approved settled reopened kb-updated"
valid_actor="human agent"

contains() { case " $1 " in *" $2 "*) return 0;; *) return 1;; esac; }

contains "$valid_arm" "$ARM"       || { echo "ERROR: invalid arm '$ARM' (want: $valid_arm)" >&2; exit 2; }
contains "$valid_status" "$STATUS" || { echo "ERROR: invalid status '$STATUS' (want: $valid_status)" >&2; exit 2; }
contains "$valid_actor" "$ACTOR"   || { echo "ERROR: invalid actor '$ACTOR' (want: $valid_actor)" >&2; exit 2; }

if [ -z "$TRACKER_SYS" ]; then
  if [ -n "$ISSUE_KEY" ]; then TRACKER_SYS="jira"; else TRACKER_SYS="none"; fi
fi

BENCH_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
STAMPS="$BENCH_ROOT/results/$ARM/$RUN_ID/stamps.jsonl"
mkdir -p "$(dirname "$STAMPS")"

ARM="$ARM" RUN_ID="$RUN_ID" STATUS="$STATUS" STEP="$STEP" \
ISSUE_KEY="$ISSUE_KEY" ACTOR="$ACTOR" TRACKER_SYS="$TRACKER_SYS" STAMPS="$STAMPS" \
python3 - <<'PY'
import json, os, pathlib, uuid
from datetime import datetime, timezone

stamp = {
    "stamp_id": str(uuid.uuid4()),
    "step": os.environ["STEP"],
    "status": os.environ["STATUS"],
    "at": datetime.now(timezone.utc).isoformat(),
    "arm": os.environ["ARM"],
    "actor": os.environ["ACTOR"],
    "run_id": os.environ["RUN_ID"],
}

issue_key = os.environ.get("ISSUE_KEY", "")
if issue_key:
    stamp["tracker"] = {"system": os.environ["TRACKER_SYS"], "issue_key": issue_key}

path = pathlib.Path(os.environ["STAMPS"])
with path.open("a") as f:
    f.write(json.dumps(stamp) + "\n")

where = stamp.get("tracker", {}).get("issue_key", "(no tracker)")
print(f"Stamped {stamp['arm']}/{stamp['run_id']} {stamp['status']}@{stamp['step']} {where} -> {path}")
PY
