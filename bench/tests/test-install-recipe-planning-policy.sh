#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-planning-policy.sh
# (TASK-012). Matches the convention of bench/tests/test-install-tracker-sync.sh,
# minus the config.json/tracker-specific cases — this installer never touches
# .gsd-recipe/config.json at all.
# Run: ./bench/tests/test-install-recipe-planning-policy.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-planning-policy.sh"

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

# 2. Fresh install stages the skill at skills/recipe-planning-policy/SKILL.md
# (plain top-level skills/, NOT .cursor/skills/ — the agent_skills injection
# mechanism, distinct from invoke-by-name Cursor skills).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/skills/recipe-planning-policy/SKILL.md" ]
check "fresh install stages skills/recipe-planning-policy/SKILL.md" "$?"

[ ! -d "$TARGET1/.cursor" ]
check "fresh install does NOT stage under .cursor/skills/ (this is agent_skills injection, not an invoke-by-name skill)" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-planning-policy']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. The staged skill references the three PLANNING-POLICY.md sections it operationalizes
grep -q "Prerequisites table" "$TARGET1/skills/recipe-planning-policy/SKILL.md" && rc=0 || rc=$?
check "staged skill references the mandatory Prerequisites table" "$rc"
grep -q "SPEC.template.md" "$TARGET1/skills/recipe-planning-policy/SKILL.md" && rc=0 || rc=$?
check "staged skill references SPEC.template.md" "$rc"
grep -q "graphify" "$TARGET1/skills/recipe-planning-policy/SKILL.md" && rc=0 || rc=$?
check "staged skill references graphify context-gathering" "$rc"

# 4. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-planning-policy']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/skills/recipe-planning-policy/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-planning-policy' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/skills" ]
check "uninstall cleans up the now-empty skills/ directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error and preserves canonical source on uninstall
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-planning-policy.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-planning-policy.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-planning-policy-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
