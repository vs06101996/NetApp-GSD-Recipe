#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-review-ship.sh
# (TASK-026). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh /
# bench/tests/test-install-recipe-plan-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented gates/behaviors/decisions.
#
# No install.sh composition section here (unlike test-install-recipe-run-phase.sh's
# §8): TASK-026 is explicitly scoped to defer composing this installer into
# .gsd-recipe/scripts/install.sh / bench/tests/test-install.sh to a later
# integration pass — three sibling tasks (TASK-018/025/027) are being built
# concurrently against those same shared files. See
# bench/report/recipe-review-ship-integration-report.md for the exact
# deferred snippet.
#
# Run: ./bench/tests/test-install-recipe-review-ship.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-review-ship.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-review-ship/SKILL.md
# (invoke-by-name Cursor skill, NOT the plain top-level skills/ path used by
# recipe-planning-policy's agent_skills injection mechanism).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-review-ship/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-review-ship']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors/
# decisions the task requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-review-ship/SKILL.md"

grep -q "gsd-code-review" "$STAGED" && rc=0 || rc=$?
check "staged skill references calling native gsd-code-review directly" "$rc"
grep -q "review_complete" "$STAGED" && rc=0 || rc=$?
check "staged skill references the review_complete sync event" "$rc"
grep -q "gsd-jira-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking gsd-jira-sync (skill-to-skill, not inline)" "$rc"
grep -q "does not inline\|not by inlining\|do not inline\|Do not inline" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims inlining draft-jira-comment.sh's posting logic" "$rc"
grep -q "In Review" "$STAGED" && rc=0 || rc=$?
check "staged skill references the optional 'In Review' transition" "$rc"
grep -q "transitionJiraIssue" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims calling transitionJiraIssue directly itself" "$rc"
grep -q "gsd-ship" "$STAGED" && rc=0 || rc=$?
check "staged skill references calling native gsd-ship directly" "$rc"
grep -q -- "--draft" "$STAGED" && rc=0 || rc=$?
check "staged skill forwards --draft to gsd-ship" "$rc"
grep -qi "PR " "$STAGED" && rc=0 || rc=$?
check "staged skill references surfacing the resulting PR link" "$rc"
grep -q "settled" "$STAGED" && rc=0 || rc=$?
check "staged skill explains why there is no distinct ship/PR sync event (settled/TASK-027)" "$rc"
grep -q "TASK-027\|recipe-settle" "$STAGED" && rc=0 || rc=$?
check "staged skill names recipe-settle/TASK-027 as the owner of the settled event" "$rc"
grep -q "draft-github-pr-comment.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims bundling draft-github-pr-comment.sh" "$rc"
grep -q "Do not auto-invoke or print optional native review commands" "$STAGED" && rc=0 || rc=$?
check "staged skill suppresses native optional-review handoffs" "$rc"
grep -q 'Print only recipe-surface handoff commands: `recipe-status`, then `recipe-settle`' "$STAGED" && rc=0 || rc=$?
check "staged skill keeps next actions on the recipe command surface" "$rc"
grep -q "recipe-verify-feature\|TASK-025" "$STAGED" && rc=0 || rc=$?
check "staged skill defers gsd-verify-work re-checking to recipe-verify-feature (TASK-025)" "$rc"
grep -qi "never silently bypass\|never bypass" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims silently bypassing/faking gsd-ship's passed prerequisite" "$rc"
grep -q "fail-open\|fail closed\|do not block\|Do not block\|never block\|warn and continue" "$STAGED" && rc=0 || rc=$?
check "staged skill documents fail-open behavior on tracker/MCP issues" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-review-ship']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-review-ship' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-review-ship" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
if [ ! -d "$COPY/.git" ]; then
  rm -f "$COPY/.git"
  git -C "$COPY" init -q
  git -C "$COPY" config user.email "test@local"
  git -C "$COPY" config user.name "test"
  git -C "$COPY" add -A
  git -C "$COPY" commit -qm init
fi
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-review-ship.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-review-ship.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-review-ship-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
rm -rf "$(dirname "$COPY")"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
