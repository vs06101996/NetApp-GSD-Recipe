#!/usr/bin/env bash
# tracker-sync config accessor (TASK-014, narrowed scope — see
# bench/report/tracker-sync-integration-report.md for the scope decision).
#
# Reads/writes the `tracker` field of .gsd-recipe/config.json, the single
# piece of state the tracker-sync skill dispatches on. Locked to the v1 set
# from DECISIONS.md ("Platforms | Jira + GitHub") — NOT the wider
# jira|github_issues|linear placeholder list INSTALL-LLD.md's {TRACKER} table
# uses as illustrative examples; only jira/github are real, buildable options
# today, so `set-tracker` fails closed on anything else rather than silently
# accepting a value nothing can actually act on.
#
# Contract (carried in-code, same convention as sync-ledger.sh):
#   Config file : .gsd-recipe/config.json (JSON object, may hold other keys —
#                 this script only ever touches the "tracker" key)
#   Value       : "jira" | "github"
#   Default     : "jira" when the file or key is absent (the only tracker with
#                 a fully working draft/post/ledger/drain path today)
#
# Usage:
#   tracker-sync-config.sh get-tracker [--config PATH]
#   tracker-sync-config.sh set-tracker <jira|github> [--config PATH]
#
# Examples:
#   bench/lib/tracker-sync-config.sh get-tracker
#   bench/lib/tracker-sync-config.sh set-tracker github --config .gsd-recipe/config.json
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DEFAULT_CONFIG="$REPO_ROOT/.gsd-recipe/config.json"
VALID_TRACKERS="jira github"

usage() {
  cat >&2 <<'EOF'
Usage:
  tracker-sync-config.sh get-tracker [--config PATH]
  tracker-sync-config.sh set-tracker <jira|github> [--config PATH]
EOF
  exit 2
}

is_valid_tracker() {
  case " $VALID_TRACKERS " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  get-tracker)
    CONFIG="$DEFAULT_CONFIG"
    while [ $# -gt 0 ]; do
      case "$1" in
        --config) CONFIG="${2:?--config requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    if [ ! -f "$CONFIG" ]; then
      echo "jira"
      exit 0
    fi
    CONFIG="$CONFIG" python3 - <<'PY'
import json, os, sys

path = os.environ["CONFIG"]
try:
    with open(path) as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    sys.exit(f"ERROR: {path} is not valid JSON: {e}")

tracker = data.get("tracker", "jira")
valid = ["jira", "github"]
if tracker not in valid:
    sys.exit(f"ERROR: {path} has unsupported tracker '{tracker}' (valid: {', '.join(valid)})")
print(tracker)
PY
    ;;

  set-tracker)
    [ $# -ge 1 ] || usage
    VALUE="$1"; shift
    CONFIG="$DEFAULT_CONFIG"
    while [ $# -gt 0 ]; do
      case "$1" in
        --config) CONFIG="${2:?--config requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    is_valid_tracker "$VALUE" || {
      echo "ERROR: tracker must be one of: $VALID_TRACKERS (got '$VALUE')" >&2
      exit 2
    }
    mkdir -p "$(dirname "$CONFIG")"
    CONFIG="$CONFIG" VALUE="$VALUE" python3 - <<'PY'
import json, os

path = os.environ["CONFIG"]
value = os.environ["VALUE"]

data = {}
if os.path.isfile(path):
    with open(path) as f:
        content = f.read().strip()
        if content:
            data = json.loads(content)

data["tracker"] = value
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"tracker set to '{value}' in {path}")
PY
    ;;

  *)
    usage
    ;;
esac
