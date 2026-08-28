#!/usr/bin/env bash
# Tests for bench/lib/recipe-update-nudge.sh (recipe-start fail-open check).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NUDGE="$REPO_ROOT/bench/lib/recipe-update-nudge.sh"
LIB="$REPO_ROOT/bench/lib/recipe-update.sh"

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

setup_repos() {
  SOURCE="$(mktemp -d)"
  BARE="$(mktemp -d)"
  TARGET="$(mktemp -d)"
  git init -q "$SOURCE"
  git -C "$SOURCE" config user.email "test@test"
  git -C "$SOURCE" config user.name "test"
  git -C "$SOURCE" commit --allow-empty -qm "init"
  git clone --bare -q "$SOURCE" "$BARE" 2>/dev/null
  git -C "$SOURCE" remote add origin "$BARE"
  git -C "$SOURCE" fetch -q
  git -C "$SOURCE" branch -u origin/main main 2>/dev/null || true
  mkdir -p "$SOURCE/.gsd-recipe/scripts"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$SOURCE/.gsd-recipe/scripts/install.sh"
  chmod +x "$SOURCE/.gsd-recipe/scripts/install.sh"
  git -C "$SOURCE" add -A && git -C "$SOURCE" commit -qm "mock install"
  git -C "$SOURCE" push -q origin main
  git init -q "$TARGET"
  git -C "$TARGET" config user.email "test@test"
  git -C "$TARGET" config user.name "test"
  git -C "$TARGET" commit --allow-empty -qm "init"
  mkdir -p "$TARGET/.gsd-recipe/lib"
  python3 -c "import json; json.dump({'recipe_source': '$SOURCE'}, open('$TARGET/.gsd-recipe/config.json','w'))"
  cp "$LIB" "$TARGET/.gsd-recipe/lib/recipe-update.sh"
  chmod +x "$TARGET/.gsd-recipe/lib/recipe-update.sh"
}

add_upstream_commit() {
  local tmp; tmp="$(mktemp -d)"
  git clone -q "$BARE" "$tmp" 2>/dev/null
  git -C "$tmp" config user.email "test@test"
  git -C "$tmp" config user.name "test"
  git -C "$tmp" commit --allow-empty -qm "upstream: new recipe change"
  git -C "$tmp" push -q origin main
  rm -rf "$tmp"
}

chmod +x "$NUDGE"

OUT="$(RECIPE_UPDATE_CHECK=0 bash "$NUDGE" --target /tmp 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ -z "$OUT" ]
check "RECIPE_UPDATE_CHECK=0 is silent exit 0" "$?"

MISSING="$(mktemp -d)"
git init -q "$MISSING" && git -C "$MISSING" commit --allow-empty -qm init
OUT="$(bash "$NUDGE" --target "$MISSING" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ -z "$OUT" ]
check "missing recipe-update lib is silent" "$?"

setup_repos
OUT="$(bash "$NUDGE" --target "$TARGET" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "up to date exits 0" "$rc"
echo "$OUT" | grep -q "Type recipe-update" && r=1 || r=0
[ "$r" = "0" ]
check "up to date does not nudge restage" "$?"

setup_repos
add_upstream_commit
OUT="$(bash "$NUDGE" --target "$TARGET" 2>&1)" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "incoming changes: nudge exits 0" "$rc"
echo "$OUT" | grep -q "incoming changes" && echo "$OUT" | grep -q "Type recipe-update to restage" && r=0 || r=1
check "incoming changes: prints check output and restage nudge" "$r"
echo "$OUT" | grep -q "recipe-start will not restage" && r=0 || r=1
check "incoming changes: states start will not restage" "$r"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
