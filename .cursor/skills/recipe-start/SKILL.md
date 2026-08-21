---
name: recipe-start
description: "Recipe: first-run coach (TASK-056). After install, tells you the next friendly command (how to onboard a PRD, then plan/run). Read-only unless you say Yes to invoke it."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-start`). No flags required.

Examples:
- `recipe-start`

## B. Prerequisites

- Recipe already installed in this repo (this skill is staged at install).
- Read-only by default. Does not write files unless the operator answers **Yes** to invoke the recommended skill.

## C. Tool Usage

1. Find repo root (git top-level / workspace).
2. Run the helper (prefer staged copy, else harness):

```bash
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/.gsd-recipe/scripts/recipe-next.sh" --target "$ROOT"
```

If that file is missing, resolve the harness copy:

```bash
ROOT="$(git rev-parse --show-toplevel)"
NEXT="$("$ROOT/.gsd-recipe/scripts/recipe-paths.sh" resolve bench/lib/recipe-next.sh --target "$ROOT")"
bash "$NEXT" --target "$ROOT"
```

Print the helper output **verbatim** — that is the user-facing next step.

3. Then ask **one** Yes/No question:

> Run that command for you now? (Yes / No)

- **No** → stop. They already have the text to copy.
- **Yes** → invoke **only** the recommended `recipe-*` skill by name in this same turn (e.g. `recipe-onboard`, `recipe-bootstrap-knowledge`, `recipe-plan-phase N`). Do not invent a different workflow. If the helper said to run the **bash installer**, print that command again and do **not** pretend `recipe-install` exists on a repo with no skills.

## D. Do NOT

- Chain the whole delivery pipeline.
- Mutate the repo except by invoking the one recommended skill after Yes.
- Hardcode product repo names or Jira keys.
</cursor_skill_adapter>

# recipe-start — first-run coach (TASK-056)

After `install-recipe-to-target.sh`, type **`recipe-start`** in Cursor Agent.

It looks only at generic files (`docs/PRD.md`, `.planning/ROADMAP.md`, `STATE.md`, `.knowledge/`) and tells you the next command in plain language.

| You have | It suggests |
|----------|-------------|
| No PRD | `recipe-onboard` (file, paste, or describe) |
| PRD, no ROADMAP | `recipe-onboard` |
| ROADMAP, no Epic | `recipe-onboard` |
| Onboarded | `recipe-bootstrap-knowledge` |
| Then | `recipe-plan-phase N` → `recipe-run-phase N` → verify → review-ship → settle |

Full catalog: `recipe-help`  
Snapshot + next step (read-only): `recipe-status`  
Same next-step in a terminal: `.gsd-recipe/scripts/recipe-next.sh`
