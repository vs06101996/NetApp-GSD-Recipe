#!/usr/bin/env bash
# Regression test for bench/lib/sync-ledger.sh (TASK-001).
# Run: ./bench/tests/test-sync-ledger.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/sync-ledger.sh"
TMP_LEDGER="$(mktemp -d)/sync-ledger.jsonl"

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

# 1. Phase-routed key format
KEY1="$("$LIB" key plan_complete PROJ-101 --phase 1)"
[ "$KEY1" = "gsd-recipe:plan_complete:phase=1:issue=PROJ-101" ]
check "phase-routed key format" "$?"

# 2. Epic-routed key omits phase segment
KEY2="$("$LIB" key settled EPIC-100)"
[ "$KEY2" = "gsd-recipe:settled:issue=EPIC-100" ]
check "epic-routed key omits phase" "$?"

# 3. Wave + commit segments in order
KEY3="$("$LIB" key execute_wave PROJ-101 --phase 1 --wave 2 --commit 7af12cd)"
[ "$KEY3" = "gsd-recipe:execute_wave:phase=1:wave=2:commit=7af12cd:issue=PROJ-101" ]
check "wave+commit key format" "$?"

# 4. has() on empty/missing ledger returns not-found (exit 1)
"$LIB" has "$KEY1" --ledger "$TMP_LEDGER" && rc=0 || rc=$?
[ "$rc" = "1" ]
check "has() on missing ledger returns not-found" "$?"

# 5. append() then has() finds it
"$LIB" append "$KEY1" jira --external-id jira-comment-88421 --result posted --ledger "$TMP_LEDGER" >/dev/null
"$LIB" has "$KEY1" --ledger "$TMP_LEDGER" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "has() finds key after append()" "$?"

# 6. has() does not false-positive on a different key
"$LIB" has "$KEY2" --ledger "$TMP_LEDGER" && rc=0 || rc=$?
[ "$rc" = "1" ]
check "has() does not match unrelated key" "$?"

# 7. Re-running append for the same key is still idempotent from the caller's
#    perspective once combined with has() — verify duplicate_skipped can be recorded
"$LIB" append "$KEY1" jira --result duplicate_skipped --detail "already present in ledger" --ledger "$TMP_LEDGER" >/dev/null
LINE_COUNT="$(wc -l < "$TMP_LEDGER" | tr -d ' ')"
[ "$LINE_COUNT" = "2" ]
check "duplicate_skipped is recorded as a second ledger line (caller-driven idempotency)" "$?"

# 8. append() rejects invalid target
"$LIB" append "$KEY2" slack --ledger "$TMP_LEDGER" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "append() rejects invalid target" "$?"

# 9. append() rejects invalid result
"$LIB" append "$KEY2" jira --result bogus --ledger "$TMP_LEDGER" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "append() rejects invalid result" "$?"

# 10. append() writes a well-formed record matching the documented shape
#     (contract: {"key","ts","target","external_id"?,"result"?,"detail"?})
LEDGER_FILE="$TMP_LEDGER" LOOKUP_KEY="$KEY1" python3 -c "
import json, os
key = os.environ['LOOKUP_KEY']
with open(os.environ['LEDGER_FILE']) as f:
    recs = [json.loads(l) for l in f if l.strip()]
rec = next(r for r in recs if r['key'] == key and r.get('result') == 'posted')
assert rec['ts'], 'ts must be non-empty'
assert rec['target'] == 'jira'
assert rec['external_id'] == 'jira-comment-88421'
"
check "append() writes ts/target/external_id fields matching the documented record shape" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
