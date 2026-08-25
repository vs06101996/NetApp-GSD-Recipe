#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-help.sh (TASK-038).
# Run: ./bench/tests/test-install-recipe-help.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-help.sh"

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
[ -f "$TARGET1/.cursor/skills/recipe-help/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-help/SKILL.md" "$?"
[ -f "$TARGET1/docs/RECIPE-COMMANDS.md" ]
check "fresh install stages docs/RECIPE-COMMANDS.md" "$?"
[ -f "$TARGET1/docs/RECIPE-BENCHMARKS.md" ]
check "fresh install stages docs/RECIPE-BENCHMARKS.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-help']))")"
[ "$LEDGER_COUNT1" = "3" ]
check "fresh install records exactly 3 ledger rows (skill + commands + benchmarks)" "$?"

STAGED="$TARGET1/.cursor/skills/recipe-help/SKILL.md"
grep -q "docs/RECIPE-COMMANDS.md" "$STAGED"
check "staged skill references docs/RECIPE-COMMANDS.md" "$?"
grep -q "KAN-53" "$TARGET1/docs/RECIPE-BENCHMARKS.md"
check "staged benchmarks doc includes KAN-53 field benchmark" "$?"
grep -q "Quick start" "$TARGET1/docs/RECIPE-COMMANDS.md"
check "staged doc contains Quick start workflow section" "$?"
grep -q "\-\-full" "$STAGED"
check "staged skill documents --full mode" "$?"
grep -q "\-\-next" "$STAGED"
check "staged skill documents --next mode" "$?"
grep -q "recipe-start" "$STAGED"
check "staged skill mentions recipe-start" "$?"
grep -q "\-\-assignee" "$STAGED"
check "staged skill documents --assignee for Jira create" "$?"
grep -q "gsd-jira-sync" "$STAGED"
check "staged skill mentions gsd-jira-sync transitions" "$?"
grep -q "Jira tickets" "$TARGET1/docs/RECIPE-COMMANDS.md"
check "staged RECIPE-COMMANDS.md has Jira tickets (assign + status) section" "$?"
grep -q "PRD input formats" "$TARGET1/docs/RECIPE-COMMANDS.md"
check "staged RECIPE-COMMANDS.md exposes PRD input formats" "$?"
grep -q "JIRA-PRD.input.template.md" "$STAGED"
check "staged help skill exposes Jira PRD input template" "$?"
grep -q "Do NOT" "$STAGED"
check "staged skill documents read-only / do-not-invoke-other-skills boundary" "$?"

"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-help']))")"
[ "$LEDGER_COUNT2" = "3" ]
check "re-running install does not duplicate ledger rows" "$?"

TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null
[ ! -f "$TARGET2/.cursor/skills/recipe-help/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/docs/RECIPE-COMMANDS.md" ]
check "uninstall removes the staged doc" "$?"
[ ! -f "$TARGET2/docs/RECIPE-BENCHMARKS.md" ]
check "uninstall removes the staged benchmarks doc" "$?"
python3 -c "
import json
d = json.load(open('$TARGET2/.gsd-recipe/ledger.json'))
assert 'recipe-help' not in d, d
"
check 'uninstall clears the recipe-help ledger entry' "$?"

COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-help.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-help.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-help-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/docs/RECIPE-COMMANDS.md" ]
check "self-uninstall preserves the canonical docs/RECIPE-COMMANDS.md source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
