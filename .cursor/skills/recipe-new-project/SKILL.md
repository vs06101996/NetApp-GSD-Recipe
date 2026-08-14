---
name: recipe-new-project
description: "Recipe: gated repo-bootstrap wrapper for the NetApp GSD recipe (TASK-036). Determines first-init vs re-init (soft warn-and-confirm), resolves bootstrap input (explicit argument, else docs/PRD.md if present, else native input-gathering), calls native gsd-new-project (or gsd-import with --import) directly, then re-verifies .planning/PROJECT.md + ROADMAP.md + STATE.md were actually created. Never syncs intake_started itself — that stays recipe-create-epic's job once an Epic exists."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-new-project`) with:
- `<input>` — optional. A file path, pasted brief, or `@`-referenced document to feed native
  `gsd-new-project`/`gsd-import`. When omitted, prefer `docs/PRD.md` if it exists; otherwise let
  native GSD gather input conversationally.
- `--import` — optional. Routes step 3 to native `gsd-import` instead of `gsd-new-project`
  (brownfield / external-plan ingestion — same wrapper shape, different native command).

Examples:
- `recipe-new-project`
- `recipe-new-project docs/PRD.md`
- `recipe-new-project --import path/to/external-plan.md`

## B. Prerequisites

- None strictly required before invocation — this skill itself determines first-init vs re-init
  (see step 1). Either outcome is a valid starting state.
- `docs/PRD.md` may or may not exist. When present and no explicit `<input>` was given, it is the
  preferred bootstrap input (see step 2) — but its absence is not a hard block; native GSD can
  gather input instead.

## C. Tool Usage

1. **Determine first-init vs re-init (informational only, before calling native GSD).**
   `Glob`/`Read` for `.planning/ROADMAP.md`.
   - Not found → **first-init**; continue to step 2 without an extra gate.
   - Found → **re-init**; continue to step 2 and surface the soft warn-and-confirm gate there.

2. **Soft warn-and-confirm gate when re-init.** When step 1 found an existing `.planning/ROADMAP.md`,
   print a plain warning: re-running project bootstrap against an already-initialized repo may
   overwrite or merge planning artifacts per native GSD's own semantics — this skill does not enforce
   native overwrite rules, it only informs the operator. Ask yes/no before proceeding.
   - **Decline** → stop here. Report "operator declined — project bootstrap not run."
   - **Confirm** → continue to step 3.
   - **First-init** (no existing `ROADMAP.md`) → skip this gate and continue straight to step 3.

3. **Resolve bootstrap input and route to the correct native command.**
   - Explicit `<input>` on this invocation → use it as the native command's input.
   - No explicit input, but `docs/PRD.md` exists → prefer `docs/PRD.md` as the bootstrap brief
     (read it and pass its content / `@`-reference it to native GSD).
   - Neither → call native GSD with no preloaded brief; let its own questioning flow run.
   - **`--import` passed** → invoke native `gsd-import` directly in this same turn with the
     resolved input (skill-to-skill / workflow invocation — read and follow
     `gsd-import-SKILL.md`'s own documented workflow).
   - **`--import` not passed** → invoke native `gsd-new-project` directly in this same turn (read
     and follow `gsd-new-project-SKILL.md`'s own documented workflow).

4. **Re-verify the expected planning artifacts exist.** After the native call returns, `Glob`/`Read`
   for:
   - `.planning/PROJECT.md`
   - `.planning/ROADMAP.md`
   - `.planning/STATE.md`
   - Any missing → report plainly which file(s) are absent and **stop here** — do not fabricate
     `.planning/*` artifacts yourself. Native GSD aborted, was declined, or errored inside its own
     call.
   - All three present → report success with a one-line summary of what native GSD produced.

5. **Print the final summary, always.** Note first-init vs re-init, which native command ran
   (`gsd-new-project` vs `gsd-import`), which input source was used (`docs/PRD.md`, explicit path,
   or conversational), and whether all three core files verified. Never invoke `gsd-jira-sync` or
   post `intake_started` from this skill — that event is owned exclusively by `recipe-create-epic`
   once a Jira Epic actually exists (see § D).

## D. Do NOT

- Do not fabricate `.planning/PROJECT.md`, `.planning/ROADMAP.md`, or `.planning/STATE.md` — those
  are exclusively native `gsd-new-project`'s/`gsd-import`'s own output. If the native call doesn't
  produce them, that is a failure to report, never values to invent inline.
- Do not sync `intake_started` (or any other tracker event) from this skill — at the point this
  skill runs there may be no Jira Epic yet to attach a comment to. `recipe-create-epic` owns
  emitting `intake_started` once the Epic genuinely exists (see its own step 9).
- Do not chain to `recipe-prd-intake`, `recipe-create-epic`, or `recipe-create-phase-tasks` —
  `recipe-onboard` (TASK-037) is the orchestrator that sequences those steps; this skill is only
  the project-bootstrap slice.
- Do not validate or reorder ROADMAP phase DAG frontmatter, read/write `.knowledge/dag/*`, or
  topo-sort phases — DAG tracking is explicitly out of scope (parked pending TASK-009); print-only
  reminders elsewhere in the recipe already cover that gap.
- Do not hard-block re-init — the step-2 gate is soft warn-and-confirm only; native GSD owns
  overwrite/refusal semantics once the operator confirms.
</cursor_skill_adapter>

# recipe-new-project — repo bootstrap wrapper (TASK-036)

Recipe configuration on top of native GSD (`gsd-new-project` / `gsd-import`) — closes the "make my
current repo ready" gap: project bootstrap was the one onboarding step with no `recipe-*` equivalent,
so operators following the recipe end-to-end still had to type native GSD directly.

**Spec:** `docs/netapp-recipe/BACKLOG.md` TASK-036.

## Workflow

1. Check whether `.planning/ROADMAP.md` already exists → first-init vs re-init.
2. Soft warn-and-confirm gate on re-init only.
3. Resolve input (`<input>` arg → else `docs/PRD.md` → else conversational) and call native
   `gsd-new-project` or `gsd-import` (`--import`).
4. Re-verify `.planning/PROJECT.md`, `ROADMAP.md`, and `STATE.md` exist.
5. Final summary — never sync tracker events from here.

## Why this skill never syncs intake_started itself

`bench/recipe/trackers/jira-events.json` lists `intake_started`'s trigger as "`gsd-new-project` or
`gsd-import`" — but at the point this skill runs there may be no Jira Epic yet. `recipe-create-epic`
already owns emitting `intake_started` once the Epic actually exists. One event, one owner.

## Relationship to recipe-onboard

`recipe-onboard` (TASK-037) chains `recipe-prd-intake` → **`recipe-new-project`** →
`recipe-create-epic` → `recipe-create-phase-tasks`, skipping any step whose artifact already exists.
When `recipe-new-project` is not staged, `recipe-onboard` falls back to native `gsd-new-project`
for the bootstrap step only — install this skill to avoid that fallback.

## What this does NOT do

- **No PRD intake.** Run `recipe-prd-intake` first (or let `recipe-onboard` invoke it).
- **No Epic or phase-task creation.** Those are `recipe-create-epic` / `recipe-create-phase-tasks`.
- **No DAG validation.** Phase order follows native ROADMAP output only.
