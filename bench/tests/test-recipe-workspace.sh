#!/usr/bin/env bash
# Tests for bench/lib/workspace-swap.sh (TASK-059).
# Run: ./bench/tests/test-recipe-workspace.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/workspace-swap.sh"

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

# ── 1. sanitize: / → __ ──────────────────────────────────────────────────────
result="$(bash "$LIB" sanitize feat/my-branch)"
[ "$result" = "feat__my-branch" ]
check "sanitize: / becomes __" "$?"

# ── 2. sanitize: special chars → - ──────────────────────────────────────────
result="$(bash "$LIB" sanitize "feat/my branch@v2")"
[ "$result" = "feat__my-branch-v2" ]
check "sanitize: spaces and @ become -" "$?"

# ── 3. snapshot fails closed on non-git directory ────────────────────────────
NOTGIT="$(mktemp -d)"
bash "$LIB" snapshot main --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "snapshot fails closed on non-git directory" "$?"
rm -rf "$NOTGIT"

# ── 4. snapshot: nothing to snapshot (no .planning, no docs/PRD.md) ──────────
T4="$(new_repo)"
out="$(bash "$LIB" snapshot main --target "$T4" 2>&1)"
echo "$out" | grep -qi "nothing to snapshot"
check "snapshot: exits 0 with 'nothing to snapshot' when no artifacts" "$?"
rm -rf "$T4"

# ── 5. snapshot: copies .planning/ ───────────────────────────────────────────
T5="$(new_repo)"
mkdir -p "$T5/.planning"
echo "phase: 1" > "$T5/.planning/ROADMAP.md"
bash "$LIB" snapshot main --target "$T5" >/dev/null
[ -f "$T5/.gsd-recipe/workspaces/main/.planning/ROADMAP.md" ]
check "snapshot: copies .planning/ contents" "$?"
rm -rf "$T5"

# ── 6. snapshot: copies docs/PRD.md when untracked ──────────────────────────
T6="$(new_repo)"
mkdir -p "$T6/docs"
echo "# PRD" > "$T6/docs/PRD.md"
# PRD.md is untracked (not committed) — snapshot should include it
bash "$LIB" snapshot main --target "$T6" >/dev/null
[ -f "$T6/.gsd-recipe/workspaces/main/docs/PRD.md" ]
check "snapshot: copies untracked docs/PRD.md" "$?"
rm -rf "$T6"

# ── 7. snapshot: does NOT copy docs/PRD.md when committed ────────────────────
T7="$(new_repo)"
mkdir -p "$T7/docs"
echo "# PRD" > "$T7/docs/PRD.md"
git -C "$T7" add docs/PRD.md
git -C "$T7" commit -qm "add prd"
mkdir -p "$T7/.planning" && echo "x" > "$T7/.planning/ROADMAP.md"
bash "$LIB" snapshot main --target "$T7" >/dev/null
[ ! -f "$T7/.gsd-recipe/workspaces/main/docs/PRD.md" ]
check "snapshot: does NOT copy committed docs/PRD.md" "$?"
rm -rf "$T7"

# ── 8. snapshot: creates .branch-name file ───────────────────────────────────
T8="$(new_repo)"
mkdir -p "$T8/.planning" && echo "x" > "$T8/.planning/ROADMAP.md"
bash "$LIB" snapshot "feat/ui-prd" --target "$T8" >/dev/null
content="$(cat "$T8/.gsd-recipe/workspaces/feat__ui-prd/.branch-name")"
[ "$content" = "feat/ui-prd" ]
check "snapshot: .branch-name records original branch name" "$?"
rm -rf "$T8"

# ── 9. snapshot: idempotent (second call overwrites cleanly) ─────────────────
T9="$(new_repo)"
mkdir -p "$T9/.planning"
echo "v1" > "$T9/.planning/ROADMAP.md"
bash "$LIB" snapshot main --target "$T9" >/dev/null
echo "v2" > "$T9/.planning/ROADMAP.md"
bash "$LIB" snapshot main --target "$T9" >/dev/null
content="$(cat "$T9/.gsd-recipe/workspaces/main/.planning/ROADMAP.md")"
[ "$content" = "v2" ]
check "snapshot: idempotent — second call overwrites first" "$?"
rm -rf "$T9"

# ── 10. restore: copies snapshot back to working tree ────────────────────────
T10="$(new_repo)"
mkdir -p "$T10/.planning"
echo "restored" > "$T10/.planning/ROADMAP.md"
bash "$LIB" snapshot main --target "$T10" >/dev/null
rm -rf "$T10/.planning"
[ ! -d "$T10/.planning" ]
bash "$LIB" restore main --target "$T10" >/dev/null
[ -f "$T10/.planning/ROADMAP.md" ]
check "restore: restores .planning/ from snapshot" "$?"
rm -rf "$T10"

# ── 11. restore: no-op (exits 0) when no snapshot exists ─────────────────────
T11="$(new_repo)"
out="$(bash "$LIB" restore "nonexistent-branch" --target "$T11" 2>&1)"
rc=$?
[ "$rc" = "0" ]
check "restore: exits 0 when no snapshot exists" "$?"
echo "$out" | grep -qi "no snapshot\|nothing to restore"
check "restore: prints 'no snapshot' message when none exists" "$?"
rm -rf "$T11"

# ── 12. restore: RECIPE_WORKSPACE_SWAP=0 exits 0 with disabled message ───────
T12="$(new_repo)"
out="$(RECIPE_WORKSPACE_SWAP=0 bash "$LIB" restore main --target "$T12" 2>&1)"
rc=$?
[ "$rc" = "0" ]
check "restore: exits 0 when RECIPE_WORKSPACE_SWAP=0" "$?"
echo "$out" | grep -qi "disabled"
check "restore: prints 'disabled' when RECIPE_WORKSPACE_SWAP=0" "$?"
rm -rf "$T12"

# ── 13. status: lists snapshots ──────────────────────────────────────────────
T13="$(new_repo)"
mkdir -p "$T13/.planning" && echo "x" > "$T13/.planning/ROADMAP.md"
bash "$LIB" snapshot "feat/alpha" --target "$T13" >/dev/null
bash "$LIB" snapshot "feat/beta"  --target "$T13" >/dev/null
out="$(bash "$LIB" status --target "$T13" 2>&1)"
echo "$out" | grep -q "feat/alpha\|feat__alpha"
check "status: lists first snapshot branch" "$?"
echo "$out" | grep -q "feat/beta\|feat__beta"
check "status: lists second snapshot branch" "$?"
rm -rf "$T13"

# ── 14. list: prints snapshot dir names ──────────────────────────────────────
T14="$(new_repo)"
mkdir -p "$T14/.planning" && echo "x" > "$T14/.planning/ROADMAP.md"
bash "$LIB" snapshot "main"     --target "$T14" >/dev/null
bash "$LIB" snapshot "feat/foo" --target "$T14" >/dev/null
out="$(bash "$LIB" list --target "$T14" 2>&1)"
echo "$out" | grep -q "main"
check "list: includes main snapshot" "$?"
echo "$out" | grep -q "feat__foo"
check "list: includes feat__foo snapshot (sanitized)" "$?"
rm -rf "$T14"

# ── 15. snapshot: RECIPE_WORKSPACE_SWAP=0 exits 0 with disabled message ──────
T15="$(new_repo)"
mkdir -p "$T15/.planning" && echo "x" > "$T15/.planning/ROADMAP.md"
out="$(RECIPE_WORKSPACE_SWAP=0 bash "$LIB" snapshot main --target "$T15" 2>&1)"
rc=$?
[ "$rc" = "0" ]
check "snapshot: exits 0 when RECIPE_WORKSPACE_SWAP=0" "$?"
echo "$out" | grep -qi "disabled"
check "snapshot: prints 'disabled' when RECIPE_WORKSPACE_SWAP=0" "$?"
rm -rf "$T15"

# ── 16. archive: preserves old cycle, clears active context, keeps source ─────
T16="$(new_repo)"
mkdir -p "$T16/.planning" "$T16/docs" "$T16/.gsd-recipe"
mkdir -p "$T16/.gsd"
echo "old roadmap" > "$T16/.planning/ROADMAP.md"
echo '{"phase":"old"}' > "$T16/.gsd/dispatch-isolation-sentinel.json"
echo "old prd" > "$T16/docs/PRD.md"
echo "new source" > "$T16/docs/PRD-next.md"
echo '{"status":"ready"}' > "$T16/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
echo '{"phase":"old"}' > "$T16/.gsd-recipe/phase-tasks-queue.jsonl"
echo '{"event":"old"}' > "$T16/.gsd-recipe/sync-ledger.jsonl"
echo '{"tracker":"jira","onboard":{"skip_tracker":true}}' > "$T16/.gsd-recipe/config.json"
RECIPE_WORKSPACE_ARCHIVE_ID=test-run bash "$LIB" archive feat/current \
  --target "$T16" --preserve "$T16/docs/PRD-next.md" >/dev/null
ARCHIVE="$T16/.gsd-recipe/workspace-archives/feat__current/test-run"
[ -f "$ARCHIVE/.planning/ROADMAP.md" ] &&
  [ -f "$ARCHIVE/docs/PRD.md" ] &&
  [ -f "$ARCHIVE/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ] &&
  [ -f "$ARCHIVE/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ -f "$ARCHIVE/.gsd-recipe/sync-ledger.jsonl" ] &&
  [ -f "$ARCHIVE/.gsd/dispatch-isolation-sentinel.json" ]
check "archive: preserves prior planning, PRD, GSD runtime, tracker state, and knowledge marker" "$?"
[ ! -d "$T16/.planning" ] &&
  [ ! -f "$T16/docs/PRD.md" ] &&
  [ ! -f "$T16/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ] &&
  [ ! -f "$T16/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ ! -f "$T16/.gsd-recipe/sync-ledger.jsonl" ] &&
  [ ! -d "$T16/.gsd" ]
check "archive: clears active prior-cycle planning and tracker context" "$?"
[ -f "$T16/docs/PRD-next.md" ]
check "archive: --preserve keeps the incoming PRD source" "$?"
python3 - "$T16/.gsd-recipe/config.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["tracker"] == "jira"
assert "skip_tracker" not in d.get("onboard", {})
PY
check "archive: clears stale skip_tracker and preserves unrelated config" "$?"
rm -rf "$T16"

# ── 17. branch restore --clear prevents old planning leakage ─────────────────
T17="$(new_repo)"
mkdir -p "$T17/.planning" "$T17/docs"
mkdir -p "$T17/.gsd"
echo "branch-a" > "$T17/.planning/ROADMAP.md"
echo "branch-a" > "$T17/docs/PRD.md"
mkdir -p "$T17/.gsd-recipe"
echo "branch-a" > "$T17/.gsd-recipe/phase-tasks-queue.jsonl"
echo "branch-a" > "$T17/.gsd-recipe/sync-ledger.jsonl"
echo "branch-a" > "$T17/.gsd/dispatch-isolation-sentinel.json"
bash "$LIB" snapshot branch-a --target "$T17" >/dev/null
bash "$LIB" restore branch-b --target "$T17" --clear >/dev/null
[ ! -d "$T17/.planning" ] &&
  [ ! -f "$T17/docs/PRD.md" ] &&
  [ ! -f "$T17/.gsd-recipe/phase-tasks-queue.jsonl" ] &&
  [ ! -f "$T17/.gsd-recipe/sync-ledger.jsonl" ] &&
  [ ! -d "$T17/.gsd" ]
check "restore --clear: new branch cannot inherit previous planning or tracker context" "$?"
rm -rf "$T17"

# ── 18. archive: stale skip_tracker alone is archived and cleared ─────────────
T18="$(new_repo)"
mkdir -p "$T18/.gsd-recipe"
echo '{"onboard":{"skip_tracker":true}}' > "$T18/.gsd-recipe/config.json"
RECIPE_WORKSPACE_ARCHIVE_ID=skip-only bash "$LIB" archive main --target "$T18" >/dev/null
[ -f "$T18/.gsd-recipe/workspace-archives/main/skip-only/.gsd-recipe/onboard-state.json" ]
check "archive: preserves stale skip_tracker when it is the only cycle state" "$?"
python3 - "$T18/.gsd-recipe/config.json" <<'PY'
import json, sys
assert "skip_tracker" not in json.load(open(sys.argv[1])).get("onboard", {})
PY
check "archive: clears skip_tracker-only active state" "$?"
rm -rf "$T18"

# ── 19. archive: malformed config fails before clearing active files ──────────
T19="$(new_repo)"
mkdir -p "$T19/.planning" "$T19/.gsd-recipe"
echo "keep me" > "$T19/.planning/ROADMAP.md"
echo '{bad json' > "$T19/.gsd-recipe/config.json"
bash "$LIB" archive main --target "$T19" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ] && [ -f "$T19/.planning/ROADMAP.md" ]
check "archive: invalid config fails closed before active context is cleared" "$?"
rm -rf "$T19"

# ── 20. snapshot/restore round-trips all initiative-local recipe state ────────
T20="$(new_repo)"
mkdir -p "$T20/.gsd-recipe"
mkdir -p "$T20/.gsd"
echo "queue-a" > "$T20/.gsd-recipe/phase-tasks-queue.jsonl"
echo "ledger-a" > "$T20/.gsd-recipe/sync-ledger.jsonl"
echo '{"status":"ready"}' > "$T20/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
echo '{"tracker":"jira","onboard":{"skip_tracker":true}}' > "$T20/.gsd-recipe/config.json"
echo "sentinel-a" > "$T20/.gsd/dispatch-isolation-sentinel.json"
bash "$LIB" snapshot branch-a --target "$T20" >/dev/null
rm -f "$T20/.gsd-recipe/"{phase-tasks-queue.jsonl,sync-ledger.jsonl,KNOWLEDGE-BOOTSTRAPPED}
rm -rf "$T20/.gsd"
echo '{"tracker":"jira"}' > "$T20/.gsd-recipe/config.json"
bash "$LIB" restore branch-a --target "$T20" --clear >/dev/null
grep -q "queue-a" "$T20/.gsd-recipe/phase-tasks-queue.jsonl" &&
  grep -q "ledger-a" "$T20/.gsd-recipe/sync-ledger.jsonl" &&
  [ -f "$T20/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ] &&
  grep -q "sentinel-a" "$T20/.gsd/dispatch-isolation-sentinel.json"
check "snapshot/restore: GSD runtime, tracker queue, sync ledger, and readiness marker round-trip" "$?"
python3 - "$T20/.gsd-recipe/config.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["tracker"] == "jira"
assert d["onboard"]["skip_tracker"] is True
PY
check "snapshot/restore: onboard.skip_tracker round-trips without replacing shared config" "$?"
rm -rf "$T20"

# ── 21. PRD-*.md alone is enough to create a snapshot ────────────────────────
T21="$(new_repo)"
mkdir -p "$T21/docs"
echo "source only" > "$T21/docs/PRD-next.md"
bash "$LIB" snapshot main --target "$T21" >/dev/null
[ -f "$T21/.gsd-recipe/workspaces/main/docs/PRD-next.md" ]
check "snapshot: untracked PRD-*.md alone is captured" "$?"
rm -rf "$T21"

# ── 21b. Gitignored PRDs still round-trip; a committed PRD is left alone ─────
T21B="$(new_repo)"
mkdir -p "$T21B/docs"
printf 'docs/PRD.md\ndocs/PRD-*.md\n' > "$T21B/.gitignore"
echo "committed product prd" > "$T21B/docs/PRD-product.md"
git -C "$T21B" add -f .gitignore docs/PRD-product.md
git -C "$T21B" commit -qm "track a product PRD"
echo "generated" > "$T21B/docs/PRD.md"
echo "generated source" > "$T21B/docs/PRD-next.md"
bash "$LIB" snapshot main --target "$T21B" >/dev/null
[ -f "$T21B/.gsd-recipe/workspaces/main/docs/PRD.md" ] &&
  [ -f "$T21B/.gsd-recipe/workspaces/main/docs/PRD-next.md" ]
check "snapshot: gitignored PRDs are captured (not skipped as excluded)" "$?"
[ ! -f "$T21B/.gsd-recipe/workspaces/main/docs/PRD-product.md" ]
check "snapshot: a committed PRD is left to the product, not the initiative" "$?"
rm -f "$T21B/docs/PRD.md" "$T21B/docs/PRD-next.md"
bash "$LIB" restore main --target "$T21B" --clear >/dev/null
grep -q "generated" "$T21B/docs/PRD.md" &&
  grep -q "generated source" "$T21B/docs/PRD-next.md" &&
  grep -q "committed product prd" "$T21B/docs/PRD-product.md"
check "restore: gitignored PRDs come back and the committed one is untouched" "$?"
rm -rf "$T21B"

# ── 22. malformed config blocks snapshot before any later clear can occur ────
T22="$(new_repo)"
mkdir -p "$T22/.planning" "$T22/.gsd-recipe"
echo "keep me" > "$T22/.planning/ROADMAP.md"
echo '{bad json' > "$T22/.gsd-recipe/config.json"
bash "$LIB" snapshot main --target "$T22" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ] && [ -f "$T22/.planning/ROADMAP.md" ]
check "snapshot: invalid config fails closed without touching active context" "$?"
rm -rf "$T22"

# ── summary ───────────────────────────────────────────────────────────────────
echo
echo "Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
