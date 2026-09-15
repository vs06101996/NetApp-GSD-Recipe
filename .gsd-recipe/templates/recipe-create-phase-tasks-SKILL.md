---
name: recipe-create-phase-tasks
description: "Recipe: creates one Jira phase task per ROADMAP phase with verified native Parent hierarchy when the project's Task create metadata supports it; uses the legacy Epic Link custom field only as an explicit compatibility fallback, and never records an orphan as successful."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-create-phase-tasks`) with:
- `--issue-type NAME` — optional. Skip auto-resolution (step 4) and use this Jira issue type for
  the whole batch.
- `--assignee NAME` — optional. Same resolution as `recipe-create-epic` (`--assignee`, then
  config `assignee`, then `git config user.name`, then a live question). Applied to every
  created phase task via `lookupJiraAccountId` → `assignee_account_id`.
- `--dry-run` — optional. Passed straight through to `create-phase-tasks.sh detect`'s own
  `--dry-run` (drafts nothing to disk); still useful to preview what `detect` would queue, but a
  `--dry-run` invocation never reaches the MCP-calling steps below (there is nothing in `list`'s
  `work` array to act on when `detect` wrote no queue rows).
- `--roadmap PATH` / `--state PATH` / `--queue PATH` — optional path overrides, passed straight
  through to both `detect` and `list`.

Examples:
- `recipe-create-phase-tasks`
- `recipe-create-phase-tasks --assignee "Ada Lovelace"`
- `recipe-create-phase-tasks --issue-type "Task"`
- `recipe-create-phase-tasks --dry-run`

## B. Prerequisites

- `.planning/STATE.md` must already have a `## Tracker` section with a non-empty `epic` — this is
  `create-phase-tasks.sh detect`'s own fail-closed check (`parse-state.sh get-tracker`), not
  something this skill re-implements. If it fails, **do not** just surface the raw script error —
  tell the operator plainly to run `recipe-create-epic` (TASK-033) first, then retry.
- `ROADMAP.md` must have at least one `## Phase N — Title` heading (same `detect` check).
- Atlassian MCP enabled and authenticated — needed starting at step 4. An empty tool-discovery
  result is **inconclusive** because Cursor may idle-suspend a healthy HTTP transport. Invoke the
  known `getAccessibleAtlassianResources` operation once as a wake probe, then retry discovery.
  Only a real invocation/authentication failure counts as unavailable.

## C. Tool Usage

`bench/runners/create-phase-tasks.sh` is not duplicated into every target by design — resolve its
real path once, via `.gsd-recipe/scripts/recipe-paths.sh` (same mechanism
`recipe-validate-tokens-SKILL.md` § C step 1 documents in full), and reuse that resolved path for
every step below (1, 2, 8):
```
RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/create-phase-tasks.sh)"
```

1. `Shell`: `<resolved> detect [--dry-run] [--roadmap PATH] [--state PATH]
   [--queue PATH] [--arm recipe] [--run RUN_ID]` — drafts anything newly discovered from
   `ROADMAP.md` into the queue. Run this **exactly once**, up front.
2. `Shell`: `<resolved> list [--queue PATH] [--state PATH]` — self-heals
   anything already linked out-of-band and returns the genuinely-pending `work` array.
3. If `work` is empty: report "nothing to create" (including any `self_healed` count from step 2)
   and **stop cleanly** — no further steps, no MCP calls.
4. Wake the known `plugin-atlassian-atlassian` transport with a real
   `getAccessibleAtlassianResources` invocation when discovery is empty, then read the
   `getJiraProjectIssueTypesMetadata` and `getJiraIssueTypeMetaWithFields` — read once for the
   project derived from the linked epic's key prefix. Prefer a standard `"Task"` whose create
   metadata exposes writable field key `parent`; otherwise use another standard level-0 type
   selected by the operator. Never prefer `"Sub-task"` directly under an Epic: Jira schemes
   normally require a Sub-task's parent to be a level-0 Task/Story, not an Epic.
   Then `lookupJiraAccountId` for the assignee (see `--assignee` / config / git user.name).
5. Soft confirm gate — print the full batch, the resolved issue type, and the **assignee**; ask yes/no.
6. `GetMcpTools` tools `createJiraIssue`, `getJiraIssue`,
   `getTransitionsForJiraIssue`, `transitionJiraIssue`.
7. For each work item, ascending `phase_id` order: `CallMcpTool createJiraIssue` including
   `assignee_account_id` and `parent: <epic_key>` in the same create call when metadata exposes
   the native Parent field. Then call `getJiraIssue` for `parent`; success requires
   `fields.parent.key == epic_key`.
   - Compatibility fallback only: if the selected standard issue type has no Parent field but
     exposes the Jira Epic Link custom field in create metadata, create with
     `additional_fields: {"<reported-customfield-id>": "<epic_key>"}` and verify that exact
     custom field after creation. Report this row as `legacy-epic-link`, not native parent.
   - If neither native Parent nor Epic Link is writable, `mark-failed`; never create or accept a
     generic `createIssueLink` as hierarchy and never record an orphan as successful.
   Then transition the new issue to **To Do** (Backlog / Open / New aliases) unless already there.
8. `Shell`: `<resolved> mark-done <phase_id> <issue_key> [--state PATH]
   [--queue PATH]` on success, or `<resolved> mark-failed <phase_id> --error "<reason>" [--queue PATH]` on
   failure — every single row, no exceptions.

## D. Do NOT

- Never call `mark-done` before `createJiraIssue` succeeds and a follow-up `getJiraIssue`
  verifies either the native Parent key or the explicit legacy Epic Link fallback.
- Never skip `mark-failed` on error — an un-marked failure stays stuck as `queued` forever instead
  of being retried on the next `list` call.
- Never re-run `detect` mid-batch — it runs exactly once, up front (step 1). If the operator wants
  to pick up newly-added `ROADMAP.md` phases mid-session, that is a fresh, separate invocation of
  this skill, not a re-run inside the current one.
- Never call `addCommentToJiraIssue`/post any Jira **comment** from this skill — that stays
  `gsd-jira-sync`. Creating **does** set assignee and transition to **To Do**.
- Never fabricate an issue type or hierarchy field without checking what the target Jira instance
  actually offers (`getJiraProjectIssueTypesMetadata` /
  `getJiraIssueTypeMetaWithFields`). If no suitable standard issue type exists, list what IS
  available and ask the operator to pick, live; never guess.
- Never proceed past the step-5 confirm gate on a decline — stop cleanly, nothing created, nothing
  marked.
</cursor_skill_adapter>

# recipe-create-phase-tasks — agent-mediated phase-task creation (TASK-034)

Closes the exact gap `docs/netapp-recipe/BACKLOG.md`'s own TASK-007 row leaves open in writing:
`create-phase-tasks.sh` can **detect + draft + queue** a phase-task summary/description per
unlinked `ROADMAP.md` phase, but — same bash-has-no-MCP-access constraint as
`sync-reconcile.sh`/`gsd-jira-sync` — it "does not call `createJiraIssue`/`createIssueLink`
(agent-mediated, same split as `sync-reconcile.sh`)". This skill is that agent-mediated step,
wrapping `detect` + `list` + the two real MCP calls + `mark-done`/`mark-failed` into one
operator-invokable command, the same shape `gsd-jira-sync`'s Drain mode already established for
posting queued lifecycle comments — adapted here from "post a comment per queued lifecycle event"
to "create+link a Jira issue per queued phase task."

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` § "1.d Tracker epic + tasks [C]" ·
`docs/netapp-recipe/BACKLOG.md` TASK-007 (the gap this closes), TASK-034 (this skill).

**Built standalone**, the same pattern already used by `recipe-plan-phase` (TASK-017),
`recipe-run-phase` (TASK-024), and every other `recipe-*` skill ahead of/alongside the full
`install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh`, intended to also be composed into
`install.sh` as a sub-installer in a follow-up integration pass (see the integration report for
the exact `install.sh` wiring snippet, held back from this task's own diff to avoid a merge
conflict with sibling tasks — TASK-033 (`recipe-create-epic`), TASK-035 — editing `install.sh`
concurrently).

## Workflow

1. **Detect (once).** Run `create-phase-tasks.sh detect [--dry-run] [--roadmap PATH] [--state
   PATH] [--queue PATH] [--arm recipe] [--run RUN_ID]`. This drafts a summary/description for any
   `ROADMAP.md` phase that doesn't yet have a linked `issue_key` in `.planning/STATE.md`'s `##
   Phase tasks` table, and queues it to `.gsd-recipe/phase-tasks-queue.jsonl`. If it fails closed
   because there's no linked epic yet (`no '## Tracker' section found` / `tracker.epic is
   missing/empty`), **do not** just echo the raw error — tell the operator plainly: "No tracker
   epic linked yet — run `recipe-create-epic` first, then retry `recipe-create-phase-tasks`." and
   stop here.

2. **List (self-healed work).** Run `create-phase-tasks.sh list [--queue PATH] [--state PATH]`.
   This re-verifies every `queued`/`failed` row against `parse-state.sh dump`'s `phase_tasks`
   table FIRST — if a phase already has a linked `issue_key` there (someone ran `add-phase-task`
   manually in between, or a prior run got interrupted after `mark-done`'s `STATE.md` write but
   before its queue-row flip), that row is silently self-healed (flipped to `done`, counted under
   `self_healed`, **no MCP call**) rather than handed to this skill as a duplicate-create
   candidate. Returns `{work: [...], self_healed: N, errors: [...]}`; `work` items already carry
   every field needed for step 6-7 (`phase_id`, `key`, `epic_key`, `phase_title`, `phase_goal`,
   `drafted_summary`, `drafted_description`, `target`) — reused verbatim from `detect`'s own
   draft, never re-derived from `ROADMAP.md` again.

3. **Empty check.** If `work` is empty: report "nothing to create" — including the `self_healed`
   count from step 2 if non-zero (e.g. "0 to create, 2 self-healed-duplicate") — and **stop
   cleanly**. No step 4 onward, no MCP calls at all.

4. **Resolve the batch issue type and hierarchy field (once, not per-row).** Derive the Jira
   project key from the linked epic's key prefix, then call
   `getJiraProjectIssueTypesMetadata`. If `--issue-type NAME` was passed, validate that it exists;
   otherwise prefer `"Task"`, then another operator-selected standard level-0 issue type. Never
   choose `"Sub-task"` as a direct child of an Epic. Call `getJiraIssueTypeMetaWithFields` with
   `requiredFieldsOnly: false` for the selected type:
   - writable field key `parent` → native-parent mode (preferred);
   - otherwise writable Epic Link custom field → legacy-epic-link mode;
   - neither → stop before creation and explain that the project exposes no supported hierarchy
     field.

4b. **Resolve assignee (once for the batch).** Same order as `recipe-create-epic`: `--assignee`,
    `.gsd-recipe/config.json` `assignee`, `git config user.name`, else a live question. Then
    `lookupJiraAccountId`. Do not create unassigned phase tasks.

5. **Soft confirm gate.** Print the full batch (every work item's `phase_id` + `phase_title`), the
   resolved issue type, and the assignee; ask a plain yes/no question before creating anything remote. Decline →
   stop cleanly — nothing created, nothing marked, no further steps.

6. **Read MCP schemas once.** Read `createJiraIssue` and `getJiraIssue` once for the batch.

7. **For each work item, ascending `phase_id` order:**
   - `CallMcpTool createJiraIssue` with the resolved issue type + that row's
     `drafted_summary`/`drafted_description` + `assignee_account_id`. In native-parent mode include
     top-level `parent: epic_key`; in legacy mode include the metadata-reported Epic Link field
     under `additional_fields`.
   - **Verify hierarchy.** Call `getJiraIssue` requesting `parent` and, in legacy mode, the
     discovered custom field. A native row passes only when `parent.key == epic_key`; a legacy row
     passes only when its Epic Link value resolves to `epic_key`.
   - **Status:** `getTransitionsForJiraIssue` then `transitionJiraIssue` to **To Do** (or Backlog /
     Open / New). Already there → skip. No match → warn, still `mark-done` if create+link succeeded.
   - **On success:** `create-phase-tasks.sh mark-done <phase_id> <issue_key> [--state PATH]
     [--queue PATH]` — only after create + hierarchy verification.
   - **On failure (create or hierarchy verification):** `create-phase-tasks.sh mark-failed <phase_id> --error
     "<reason>" [--queue PATH]` — immediately, for that row, then **continue to the next work
     item** in the batch (never abort the whole batch on one row's failure, and never silently
     drop a failure — it must stay retryable via the next invocation's own `list` step, never
     re-attempted again later in this same run).

8. **Report a final summary:** `N created, M failed, K self-healed-duplicate` — the wording
   mirrors `gsd-jira-sync`'s own Drain-mode summary line (`N posted, M failed, K
   skipped-duplicate`), adapted from "posted" to "created". Include each created row's new
   `issue_key` and each failed row's error message in the detail, not just the counts.

## Why detect and list are two separate steps, not one

Same split `sync-drain-queue.sh`/`gsd-jira-sync`'s Drain mode already established, applied a
second time to a second queue: `detect` is the read-`ROADMAP.md`-and-draft step (expensive,
`ROADMAP.md`-dependent, meant to run once per invocation), and `list` is the
re-verify-against-STATE.md-and-self-heal step (cheap, meant to be safe to call again if this skill
were ever resumed mid-batch). Collapsing them into one step would either mean re-parsing
`ROADMAP.md` on every self-heal check (wasteful and risks a second `detect` run mutating the queue
mid-batch, exactly what step D's "never re-run detect mid-batch" rule forbids) or losing the
self-heal safety net `list` provides for free.

## Why the issue type is resolved once per batch, not once per row

`getJiraProjectIssueTypesMetadata` is a per-*project* lookup, not a per-*issue* lookup, and every
phase task in a single `recipe-create-phase-tasks` invocation shares the same epic and therefore
the same project. Calling it once and reusing the result for every row in step 7 avoids N
redundant MCP round-trips for what is structurally one decision, made once, at the top of the
batch (step 4) — the same "resolve once, act many times" shape `recipe-verify-feature`'s and
`recipe-plan-phase`'s own single-schema-read-then-loop steps already use elsewhere in this recipe.

## What this does NOT do (see the integration report for the full rationale)

- **No Jira comment posting.** `addCommentToJiraIssue` and any lifecycle-comment concern stay
  exclusively `gsd-jira-sync`'s job — this skill only ever creates+links new phase-task issues,
  never comments on them.
- **No mid-batch re-detection.** `detect` runs exactly once, at the very top (step 1) — a fresh
  `ROADMAP.md` phase added mid-session is picked up by the *next* invocation of this skill, not by
  this one re-running itself.
- **No fabricated issue types or hierarchy fields.** Both are resolved from live project metadata;
  no generic issue link is treated as Jira parent hierarchy.
- **No `recipe-create-epic` invocation.** If `detect` fails closed on a missing tracker epic, this
  skill tells the operator to run `recipe-create-epic` (TASK-033) themselves — it never invokes
  that skill (or any other GSD/recipe skill) on the operator's behalf as a silent side effect.
- **No DAG-order creation.** Phase tasks are created in ascending `phase_id` order (same as
  `detect`'s own numeric-not-lexicographic phase enumeration), not any dependency-graph order —
  Tier-1 DAG work (TASK-009) stays parked, same precedent as every other `recipe-*` skill in this
  backlog.

## Fail-open vs fail-closed boundaries

Unlike `recipe-plan-phase`/`recipe-verify-feature`'s fail-*open* posture on a missing tracker
issue (they warn and continue the underlying native GSD command regardless), this skill's very
first gate is fail-*closed* by design: `create-phase-tasks.sh detect` itself refuses to draft
anything without a linked epic, and there is no underlying native GSD command for this skill to
fall back to running anyway — creating phase-task issues with no epic to link them to would
produce orphaned Jira issues, not a graceful degradation. Once past that gate, every remaining
failure mode (a single row's `createJiraIssue`/link call failing) is handled per-row via
`mark-failed`, never as a whole-batch abort — one bad row never blocks the rest of the batch from
being created.
