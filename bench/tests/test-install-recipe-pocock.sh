#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-pocock.sh (TASK-063).
# Run: ./bench/tests/test-install-recipe-pocock.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$ROOT/.gsd-recipe/scripts/install-recipe-pocock.sh"
pass=0
fail=0

check() {
  if [[ "$2" == 0 ]]; then
    echo "ok - $1"; pass=$((pass + 1))
  else
    echo "FAIL - $1"; fail=$((fail + 1))
  fi
}

new_repo() {
  local target
  target="$(mktemp -d)"
  (cd "$target" && git init -q)
  echo "$target"
}

not_git="$(mktemp -d)"
"$INSTALLER" --yes --target "$not_git" >/dev/null 2>&1 && rc=0 || rc=$?
[[ "$rc" -ne 0 ]]; check "rejects a non-git target" "$?"

target="$(new_repo)"
"$INSTALLER" --yes --target "$target" >/dev/null
[[ -f "$target/.cursor/skills/recipe-grill/SKILL.md" ]]; check "stages recipe-grill" "$?"
[[ -f "$target/skills/recipe-tdd/SKILL.md" ]]; check "stages recipe-tdd agent skill" "$?"
[[ -f "$target/skills/recipe-two-axis-review/SKILL.md" ]]; check "stages two-axis review agent skill" "$?"
[[ -f "$target/.gsd-recipe/vendor/mattpocock/LICENSE" ]]; check "stages MIT LICENSE" "$?"
[[ -f "$target/.gsd-recipe/vendor/mattpocock/SOURCE.md" ]]; check "stages SOURCE.md" "$?"
[[ -f "$target/.gsd-recipe/vendor/mattpocock/skills/productivity/grilling/SKILL.md" ]]
check "stages grilling sheet" "$?"
[[ -f "$target/.gsd-recipe/vendor/mattpocock/skills/engineering/tdd/SKILL.md" ]]
check "stages tdd sheet" "$?"
[[ -f "$target/.gsd-recipe/vendor/mattpocock/skills/engineering/code-review/SKILL.md" ]]
check "stages code-review sheet" "$?"

python3 - "$target/.gsd-recipe/ledger.json" <<'PY'
import json
import sys

rows = json.load(open(sys.argv[1]))["recipe-pocock-skills"]
assert len(rows) == 13, rows
assert len(rows) == len(set(rows))
PY
check "records 13 unique ledger rows (10 vendor + 3 adapters)" "$?"

"$INSTALLER" --yes --target "$target" >/dev/null
count="$(python3 -c "import json; print(len(json.load(open('$target/.gsd-recipe/ledger.json'))['recipe-pocock-skills']))")"
[[ "$count" == 13 ]]; check "reinstall remains idempotent" "$?"

grep -q "mattpocock/skills pack" "$target/.cursor/skills/recipe-grill/SKILL.md" && rc=0 || rc=$?
check "grill adapter forbids the full Pocock pack" "$rc"
grep -q "CONTEXT.md" "$target/skills/recipe-tdd/SKILL.md" && rc=0 || rc=$?
check "tdd adapter maps CONTEXT.md" "$rc"
grep -qi "fail-open" "$target/skills/recipe-two-axis-review/SKILL.md" && rc=0 || rc=$?
check "two-axis adapter is fail-open" "$rc"

"$INSTALLER" --uninstall --target "$target" >/dev/null
[[ ! -f "$target/.cursor/skills/recipe-grill/SKILL.md" &&
   ! -f "$target/skills/recipe-tdd/SKILL.md" &&
   ! -f "$target/.gsd-recipe/vendor/mattpocock/LICENSE" ]]
check "uninstall removes staged vendor and adapters" "$?"
has_component="$(python3 -c "import json; print('recipe-pocock-skills' in json.load(open('$target/.gsd-recipe/ledger.json')))")"
[[ "$has_component" == False ]]; check "uninstall clears ledger component" "$?"

copy="$(mktemp -d)/copy"
cp -R "$ROOT" "$copy"
(cd "$copy" && ./.gsd-recipe/scripts/install-recipe-pocock.sh --yes >/dev/null &&
  ./.gsd-recipe/scripts/install-recipe-pocock.sh --uninstall >/dev/null)
check "self-install and uninstall preserve canonical sources" "$?"
[[ -f "$copy/.gsd-recipe/templates/recipe-grill-SKILL.md" &&
   -f "$copy/.gsd-recipe/vendor/mattpocock/LICENSE" &&
   -f "$copy/.gsd-recipe/vendor/mattpocock/skills/productivity/grilling/SKILL.md" ]]
check "self-uninstall keeps vendor and templates" "$?"

INSTALL_SH="$ROOT/.gsd-recipe/scripts/install.sh"
grep -q "RECIPE_POCOCK_INSTALLER" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh declares RECIPE_POCOCK_INSTALLER" "$rc"
grep -q 'RECIPE_POCOCK_INSTALLER" --yes' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_POCOCK_INSTALLER --yes" "$rc"
grep -q 'RECIPE_POCOCK_INSTALLER" --uninstall' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_POCOCK_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-pocock-skills"' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-pocock-skills ledger component" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[[ "$fail" == 0 ]]
