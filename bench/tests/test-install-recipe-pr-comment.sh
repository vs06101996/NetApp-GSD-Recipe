#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-pr-comment.sh
# (TASK-030). Matches the convention of
# bench/tests/test-install-recipe-install-verify.sh — two-file staging shape
# (skill + bench/runners/post-github-pr-comment.sh runtime dependency), no
# single canonical staged_path, ledger tracking, fail-closed non-git target,
# never touches config.json/.planning/config.json/sync-ledger.jsonl,
# idempotent re-install, uninstall cleanup, self-install collision safety.
# Run: ./bench/tests/test-install-recipe-pr-comment.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-pr-comment.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-pr-comment/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-pr-comment/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-pr-comment/SKILL.md" "$?"

# 3. Also stages its runtime dependency, bench/runners/post-github-pr-comment.sh
[ -f "$TARGET1/bench/runners/post-github-pr-comment.sh" ]
check "fresh install stages bench/runners/post-github-pr-comment.sh" "$?"
[ -x "$TARGET1/bench/runners/post-github-pr-comment.sh" ]
check "staged post-github-pr-comment.sh is executable" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-pr-comment']))")"
[ "$LEDGER_COUNT1" = "2" ]
check "fresh install records exactly 2 ledger rows (skill + runner)" "$?"

# 4. Never touches .gsd-recipe/config.json, .gsd-recipe/install-report.json,
# .planning/config.json, or .gsd-recipe/sync-ledger.jsonl.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/install-report.json" ]
check "install never creates .gsd-recipe/install-report.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/sync-ledger.jsonl" ]
check "install never creates .gsd-recipe/sync-ledger.jsonl" "$?"

# 5. Staged content: the skill documents the delegation shape, the
# synthetic-issue-key convention, and the no-stamp-emission rationale.
STAGED="$TARGET1/.cursor/skills/recipe-pr-comment/SKILL.md"

grep -q "post-github-pr-comment.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill delegates to bench/runners/post-github-pr-comment.sh" "$rc"
grep -qi "does not reimplement\|never reimplement\|delegates entirely\|never duplicat" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims reimplementing the runner's logic" "$rc"
grep -q "gh pr comment" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real gh pr comment CLI call" "$rc"
grep -qi "pr-<PR_NUMBER>\|pr-\\\$PR_NUMBER\|synthetic" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the synthetic pr-<PR_NUMBER> issue-key convention" "$rc"
grep -qi "no stamp\|never emits a stamp\|does not emit a stamp" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the no-stamp-emission decision" "$rc"
grep -qi "duplicate_skipped" "$STAGED" && rc=0 || rc=$?
check "staged skill documents duplicate_skipped idempotency behavior" "$rc"
grep -q -- "--dry-run" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --dry-run mode" "$rc"
grep -qi "not an MCP call\|no MCP call\|not.*MCP" "$STAGED" && rc=0 || rc=$?
check "staged skill clarifies gh pr comment is a real local CLI call, not an MCP call" "$rc"

# 6. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-pr-comment']))")"
[ "$LEDGER_COUNT2" = "2" ]
check "re-running install does not duplicate ledger rows" "$?"

# 7. Uninstall removes both staged files and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-pr-comment/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/bench/runners/post-github-pr-comment.sh" ]
check "uninstall removes the staged runner" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-pr-comment' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-pr-comment" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 8. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical sources on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-pr-comment.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-pr-comment.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-pr-comment-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/bench/runners/post-github-pr-comment.sh" ]
check "self-uninstall preserves the canonical runner source" "$?"
rm -rf "$COPY"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
