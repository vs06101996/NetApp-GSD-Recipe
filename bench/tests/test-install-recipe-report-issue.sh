#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$ROOT/.gsd-recipe/scripts/install-recipe-report-issue.sh"
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
[[ -f "$target/.cursor/skills/recipe-report-issue/SKILL.md" ]]; check "stages the skill" "$?"
[[ -x "$target/.gsd-recipe/scripts/report-recipe-issue.sh" ]]; check "stages executable runner" "$?"
! grep -q 'readonly INSTALLED_RECIPE_REVISION="__RECIPE_REVISION__"' \
  "$target/.gsd-recipe/scripts/report-recipe-issue.sh"
check "staged runner embeds the source recipe revision" "$?"
[[ -f "$target/.gsd-recipe/templates/recipe-issue-body.template.md" ]]; check "stages body template" "$?"

python3 - "$target/.gsd-recipe/ledger.json" <<'PY'
import json
import sys

rows = json.load(open(sys.argv[1]))["recipe-report-issue"]
assert len(rows) == 3
assert len(rows) == len(set(rows))
PY
check "records three unique ledger rows" "$?"

"$INSTALLER" --yes --target "$target" >/dev/null
count="$(python3 -c "import json; print(len(json.load(open('$target/.gsd-recipe/ledger.json'))['recipe-report-issue']))")"
[[ "$count" == 3 ]]; check "reinstall remains idempotent" "$?"

staged="$target/.cursor/skills/recipe-report-issue/SKILL.md"
grep -q "vs06101996/NetApp-GSD-Recipe" "$staged" &&
  grep -q "non-skippable yes/no" "$staged" &&
  grep -q -- "--dry-run" "$staged" &&
  grep -q "duplicate" "$staged"
check "staged skill preserves fixed target and safety gates" "$?"

"$INSTALLER" --uninstall --target "$target" >/dev/null
[[ ! -f "$target/.cursor/skills/recipe-report-issue/SKILL.md" &&
   ! -f "$target/.gsd-recipe/scripts/report-recipe-issue.sh" &&
   ! -f "$target/.gsd-recipe/templates/recipe-issue-body.template.md" ]]
check "uninstall removes staged files" "$?"

has_component="$(python3 -c "import json; print('recipe-report-issue' in json.load(open('$target/.gsd-recipe/ledger.json')))")"
[[ "$has_component" == False ]]; check "uninstall clears ledger component" "$?"

copy="$(mktemp -d)/copy"
cp -R "$ROOT" "$copy"
(cd "$copy" && ./.gsd-recipe/scripts/install-recipe-report-issue.sh --yes >/dev/null &&
  ./.gsd-recipe/scripts/install-recipe-report-issue.sh --uninstall >/dev/null)
check "self-install and uninstall preserve canonical sources" "$?"
[[ -f "$copy/.gsd-recipe/templates/recipe-report-issue-SKILL.md" &&
   -f "$copy/.gsd-recipe/templates/recipe-issue-body.template.md" &&
   -f "$copy/bench/runners/report-recipe-issue.sh" ]]
check "self-uninstall keeps source files" "$?"

echo "---"
echo "$pass passed, $fail failed"
[[ "$fail" == 0 ]]
