#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-create-phase-tasks.sh
# (TASK-034). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented workflow/gates. Deliberately does
# NOT assert install.sh composition (unlike test-install-recipe-run-phase.sh's
# item 8) — install.sh wiring for this component is deferred to a later
# integration pass (see bench/report/recipe-create-phase-tasks-integration-report.md),
# not part of this task's own diff.
# Run: ./bench/tests/test-install-recipe-create-phase-tasks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh"

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

# 2. Fresh install stages the skill at
# .cursor/skills/recipe-create-phase-tasks/SKILL.md (invoke-by-name Cursor
# skill, same shape as recipe-run-phase/recipe-plan-phase).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-create-phase-tasks/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-create-phase-tasks/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-create-phase-tasks']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. No new runner script is staged — bench/runners/create-phase-tasks.sh
# already lives in place, extended in-place (not staged) by this task.
[ ! -d "$TARGET1/bench" ]
check "install never stages a bench/ tree (create-phase-tasks.sh already lives in place)" "$?"

# 4. Never touches .gsd-recipe/config.json, .planning/config.json, or
# .gsd-recipe/phase-tasks-queue.jsonl.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/phase-tasks-queue.jsonl" ]
check "install never creates .gsd-recipe/phase-tasks-queue.jsonl" "$?"

# 5. Staged content: the workflow steps and documented gates/behaviors the
# plan requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-create-phase-tasks/SKILL.md"

grep -q "create-phase-tasks.sh detect" "$STAGED" && rc=0 || rc=$?
check "staged skill references create-phase-tasks.sh detect" "$rc"
grep -q "create-phase-tasks.sh list" "$STAGED" && rc=0 || rc=$?
check "staged skill references create-phase-tasks.sh list" "$rc"
grep -q "self_healed\|self-healed\|self-heal" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the self-heal behavior of the list step" "$rc"
grep -q "getJiraProjectIssueTypesMetadata" "$STAGED" && rc=0 || rc=$?
check "staged skill references getJiraProjectIssueTypesMetadata for batch issue-type resolution" "$rc"
grep -qi '"Task"' "$STAGED" && rc=0 || rc=$?
check "staged skill documents preferring Task first" "$rc"
grep -qi "Sub-task" "$STAGED" && rc=0 || rc=$?
check "staged skill documents falling back to Sub-task" "$rc"
grep -q "createJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real createJiraIssue MCP call" "$rc"
grep -q "lookupJiraAccountId" "$STAGED" && rc=0 || rc=$?
check "staged skill looks up assignee via lookupJiraAccountId" "$rc"
grep -q "assignee_account_id" "$STAGED" && rc=0 || rc=$?
check "staged skill assigns on create" "$rc"
grep -q "To Do" "$STAGED" && rc=0 || rc=$?
check "staged skill transitions new tasks to To Do" "$rc"
grep -q "createIssueLink" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real createIssueLink MCP call" "$rc"
grep -q "parent" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the parent-field sub-task linking pattern" "$rc"
grep -qi "getIssueLinkTypes" "$STAGED" && rc=0 || rc=$?
check "staged skill references checking getIssueLinkTypes before guessing a link type" "$rc"
grep -q "mark-done" "$STAGED" && rc=0 || rc=$?
check "staged skill references mark-done" "$rc"
grep -q "mark-failed" "$STAGED" && rc=0 || rc=$?
check "staged skill references mark-failed" "$rc"
grep -qi "recipe-create-epic" "$STAGED" && rc=0 || rc=$?
check "staged skill cross-references recipe-create-epic (TASK-033) when no epic is linked" "$rc"
grep -q "never re-run detect\|Never re-run detect" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims re-running detect mid-batch" "$rc"
grep -qi "addCommentToJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims posting Jira comments (gsd-jira-sync's job)" "$rc"
grep -qi "soft confirm gate\|confirm gate" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the soft confirm gate before creating anything remote" "$rc"
grep -q "ascending" "$STAGED" && rc=0 || rc=$?
check "staged skill documents ascending phase-id processing order" "$rc"

# 6. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-create-phase-tasks']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6b. --verify passes on a freshly-installed target, fails on a target that
# was never installed (mirrors install-recipe-create-epic.sh's own --verify
# precedent).
"$INSTALLER" --verify --target "$TARGET1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "--verify passes on a freshly-installed target" "$rc"

TARGET_NEVER_INSTALLED="$(new_repo)"
"$INSTALLER" --verify --target "$TARGET_NEVER_INSTALLED" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--verify fails on a target that was never installed" "$?"

# 7. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-create-phase-tasks/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-create-phase-tasks' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-create-phase-tasks" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 8. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-create-phase-tasks-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
rm -rf "$COPY"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
