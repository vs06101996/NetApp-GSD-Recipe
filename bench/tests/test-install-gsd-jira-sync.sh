#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-gsd-jira-sync.sh (TASK-028).
# Matches the convention of bench/tests/test-install-tracker-sync.sh /
# bench/tests/test-install-recipe-verify-feature.sh — single-file staging
# shape, ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented behaviors.
# Run: ./bench/tests/test-install-gsd-jira-sync.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-gsd-jira-sync.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/gsd-jira-sync/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/gsd-jira-sync/SKILL.md" ]
check "fresh install stages .cursor/skills/gsd-jira-sync/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['gsd-jira-sync']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json (in particular never sets/reads
# its 'tracker' field — that's install-tracker-sync.sh's own job), never
# touches .planning/config.json, .planning/STATE.md, or
# .gsd-recipe/sync-ledger.jsonl — issue resolution and idempotent posting are
# the staged skill's own runtime job, not the installer's.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.planning/STATE.md" ]
check "install never creates .planning/STATE.md" "$?"
[ ! -f "$TARGET1/.gsd-recipe/sync-ledger.jsonl" ]
check "install never creates .gsd-recipe/sync-ledger.jsonl itself (that's the staged skill's runtime job)" "$?"

# 4. Staged content: the skill's documented behaviors are actually present
# in the shipped file.
STAGED="$TARGET1/.cursor/skills/gsd-jira-sync/SKILL.md"

grep -q "Single-event mode" "$STAGED" && rc=0 || rc=$?
check "staged skill documents single-event mode" "$rc"
grep -q "Drain mode" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Drain mode (TASK-005)" "$rc"
grep -q "gsd-jira-sync --drain" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the --drain invocation" "$rc"
grep -q "sync-drain-queue.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references sync-drain-queue.sh for Drain mode" "$rc"
grep -q "addCommentToJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill references the addCommentToJiraIssue MCP tool" "$rc"
grep -q "transitionJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill references the transitionJiraIssue MCP tool" "$rc"
grep -q "plugin-atlassian-atlassian" "$STAGED" && rc=0 || rc=$?
check "staged skill references the plugin-atlassian-atlassian MCP server" "$rc"
grep -q "draft-jira-comment.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references draft-jira-comment.sh" "$rc"
grep -q "emit-stamp.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references emit-stamp.sh" "$rc"
grep -qi "epic-routed events\|Routing:" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the epic-vs-phase-task routing rule" "$rc"
grep -q "Skip Jira comment when recipe arm is active" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims skipping the Jira comment when arm is active" "$rc"
grep -qi "Post empty comments" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims posting empty comments" "$rc"
grep -q "mark-done" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Drain mode's mark-done step" "$rc"
grep -q "mark-failed" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Drain mode's mark-failed step" "$rc"
grep -qi "ic-\*" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the ic-* (Instaclustr) relationship note" "$rc"
grep -q "do not double-post" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims double-posting alongside ic-*" "$rc"
grep -q "## Linking Jira to the project" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the STATE.md Tracker/Phase-tasks linking contract" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['gsd-jira-sync']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill, clears the ledger entry, cleans up the
# now-empty skill directory
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/gsd-jira-sync/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('gsd-jira-sync' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/gsd-jira-sync" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-gsd-jira-sync.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-gsd-jira-sync.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/gsd-jira-sync-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
