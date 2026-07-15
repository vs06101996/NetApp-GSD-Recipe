#!/usr/bin/env bash
# Regression test for bench/runners/sync-reconcile.sh (TASK-003).
# Run: ./bench/tests/test-sync-reconcile.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RECONCILE="$REPO_ROOT/bench/runners/sync-reconcile.sh"
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
trap 'rm -rf "$SCRATCH"' EXIT

git init -q "$SCRATCH"
git -C "$SCRATCH" config user.email "test@example.com"
git -C "$SCRATCH" config user.name "Test"

mkdir -p "$SCRATCH/.planning/phases/01-auth"
cat > "$SCRATCH/.planning/STATE.md" <<'EOF'
## Tracker
- epic: PROJ-100
- issue: PROJ-100
- system: jira
- url: https://example.atlassian.net/browse/PROJ-100
- run_id: recon-test-01
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-101 |
EOF
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -q -m "init"

reconcile() {
  REPO_ROOT="$SCRATCH" "$RECONCILE" --run recon-test-01 "$@"
}

QUEUE="$SCRATCH/.gsd-recipe/sync-queue.jsonl"
CHECKPOINT="$SCRATCH/.gsd-recipe/reconcile-state.json"
LEDGER="$SCRATCH/.gsd-recipe/sync-ledger.jsonl"

# --- 1. dry-run is side-effect-free -----------------------------------------
# STATE.md already exists at this point, so intake_started is a real candidate —
# dry-run must still report it (detection ran) but write nothing to disk.
OUT1="$(REPO_ROOT="$SCRATCH" "$RECONCILE" --dry-run --run recon-test-01)"
echo "$OUT1" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['dry_run'] is True
assert [e['event_id'] for e in d['queued']] == ['intake_started']
" && rc=0 || rc=1
[ ! -e "$QUEUE" ] && [ ! -e "$CHECKPOINT" ] && [ "$rc" = "0" ]
check "dry-run detects intake_started but writes nothing to disk" "$?"

# --- 2. Create CONTEXT.md + PLAN.md, expect intake_started + discuss_complete + plan_complete ---
cat > "$SCRATCH/.planning/phases/01-auth/01-CONTEXT.md" <<'EOF'
# context
EOF
cat > "$SCRATCH/.planning/phases/01-auth/01-01-PLAN.md" <<'EOF'
---
phase_id: 01-auth
depends_on: []
touches:
  - src/auth/**
---
# plan
EOF
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -q -m "phase 1: context + plan"

OUT2="$(reconcile)"
echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
events = sorted(e['event_id'] for e in d['queued'])
assert events == ['discuss_complete', 'intake_started', 'plan_complete'], events
" && rc=0 || rc=1
check "first real run queues intake_started + discuss_complete + plan_complete" "$rc"

[ -f "$QUEUE" ] && [ "$(wc -l < "$QUEUE" | tr -d ' ')" = "3" ]
check "queue file has exactly 3 lines" "$?"

python3 -c "
import json
for line in open('$QUEUE'):
    rec = json.loads(line)
    for field in ('queued_at', 'event_id', 'issue_key', 'target', 'template', 'key', 'status'):
        assert field in rec, (field, rec)
    assert rec['target'] == 'jira'
    assert rec['status'] == 'queued'
" && rc=0 || rc=1
check "queue rows match DATA-CONTRACTS.md sync-queue.jsonl schema" "$rc"

[ -f "$CHECKPOINT" ]
check "checkpoint file written after real run" "$?"

# --- 3. Re-run with unchanged tree: nothing new (checkpoint short-circuits) ---
OUT3="$(reconcile)"
echo "$OUT3" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['queued'] == [] and d['duplicate_skipped'] == [] and d['errors'] == []
" && rc=0 || rc=1
check "re-run on unchanged tree produces no candidates at all (checkpoint dedup)" "$rc"

# --- 4. Simulate drain (mark all 3 posted), reset checkpoint, verify ledger safety net ---
"$LEDGER_LIB" append "gsd-recipe:intake_started:issue=PROJ-100" jira --result posted --ledger "$LEDGER" >/dev/null
"$LEDGER_LIB" append "gsd-recipe:discuss_complete:issue=PROJ-100" jira --result posted --ledger "$LEDGER" >/dev/null
"$LEDGER_LIB" append "gsd-recipe:plan_complete:phase=1:issue=PROJ-101" jira --result posted --ledger "$LEDGER" >/dev/null
rm -f "$CHECKPOINT"

OUT4="$(reconcile)"
echo "$OUT4" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['queued'] == [], d['queued']
skipped_events = sorted(e['event_id'] for e in d['duplicate_skipped'])
assert skipped_events == ['discuss_complete', 'intake_started', 'plan_complete'], skipped_events
" && rc=0 || rc=1
check "checkpoint reset + already-ledgered events -> duplicate_skipped, never re-queued" "$rc"

LINES_AFTER="$(wc -l < "$QUEUE" | tr -d ' ')"
[ "$LINES_AFTER" = "3" ]
check "queue file unchanged after ledger-caught duplicates (still 3 lines)" "$?"

# --- 5. execute_started: commit touching PLAN.md's touches: glob, plan_complete already ledgered ---
mkdir -p "$SCRATCH/src/auth"
echo "package auth" > "$SCRATCH/src/auth/main.go"
git -C "$SCRATCH" add -A && git -C "$SCRATCH" -c user.email=t@e.com -c user.name=T commit -q -m "implement auth"

OUT5="$(reconcile)"
echo "$OUT5" | python3 -c "
import json, sys
d = json.load(sys.stdin)
events = sorted(e['event_id'] for e in d['queued'])
assert events == ['execute_started'], events
" && rc=0 || rc=1
check "commit touching PLAN.md touches: glob fires execute_started" "$rc"

# --- 6. plan_revised: modify PLAN.md again after plan_complete is ledgered, commit-keyed ---
# Drain execute_started from step 5 first — otherwise it legitimately keeps
# reappearing every run (detection vs. posting are separate; only a drained/
# ledgered entry stops being redetected).
"$LEDGER_LIB" append "gsd-recipe:execute_started:phase=1:issue=PROJ-101" jira --result posted --ledger "$LEDGER" >/dev/null
sleep 1.1
cat >> "$SCRATCH/.planning/phases/01-auth/01-01-PLAN.md" <<'EOF'

## revision
EOF
touch "$SCRATCH/.planning/phases/01-auth/01-01-PLAN.md"
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -q -m "revise plan"

OUT6="$(reconcile)"
echo "$OUT6" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d['queued']) == 1, d
rev = d['queued'][0]
assert rev['event_id'] == 'plan_revised', rev
assert rev['key'].startswith('gsd-recipe:plan_revised:phase=1:commit='), rev['key']
assert ':issue=PROJ-101' in rev['key']
" && rc=0 || rc=1
check "modifying PLAN.md again fires commit-keyed plan_revised" "$rc"

# --- 7. execute_complete / review_complete / verify_complete on SUMMARY/REVIEW/VERIFICATION ---
cat > "$SCRATCH/.planning/phases/01-auth/01-01-SUMMARY.md" <<'EOF'
# summary
EOF
cat > "$SCRATCH/.planning/phases/01-auth/01-VERIFICATION.md" <<'EOF'
# verification
EOF
cat > "$SCRATCH/.planning/phases/01-auth/01-01-REVIEW.md" <<'EOF'
# review
EOF
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -q -m "phase 1 done"

OUT7="$(reconcile)"
echo "$OUT7" | python3 -c "
import json, sys
d = json.load(sys.stdin)
events = sorted(e['event_id'] for e in d['queued'])
assert events == ['execute_complete', 'review_complete', 'verify_complete'], events
for e in d['queued']:
    assert e.get('phase_id') == '1', e
" && rc=0 || rc=1
check "SUMMARY/VERIFICATION/REVIEW fire execute_complete + verify_complete + review_complete, phase-routed" "$rc"

# --- 8. learning_stored is deliberately NOT auto-inferred (deferred, no error) ---
mkdir -p "$SCRATCH/.sdlc/patterns/repo"
cat > "$SCRATCH/.sdlc/patterns/repo/auth-pattern.md" <<'EOF'
# learned pattern
EOF
git -C "$SCRATCH" add -A && git -C "$SCRATCH" commit -q -m "learning"

OUT8="$(reconcile)"
echo "$OUT8" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['queued'] == [] and d['errors'] == [], d
" && rc=0 || rc=1
check "new .sdlc/patterns/repo/ file does not raise an error or get mis-routed (deferred by design)" "$rc"

# --- 9. execute_started never fires before plan_complete is ledgered (fresh phase, no ledger entry) ---
SCRATCH2="$(mktemp -d)"
git init -q "$SCRATCH2"
git -C "$SCRATCH2" config user.email "test@example.com"
git -C "$SCRATCH2" config user.name "Test"
mkdir -p "$SCRATCH2/.planning/phases/02-billing" "$SCRATCH2/src/billing"
cat > "$SCRATCH2/.planning/STATE.md" <<'EOF'
## Tracker
- epic: PROJ-200
- issue: PROJ-200
- system: jira
- url: https://example.atlassian.net/browse/PROJ-200
- run_id: recon-test-02
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 2 | PROJ-201 |
EOF
cat > "$SCRATCH2/.planning/phases/02-billing/02-02-PLAN.md" <<'EOF'
---
phase_id: 02-billing
depends_on: []
touches:
  - src/billing/**
---
# plan (not yet ledgered as plan_complete)
EOF
echo "package billing" > "$SCRATCH2/src/billing/main.go"
git -C "$SCRATCH2" add -A && git -C "$SCRATCH2" commit -q -m "plan + code, but plan_complete never drained/ledgered"

OUT9="$(REPO_ROOT="$SCRATCH2" "$RECONCILE" --run recon-test-02)"
echo "$OUT9" | python3 -c "
import json, sys
d = json.load(sys.stdin)
events = sorted(e['event_id'] for e in d['queued'])
# intake_started fires too (fresh STATE.md in this scratch repo) -- the point
# of this case is that execute_started must NOT be among them.
assert events == ['intake_started', 'plan_complete'], events
" && rc=0 || rc=1
check "execute_started never fires while plan_complete is unposted (unledgered), even though the touching commit exists" "$rc"
rm -rf "$SCRATCH2"

# --- 10. --state / --checkpoint / --queue / --ledger overrides are honored ---
SCRATCH3="$(mktemp -d)"
git init -q "$SCRATCH3"
git -C "$SCRATCH3" config user.email "test@example.com"
git -C "$SCRATCH3" config user.name "Test"
CUSTOM_STATE="$SCRATCH3/custom/STATE.md"
CUSTOM_QUEUE="$SCRATCH3/custom/queue.jsonl"
CUSTOM_CHECKPOINT="$SCRATCH3/custom/checkpoint.json"
CUSTOM_LEDGER="$SCRATCH3/custom/ledger.jsonl"
mkdir -p "$SCRATCH3/custom"
cat > "$CUSTOM_STATE" <<'EOF'
## Tracker
- epic: PROJ-300
- issue: PROJ-300
- system: jira
- url: https://example.atlassian.net/browse/PROJ-300
- run_id: recon-test-03
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-301 |
EOF
git -C "$SCRATCH3" add -A && git -C "$SCRATCH3" commit -q -m "init custom paths"

REPO_ROOT="$SCRATCH3" "$RECONCILE" --run recon-test-03 \
  --state "$CUSTOM_STATE" --queue "$CUSTOM_QUEUE" \
  --checkpoint "$CUSTOM_CHECKPOINT" --ledger "$CUSTOM_LEDGER" >/dev/null

[ -f "$CUSTOM_QUEUE" ] && [ -f "$CUSTOM_CHECKPOINT" ] && [ ! -e "$SCRATCH3/.gsd-recipe/sync-queue.jsonl" ]
check "--state/--queue/--checkpoint/--ledger overrides are honored (nothing written to default .gsd-recipe/ paths)" "$?"
rm -rf "$SCRATCH3"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
