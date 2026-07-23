---
name: gsd-jira-sync
description: "Recipe: post GSD lifecycle updates as Jira comments (and optional transitions) via Atlassian MCP; emit matching stamps."
---

<cursor_skill_adapter>
## A. Skill Invocation
Invoke when the user says `gsd-jira-sync` or after a GSD milestone should be mirrored to Jira.

**Single-event mode** (manual, one milestone at a time):

Arguments: `{{GSD_ARGS}}` = `<event_id> <issue_key> [--phase N] [--arm recipe] [--run run-01] [--transition "Name"]`

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
2. `Shell`: draft comment — **bundled path** (recipe folder as-is):
   `docs/netapp-recipe/reference/harness/runners/draft-jira-comment.sh <event> <issue> [--phase N] ...`
   **After copy** to target repo: `./bench/runners/draft-jira-comment.sh` (see [README.md](../../../README.md))
3. `CallMcpTool` server `plugin-atlassian-atlassian` to post comment (and transition if requested)
4. `Shell`: emit stamp — bundled `reference/harness/runners/emit-stamp.sh` or `./bench/runners/emit-stamp.sh` after copy

## D. Do NOT
- Skip Jira comment when recipe arm is active and issue key is known
- Post empty comments — enrich draft with paths/summaries from `.planning/` artifacts
- Transition without confirming transition name via `getTransitionsForJiraIssue` when unsure
- **Drain mode:** call `mark-done` before the `addCommentToJiraIssue` call actually succeeds
- **Drain mode:** skip `mark-failed` on error — an un-marked failure stays stuck as `queued` forever instead of being retried on the next drain
</cursor_skill_adapter>

# gsd-jira-sync — GSD recipe: Jira comment mirror

Post **every GSD lifecycle milestone** to the linked Jira issue. This is the **recipe arm** tracker bridge on top of vanilla GSD — GSD still owns `.planning/`; this skill owns **Jira audit trail + stamps**.

**Spec:** [TRACEABILITY-LLD.md](../../../lld/TRACEABILITY-LLD.md) · **Run:** [README.md](../../../README.md)  
**Events:** [jira-events.json](../../../reference/harness/recipe/trackers/jira-events.json)

## Workflow

1. **Resolve issue key** — from args or grep `.planning/STATE.md` / `CONTEXT.md` for `INS-` / `PROJ-` pattern.
2. **Validate event** — `event_id` must exist in `jira-events.json`.
3. **Draft comment** — run [draft-jira-comment.sh](../../../reference/harness/runners/draft-jira-comment.sh) (bundled) or `./bench/runners/draft-jira-comment.sh` after harness copy; enrich placeholders from `.planning/` artifacts.
4. **Post to Jira** — Atlassian MCP `addCommentToJiraIssue` with `cloudId` + `issueKey` + comment body (markdown/wiki as supported).
5. **Optional transition** — if `--transition` or event config says so, call `getTransitionsForJiraIssue` then `transitionJiraIssue`.
6. **Emit stamp** — run `emit-stamp.sh` line printed by draft script (immutable KPI record).

<a id="drain-mode-task-005"></a>
## Drain mode (TASK-005)

`sync-reconcile.sh` (TASK-003) detects lifecycle events and queues them to
`.gsd-recipe/sync-queue.jsonl` but never posts — it has no MCP tool-calling
access. Drain mode is the agent-mediated step that closes that loop, using
`bench/runners/sync-drain-queue.sh` (same `bench/` location as
`sync-reconcile.sh`/`sync-ledger.sh` — no `reference/harness/` bundling for
this script, matching TASK-001–003's precedent) for everything around the
actual post:

1. **List pending work** — `sync-drain-queue.sh list`. This re-verifies every
   `queued`/`failed` row against the ledger first (self-healing anything
   already posted out-of-band, e.g. a manual single-event `gsd-jira-sync` call
   that happened in between — those rows are silently flipped to `done` and
   dropped from the list, no MCP call needed) and re-drafts the comment body
   for whatever's genuinely still pending. Returns a JSON `work` array of
   `{key, event_id, issue_key, phase_id, target, body}`.
2. **For each work item** — read MCP tool schemas (`addCommentToJiraIssue`,
   `transitionJiraIssue`) and call `addCommentToJiraIssue` with `issueKey` +
   `body` from the work item.
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

Add to `.planning/STATE.md` per [DATA-CONTRACTS § STATE](../../../contracts/DATA-CONTRACTS.md#state-md) (required fields — do not omit):

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
