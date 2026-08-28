#!/usr/bin/env bash
# Tests for .gsd-recipe/scripts/install-recipe-update.sh (TASK-058)
# Run: ./bench/tests/test-install-recipe-update.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-update.sh"

pass=0
fail=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $desc"
    pass=$((pass + 1))
  else
    echo "FAIL - $desc"
    fail=$((fail + 1))
  fi
}

new_repo() {
  local dir; dir="$(mktemp -d)"
  git init -q "$dir"
  git -C "$dir" config user.email "test@test" && git -C "$dir" config user.name "test"
  git -C "$dir" commit --allow-empty -qm "init"
  echo "$dir"
}

# 1. Refuses non-git directory
NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]; check "refuses to install into a non-git directory" "$?"

# 2. Fresh install stages both expected files
T1="$(new_repo)"
"$INSTALLER" --yes --target "$T1" >/dev/null
[ -f "$T1/.cursor/skills/recipe-update/SKILL.md" ] && [ -f "$T1/.gsd-recipe/lib/recipe-update.sh" ] && [ -f "$T1/.gsd-recipe/lib/recipe-update-nudge.sh" ]
check "fresh install stages skill + lib + nudge" "$?"

# 3. Staged lib is executable
[ -x "$T1/.gsd-recipe/lib/recipe-update.sh" ]
check "staged lib is executable" "$?"

# 4. Ledger records both component files
LEDGER_FILES="$(python3 -c "import json; d=json.load(open('$T1/.gsd-recipe/ledger.json')); print('\n'.join(d.get('recipe-update',[])))")"
echo "$LEDGER_FILES" | grep -q ".cursor/skills/recipe-update/SKILL.md"
check "ledger records skill file" "$?"
echo "$LEDGER_FILES" | grep -q ".gsd-recipe/lib/recipe-update-nudge.sh"
check "ledger records nudge helper" "$?"

# 5. Idempotent re-install does not error
"$INSTALLER" --yes --target "$T1" >/dev/null && rc=0 || rc=$?
[ "$rc" = "0" ]; check "idempotent re-install does not error" "$?"

# 6. --verify passes after fresh install
"$INSTALLER" --verify --target "$T1" >/dev/null && rc=0 || rc=$?
[ "$rc" = "0" ]; check "--verify passes after fresh install" "$?"

# 7. --uninstall removes staged files
T2="$(new_repo)"
"$INSTALLER" --yes --target "$T2" >/dev/null
"$INSTALLER" --uninstall --target "$T2" >/dev/null
[ ! -f "$T2/.cursor/skills/recipe-update/SKILL.md" ] && [ ! -f "$T2/.gsd-recipe/lib/recipe-update.sh" ] && [ ! -f "$T2/.gsd-recipe/lib/recipe-update-nudge.sh" ]
check "--uninstall removes staged files" "$?"

# 8. --uninstall removes component from ledger
REMAINING="$(python3 -c "import json; print(json.load(open('$T2/.gsd-recipe/ledger.json')).get('recipe-update','none'))" 2>/dev/null || echo "none")"
[ "$REMAINING" = "none" ] || [ "$REMAINING" = "[]" ]
check "--uninstall clears ledger component" "$?"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
