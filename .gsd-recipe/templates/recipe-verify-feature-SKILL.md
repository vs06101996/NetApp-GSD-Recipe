---
name: recipe-verify-feature
description: "Recipe: gated single-phase verify wrapper for the NetApp GSD recipe (TASK-025). Resolves the phase's tracker issue key, then chains native gsd-audit-milestone (informational gap analysis vs ROADMAP DoD, no stamp, never blocks) and gsd-audit-uat (cross-phase UAT, warn-and-skip if not applicable) directly, then calls native gsd-verify-work N directly — the genuinely conversational/interactive UAT command, run live with the operator, never scripted — and once that returns, emits verify_complete by invoking the gsd-jira-sync skill (idempotent via sync-ledger.sh, fail-open when no tracker issue is linked)."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-verify-feature`) with:
- `N` — the phase number to verify (required).

Examples:
- `recipe-verify-feature 3`

## B. Prerequisites

- Phase `N` should generally have already been executed (`gsd-execute-phase N` /
  `recipe-run-phase N`) — this skill does not check for or require a `SUMMARY.md`/`PLAN.md`
  before proceeding, because `gsd-verify-work N` (step 4) is itself the command responsible for
  deciding what there is to verify. Unlike `recipe-run-phase`'s pre-hoc `PLAN.md` existence gate,
  this skill has no equivalent hard prerequisite — it always proceeds through all 4 native/skill
  steps below.
- `.planning/STATE.md` may or may not have a tracker section / phase-task row for phase `N`. If it
  doesn't, this skill continues in warn-and-continue mode (see step 1) — it never blocks on a
  missing tracker linkage.

## C. Tool Usage

1. **Resolve the issue key.** Run
   `bench/lib/parse-state.sh resolve-issue verify_complete --phase N`.
   - Resolves → carry that issue key into step 5.
   - Fails (no `.planning/STATE.md`, no `## Tracker` section, or no matching phase-task row for
     `N`) → do not block. Warn the operator ("No tracker issue linked for phase N — skipping Jira
     sync, continuing with verification") and continue straight to step 2 regardless.

2. **Call native `gsd-audit-milestone` directly**, in this same turn (Option B — see "Why Option
   B" below). This is `RUNTIME-LLD.md` §3.a's **informational gap analysis vs ROADMAP DoD** —
   it produces no stamp (`jira-events.json` defines no event for this step; `verify_complete`'s
   own stamp is `null` too, and this step is a full level earlier than that), and it **never
   blocks the rest of this workflow**, regardless of what it reports. If `gsd-audit-milestone`
   isn't applicable in this context (e.g. no `ROADMAP.md`/milestone concept for this repo, or the
   command errors/isn't available) — print a plain warning naming what happened and continue
   straight to step 3. Never fabricate a gap-analysis result to fill in for a skipped or failed
   call; a warn-and-skip here reports honestly that milestone-gap analysis did not run this time.

3. **Call native `gsd-audit-uat` directly**, in this same turn, same Option-B reasoning as step 2.
   This is `RUNTIME-LLD.md` §3.b's **cross-phase UAT** debt check. Same graceful-degradation rule
   as step 2: if it isn't applicable/available (e.g. no other phases yet to cross-check, or the
   command errors), warn and continue straight to step 4 — never hard-fail the whole
   `recipe-verify-feature` invocation on this account, and never fabricate a result. Do not call
   `gsd-audit-fix` here even optionally — `RUNTIME-LLD.md` §3.b lists it as a separate, distinct
   follow-up command the operator can choose to run themselves after seeing `gsd-audit-uat`'s
   output; this skill's job is the audit, not an automated fix pass.

4. **Call native `gsd-verify-work N` directly**, in this same turn, same Option-B reasoning as
   steps 2-3 — **but read this step's note carefully before treating it like steps 2-3.**
   `gsd-verify-work N` is `RUNTIME-LLD.md` §3.c's **conversational, interactive UAT command** —
   per `docs/GSD-COMMANDS.md`, it is literally "Conversational UAT from SUMMARYs; may create fix
   plans." This is a **meaningfully different shape from every other native call this skill (or
   any sibling `recipe-*` skill in this backlog) makes**: steps 2-3 above, and every native call in
   `recipe-plan-phase`/`recipe-run-phase`/`recipe-bootstrap-knowledge`, are one-shot commands that
   run to completion and return a result for this skill to inspect. `gsd-verify-work N` is not —
   it opens a live back-and-forth with the operator (asking what to check, walking through
   acceptance criteria, possibly proposing fix plans mid-conversation). This skill's job at this
   step is to **call it and then get out of the way**: let its own conversational flow run exactly
   as it would if the operator had typed `gsd-verify-work N` directly, asking the operator its own
   questions and reading their own answers. Do **not** attempt to script, pre-answer, simulate, or
   shortcut that conversation on the operator's behalf, and do not treat a mid-conversation pause
   as a failure requiring a warn-and-skip (unlike steps 2-3, this step is not something to
   gracefully degrade past — it is the whole reason the operator invoked
   `recipe-verify-feature` in the first place). Step 5 begins only once `gsd-verify-work N`'s own
   conversational flow has genuinely concluded (the operator and the native command have reached
   an end state — accepted, rejected with fix plans queued, or otherwise closed out).

5. **Emit `verify_complete`** (only when step 1 resolved an issue key), once `gsd-verify-work N`
   has genuinely concluded. Compute the idempotency key via
   `bench/lib/sync-ledger.sh key verify_complete <issue_key> --phase N` and check
   `bench/lib/sync-ledger.sh has <key>` first. Already present → skip (report `duplicate_skipped`,
   no re-post). Otherwise, invoke the `gsd-jira-sync` skill's own documented single-event workflow
   (`gsd-jira-sync verify_complete <issue_key> --phase N`) — do not inline
   `draft-jira-comment.sh`'s draft/post/stamp steps here. That skill owns drafting the comment
   body, the `addCommentToJiraIssue` MCP call, and running `emit-stamp.sh` (a no-op here per
   `jira-events.json`'s `"stamp": null` for `verify_complete` — the comment still posts; there is
   simply no KPI stamp tied to this particular event); this skill only decides *whether* to call
   it and *what* to pass.

6. **Summarize**, in one final report to the operator: phase number, resolved issue key (or "none
   linked"), the `gsd-audit-milestone` outcome (`ran` / `skipped — <reason>`), the `gsd-audit-uat`
   outcome (`ran` / `skipped — <reason>`), confirmation that `gsd-verify-work N`'s conversational
   flow concluded, and the tracker post result (`posted` / `duplicate_skipped` /
   `skipped-no-issue`).

## D. Do NOT

- Do not script, pre-answer, simulate, or shortcut `gsd-verify-work N`'s own conversational UAT
  flow — step 4 is genuinely interactive; this skill's role there is to invoke it and then defer
  entirely to its own back-and-forth with the operator, not to automate around it.
- Do not fabricate a `gsd-audit-milestone` or `gsd-audit-uat` result when either is skipped —
  report the skip and its reason plainly; never invent a gap-analysis or cross-phase-UAT finding
  to fill the gap.
- Do not hard-fail the whole `recipe-verify-feature` invocation because `gsd-audit-milestone` or
  `gsd-audit-uat` wasn't applicable/available — warn-and-skip only, and always continue on to the
  next step (steps 2 and 3 are each independently, individually skippable; step 4 is not).
- Do not call `gsd-audit-fix` (with or without `--dry-run`) — that is a separate, operator-invoked
  follow-up to `gsd-audit-uat`'s output per `RUNTIME-LLD.md` §3.b, not part of this skill's chain.
- Do not implement Bootstrap Gate A/B (`RUNTIME-LLD.md` §3.c.1, `bare_metal.template.md`
  re-run) — explicitly out of scope for this task (feasibility caveat: those commands are
  repo-specific, `bare_metal.template.md` is generic; see the integration report).
- Do not implement the `gsd-debug` recovery loop (`RUNTIME-LLD.md` §3.c.2, `gsd-debug "..."` /
  `gsd-debug list` / `gsd-debug continue <slug>`) — explicitly out of scope for this task. If
  `gsd-verify-work N`'s own conversation surfaces an environment failure, that stays the
  operator's own separate `gsd-debug` call, never triggered by this skill.
- Do not implement or call any benchmark/project-specific grader hook (`bench/grade/grade.sh` or
  similar) — explicitly out of scope for this task, same precedent as the parked DAG work.
  `RUNTIME-LLD.md` and `docs/GSD-COMMANDS.md` are both explicit that `gsd-verify-work` alone is
  never production sign-off / the grader; this skill does not blur that line by wiring one in.
- Do not inline Jira drafting/posting/stamping logic (`draft-jira-comment.sh`'s steps) directly —
  always call into `gsd-jira-sync`'s documented workflow instead for `verify_complete`.
- Do not hard-block on a missing/unresolved issue key — warn and continue straight through steps
  2-4 regardless (fail-open on tracker/MCP issues; this is the expected path for the baseline arm
  or any repo with no tracker linked yet).
- Do not emit any stamp for the `gsd-audit-milestone` or `gsd-audit-uat` calls — per
  `RUNTIME-LLD.md` §3.a's own table, that step's stamp is explicitly "None (feeds settle gate)";
  only `verify_complete` (step 5, itself stamp-null per `jira-events.json`) ever reaches
  `gsd-jira-sync` in this skill.
</cursor_skill_adapter>

# recipe-verify-feature — gated single-phase verify (TASK-025)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §3 "Verify" — §3.a Milestone
completion, §3.b Cross-phase UAT, §3.c Manual UAT + bare metal — tag **[N]** for the three
underlying native calls) — GSD stays the orchestrator; this skill adds tracker issue resolution, a
direct, same-turn chain of `gsd-audit-milestone` → `gsd-audit-uat` → `gsd-verify-work N`, and a
`verify_complete` tracker sync once that chain (and specifically `gsd-verify-work N`'s own
conversational flow) concludes.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §3 · `docs/netapp-recipe/BACKLOG.md` TASK-025.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), `recipe-plan-phase`
(TASK-017), and `recipe-bootstrap-knowledge` (TASK-022) ahead of/alongside the full `install.sh`
(TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-verify-feature.sh`, intended to also be composed into
`install.sh` as a sub-installer in a follow-up integration pass (see the integration report for
the exact `install.sh` wiring snippet, held back from this task's own diff to avoid a merge
conflict with sibling tasks editing `install.sh` concurrently).

## Workflow

1. Resolve the phase's tracker issue key via `parse-state.sh resolve-issue verify_complete --phase
   N`. Unresolved → warn and continue (fail-open).
2. Call native `gsd-audit-milestone` directly, in the same turn (Option B). Informational gap
   analysis vs ROADMAP DoD, no stamp, never blocks — warn-and-skip if not applicable/available.
3. Call native `gsd-audit-uat` directly, in the same turn, same reasoning. Cross-phase UAT —
   warn-and-skip if not applicable/available. No `gsd-audit-fix` call.
4. Call native `gsd-verify-work N` directly, in the same turn, same reasoning — **but this step is
   genuinely interactive/conversational**, unlike every other native call in this skill or its
   siblings. Let its own back-and-forth with the operator run; do not script or shortcut it.
5. Once that conversation has concluded, emit `verify_complete` via the `gsd-jira-sync` skill
   (idempotent via `sync-ledger.sh`), if an issue key resolved in step 1.
6. Summarize phase/issue/audit-outcomes/verify-conclusion/post-result in one final report.

## Why Option B (direct same-turn calls), not a background/async trigger

Decision (approved, mirroring `recipe-plan-phase`'s, `recipe-run-phase`'s, and
`recipe-bootstrap-knowledge`'s own precedent — the same reasoning applied a fourth time, to a
fourth distinct set of native commands): the operator's own act of invoking
`recipe-verify-feature N` already is the "human decided to verify this phase now" gate
`RUNTIME-LLD.md` §3 describes for `gsd-audit-milestone`, `gsd-audit-uat`, and `gsd-verify-work N`.
`docs/netapp-recipe/AGENTS.md` line 11's standing rule — "User runs GSD skills manually — do not
invoke `gsd-plan-phase`, `gsd-execute-phase`, etc. on the user's behalf" — governs *autonomous*,
unrequested invocation on the operator's behalf. It does not forbid a skill the operator
explicitly named and ran from directly calling the native command(s) that skill exists to wrap, in
the same turn, as its documented job. This is the exact same reasoning
`recipe-plan-phase-SKILL.md`, `recipe-run-phase-SKILL.md`, and
`recipe-bootstrap-knowledge-SKILL.md` already establish — applied here, unchanged, to a fourth
distinct trio of native commands. No new precedent is created by this task.

**The one genuinely new wrinkle**, named explicitly rather than glossed over: every prior
Option-B native call in this recipe (`gsd-plan-phase`, `gsd-execute-phase`, `gsd-map-codebase`,
`gsd-graphify build`, `gsd-ingest-docs`, and this skill's own `gsd-audit-milestone`/`gsd-audit-uat`
in steps 2-3) is a one-shot command — the skill calls it, it runs to completion, and the skill
inspects a result. `gsd-verify-work N` (step 4) is not one-shot; it is `docs/GSD-COMMANDS.md`'s
own "Conversational UAT" — a live, multi-turn exchange with the operator that this skill does not
own or control the shape of. Option B still applies (the operator's invocation of
`recipe-verify-feature` is still the manual trigger for calling it), but this skill's
responsibility at that step is narrower than at every other step: invoke it, then step back and
let the native command's own conversational contract with the operator run unmodified. This is
why step 4's instructions above are markedly more detailed about what *not* to do than any other
step in this skill or its siblings.

## What this does NOT do (see the integration report for the full rationale)

- **No Bootstrap Gate A/B.** `RUNTIME-LLD.md` §3.c.1 describes re-running `bare_metal.template.md`
  commands and writing `.knowledge/bootstrap-status.json` — explicitly out of scope for this task.
  Feasibility caveat carried verbatim from the spec: "Commands are repo-specific; template is
  generic," meaning a general-purpose skill cannot safely auto-run them.
- **No `gsd-debug` recovery loop.** `RUNTIME-LLD.md` §3.c.2's environment-failure recovery pattern
  (`gsd-debug "..."` / `gsd-debug list` / `gsd-debug continue <slug>`) stays a separate,
  operator-triggered call, never invoked by this skill even if `gsd-verify-work N`'s own
  conversation surfaces an environment failure.
- **No benchmark/project-specific grader hook.** This skill never calls `bench/grade/grade.sh` or
  any project grader — `RUNTIME-LLD.md` and `docs/GSD-COMMANDS.md` are both explicit that
  `gsd-verify-work` alone is never production sign-off; wiring a grader call in here would blur
  that line. Same "parked, not required for v1" precedent as the DAG work (TASK-009).
- **No `gsd-audit-fix` call.** A separate, operator-invoked follow-up to `gsd-audit-uat`'s
  findings, not part of this skill's chain.
- **No fabricated audit results.** A skipped/unavailable `gsd-audit-milestone` or `gsd-audit-uat`
  is reported as a skip with a reason, never as an invented finding.
- **No scripting of `gsd-verify-work N`'s conversation.** See "The one genuinely new wrinkle"
  above.
- **No inlined Jira posting logic.** `verify_complete` is emitted by invoking `gsd-jira-sync`'s
  documented workflow, not by calling `draft-jira-comment.sh` and the Atlassian MCP directly from
  within this skill.

## Fail-open behavior on tracker/MCP issues

If `.planning/STATE.md` has no tracker section, no phase-task row for `N`, or the Atlassian MCP is
unreachable/unauthenticated when `gsd-jira-sync` is invoked, this skill never blocks any of steps
2-4 on that account — it warns and continues. There is no condition in this skill's documented
workflow where a tracker/MCP problem stops verification itself; only `gsd-verify-work N`'s own
conversational outcome (step 4) and, informationally, `gsd-audit-milestone`/`gsd-audit-uat`'s
applicability (steps 2-3) affect what gets reported in the final summary.
