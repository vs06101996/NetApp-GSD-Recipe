#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/derive-initiative-branch.sh"

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

got="$(bash "$LIB" --title "Add a validation checklist")"
[ "$got" = "feat/add-a-validation-checklist" ]
check "freeform title defaults to feat/slug" "$?"

got="$(bash "$LIB" --kind fix --title "Null pointer in ingest")"
[ "$got" = "fix/null-pointer-in-ingest" ]
check "--kind fix prefixes fix/" "$?"

got="$(bash "$LIB" --file "/tmp/docs/object-store-reconcile.md" --ticket "KAN-53")"
[ "$got" = "feat/object-store-reconcile-KAN-53" ]
check "file + ticket is feat/title-Ticket" "$?"

got="$(bash "$LIB" --ticket "KAN-53")"
[ "$got" = "feat/KAN-53" ]
check "ticket-only uses feat/Ticket" "$?"

got="$(bash "$LIB" --title "KAN-53" --ticket "KAN-53")"
[ "$got" = "feat/KAN-53" ]
check "title matching the ticket is not duplicated" "$?"

bash "$LIB" --kind chore --title "x" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "rejects kind other than feat or fix" "$?"

bash "$LIB" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "fails closed with no title, file, or ticket" "$?"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
