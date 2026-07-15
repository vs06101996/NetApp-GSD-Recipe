# sync-reconcile — near-RT event reconciler (TASK-003)

**Picked next per `BACKLOG.md`'s own "Wave 1 — start here" order.** With TASK-001
(`sync-ledger`) and TASK-002 (`parse-state`) both built, TASK-003 was the
literal next line in the backlog table and the highest-leverage unlock left —
it feeds TASK-005 (`sync-drain-queue.sh`) and turns the fully-manual chaining
proven in the live `gsd-jira-sync` test (see
[gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md)) into
an automated detection step.

## Key design decision: reconcile ≠ post

`TRACEABILITY-LLD.md`'s one-line spec says `sync-reconcile.sh` "watches
`.planning/` mtimes + `git log`, infers `event_id`, runs draft + post +
stamp." Taken literally this is impossible: `sync-reconcile.sh` is a plain
bash/python process and has no way to call `CallMcpTool` — only an agent turn
can do that. `FAILURE-MATRIX.md` itself uses the phrase "**reconcile/drain**"
as two distinct recovery steps, and `DATA-CONTRACTS.md`'s `sync-queue.jsonl`
schema has a `status: queued|done|failed` lifecycle that only makes sense if
something separate drains it. `BACKLOG.md`'s own dependency graph agrees:
`TASK-003 → TASK-005`.

So this task's actual scope, confirmed with the user before building:

| Script | MCP access? | Job |
|---|---|---|
| `sync-reconcile.sh` (this task) | No | Detect new artifacts → infer `event_id` → resolve issue key → skip if already posted → draft comment body → **always** write a `queued` row to `sync-queue.jsonl` |
| drain (TASK-005, or manual today) | Yes | Read `queued` rows → post via `addCommentToJiraIssue` → append `posted` to ledger → `emit-stamp.sh` |

This exactly mirrors what was done by hand in the live `gsd-jira-sync` test,
just automating the detection half.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Bundle copy | `bench/runners/draft-jira-comment.sh`, `bench/recipe/trackers/jira-events.json`, `bench/recipe/templates/jira-comments/_comment.template.md` | Closed a gap `BACKLOG.md`'s own example command (`./bench/runners/draft-jira-comment.sh ...`) assumed but that hadn't actually been copied from `docs/netapp-recipe/reference/harness/` yet. `sync-reconcile.sh` needs these inside `bench/` — reaching into `docs/netapp-recipe/reference/` from a script meant to ship with a customer's copy of `bench/` would be a layering violation. |
| Reconciler | `bench/runners/sync-reconcile.sh` | Detects new lifecycle artifacts, infers `event_id`, resolves issue key (`parse-state.sh`), dedups (`sync-ledger.sh`), drafts (`draft-jira-comment.sh`), enqueues to `sync-queue.jsonl`. `--dry-run` for CI (no writes at all). |
| Tests | `bench/tests/test-sync-reconcile.sh` | 14 assertions against real scratch git repos (see below). |

### Signal → `event_id` inference table (this implementation's own design)

The LLD prose ("watches mtimes + git log, infers event_id") gives no concrete
rules. These were derived from `RUNTIME-LLD.md`'s documented per-phase
artifact paths and confirmed against the user before building:

| `event_id` | Routing | Signal |
|---|---|---|
| `intake_started` | epic | `.planning/STATE.md` newly exists |
| `discuss_complete` | epic | `.planning/phases/NN-*/*CONTEXT.md` new |
| `plan_complete` | phase N | `.planning/phases/NN-*/*PLAN.md` new |
| `plan_revised` | phase N (commit-keyed) | same `PLAN.md` modified again, *after* `plan_complete` is already ledgered |
| `execute_started` | phase N | new commit touching `PLAN.md`'s frontmatter `touches:` globs, after `plan_complete` is ledgered, before `SUMMARY.md` exists |
| `execute_complete` | phase N | `.planning/phases/NN-*/*SUMMARY.md` new |
| `review_complete` | phase N | `.planning/phases/NN-*/*REVIEW.md` new |
| `verify_complete` | phase N | `.planning/phases/NN-*/*VERIFICATION.md` or `*UAT.md` new |
| `execute_wave`, `settled`, `reopened`, `learning_stored` | — | **deferred** — see below |

`plan_revised`'s ledger key includes a `--commit <short_sha>` segment (the
optional segment `DATA-CONTRACTS.md`'s key format explicitly allows) so each
revision gets its own key instead of colliding with the first `plan_complete`
post or with each other.

### A real bug caught mid-build

First draft treated `learning_stored` as **epic-routed** and inferred it from
new files under `.sdlc/patterns/repo/`. `DATA-CONTRACTS.md` rule 7 and
`parse-state.sh`'s own routing table both actually list `learning_stored` as
**phase-routed** — caught immediately by `parse-state.sh resolve-issue`
correctly rejecting the call for missing `--phase` during manual testing.
Fixed by removing the auto-inference entirely rather than guessing a
phase_id: nothing in `.sdlc/patterns/repo/`'s file layout ties a pattern file
back to the phase that produced it, so guessing (e.g. "most recently active
phase") would be a fragile heuristic dressed up as a real signal. Deferred to
manual `gsd-jira-sync`, flagged explicitly so it isn't mistaken for an
oversight later.

### Explicitly deferred (do not mistake for oversights)

| Deferred | Why |
|---|---|
| `execute_wave` | No reliable filesystem signal — wave boundaries are internal to `gsd-execute-phase`'s own execution, not externally observable via mtimes. |
| `settled` | Requires human PO acceptance + CI green (`TRACEABILITY-LLD.md` principle 4) — not filesystem-inferable by design. |
| `reopened` | Human-initiated rework decision, not a filesystem state. |
| `learning_stored` | Phase-routed per spec, but no signal ties a `.sdlc/patterns/repo/` file to a specific `phase_id`. See bug note above. |
| Actual posting/draining | TASK-005's job per `BACKLOG.md`'s dependency graph; see "Key design decision" above. |

## Validation performed

Manual smoke test against real scratch git repos first (to shake out the
`learning_stored` bug above before writing formal fixtures), then a full
regression suite:

| # | Check | Result |
|---|---|---|
| 1 | `--dry-run` detects candidates but writes nothing to disk | PASS |
| 2 | First real run queues `intake_started` + `discuss_complete` + `plan_complete` | PASS |
| 3 | Queue rows match `DATA-CONTRACTS.md`'s `sync-queue.jsonl` schema exactly | PASS |
| 4 | Checkpoint file written after a real run | PASS |
| 5 | Re-run on an unchanged tree produces zero candidates (checkpoint short-circuit) | PASS |
| 6 | Checkpoint reset + already-ledgered events → `duplicate_skipped`, never re-queued (ledger is the real source of truth, checkpoint is just a perf/plan_revised aid) | PASS |
| 7 | Commit touching `PLAN.md`'s `touches:` glob fires `execute_started` | PASS |
| 8 | Modifying `PLAN.md` again fires commit-keyed `plan_revised` | PASS |
| 9 | `SUMMARY.md`/`VERIFICATION.md`/`REVIEW.md` fire `execute_complete`/`verify_complete`/`review_complete`, correctly phase-routed | PASS |
| 10 | New `.sdlc/patterns/repo/` file does not error or get mis-routed (deferred by design) | PASS |
| 11 | `execute_started` never fires while `plan_complete` is unposted, even with a touching commit present | PASS |
| 12 | `--state`/`--queue`/`--checkpoint`/`--ledger` overrides all honored | PASS |

Full `bench/tests/` suite after this addition: 10 (nudge) + 17
(install-observer) + 17 (install-recipe-prd-intake) + 12 (observer-lib) + 6
(observer-tick-loop) + 20 (parse-state) + 9 (sync-ledger) + 14
(sync-reconcile, this task) = **105 assertions total, all passing, zero
regressions.**

## Files

- `bench/runners/sync-reconcile.sh`
- `bench/runners/draft-jira-comment.sh` (bundle copy from `reference/harness/`)
- `bench/recipe/trackers/jira-events.json` (bundle copy)
- `bench/recipe/templates/jira-comments/_comment.template.md` (bundle copy)
- `bench/tests/test-sync-reconcile.sh`
