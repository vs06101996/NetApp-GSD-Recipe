#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-sync.sh (TASK-029).
# Matches the convention of bench/tests/test-install-tracker-sync.sh /
# bench/tests/test-install-recipe-run-phases.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented workflow/scope boundaries.
#
# Run: ./bench/tests/test-install-recipe-sync.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-sync.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-sync/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-sync/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-sync/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-sync']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json, .planning/config.json,
# .gsd-recipe/sync-queue.jsonl, or .gsd-recipe/sync-ledger.jsonl — all four
# are the staged skill's own runtime concern, not the installer's.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/sync-queue.jsonl" ]
check "install never creates .gsd-recipe/sync-queue.jsonl" "$?"
[ ! -f "$TARGET1/.gsd-recipe/sync-ledger.jsonl" ]
check "install never creates .gsd-recipe/sync-ledger.jsonl" "$?"

# 4. Staged content: the workflow steps and documented scope
# boundaries/behaviors this task requires are actually present in the
# shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-sync/SKILL.md"

grep -q "sync-reconcile.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes sync-reconcile.sh directly (real script call)" "$rc"
grep -q -- "--dry-run" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --dry-run passthrough" "$rc"
grep -qi "stop here\|stops here\|stop before\|never proceed to step 3" "$STAGED" && rc=0 || rc=$?
check "staged skill documents stopping before drain on --dry-run" "$rc"
grep -q "gsd-jira-sync --drain" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes gsd-jira-sync --drain by name (skill-to-skill)" "$rc"
grep -qi "does not call \`sync-drain-queue.sh\|never call.*sync-drain-queue.sh\|not reimplement.*sync-drain-queue" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims reimplementing sync-drain-queue.sh's own subcommands" "$rc"
grep -qi "combined summary\|combined report" "$STAGED" && rc=0 || rc=$?
check "staged skill documents a combined summary (step 1 + step 2/3)" "$rc"
grep -q "OD-05" "$STAGED" && rc=0 || rc=$?
check "staged skill references OD-05 by name" "$rc"
grep -qi "why this doesn't loop itself\|doesn't loop itself\|does not loop itself" "$STAGED" && rc=0 || rc=$?
check "staged skill has a 'why this doesn't loop itself' explanation" "$rc"
grep -q -- "--interval" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims an --interval flag" "$rc"
grep -q -- "--watch" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims a --watch flag" "$rc"
grep -qi "daemon" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims a background daemon mode" "$rc"
grep -q "target: github" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the target: github limitation" "$rc"
grep -qi "never fabricat" "$STAGED" && rc=0 || rc=$?
check "staged skill documents never fabricating a drain result" "$rc"
grep -qi "/loop" "$STAGED" && rc=0 || rc=$?
check "staged skill mentions composing with Cursor's own /loop automation" "$rc"
grep -q "hooks later\|hooks-based auto-triggering" "$STAGED" && rc=0 || rc=$?
check "staged skill documents hooks-based auto-triggering as out of scope" "$rc"
grep -q "tracker-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill references tracker-sync's own delegation precedent" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-sync']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill, clears the ledger entry, and cleans up the dir
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-sync/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-sync' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-sync" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-sync.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-sync.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-sync-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
