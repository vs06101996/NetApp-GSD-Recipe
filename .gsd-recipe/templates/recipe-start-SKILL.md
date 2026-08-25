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

3. Open the sequenced command list (local, gitignored): `docs/RECIPE-SEQUENCE.md`. Use the editor Open-file tool, or `cursor docs/RECIPE-SEQUENCE.md` if the CLI exists. If the file is missing, say so (re-run recipe install / `install-recipe-start.sh`). Do not commit this file.

4. Then ask **one** Yes/No question:

> Run that command for you now? (Yes / No)

- **No** → stop. They already have the text to copy (and the sequence page).
- **Yes** → if the helper **Command** is `recipe-onboard`, ask one extra: “Create Jira Epic and phase tasks? (Yes / No)”. Yes → invoke `recipe-onboard`. No → invoke `recipe-onboard --skip-tracker`. For any other Command, invoke **only** that `recipe-*` skill by name in this same turn (e.g. `recipe-bootstrap-knowledge`, `recipe-plan-phase N`). Do not invent a different workflow. If the helper said to run the **bash installer**, print that command again and do **not** pretend `recipe-install` exists on a repo with no skills.

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
| No PRD | `recipe-onboard` (Jira/Confluence export, file, paste, or describe). No Jira: `--skip-tracker` |
| PRD, no ROADMAP | `recipe-onboard` |
| ROADMAP, no Epic | `recipe-onboard` |
| Onboarded (knowledge included) | `recipe-plan-phase N` |
| Then | `recipe-plan-phase N` → `recipe-run-phase N` → verify → review-ship → settle |

After Yes on onboard, it asks whether to create Jira tickets. Sequence page (gitignored): `docs/RECIPE-SEQUENCE.md`.

Jira/Confluence PRD exports use `.templates/JIRA-PRD.input.template.md` as an
**input-only** shape. Pass one with `recipe-onboard @path/to/file.md`; intake maps it
to canonical `docs/PRD.md` using `.templates/JIRA-PRD.input.MAPPING.md`.

Full catalog: `recipe-help`  
Snapshot + next step (read-only): `recipe-status`  
Same next-step in a terminal: `.gsd-recipe/scripts/recipe-next.sh`
