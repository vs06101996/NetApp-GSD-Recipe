#!/usr/bin/env bash
# Regression test for bench/runners/draft-github-pr-comment.sh (TASK-006).
# Run: ./bench/tests/test-draft-github-pr-comment.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRAFT="$REPO_ROOT/bench/runners/draft-github-pr-comment.sh"

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

# --- 1-4. Each of the 4 event_ids in github-events.json renders without ----
#          error and the body contains the expected fields.
for EVENT in execute_wave execute_complete review_complete phase_complete; do
  OUT="$("$DRAFT" "$EVENT" --pr 42 --phase 1 --issue PROJ-101)"
  echo "$OUT" | grep -q -- "$EVENT" \
    && echo "$OUT" | grep -q "PR #42" \
    && echo "$OUT" | grep -q "Phase:\*\* 1" \
    && echo "$OUT" | grep -q "Issue:\*\* PROJ-101" \
    && echo "$OUT" | grep -q "### Idempotency"
  check "$EVENT renders without error with event/PR/phase/issue/idempotency fields" "$?"
done

# --- 5. Missing --pr fails with a clear error, exit non-zero ---------------
if OUT="$("$DRAFT" execute_wave --phase 1 2>&1)"; then rc=1; else rc=0; fi
[ "$rc" = "0" ] && echo "$OUT" | grep -q "\-\-pr and \-\-phase are required"
check "missing --pr fails non-zero with a clear error" "$?"

# --- 6. Missing --phase fails with a clear error, exit non-zero ------------
if OUT="$("$DRAFT" execute_wave --pr 42 2>&1)"; then rc=1; else rc=0; fi
[ "$rc" = "0" ] && echo "$OUT" | grep -q "\-\-pr and \-\-phase are required"
check "missing --phase fails non-zero with a clear error" "$?"

# --- 7. Missing event_id entirely fails with a clear error -----------------
if OUT="$("$DRAFT" 2>&1)"; then rc=1; else rc=0; fi
[ "$rc" = "0" ] && echo "$OUT" | grep -q "event_id required"
check "missing event_id fails non-zero with a clear error" "$?"

# --- 8. Unknown event_id fails with a clear error, exit non-zero -----------
if OUT="$("$DRAFT" not_a_real_event --pr 42 --phase 1 2>&1)"; then rc=1; else rc=0; fi
[ "$rc" = "0" ] && echo "$OUT" | grep -q "Unknown event_id: not_a_real_event"
check "unknown event_id fails non-zero with a clear error" "$?"

# --- 9. --wave present changes the idempotency key format (adds :wave=N) ---
OUT="$("$DRAFT" execute_wave --pr 42 --phase 1 --wave 3 --issue PROJ-101)"
echo "$OUT" | grep -q ":phase=1:wave=3:commit=.*:issue=PROJ-101"
check "--wave present adds a :wave=N segment to the idempotency key" "$?"

# --- 10. --wave absent omits the :wave= segment entirely --------------------
OUT="$("$DRAFT" execute_complete --pr 42 --phase 1 --issue PROJ-101)"
echo "$OUT" | grep -q ":phase=1:commit=.*:issue=PROJ-101" \
  && ! echo "$OUT" | grep -q ":wave="
check "--wave absent omits the :wave= segment from the idempotency key" "$?"

# --- 11. --issue omitted falls back to the TBD-ISSUE placeholder ------------
#         (documents actual current behavior of the script, not a wish)
OUT="$("$DRAFT" execute_wave --pr 42 --phase 1 --wave 1)"
echo "$OUT" | grep -q "Issue:\*\* TBD-ISSUE" \
  && echo "$OUT" | grep -q "issue=TBD-ISSUE"
check "--issue omitted falls back to the TBD-ISSUE placeholder" "$?"

# --- 12. Idempotency key's commit segment resolves the real short SHA ------
#         (regression guard for the hardcoded "commit=HEAD" bug fixed in this task)
REAL_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
OUT="$("$DRAFT" execute_wave --pr 42 --phase 1 --wave 1 --issue PROJ-101)"
echo "$OUT" | grep -q "commit=${REAL_SHA}:issue=PROJ-101"
check "idempotency key's commit segment is the real short SHA, not a literal 'HEAD'" "$?"

# --- 13. Rendered body draws from the real template placeholders -----------
OUT="$("$DRAFT" review_complete --pr 7 --phase 2 --issue PROJ-202)"
echo "$OUT" | grep -q "### Changes"
check "rendered body includes the ### Changes section from the template" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
