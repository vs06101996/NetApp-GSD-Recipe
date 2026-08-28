#!/usr/bin/env bash
# Regression test for bench/lib/recipe-paths.sh — the permanent fix for the
# "script not found on external --target" class of bug install.sh's own
# --target mode otherwise reintroduces for every recipe-*/install-recipe-*.sh
# path that isn't independently duplicated into every installed target.
# Matches the convention of bench/tests/test-install-tracker-sync.sh.
# Run: ./bench/tests/test-recipe-paths.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESOLVER="$REPO_ROOT/bench/lib/recipe-paths.sh"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install.sh"

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

# 1. Fresh external --target install writes recipe_source pointing at REPO_ROOT
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null

python3 -c "
import json, os, sys
d = json.load(open('$TARGET1/.gsd-recipe/config.json'))
assert os.path.realpath(d.get('recipe_source', '')) == os.path.realpath('$REPO_ROOT'), d
" && rc=0 || rc=$?
check "external --target install writes recipe_source pointing at the recipe source repo" "$rc"

[ -x "$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" ]
check "recipe-paths.sh is staged and executable on an external target" "$?"

RESOLVED="$("$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" resolve .gsd-recipe/scripts/install-recipe-settle.sh --target "$TARGET1")" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ "$RESOLVED" = "$REPO_ROOT/.gsd-recipe/scripts/install-recipe-settle.sh" ]
check "resolve() falls back to recipe_source for a script never staged locally" "$?"

RESOLVED_RUNNER="$("$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" resolve bench/runners/create-phase-tasks.sh --target "$TARGET1")" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ "$RESOLVED_RUNNER" = "$REPO_ROOT/bench/runners/create-phase-tasks.sh" ]
check "resolve() falls back to recipe_source for a bench/runners/ path never staged locally" "$?"

SRC_OUT="$("$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" source --target "$TARGET1")" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ "$SRC_OUT" = "$REPO_ROOT" ]
check "source subcommand prints recipe_source verbatim" "$?"

# 2. resolve() prefers a locally-staged copy over recipe_source when both exist
mkdir -p "$TARGET1/.gsd-recipe/scripts"
printf '#!/usr/bin/env bash\necho local-copy\n' > "$TARGET1/.gsd-recipe/scripts/install-recipe-settle.sh"
chmod +x "$TARGET1/.gsd-recipe/scripts/install-recipe-settle.sh"
RESOLVED_LOCAL="$("$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" resolve .gsd-recipe/scripts/install-recipe-settle.sh --target "$TARGET1")" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ "$RESOLVED_LOCAL" = "$TARGET1/.gsd-recipe/scripts/install-recipe-settle.sh" ]
check "resolve() prefers a locally-staged copy over recipe_source when both exist" "$?"
rm -f "$TARGET1/.gsd-recipe/scripts/install-recipe-settle.sh"

# 3. resolve() fails closed (non-zero, no output-as-path) for a path that
#    exists nowhere — not locally, not under recipe_source.
OUT3="$("$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" resolve bench/runners/does-not-exist.sh --target "$TARGET1" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && printf '%s' "$OUT3" | grep -qi "could not resolve"
check "resolve() fails closed with an actionable message for an unresolvable path" "$?"

# 4. Self-install (TARGET == the recipe's own source repo) never writes
#    recipe_source — everything is local already.
COPY="$(mktemp -d)/gsd-benchmark-copy"
mkdir -p "$(dirname "$COPY")"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && rm -rf .git && git init -q && git add -A && git commit -qm init)
(cd "$COPY" && ./.gsd-recipe/scripts/install.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install (copy of the source repo installed into itself) does not error" "$rc"

python3 -c "
import json
d = json.load(open('$COPY/.gsd-recipe/config.json'))
assert 'recipe_source' not in d, d
" && rc=0 || rc=$?
check "self-install never writes recipe_source (everything already local)" "$rc"

RESOLVED_SELF="$("$COPY/.gsd-recipe/scripts/recipe-paths.sh" resolve .gsd-recipe/scripts/install-recipe-settle.sh --target "$COPY")" && rc=0 || rc=$?
[ "$rc" = "0" ] && [ "$RESOLVED_SELF" = "$COPY/.gsd-recipe/scripts/install-recipe-settle.sh" ]
check "resolve() finds a self-install target's own local copy with no recipe_source set" "$?"

# 5. install.sh --verify reports recipe-paths.sh + recipe_source checks
VERIFY_OUT="$("$INSTALLER" --verify --target "$TARGET1" 2>&1)" || true
printf '%s' "$VERIFY_OUT" | grep -q "recipe-paths.sh staged — pass"
check "install.sh --verify reports recipe-paths.sh staged as pass" "$?"
printf '%s' "$VERIFY_OUT" | grep -q "recipe_source resolvable (self-install or recorded in config.json) — pass"
check "install.sh --verify reports a valid recipe_source as pass" "$?"

VERIFY_OUT_SELF="$(cd "$COPY" && ./.gsd-recipe/scripts/install.sh --verify 2>&1)" || true
printf '%s' "$VERIFY_OUT_SELF" | grep -q "recipe_source resolvable (self-install or recorded in config.json) — pass"
check "install.sh --verify reports an unset recipe_source as pass on self-install" "$?"

rm -rf "$TARGET1" "$(dirname "$COPY")"

echo
echo "recipe-paths.sh tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
