---
name: recipe-update
description: "Recipe: in-place upgrade to latest recipe (TASK-058). Pulls the recipe source and restages skills/scripts/templates without wiping .planning/, .knowledge/, or custom .templates/."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-update`). Optional flags: `--dry-run`, `--check`.

Examples:
- `recipe-update` — fetch, preview, confirm, pull, restage
- `recipe-update --dry-run` — fetch + preview only, no changes made
- `recipe-update --check` — same as `--dry-run`

## B. Prerequisites

- Recipe installed in this repo (this skill is staged at install).
- `.gsd-recipe/config.json` contains `recipe_source` pointing to the `gsd-benchmark` clone used during install. Set by `install-recipe-to-target.sh`; re-run it if missing.
- Recipe source working tree must be clean (no uncommitted changes).
- Network access to the recipe source's remote (for `git fetch`).

## C. Tool Usage

1. Find repo root:

```bash
ROOT="$(git rev-parse --show-toplevel)"
LIB="$ROOT/.gsd-recipe/lib/recipe-update.sh"
```

2. If `LIB` is missing: stop and print "recipe-update: lib not found — re-run install or `install-recipe-to-target.sh --target $ROOT`."

3. Run the lib, passing through any operator flags:

```bash
bash "$LIB" --target "$ROOT"
# or with flags:
bash "$LIB" --target "$ROOT" --dry-run
bash "$LIB" --target "$ROOT" --check
```

4. Report the output verbatim to the operator.

## D. What It Does NOT Do

- Does NOT wipe `.planning/`, `STATE.md`, Epic/phase keys, `.knowledge/` human files, or customized `.templates/` (those are never touched by `install.sh --yes`).
- Does NOT push anything.
- Does NOT touch the product repo's `git history` — only restages recipe-owned Cursor skill files and scripts.
- Does NOT auto-restage. `recipe-start` may run `--check` via `recipe-update-nudge.sh`
  (print-only). Restage only when the operator invokes `recipe-update`.
</cursor_skill_adapter>
