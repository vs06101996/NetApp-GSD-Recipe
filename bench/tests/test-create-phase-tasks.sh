#!/usr/bin/env bash
# Regression test for bench/runners/create-phase-tasks.sh (TASK-007).
# Run: ./bench/tests/test-create-phase-tasks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/bench/runners/create-phase-tasks.sh"
PARSE_STATE="$REPO_ROOT/bench/lib/parse-state.sh"
FIX="$REPO_ROOT/bench/tests/fixtures"

ROADMAP_FIX="$FIX/roadmap-sample.md"
STATE_FIX="$FIX/state-partial-phase-tasks.md"

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

ROADMAP="$SCRATCH/ROADMAP.md"
STATE="$SCRATCH/STATE.md"
QUEUE="$SCRATCH/phase-tasks-queue.jsonl"
cp "$ROADMAP_FIX" "$ROADMAP"
cp "$STATE_FIX" "$STATE"

detect() {
  REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --roadmap "$ROADMAP" --state "$STATE" --queue "$QUEUE" --run t007-test "$@"
}

# --- 1. --dry-run: correct phase enumeration from fixture ROADMAP.md, correctly
#        skipping the already-linked phase, and no writes at all ------------
OUT1="$(detect --dry-run)"
echo "$OUT1" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['dry_run'] is True
assert d['epic_key'] == 'PROJ-500'
assert sorted(x['phase_id'] for x in d['to_create']) == ['2', '3'], d['to_create']
assert [x['phase_id'] for x in d['already_linked']] == ['1']
assert d['already_queued'] == [] and d['errors'] == []
" && rc=0 || rc=1
check "dry-run enumerates phases from ROADMAP.md, skips already-linked phase 1" "$rc"

[ ! -e "$QUEUE" ]
check "dry-run writes nothing to the queue file" "$?"

STATE_MTIME_BEFORE="$(stat -f %m "$STATE" 2>/dev/null || stat -c %Y "$STATE")"

# --- 2. dry-run drafted content includes phase title/goal and epic linkage --
echo "$OUT1" | python3 -c "
import json, sys
d = json.load(sys.stdin)
p2 = next(x for x in d['to_create'] if x['phase_id'] == '2')
assert 'Agent Studio pilot task' in p2['drafted_summary'], p2
desc = p2['drafted_description']
assert 'PROJ-500' in desc
assert 'Real service registered' in desc
assert 'Phase 2' in desc
"
check "drafted content includes phase title, goal, and epic linkage" "$?"

# --- 3. detect never writes to STATE.md (only mark-done does) --------------
detect --dry-run >/dev/null
STATE_MTIME_AFTER="$(stat -f %m "$STATE" 2>/dev/null || stat -c %Y "$STATE")"
[ "$STATE_MTIME_BEFORE" = "$STATE_MTIME_AFTER" ]
check "detect never modifies STATE.md" "$?"

# --- 4. real run writes exactly 2 queue rows (phases 2 and 3) --------------
OUT2="$(detect)"
[ -f "$QUEUE" ] && [ "$(wc -l < "$QUEUE" | tr -d ' ')" = "2" ]
check "real run writes exactly 2 queue rows for the 2 unlinked phases" "$?"

echo "$OUT2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert sorted(x['phase_id'] for x in d['to_create']) == ['2', '3'], d['to_create']
"
check "real run reports the same 2 phases as dry-run" "$?"

# --- 5. queue rows match this script's own documented schema ---------------
python3 -c "
import json
for line in open('$QUEUE'):
    rec = json.loads(line)
    for field in ('queued_at', 'phase_id', 'phase_title', 'phase_goal', 'epic_key',
                  'key', 'status', 'target', 'drafted_summary', 'drafted_description'):
        assert field in rec, (field, rec)
    assert rec['target'] == 'jira'
    assert rec['status'] == 'queued'
    assert rec['epic_key'] == 'PROJ-500'
"
check "queue rows match documented phase-tasks-queue.jsonl schema" "$?"

# --- 6. idempotency key format reuses sync-ledger.sh's canonical shape -----
python3 -c "
import json
recs = {json.loads(l)['phase_id']: json.loads(l) for l in open('$QUEUE')}
assert recs['2']['key'] == 'gsd-recipe:create_subissue:phase=2:issue=PROJ-500', recs['2']['key']
assert recs['3']['key'] == 'gsd-recipe:create_subissue:phase=3:issue=PROJ-500', recs['3']['key']
"
check "idempotency key format is gsd-recipe:create_subissue:phase={N}:issue={EPIC_KEY}" "$?"

# --- 7. re-running detect on an unchanged queue reports already_queued, does
#        not duplicate rows -------------------------------------------------
OUT3="$(detect)"
echo "$OUT3" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['to_create'] == [], d['to_create']
assert sorted(x['phase_id'] for x in d['already_queued']) == ['2', '3'], d['already_queued']
"
check "re-running detect reports already_queued, no new to_create" "$?"

[ "$(wc -l < "$QUEUE" | tr -d ' ')" = "2" ]
check "queue file still has exactly 2 rows after re-run (no duplication)" "$?"

# --- 8. mark-done writes the issue_key into STATE.md's Phase tasks table ---
OUT4="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-done 2 PROJ-502 --state "$STATE" --queue "$QUEUE")"
echo "$OUT4" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['phase_id'] == '2' and d['issue_key'] == 'PROJ-502'
assert d['state'] == 'updated' and d['queue'] == 'done'
"
check "mark-done reports state=updated, queue=done" "$?"

OUT5="$("$PARSE_STATE" get-phase-issue 2 --state "$STATE")"
[ "$OUT5" = "PROJ-502" ]
check "mark-done actually wrote phase 2 -> PROJ-502 into STATE.md" "$?"

# --- 9. mark-done flips the queue row's status to done ---------------------
python3 -c "
import json
recs = {json.loads(l)['phase_id']: json.loads(l) for l in open('$QUEUE')}
assert recs['2']['status'] == 'done', recs['2']
assert recs['2']['issue_key'] == 'PROJ-502', recs['2']
"
check "mark-done flips the phase 2 queue row to status=done with issue_key recorded" "$?"

# --- 10. mark-done on an already-done phase fails (no queued/failed row) ---
REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-done 2 PROJ-999 --state "$STATE" --queue "$QUEUE" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "mark-done fails when no queued/failed row exists for that phase (already done)" "$?"

# --- 11. detect after mark-done: phase 2 now already_linked ----------------
OUT6="$(detect)"
echo "$OUT6" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert sorted(x['phase_id'] for x in d['already_linked']) == ['1', '2'], d['already_linked']
assert sorted(x['phase_id'] for x in d['already_queued']) == ['3'], d['already_queued']
assert d['to_create'] == []
"
check "detect after mark-done treats phase 2 as already_linked (via STATE.md, not just the queue)" "$?"

# --- 12. mark-failed sets status + error on the phase 3 row ----------------
REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-failed 3 --error "Jira API 500" --queue "$QUEUE" >/dev/null
python3 -c "
import json
recs = {json.loads(l)['phase_id']: json.loads(l) for l in open('$QUEUE')}
assert recs['3']['status'] == 'failed', recs['3']
assert recs['3']['error'] == 'Jira API 500', recs['3']
"
check "mark-failed sets status=failed and records the error message" "$?"

# --- 13. mark-failed on an unknown phase_id fails ---------------------------
REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-failed 999 --error "x" --queue "$QUEUE" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "mark-failed fails on a phase_id with no queued row" "$?"

# --- 14. detect retries a failed row in place (requeue), no duplicate line -
OUT7="$(detect)"
echo "$OUT7" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert [x['phase_id'] for x in d['to_create']] == ['3'], d['to_create']
assert [x['phase_id'] for x in d['requeued']] == ['3'], d['requeued']
"
check "detect requeues a previously-failed phase (retry) instead of skipping or erroring" "$?"

[ "$(wc -l < "$QUEUE" | tr -d ' ')" = "2" ]
check "requeue updates the existing row in place (still 2 lines, no duplicate)" "$?"

python3 -c "
import json
recs = {json.loads(l)['phase_id']: json.loads(l) for l in open('$QUEUE')}
assert recs['3']['status'] == 'queued', recs['3']
assert 'error' not in recs['3'], recs['3']
"
check "requeued row's status is back to queued with the prior error cleared" "$?"

# --- 15. --dry-run and the real run produce the same to_create shape (schema
#         parity, not just phase_id lists) ----------------------------------
SCRATCH2="$(mktemp -d)"
cp "$ROADMAP_FIX" "$SCRATCH2/ROADMAP.md"
cp "$STATE_FIX" "$SCRATCH2/STATE.md"
DRY="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --dry-run --roadmap "$SCRATCH2/ROADMAP.md" --state "$SCRATCH2/STATE.md" --queue "$SCRATCH2/q.jsonl" --run parity)"
echo "$DRY" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for item in d['to_create']:
    for field in ('phase_id', 'key', 'drafted_summary', 'drafted_description'):
        assert field in item, (field, item)
"
check "dry-run to_create entries carry the same fields a real run's queue rows would" "$?"
rm -rf "$SCRATCH2"

# --- 16. missing '## Tracker' epic fails fast with an actionable error -----
SCRATCH3="$(mktemp -d)"
cp "$ROADMAP_FIX" "$SCRATCH3/ROADMAP.md"
cat > "$SCRATCH3/STATE.md" <<'EOF'
## Phase tasks
| phase_id | issue_key |
|----------|-----------|
EOF
ERR="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --roadmap "$SCRATCH3/ROADMAP.md" --state "$SCRATCH3/STATE.md" --queue "$SCRATCH3/q.jsonl" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$ERR" | grep -qi "tracker"
check "detect fails fast with an actionable error when STATE.md has no '## Tracker' epic" "$?"
rm -rf "$SCRATCH3"

# --- 17. ROADMAP.md with no '## Phase N — Title' headings fails fast -------
SCRATCH4="$(mktemp -d)"
echo "# Just a title, no phases" > "$SCRATCH4/ROADMAP.md"
cp "$STATE_FIX" "$SCRATCH4/STATE.md"
ERR2="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --roadmap "$SCRATCH4/ROADMAP.md" --state "$SCRATCH4/STATE.md" --queue "$SCRATCH4/q.jsonl" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$ERR2" | grep -qi "no '## Phase"
check "detect fails fast when ROADMAP.md has no phase headings at all" "$?"
rm -rf "$SCRATCH4"

# --- 18. a phase with no '**Goal:**' line still drafts (fallback text) -----
SCRATCH5="$(mktemp -d)"
cat > "$SCRATCH5/ROADMAP.md" <<'EOF'
## Phase 1 — No goal declared

| Task | Deliverable |
|------|-------------|
| 1.1 | something |
EOF
cat > "$SCRATCH5/STATE.md" <<'EOF'
## Tracker
- epic: PROJ-900
- system: jira
- url: https://your-org.atlassian.net/browse/PROJ-900
- run_id: t007-nogoal
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
EOF
OUT8="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --dry-run --roadmap "$SCRATCH5/ROADMAP.md" --state "$SCRATCH5/STATE.md" --queue "$SCRATCH5/q.jsonl")"
echo "$OUT8" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert len(d['to_create']) == 1, d
assert 'no goal declared in ROADMAP.md' in d['to_create'][0]['drafted_description']
"
check "a phase with no '**Goal:**' line drafts with fallback goal text, no crash" "$?"
rm -rf "$SCRATCH5"

# --- 19. --roadmap/--state/--queue path overrides are honored (no writes to
#         any default .gsd-recipe/ path) ------------------------------------
SCRATCH6="$(mktemp -d)"
git init -q "$SCRATCH6"
mkdir -p "$SCRATCH6/custom"
cp "$ROADMAP_FIX" "$SCRATCH6/custom/ROADMAP.md"
cp "$STATE_FIX" "$SCRATCH6/custom/STATE.md"
REPO_ROOT="$SCRATCH6" "$SCRIPT" detect \
  --roadmap "$SCRATCH6/custom/ROADMAP.md" --state "$SCRATCH6/custom/STATE.md" \
  --queue "$SCRATCH6/custom/queue.jsonl" --run t007-custom >/dev/null
[ -f "$SCRATCH6/custom/queue.jsonl" ] && [ ! -e "$SCRATCH6/.gsd-recipe/phase-tasks-queue.jsonl" ]
check "--roadmap/--state/--queue overrides are honored (nothing written to default .gsd-recipe/ path)" "$?"
rm -rf "$SCRATCH6"

# --- 20. correct phase enumeration order (numeric, not lexicographic) ------
SCRATCH7="$(mktemp -d)"
cat > "$SCRATCH7/ROADMAP.md" <<'EOF'
## Phase 10 — Tenth phase

**Goal:** tenth.

## Phase 2 — Second phase

**Goal:** second.
EOF
cat > "$SCRATCH7/STATE.md" <<'EOF'
## Tracker
- epic: PROJ-950
- system: jira
- url: https://your-org.atlassian.net/browse/PROJ-950
- run_id: t007-order
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
EOF
OUT9="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --dry-run --roadmap "$SCRATCH7/ROADMAP.md" --state "$SCRATCH7/STATE.md" --queue "$SCRATCH7/q.jsonl")"
echo "$OUT9" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert [x['phase_id'] for x in d['to_create']] == ['2', '10'], d['to_create']
"
check "phases are enumerated in numeric order (2 before 10, not lexicographic)" "$?"
rm -rf "$SCRATCH7"

# --- 21. real ROADMAP.md's actual '## Phase N — Title' shape (this repo's
#         own .planning/ROADMAP.md) parses without error -------------------
REAL_ROADMAP="$REPO_ROOT/.planning/ROADMAP.md"
if [ -f "$REAL_ROADMAP" ]; then
  OUT10="$(REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --dry-run --roadmap "$REAL_ROADMAP" --state "$STATE" --queue "$SCRATCH/real-q.jsonl" 2>&1)" && rc=0 || rc=$?
  echo "$OUT10" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert '0' in [x['phase_id'] for x in d['to_create']], d['to_create']
" && rc2=0 || rc2=1
  [ "$rc" = "0" ] && [ "$rc2" = "0" ]
  check "parses this repo's real .planning/ROADMAP.md phase headings without error" "$?"
else
  check "parses this repo's real .planning/ROADMAP.md phase headings without error (skipped, file absent)" "0"
fi

# --- 22. errors array is empty on a clean, valid run ------------------------
echo "$OUT1" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['errors'] == []
"
check "errors array is empty for a valid tracker+ROADMAP combination" "$?"

# --- 23. unknown subcommand exits non-zero with usage ----------------------
"$SCRIPT" bogus-command >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "2" ]
check "unknown subcommand exits 2 with usage" "$?"

# --- `list` subcommand (TASK-034) -------------------------------------------

list() {
  REPO_ROOT="$REPO_ROOT" "$SCRIPT" list "$@"
}

# --- 24. list on a nonexistent/empty queue file returns empty work array,
#         without requiring a valid STATE.md (no rows to check against it) --
SCRATCH8="$(mktemp -d)"
OUT_L1="$(list --queue "$SCRATCH8/no-such-queue.jsonl" --state "$SCRATCH8/no-such-state.md")"
[ "$OUT_L1" = '{
  "work": [],
  "self_healed": [],
  "errors": []
}' ]
check "list on a missing queue file returns empty work/self_healed/errors" "$?"
rm -rf "$SCRATCH8"

# --- 25. list surfaces genuinely-pending rows, reusing detect's own drafted
#         fields verbatim (no re-derivation from ROADMAP.md) ----------------
SCRATCH9="$(mktemp -d)"
ROADMAP9="$SCRATCH9/ROADMAP.md"
STATE9="$SCRATCH9/STATE.md"
QUEUE9="$SCRATCH9/phase-tasks-queue.jsonl"
cp "$ROADMAP_FIX" "$ROADMAP9"
cp "$STATE_FIX" "$STATE9"
REPO_ROOT="$REPO_ROOT" "$SCRIPT" detect --roadmap "$ROADMAP9" --state "$STATE9" --queue "$QUEUE9" --run t034-test >/dev/null

OUT_L2="$(list --queue "$QUEUE9" --state "$STATE9")"
echo "$OUT_L2" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert sorted(w['phase_id'] for w in d['work']) == ['2', '3'], d['work']
assert d['self_healed'] == [] and d['errors'] == []
w2 = next(w for w in d['work'] if w['phase_id'] == '2')
assert w2['epic_key'] == 'PROJ-500', w2
assert w2['key'] == 'gsd-recipe:create_subissue:phase=2:issue=PROJ-500', w2
assert 'Agent Studio pilot task' in w2['drafted_summary'], w2
assert 'Real service registered' in w2['drafted_description'], w2
assert w2['target'] == 'jira', w2
"
check "list returns genuinely-pending rows 2 and 3, reusing detect's own drafted fields verbatim" "$?"

# --- 26. list never mutates the queue file when nothing needs self-healing -
QUEUE9_BEFORE="$(cat "$QUEUE9")"
list --queue "$QUEUE9" --state "$STATE9" >/dev/null
QUEUE9_AFTER="$(cat "$QUEUE9")"
[ "$QUEUE9_BEFORE" = "$QUEUE9_AFTER" ]
check "list does not mutate the queue file when there is nothing to self-heal" "$?"

# --- 27. list self-heals a phase manually linked out-of-band (e.g. a stray
#         manual add-phase-task call) -- no MCP call, dropped from work,
#         counted under self_healed, and the queue row itself flips to done -
"$PARSE_STATE" add-phase-task 2 PROJ-777 --state "$STATE9" >/dev/null

OUT_L3="$(list --queue "$QUEUE9" --state "$STATE9")"
echo "$OUT_L3" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert [w['phase_id'] for w in d['work']] == ['3'], d['work']
assert [h['phase_id'] for h in d['self_healed']] == ['2'], d['self_healed']
assert d['self_healed'][0]['issue_key'] == 'PROJ-777', d['self_healed']
assert d['errors'] == []
"
check "list self-heals a manually-linked phase (dropped from work, counted, no MCP call)" "$?"

python3 -c "
import json
recs = {json.loads(l)['phase_id']: json.loads(l) for l in open('$QUEUE9')}
assert recs['2']['status'] == 'done', recs['2']
assert recs['2']['issue_key'] == 'PROJ-777', recs['2']
assert recs['3']['status'] == 'queued', recs['3']
"
check "self-heal writes issue_key + status=done into the self-healed queue row only" "$?"

# --- 28. list retries a `failed` row exactly like a `queued` one (mix of
#         queued/failed rows are both surfaced) -----------------------------
REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-failed 3 --error "Jira API 500" --queue "$QUEUE9" >/dev/null

OUT_L4="$(list --queue "$QUEUE9" --state "$STATE9")"
echo "$OUT_L4" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert [w['phase_id'] for w in d['work']] == ['3'], d['work']
assert d['self_healed'] == [] and d['errors'] == []
"
check "list surfaces a failed row exactly like a queued one (both retried/listed)" "$?"

# --- 29. list on an all-done queue (no queued/failed rows left) returns an
#         empty work array without even needing to read STATE.md -----------
REPO_ROOT="$REPO_ROOT" "$SCRIPT" mark-done 3 PROJ-503 --state "$STATE9" --queue "$QUEUE9" >/dev/null
OUT_L5="$(list --queue "$QUEUE9" --state "$SCRATCH9/definitely-does-not-exist.md")"
[ "$OUT_L5" = '{
  "work": [],
  "self_healed": [],
  "errors": []
}' ]
check "list on an all-done queue returns empty work without needing a valid STATE.md" "$?"

rm -rf "$SCRATCH9"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
