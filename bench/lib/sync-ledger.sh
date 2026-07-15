#!/usr/bin/env bash
# Idempotent sync ledger for GSD recipe Jira/GitHub milestone comments.
#
# Contract (carried in-code — no separate spec doc):
#   Ledger file : .gsd-recipe/sync-ledger.jsonl (JSON Lines, append-only)
#   Key format  : gsd-recipe:{event_id}:phase={N}:wave={W}:commit={SHA}:issue={ISSUE_KEY}
#                 (phase/wave/commit segments omitted when not applicable, e.g. epic-routed events)
#   Record      : {"key","ts","target","external_id"?,"result"?,"detail"?}
#     target : jira | github
#     result : posted | duplicate_skipped
#
# Usage:
#   sync-ledger.sh key <event_id> <issue_key> [--phase N] [--wave W] [--commit SHA]
#   sync-ledger.sh has <key> [--ledger PATH]
#   sync-ledger.sh append <key> <target> [--external-id ID] [--result posted|duplicate_skipped] [--detail TEXT] [--ledger PATH]
#
# Examples:
#   KEY=$(bench/lib/sync-ledger.sh key plan_complete PROJ-101 --phase 1)
#   if bench/lib/sync-ledger.sh has "$KEY"; then
#     echo "duplicate_skipped"
#   else
#     # ... post comment to Jira/GitHub ...
#     bench/lib/sync-ledger.sh append "$KEY" jira --external-id jira-comment-123 --result posted
#   fi
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DEFAULT_LEDGER="$REPO_ROOT/.gsd-recipe/sync-ledger.jsonl"

usage() {
  cat >&2 <<'EOF'
Usage:
  sync-ledger.sh key <event_id> <issue_key> [--phase N] [--wave W] [--commit SHA]
  sync-ledger.sh has <key> [--ledger PATH]
  sync-ledger.sh append <key> <target> [--external-id ID] [--result posted|duplicate_skipped] [--detail TEXT] [--ledger PATH]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  key)
    [ $# -ge 2 ] || usage
    EVENT_ID="$1"; ISSUE_KEY="$2"; shift 2
    PHASE=""; WAVE=""; COMMIT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --phase) PHASE="${2:?--phase requires a value}"; shift 2 ;;
        --wave) WAVE="${2:?--wave requires a value}"; shift 2 ;;
        --commit) COMMIT="${2:?--commit requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    KEY="gsd-recipe:${EVENT_ID}"
    [ -n "$PHASE" ] && KEY="${KEY}:phase=${PHASE}"
    [ -n "$WAVE" ] && KEY="${KEY}:wave=${WAVE}"
    [ -n "$COMMIT" ] && KEY="${KEY}:commit=${COMMIT}"
    KEY="${KEY}:issue=${ISSUE_KEY}"
    echo "$KEY"
    ;;

  has)
    [ $# -ge 1 ] || usage
    LOOKUP_KEY="$1"; shift
    LEDGER="$DEFAULT_LEDGER"
    while [ $# -gt 0 ]; do
      case "$1" in
        --ledger) LEDGER="${2:?--ledger requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    if [ ! -f "$LEDGER" ]; then
      exit 1
    fi
    LOOKUP_KEY="$LOOKUP_KEY" LEDGER="$LEDGER" python3 - <<'PY'
import json, os, sys

key = os.environ["LOOKUP_KEY"]
path = os.environ["LEDGER"]
found = False
with open(path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError:
            continue
        if rec.get("key") == key:
            found = True
            break
sys.exit(0 if found else 1)
PY
    ;;

  append)
    [ $# -ge 2 ] || usage
    APPEND_KEY="$1"; TARGET="$2"; shift 2
    EXTERNAL_ID=""; RESULT="posted"; DETAIL=""; LEDGER="$DEFAULT_LEDGER"
    while [ $# -gt 0 ]; do
      case "$1" in
        --external-id) EXTERNAL_ID="${2:?--external-id requires a value}"; shift 2 ;;
        --result) RESULT="${2:?--result requires a value}"; shift 2 ;;
        --detail) DETAIL="${2:?--detail requires a value}"; shift 2 ;;
        --ledger) LEDGER="${2:?--ledger requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    case "$TARGET" in
      jira|github) ;;
      *) echo "ERROR: target must be 'jira' or 'github', got '$TARGET'" >&2; exit 2 ;;
    esac
    case "$RESULT" in
      posted|duplicate_skipped) ;;
      *) echo "ERROR: result must be 'posted' or 'duplicate_skipped', got '$RESULT'" >&2; exit 2 ;;
    esac
    mkdir -p "$(dirname "$LEDGER")"
    APPEND_KEY="$APPEND_KEY" TARGET="$TARGET" EXTERNAL_ID="$EXTERNAL_ID" \
    RESULT="$RESULT" DETAIL="$DETAIL" LEDGER="$LEDGER" python3 - <<'PY'
import json, os
from datetime import datetime, timezone

rec = {
    "key": os.environ["APPEND_KEY"],
    "ts": datetime.now(timezone.utc).isoformat(),
    "target": os.environ["TARGET"],
}
if os.environ.get("EXTERNAL_ID"):
    rec["external_id"] = os.environ["EXTERNAL_ID"]
if os.environ.get("RESULT"):
    rec["result"] = os.environ["RESULT"]
if os.environ.get("DETAIL"):
    rec["detail"] = os.environ["DETAIL"]

with open(os.environ["LEDGER"], "a") as f:
    f.write(json.dumps(rec) + "\n")

print(f"Ledgered {rec['key']} -> {rec['target']} ({rec['result']})")
PY
    ;;

  *)
    usage
    ;;
esac
