---
name: recipe-two-axis-review
description: "GSD agent_skills two-axis review adapter (TASK-063). After native gsd-code-review, append Standards vs Spec using the vendored Pocock code-review sheet. Not invoke-by-name."
---

# recipe-two-axis-review (TASK-063)

This file is **not invoked by name**. `recipe-review-ship` runs native
`gsd-code-review N` first (canonical REVIEW.md), then this adapter **appends**
`## Standards` and `## Spec` — it does not replace the native review.

Read `.gsd-recipe/vendor/mattpocock/skills/engineering/code-review/SKILL.md`.

## Recipe mapping

- Spec source order: phase `PLAN.md`, `docs/PRD.md`, `.planning/REQUIREMENTS.md`,
  Jira issue from `.planning/STATE.md`. Do **not** require
  `docs/agents/issue-tracker.md` or `/setup-matt-pocock-skills`.
- Fixed point: merge-base with the default branch, or the phase's first commit
  if obvious. If unclear, ask once; empty diff → skip the append and warn.
- Standards: repo CONTRIBUTING/coding-standards if present, plus the vendored
  smell baseline. Repo docs override the baseline.

Spawn Standards and Spec as parallel sub-agents per the vendored sheet, then
append both headings to the phase `REVIEW.md`. Fail-open: lookup failures warn
and still continue to `gsd-jira-sync` / `gsd-ship`.
