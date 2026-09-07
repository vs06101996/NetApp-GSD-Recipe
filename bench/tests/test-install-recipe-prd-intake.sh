#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-prd-intake.sh.
# Formalizes the ad hoc temp-repo validation performed during development
# (fresh install, idempotent re-run, template preservation on both install
# and uninstall, uninstall leaving docs/PRD.md untouched) into a
# checked-in, repeatable test, matching the convention of
# bench/tests/test-install-observer.sh.
# Run: ./bench/tests/test-install-recipe-prd-intake.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-prd-intake.sh"

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

# 1. Refuses to install outside a git repo (fail closed)
NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"

# 2. Fresh install stages both expected files
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.templates/PRD.template.md" ]
check "fresh install stages .templates/PRD.template.md" "$?"
[ -f "$TARGET1/.templates/JIRA-PRD.input.template.md" ]
check "fresh install stages .templates/JIRA-PRD.input.template.md" "$?"
[ -f "$TARGET1/.templates/JIRA-PRD.input.MAPPING.md" ]
check "fresh install stages .templates/JIRA-PRD.input.MAPPING.md" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-prd-intake/SKILL.md" "$?"
LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-prd-intake']))")"
[ "$LEDGER_COUNT1" = "4" ]
check "fresh install records exactly 4 ledger rows" "$?"

# 3. The staged skill references the fotw-observer-bootstrap integration point
grep -q "fotw-observer-bootstrap" "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" && rc=0 || rc=$?
check "staged skill references fotw-observer-bootstrap" "$rc"

grep -q "JIRA-PRD.input.MAPPING" "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" && rc=0 || rc=$?
check "staged skill references Jira PRD input mapping" "$rc"

grep -q "Never write the 15-section Jira/Confluence form" "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" && rc=0 || rc=$?
check "staged skill forbids writing Jira shape to docs/PRD.md" "$rc"

grep -q "getJiraIssue" "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" && rc=0 || rc=$?
check "staged skill fetches Jira issues via getJiraIssue" "$rc"

# 4. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-prd-intake']))")"
[ "$LEDGER_COUNT2" = "4" ]
check "re-running install does not duplicate ledger rows" "$?"

# 5. Never overwrites an operator-customized PRD.template.md on re-install
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
echo "OPERATOR CUSTOM CONTENT" >> "$TARGET2/.templates/PRD.template.md"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
grep -q "OPERATOR CUSTOM CONTENT" "$TARGET2/.templates/PRD.template.md" && rc=0 || rc=$?
check "re-install never overwrites an operator-customized template" "$rc"

# 6. Uninstall removes the skill, preserves the (possibly customized) template, and never touches docs/PRD.md
TARGET3="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET3" >/dev/null
echo "OPERATOR CUSTOM CONTENT" >> "$TARGET3/.templates/PRD.template.md"
mkdir -p "$TARGET3/docs"
echo "# a real PRD written during usage" > "$TARGET3/docs/PRD.md"
"$INSTALLER" --uninstall --target "$TARGET3" >/dev/null

[ ! -f "$TARGET3/.cursor/skills/recipe-prd-intake/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ -f "$TARGET3/.templates/PRD.template.md" ]
check "uninstall preserves .templates/PRD.template.md (operator-customizable scaffold data)" "$?"
grep -q "OPERATOR CUSTOM CONTENT" "$TARGET3/.templates/PRD.template.md" && rc=0 || rc=$?
check "preserved template's customization is intact after uninstall" "$rc"
[ -f "$TARGET3/docs/PRD.md" ]
check "uninstall never touches docs/PRD.md (not tracked by this installer)" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET3/.gsd-recipe/ledger.json')); print('recipe-prd-intake' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"

# 7. Uninstall on a fresh (never-customized) install also preserves the template
TARGET4="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET4" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET4" >/dev/null
[ -f "$TARGET4/.templates/PRD.template.md" ]
check "uninstall preserves the template even when it was never customized" "$?"

# 8. Self-install case (installing into this implementation repo itself) does not error and does not delete canonical sources on uninstall
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-prd-intake.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-prd-intake.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-prd-intake-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/.gsd-recipe/templates/PRD.template.md" ]
check "self-uninstall preserves the canonical PRD template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
