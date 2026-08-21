---
name: recipe-status
description: "Recipe: read-only status snapshot (TASK-060). Prints branch, PRD/ROADMAP/Epic/phase keys, PLAN/SUMMARY, install/sync hints, then the same next-step as recipe-start. Never writes files."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-status`). No flags required.

Examples:
- `recipe-status`

## B. Prerequisites

- Recipe already installed (this skill is staged at install).
- **Always read-only.** Never invoke other skills. Never mutate the repo.

## C. Tool Usage

1. Find repo root (`git rev-parse --show-toplevel`).
2. Run:

```bash
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/.gsd-recipe/scripts/recipe-status.sh" --target "$ROOT"
```

If missing:

```bash
ROOT="$(git rev-parse --show-toplevel)"
ST="$("$ROOT/.gsd-recipe/scripts/recipe-paths.sh" resolve bench/lib/recipe-status.sh --target "$ROOT")"
bash "$ST" --target "$ROOT"
```

Print stdout **verbatim**. That is the whole answer: snapshot plus next-step block.

3. Do **not** ask Yes/No to run the next command. Point to `recipe-start` if they want that.

## D. Do NOT

- Invoke `recipe-onboard`, `recipe-plan-phase`, or any other skill.
- Hardcode product repo names.
- Dump git status or invent Jira fields not in `.planning/STATE.md`.
</cursor_skill_adapter>

# recipe-status — snapshot + next step (TASK-060)

Type **`recipe-status`** in Cursor Agent for a one-screen read of this checkout.

Shows generic artifacts only: branch, PRD, ROADMAP, knowledge, Epic key, phase-task keys, PLAN/SUMMARY per phase, install Jira check, sync-queue depth — then the same next-step text as `recipe-start` / `recipe-help --next`.

Terminal: `.gsd-recipe/scripts/recipe-status.sh`

To have the agent **run** the next command: `recipe-start`
