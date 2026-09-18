---
name: recipe-tdd
description: "GSD agent_skills TDD adapter (TASK-063). Injects the vendored Matt Pocock red-green-refactor sheet into gsd-planner and gsd-executor. Not invoke-by-name."
---

# recipe-tdd — planner/executor context (TASK-063)

This file is **not invoked by name**. Inject it via `.planning/config.json`
`agent_skills.gsd-planner` and `agent_skills.gsd-executor` (print-only at install).

Read the vendored sheet (do not rewrite it):

`.gsd-recipe/vendor/mattpocock/skills/engineering/tdd/SKILL.md`

Also consult `tests.md` and `mocking.md` in that same directory, and
`.gsd-recipe/vendor/mattpocock/skills/engineering/codebase-design/SKILL.md`
when seam/module shape is the question.

## Recipe mapping (do not use Pocock's default paths)

| Pocock sheet says | Use in this recipe |
|---|---|
| `CONTEXT.md` | `docs/PRD.md`, `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.knowledge/` |
| ADRs under Pocock layout | `.knowledge/`, `.planning/`, existing `DECISIONS.md` if present |
| Skill tool `"tdd"` / `"codebase-design"` | Read the vendored files above; never install the full pack |
| User-invoked `/implement` | `recipe-run-phase` / native `gsd-execute-phase` |

## Loop

Native `recipe-plan-phase N --tdd` and `recipe-run-phase N --tdd` plus
`workflow.tdd_mode` already request TDD. Follow red → green, one vertical slice,
tests at confirmed public seams. If native TDD cannot engage, warn and continue
(same circuit breaker as the plan/run skills).

## Do NOT

- Do not replace GSD plans with `/to-tickets` or `/implement`.
- Do not fail a phase solely because a seam confirmation was skipped; warn.
