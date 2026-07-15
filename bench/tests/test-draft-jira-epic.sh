#!/usr/bin/env bash
# Regression test for bench/runners/draft-jira-epic.sh (TASK-033).
# Run: ./bench/tests/test-draft-jira-epic.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$REPO_ROOT/bench/runners/draft-jira-epic.sh"
FIX="$REPO_ROOT/bench/tests/fixtures"

NORMAL="$FIX/prd-normal.md"
MISSING_H1="$FIX/prd-missing-h1.md"
OVERLONG="$FIX/prd-overlong-title.md"
MISSING_FILE="$FIX/does-not-exist.md"

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

# 1. Fails non-zero, actionable, when the PRD file doesn't exist at all.
OUT="$("$RUNNER" --prd "$MISSING_FILE" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -qi "not found" && echo "$OUT" | grep -qi "recipe-prd-intake"
check "fails non-zero with an actionable error when the PRD file doesn't exist" "$?"

# 2. Normal PRD: emits a single JSON object with summary+description keys.
OUT="$("$RUNNER" --prd "$NORMAL")"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
assert set(d.keys()) == {'summary', 'description'}, d.keys()
"
check "emits a single JSON object with exactly summary+description keys" "$?"

# 3. Normal PRD: summary is derived from the real H1 heading.
SUMMARY="$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary'])")"
[ "$SUMMARY" = "PRD: Widget Exporter" ]
check "summary is derived from the PRD's first H1 heading" "$?"

# 4. Normal PRD: description concatenates the real PRD.template.md section
# names (Problem/Goals/Non-Goals/Requirements/Out of Scope/Open Questions),
# not invented generic ones, in file order.
DESC="$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['description'])")"
echo "$DESC" | grep -q "^## Problem$"
check "description includes the real '## Problem' section" "$?"
echo "$DESC" | grep -q "^## Goals$"
check "description includes the real '## Goals' section" "$?"
echo "$DESC" | grep -q "^## Non-Goals$"
check "description includes the real '## Non-Goals' section" "$?"
echo "$DESC" | grep -q "^## Requirements$"
check "description includes the real '## Requirements' section" "$?"
echo "$DESC" | grep -q "^## Out of Scope$"
check "description includes the real '## Out of Scope' section" "$?"
echo "$DESC" | grep -q "^## Open Questions (optional)$"
check "description includes the real '## Open Questions (optional)' section" "$?"

PROBLEM_IDX="$(echo "$DESC" | grep -n "^## Problem$" | head -1 | cut -d: -f1)"
GOALS_IDX="$(echo "$DESC" | grep -n "^## Goals$" | head -1 | cut -d: -f1)"
[ "$PROBLEM_IDX" -lt "$GOALS_IDX" ]
check "description preserves file order (Problem before Goals)" "$?"

echo "$DESC" | grep -q "Export any widget list to CSV in one click."
check "description carries through the real filled-in section content" "$?"

# 5. Missing-H1 PRD: falls back to a placeholder summary, still exits 0.
OUT="$("$RUNNER" --prd "$MISSING_H1" 2>/tmp/draft-jira-epic-stderr.$$)" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "missing-H1 PRD still exits 0 (resilient, never hard-fails on a missing heading)" "$?"

SUMMARY="$(echo "$OUT" | python3 -c "import json,sys; print(json.load(sys.stdin)['summary'])")"
[ "$SUMMARY" = "Untitled PRD" ]
check "missing-H1 PRD falls back to the 'Untitled PRD' placeholder summary" "$?"

grep -qi "no top-level" /tmp/draft-jira-epic-stderr.$$
check "missing-H1 PRD prints a warning to stderr" "$?"
rm -f /tmp/draft-jira-epic-stderr.$$

# 6. Overlong-title PRD: truncates to Jira's 255-char limit with a trailing
# ellipsis marker.
OUT="$("$RUNNER" --prd "$OVERLONG")"
echo "$OUT" | python3 -c "
import json, sys
d = json.load(sys.stdin)
s = d['summary']
assert len(s) <= 255, len(s)
assert s.endswith('\u2026'), s[-5:]
"
check "overlong H1 title is truncated to <=255 chars with a trailing ellipsis marker" "$?"

# 7. --project is accepted without changing exit behavior (forwarded,
# not required, does not error).
"$RUNNER" --prd "$NORMAL" --project PROJ >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "--project flag is accepted without error" "$?"

# 8. Default --prd path is docs/PRD.md under REPO_ROOT when omitted.
TMPREPO="$(mktemp -d)"
mkdir -p "$TMPREPO/docs"
cp "$NORMAL" "$TMPREPO/docs/PRD.md"
OUT="$(cd "$TMPREPO" && REPO_ROOT="$TMPREPO" "$RUNNER")"
echo "$OUT" | grep -q "PRD: Widget Exporter"
check "defaults to docs/PRD.md under REPO_ROOT when --prd is omitted" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
