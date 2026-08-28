#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-observe.sh (TASK-032).
# Matches the convention of bench/tests/test-install-tracker-sync.sh /
# bench/tests/test-install-recipe-sync.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, plus staged-content
# assertions for the skill's documented workflow/scope boundaries, plus a
# dedicated check that this installer never touches any other FOTW file.
#
# Run: ./bench/tests/test-install-recipe-observe.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-observe.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-observe/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-observe/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-observe/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-observe']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never stages/touches observer-config.json, observer-lib.sh, or
# install-observer.sh — all three remain exclusively install-observer.sh's
# job. Also never creates any other FOTW-owned file.
[ ! -f "$TARGET1/.gsd-recipe/observer-config.json" ]
check "install never creates .gsd-recipe/observer-config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/lib/observer-lib.sh" ]
check "install never creates .gsd-recipe/lib/observer-lib.sh" "$?"
[ ! -f "$TARGET1/.gsd-recipe/scripts/install-observer.sh" ]
check "install never creates .gsd-recipe/scripts/install-observer.sh" "$?"
[ ! -f "$TARGET1/.cursor/skills/fotw-observer-bootstrap/SKILL.md" ]
check "install never stages fotw-observer-bootstrap's own skill file" "$?"
[ ! -f "$TARGET1/.gsd-recipe/.observer-active.json" ]
check "install never creates .gsd-recipe/.observer-active.json" "$?"
[ ! -d "$TARGET1/.learnings" ]
check "install never creates a .learnings/ tree" "$?"

# 4. Only the skill file is ledgered under this component — asserts the
# ledger row set is exactly {".cursor/skills/recipe-observe/SKILL.md"}, not
# a superset that accidentally swept in an observer-owned path.
python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/ledger.json'))
assert d['recipe-observe'] == ['.cursor/skills/recipe-observe/SKILL.md'], d['recipe-observe']
"
check "ledger's recipe-observe component contains exactly the one staged skill file" "$?"

# 5. Staged content: the workflow steps and documented scope
# boundaries/behaviors this task requires are actually present in the
# shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-observe/SKILL.md"

grep -q "status|start|stop|enable|disable" "$STAGED" && rc=0 || rc=$?
check "staged skill documents all 5 subcommands in its invocation line" "$rc"
grep -q "fotw-observer-bootstrap" "$STAGED" && rc=0 || rc=$?
check "staged skill references fotw-observer-bootstrap by name for 'start'" "$rc"
grep -q "observer-lib.sh status" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes observer-lib.sh status directly for the 'status' subcommand" "$rc"
grep -q "observer-lib.sh request-stop" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes observer-lib.sh request-stop directly for the 'stop' subcommand" "$rc"
grep -q "observer-lib.sh enable" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes observer-lib.sh enable directly for the 'enable' subcommand" "$rc"
grep -q "observer-lib.sh disable" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes observer-lib.sh disable directly for the 'disable' subcommand" "$rc"
grep -qi "forcibly kill" "$STAGED" && rc=0 || rc=$?
check "staged skill documents that 'stop' cannot forcibly kill a running subagent" "$rc"
grep -qi "graceful.finalize signal\|graceful-finalize" "$STAGED" && rc=0 || rc=$?
check "staged skill documents 'stop' as a graceful-finalize signal only" "$rc"
grep -q "session_end_triggers" "$STAGED" && rc=0 || rc=$?
check "staged skill references observer-config.json's session_end_triggers.explicit_stop" "$rc"
grep -qi "not installed" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the 'not installed' fail-closed message" "$rc"
grep -q "tracker-sync-SKILL.md\|tracker-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill references tracker-sync's own thin-dispatch precedent" "$rc"
grep -qi "do not reimplement\|never reimplement\|zero.*spawn logic\|adds zero new spawn logic" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims reimplementing fotw-observer-bootstrap's spawn logic" "$rc"
grep -q "key: value" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the status report's key: value line format" "$rc"
grep -q "tick_count" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the status report's tick_count field" "$rc"

# 6. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-observe']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 7. Uninstall removes the skill, clears the ledger entry, cleans up the
# dir, and leaves every FOTW-owned file/dir untouched (there were none to
# begin with, but assert the negative explicitly for the removal path too).
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-observe/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-observe' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-observe" ]
check "uninstall cleans up the now-empty skill directory" "$?"
[ ! -f "$TARGET2/.gsd-recipe/observer-config.json" ]
check "uninstall does not create/touch .gsd-recipe/observer-config.json" "$?"
[ ! -f "$TARGET2/.gsd-recipe/lib/observer-lib.sh" ]
check "uninstall does not create/touch .gsd-recipe/lib/observer-lib.sh" "$?"
[ ! -f "$TARGET2/.gsd-recipe/scripts/install-observer.sh" ]
check "uninstall does not create/touch .gsd-recipe/scripts/install-observer.sh" "$?"

# 8. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-observe.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-observe.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-observe-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/bench/lib/observer-lib.sh" ]
check "self-install/uninstall never removes this repo's own bench/lib/observer-lib.sh" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
