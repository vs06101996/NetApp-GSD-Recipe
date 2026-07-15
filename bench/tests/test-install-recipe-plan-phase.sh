#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-plan-phase.sh
# (TASK-017). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented gates/behaviors.
# Run: ./bench/tests/test-install-recipe-plan-phase.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-plan-phase.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-plan-phase/SKILL.md
# (invoke-by-name Cursor skill, NOT the plain top-level skills/ path used by
# recipe-planning-policy's agent_skills injection mechanism).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-plan-phase/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-plan-phase']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors the
# plan requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-plan-phase/SKILL.md"

grep -q "plan_complete" "$STAGED" && rc=0 || rc=$?
check "staged skill references plan_complete" "$rc"
grep -q "plan_revised" "$STAGED" && rc=0 || rc=$?
check "staged skill references plan_revised" "$rc"
grep -q "gsd-plan-phase" "$STAGED" && rc=0 || rc=$?
check "staged skill references calling native gsd-plan-phase directly" "$rc"
grep -qi "soft.*gate\|soft warn-and-confirm" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the compliance check as a soft warn-and-confirm gate" "$rc"
grep -qi "never fill\|never fill or fabricate" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims filling/fabricating the Prerequisites table itself" "$rc"
grep -q "depends_on" "$STAGED" && rc=0 || rc=$?
check "staged skill references the non-blocking depends_on reminder" "$rc"
grep -q "touches" "$STAGED" && rc=0 || rc=$?
check "staged skill references the non-blocking touches reminder" "$rc"
grep -q "gsd-jira-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking gsd-jira-sync (skill-to-skill, not inline)" "$rc"
grep -q "does not inline\|not by inlining\|do not inline\|Do not inline" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims inlining draft-jira-comment.sh's posting logic" "$rc"
grep -q "DAG" "$STAGED" && rc=0 || rc=$?
check "staged skill documents DAG topo-sort/gating as explicitly out of scope" "$rc"
grep -q "fail-open\|fail closed\|do not block\|Do not block\|never block\|warn and continue" "$STAGED" && rc=0 || rc=$?
check "staged skill documents fail-open behavior on tracker/MCP issues" "$rc"
grep -qi "first-plan\|re-plan" "$STAGED" && rc=0 || rc=$?
check "staged skill documents first-plan-vs-re-plan routing" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-plan-phase']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-plan-phase' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-plan-phase" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-plan-phase.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-plan-phase.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-plan-phase-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

# 8. Composition assertions once wired into install.sh (TASK-010) — same
# pattern as bench/tests/test-install.sh's own TASK-024 composition checks.
INSTALL_SH="$REPO_ROOT/.gsd-recipe/scripts/install.sh"
grep -q "RECIPE_PLAN_PHASE_INSTALLER" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh declares RECIPE_PLAN_PHASE_INSTALLER" "$rc"
grep -q 'RECIPE_PLAN_PHASE_INSTALLER" --yes' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_PLAN_PHASE_INSTALLER --yes" "$rc"
grep -q 'RECIPE_PLAN_PHASE_INSTALLER" --uninstall' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_PLAN_PHASE_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-plan-phase"' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-plan-phase ledger component" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
