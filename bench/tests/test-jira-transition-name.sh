#!/usr/bin/env bash
# Tests for jira-events.json required transitions + jira-transition-name.sh
# Run: ./bench/tests/test-jira-transition-name.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$REPO_ROOT/bench/lib/jira-transition-name.sh"
CATALOG="$REPO_ROOT/bench/recipe/trackers/jira-events.json"
REF="$REPO_ROOT/docs/netapp-recipe/reference/harness/recipe/trackers/jira-events.json"

pass=0
fail=0
check() {
  local desc="$1"; local result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $desc"
    pass=$((pass + 1))
  else
    echo "FAIL - $desc"
    fail=$((fail + 1))
  fi
}

diff -q "$CATALOG" "$REF" >/dev/null && rc=0 || rc=$?
check "bench and reference jira-events.json stay in sync" "$rc"

python3 - "$CATALOG" <<'PY'
import json, sys
p = sys.argv[1]
data = json.load(open(p))
for ev in data["events"]:
    t = (ev.get("jira") or {}).get("transition")
    if t is None:
        continue
    assert isinstance(t, str) and t.strip(), ev
    assert not t.lower().startswith("optional:"), ev
PY
check "named transitions are required strings (no optional: prefix)" "$?"

[ "$("$HELPER" plan_complete)" = "In Progress" ]
check "plan_complete → In Progress" "$?"
[ "$("$HELPER" review_complete)" = "In Review" ]
check "review_complete → In Review" "$?"
[ "$("$HELPER" settled)" = "Done" ]
check "settled → Done" "$?"
[ "$("$HELPER" intake_started)" = "To Do" ]
check "intake_started → To Do" "$?"
out="$("$HELPER" execute_wave)"
[ -z "$out" ]
check "execute_wave has no transition" "$?"

"$HELPER" not_a_real_event >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "unknown event_id exits non-zero" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
