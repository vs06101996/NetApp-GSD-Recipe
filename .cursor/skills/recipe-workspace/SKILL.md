---
name: recipe-workspace
description: "Recipe: per-branch initiative workspace swap (TASK-059/061). Manual save/restore/status plus archive. Planning, GSD runtime, PRDs, tracker queue/ledger, and readiness state follow their initiative branch."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name: `recipe-workspace <save|restore|archive|status>`

- `recipe-workspace save` — snapshot current branch's initiative-local recipe state to `.gsd-recipe/workspaces/<branch>/`
- `recipe-workspace restore` — restore snapshot for current branch (no-op if none exists)
- `recipe-workspace archive` — archive and clear the current branch's active onboarding
  context (`.planning/`, `.gsd/`, untracked `docs/PRD*.md`, tracker queue/ledger, knowledge-ready
  marker). This is the `recipe-onboard <source> --no-branch` switch-out primitive.
- `recipe-workspace status` — list all branch snapshots and show current branch

## B. Prerequisites

- Recipe installed; `workspace-swap.sh` staged at `.gsd-recipe/lib/workspace-swap.sh`
- `RECIPE_WORKSPACE_SWAP` env var unset or not `0` (if set to `0`, swap is disabled and this skill reports that)

## C. Tool Usage

1. Find repo root:

```bash
ROOT="$(git rev-parse --show-toplevel)"
LIB="$ROOT/.gsd-recipe/lib/workspace-swap.sh"
```

2. Check the lib is present:

```bash
[ -f "$LIB" ] || echo "recipe-workspace: workspace-swap.sh not found — re-run install"
```

3. Dispatch on the subcommand:

For `save`:
```bash
bash "$LIB" snapshot "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" --target "$ROOT"
```

For `restore`:
```bash
bash "$LIB" restore "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" --target "$ROOT"
```

For `archive`, first preview the paths that will be archived/cleared and ask a
non-skippable Yes/No question. On Yes:
```bash
bash "$LIB" archive "$(git -C "$ROOT" rev-parse --abbrev-ref HEAD)" --target "$ROOT"
```

For `status`:
```bash
bash "$LIB" status --target "$ROOT"
```

4. Report the output to the operator verbatim.

## D. Error Handling

- If `workspace-swap.sh` is missing: print `recipe-workspace: workspace-swap.sh not found — re-run install` and stop.
- If `RECIPE_WORKSPACE_SWAP=0`: the lib prints a disabled message and exits 0 — relay that to the operator.
- If `restore` finds no snapshot: lib prints `no snapshot for '<branch>' — nothing to restore` and exits 0 — relay that.
- If `save` finds no initiative-local state: lib prints `nothing to snapshot` and exits 0 — relay that.
- Never run `archive` without the operator's explicit confirmation. It preserves the
  previous context under `.gsd-recipe/workspace-archives/` before clearing active files.
</cursor_skill_adapter>
