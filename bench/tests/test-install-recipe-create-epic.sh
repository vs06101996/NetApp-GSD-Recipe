#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-create-epic.sh
# (TASK-033). Matches the convention of
# bench/tests/test-install-recipe-pr-comment.sh — two-file staging shape
# (skill + bench/runners/draft-jira-epic.sh runtime dependency), no single
# canonical staged_path, ledger tracking, fail-closed non-git target, never
# touches config.json/.planning/STATE.md/.planning/config.json, idempotent
# re-install, uninstall cleanup, self-install collision safety, plus this
# installer's own additive --verify mode.
# Run: ./bench/tests/test-install-recipe-create-epic.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-create-epic.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-create-epic/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-create-epic/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-create-epic/SKILL.md" "$?"

# 3. Also stages its runtime dependency, bench/runners/draft-jira-epic.sh
[ -f "$TARGET1/bench/runners/draft-jira-epic.sh" ]
check "fresh install stages bench/runners/draft-jira-epic.sh" "$?"
[ -x "$TARGET1/bench/runners/draft-jira-epic.sh" ]
check "staged draft-jira-epic.sh is executable" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-create-epic']))")"
[ "$LEDGER_COUNT1" = "2" ]
check "fresh install records exactly 2 ledger rows (skill + runner)" "$?"

# 4. Never touches .gsd-recipe/config.json, .planning/STATE.md, or
# .planning/config.json.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/STATE.md" ]
check "install never creates .planning/STATE.md" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 5. Staged content: the skill documents the delegation shape, the fail-closed
# PRD-missing check, the confirm gate, init-tracker linkage, and the
# gsd-jira-sync Option-B delegation.
STAGED="$TARGET1/.cursor/skills/recipe-create-epic/SKILL.md"

grep -q "draft-jira-epic.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill delegates to bench/runners/draft-jira-epic.sh" "$rc"
grep -q "recipe-prd-intake" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the fail-closed docs/PRD.md missing case" "$rc"
grep -q "createJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real createJiraIssue MCP call" "$rc"
grep -q "init-tracker" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the parse-state.sh init-tracker linkage step" "$rc"
grep -q "gsd-jira-sync intake_started" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the gsd-jira-sync intake_started sync call" "$rc"
grep -qi "getVisibleJiraProjects" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the live getVisibleJiraProjects question" "$rc"
grep -qi "getJiraProjectIssueTypesMetadata" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the getJiraProjectIssueTypesMetadata issue-type resolution" "$rc"
grep -q -- "--force" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the --force relink flag" "$rc"
grep -qi "never call \`addCommentToJiraIssue\` or \`transitionJiraIssue\` directly" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims posting/transitioning Jira issues directly" "$rc"

# 6. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-create-epic']))")"
[ "$LEDGER_COUNT2" = "2" ]
check "re-running install does not duplicate ledger rows" "$?"

# 7. --verify passes on a correctly-installed target.
"$INSTALLER" --verify --target "$TARGET1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "--verify passes on a correctly-installed target" "$?"

# 8. --verify fails on a target that was never installed.
NEVER_INSTALLED="$(new_repo)"
"$INSTALLER" --verify --target "$NEVER_INSTALLED" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--verify fails non-zero on a never-installed target" "$?"

# 9. Uninstall removes both staged files and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-create-epic/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/bench/runners/draft-jira-epic.sh" ]
check "uninstall removes the staged runner" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-create-epic' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-create-epic" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 10. --verify fails after uninstall.
"$INSTALLER" --verify --target "$TARGET2" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--verify fails non-zero after uninstall" "$?"

# 11. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical sources on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-create-epic.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-create-epic.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-create-epic-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/bench/runners/draft-jira-epic.sh" ]
check "self-uninstall preserves the canonical runner source" "$?"
rm -rf "$COPY"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
