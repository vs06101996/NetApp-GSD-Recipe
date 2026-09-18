---
name: recipe-grill
description: "Manual standalone grilling entry point (TASK-063). recipe-plan-phase normally runs this vendored accuracy pass internally in Cursor Plan mode. Writes .planning/GRILL.md without replacing recipe-prd-intake or creating a second SDLC."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-grill`) with optional phase `N` (defaults to the next unplanned phase, else 1).

Examples:
- `recipe-grill`
- `recipe-grill 2`

## B. Prerequisites

- This named command is optional; `recipe-plan-phase` normally runs its equivalent internally in
  Cursor Plan mode. Use it manually only when you want to grill before choosing a phase command.
- Decline is always valid: planning continues without a completed grill.
- Do **not** install the full mattpocock/skills pack. Read only the vendored grilling sheet.

## C. Tool Usage

1. Resolve the vendored grilling skill:
   ```
   GRILL="$(.gsd-recipe/scripts/recipe-paths.sh resolve .gsd-recipe/vendor/mattpocock/skills/productivity/grilling/SKILL.md)"
   ```
   If missing, tell the operator to re-run recipe install / `recipe-update` and stop.

2. Follow that sheet's round/frontier interview. Map facts to this repo's artifacts, never `CONTEXT.md`:
   `docs/PRD.md`, `.planning/PROJECT.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.knowledge/`.

3. When the frontier is empty and the operator confirms shared understanding, write
   `.planning/GRILL.md` with: phase (if any), settled decisions, open leftovers (`none` if empty),
   and a one-line "ready to `recipe-plan-phase N`" (or "operator declined further grilling").

4. Do not call `gsd-plan-phase`, do not create Jira issues, do not invoke `/to-spec` or `/implement`.

## D. Do NOT

- Do not make this named command a prerequisite. `recipe-plan-phase` owns the internal Plan-mode
  accuracy pass and remains fail-open if grilling cannot complete.
- Do not run `npx skills add mattpocock/skills` or `/setup-matt-pocock-skills`.
- Do not invent a second ticket tracker or domain-doc home.
</cursor_skill_adapter>
