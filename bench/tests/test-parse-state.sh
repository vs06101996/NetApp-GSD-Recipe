#!/usr/bin/env bash
# Regression test for bench/lib/parse-state.sh (TASK-002).
# Run: ./bench/tests/test-parse-state.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/parse-state.sh"
FIX="$REPO_ROOT/bench/tests/fixtures"

VALID="$FIX/state-tracker-valid.md"
NO_PHASE_TABLE="$FIX/state-tracker-no-phase-table.md"
MISSING_FIELD="$FIX/state-tracker-missing-field.md"
DUPLICATE_PHASE="$FIX/state-tracker-duplicate-phase.md"
EMPTY_ISSUE_KEY="$FIX/state-tracker-empty-issue-key.md"
NO_TRACKER="$FIX/state-tracker-no-tracker-section.md"
DUPLICATE_TRACKER="$FIX/state-tracker-duplicate-tracker-section.md"
UNSUPPORTED_SYSTEM="$FIX/state-tracker-unsupported-system.md"
MISSING_FILE="$REPO_ROOT/bench/tests/fixtures/does-not-exist.md"

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

# 1. get-tracker on a valid file returns all fields as JSON
OUT="$("$LIB" get-tracker --state "$VALID")"
echo "$OUT" | grep -q '"epic": "PROJ-100"'
check "get-tracker returns tracker fields as JSON" "$?"

# 2. get-tracker fails on missing file
"$LIB" get-tracker --state "$MISSING_FILE" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "get-tracker fails on missing STATE.md" "$?"

# 3. get-phase-issue resolves a known phase_id
OUT="$("$LIB" get-phase-issue 2 --state "$VALID")"
[ "$OUT" = "PROJ-102" ]
check "get-phase-issue resolves a known phase_id" "$?"

# 4. get-phase-issue fails on an unknown phase_id
"$LIB" get-phase-issue 99 --state "$VALID" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "get-phase-issue fails on unknown phase_id" "$?"

# 5. resolve-issue routes an epic-routed event to tracker.epic
OUT="$("$LIB" resolve-issue settled --state "$VALID")"
[ "$OUT" = "PROJ-100" ]
check "resolve-issue routes epic-routed event to tracker.epic" "$?"

# 6. resolve-issue routes a phase-routed event to the matching phase_id row
OUT="$("$LIB" resolve-issue plan_complete --phase 1 --state "$VALID")"
[ "$OUT" = "PROJ-101" ]
check "resolve-issue routes phase-routed event to matching phase_id" "$?"

# 7. resolve-issue fails non-zero (actionable error) when phase-routed event's
#    phase_id has no matching row — DATA-CONTRACTS.md rule 8
"$LIB" resolve-issue plan_complete --phase 99 --state "$VALID" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "resolve-issue fails non-zero on unresolved phase-routed event" "$?"

# 8. resolve-issue fails when a phase-routed event is given without --phase
"$LIB" resolve-issue execute_started --state "$VALID" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "resolve-issue fails when phase-routed event given without --phase" "$?"

# 9. resolve-issue fails on an event_id outside the known vocabulary
"$LIB" resolve-issue not_a_real_event --state "$VALID" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "resolve-issue fails on unknown event_id" "$?"

# 10. validate passes on a well-formed STATE.md
"$LIB" validate --state "$VALID" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "validate passes on well-formed STATE.md" "$?"

# 11. validate passes even with no '## Phase tasks' table at all (optional section)
"$LIB" validate --state "$NO_PHASE_TABLE" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "validate passes when Phase tasks table is absent entirely" "$?"

# 12. validate fails on a missing required Tracker field
OUT="$("$LIB" validate --state "$MISSING_FIELD" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required field 'arm'"
check "validate fails with actionable error on missing required field" "$?"

# 13. validate fails on duplicate phase_id rows
OUT="$("$LIB" validate --state "$DUPLICATE_PHASE" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "duplicate phase_id '1'"
check "validate fails on duplicate phase_id" "$?"

# 14. validate fails on an empty issue_key
OUT="$("$LIB" validate --state "$EMPTY_ISSUE_KEY" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "empty issue_key"
check "validate fails on empty issue_key" "$?"

# 15. validate fails when '## Tracker' section is missing entirely
OUT="$("$LIB" validate --state "$NO_TRACKER" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "no '## Tracker' section found"
check "validate fails when Tracker section is missing" "$?"

# 16. validate does not emit redundant per-field errors when Tracker is missing
OUT="$("$LIB" validate --state "$NO_TRACKER" 2>&1)" || true
LINES="$(echo "$OUT" | wc -l | tr -d ' ')"
[ "$LINES" = "1" ]
check "validate emits exactly one error when Tracker section is missing (no redundant noise)" "$?"

# 17. validate fails when '## Tracker' appears more than once
OUT="$("$LIB" validate --state "$DUPLICATE_TRACKER" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "appears 2 times"
check "validate fails when Tracker section appears more than once" "$?"

# 18. validate fails on an unsupported tracker system
OUT="$("$LIB" validate --state "$UNSUPPORTED_SYSTEM" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "system 'trello' is not supported"
check "validate fails on unsupported tracker system" "$?"

# 19. dump emits both tracker and phase_tasks as structured JSON
OUT="$("$LIB" dump --state "$VALID")"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d['tracker']['epic'] == 'PROJ-100'
assert len(d['phase_tasks']) == 3
assert d['phase_tasks'][0] == {'phase_id': '1', 'issue_key': 'PROJ-101'}
"
check "dump emits structured tracker + phase_tasks JSON" "$?"

# 20. default --state path is .planning/STATE.md under REPO_ROOT (fixed-path contract)
TMPREPO="$(mktemp -d)"
mkdir -p "$TMPREPO/.planning"
cp "$VALID" "$TMPREPO/.planning/STATE.md"
OUT="$(cd "$TMPREPO" && REPO_ROOT="$TMPREPO" "$LIB" get-tracker)"
echo "$OUT" | grep -q '"epic": "PROJ-100"'
check "defaults to .planning/STATE.md under REPO_ROOT when --state is omitted" "$?"

# --- add-phase-task (TASK-007 dependent) ------------------------------------

# 21. add-phase-task appends a new row to an existing '## Phase tasks' table
TMP1="$(mktemp -d)/STATE.md"
mkdir -p "$(dirname "$TMP1")"
cp "$VALID" "$TMP1"
"$LIB" add-phase-task 4 PROJ-104 --state "$TMP1" >/dev/null
OUT="$("$LIB" get-phase-issue 4 --state "$TMP1")"
[ "$OUT" = "PROJ-104" ]
check "add-phase-task appends a new row to an existing Phase tasks table" "$?"

# 22. add-phase-task preserves the pre-existing rows untouched
OUT="$("$LIB" get-phase-issue 2 --state "$TMP1")"
[ "$OUT" = "PROJ-102" ]
check "add-phase-task leaves pre-existing rows untouched" "$?"

# 23. add-phase-task fails (non-zero, actionable) on a duplicate phase_id
OUT="$("$LIB" add-phase-task 4 PROJ-999 --state "$TMP1" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "already has issue_key 'PROJ-104'"
check "add-phase-task refuses to overwrite an existing phase_id row" "$?"

# 24. add-phase-task creates the '## Phase tasks' section when absent entirely
TMP2="$(mktemp -d)/STATE.md"
mkdir -p "$(dirname "$TMP2")"
cp "$NO_PHASE_TABLE" "$TMP2"
"$LIB" add-phase-task 1 PROJ-201 --state "$TMP2" >/dev/null
"$LIB" validate --state "$TMP2" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "add-phase-task creates a well-formed Phase tasks section when absent" "$?"

OUT="$("$LIB" get-phase-issue 1 --state "$TMP2")"
[ "$OUT" = "PROJ-201" ]
check "add-phase-task's newly-created section resolves the added phase_id" "$?"

# 25. add-phase-task fails when '## Tracker' is missing entirely (required order)
OUT="$("$LIB" add-phase-task 2 PROJ-602 --state "$NO_TRACKER" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "no '## Tracker' section found"
check "add-phase-task fails when '## Tracker' section is missing" "$?"

# 26. add-phase-task rejects an empty issue_key argument
OUT="$("$LIB" add-phase-task 5 "" --state "$TMP1" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "non-empty issue_key"
check "add-phase-task rejects an empty issue_key" "$?"

# --- init-tracker (TASK-033 dependent) --------------------------------------

# 27. init-tracker creates STATE.md from scratch with both sections when the
# file doesn't exist yet.
TMP3="$(mktemp -d)/STATE.md"
"$LIB" init-tracker --epic PROJ-500 --system jira --url "https://x/browse/PROJ-500" \
  --run-id run-05 --arm recipe --state "$TMP3" >/dev/null
[ -f "$TMP3" ]
check "init-tracker creates STATE.md when it doesn't exist" "$?"

OUT="$("$LIB" get-tracker --state "$TMP3")"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d == {'epic': 'PROJ-500', 'system': 'jira', 'url': 'https://x/browse/PROJ-500', 'run_id': 'run-05', 'arm': 'recipe'}, d
"
check "init-tracker's freshly-created Tracker section has exactly the 5 requested fields" "$?"

"$LIB" validate --state "$TMP3" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "init-tracker's freshly-created STATE.md validates (Tracker + empty Phase tasks)" "$?"

"$LIB" add-phase-task 1 PROJ-501 --state "$TMP3" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "init-tracker's freshly-created empty Phase tasks section accepts add-phase-task unmodified" "$?"

# 28. init-tracker inserts '## Tracker' into a file with only '## Phase
# tasks' (NO_TRACKER fixture), preserving its existing data row.
TMP4="$(mktemp -d)/STATE.md"
cp "$NO_TRACKER" "$TMP4"
"$LIB" init-tracker --epic PROJ-510 --system jira --url "https://x/browse/PROJ-510" \
  --run-id run-05 --arm recipe --state "$TMP4" >/dev/null
OUT="$("$LIB" get-tracker --state "$TMP4")"
echo "$OUT" | grep -q '"epic": "PROJ-510"'
check "init-tracker inserts a Tracker section into a file with only Phase tasks" "$?"

OUT="$("$LIB" get-phase-issue 1 --state "$TMP4")"
[ "$OUT" = "PROJ-601" ]
check "init-tracker's Tracker insertion preserves the pre-existing Phase tasks data row" "$?"

# 29. init-tracker is idempotent: an identical re-run is a no-op success.
"$LIB" init-tracker --epic PROJ-510 --system jira --url "https://x/browse/PROJ-510" \
  --run-id run-05 --arm recipe --state "$TMP4" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "init-tracker is idempotent (identical re-run exits 0)" "$?"

# 30. init-tracker fails non-zero, actionable, on a differing epic without --force.
OUT="$("$LIB" init-tracker --epic PROJ-999 --system jira --url "https://x/browse/PROJ-999" \
  --run-id run-06 --arm gsd --state "$TMP4" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "already linked to epic 'PROJ-510'" && echo "$OUT" | grep -q -- "--force"
check "init-tracker fails non-zero with an actionable error naming the existing epic on conflict" "$?"

# 31. Conflict-without-force never touched the file (still PROJ-510).
OUT="$("$LIB" get-tracker --state "$TMP4")"
echo "$OUT" | grep -q '"epic": "PROJ-510"'
check "init-tracker's rejected conflict leaves the existing Tracker section untouched" "$?"

# 32. --force overwrites all 5 fields, preserving Phase tasks data rows.
"$LIB" add-phase-task 2 PROJ-602 --state "$TMP4" >/dev/null
"$LIB" init-tracker --epic PROJ-999 --system jira --url "https://x/browse/PROJ-999" \
  --run-id run-06 --arm gsd --state "$TMP4" --force >/dev/null
OUT="$("$LIB" get-tracker --state "$TMP4")"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert d == {'epic': 'PROJ-999', 'system': 'jira', 'url': 'https://x/browse/PROJ-999', 'run_id': 'run-06', 'arm': 'gsd'}, d
"
check "init-tracker --force overwrites all 5 fields" "$?"

OUT="$("$LIB" get-phase-issue 1 --state "$TMP4")"
[ "$OUT" = "PROJ-601" ]
check "init-tracker --force preserves pre-existing Phase tasks rows (row 1)" "$?"
OUT="$("$LIB" get-phase-issue 2 --state "$TMP4")"
[ "$OUT" = "PROJ-602" ]
check "init-tracker --force preserves pre-existing Phase tasks rows (row 2)" "$?"

"$LIB" validate --state "$TMP4" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "init-tracker --force result still validates cleanly" "$?"

# 33. init-tracker rejects a missing required field (--epic omitted).
OUT="$("$LIB" init-tracker --system jira --url "https://x" --run-id r --arm recipe --state "$TMP4" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "non-empty --epic"
check "init-tracker rejects a missing --epic" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
