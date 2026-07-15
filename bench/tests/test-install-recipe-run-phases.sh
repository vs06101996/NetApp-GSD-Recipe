#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-run-phases.sh
# (TASK-018). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh /
# bench/tests/test-install-recipe-plan-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented gates/behaviors/decisions.
#
# Deliberately omits the install.sh-composition assertion block those two
# sibling test files carry (their own §8) — TASK-018's hard constraints
# forbid editing .gsd-recipe/scripts/install.sh or bench/tests/test-install.sh
# in this task (3 sibling tasks are editing those files concurrently; a
# parent integration pass applies the deferred RECIPE_RUN_PHASES_INSTALLER
# wiring afterward — see bench/report/recipe-run-phases-integration-report.md
# for the exact snippet). Composition assertions would fail against an
# unmodified install.sh, so they don't belong in this standalone file yet.
#
# Run: ./bench/tests/test-install-recipe-run-phases.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-run-phases.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-run-phases/SKILL.md
# (invoke-by-name Cursor skill, NOT the plain top-level skills/ path used by
# recipe-planning-policy's agent_skills injection mechanism).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-run-phases/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-run-phases']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors/
# decisions the task requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-run-phases/SKILL.md"

grep -q "recipe-plan-phase" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-plan-phase (skill-to-skill)" "$rc"
grep -q "recipe-run-phase N" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-run-phase (skill-to-skill)" "$rc"
grep -q "gsd-autonomous" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims calling gsd-autonomous" "$rc"
grep -qi "sequential ascending\|ascending order\|ascending phase-number" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the loop as strictly sequential ascending (no DAG topo-sort)" "$rc"
grep -q "DAG" "$STAGED" && rc=0 || rc=$?
check "staged skill documents DAG topo-sort/eligibility gating as explicitly out of scope" "$rc"
grep -q "PLAN.md" "$STAGED" && rc=0 || rc=$?
check "staged skill references the per-phase PLAN.md-exists check before invoking recipe-plan-phase" "$rc"
grep -qi "stop the whole loop\|stop the loop immediately\|stops? the loop" "$STAGED" && rc=0 || rc=$?
check "staged skill documents stopping the whole loop immediately on the first failure" "$rc"
grep -q "plan step failed\|run step failed" "$STAGED" && rc=0 || rc=$?
check "staged skill distinguishes plan-step vs run-step failure" "$rc"
grep -qi "do not proceed to phase\|does not proceed to\|never proceeds to" "$STAGED" && rc=0 || rc=$?
check "staged skill documents never proceeding to N+1 after a failure" "$rc"
grep -qi "soft.*gate\|soft warn-and-confirm" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the pre-loop range confirmation as a soft gate" "$rc"
grep -q "gsd-jira-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims invoking gsd-jira-sync directly (no duplicate sync)" "$rc"
grep -qi "never dupl\|does not duplicate\|zero additional tracker" "$STAGED" && rc=0 || rc=$?
check "staged skill documents not duplicating Jira sync (already emitted per-phase by the invoked skills)" "$rc"
grep -q "depends_on" "$STAGED" && rc=0 || rc=$?
check "staged skill references depends_on as print-only informational (owned by the invoked skills)" "$rc"
grep -q -- "--wave" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims accepting/forwarding --wave itself" "$rc"

# 4b. TASK-035: auto-range detection + optional --full verify/review/settle chaining
# (staged-content assertions added alongside the original 14 above, same style).
grep -qi "auto-detect" "$STAGED" && rc=0 || rc=$?
check "staged skill documents auto-detecting the range when start/end are both omitted" "$rc"
grep -q "## Phase N" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the '## Phase N — Title' heading grammar for auto-detection" "$rc"
grep -q "create-phase-tasks.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references create-phase-tasks.sh's heading grammar for auto-detection" "$rc"
grep -q -- "--full" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the optional --full flag" "$rc"
grep -q "recipe-verify-feature N" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-verify-feature (skill-to-skill, --full chain)" "$rc"
grep -q "recipe-review-ship N" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-review-ship (skill-to-skill, --full chain)" "$rc"
grep -q "recipe-settle N" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking recipe-settle (skill-to-skill, --full chain)" "$rc"
grep -qi "byte-for-byte identical" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --full as strictly opt-in (byte-for-byte identical when omitted)" "$rc"
grep -q -- "--full sub-step failed" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --full sub-step failures stopping the loop with a specific reason" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-run-phases']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-run-phases' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-run-phases" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-run-phases.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-run-phases.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-run-phases-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
