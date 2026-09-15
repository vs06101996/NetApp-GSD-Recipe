---
name: recipe-planning-policy
description: "GSD agent_skills injected context for gsd-planner (TASK-012). Operationalizes docs/netapp-recipe/lld/PLANNING-POLICY.md's per-phase prerequisite workflow, SPEC/TDD usage, and context-gathering sections directly into the planning subagent's own prompt."
---

# recipe-planning-policy — planner context (TASK-012)

This file is **not invoked by name**. It is injected as context into the
`gsd-planner` subagent's own prompt via `.planning/config.json`'s
`agent_skills.gsd-planner` array (a plain `skills/` path resolved relative to
project root — distinct from the `.cursor/skills/` directory used by
invoke-by-name skills like `tracker-sync`/`recipe-prd-intake`). Because
nothing ever says "recipe-planning-policy" out loud, this file has no
`<cursor_skill_adapter>` A/B/C/D invocation block — it just states the policy
directly, for `gsd-planner` to read and follow as part of composing
`PLAN.md`.

Full policy source of truth:
[docs/netapp-recipe/lld/PLANNING-POLICY.md](../../docs/netapp-recipe/lld/PLANNING-POLICY.md).
This file operationalizes that doc's three added sections — read the doc
itself for the complete rationale; what follows is the concrete "do this,
in this order" version for whoever is holding the pen on a `PLAN.md`.

## 1. Per-phase prerequisite workflow

Before writing any of this phase's own new-work sections:

1. **Verify** — for every deliverable the *prior* phase claimed to ship,
   actually check it's present and passing right now. Run its tests if it
   has them; open the artifact and read it if it doesn't. Never write
   "assumed done" — either it checks out or it doesn't.
2. **Close gaps in-scope** — if verification finds something missing or
   broken, that fix becomes part of *this* phase's own scope. Don't punt it
   to "later" or a new backlog row; the whole point of this workflow is that
   a phase never builds on an unverified foundation.
3. **Extend tests to cover it** — whatever was (re-)verified or fixed needs
   a test that would catch regression, added to this phase's own test
   changes, not left as a manual-only check.
4. **Fill the Prerequisites table** in this phase's `PLAN.md`, before any
   new-work section, with exactly these columns:

   | Prerequisite | Delivered by (phase/task) | Verified? | Gap found | Resolution |
   |---|---|---|---|---|

   Fill one row per prior-phase deliverable this phase actually depends on.
   A clean bill of health still gets a row (`Verified?: yes`,
   `Gap found: none`, `Resolution: n/a`) — omitting rows because "everything
   was fine" defeats the purpose of forcing the check to happen at all.

## 2. Supporting artifacts — SPEC.md / TDD.md

Before finalizing the plan:

- Check whether a formal LLD spec already exists for the deliverable (most
  `BACKLOG.md` rows already have one in their `Spec` column). If yes, cite
  it directly in the plan — do not duplicate it into a new SPEC.md.
- If no LLD spec exists yet for this piece of net-new work, fill
  `.templates/SPEC.template.md` (design/scope/interfaces/testing) before the
  plan is considered final. Add `.templates/TDD.template.md` too if the work
  involves a real design decision with alternatives worth recording
  (context/design/alternatives-considered/risks).
- The goal: net-new work without a pre-existing LLD doc still gets a real
  spec/design record instead of skipping straight from idea to code. Both
  templates already ship in every recipe-installed repo via `install.sh`
  (TASK-010) — they exist specifically for this consumer.

## 3. Context gathering before planning

Before drafting the plan, spend a few minutes checking whether this ground
has already been covered:

1. Read `.knowledge/log.md` and `.knowledge/index.md` for prior decisions or
   learnings relevant to this phase's subject area.
2. Always try `gsd-graphify query <topic>` for the phase's subject area (recipe
   defaults `graphify.enabled` to true). Factor anything relevant into the plan.
3. Step 2 is a **circuit breaker** — if the CLI is missing, the query fails, or
   graphify was skipped at knowledge bootstrap, warn and proceed with just the
   `.knowledge/` read from step 1. Never block planning on graphify.

## Do NOT

- Skip the Prerequisites table because "the prior phase obviously worked" —
  the table exists to force an actual check, not a vibe.
- Treat a cited existing LLD spec as optional busywork — if one exists, cite
  it; if one doesn't, fill a template. Either way, don't skip straight to
  code with no design record at all.
- Hard-block planning on graphify. It is, and stays, optional tooling.
