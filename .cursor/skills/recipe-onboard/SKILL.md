---
name: recipe-onboard
description: "Recipe: single onboarding orchestrator. Chains PRD intake, project bootstrap, optional Jira Epic/tasks, then mandatory knowledge bootstrap. --skip-tracker skips only Jira; knowledge still runs. One preview gate, artifact-aware skips, fail closed on the first failed required step."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-onboard`) with:
- A PRD source (optional) — a file path, pasted text, or a freeform description. Forwarded
  verbatim to `recipe-prd-intake` in step 2's chain **only if** `docs/PRD.md` doesn't already
  exist. If it already exists, this input is ignored (that step is skipped entirely — see § C
  step 1).
- `--project KEY` / `--issue-type NAME` / `--assignee NAME` / `--force` — optional. Forwarded
  verbatim to `recipe-create-epic` (and `--assignee` also to `recipe-create-phase-tasks`) when
  those steps actually run.
- `--skip-tracker` — optional. Light path (TASK-042): skip Epic creation and phase-task creation
  even if those artifacts are missing. PRD intake, project bootstrap, and knowledge bootstrap still
  run when needed.
  After those succeed, merge `"onboard": {"skip_tracker": true}` into `.gsd-recipe/config.json`
  (do not invent an Epic key in `.planning/STATE.md`). The full Jira path stays the default;
  knowledge is mandatory on both paths.

Examples:
- `recipe-onboard` — no PRD source given; onboard whatever is missing, asking for PRD input live
  if that step is reached and nothing was provided.
- `recipe-onboard docs/PRD.md` — already-written PRD file; skips intake's own file/paste/freeform
  question if that step runs.
- `recipe-onboard --skip-tracker` — PRD + `.planning/` + knowledge; no Jira Epic or phase tasks.
- `recipe-onboard --project KAN --assignee "Ada Lovelace"` — skips the live Jira-project question if the Epic step runs; assigns created tickets.

## B. Prerequisites

- Cursor GSD full profile must be installed (the recipe installer installs/verifies it by default).
- None of the project artifacts are required before invocation — this skill's first phase (§ C step 1) is
  determining, per artifact, whether a prerequisite is already satisfied. Any combination of
  present/missing artifacts across the five steps is a valid starting state, including "all five
  already present" (in which case the preview gate shows an all-skip plan and nothing is invoked).
- Atlassian MCP enabled and authenticated — needed only if step 4 and/or step 5 below actually run
  (their own prerequisite, not re-checked here; see `recipe-create-epic-SKILL.md` § B /
  `recipe-create-phase-tasks-SKILL.md` § B).

## C. Tool Usage

1. **Determine which of the five artifacts already exist — read-only, no gate yet.**
   - `Glob`/`Read` for `docs/PRD.md`. Present → step 2 ("PRD intake") will be **skipped**. Missing →
     step 2 will **run**.
   - `Glob`/`Read` for `.planning/ROADMAP.md`. Present → step 3 ("project bootstrap") will be
     **skipped**. Missing → step 3 will **run**.
   - Resolve `bench/lib/parse-state.sh` via `.gsd-recipe/scripts/recipe-paths.sh resolve` (same
     mechanism `recipe-create-epic-SKILL.md` § C step 2 documents in full) and run
     `get-tracker --state .planning/STATE.md`. A non-empty `epic` field → step 4 ("Epic creation")
     will be **skipped**. Missing/empty (including when `.planning/STATE.md` doesn't exist yet) →
     step 4 will **run** — *unless* step 3 above is also going to run, in which case step 4's
     eligibility can't be determined until step 3 actually produces a `ROADMAP.md`; note this
     dependency in the preview (step 1e below) rather than resolving it early.
   - If step 4 is not going to run (an Epic is already linked) or step 3 will run first: resolve
     `bench/runners/create-phase-tasks.sh` the same way, run its `list` subcommand, and check
     whether it reports zero pending phase-task rows. Zero pending → step 5 ("phase-task creation")
     will be **skipped**. One or more pending (or `list` itself fails closed because no Epic is
     linked yet, or `ROADMAP.md` doesn't exist yet) → step 5 will **run**.
   - Read `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`. Valid JSON with `status: "ready"` → the final
     "knowledge bootstrap" step will be **skipped**. Missing, invalid, or any other status → it
     will **run**. The install-time `.knowledge/index.md` skeleton does not satisfy this check.
     Prefer running `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` for the skip/run
     decision — it also requires map + graph artifacts and rejects no-op graphify stubs.
   - This step never writes anything and never asks the operator anything yet — it is purely
     read-only reconnaissance for the single preview gate in step 2 below.

2. **Single soft preview-then-confirm gate — before invoking anything.** Print, plainly, all five
   steps in their fixed order (PRD intake → project bootstrap → Epic creation → phase-task
   creation → knowledge bootstrap) and, for each, whether it will **run** or **skip** (and why — e.g. "skip: docs/PRD.md
   already exists"). When `--skip-tracker` was passed, print steps 4 and 5 as **skip (flag:
   --skip-tracker)** — not provisional "will run". When `--skip-tracker` was *not* passed, add one
   line: "No Jira this time: `recipe-onboard --skip-tracker`." When step 3 will run and tracker
   steps are not skipped by flag, note explicitly that steps 4 and 5's own skip/run determination
   is provisional until step 3 actually completes (their `ROADMAP.md`/`STATE.md` inputs don't exist
   yet to check). Ask the operator to confirm (yes/no) — one gate for the whole chain, not nested
   per-step gates (see "Why one preview gate" below).
   - **Decline** → stop here entirely. Nothing has been invoked. Report "operator declined —
     onboarding not run" as the final summary.
   - **Confirm** → continue to step 3.

3. **Step "PRD intake" — only if step 1 determined `docs/PRD.md` is missing.** Invoke
   `recipe-prd-intake` by name (skill-to-skill, same turn), forwarding whatever PRD source was
   given to this invocation (file path / pasted text / freeform description), or nothing if none
   was given (that skill's own "no PRD" fallback then applies — see its § D). Follow
   `recipe-prd-intake-SKILL.md`'s own full documented workflow exactly, including its own
   clarifying-question human gate for underspecified required sections.
   - `docs/PRD.md` still doesn't exist after this call returns → **this step failed.** Stop the
     whole chain immediately. Record "PRD intake" as the blocking step with reason
     "recipe-prd-intake did not produce docs/PRD.md", then print the final summary.
   - `docs/PRD.md` now exists → continue to step 4.
   - **If step 1 determined this step should skip:** do not invoke `recipe-prd-intake` at all;
     continue straight to step 4.

4. **Step "project bootstrap" — only if step 1 determined `.planning/ROADMAP.md` is missing.**
   Invoke `recipe-new-project` by name (skill-to-skill, same turn) if it is staged at
   `.cursor/skills/recipe-new-project/SKILL.md` in this repo — follow its own documented workflow
   exactly (first-init-vs-re-init routing, `docs/PRD.md`-as-input preference, native
   `gsd-new-project`/`gsd-import` call, re-verification). **If `recipe-new-project` is not staged**
   (it is a separate, independently-installed skill, TASK-036 — this is a real, currently-common
   state, not an error condition), fall back to calling native `gsd-new-project` directly in this
   same turn instead, preferring `docs/PRD.md` as its input when present (same preference
   `recipe-new-project` itself documents) — this is the one and only step in this skill's chain
   where a native GSD call is made directly, and only as an explicit, narrow fallback for a sibling
   skill that may not exist yet on a given install.
   - `.planning/ROADMAP.md` still doesn't exist after this call returns → **this step failed.**
     Stop the whole chain immediately: do not invoke tracker or knowledge steps. Record "project bootstrap" as the
     blocking step with reason "neither recipe-new-project nor native gsd-new-project produced
     .planning/ROADMAP.md", then print the final summary.
   - `.planning/ROADMAP.md` now exists → if `--skip-tracker` was passed, skip re-checking Epic/phase
     tasks and continue to the skip-tracker persistence step below. Otherwise re-run
     step 1's Epic/phase-task checks (they were provisional per step 1's own note) before continuing
     to step 5.
   - **If step 1 determined this step should skip:** do not invoke anything; continue straight to
     step 5 with step 1's original (non-provisional) determination for steps 5/6 (or persistence when
     `--skip-tracker`).

5. **Step "Epic creation" — skip entirely when `--skip-tracker` was passed** (record the step as
   skipped (flag); do not invoke `recipe-create-epic`). Otherwise, only if the (possibly re-checked,
   per step 4) determination is that no Jira Epic is linked yet: invoke `recipe-create-epic` by name
   (skill-to-skill, same turn), forwarding `--project`/`--issue-type`/`--force` exactly as given to
   this invocation (or omitted, letting `recipe-create-epic`'s own live MCP questions run). Follow
   `recipe-create-epic-SKILL.md`'s own full 9-step documented workflow exactly, including its own
   fail-closed check on `docs/PRD.md` (already guaranteed present by this point via step 3) and its
   own soft confirm gate immediately before creating anything remote.
   - `parse-state.sh get-tracker` still reports no non-empty `epic` field after this call returns
     → **this step failed.** Stop the whole chain immediately: do not invoke step 6. Record "Epic
     creation" as the blocking step with the specific reason `recipe-create-epic` itself reported
     (e.g. "operator declined the confirm gate", "no Jira project resolved"), then print the final
     summary without running knowledge.
   - An Epic is now linked → continue to step 6.
   - **If skipped:** do not invoke anything; continue straight to step 6.

6. **Step "phase-task creation" — skip entirely when `--skip-tracker` was passed** (record skipped
   (flag); do not invoke `recipe-create-phase-tasks`). Otherwise, only if the (possibly re-checked)
   determination is that one or more `ROADMAP.md` phases have no linked Jira sub-task yet: invoke
   `recipe-create-phase-tasks` by name (skill-to-skill, same turn) with no arguments of its own.
   Follow `recipe-create-phase-tasks-SKILL.md`'s own full documented workflow exactly (detect → list
   → issue-type resolution → confirm gate → per-row create+link → mark-done/mark-failed).
   - Any row in that skill's own final summary reports `mark-failed` → **this step failed.**
     Stop before knowledge bootstrap and report the failed rows in the final summary.
   - Otherwise — all pending rows resolved to `mark-done`, or there were zero pending rows to begin
     with — this step is complete.

7. **When `--skip-tracker` was passed and steps 3–4 did not fail:** merge into
   `.gsd-recipe/config.json` (create the file if needed; preserve unrelated keys):
   `"onboard": { "skip_tracker": true }`. Do **not** write a fake Epic key into `.planning/STATE.md`.
   Then continue to knowledge bootstrap.

8. **Mandatory final "knowledge bootstrap" step.** If step 1 found knowledge already ready via
   `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` (exit 0), skip with reason
   "already ready". Otherwise invoke `recipe-bootstrap-knowledge` by name in this same turn.
   After it returns, **must** run `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` again;
   exit 0 → record knowledge bootstrap **completed**. Non-zero → knowledge bootstrap **failed**;
   report overall onboarding failed. Never treat a hand-written marker as success.
   `--skip-tracker` never skips this step.

9. **Print the final summary, always** (whether the chain completed all five steps, stopped early,
   or found every artifact already present): for each of the five steps,
   report **skipped** (with the reason, including `--skip-tracker` when that flag caused the skip),
   **completed** (carrying forward that sibling skill's own one-line summary), or — for at most one
   step, the one that blocked — **failed** (with the specific reason recorded at that step). Never
   invoke `gsd-jira-sync` directly from this step or any other step in this skill — `recipe-create-epic`
   (`intake_started`) and `recipe-create-phase-tasks` (no direct sync; see its own § D) already own
   every tracker event this chain can produce; `recipe-onboard` adds zero sync calls of its own.

## D. Do NOT

- Do not re-implement any step `recipe-prd-intake`/`recipe-new-project`/`recipe-create-epic`/
  `recipe-create-phase-tasks` already documents for itself — clarifying-question gates, first-init
  routing, live Jira project/issue-type questions, per-row create+link logic, or any of their own
  tracker syncs. This skill only ever decides, per artifact, *whether* to invoke each one, in what
  order, and whether to keep going or stop.
- Do not fabricate `docs/PRD.md`, `.planning/ROADMAP.md`, a Jira Epic key, or any phase-task issue
  key — every one of those is exclusively the invoked sibling skill's own real output. If a step's
  own call doesn't produce its artifact, that is a failure to report (§ C), never a value to invent.
- Do not sync `intake_started` (or any other tracker event) directly from this skill — that stays
  `recipe-create-epic`'s own job, once an Epic genuinely exists (same ownership boundary
  `recipe-new-project-SKILL.md` documents for itself).
- Do not implement `recipe-discuss-phase` or `recipe-complete-milestone` as part of this chain, and
  do not fold either's intent into any of the five existing steps — both were explicitly evaluated
  and deferred (see "Why `recipe-discuss-phase` and `recipe-complete-milestone` were evaluated but
  not built" below). This skill's chain is exactly five steps, no more.
- Do not ask separate confirm questions per step — exactly one preview-then-confirm gate
  (§ C step 2), shown once, before any step runs.
- Do not continue past a failed/declined step to a later one that depends on it (steps 3/4/5 each
  depend on the previous one's artifact) — stop the whole chain immediately and report exactly
  which step blocked and why (§ C, per-step "this step failed" language). `--skip-tracker` is the
  only way to omit Epic/phase-task steps without declining the whole gate.
- Do not call native `gsd-new-project`/`gsd-import` directly when `recipe-new-project` **is**
  staged — the native fallback in step 4 is a narrow, explicitly-scoped exception for when that
  sibling skill isn't installed yet, not a general shortcut.
</cursor_skill_adapter>

# recipe-onboard — single onboarding orchestrator (TASK-037)

Recipe configuration on top of five independently-invokable `recipe-*` skills — closes the
"no single on-ramp" gap: even with `recipe-prd-intake`, `recipe-new-project`, `recipe-create-epic`,
`recipe-create-phase-tasks`, and `recipe-bootstrap-knowledge` individually recipe-native, an
operator still had to know and manually sequence all five.

**Spec:** `docs/netapp-recipe/BACKLOG.md` TASK-037.

## Workflow

1. Read-only check: which of the five artifacts (`docs/PRD.md`, `.planning/ROADMAP.md`, a linked
   Jira Epic, per-phase Jira sub-tasks, knowledge-ready marker) already exist.
2. One preview-then-confirm gate showing all five steps and their run/skip determination. With
   `--skip-tracker`, Epic and phase-task steps show **skip (flag)**. Without it, mention
   `recipe-onboard --skip-tracker` as the no-Jira option. Decline → stop, nothing invoked.
3. PRD intake (skip if `docs/PRD.md` exists) → invoke `recipe-prd-intake` by name.
4. Project bootstrap (skip if `.planning/ROADMAP.md` exists) → invoke `recipe-new-project` by name,
   or fall back to native `gsd-new-project` directly if that sibling skill isn't staged.
5. Epic creation (skip if `--skip-tracker`, or if an Epic is already linked) → invoke
   `recipe-create-epic` by name.
6. Phase-task creation (skip if `--skip-tracker`, or if no `ROADMAP.md` phase is missing a linked
   sub-task) → invoke `recipe-create-phase-tasks` by name.
7. If `--skip-tracker` succeeded through PRD + planning: set `onboard.skip_tracker` in
   `.gsd-recipe/config.json`.
8. Knowledge bootstrap (skip only when marker is ready) → invoke `recipe-bootstrap-knowledge`,
   then verify `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`.
9. Final combined summary: skipped / completed / failed, per step.

The chain stops immediately on the first step that fails or is declined — never continues to a
later step that depends on it.

## Why one preview-then-confirm gate, not nested ones

The invoked skills already have their own internal, appropriately-scoped
confirm/decline gate before doing anything consequential (`recipe-prd-intake`'s overwrite
confirmation, `recipe-create-epic`'s pre-create confirm, `recipe-create-phase-tasks`'s batch
confirm). Re-asking "are you sure?" a second time immediately before each of those own gates would
be pure noise stacked on top of already-adequate protection. `recipe-onboard` instead shows exactly
one gate, above all five, previewing the whole chain (which steps will run vs skip) before anything
happens — the same single-preview shape `recipe-run-phases` already established for its own
per-phase-range loop.

## Why the whole chain stops on the first blocked step

A missing PRD makes `recipe-new-project`'s own `docs/PRD.md`-as-input convenience meaningless. A
missing `ROADMAP.md` makes `recipe-create-phase-tasks` meaningless (it fails closed on exactly that
precondition). A missing Epic makes `recipe-create-phase-tasks` meaningless for the same reason
(fails closed on `get-tracker` returning no epic). Continuing past a failed/declined step to a later
one that depends on it would just relay a second, redundant failure instead of stopping cleanly at
the first one — same "stop the whole loop on first failure" precedent `recipe-run-phases` already
established for its own per-phase loop.

## Why step 4 has a native-call fallback (the one exception to "always invoke by name")

`recipe-new-project` (TASK-036) and `recipe-onboard` (TASK-037) were designed in the same pass and
are meant to be installed together, but nothing in this recipe's install composition *guarantees*
`recipe-new-project` is staged before `recipe-onboard` is invoked — a target repo may have
`recipe-onboard` staged (this file) without `recipe-new-project` staged alongside it. Rather than
failing closed on a missing sibling skill for a step whose only real job is calling native
`gsd-new-project`/`gsd-import` anyway, step 4 checks whether `recipe-new-project` is actually
present and, if not, makes the exact same native call directly. This is the **only** step in this
chain with such a fallback — steps 3/5/6 (`recipe-prd-intake`/`recipe-create-epic`/
`recipe-create-phase-tasks`) have no native-call equivalent to fall back to, so they are always
invoked by name, with no exception.

## Why `recipe-discuss-phase` and `recipe-complete-milestone` were evaluated but not built

Both were explicitly considered during the same gap-closing pass that produced this skill:
`recipe-discuss-phase` was judged not required, on the basis that PRD-level Q&A
(`recipe-prd-intake`'s own clarifying-question gate) is assumed to cover the gray areas a
phase-level discuss would otherwise surface; `recipe-complete-milestone` was judged out of scope for
this pass. Neither is silently folded into this skill's own steps — this skill's chain is exactly
the five steps documented above, no more.

## What this does NOT do

- **No planning/execution step.** `recipe-plan-phase`/`recipe-run-phase`/`recipe-run-phases` starts
  only after onboarding has completed mandatory knowledge bootstrap (and, unless
  `--skip-tracker`, created the Epic and phase tasks).
- **No DAG involvement.** Phase-task creation order follows `ROADMAP.md`'s own phase numbering,
  exactly as `recipe-create-phase-tasks` itself already implements — no topo-sort, no
  `depends_on`/`touches` handling here.
- **No re-derivation of any sibling skill's own pass/fail definition.** Each step's "did this
  genuinely conclude successfully" question is answered by re-checking that step's own artifact
  (a file existing, `get-tracker` returning a non-empty epic, zero pending phase-task rows) — never
  by re-parsing that sibling skill's own internal reasoning.
- **No duplicated Jira sync**, ever — every tracker event this chain can produce is already emitted
  by `recipe-create-epic` on its own terms; this skill adds zero sync calls of its own.
