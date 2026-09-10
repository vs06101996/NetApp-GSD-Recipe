#!/usr/bin/env bash
# Tests for .gsd-recipe/scripts/install-recipe-workspace.sh (TASK-059).
# Run: ./bench/tests/test-install-recipe-workspace.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-workspace.sh"

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
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email "test@local"
  git -C "$dir" config user.name "test"
  git -C "$dir" commit --allow-empty -qm "init"
  echo "$dir"
}

# ── 1. Refuses non-git directory ─────────────────────────────────────────────
NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"
rm -rf "$NOTGIT"

# ── 2. Fresh install stages all expected files ───────────────────────────────
T2="$(new_repo)"
"$INSTALLER" --yes --target "$T2" >/dev/null
EXPECTED=(
  ".cursor/skills/recipe-workspace/SKILL.md"
  ".gsd-recipe/lib/workspace-swap.sh"
  ".gsd-recipe/lib/initiative-branch.sh"
  ".gsd-recipe/lib/derive-initiative-branch.sh"
  ".gsd-recipe/lib/recipe-gitignore.sh"
  ".cursor/hooks/workspace-swap-cursor-fallback.sh"
  ".cursor/hooks.json"
  ".gsd-recipe/workspaces/.gitkeep"
)
ok=0
for f in "${EXPECTED[@]}"; do
  [ -f "$T2/$f" ] || { echo "  missing: $f"; ok=1; }
done
check "fresh install stages all expected files" "$ok"
grep -q "cmd_archive" "$T2/.gsd-recipe/lib/workspace-swap.sh"
check "staged workspace runtime supports fresh-onboarding archive" "$?"

# ── 3. git post-checkout hook exists and is executable ───────────────────────
[ -x "$T2/.git/hooks/post-checkout" ]
check ".git/hooks/post-checkout exists and is executable" "$?"

# ── 4. hooks.json has the postToolUse entry ───────────────────────────────────
python3 - "$T2/.cursor/hooks.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
post = data.get("hooks", {}).get("postToolUse", [])
found = any(e.get("command") == ".cursor/hooks/workspace-swap-cursor-fallback.sh" and e.get("matcher") == "Bash" for e in post)
sys.exit(0 if found else 1)
PY
check "hooks.json has postToolUse Bash entry for fallback" "$?"

# ── 5. Ledger records all component files ────────────────────────────────────
python3 - "$T2/.gsd-recipe/ledger.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
files = data.get("recipe-workspace", [])
expected = [
    ".cursor/skills/recipe-workspace/SKILL.md",
    ".gsd-recipe/lib/workspace-swap.sh",
    ".gsd-recipe/lib/initiative-branch.sh",
    ".gsd-recipe/lib/derive-initiative-branch.sh",
    ".gsd-recipe/lib/recipe-gitignore.sh",
    ".cursor/hooks/workspace-swap-cursor-fallback.sh",
    ".cursor/hooks.json",
    ".gsd-recipe/workspaces/.gitkeep",
]
missing = [f for f in expected if f not in files]
if missing:
    print("missing from ledger:", missing)
    sys.exit(1)
sys.exit(0)
PY
check "ledger records all component files under recipe-workspace" "$?"

# ── 6. Idempotent re-install ─────────────────────────────────────────────────
"$INSTALLER" --yes --target "$T2" >/dev/null 2>&1
check "idempotent re-install does not error" "$?"

# ── 7. --verify passes after fresh install ───────────────────────────────────
"$INSTALLER" --verify --target "$T2" >/dev/null 2>&1
check "--verify passes after fresh install" "$?"

# ── 8. --uninstall removes staged files ──────────────────────────────────────
T8="$(new_repo)"
"$INSTALLER" --yes --target "$T8" >/dev/null
"$INSTALLER" --uninstall --target "$T8" >/dev/null
LEDGER_FILES="$T8/.gsd-recipe/lib/workspace-swap.sh $T8/.gsd-recipe/lib/initiative-branch.sh $T8/.cursor/skills/recipe-workspace/SKILL.md $T8/.cursor/hooks/workspace-swap-cursor-fallback.sh"
removed_ok=0
for f in $LEDGER_FILES; do
  [ -f "$f" ] && { echo "  still present: $f"; removed_ok=1; }
done
check "--uninstall removes staged files" "$removed_ok"
rm -rf "$T8"

# ── 9. --uninstall keeps .gsd-recipe/workspaces/ when it has content ─────────
T9="$(new_repo)"
"$INSTALLER" --yes --target "$T9" >/dev/null
# Simulate a snapshot existing
mkdir -p "$T9/.gsd-recipe/workspaces/main"
echo "feat/something" > "$T9/.gsd-recipe/workspaces/main/.branch-name"
"$INSTALLER" --uninstall --target "$T9" >/dev/null
[ -d "$T9/.gsd-recipe/workspaces/main" ]
check "--uninstall preserves workspaces/ when snapshots exist" "$?"
rm -rf "$T9"

# ── 10. --uninstall removes postToolUse entry from hooks.json ────────────────
T10="$(new_repo)"
"$INSTALLER" --yes --target "$T10" >/dev/null
"$INSTALLER" --uninstall --target "$T10" >/dev/null
python3 - "$T10/.cursor/hooks.json" <<'PY'
import json, sys, os
path = sys.argv[1]
if not os.path.exists(path):
    sys.exit(0)  # hooks.json removed entirely is also fine
data = json.load(open(path))
post = data.get("hooks", {}).get("postToolUse", [])
found = any(e.get("command") == ".cursor/hooks/workspace-swap-cursor-fallback.sh" for e in post)
sys.exit(1 if found else 0)
PY
check "--uninstall removes postToolUse entry from hooks.json" "$?"
rm -rf "$T10"

# ── 11. Real git switch snapshots old branch and clears/restores new branch ───
T11="$(new_repo)"
"$INSTALLER" --yes --target "$T11" >/dev/null
DEFAULT_BRANCH="$(git -C "$T11" branch --show-current)"
mkdir -p "$T11/.planning"
echo "main roadmap" > "$T11/.planning/ROADMAP.md"
mkdir -p "$T11/.gsd-recipe"
echo "main queue" > "$T11/.gsd-recipe/phase-tasks-queue.jsonl"
echo "main ledger" > "$T11/.gsd-recipe/sync-ledger.jsonl"
git -C "$T11" branch feat/fresh
git -C "$T11" switch -q feat/fresh
[ -f "$T11/.gsd-recipe/workspaces/master/.planning/ROADMAP.md" ] ||
  [ -f "$T11/.gsd-recipe/workspaces/main/.planning/ROADMAP.md" ]
check "post-checkout: snapshots the branch being left" "$?"
[ ! -d "$T11/.planning" ]
check "post-checkout: fresh branch cannot inherit previous planning" "$?"
[ ! -f "$T11/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ ! -f "$T11/.gsd-recipe/sync-ledger.jsonl" ]
check "post-checkout: fresh branch cannot inherit previous tracker state" "$?"
mkdir -p "$T11/.planning"
echo "feature roadmap" > "$T11/.planning/ROADMAP.md"
echo "feature queue" > "$T11/.gsd-recipe/phase-tasks-queue.jsonl"
git -C "$T11" switch -q "$DEFAULT_BRANCH"
grep -q "main roadmap" "$T11/.planning/ROADMAP.md"
check "post-checkout: returning restores the branch-specific snapshot" "$?"
grep -q "main queue" "$T11/.gsd-recipe/phase-tasks-queue.jsonl" &&
  grep -q "main ledger" "$T11/.gsd-recipe/sync-ledger.jsonl"
check "post-checkout: returning restores branch-specific tracker state" "$?"
rm -rf "$T11"

rm -rf "$T2"

# ── summary ───────────────────────────────────────────────────────────────────
echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
