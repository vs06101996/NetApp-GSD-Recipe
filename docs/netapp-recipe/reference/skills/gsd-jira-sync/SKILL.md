---
name: gsd-jira-sync
description: "Recipe: post GSD lifecycle updates as Jira comments AND required status transitions via Atlassian MCP; emit matching stamps. Do not comment-only when jira-events.json names a status."
---

<cursor_skill_adapter>
## A. Skill Invocation
Invoke when the user says `gsd-jira-sync` or after a GSD milestone should be mirrored to Jira.

**Single-event mode** (manual, one milestone at a time):

Arguments: `{{GSD_ARGS}}` = `<event_id> <issue_key> [--phase N] [--arm recipe] [--run run-01] [--transition "Name"]`

`--transition` overrides the **required** status in `jira-events.json` for that event. If omitted, use the catalog name (via `bench/lib/jira-transition-name.sh`). Do not skip the transition when the catalog names one — comments alone are not enough.

Examples:
- `gsd-jira-sync plan_complete INS-12345 --phase 1`
- `gsd-jira-sync execute_complete INS-12345 --phase 1 --transition "In Review"`

**Drain mode** (TASK-005, automated backlog): `gsd-jira-sync --drain [--queue PATH] [--ledger PATH]`

Invoke this when `sync-reconcile.sh` (TASK-003) has been run and left rows in
`.gsd-recipe/sync-queue.jsonl` — see [§ Drain mode](#drain-mode-task-005) below.

## B. Prerequisites
- Atlassian MCP enabled and authenticated (`netapp.atlassian.net` or project's cloudId)
- Jira issue exists and user can comment
- Issue key recorded in `.planning/STATE.md` or passed explicitly

## C. Tool Usage
1. Read MCP tool schemas: `addCommentToJiraIssue`, `transitionJiraIssue`, `getJiraIssue`, `getTransitionsForJiraIssue`
2. **Draft comment.** `bench/runners/draft-jira-comment.sh` is not duplicated into every target by
   design (only `gsd-benchmark`, the recipe's own source repo, keeps the full `bench/` tree) —
   resolve its real path via `.gsd-recipe/scripts/recipe-paths.sh` (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full; this is the current fix,
   replacing the older "bundled harness mirror under `docs/netapp-recipe/reference/harness/`"
   convention that file tree no longer exists). `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/draft-jira-comment.sh)"
   "$RESOLVED" <event> <issue> [--phase N] ...
   ```
3. `CallMcpTool` server `plugin-atlassian-atlassian` to post the comment, then to **transition**
   when the catalog or `--transition` names a status (see workflow step 5).
4. **Emit stamp.** Same resolution as step 2, for `bench/runners/emit-stamp.sh`. `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/emit-stamp.sh)"
   "$RESOLVED" ...
   ```

## D. Do NOT
- Skip Jira comment when recipe arm is active and issue key is known
- Post empty comments — enrich draft with paths/summaries from `.planning/` artifacts
- Skip the catalog transition (comment-only) when `jira-events.json` names a status
- Transition without matching a real transition id via `getTransitionsForJiraIssue`
- **Drain mode:** call `mark-done` before the `addCommentToJiraIssue` call actually succeeds
- **Drain mode:** skip `mark-failed` on error — an un-marked failure stays stuck as `queued` forever instead of being retried on the next drain
</cursor_skill_adapter>

# gsd-jira-sync — GSD recipe: Jira comment + status mirror

Post **every GSD lifecycle milestone** to the linked Jira issue as a **comment and a status change** when the event catalog names one. This is the **recipe arm** tracker bridge on top of vanilla GSD — GSD still owns `.planning/`; this skill owns **Jira audit trail + stamps + board status**.

**Spec:** `docs/netapp-recipe/lld/TRACEABILITY-LLD.md` · **Run:** `docs/netapp-recipe/README.md`  
**Events:** `bench/recipe/trackers/jira-events.json` (bundled mirror: `docs/netapp-recipe/reference/harness/recipe/trackers/jira-events.json`)

## Workflow

1. **Resolve issue key** — from args or grep `.planning/STATE.md` / `CONTEXT.md` for `INS-` / `PROJ-` pattern.
2. **Validate event** — `event_id` must exist in `jira-events.json`.
3. **Draft comment** — run `bench/runners/draft-jira-comment.sh`, resolved via
   `.gsd-recipe/scripts/recipe-paths.sh` per § C step 2 above (this repo's own canonical
   implementation of the script; not duplicated into every target by design); enrich placeholders
   from `.planning/` artifacts.
4. **Post to Jira** — Atlassian MCP `addCommentToJiraIssue` with `cloudId` + `issueKey` + comment body (markdown/wiki as supported).
5. **Required transition** — resolve the status name: `--transition` if passed, else
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/jira-transition-name.sh)"
   "$RESOLVED" <event_id>
   ```
   If the helper prints a name: `getJiraIssue` — if current status already matches (case-insensitive), skip. Else `getTransitionsForJiraIssue`, pick the transition whose **name or to-status** matches (aliases below), then `transitionJiraIssue` with that **id**. No matching transition → **warn and continue** (comment still posted; some boards use different names). Empty helper output → skip (event has `transition: null`).
   Aliases: `To Do` ≈ Backlog / Open / New; `In Progress` ≈ Doing / In-Progress; `In Review` ≈ Review / Code Review; `Done` ≈ Closed / Resolved / Complete.
6. **Emit stamp** — run `emit-stamp.sh` line printed by draft script (immutable KPI record).

<a id="drain-mode-task-005"></a>
## Drain mode (TASK-005)

`sync-reconcile.sh` (TASK-003) detects lifecycle events and queues them to
`.gsd-recipe/sync-queue.jsonl` but never posts — it has no MCP tool-calling
access. Drain mode is the agent-mediated step that closes that loop, using
`bench/runners/sync-drain-queue.sh` (same `bench/` location as
`sync-reconcile.sh`/`sync-ledger.sh`, resolved the same
`.gsd-recipe/scripts/recipe-paths.sh` way as step 2 above — not duplicated into
every target by design) for everything around the actual post:

1. **List pending work** — `sync-drain-queue.sh list`. This re-verifies every
   `queued`/`failed` row against the ledger first (self-healing anything
   already posted out-of-band, e.g. a manual single-event `gsd-jira-sync` call
   that happened in between — those rows are silently flipped to `done` and
   dropped from the list, no MCP call needed) and re-drafts the comment body
   for whatever's genuinely still pending. Returns a JSON `work` array of
   `{key, event_id, issue_key, phase_id, target, body}`.
2. **For each work item** — read MCP tool schemas (`addCommentToJiraIssue`,
   `transitionJiraIssue`, `getTransitionsForJiraIssue`, `getJiraIssue`) and call
   `addCommentToJiraIssue` with `issueKey` + `body` from the work item. Then apply the
   **required** catalog transition for that row's `event_id` (same rules as single-event
   step 5 — `jira-transition-name.sh`, match id, warn-and-continue if the board has no match).
   Do not mark the row done after a comment if you skipped a named transition without trying
   `getTransitionsForJiraIssue`.
3. **On success** — `sync-drain-queue.sh mark-done <key> --external-id <comment_id> --run <run_id>`.
   This appends `posted` to `sync-ledger.jsonl`, flips the queue row to `done`,
   and emits the KPI stamp configured for that `event_id` in `jira-events.json`
   automatically (skip silently if the event has no stamp configured, e.g.
   `execute_wave`/`verify_complete`).
4. **On failure** — `sync-drain-queue.sh mark-failed <key> --error "<reason>"`.
   The row stays `failed` and is retried on the next `list` call — do not drop
   it silently.
5. **Report a summary** — `N posted, M failed, K skipped-duplicate` from the
   `list` output's `self_healed`/`errors` plus this run's post outcomes.

`target: github` rows are not yet supported (`TASK-006` — GitHub draft script
doesn't exist yet); `list` surfaces them under `errors` rather than silently
dropping or mis-posting them.

## When to invoke (operator checklist)

| After GSD command | event_id |
|-------------------|----------|
| `gsd-new-project` / link ticket | `intake_started` |
| `gsd-discuss-phase N` | `discuss_complete` |
| `gsd-plan-phase N` (plan-check pass) | `plan_complete` |
| Plan revision | `plan_revised` |
| `gsd-execute-phase N` start | `execute_started` |
| Each execute wave (optional) | `execute_wave` |
| `gsd-execute-phase N` end | `execute_complete` |
| `gsd-verify-work N` | `verify_complete` |
| `gsd-code-review N` | `review_complete` |
| `gsd-extract-learnings N` | `learning_stored` |
| PO accept / grader pass | `settled` |
| Rework | `reopened` |

## Linking Jira to the project

Add to `.planning/STATE.md` per `docs/netapp-recipe/contracts/DATA-CONTRACTS.md#state-md` (required fields — do not omit):

```markdown
## Tracker
- epic: PROJ-100
- issue: PROJ-100
- system: jira
- url: https://your-org.atlassian.net/browse/PROJ-100
- run_id: pilot-01
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-101 |
```

**Routing:** epic-routed events (`discuss_complete`, `settled`, …) → `epic`; phase events (`plan_complete`, `execute_complete`, …) → matching `issue_key` from the phase table.

## MCP posting (reference)

Read tool descriptor before call. Typical shape:

- `addCommentToJiraIssue`: `cloudId`, `issueKey`, `commentBody`
- `transitionJiraIssue`: `cloudId`, `issueKey`, `transition` (id or name per tool schema)

## Relationship to ic-* (Instaclustr)

On Instaclustr `app` repo, **ic-*** skills may already write Jira fields. Use **either** ic-* **or** this GSD recipe on a repo — do not double-post. This skill targets **GSD + Jira** benchmark/recipe runs.
