#!/usr/bin/env bash
# Regression test for bench/runners/sync-drain-queue.sh (TASK-005).
# Run: ./bench/tests/test-sync-drain-queue.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRAIN="$REPO_ROOT/bench/runners/sync-drain-queue.sh"
LEDGER_LIB="$REPO_ROOT/bench/lib/sync-ledger.sh"

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

SCRATCH="$(mktemp -d)"
# emit-stamp.sh resolves its own BENCH_ROOT from $0, not from REPO_ROOT/env --
# it always writes under the real repo's results/, never a scratch dir. Use a
# dedicated run_id so this test can't collide with real stamp data, and clean
# it up alongside the scratch dir.
STAMP_RUN_ID="drain-test-run-$$"
cleanup() {
  rm -rf "$SCRATCH"
  rm -rf "$REPO_ROOT/results/recipe/$STAMP_RUN_ID"
}
trap cleanup EXIT

QUEUE="$SCRATCH/queue.jsonl"
LEDGER="$SCRATCH/ledger.jsonl"
STAMPS_FILE="$REPO_ROOT/results/recipe/$STAMP_RUN_ID/stamps.jsonl"

write_queue() {
  # Overwrites $QUEUE with the given JSON lines (one per arg).
  : > "$QUEUE"
  for line in "$@"; do
    echo "$line" >> "$QUEUE"
  done
}

drain() {
  "$DRAIN" "$@" --queue "$QUEUE" --ledger "$LEDGER"
}

# --- 1. list on a nonexistent queue file is empty, not an error -------------
rm -f "$QUEUE"
OUT1="$("$DRAIN" list --queue "$QUEUE" --ledger "$LEDGER")"
echo "$OUT1" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d == {'work': [], 'self_healed': [], 'errors': []}, d
"
check "list on missing queue file returns empty work/self_healed/errors" "$?"

# --- 2. Seed a real queue via a scratch GSD repo + sync-reconcile.sh, then list ---
GSD_SCRATCH="$(mktemp -d)"
git init -q "$GSD_SCRATCH"
git -C "$GSD_SCRATCH" config user.email "test@example.com"
git -C "$GSD_SCRATCH" config user.name "Test"
mkdir -p "$GSD_SCRATCH/.planning/phases/01-auth"
cat > "$GSD_SCRATCH/.planning/STATE.md" <<'EOF'
## Tracker
- epic: PROJ-100
- issue: PROJ-100
- system: jira
- url: https://example.atlassian.net/browse/PROJ-100
- run_id: drain-test-01
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-101 |
EOF
cat > "$GSD_SCRATCH/.planning/phases/01-auth/01-01-PLAN.md" <<'EOF'
---
phase_id: 01-auth
depends_on: []
touches:
  - src/auth/**
---
# plan
EOF
git -C "$GSD_SCRATCH" add -A && git -C "$GSD_SCRATCH" commit -q -m init

REPO_ROOT="$GSD_SCRATCH" "$REPO_ROOT/bench/runners/sync-reconcile.sh" --run drain-test-01 \
  --queue "$QUEUE" --ledger "$SCRATCH/reconcile-ledger.jsonl" \
  --checkpoint "$SCRATCH/checkpoint.json" >/dev/null

[ -f "$QUEUE" ] && [ "$(wc -l < "$QUEUE" | tr -d ' ')" = "2" ]
check "seed: sync-reconcile.sh queues intake_started + plan_complete" "$?"

OUT2="$(drain list)"
echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
keys = sorted(w['key'] for w in d['work'])
assert keys == [
    'gsd-recipe:intake_started:issue=PROJ-100',
    'gsd-recipe:plan_complete:phase=1:issue=PROJ-101',
], keys
for w in d['work']:
    assert w['body'].strip(), w
    assert w['target'] == 'jira', w
assert d['self_healed'] == [] and d['errors'] == []
"
check "list re-drafts both pending rows with non-empty bodies" "$?"
rm -rf "$GSD_SCRATCH"

# --- 3. mark-done requires --external-id -------------------------------------
KEY1="gsd-recipe:intake_started:issue=PROJ-100"
if drain mark-done "$KEY1" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "mark-done without --external-id fails" "$rc"

# --- 4. mark-done on an unknown key fails ------------------------------------
if drain mark-done "gsd-recipe:no_such_key:issue=ZZZ-1" --external-id x >/dev/null 2>&1; then rc=1; else rc=0; fi
check "mark-done on a key with no matching queue row fails" "$rc"

# --- 5. mark-done happy path: ledger + queue + stamp -------------------------
"$DRAIN" mark-done "$KEY1" --external-id "jira-comment-1" --run "$STAMP_RUN_ID" \
  --queue "$QUEUE" --ledger "$LEDGER" >/dev/null

"$LEDGER_LIB" has "$KEY1" --ledger "$LEDGER"
check "mark-done appends to ledger" "$?"

python3 -c "
import json
rec = next(json.loads(l) for l in open('$LEDGER') if json.loads(l).get('key') == '$KEY1')
assert rec['result'] == 'posted', rec
assert rec['external_id'] == 'jira-comment-1', rec
"
check "ledger entry has result=posted and external_id" "$?"

python3 -c "
import json
row = next(json.loads(l) for l in open('$QUEUE') if json.loads(l).get('key') == '$KEY1')
assert row['status'] == 'done', row
assert row['result'] == 'posted', row
assert row['external_id'] == 'jira-comment-1', row
assert 'error' not in row, row
"
check "queue row for drained key flips to done with result/external_id, no error" "$?"

[ -f "$STAMPS_FILE" ]
check "stamp file created (intake_started has a stamp configured)" "$?"

python3 -c "
import json
rec = json.loads(open('$STAMPS_FILE').read().strip().splitlines()[0])
assert rec['step'] == 'intake' and rec['status'] == 'started', rec
assert rec['tracker'] == {'system': 'jira', 'issue_key': 'PROJ-100'}, rec
assert rec['run_id'] == '$STAMP_RUN_ID' and rec['arm'] == 'recipe', rec
"
check "stamp matches jira-events.json's intake_started stamp config (intake/started)" "$?"

# --- 6. mark-done on an already-done row fails -------------------------------
if drain mark-done "$KEY1" --external-id "jira-comment-2" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "mark-done on an already-done row fails (no double-post)" "$rc"

# --- 7. mark-failed happy path + list retries it -----------------------------
KEY2="gsd-recipe:plan_complete:phase=1:issue=PROJ-101"
drain mark-failed "$KEY2" --error "MCP auth expired" >/dev/null

python3 -c "
import json
row = next(json.loads(l) for l in open('$QUEUE') if json.loads(l).get('key') == '$KEY2')
assert row['status'] == 'failed', row
assert row['error'] == 'MCP auth expired', row
"
check "mark-failed sets status=failed with error message" "$?"

OUT7="$(drain list)"
echo "$OUT7" | python3 -c "
import json, sys
d = json.load(sys.stdin)
keys = [w['key'] for w in d['work']]
assert keys == ['$KEY2'], keys
"
check "list retries a failed row on the next run (only the failed one, not the done one)" "$?"

# --- 8. mark-failed requires --error -----------------------------------------
if drain mark-failed "$KEY2" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "mark-failed without --error fails" "$rc"

# --- 9. Self-healing: something else posts out-of-band, list dedupes --------
"$LEDGER_LIB" append "$KEY2" jira --result posted --ledger "$LEDGER" >/dev/null

OUT9="$(drain list)"
echo "$OUT9" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['work'] == [], d['work']
assert [h['key'] for h in d['self_healed']] == ['$KEY2'], d['self_healed']
"
check "list self-heals a row whose key is already ledgered out-of-band" "$?"

python3 -c "
import json
row = next(json.loads(l) for l in open('$QUEUE') if json.loads(l).get('key') == '$KEY2')
assert row['status'] == 'done', row
assert row['result'] == 'duplicate_skipped', row
assert 'error' not in row, row
"
check "self-healed row flips to done/duplicate_skipped and drops its error field" "$?"

# --- 10. Unsupported target (github, pre-TASK-006) surfaces as an error, not silently dropped ---
write_queue \
  '{"queued_at":"2026-07-08T00:00:00Z","event_id":"execute_wave","issue_key":"PROJ-101","target":"github","template":"_comment.template.md","key":"gsd-recipe:execute_wave:phase=1:wave=1:issue=PROJ-101","status":"queued","phase_id":"1"}'
: > "$LEDGER"

OUT10="$(drain list)" && rc=0 || rc=1
echo "$OUT10" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['work'] == [], d
assert len(d['errors']) == 1 and 'github' in d['errors'][0]['error'], d
"
check "list surfaces a github-target row as an error (target not yet supported) instead of posting or dropping it" "$?"
[ "$rc" = "1" ]
check "list exits non-zero when any row errors" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
