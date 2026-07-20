---
name: recipe-run-phase
description: "Recipe: gated single-phase execute wrapper for the NetApp GSD recipe (TASK-024). Resolves a phase's PLAN.md, soft-warns on planning-policy non-compliance (7 mandatory sections + a filled Prerequisites table) and prints any declared depends_on as an informational reminder, emits execute_started/execute_complete by invoking the gsd-jira-sync skill (idempotent via sync-ledger.sh), calls native gsd-execute-phase N [--wave W] directly, and summarizes phase/issue/gate/post results to the operator."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-run-phase`) with:
- `N` — the phase number to execute (required).
- `--wave W` — optional, forwarded verbatim to `gsd-execute-phase N --wave W`.

Examples:
- `recipe-run-phase 3`
- `recipe-run-phase 3 --wave 2`

## B. Prerequisites

- A `PLAN.md` for phase `N` exists under `.planning/phases/` (glob shape below). Missing → tell the
  operator to run `gsd-plan-phase N` first, then stop — do not fabricate or partially execute.
- `.planning/STATE.md` may or may not have a tracker section / phase-task row for phase `N`. If it
  doesn't, this skill continues in warn-and-continue mode (see step 4) — it never blocks on a
  missing tracker linkage.

## C. Tool Usage

1. **Resolve `PLAN.md`.** `Glob` for the phase's plan, the same shape
   `bench/runners/draft-jira-comment.sh` uses:
   `.planning/phases/{NN}-*/*-{NN}-*-PLAN.md`, falling back to
   `.planning/phases/*/*-{NN}-*-PLAN.md` if the padded-prefix directory glob finds nothing —
   where `{NN}` is `N` zero-padded to 2 digits.
   - Not found → tell the operator: "No PLAN.md found for phase N — run `gsd-plan-phase N`
     first." Stop here; do not proceed to any later step.

2. **Planning-policy compliance gate (read-only, soft).** `Read` the resolved `PLAN.md` and check,
   per `docs/netapp-recipe/lld/PLANNING-POLICY.md`:
   - All 7 mandatory sections are present: Problem restatement, Proposed approach, Security
     considerations, Performance considerations, Expected review concerns, Validation / testing
     strategy, Learning extraction opportunities. Match on heading text case-insensitively,
     tolerant of numbering/prefixes (e.g. `## 3. Security considerations` counts).
   - A `Prerequisites` table is present **and filled**: at least one data row (not just the header
     and separator rows), with no cell left blank or holding placeholder text like `...`/`TBD`.
   - If either check fails, print a specific warning naming exactly what's missing/unfilled, and
     ask the operator to confirm before proceeding (a yes/no human gate). This is a **soft gate**:
     never hard-block, and never fill or fabricate the table yourself — that is
     `recipe-planning-policy`'s / the planner's job, not this skill's. If the operator declines,
     stop here without calling `gsd-execute-phase`.
   - If both checks pass, note "planning-policy gate: compliant" in the final summary and continue
     without an extra prompt.

3. **`depends_on` reminder (soft, informational only).** Hand-parse the `PLAN.md` frontmatter the
   same minimal way `bench/runners/sync-reconcile.sh`'s `parse_touches()` already does for
   `touches:` — a fixed `depends_on: [...]` (or multi-line `- item` list) block, no YAML library.
   If a non-empty `depends_on` list is found, print it to the operator as an informational
   reminder, e.g.: "This phase declares depends_on: [01-auth, 02-schema] — DAG state isn't tracked
   yet (TASK-009 parked), so verify those phases are actually done yourself." Never read or write
   `.knowledge/dag/*` (it does not exist — parked per `DECISIONS.md`) and never block on this;
   print-only, always continue to step 4 regardless of what — or whether anything — was found.

4. **Resolve the issue key.** `bench/lib/parse-state.sh` is not duplicated into every target by
   design — resolve its real path via `.gsd-recipe/scripts/recipe-paths.sh` first (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full), then run:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   "$RESOLVED" resolve-issue execute_started --phase N
   ```
   - Resolves → carry that issue key into steps 5 and 7.
   - Fails (no `.planning/STATE.md`, no `## Tracker` section, or no matching phase-task row for
     `N`) → do not block. Warn the operator ("No tracker issue linked for phase N — skipping Jira
     sync, continuing with gsd-execute-phase") and skip straight to step 6.

5. **Emit `execute_started`** (only when step 4 resolved an issue key). `bench/lib/sync-ledger.sh`
   needs the same `recipe-paths.sh` resolution as step 4 above — resolve it once, then compute the
   idempotency key via `<resolved> key execute_started <issue_key> --phase N` and check
   `<resolved> has <key>` first. Already present → skip (report
   `duplicate_skipped`, no re-post). Otherwise, invoke the `gsd-jira-sync` skill's own documented
   single-event workflow (`gsd-jira-sync execute_started <issue_key> --phase N`) — do not inline
   `draft-jira-comment.sh`'s draft/post/stamp steps here. That skill owns drafting the comment
   body, the `addCommentToJiraIssue` MCP call, and running `emit-stamp.sh`; this skill only
   decides *whether* to call it and *what* to pass.

6. **Call native `gsd-execute-phase N [--wave W]` directly**, in this same turn. Invoking
   `recipe-run-phase` was itself the operator's deliberate act of choosing to execute this phase —
   that IS the manual GSD trigger; this is not an unapproved autonomous invocation. Add no DAG
   pre-req/post-op gating here (`RUNTIME-LLD.md` §1.c.2.a/b — parked pending TASK-009) and
   implement no `execute_wave` handling — `gsd-execute-phase` owns its own internal wave
   orchestration; this skill never second-guesses it.

7. **Emit `execute_complete`** (only when step 4 resolved an issue key), the same skill-to-skill
   way as step 5, once `gsd-execute-phase` returns — idempotent via the same
   `<resolved> has`-check pattern (key computed with `execute_complete` instead of
   `execute_started`, same `recipe-paths.sh`-resolved `sync-ledger.sh` path from step 5).

8. **Summarize**, in one final line to the operator: phase number, resolved issue key (or "none
   linked"), the planning-policy gate result (`compliant` / `warned-and-confirmed` /
   `operator declined — stopped`), and the two post results
   (`execute_started`/`execute_complete`: `posted` / `duplicate_skipped` / `skipped-no-issue`).

## D. Do NOT

- Do not implement DAG pre-req/post-op gating (`RUNTIME-LLD.md` §1.c.2.a/b) — parked pending
  TASK-009 per `DECISIONS.md`. Never read or write `.knowledge/dag/*`.
- Do not implement `execute_wave` handling or any DAG-dependent wave-selection heuristics — those
  stay `gsd-execute-phase`'s own territory, and are explicitly out of scope per
  `bench/runners/sync-reconcile.sh`'s header comments on why `execute_wave` isn't auto-inferred
  either.
- Do not fill or fabricate the Prerequisites table yourself, ever — even while warning that it's
  unfilled. That is the planner's job, gated by the `recipe-planning-policy` skill, not this one.
- Do not inline Jira drafting/posting/stamping logic (`draft-jira-comment.sh`'s steps) directly —
  always call into `gsd-jira-sync`'s documented workflow instead for both `execute_started` and
  `execute_complete`.
- Do not hard-block on a missing/unfilled Prerequisites table — warn-and-confirm only (soft gate,
  decision #2). The operator can always choose to proceed.
- Do not hard-block on an unresolved issue key — warn and continue straight to
  `gsd-execute-phase` regardless (fail-open on tracker/MCP issues; this is the expected path for
  the baseline arm or any repo with no tracker linked yet).
- Do not touch `recipe-run-phases` (plural, TASK-018, not yet built) — that is a separate
  multi-phase loop wrapper. This skill only ever runs a single phase per invocation.
- Do not re-run `gsd-plan-phase` on the operator's behalf when `PLAN.md` is missing — tell them to
  run it, then stop.
</cursor_skill_adapter>

# recipe-run-phase — gated single-phase execute (TASK-024)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §2.a "Execute", tag **[N]** for the
underlying `gsd-execute-phase` call, **[C]** for this wrapper's gating/tracker-linkage layer) —
GSD stays the orchestrator; this skill adds a read-only planning-policy compliance check, an
informational `depends_on` reminder, and `execute_started`/`execute_complete` tracker sync around
a direct, same-turn call to native `gsd-execute-phase`.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §2.a · `docs/netapp-recipe/BACKLOG.md` TASK-024.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016) and
`recipe-planning-policy` (TASK-012) ahead of the full `install.sh` (TASK-010) — this skill has its
own installer, `.gsd-recipe/scripts/install-recipe-run-phase.sh`, and is also composed into
`install.sh` as a fourth sub-installer.

## Workflow

1. Resolve the phase's `PLAN.md` (glob; missing → stop, tell operator to plan first).
2. Read-only planning-policy gate: 7 mandatory sections + filled Prerequisites table. Soft
   warn-and-confirm if non-compliant — never a hard block, never fills the table.
3. Print any declared `depends_on` phases as an informational, non-blocking reminder.
4. Resolve the phase's tracker issue key via `parse-state.sh resolve-issue`. Unresolved → warn and
   continue (fail-open).
5. Emit `execute_started` via the `gsd-jira-sync` skill (idempotent), if an issue key resolved.
6. Call native `gsd-execute-phase N [--wave W]` directly, in the same turn (Option B — the
   operator's own invocation of `recipe-run-phase` is the manual GSD trigger).
7. Emit `execute_complete` the same skill-to-skill way, once `gsd-execute-phase` returns.
8. Summarize phase/issue/gate-result/post-results in one line.

## Why Option B (direct same-turn call), not a background/async trigger

Decision #1 (approved): the operator's own act of invoking `recipe-run-phase` already is the
"human decided to execute this phase" gate `RUNTIME-LLD.md` describes for `gsd-execute-phase`.
Unlike `recipe-prd-intake`'s deliberate *non*-invocation of `gsd-discuss-phase` (that skill
explicitly defers to the operator to run discuss themselves — see its own SKILL.md § D), this
skill is explicitly approved to call `gsd-execute-phase` on the operator's behalf, because
`recipe-run-phase N` *is* the operator's request to run phase `N` right now.

## What this does NOT do (see the integration report for the full rationale)

- **No DAG pre-req/post-op gating.** `RUNTIME-LLD.md` §1.c.2.a/b describes a `.knowledge/dag/`
  eligibility check and a `verified` status write-back — both depend on TASK-009's `dag-build.sh`,
  which is parked per `DECISIONS.md` ("Not required for v1"). This skill never reads or writes
  `.knowledge/dag/*`.
- **No `execute_wave` handling.** `gsd-execute-phase --wave W` already owns intra-phase wave
  orchestration; this skill only ever forwards `--wave W` verbatim, never inspects or infers wave
  state itself.
- **No Prerequisites-table filling.** The compliance gate is strictly read-only — it warns, it
  never writes to `PLAN.md`.
- **No inlined Jira posting logic.** `execute_started`/`execute_complete` are emitted by invoking
  `gsd-jira-sync`'s documented workflow, not by calling `draft-jira-comment.sh` and the Atlassian
  MCP directly from within this skill.

## Fail-open behavior on tracker/MCP issues

If `.planning/STATE.md` has no tracker section, no phase-task row for `N`, or the Atlassian MCP is
unreachable/unauthenticated when `gsd-jira-sync` is invoked, this skill never blocks
`gsd-execute-phase` on that account — it warns and continues. The only two conditions that stop
this skill before calling `gsd-execute-phase` are: (a) `PLAN.md` for phase `N` doesn't exist at
all, or (b) the operator explicitly declines to proceed past the soft planning-policy gate.
