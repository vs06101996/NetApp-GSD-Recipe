# TASK-059 Unbiased Tester Report
**Date:** 2026-08-26
**Tester persona:** Platform engineer (no implementer context)
**Branch tested:** agent-a6961a778958026dc worktree (feature implementation)

## Setup

Reset sandbox with `setup-recipe-sandbox.sh --reset`, then installed recipe from the feature worktree using `install-recipe-to-target.sh --yes --no-open-start`. Install completed without errors. All five recipe-workspace files were confirmed present:
- `.gsd-recipe/lib/workspace-swap.sh`
- `.git/hooks/post-checkout` (executable)
- `.cursor/skills/recipe-workspace/SKILL.md`
- `.cursor/hooks/workspace-swap-cursor-fallback.sh`
- `.cursor/hooks.json` (with postToolUse/Bash entry)

## Results

| AC | Description | Result | Notes |
|----|-------------|--------|-------|
| AC-1 | git switch via Shell snapshots + restores | PARTIAL PASS | `.planning/` content snapshotted and restored correctly. `docs/PRD.md` snapshot+restore also works when branches don't have a committed version of that file. However, attempting to switch from a branch with an untracked `docs/PRD.md` to a branch where that file IS committed causes git to refuse the switch entirely (before the hook fires). See edge case detail below. |
| AC-2 | No snapshot on first checkout of branch with no snapshot | FAIL | When switching from `main` (which has `.planning/` content) to `feat/backend-prd` for the first time, the hook runs `restore feat/backend-prd` which is a no-op (no snapshot). But the hook never cleans up main's `.planning/` files. Result: main's entire `.planning/` tree is present on `feat/backend-prd`'s working tree. The "swap" is incomplete — old branch planning files leak into the new branch. |
| AC-3 | `RECIPE_WORKSPACE_SWAP=0` is a complete no-op | PASS | With `RECIPE_WORKSPACE_SWAP=0 git switch main`, the hook skipped all snapshot and restore logic. No snapshot was written, working tree was unchanged. |
| AC-4 | File-only checkout does NOT swap | PASS | `git checkout HEAD -- README.md` did not modify any snapshot directories (verified via mtime comparison before/after in the same shell call). Hook correctly checks `$3 = "1"` flag. |
| AC-5 | `recipe-workspace status` shows snapshots | PASS | `workspace-swap.sh status` output correctly showed `current branch: feat/ui-prd` and listed all 3 snapshots with both original branch name and sanitized directory name (e.g. `feat/ui-prd (dir: feat__ui-prd)`). |
| AC-6 | Manual `save` and `restore` work | PASS | Manual `snapshot feat/ui-prd` captured `.planning/` contents including subdirectories. After deleting `.planning/`, `restore feat/ui-prd` correctly recreated the directory tree with all files. |
| AC-7 | Installer `--verify` exits 0 | PASS | `install-recipe-workspace.sh --verify --target ~/Projects/recipe-sandbox` printed `verify PASS — all files present` and exited 0. |
| AC-8 | Committed `docs/PRD.md` is NOT snapshotted | PASS | On `feat/ui-prd` where `docs/PRD.md` is a tracked (committed) file, running `snapshot feat/ui-prd` did not include `docs/` in the snapshot. The `git ls-files --error-unmatch` guard works correctly. |

## Surprises / edge cases found

### 1. AC-2 FAIL: Planning files leak between branches (critical)

**Observed:** When switching from `main` (which has `.planning/` content) to a branch that has never been snapshotted, the old branch's `.planning/` directory remains in the working tree untouched. Only `cmd_restore` clears `.planning/` (via `rm -rf "$TARGET/.planning"` before the copy), and that line is only reached when a snapshot exists. With no snapshot, there is no cleanup.

**Impact:** The per-branch isolation guarantee — the core value of this feature — breaks on first checkout of any new branch. A developer checking out a fresh branch sees the previous branch's planning state. Agent tools reading `.planning/` would operate on wrong context.

**Reproduction:**
```bash
# On main with .planning/ content
git -C ~/Projects/recipe-sandbox switch feat/backend-prd
# Hook prints: "no snapshot for 'feat/backend-prd' — nothing to restore"
# .planning/ from main is still fully present in feat/backend-prd's working tree
ls ~/Projects/recipe-sandbox/.planning/   # shows main's files
```

**Expected behavior:** When switching to a branch with no snapshot, `.planning/` should be cleared (clean slate). The restore of "nothing" should mean an empty `.planning/`, not a carry-over from the previous branch.

**Suggested fix:** In the `post-checkout` hook, clear the working-tree planning dirs after snapshotting the old branch, regardless of whether the new branch has a snapshot:
```bash
bash "$LIB" snapshot "$OLD_BRANCH" --target "$ROOT"
# Clear working tree unconditionally before restore
rm -rf "$ROOT/.planning"
# Only remove untracked docs/PRD.md (not a committed one)
if [ -f "$ROOT/docs/PRD.md" ]; then
  if ! git -C "$ROOT" ls-files --error-unmatch "docs/PRD.md" >/dev/null 2>&1; then
    rm -f "$ROOT/docs/PRD.md"
  fi
fi
bash "$LIB" restore  "$NEW_BRANCH" --target "$ROOT"
```
Alternatively, `cmd_restore` itself could clear `.planning/` unconditionally (even when no snapshot exists).

### 2. docs/PRD.md collision blocks git switch (usability issue, not a hook bug)

**Observed:** When `main` has an untracked `docs/PRD.md` and the target branch (`feat/ui-prd`) has a committed `docs/PRD.md`, git refuses the branch switch entirely:
```
error: The following untracked working tree files would be overwritten by checkout:
        docs/PRD.md
Please move or remove them before you switch branches.
Aborting
```
The post-checkout hook never fires in this case. The feature cannot help here since git blocks it upstream.

**Impact:** A workflow where an engineer writes `docs/PRD.md` on `main` then tries to switch to a feature branch that has its own committed PRD will be blocked. Users will need to manually remove or stash the untracked PRD before switching.

**Note:** This is a git architectural constraint, not a bug in the implementation. However, it is a real operational friction point that should be documented as a known limitation in the SKILL.md.

### 3. Cursor fallback hook uses sentinel file (design observation, positive)

The `.cursor/hooks/workspace-swap-cursor-fallback.sh` uses a `.gsd-recipe/.last-branch` sentinel file to detect branch changes that bypass the git hook (e.g. Cursor UI branch picker via libgit2). The first Bash tool call after a libgit2 branch switch will trigger the swap. Clean and resilient design. Not tested in a live Cursor UI environment (only tested via shell git commands).

### 4. Snapshot does not remove files from working tree after copy (design root cause of AC-2)

`cmd_snapshot` copies `.planning/` into the snapshot store but does not delete it from the working tree. This is intentional for the snapshot operation itself, but the `post-checkout` hook relies on `cmd_restore` to do the cleanup. Since `cmd_restore` exits early when no snapshot exists (`exit 0` at line 149), the cleanup never happens for fresh branches.

## Verdict: FAIL

**Blocker:** AC-2 FAIL. Planning files from the previous branch are not cleaned up when switching to a branch that has no snapshot. This directly breaks the core per-branch isolation guarantee of TASK-059.

**Passing:** AC-1 (core behavior), AC-3, AC-4, AC-5, AC-6, AC-7, AC-8 all pass. The infrastructure (hook installation, lib correctness, snapshot/restore mechanics, flag gating, committed-file exclusion) is sound.

**To ship:** Fix the cleanup-on-no-snapshot gap in either the `post-checkout` hook or in `cmd_restore`, then re-test AC-2.

---

## Remediation retest — 2026-09-06

The blocker above was fixed before integration:

- `post-checkout` now calls `restore <new-branch> --clear`.
- `--clear` removes the previous branch's `.planning/` and untracked `docs/PRD*.md`
  before checking whether the destination snapshot exists.
- A branch with no snapshot therefore starts clean; a branch with a snapshot restores
  only its own context.

Automated evidence now includes a real installed-hook branch-switch test in
`bench/tests/test-install-recipe-workspace.sh`: create distinct branch contexts, invoke
`git switch`, assert the old branch snapshot, assert the fresh branch is empty, then
switch back and assert restoration. Direct `restore --clear` and fresh-onboarding archive
coverage lives in `bench/tests/test-recipe-workspace.sh`.

**Retest verdict: PASS.** AC-2 is closed; the original observations remain above as the
defect history.
