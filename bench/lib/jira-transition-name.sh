#!/usr/bin/env bash
# jira-transition-name.sh — print the required Jira status name for a GSD
# event_id from jira-events.json (TASK: required transitions, not comments-only).
#
# Usage:
#   bench/lib/jira-transition-name.sh <event_id> [--catalog PATH]
#
# Prints the transition/status name, or empty if the event has no transition.
# Strips a legacy "optional: " prefix so old catalogs still work.
# Exit 0 even when empty (callers treat blank as skip). Unknown event_id → exit 2.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CATALOG="$REPO_ROOT/bench/recipe/trackers/jira-events.json"
EVENT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --catalog) CATALOG="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 <event_id> [--catalog PATH]"
      exit 0
      ;;
    *)
      if [ -z "$EVENT" ]; then EVENT="$1"; shift
      else echo "Unknown argument: $1" >&2; exit 2
      fi
      ;;
  esac
done

if [ -z "$EVENT" ]; then
  echo "Usage: $0 <event_id> [--catalog PATH]" >&2
  exit 2
fi

python3 - "$CATALOG" "$EVENT" <<'PY'
import json, sys
path, event_id = sys.argv[1], sys.argv[2]
with open(path) as f:
    data = json.load(f)
found = None
for ev in data.get("events", []):
    if ev.get("id") == event_id:
        found = ev
        break
if found is None:
    sys.stderr.write(f"jira-transition-name: unknown event_id {event_id!r}\n")
    sys.exit(2)
raw = (found.get("jira") or {}).get("transition")
if not raw:
    sys.exit(0)
name = str(raw)
if name.lower().startswith("optional:"):
    name = name.split(":", 1)[1].strip()
print(name)
PY
