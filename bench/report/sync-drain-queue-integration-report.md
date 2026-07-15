# sync-drain-queue — Jira posting drain loop (TASK-005)

**Picked next per user direction**, following the `recipe/clubbing` design
discussion: `sync-drain-queue.sh` is the literal continuation of TASK-003
(`sync-reconcile.sh`) — it drains the queue reconcile deliberately left full,
closing the loop from "event detected" to "Jira comment actually posted."

## Design confirmed with the user before building

Same reconcile/drain split established for TASK-003: `sync-drain-queue.sh` is
a plain script with no MCP tool-calling access, so it does everything *around*
the post and leaves the actual `addCommentToJiraIssue` call to an agent turn
(`gsd-jira-sync` skill's new "Drain mode").

| Piece | MCP access? | Job |
|---|---|---|
| `sync-drain-queue.sh list` | No | Re-verify every `queued`/`failed` row against the ledger (self-heal anything posted out-of-band), re-draft comment bodies for what's genuinely pending, return a JSON work list |
| Agent (drain mode) | Yes | For each work item: read MCP tool schemas, call `addCommentToJiraIssue` |
| `sync-drain-queue.sh mark-done` / `mark-failed` | No | Record the outcome: ledger append + queue status flip + stamp emission, or failed + error for retry |

## Key design decisions

### 1. The queue row never stores comment body text — `list` always re-drafts

`DATA-CONTRACTS.md`'s `sync-queue.jsonl` schema has no `body` field, and
`sync-reconcile.sh` (TASK-003) only ever wrote a `body_preview` (first line)
to its console output, never to the queue file itself. Confirmed this is the
intended design, not a gap: `list` re-runs `draft-jira-comment.sh
<event_id> <issue_key> [--phase N]` at drain time, which means the comment
reflects the *current* state of `.planning/` rather than a possibly-stale
snapshot from whenever reconcile happened to run. This also means
`draft-jira-comment.sh` doesn't need to be touched, and the queue schema
`DATA-CONTRACTS.md` already defines didn't need to change.

### 2. `list` self-heals duplicates instead of handing them to the agent

If something else posts an event out-of-band between reconcile and drain
(e.g. a manual single-event `gsd-jira-sync <event> <issue>` call, or a second
drain run racing the first), `list` re-checks `sync-ledger.sh has <key>` for
every pending row *before* re-drafting or including it in the work list. If
the ledger already has it, the row is silently flipped to
`status: done, result: duplicate_skipped` and dropped from the output — no
MCP call, no duplicate comment, no agent decision needed. This mirrors
exactly what `sync-reconcile.sh` already does for its own candidates before
queuing them.

### 3. `mark-done` consolidates 3 manual steps from the live test into 1 call

The live `gsd-jira-sync` test
([gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md))
required 3 separate manual actions after a successful post: ledger append,
stamp emission, and (implicitly) remembering not to re-post. `mark-done
<key> --external-id ID` now does all of it atomically: appends `posted` to
`sync-ledger.jsonl`, flips the queue row to `done`, and emits the KPI stamp
configured for that `event_id` in `jira-events.json` — skipping silently for
events with `stamp: null` (`execute_wave`, `verify_complete`).

### 4. `arm`/`run_id` are CLI flags on drain, not queue row fields

Queue rows written by `sync-reconcile.sh` don't carry `arm`/`run_id` (only
`sync-reconcile.sh`'s own CLI flags know those; they were never persisted per
row). Rather than modify already-shipped, already-tested TASK-003 code,
`sync-drain-queue.sh mark-done` takes its own `--arm`/`--run`/`--actor` flags
at invocation time, same pattern as `sync-reconcile.sh` itself.

### 5. `target: github` rows surface as errors, not silent drops or mis-posts

`TASK-006` (GitHub draft script) doesn't exist yet, and `sync-reconcile.sh`
only ever writes `target: "jira"` today — but the schema allows `github`, so
`list` explicitly checks `target` and reports non-`jira` rows under `errors`
(with a clear "not supported yet (TASK-006)" message) rather than either
silently dropping them or trying to post them as if they were Jira comments.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Drain script | `bench/runners/sync-drain-queue.sh` | 3 subcommands: `list` (re-verify + re-draft + report), `mark-done` (ledger + queue + stamp), `mark-failed` (queue + error, for retry) |
| Skill wire-up | `docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md` | New "Drain mode" section + `--drain` invocation mode + 2 new "Do NOT" rules (don't `mark-done` before the MCP call succeeds; don't skip `mark-failed` on error) |
| Tests | `bench/tests/test-sync-drain-queue.sh` | 18 assertions |

## Validation performed

Manual smoke test against a real scratch repo first (seeded via
`sync-reconcile.sh`, exercising `list` → `mark-done` → `mark-failed` → retry
→ self-heal end to end), then a full regression suite:

| # | Check | Result |
|---|---|---|
| 1 | `list` on a missing queue file returns empty work/self_healed/errors, not an error | PASS |
| 2 | `list` re-drafts both pending rows seeded by a real `sync-reconcile.sh` run, non-empty bodies | PASS |
| 3 | `mark-done` without `--external-id` fails | PASS |
| 4 | `mark-done` on an unknown key fails | PASS |
| 5 | `mark-done` appends `posted` + `external_id` to the ledger | PASS |
| 6 | `mark-done` flips the queue row to `done` with `result`/`external_id`, no leftover `error` field | PASS |
| 7 | `mark-done` emits the KPI stamp configured for the event (`intake_started` → `intake`/`started`) | PASS |
| 8 | Stamp record matches `jira-events.json`'s config exactly (step, status, tracker, run_id, arm) | PASS |
| 9 | `mark-done` on an already-`done` row fails (no double-post) | PASS |
| 10 | `mark-failed` sets `status: failed` + `error` message | PASS |
| 11 | `list` retries a `failed` row on the next run (only the failed one, not the done one) | PASS |
| 12 | `mark-failed` without `--error` fails | PASS |
| 13 | `list` self-heals a row whose key is already ledgered out-of-band (no MCP call, no duplicate) | PASS |
| 14 | Self-healed row flips to `done`/`duplicate_skipped`, drops any error field | PASS |
| 15 | `target: github` row surfaces under `errors` (not silently dropped or posted) | PASS |
| 16 | `list` exits non-zero when any row errors | PASS |

Full `bench/tests/` suite after this addition: 10 (nudge) + 17
(install-observer) + 17 (install-recipe-prd-intake) + 12 (observer-lib) + 6
(observer-tick-loop) + 20 (parse-state) + 18 (sync-drain-queue, this task) + 9
(sync-ledger) + 14 (sync-reconcile) = **123 assertions total, all passing,
zero regressions.**

## Files

- `bench/runners/sync-drain-queue.sh`
- `bench/tests/test-sync-drain-queue.sh`
- `docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md` (Drain mode section added)
- `docs/netapp-recipe/README.md` (Built vs spec table updated)
