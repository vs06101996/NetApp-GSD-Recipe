#!/usr/bin/env bash
# Tests for bench/lib/recipe-update.sh (TASK-058)
# Run: ./bench/tests/test-recipe-update.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
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

# grep_check: safe grep that never triggers set -e
grep_check() {
  if echo "$1" | grep -q "$2"; then printf '0'; else printf '1'; fi
}

new_target() {
  local dir; dir="$(mktemp -d)"
  git init -q "$dir"
  git -C "$dir" config user.email "test@test" && git -C "$dir" config user.name "test"
  git -C "$dir" commit --allow-empty -qm "init"
  mkdir -p "$dir/.gsd-recipe"
  printf '{}\n' > "$dir/.gsd-recipe/config.json"
  echo "$dir"
}

BARE="" SOURCE="" TARGET=""

setup_repos() {
  SOURCE="$(mktemp -d)"
  BARE="$(mktemp -d)"
  TARGET="$(mktemp -d)"

  # Build SOURCE with a commit, then use a bare clone as the "remote"
  git init -q "$SOURCE"
  git -C "$SOURCE" config user.email "test@test"
  git -C "$SOURCE" config user.name "test"
  git -C "$SOURCE" commit --allow-empty -qm "init"
  git clone --bare -q "$SOURCE" "$BARE" 2>/dev/null
  git -C "$SOURCE" remote add origin "$BARE"
  git -C "$SOURCE" fetch -q
  git -C "$SOURCE" branch -u origin/main main 2>/dev/null || true

  # Mock install.sh in SOURCE (committed so working tree stays clean)
  mkdir -p "$SOURCE/.gsd-recipe/scripts"
  printf '#!/usr/bin/env bash\ntouch "${@: -1}/.gsd-recipe/.install-ran"\n' > "$SOURCE/.gsd-recipe/scripts/install.sh"
  chmod +x "$SOURCE/.gsd-recipe/scripts/install.sh"
  git -C "$SOURCE" add -A && git -C "$SOURCE" commit -qm "add mock install.sh"
  git -C "$SOURCE" push -q origin main

  # TARGET with config pointing to SOURCE
  git init -q "$TARGET"
  git -C "$TARGET" config user.email "test@test"
  git -C "$TARGET" config user.name "test"
  git -C "$TARGET" commit --allow-empty -qm "init"
  mkdir -p "$TARGET/.gsd-recipe"
  python3 -c "import json; json.dump({'recipe_source': '$SOURCE'}, open('$TARGET/.gsd-recipe/config.json','w'))"
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

# 1. Fails closed when config.json missing
T1="$(new_target)"
rm -f "$T1/.gsd-recipe/config.json"
"$LIB" --target "$T1" 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "fails closed when config.json missing" "0"
else check "fails closed when config.json missing" "1"; fi

# 2. Fails closed when recipe_source not set in config
T2="$(new_target)"
python3 -c "import json; json.dump({}, open('$T2/.gsd-recipe/config.json','w'))"
"$LIB" --target "$T2" 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "fails closed when recipe_source not set" "0"
else check "fails closed when recipe_source not set" "1"; fi

# 3. Fails closed when recipe_source path does not exist
T3="$(new_target)"
python3 -c "import json; json.dump({'recipe_source': '/nonexistent/path'}, open('$T3/.gsd-recipe/config.json','w'))"
"$LIB" --target "$T3" 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "fails closed when recipe_source path does not exist" "0"
else check "fails closed when recipe_source path does not exist" "1"; fi

# 4. Fails closed when recipe_source is not a git repo
T4="$(new_target)"
NOT_GIT="$(mktemp -d)"
python3 -c "import json; json.dump({'recipe_source': '$NOT_GIT'}, open('$T4/.gsd-recipe/config.json','w'))"
"$LIB" --target "$T4" 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "fails closed when recipe_source is not a git repo" "0"
else check "fails closed when recipe_source is not a git repo" "1"; fi

# 5. Fails closed when recipe source has dirty working tree
setup_repos
echo "dirty" > "$SOURCE/dirty.txt"
"$LIB" --target "$TARGET" 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "fails closed when recipe source working tree is dirty" "0"
else check "fails closed when recipe source working tree is dirty" "1"; fi
rm -f "$SOURCE/dirty.txt"

# 6. Prints "already up to date" when no commits incoming
setup_repos
OUT="$("$LIB" --target "$TARGET" --dry-run 2>&1 || true)"
check "already up to date when nothing incoming" "$(grep_check "$OUT" "already up to date")"

# 7. --dry-run shows preview and exits 0 without pulling
setup_repos
add_upstream_commit
OUT="$("$LIB" --target "$TARGET" --dry-run 2>&1 || true)"
check "--dry-run shows incoming changes preview" "$(grep_check "$OUT" "incoming changes")"
# Verify SOURCE was NOT pulled (still behind)
BEHIND="$(git -C "$SOURCE" log --oneline HEAD..@{u} 2>/dev/null | wc -l | tr -d ' ')"
if [ "$BEHIND" -gt "0" ]; then check "--dry-run does not pull the source" "0"
else check "--dry-run does not pull the source" "1"; fi

# 8. --check behaves same as --dry-run
setup_repos
add_upstream_commit
OUT="$("$LIB" --target "$TARGET" --check 2>&1 || true)"
check "--check shows incoming changes preview" "$(grep_check "$OUT" "incoming changes")"

# 9. --yes with incoming commits: pulls (source becomes up to date)
setup_repos
add_upstream_commit
"$LIB" --target "$TARGET" --yes 2>&1 >/dev/null || true
BEHIND="$(git -C "$SOURCE" log --oneline HEAD..@{u} 2>/dev/null | wc -l | tr -d ' ')"
if [ "$BEHIND" = "0" ]; then check "--yes with incoming commits: source up to date after" "0"
else check "--yes with incoming commits: source up to date after" "1"; fi

# 10. --yes runs mock install.sh (sentinel file created in TARGET)
setup_repos
add_upstream_commit
"$LIB" --target "$TARGET" --yes 2>&1 >/dev/null || true
if [ -f "$TARGET/.gsd-recipe/.install-ran" ]; then check "--yes runs install.sh (sentinel exists)" "0"
else check "--yes runs install.sh (sentinel exists)" "1"; fi

# 11. Records recipe_version in install-report.json
VERSION=""
if [ -f "$TARGET/.gsd-recipe/install-report.json" ]; then
  VERSION="$(python3 -c "import json; print(json.load(open('$TARGET/.gsd-recipe/install-report.json')).get('recipe_version',''))" 2>/dev/null || true)"
  if [ -n "$VERSION" ]; then check "records recipe_version in install-report.json" "0"
  else check "records recipe_version in install-report.json" "1"; fi
else
  check "records recipe_version in install-report.json" "1"
fi

# 12. recipe_version matches source HEAD short sha
EXPECTED="$(git -C "$SOURCE" rev-parse --short HEAD 2>/dev/null || true)"
if [ -n "$VERSION" ] && [ "$VERSION" = "$EXPECTED" ]; then check "recipe_version matches source HEAD short sha" "0"
else check "recipe_version matches source HEAD short sha" "1"; fi

# 13. Refuses non-fast-forward (diverged source)
SOURCE2="$(mktemp -d)"
BARE2="$(mktemp -d)"
TARGET2="$(new_target)"
git init -q "$SOURCE2"
git -C "$SOURCE2" config user.email "test@test" && git -C "$SOURCE2" config user.name "test"
git -C "$SOURCE2" commit --allow-empty -qm "init"
git clone --bare -q "$SOURCE2" "$BARE2" 2>/dev/null
git -C "$SOURCE2" remote add origin "$BARE2"
git -C "$SOURCE2" fetch -q
git -C "$SOURCE2" branch -u origin/main main 2>/dev/null || true
# Push an upstream commit via a second clone
TMPCLONE="$(mktemp -d)"
git clone -q "$BARE2" "$TMPCLONE" 2>/dev/null
git -C "$TMPCLONE" config user.email "test@test" && git -C "$TMPCLONE" config user.name "test"
git -C "$TMPCLONE" commit --allow-empty -qm "upstream1"
git -C "$TMPCLONE" push -q origin main
rm -rf "$TMPCLONE"
# Add local diverging commit in SOURCE2 (making it non-fast-forwardable)
git -C "$SOURCE2" commit --allow-empty -qm "local diverge"
python3 -c "import json; json.dump({'recipe_source': '$SOURCE2'}, open('$TARGET2/.gsd-recipe/config.json','w'))"
mkdir -p "$SOURCE2/.gsd-recipe/scripts"
printf '#!/usr/bin/env bash\necho mock\n' > "$SOURCE2/.gsd-recipe/scripts/install.sh"
chmod +x "$SOURCE2/.gsd-recipe/scripts/install.sh"
"$LIB" --target "$TARGET2" --yes 2>/dev/null && rc=0 || rc=$?
if [ "$rc" != "0" ]; then check "refuses non-fast-forward (diverged source)" "0"
else check "refuses non-fast-forward (diverged source)" "1"; fi

# 14. Output includes "recipe-update: done" on success
setup_repos
add_upstream_commit
OUT="$("$LIB" --target "$TARGET" --yes 2>&1 || true)"
check "output includes 'recipe-update: done' on success" "$(grep_check "$OUT" "recipe-update: done")"

# 15. Error message mentions recipe_source not set
T5="$(new_target)"
python3 -c "import json; json.dump({}, open('$T5/.gsd-recipe/config.json','w'))"
OUT="$("$LIB" --target "$T5" 2>&1 || true)"
check "error message mentions recipe_source not set" "$(grep_check "$OUT" "recipe_source not set")"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
