---
name: recipe-review-ship
description: "Recipe: gated single-phase review-and-ship wrapper for the NetApp GSD recipe (TASK-026). Calls native gsd-code-review N directly, resolves the phase's tracker issue key via parse-state.sh and emits review_complete by invoking the gsd-jira-sync skill (idempotent via sync-ledger.sh, with the event's optional 'In Review' transition), then calls native gsd-ship N [--draft] directly and surfaces the resulting PR link — printing gsd-review/gsd-ui-review N as informational-only suggestions, never auto-invoking either."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-review-ship`) with:
- `N` — the phase number to review and ship (required).
- `--draft` — optional, forwarded verbatim to `gsd-ship N --draft`.

Examples:
- `recipe-review-ship 3`
- `recipe-review-ship 3 --draft`

## B. Prerequisites

- `gsd-ship N`'s own documented prerequisite is "`gsd-verify-work` passed for phase `N`"
  (`RUNTIME-LLD.md` §4.c). This skill does **not** re-check or re-verify that itself — that is
  `recipe-verify-feature`'s (TASK-025) job, not this one. It just calls `gsd-ship N` in step 4 and
  surfaces whatever native GSD itself reports if the prerequisite isn't met; it never silently
  bypasses or fakes a passed state.
- `.planning/STATE.md` may or may not have a tracker section / phase-task row for phase `N`. If it
  doesn't, this skill continues in warn-and-continue mode (see step 2) — it never blocks on a
  missing tracker linkage.

## C. Tool Usage

1. **Call native `gsd-code-review N` directly**, in this same turn. Invoking `recipe-review-ship`
   was itself the operator's deliberate act of choosing to review (and ship) this phase now — that
   IS the manual GSD trigger; this is not an unapproved autonomous invocation (same precedent as
   `recipe-plan-phase`'s direct call to `gsd-plan-phase` and `recipe-run-phase`'s direct call to
   `gsd-execute-phase`). This produces `REVIEW.md` per `RUNTIME-LLD.md` §4.a.

2. **Resolve the issue key.** `bench/lib/parse-state.sh` is not duplicated into every target by
   design — resolve its real path via `.gsd-recipe/scripts/recipe-paths.sh` first (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full), then run:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   "$RESOLVED" resolve-issue review_complete --phase N
   ```
   - Resolves → carry that issue key into step 3.
   - Fails (no `.planning/STATE.md`, no `## Tracker` section, or no matching phase-task row for
     `N`) → do not block. Warn the operator ("No tracker issue linked for phase N — skipping Jira
     sync, continuing with gsd-ship") and skip straight to step 4.

3. **Emit `review_complete`** (only when step 2 resolved an issue key). `bench/lib/sync-ledger.sh`
   needs the same `recipe-paths.sh` resolution as step 2 above — resolve it once, then compute the
   idempotency key via `<resolved> key review_complete <issue_key> --phase N` and check
   `<resolved> has <key>` first. Already present → skip (report `duplicate_skipped`,
   no re-post). Otherwise, invoke the `gsd-jira-sync` skill's own documented single-event workflow
   (`gsd-jira-sync review_complete <issue_key> --phase N`) — do not inline
   `draft-jira-comment.sh`'s draft/post/stamp steps here. That skill owns drafting the comment
   body, the `addCommentToJiraIssue` MCP call, and running `emit-stamp.sh`; this skill only decides
   *whether* to call it and *what* to pass. `jira-events.json`'s `review_complete` entry marks its
   transition as `"optional: In Review"` — pass `--transition "In Review"` when invoking
   `gsd-jira-sync` so that skill's own step 5 (`getTransitionsForJiraIssue` confirmation before
   `transitionJiraIssue`) can decide whether the transition actually applies; never transition
   directly from this skill.

4. **Call native `gsd-ship N [--draft]` directly**, in this same turn. This skill never re-verifies
   `gsd-ship`'s own documented prerequisite ("`gsd-verify-work` passed for phase") itself — that
   check belongs to `recipe-verify-feature` (TASK-025). If native GSD reports the prerequisite
   isn't met (or any other failure), surface that report to the operator verbatim and stop here —
   never silently bypass it, never fabricate a passed state, never proceed to step 5 as if a PR
   were created when one wasn't.

5. **Surface the PR link.** Once `gsd-ship` returns successfully, print the resulting PR URL/link
   it reports to the operator. Do not fabricate a URL if `gsd-ship` didn't produce one — report
   plainly that no PR link was returned.

6. **Print informational-only suggestions** for the two optional review paths `RUNTIME-LLD.md`
   §4.a also lists: `gsd-review` (optional cross-AI peer review of plans) and `gsd-ui-review N`
   (if the phase is front-end-facing, paired with browser MCP). Print both as plain suggestions the
   operator can run themselves — **never auto-invoke either.**

7. **Summarize**, in one final line to the operator: phase number, resolved issue key (or "none
   linked"), the `review_complete` post result (`posted` / `duplicate_skipped` /
   `skipped-no-issue`), and the ship result (PR link, or the native failure reported in step 4).

## D. Do NOT

- Do not re-verify `gsd-verify-work`'s pass/fail state for phase `N` yourself before calling
  `gsd-ship` — that is `recipe-verify-feature`'s (TASK-025) job. Never silently bypass or fake a
  passed state; just call `gsd-ship N` and surface whatever native GSD itself reports.
- Do not invent a distinct sync event for the ship/PR-creation step. `jira-events.json`'s only
  later-lifecycle event, `settled`, is explicitly triggered by "PO accept + CI green" — that is a
  different task (`recipe-settle`, TASK-027), not this one. There is no `ship_complete`/
  `pr_opened` event in the catalog; do not add one.
- Do not bundle `bench/runners/draft-github-pr-comment.sh` (TASK-006) posting into this skill's own
  flow. That stays a separate, standalone tool an operator can run independently — this skill never
  invokes it.
- Do not auto-invoke `gsd-review` (optional cross-AI peer review) or `gsd-ui-review N` on the
  operator's behalf. Both are print-only informational suggestions in this skill's own output.
- Do not inline Jira drafting/posting/stamping logic (`draft-jira-comment.sh`'s steps) directly —
  always call into `gsd-jira-sync`'s documented workflow instead for `review_complete`.
- Do not transition the Jira issue directly from this skill (e.g. calling `transitionJiraIssue`
  itself) — pass `--transition "In Review"` to `gsd-jira-sync` and let that skill's own
  confirm-before-transition step decide.
- Do not hard-block on an unresolved issue key — warn and continue straight to `gsd-code-review`/
  `gsd-ship` regardless (fail-open on tracker/MCP issues; this is the expected path for the
  baseline arm or any repo with no tracker linked yet).
- Do not proceed to step 5 (surfacing a PR link) if `gsd-ship` itself reported failure or an unmet
  prerequisite — stop and report that plainly instead of fabricating a link.
</cursor_skill_adapter>

# recipe-review-ship — gated single-phase review and ship (TASK-026)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §4 "Review and ship", tag **[N]** for
the underlying `gsd-code-review`/`gsd-ship` calls, **[C]** for this wrapper's tracker-linkage
layer) — GSD stays the orchestrator; this skill adds `review_complete` tracker sync (with the
event's optional "In Review" transition) between a direct, same-turn call to native
`gsd-code-review` and a direct, same-turn call to native `gsd-ship`, then surfaces the resulting PR
link.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §4.a, §4.c · `docs/netapp-recipe/BACKLOG.md`
TASK-026.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) ahead of the full `install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-review-ship.sh`. Composition into `install.sh` as a ninth
sub-installer is deferred to a later integration pass (see the integration report) — three sibling
tasks (TASK-018/025/027) are being built concurrently against the same shared files.

## Workflow

1. Call native `gsd-code-review N` directly, in the same turn (Option B — the operator's own
   invocation of `recipe-review-ship` is the manual GSD trigger). Produces `REVIEW.md`.
2. Resolve the phase's tracker issue key via `parse-state.sh resolve-issue review_complete --phase
   N`. Unresolved → warn and continue (fail-open).
3. Emit `review_complete` via the `gsd-jira-sync` skill (idempotent), with the optional `"In
   Review"` transition, if an issue key resolved.
4. Call native `gsd-ship N [--draft]` directly, in the same turn. Does not re-verify `gsd-ship`'s
   own documented prerequisite (`gsd-verify-work` passed) — surfaces whatever native GSD reports if
   unmet.
5. Surface the resulting PR URL/link to the operator (or report plainly that none was returned).
6. Print `gsd-review`/`gsd-ui-review N` as informational-only suggestions — never auto-invoke
   either.
7. Summarize phase/issue/post-result/ship-result in one line.

## Why Option B (direct same-turn call), not a background/async trigger

Decision #1 (approved): the operator's own act of invoking `recipe-review-ship` already is the
"human decided to review and ship this phase" gate `RUNTIME-LLD.md` describes for
`gsd-code-review`/`gsd-ship` — same reasoning already approved for `recipe-plan-phase`'s direct
call to `gsd-plan-phase` and `recipe-run-phase`'s direct call to `gsd-execute-phase`. Unlike
`recipe-prd-intake`'s deliberate *non*-invocation of `gsd-discuss-phase` (that skill explicitly
defers to the operator to run discuss themselves — see its own SKILL.md § D), this skill is
explicitly approved to call both `gsd-code-review` and `gsd-ship` on the operator's behalf, because
`recipe-review-ship N` *is* the operator's request to review and ship phase `N` right now.

## Why there is no `ship_complete`/`pr_opened` sync event

Decision #2 (approved): `jira-events.json`'s only relevant later-lifecycle event is `settled`,
explicitly triggered by "PO accept + CI green" — a fundamentally different milestone (PO acceptance
and green CI, not the act of opening the PR) owned by a different task (`recipe-settle`,
TASK-027). This skill does not invent a new event id for the `gsd-ship`/PR-creation step itself; it
only syncs `review_complete` between the two native calls, and simply prints/surfaces the PR link
that `gsd-ship` itself returns.

## What this does NOT do (see the integration report for the full rationale)

- **No re-verification of `gsd-ship`'s prerequisite.** `gsd-ship N`'s own documented prerequisite
  ("`gsd-verify-work` passed for phase") is `recipe-verify-feature`'s (TASK-025) job to gate, not
  this skill's. This skill calls `gsd-ship N` and surfaces whatever native GSD itself reports if
  the prerequisite isn't met — it never silently bypasses or fakes a passed state.
- **No bundled GitHub PR comment posting.** `bench/runners/draft-github-pr-comment.sh` (TASK-006)
  stays a separate, standalone tool an operator can run independently; this skill's own flow never
  invokes it.
- **No auto-invocation of `gsd-review` or `gsd-ui-review N`.** Both are optional per
  `RUNTIME-LLD.md` §4.a; this skill only prints them as informational suggestions in its own
  output, never calls either on the operator's behalf.
- **No new sync event.** See "Why there is no `ship_complete`/`pr_opened` sync event" above.
- **No inlined Jira posting logic.** `review_complete` is emitted by invoking `gsd-jira-sync`'s
  documented workflow, not by calling `draft-jira-comment.sh` and the Atlassian MCP directly from
  within this skill.
- **No direct Jira transition call.** The optional `"In Review"` transition is passed as
  `--transition "In Review"` to `gsd-jira-sync`, which owns confirming the transition name via
  `getTransitionsForJiraIssue` before calling `transitionJiraIssue` — this skill never calls
  `transitionJiraIssue` itself.

## Fail-open behavior on tracker/MCP issues

If `.planning/STATE.md` has no tracker section, no phase-task row for `N`, or the Atlassian MCP is
unreachable/unauthenticated when `gsd-jira-sync` is invoked, this skill never blocks
`gsd-code-review`/`gsd-ship` on that account — it warns and continues. The only condition that
stops this skill before calling `gsd-ship` (step 4) or before surfacing a PR link (step 5) is
native GSD itself reporting a failure or an unmet prerequisite — never a tracker/MCP issue.
