#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/recipe-gitignore.sh"

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

T="$(mktemp -d)"
bash "$LIB" ensure --target "$T" >/dev/null
grep -qxF ".planning/" "$T/.gitignore" &&
  grep -qxF ".gsd/" "$T/.gitignore" &&
  grep -qxF ".gsd-recipe/" "$T/.gitignore" &&
  grep -qxF "graphify-out/" "$T/.gitignore"
check "ensure writes recipe ignore lines including .gsd/ and graphify-out/" "$?"

before="$(wc -l < "$T/.gitignore")"
bash "$LIB" ensure --target "$T" >/dev/null
after="$(wc -l < "$T/.gitignore")"
[ "$before" = "$after" ]
check "ensure is additive and idempotent" "$?"

bash "$LIB" missing --target "$T"
check "missing exits 0 when complete" "$?"

# Simulate trunk without last PR's gitignore: drop recipe lines, keep product ignores
printf 'node_modules/\n.DS_Store\n' > "$T/.gitignore"
bash "$LIB" missing --target "$T" >/dev/null && rc=0 || rc=$?
[ "$rc" != "0" ]
check "missing exits non-zero when recipe lines are absent" "$?"

bash "$LIB" ensure --target "$T" >/dev/null
grep -qxF "node_modules/" "$T/.gitignore" && grep -qxF ".planning/" "$T/.gitignore"
check "ensure keeps existing product ignores and adds recipe lines" "$?"

S="$(mktemp -d)"
mkdir -p "$S/.gsd-recipe/templates" "$S/bench/lib"
touch "$S/.gsd-recipe/templates/x"
cp "$LIB" "$S/bench/lib/recipe-gitignore.sh"
bash "$LIB" ensure --target "$S" >/dev/null
grep -qxF ".planning/" "$S/.gitignore"
! grep -qxF ".gsd-recipe/" "$S/.gitignore"
check "self-install skips hiding .gsd-recipe/" "$?"

rm -rf "$T" "$S"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
