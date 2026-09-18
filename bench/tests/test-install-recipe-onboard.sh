#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-onboard.sh
# (TASK-037). Matches the convention of
# bench/tests/test-install-recipe-run-phases.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented gates/behaviors.
# Run: ./bench/tests/test-install-recipe-onboard.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-onboard.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-onboard/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-onboard/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-onboard/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-onboard']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors the
# skill requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-onboard/SKILL.md"

grep -q "getAccessibleAtlassianResources" "$STAGED" &&
  grep -qi "discovery.*inconclusive\|discovery is empty" "$STAGED" && rc=0 || rc=$?
check "staged skill wakes dormant Atlassian transport before declaring it unavailable" "$rc"
grep -q "recipe-prd-intake" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-prd-intake by name" "$rc"
grep -q "fotw-observer-bootstrap" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes fotw-observer-bootstrap after PRD exists" "$rc"
grep -qi "whether intake ran or was skipped\|skip.*intake.*observer\|observer hook" "$STAGED" && rc=0 || rc=$?
check "staged skill starts FOTW even when PRD intake is skipped" "$rc"
grep -q -- "--skip-tracker" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --skip-tracker" "$rc"
grep -q "skip_tracker" "$STAGED" && rc=0 || rc=$?
check "staged skill records onboard.skip_tracker in config.json" "$rc"
grep -q "recipe-new-project" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-new-project by name" "$rc"
grep -q "recipe-create-epic" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-create-epic by name" "$rc"
grep -q "recipe-create-phase-tasks" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-create-phase-tasks by name" "$rc"
grep -q "recipe-bootstrap-knowledge" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes mandatory recipe-bootstrap-knowledge" "$rc"
grep -q "recipe-enable-defaults" "$STAGED" && rc=0 || rc=$?
check "staged onboard enables TDD/graphify defaults after roadmap exists" "$rc"
grep -q "recipe-verify-knowledge" "$STAGED" && rc=0 || rc=$?
check "staged skill verifies knowledge via recipe-verify-knowledge.sh" "$rc"
grep -qi "do not.*Write tool\|never treat a hand-written marker" "$STAGED" && rc=0 || rc=$?
check "staged skill rejects hand-written knowledge markers" "$rc"
grep -qi -- "--skip-tracker.*never skips\\|skip-tracker.*knowledge" "$STAGED" && rc=0 || rc=$?
check "--skip-tracker skips Jira but not knowledge" "$rc"
grep -qi "preview-then-confirm\|preview.*confirm" "$STAGED" && rc=0 || rc=$?
check "staged skill documents a single preview-then-confirm gate" "$rc"
grep -qi "stop the whole chain\|stops the whole chain" "$STAGED" && rc=0 || rc=$?
check "staged skill documents stopping the whole chain on first failure" "$rc"
grep -qi "skip\b" "$STAGED" && rc=0 || rc=$?
check "staged skill documents skipping steps whose artifact already exists" "$rc"
grep -qi "never re-implement\|do not re-implement" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims re-implementing any invoked skill's own logic" "$rc"
grep -qi "never fabricate\|do not fabricate" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fabricating any sub-result" "$rc"
grep -q "intake_started" "$STAGED" && rc=0 || rc=$?
check "staged skill references intake_started ownership" "$rc"
grep -qi "recipe-discuss-phase" "$STAGED" && rc=0 || rc=$?
check "staged skill documents recipe-discuss-phase as explicitly deferred" "$rc"
grep -qi "recipe-complete-milestone" "$STAGED" && rc=0 || rc=$?
check "staged skill documents recipe-complete-milestone as explicitly deferred" "$rc"
grep -q "getJiraIssue\|parse-jira-issue-ref\|browse/" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Jira ticket / browse URL onboard" "$rc"
grep -q "init-tracker" "$STAGED" && rc=0 || rc=$?
check "staged skill links existing tickets via init-tracker" "$rc"
grep -qi "do not invoke \`recipe-create-epic\` when" "$STAGED" && rc=0 || rc=$?
check "staged skill does not create a second Epic for an existing ticket" "$rc"
grep -q 'workspace-swap.sh.*archive\|"$LIB" archive' "$STAGED" && rc=0 || rc=$?
check "staged skill archives prior context for explicit new onboarding" "$rc"
grep -qi "must not be used\|will not be reused\|do not reuse" "$STAGED" && rc=0 || rc=$?
check "staged skill forbids reusing prior-cycle recipe artifacts" "$rc"
grep -qi "preload.*before.*switch-out\|read.*before.*switch-out" "$STAGED" && rc=0 || rc=$?
check "staged skill preserves incoming file source before switch-out" "$rc"
grep -q "initiative-branch.sh.*validate" "$STAGED" &&
  grep -q "initiative-branch.sh.*create" "$STAGED" && rc=0 || rc=$?
check "staged skill validates and creates an initiative branch before intake" "$rc"
grep -q "derive-initiative-branch.sh" "$STAGED" &&
  grep -q "feat|fix" "$STAGED" && rc=0 || rc=$?
check "staged skill derives feat/fix feature-title-Ticket branch names" "$rc"
grep -q "recipe-gitignore.sh" "$STAGED" &&
  grep -qi "additive" "$STAGED" && rc=0 || rc=$?
check "staged skill re-applies recipe gitignore after the initiative boundary" "$rc"
grep -q -- "--branch NAME" "$STAGED" && grep -q -- "--no-branch" "$STAGED" && rc=0 || rc=$?
check "staged skill documents branch override and explicit no-branch escape hatch" "$rc"
grep -qi "Never also.*archive\|never also.*archive" "$STAGED" && rc=0 || rc=$?
check "staged skill keeps branch creation and archive-in-place mutually exclusive" "$rc"
grep -q "phase-tasks-queue.jsonl" "$STAGED" &&
  grep -q "sync-ledger.jsonl" "$STAGED" && rc=0 || rc=$?
check "staged skill treats tracker queue and sync ledger as prior initiative state" "$rc"
grep -qi "dirty product worktree\\|tracked/untracked product changes" "$STAGED" && rc=0 || rc=$?
check "staged skill fails closed on dirty product state" "$rc"
grep -q "Recipe-install dirt is not product work" "$STAGED" && rc=0 || rc=$?
check "staged skill excludes recipe-install gitignore/hooks from product dirt" "$rc"
grep -q -- "--base REF" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the --base override for non-default integration branches" "$rc"
grep -q "base-ambiguous" "$STAGED" &&
  grep -qi "never auto-select" "$STAGED" && rc=0 || rc=$?
check "staged skill asks for the base instead of guessing when validate reports ambiguity" "$rc"
grep -qi "do not open a second gate" "$STAGED" && rc=0 || rc=$?
check "staged skill folds the base question into the single preview gate" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-onboard']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-onboard/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-onboard' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-onboard" ]
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
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-onboard.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-onboard.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-onboard-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

# 8. Composition assertions once wired into install.sh (TASK-010) — same
# pattern as bench/tests/test-install.sh's own TASK-024 composition checks.
INSTALL_SH="$REPO_ROOT/.gsd-recipe/scripts/install.sh"
grep -q "RECIPE_ONBOARD_INSTALLER" "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh declares RECIPE_ONBOARD_INSTALLER" "$rc"
grep -q 'RECIPE_ONBOARD_INSTALLER" --yes' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_ONBOARD_INSTALLER --yes" "$rc"
grep -q 'RECIPE_ONBOARD_INSTALLER" --uninstall' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_ONBOARD_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-onboard"' "$INSTALL_SH" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-onboard ledger component" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
