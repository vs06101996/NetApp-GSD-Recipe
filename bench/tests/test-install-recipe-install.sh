#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-install.sh (TASK-031).
# Matches the convention of bench/tests/test-install-recipe-sync.sh —
# single-file staging shape, ledger tracking, fail-closed non-git target,
# idempotent re-install, uninstall cleanup, self-install collision safety,
# plus staged-content assertions for the skill's documented workflow/scope
# boundaries and, uniquely for this installer, an explicit "never touches
# install.sh itself" assertion.
#
# Run: ./bench/tests/test-install-recipe-install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-install.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-install/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-install/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-install/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-install']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json, .planning/config.json, or
# .gsd-recipe/scripts/install.sh itself — this installer's only job is
# staging one file; install.sh is a sibling script the staged skill's own
# runtime instructions invoke via Shell, never something this installer
# stages, copies, or removes.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/scripts/install.sh" ]
check "install never stages/copies install.sh itself into the target" "$?"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/ledger.json'))
assert list(d.keys()) == ['recipe-install'], d
assert d['recipe-install'] == ['.cursor/skills/recipe-install/SKILL.md'], d
"
check "ledger tracks only recipe-install's own single row, nothing beyond it" "$?"

# 4. Staged content: the workflow steps and documented scope
# boundaries/behaviors this task requires are actually present in the
# shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-install/SKILL.md"

grep -q "recipe-validate-tokens" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes recipe-validate-tokens by name (Step A)" "$rc"
grep -qi "never blocks\|never block" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Step A as informational/never-blocking" "$rc"
grep -qi "live.*consent\|consent gate\|genuine.*human gate" "$STAGED" && rc=0 || rc=$?
check "staged skill documents a live human consent gate (Step B)" "$rc"
grep -q -- "--yes --target" "$STAGED" && rc=0 || rc=$?
check "staged skill documents install.sh --yes --target invocation (Step C)" "$rc"
grep -q "install.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references install.sh directly" "$rc"
grep -q "recipe-install-verify" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes recipe-install-verify by name (Step D)" "$rc"
grep -qi "combined summary" "$STAGED" && rc=0 || rc=$?
check "staged skill documents a combined summary (Step E)" "$rc"
grep -qi "never fabricat" "$STAGED" && rc=0 || rc=$?
check "staged skill documents never fabricating a sub-result" "$rc"
grep -q -- "--record-jira-check" "$STAGED" && rc=0 || rc=$?
check "staged skill mentions --record-jira-check" "$rc"
grep -qi "never.*--record-jira-check\|do not call.*--record-jira-check\|does not call.*--record-jira-check" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims calling --record-jira-check" "$rc"
grep -q -- "--uninstall" "$STAGED" && rc=0 || rc=$?
check "staged skill documents --uninstall mode" "$rc"
grep -qi "install.sh --uninstall" "$STAGED" && rc=0 || rc=$?
check "staged skill's uninstall mode delegates to install.sh --uninstall" "$rc"
grep -qi "why step b is a genuine human gate" "$STAGED" && rc=0 || rc=$?
check "staged skill has a 'Why Step B is a genuine human gate' explanation" "$rc"
grep -qi "nested prompt" "$STAGED" && rc=0 || rc=$?
check "staged skill addresses install.sh's own 'nested prompts are noise' stance" "$rc"
grep -qi "why the uninstall gate mirrors" "$STAGED" && rc=0 || rc=$?
check "staged skill has a 'why the uninstall gate mirrors Step B' explanation" "$rc"
grep -q "read -p" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims implementing its gate as a read -p bash prompt" "$rc"
grep -qi "recipe-settle" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-settle's own human-gate precedent" "$rc"
grep -qi "recipe-sync\|recipe-run-phases" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-sync/recipe-run-phases's own orchestrator precedent" "$rc"
grep -qi "ownership" "$STAGED" && rc=0 || rc=$?
check "staged skill documents an ownership table (which step owns which INSTALL-LLD step)" "$rc"
grep -q "INSTALL-LLD" "$STAGED" && rc=0 || rc=$?
check "staged skill references INSTALL-LLD.md" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-install']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill, clears the ledger entry, and cleans up the dir
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-install/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-install' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-install" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error,
# never touches install.sh itself, and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
INSTALL_SH_BEFORE="$(cat "$COPY/.gsd-recipe/scripts/install.sh")"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-install.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
INSTALL_SH_AFTER="$(cat "$COPY/.gsd-recipe/scripts/install.sh")"
[ "$INSTALL_SH_BEFORE" = "$INSTALL_SH_AFTER" ]
check "self-install never modifies install.sh itself (byte-for-byte unchanged)" "$?"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-install.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-install-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/.gsd-recipe/scripts/install.sh" ]
check "self-uninstall never removes install.sh itself" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
