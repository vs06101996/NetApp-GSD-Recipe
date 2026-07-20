---
name: recipe-plan-phase
description: "Recipe: gated single-phase plan wrapper for the NetApp GSD recipe (TASK-017). Determines first-plan vs re-plan before calling gsd-plan-phase (informational only), resolves the phase's tracker issue key via parse-state.sh, calls native gsd-plan-phase N directly, then post-hoc verifies the resulting PLAN.md against the 7 mandatory sections + a filled Prerequisites table (soft warn-and-confirm, never fills/fabricates), prints any declared depends_on/touches as a non-blocking DAG-out-of-scope reminder, and emits plan_complete/plan_revised by invoking the gsd-jira-sync skill (idempotent via sync-ledger.sh)."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-plan-phase`) with:
- `N` — the phase number to plan (required).

Examples:
- `recipe-plan-phase 3`

## B. Prerequisites

- None strictly required before invocation — this skill itself decides first-plan vs re-plan by
  checking whether a `PLAN.md` for phase `N` already exists (see step 1). Either outcome is a
  valid starting state.
- `.planning/STATE.md` may or may not have a tracker section / phase-task row for phase `N`. If it
  doesn't, this skill continues in warn-and-continue mode (see step 2) — it never blocks on a
  missing tracker linkage.

## C. Tool Usage

1. **Determine first-plan vs re-plan (informational only, before calling `gsd-plan-phase`).**
   `Glob` for phase `N`'s `PLAN.md`, the same shape `bench/runners/draft-jira-comment.sh` /
   `recipe-run-phase-SKILL.md` use: `.planning/phases/{NN}-*/*-{NN}-*-PLAN.md`, falling back to
   `.planning/phases/*/*-{NN}-*-PLAN.md` if the padded-prefix directory glob finds nothing — where
   `{NN}` is `N` zero-padded to 2 digits.
   - Found → this is a **re-plan**; route the eventual tracker post to `plan_revised` in step 7.
   - Not found → this is a **first-plan**; route the eventual tracker post to `plan_complete` in
     step 7.
   - This check never blocks calling `gsd-plan-phase` either way — it only decides which event id
     to use later.

2. **Resolve the issue key.** `bench/lib/parse-state.sh` is not duplicated into every target by
   design — resolve its real path via `.gsd-recipe/scripts/recipe-paths.sh` first (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full), then run:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   "$RESOLVED" resolve-issue plan_complete --phase N
   ```
   (`plan_complete` is used as the lookup event id regardless of first-plan/re-plan — both are
   phase-routed to the same `## Phase tasks` row per `DATA-CONTRACTS.md` rule 7; only the *posted*
   event id differs, per step 1's determination.)
   - Resolves → carry that issue key into step 7.
   - Fails (no `.planning/STATE.md`, no `## Tracker` section, or no matching phase-task row for
     `N`) → do not block. Warn the operator ("No tracker issue linked for phase N — skipping Jira
     sync, continuing with gsd-plan-phase") and continue straight to step 3.

3. **Call native `gsd-plan-phase N` directly**, in this same turn. Invoking `recipe-plan-phase`
   was itself the operator's deliberate act of choosing to plan this phase now — that IS the
   manual GSD trigger; this is not an unapproved autonomous invocation (same precedent as
   `recipe-run-phase`'s direct call to `gsd-execute-phase`). Add no spike handling here — if the
   phase needs a `gsd-spike` first, that is the operator's own separate call before planning, not
   something this skill triggers on their behalf.

4. **Re-resolve `PLAN.md` for phase `N`**, using the exact same glob shape as step 1.
   - Not found → native `gsd-plan-phase` produced no plan (aborted, declined, or errored inside
     that call). Report this plainly to the operator and **stop here** — do not proceed to steps
     5-7, and never fabricate a stamp or a tracker post for a plan that doesn't exist.
   - Found → continue to step 5.

5. **Post-hoc compliance verification (read-only, soft warn-and-confirm).** `Read` the resolved
   `PLAN.md` and check, per `docs/netapp-recipe/lld/PLANNING-POLICY.md`:
   - All 7 mandatory sections are present: Problem restatement, Proposed approach, Security
     considerations, Performance considerations, Expected review concerns, Validation / testing
     strategy, Learning extraction opportunities. Match on heading text case-insensitively,
     tolerant of numbering/prefixes (e.g. `## 3. Security considerations` counts).
   - A `Prerequisites` table is present **and filled**: at least one data row (not just the header
     and separator rows), with no cell left blank or holding placeholder text like `...`/`TBD`.
   - If either check fails, print a specific warning naming exactly what's missing/unfilled, and
     ask the operator to confirm before the tracker gets stamped (a yes/no human gate). This is a
     **soft gate**: never hard-block, and never fill or fabricate the table yourself — that is
     `recipe-planning-policy`'s / the planner's job, not this skill's. If the operator declines,
     stop here without proceeding to step 7 (no tracker post for a plan the operator didn't
     confirm).
   - If both checks pass, note "compliance gate: compliant" in the final summary and continue
     without an extra prompt.
   - There is no further native call to gate at this point (`gsd-plan-phase` already returned in
     step 3) — this gate exists specifically to decide whether the tracker stamp in step 7 fires,
     not to re-run planning.

6. **`depends_on`/`touches` reminder (soft, informational only).** Hand-parse the `PLAN.md`
   frontmatter the same minimal way `bench/runners/sync-reconcile.sh`'s `parse_touches()` already
   does — a fixed `depends_on: [...]` / `touches:` (multi-line `- item` list) block, no YAML
   library. If either list is non-empty, print both to the operator as an informational reminder,
   e.g.: "This phase declares depends_on: [01-auth, 02-schema] and touches: [src/payments/**] —
   DAG state isn't tracked yet (TASK-009 parked), verify those phases yourself and check for
   file-ownership overlap manually." Never read or write `.knowledge/dag/*` (it does not exist —
   parked per `DECISIONS.md`) and never block on this; print-only, always continue to step 7
   regardless of what — or whether anything — was found.

7. **Emit `plan_complete` or `plan_revised`** (only when step 2 resolved an issue key), routed by
   step 1's first-plan/re-plan determination. `bench/lib/sync-ledger.sh` needs the same
   `recipe-paths.sh` resolution as step 2 above — resolve it once, then compute the idempotency key
   via `<resolved> key {plan_complete|plan_revised} <issue_key> --phase N` and check
   `<resolved> has <key>` first. Already present → skip (report `duplicate_skipped`,
   no re-post). Otherwise, invoke the `gsd-jira-sync` skill's own documented single-event workflow
   (`gsd-jira-sync plan_complete <issue_key> --phase N` or `gsd-jira-sync plan_revised <issue_key>
   --phase N`) — do not inline `draft-jira-comment.sh`'s draft/post/stamp steps here. That skill
   owns drafting the comment body, the `addCommentToJiraIssue` MCP call, and running
   `emit-stamp.sh`; this skill only decides *whether* to call it, *which* event id, and *what* to
   pass.

8. **Summarize**, in one final line to the operator: phase number, resolved issue key (or "none
   linked"), first-plan/re-plan determination, the compliance gate result (`compliant` /
   `warned-and-confirmed` / `warned-declined — stopped before tracker sync`), and the tracker post
   result (`posted` / `duplicate_skipped` / `skipped-no-issue`).

## D. Do NOT

- Do not implement DAG topo-sort or cycle detection (`RUNTIME-LLD.md` §1.c.2.c) — that is Tier-1
  DAG work (`dag-build.sh`, TASK-009), parked per `DECISIONS.md`. This skill only ever prints
  `depends_on`/`touches` as a plain informational reminder; it never builds a graph, never
  computes execution order, never reads or writes `.knowledge/dag/*`.
- Do not implement DAG pre-req/post-op gating (`RUNTIME-LLD.md` §1.c.2.a/b) — same parked status,
  same reason.
- Do not fill or fabricate the Prerequisites table yourself, ever — even while warning that it's
  unfilled. That is the planner's job, gated by the `recipe-planning-policy` skill, not this one.
- Do not inline Jira drafting/posting/stamping logic (`draft-jira-comment.sh`'s steps) directly —
  always call into `gsd-jira-sync`'s documented workflow instead for both `plan_complete` and
  `plan_revised`.
- Do not hard-block on a missing/unfilled Prerequisites table — warn-and-confirm only (soft gate,
  decision #2). The operator can always choose to proceed.
- Do not hard-block on an unresolved issue key — warn and continue straight to `gsd-plan-phase`
  regardless (fail-open on tracker/MCP issues; this is the expected path for the baseline arm or
  any repo with no tracker linked yet).
- Do not emit a `plan_started` stamp — `bench/recipe/trackers/jira-events.json` (and its
  `docs/netapp-recipe/reference/harness/recipe/trackers/jira-events.json` mirror) only define
  `plan_complete`/`plan_revised` for the planning milestone; there is no started/complete pairing
  for planning the way `recipe-run-phase` has `execute_started`/`execute_complete`. Do not invent
  one.
- Do not handle spike triggering (`gsd-spike`, `RUNTIME-LLD.md` §1.c.1) — that stays the
  operator's own separate call before planning, never triggered by this skill.
- Do not touch `recipe-run-phases`/`recipe-run-phase` (TASK-018/024) — those are the execute-side
  siblings, out of scope here.
</cursor_skill_adapter>

# recipe-plan-phase — gated single-phase plan (TASK-017)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §1.c "Planning", tag **[N]** for the
underlying `gsd-plan-phase` call, **[C]** for this wrapper's linkage/verification layer) — GSD
stays the orchestrator; this skill adds an informational first-plan/re-plan determination, tracker
issue resolution, a direct same-turn call to native `gsd-plan-phase`, a read-only post-hoc
planning-policy compliance check, an informational `depends_on`/`touches` reminder, and
`plan_complete`/`plan_revised` tracker sync around it.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §1.c · `docs/netapp-recipe/BACKLOG.md` TASK-017.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), and `recipe-run-phase` (TASK-024) ahead of the full
`install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-plan-phase.sh`, and is also composed into `install.sh` as a
fifth sub-installer.

## Workflow

1. Determine first-plan vs re-plan by globbing for phase `N`'s `PLAN.md` (informational only —
   never blocks calling `gsd-plan-phase` either way).
2. Resolve the phase's tracker issue key via `parse-state.sh resolve-issue plan_complete --phase
   N`. Unresolved → warn and continue (fail-open).
3. Call native `gsd-plan-phase N` directly, in the same turn (Option B — the operator's own
   invocation of `recipe-plan-phase` is the manual GSD trigger).
4. Re-resolve `PLAN.md` for phase `N`. Not found → native `gsd-plan-phase` produced no plan; stop
   here, report plainly, no fabrication.
5. Read-only post-hoc planning-policy gate: 7 mandatory sections + filled Prerequisites table.
   Soft warn-and-confirm if non-compliant — never a hard block, never fills the table. Gates
   whether the step-7 tracker stamp fires.
6. Print any declared `depends_on`/`touches` as an informational, non-blocking reminder — no DAG
   topo-sort/cycle-detection, no `.knowledge/dag/*` reads/writes.
7. Emit `plan_complete` (first-plan) or `plan_revised` (re-plan) via the `gsd-jira-sync` skill
   (idempotent via `sync-ledger.sh`), if an issue key resolved and the operator didn't decline the
   step-5 gate.
8. Summarize phase/issue/first-plan-or-re-plan/gate-result/post-result in one line.

## Why Option B (direct same-turn call), not a background/async trigger

Decision #1 (approved): the operator's own act of invoking `recipe-plan-phase` already is the
"human decided to plan this phase" gate `RUNTIME-LLD.md` describes for `gsd-plan-phase` — same
precedent as `recipe-run-phase`'s direct call to `gsd-execute-phase`. Unlike `recipe-prd-intake`'s
deliberate *non*-invocation of `gsd-discuss-phase` (that skill explicitly defers to the operator to
run discuss themselves — see its own SKILL.md § D), this skill is explicitly approved to call
`gsd-plan-phase` on the operator's behalf, because `recipe-plan-phase N` *is* the operator's request
to plan phase `N` right now.

## Why the compliance check runs *after* the native call, not before it

Unlike `recipe-run-phase`'s pre-hoc gate (which checks an already-existing `PLAN.md` before
deciding whether to call `gsd-execute-phase`), `recipe-plan-phase`'s compliance check is
necessarily post-hoc: there is no `PLAN.md` to check before `gsd-plan-phase` has run for a
first-plan invocation, and even for a re-plan the point of calling `gsd-plan-phase` again is to
produce a *new* `PLAN.md` to check. Decision #2 (approved): since there's no further native call
left to gate at that point, a non-compliant result gates the tracker stamp in step 7 instead —
warn-and-confirm before that stamp fires, never a fill/fabricate, never a hard block on the
already-completed native call.

## What this does NOT do (see the integration report for the full rationale)

- **No DAG topo-sort/cycle-detection, no DAG pre-req/post-op gating.** `RUNTIME-LLD.md`
  §1.c.2.a/b/c describes a `.knowledge/dag/` eligibility check, a `verified` status write-back, and
  a Kahn-topo-sort-based conflict/ordering algorithm — all depend on TASK-009's `dag-build.sh`,
  which is parked per `DECISIONS.md` ("Not required for v1"; TASK-017 explicitly named as
  narrowed to skip this). This skill never reads or writes `.knowledge/dag/*`.
- **No Prerequisites-table filling.** The compliance gate is strictly read-only — it warns, it
  never writes to `PLAN.md`.
- **No inlined Jira posting logic.** `plan_complete`/`plan_revised` are emitted by invoking
  `gsd-jira-sync`'s documented workflow, not by calling `draft-jira-comment.sh` and the Atlassian
  MCP directly from within this skill.
- **No `plan_started` stamp.** Only `plan_complete`/`plan_revised` exist in `jira-events.json` for
  the planning milestone — there is no started/complete pairing here, unlike
  `recipe-run-phase`'s `execute_started`/`execute_complete`.
- **No spike handling.** `gsd-spike` (§1.c.1) stays a separate, operator-triggered call before
  planning if the phase needs one.

## Fail-open behavior on tracker/MCP issues

If `.planning/STATE.md` has no tracker section, no phase-task row for `N`, or the Atlassian MCP is
unreachable/unauthenticated when `gsd-jira-sync` is invoked, this skill never blocks
`gsd-plan-phase` on that account — it warns and continues. The only two conditions that stop this
skill before reaching step 7's tracker post are: (a) `PLAN.md` for phase `N` still doesn't exist
after calling `gsd-plan-phase` (native call aborted/declined/errored), or (b) the operator
explicitly declines to proceed past the soft post-hoc compliance gate.
