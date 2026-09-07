#!/usr/bin/env bash
# Tests for bench/lib/parse-jira-issue-ref.sh
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$REPO_ROOT/bench/lib/parse-jira-issue-ref.sh"
pass=0
fail=0
check() {
  local desc="$1"; local result="$2"
  if [ "$result" = "0" ]; then echo "ok - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; fail=$((fail+1)); fi
}

OUT="$("$BIN" KAN-53)"
printf '%s\n' "$OUT" | grep -qx 'key=KAN-53' && rc=0 || rc=$?
check "bare key parses" "$rc"
printf '%s\n' "$OUT" | grep -qx 'url=' && rc=0 || rc=$?
check "bare key has empty url" "$rc"

OUT="$("$BIN" 'https://netapp.atlassian.net/browse/KAN-53')"
printf '%s\n' "$OUT" | grep -qx 'key=KAN-53' && rc=0 || rc=$?
check "browse URL parses key" "$rc"
printf '%s\n' "$OUT" | grep -qx 'url=https://netapp.atlassian.net/browse/KAN-53' && rc=0 || rc=$?
check "browse URL canonicalizes" "$rc"

OUT="$("$BIN" 'https://netapp.atlassian.net/jira/software/c/projects/KAN/issues/KAN-99?selectedIssue=KAN-99')"
printf '%s\n' "$OUT" | grep -qx 'key=KAN-99' && rc=0 || rc=$?
check "issues URL with selectedIssue parses" "$rc"

"$BIN" docs/PRD.md >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "file path is not a Jira ref" "$?"

"$BIN" 'please add logging' >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "freeform prompt is not a Jira ref" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
