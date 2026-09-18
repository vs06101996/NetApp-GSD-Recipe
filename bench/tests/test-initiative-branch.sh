#!/usr/bin/env bash
# Tests for bench/lib/initiative-branch.sh (TASK-061).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/initiative-branch.sh"
WORKSPACE_LIB="$REPO_ROOT/bench/lib/workspace-swap.sh"

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
  git -C "$dir" commit --allow-empty -qm init
  printf '.gsd-recipe/\n' >> "$dir/.git/info/exclude"
  mkdir -p "$dir/.gsd-recipe/lib"
  cp "$WORKSPACE_LIB" "$dir/.gsd-recipe/lib/workspace-swap.sh"
  chmod +x "$dir/.gsd-recipe/lib/workspace-swap.sh"
  printf '%s\n' "$dir"
}

# 1. Fail closed outside a git repo.
T1="$(mktemp -d)"
bash "$LIB" validate gsd/one --target "$T1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: refuses a non-git target" "$?"
rm -rf "$T1"

# 2. Reject invalid names.
T2="$(new_repo)"
bash "$LIB" validate "bad branch" --target "$T2" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: rejects invalid branch names" "$?"
rm -rf "$T2"

# 3. Reject an existing local branch.
T3="$(new_repo)"
git -C "$T3" branch gsd/existing
bash "$LIB" validate gsd/existing --target "$T3" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: rejects an existing local initiative branch" "$?"
rm -rf "$T3"

# 4. Reject an existing origin branch.
T4="$(new_repo)"
git -C "$T4" update-ref refs/remotes/origin/gsd/existing HEAD
bash "$LIB" validate gsd/existing --target "$T4" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: rejects an existing remote initiative branch" "$?"
rm -rf "$T4"

# 5. Reject dirty product state, but ignored recipe state remains eligible.
T5="$(new_repo)"
echo "dirty" > "$T5/product.txt"
bash "$LIB" validate gsd/dirty --target "$T5" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: rejects dirty product files" "$?"
rm -f "$T5/product.txt"
printf '.planning/\n.gsd-recipe/\n' > "$T5/.gitignore"
git -C "$T5" add .gitignore
git -C "$T5" commit -qm ignore
mkdir -p "$T5/.planning"
echo "old" > "$T5/.planning/ROADMAP.md"
mkdir -p "$T5/docs" "$T5/.gsd"
echo "generated prd" > "$T5/docs/PRD.md"
echo '{"phase":"1"}' > "$T5/.gsd/dispatch-isolation-sentinel.json"
bash "$LIB" validate gsd/clean --target "$T5" >/dev/null
check "validate: permits gitignored and generated initiative state" "$?"
rm -rf "$T5"

# 5b. Recipe-install dirt (.gitignore + Cursor recipe hooks/rules) is eligible.
T5B="$(new_repo)"
printf '# product\n' > "$T5B/.gitignore"
git -C "$T5B" add .gitignore
git -C "$T5B" commit -qm ignore
printf '.planning/\n.gsd-recipe/\n.cursor/rules/recipe-*\n' >> "$T5B/.gitignore"
mkdir -p "$T5B/.cursor/hooks" "$T5B/.cursor/rules"
echo '{"hooks":{}}' > "$T5B/.cursor/hooks.json"
echo "hook" > "$T5B/.cursor/hooks/fotw-observer-nudge.sh"
echo "swap" > "$T5B/.cursor/hooks/workspace-swap-cursor-fallback.sh"
echo "rule" > "$T5B/.cursor/rules/recipe-command-surface.mdc"
bash "$LIB" validate feat/from-github-issue --target "$T5B" >/dev/null
check "validate: permits recipe-install .gitignore and Cursor hook/rule dirt" "$?"
echo "product" > "$T5B/src.go"
bash "$LIB" validate feat/from-github-issue --target "$T5B" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: still rejects other untracked product files" "$?"
rm -rf "$T5B"

# 6. Tracked planning is never deleted or treated as swappable state.
T6="$(new_repo)"
mkdir -p "$T6/.planning"
echo "tracked" > "$T6/.planning/ROADMAP.md"
git -C "$T6" add -f .planning/ROADMAP.md
git -C "$T6" commit -qm "track planning"
bash "$LIB" validate gsd/tracked-planning --target "$T6" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ] && [ -f "$T6/.planning/ROADMAP.md" ]
check "validate: rejects tracked initiative state without deleting it" "$?"
rm -rf "$T6"

# 7. Missing workspace runtime fails closed.
T6="$(new_repo)"
rm -f "$T6/.gsd-recipe/lib/workspace-swap.sh"
bash "$LIB" validate gsd/no-runtime --target "$T6" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: missing workspace runtime fails closed" "$?"
rm -rf "$T6"

# 8. Create snapshots every initiative-local artifact and starts clean.
T7="$(new_repo)"
printf '.planning/\n.gsd-recipe/\ndocs/PRD*.md\n' > "$T7/.gitignore"
git -C "$T7" add .gitignore
git -C "$T7" commit -qm ignore
OLD_BRANCH="$(git -C "$T7" branch --show-current)"
mkdir -p "$T7/.planning" "$T7/docs" "$T7/.gsd-recipe"
mkdir -p "$T7/.gsd"
echo "old roadmap" > "$T7/.planning/ROADMAP.md"
echo "old prd" > "$T7/docs/PRD.md"
echo '{"phase":"1"}' > "$T7/.gsd/dispatch-isolation-sentinel.json"
echo "old queue" > "$T7/.gsd-recipe/phase-tasks-queue.jsonl"
echo "old ledger" > "$T7/.gsd-recipe/sync-ledger.jsonl"
echo '{"status":"ready"}' > "$T7/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
echo '{"tracker":"jira","onboard":{"skip_tracker":true}}' > "$T7/.gsd-recipe/config.json"

bash "$LIB" create gsd/initiative-one --target "$T7" >/dev/null
[ "$(git -C "$T7" branch --show-current)" = "gsd/initiative-one" ]
check "create: checks out the requested initiative branch" "$?"

SNAPSHOT="$T7/.gsd-recipe/workspaces/$OLD_BRANCH"
[ -f "$SNAPSHOT/.planning/ROADMAP.md" ] &&
  [ -f "$SNAPSHOT/docs/PRD.md" ] &&
  [ -f "$SNAPSHOT/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ -f "$SNAPSHOT/.gsd-recipe/sync-ledger.jsonl" ] &&
  [ -f "$SNAPSHOT/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ] &&
  [ -f "$SNAPSHOT/.gsd-recipe/onboard-state.json" ] &&
  [ -f "$SNAPSHOT/.gsd/dispatch-isolation-sentinel.json" ]
check "create: snapshots planning, PRD, GSD runtime, tracker queue/ledger, and readiness state" "$?"

[ ! -d "$T7/.planning" ] &&
  [ ! -f "$T7/docs/PRD.md" ] &&
  [ ! -f "$T7/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ ! -f "$T7/.gsd-recipe/sync-ledger.jsonl" ] &&
  [ ! -f "$T7/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ] &&
  [ ! -d "$T7/.gsd" ]
check "create: new initiative branch starts without prior initiative files" "$?"
python3 - "$T7/.gsd-recipe/config.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["tracker"] == "jira"
assert "skip_tracker" not in d.get("onboard", {})
PY
check "create: clears initiative-scoped config but preserves shared config" "$?"

# 9. A second initiative snapshots the first, independently.
mkdir -p "$T7/.planning" "$T7/.gsd-recipe"
echo "initiative one" > "$T7/.planning/ROADMAP.md"
echo "initiative one queue" > "$T7/.gsd-recipe/phase-tasks-queue.jsonl"
echo "initiative one product change" > "$T7/initiative-one-product.txt"
git -C "$T7" add initiative-one-product.txt
git -C "$T7" commit -qm "initiative one product change"
bash "$LIB" create gsd/initiative-two --target "$T7" >/dev/null
[ "$(git -C "$T7" branch --show-current)" = "gsd/initiative-two" ] &&
  [ -f "$T7/.gsd-recipe/workspaces/gsd__initiative-one/.planning/ROADMAP.md" ] &&
  [ ! -d "$T7/.planning" ] &&
  [ ! -f "$T7/initiative-one-product.txt" ]
check "create: initiative two starts from base, excluding initiative one's product commit and recipe state" "$?"

# 10. Switching back restores the exact first initiative.
bash "$WORKSPACE_LIB" snapshot gsd/initiative-two --target "$T7" >/dev/null
RECIPE_WORKSPACE_SWAP=0 git -C "$T7" switch -q gsd/initiative-one
bash "$WORKSPACE_LIB" restore gsd/initiative-one --target "$T7" --clear >/dev/null
grep -q "initiative one" "$T7/.planning/ROADMAP.md" &&
  grep -q "initiative one queue" "$T7/.gsd-recipe/phase-tasks-queue.jsonl"
check "restore: returning to initiative one restores its planning and tracker queue" "$?"
rm -rf "$T7"

# 11. Base selection: explicit --base wins, ambiguity is reported not guessed.
T8="$(new_repo)"
TRUNK="$(git -C "$T8" branch --show-current)"
RECIPE_WORKSPACE_SWAP=0 git -C "$T8" switch -q -c dev
git -C "$T8" commit --allow-empty -qm "dev-only integration commit"

bash "$LIB" validate feat/from-dev --target "$T8" --base dev |
  grep -q "ready to create 'feat/from-dev' from 'dev'"
check "validate: --base overrides the default base resolution" "$?"

! bash "$LIB" validate feat/from-dev --target "$T8" --base dev | grep -q "base-ambiguous"
check "validate: an explicit --base suppresses the ambiguity question" "$?"

bash "$LIB" validate feat/from-dev --target "$T8" --base no/such/ref >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate: rejects a --base that does not resolve to a commit" "$?"

NOTE="$(bash "$LIB" validate feat/from-dev --target "$T8")"
printf '%s\n' "$NOTE" | grep -q "ready to create 'feat/from-dev' from '$TRUNK'" &&
  printf '%s\n' "$NOTE" | grep -q "base-ambiguous current='dev' default='$TRUNK' ahead=1 recommend='dev'"
check "validate: reports base ambiguity when on an integration branch ahead of the default" "$?"

RECIPE_WORKSPACE_SWAP=0 git -C "$T8" switch -q -c feat/prior-initiative
git -C "$T8" commit --allow-empty -qm "prior initiative commit"
bash "$LIB" validate feat/next-initiative --target "$T8" |
  grep -q "recommend='$TRUNK'"
check "validate: recommends the default base when the current branch is a prior initiative" "$?"

RECIPE_WORKSPACE_SWAP=0 git -C "$T8" switch -q "$TRUNK"
! bash "$LIB" validate feat/from-trunk --target "$T8" | grep -q "base-ambiguous"
check "validate: stays silent when already on the default base" "$?"

bash "$LIB" create feat/cut-from-dev --target "$T8" --base dev >/dev/null 2>&1
[ "$(git -C "$T8" branch --show-current)" = "feat/cut-from-dev" ] &&
  git -C "$T8" log -1 --format=%s | grep -q "dev-only integration commit"
check "create: --base cuts the new branch from the requested ref" "$?"
rm -rf "$T8"

echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
