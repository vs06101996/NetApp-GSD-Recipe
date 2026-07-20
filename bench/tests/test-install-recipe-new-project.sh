#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-new-project.sh
# (TASK-036). Matches the convention of
# bench/tests/test-install-recipe-plan-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented gates/behaviors.
# Run: ./bench/tests/test-install-recipe-new-project.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-new-project.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-new-project/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-new-project/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-new-project/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-new-project']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors the
# skill requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-new-project/SKILL.md"

grep -q "gsd-new-project" "$STAGED" && rc=0 || rc=$?
check "staged skill references calling native gsd-new-project directly" "$rc"
grep -q "gsd-import" "$STAGED" && rc=0 || rc=$?
check "staged skill references the --import routing to native gsd-import" "$rc"
grep -qi "first-init\|re-init" "$STAGED" && rc=0 || rc=$?
check "staged skill documents first-init-vs-re-init routing" "$rc"
grep -qi "soft warn-and-confirm\|soft.*gate" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the re-init check as a soft warn-and-confirm gate" "$rc"
grep -q "docs/PRD.md" "$STAGED" && rc=0 || rc=$?
check "staged skill references docs/PRD.md as a preferred bootstrap input" "$rc"
grep -q "PROJECT.md" "$STAGED" && rc=0 || rc=$?
check "staged skill references re-verifying PROJECT.md" "$rc"
grep -q "intake_started" "$STAGED" && rc=0 || rc=$?
check "staged skill references intake_started" "$rc"
grep -qi "never sync\|does not sync\|do not sync" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims syncing intake_started itself" "$rc"
grep -q "recipe-create-epic" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-create-epic owning intake_started" "$rc"
grep -q "recipe-onboard" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-onboard as the chaining orchestrator" "$rc"
grep -qi "never fabricate\|do not fabricate" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fabricating .planning/* artifacts itself" "$rc"
grep -q "DAG" "$STAGED" && rc=0 || rc=$?
check "staged skill documents DAG validation as explicitly out of scope" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-new-project']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-new-project/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-new-project' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-new-project" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-new-project.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-new-project.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-new-project-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

# 8. Composition assertions once wired into install.sh (TASK-010) — same
# pattern as bench/tests/test-install.sh's own TASK-024 composition checks.
INSTALL_SH="$REPO_ROOT/.gsd-recipe/scripts/install.sh"
grep -q "RECIPE_NEW_PROJECT_INSTALLER" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh declares RECIPE_NEW_PROJECT_INSTALLER" "$rc"
grep -q 'RECIPE_NEW_PROJECT_INSTALLER" --yes' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_NEW_PROJECT_INSTALLER --yes" "$rc"
grep -q 'RECIPE_NEW_PROJECT_INSTALLER" --uninstall' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_NEW_PROJECT_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-new-project"' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-new-project ledger component" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
