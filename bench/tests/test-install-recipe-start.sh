#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-start.sh (TASK-056).
# Run: ./bench/tests/test-install-recipe-start.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-start.sh"

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

new_repo() {
  local dir
  dir="$(mktemp -d)"
  (cd "$dir" && git init -q && git commit --allow-empty -qm init)
  echo "$dir"
}

NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"

TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-start/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-start/SKILL.md" "$?"
[ -f "$TARGET1/.gsd-recipe/scripts/recipe-next.sh" ]
check "fresh install stages .gsd-recipe/scripts/recipe-next.sh" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-start']))")"
[ "$LEDGER_COUNT1" = "2" ]
check "fresh install records exactly 2 ledger rows (skill + helper)" "$?"

STAGED="$TARGET1/.cursor/skills/recipe-start/SKILL.md"
grep -q "recipe-next.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-next.sh" "$rc"
grep -qi "Yes / No\|Yes/No" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Yes/No invoke gate" "$rc"
grep -q "recipe-onboard" "$STAGED" && rc=0 || rc=$?
check "staged skill mentions recipe-onboard" "$rc"

"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-start']))")"
[ "$LEDGER_COUNT2" = "2" ]
check "re-running install does not duplicate ledger rows" "$?"

TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null
[ ! -f "$TARGET2/.cursor/skills/recipe-start/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/.gsd-recipe/scripts/recipe-next.sh" ]
check "uninstall removes staged recipe-next.sh on a fresh target" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-start' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"

COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-start.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-start.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-start-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/.gsd-recipe/scripts/recipe-next.sh" ]
check "self-uninstall preserves canonical recipe-next.sh" "$?"

INSTALL_SH="$REPO_ROOT/.gsd-recipe/scripts/install.sh"
grep -q "RECIPE_START_INSTALLER" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh declares RECIPE_START_INSTALLER" "$rc"
grep -q 'RECIPE_START_INSTALLER" --yes' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_START_INSTALLER --yes" "$rc"
grep -q 'RECIPE_START_INSTALLER" --uninstall' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_START_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-start"' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-start ledger component" "$rc"
grep -q "recipe-start" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh success copy mentions recipe-start" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
