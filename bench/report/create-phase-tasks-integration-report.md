# `create-phase-tasks.sh` — tracker epic + phase tasks (TASK-007)

**Picked up per `BACKLOG.md`'s Wave 2 listing** (`TASK-007`, Depends: `002`, parallel-eligible
alongside TASK-006/TASK-008 per the "Parallel after TASK-002" note). Implements
`RUNTIME-LLD.md` § "1.d Tracker epic + tasks [C]" — turning `ROADMAP.md`'s declared phases into
Jira sub-tasks under the epic, using the `create_subissue` + `link` adapter ops named in
`TRACEABILITY-LLD.md` § Tracker adapter.

## Key design decision: detect+draft+queue ≠ post (same split as `sync-reconcile.sh`)

Identical reasoning to `sync-reconcile.sh`'s own report: this is a plain bash/python process
with no `CallMcpTool` access — only an agent turn can call `createJiraIssue` or
`createIssueLink`. So the scope split is:

| Piece | MCP access? | Job |
|---|---|---|
| `create-phase-tasks.sh detect` (this task) | No | Read `ROADMAP.md` phases, read `STATE.md` via `parse-state.sh`, skip phases that already have an `issue_key`, draft a sub-task summary/description per phase, queue the rest |
| (agent turn) | Yes | For each queued phase: `createJiraIssue` (create_subissue) + `createIssueLink`/parent field (link) — same MCP call shape proven live in [gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md) |
| `create-phase-tasks.sh mark-done` / `mark-failed` (this task) | No | Bookkeeping after the agent turn: write the new `issue_key` into `STATE.md` (`parse-state.sh add-phase-task`) and flip the queue row, or record a retryable failure |

## Key design decision: a separate queue file, not `sync-queue.jsonl`

`DATA-CONTRACTS.md`'s `sync-queue.jsonl` schema requires a non-empty `issue_key` (the *target*
to comment on) and an `event_id` that exists in `jira-events.json`'s comment-event vocabulary.
A `create_subissue` work item is structurally the opposite: there is no `issue_key` yet — that's
what's being created — and "create a phase task" is a `TRACEABILITY-LLD.md` adapter op, not a
`jira-events.json` lifecycle comment event. Reusing `sync-queue.jsonl` would require either
making `issue_key` optional (weakening a field every existing consumer, including
`sync-drain-queue.sh`, currently treats as required) or inventing a fake `event_id` not in
`jira-events.json` (breaking `sync-drain-queue.sh list`'s draft path, which resolves templates by
`event_id`). Both mean touching `sync-drain-queue.sh`'s established schema/behavior — explicitly
flagged as risky by the task brief (a file this task should not need to touch, and doesn't).

So this task introduces its own queue file, `.gsd-recipe/phase-tasks-queue.jsonl`, with its own
row schema (`queued_at`, `phase_id`, `phase_title`, `phase_goal`, `epic_key`, `key`, `status`,
`target`, `drafted_summary`, `drafted_description`, plus `issue_key`/`error` once resolved).
Idempotency keys still **reuse** `sync-ledger.sh`'s `key` subcommand for format consistency
(event_id slot = `create_subissue`, issue_key slot = the **epic** key, since no phase issue
exists yet): `gsd-recipe:create_subissue:phase={N}:issue={EPIC_KEY}`. This keeps the canonical
key shape (`TRACEABILITY-LLD.md` § Idempotency) intact without needing a phase issue key that
doesn't exist yet, and without adding a new "kind" field to a schema this task was told to
avoid destabilizing.

**`sync-drain-queue.sh` was not touched.** Confirmed unnecessary per the above — this task's
detect/mark-done/mark-failed loop is fully self-contained inside `create-phase-tasks.sh` itself
(three subcommands in one file, mirroring `sync-drain-queue.sh`'s `list`/`mark-done`/`mark-failed`
shape without needing a second drain script or touching the existing one).

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Main script | `bench/runners/create-phase-tasks.sh` | `detect [--dry-run]` (enumerate `ROADMAP.md` phases, resolve epic + already-linked phases via `parse-state.sh`, draft + queue the rest, with in-place retry of `failed` rows); `mark-done <phase_id> <issue_key>` (writes `STATE.md` via `parse-state.sh add-phase-task`, flips queue row to `done`); `mark-failed <phase_id> --error MSG` (flips queue row to `failed`, retryable on next `detect`) |
| `parse-state.sh` extension | `bench/lib/parse-state.sh` | New `add-phase-task <phase_id> <issue_key> [--state PATH]` subcommand — the "narrow write subcommand" the task brief suggested in lieu of hand-rolled markdown-table editing elsewhere. Refuses to overwrite an existing phase_id row (fail-fast, actionable error); creates the `## Phase tasks` section (right after `## Tracker`, per `DATA-CONTRACTS.md`'s required section order) when it doesn't exist yet; inserts into an existing table after its last table-shaped line (correctly handles a header-only table with zero data rows). |
| Draft template | `bench/recipe/templates/jira-phase-tasks/_phase_task.template.md` | New template family (sibling to `jira-comments/`), matching `_comment.template.md`'s house style (bold header line, `·`-separated metadata line, `###` sections) but for a sub-task *description* rather than a milestone *comment* — a genuinely different Jira write (new issue vs. comment on an existing one). |
| Fixtures | `bench/tests/fixtures/roadmap-sample.md`, `bench/tests/fixtures/state-partial-phase-tasks.md` | 3-phase `ROADMAP.md` fixture (matching this repo's own `## Phase N — Title` + `**Goal:**` convention) and a `STATE.md` fixture with phase 1 linked, phases 2/3 not — the "partial `## Phase tasks` table" fixture the task brief asked for. |
| Tests | `bench/tests/test-create-phase-tasks.sh` (29 assertions), `bench/tests/test-parse-state.sh` (+7 assertions, 20 → 27) | See Validation below. |
| This report | `bench/report/create-phase-tasks-integration-report.md` | — |

## ROADMAP.md phase grammar (this implementation's own design)

`RUNTIME-LLD.md` names `ROADMAP.md` phases as an input but gives no fixed grammar beyond
prose. This repo's own `.planning/ROADMAP.md` (confirmed by reading it directly) — and every
`ROADMAP.md` `gsd-new-project`/`gsd-plan-phase` produce — uses:

```markdown
## Phase N — Title

**Goal:** one-line goal statement.

| Task | ... |
```

`create-phase-tasks.sh` parses `^##\s+Phase\s+(\d+)\b\s*[—\-]?\s*(.*)$` for the heading (phase
number + title) and an optional `**Goal:** ...` line before the next `##` heading. Phase 0 is
deliberately **included** — `RUNTIME-LLD.md`'s "one task per phase" doesn't carve out phase 0,
and a repo that wants a Jira task for its "Done (v0 harness)" phase should get one. A phase with
no `**Goal:**` line still drafts cleanly with fallback text (`"(no goal declared in
ROADMAP.md)"`) rather than erroring — confirmed by test #18, and exercised for real against this
repo's own `.planning/ROADMAP.md` (phase 0, "Done (v0 harness)", has no `**Goal:**` line at all;
see the manual verification section below).

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| The actual `createJiraIssue` (`create_subissue`) / `createIssueLink` (`link`) MCP calls | Bash has no MCP tool-calling access — same constraint as `sync-reconcile.sh`. Agent-mediated, traced not executed (see Validation below). |
| `transition` / `comment` adapter ops | Named in `TRACEABILITY-LLD.md` § Tracker adapter but out of this task's scope per the brief — `transition` is `gsd-jira-sync`'s job on `plan_complete`/etc., `comment` is what `draft-jira-comment.sh`/`sync-reconcile.sh` already do. |
| Modifying `sync-drain-queue.sh` | Considered and rejected — see "a separate queue file" decision above. Not touched. |
| `install.sh` / `.cursor/skills/` installer | This is a `bench/runners/` script like `sync-reconcile.sh`/`draft-jira-comment.sh`, not an invoke-by-name Cursor skill — no installer needed. Confirmed explicitly, not silently omitted. |
| `dag-build.sh` DAG ordering input | `RUNTIME-LLD.md`'s input list includes "DAG order" but Tier-1 DAG (TASK-009) is parked per `DECISIONS.md`, same narrowing precedent as TASK-017/TASK-024. Phases are ordered numerically from `ROADMAP.md` instead — sufficient for "one task per phase" without a dependency graph. |
| Per-story granularity ("or per story — team config") | `RUNTIME-LLD.md` names this as a team-config alternative to per-phase; not implemented — per-phase only, matching the more common default and this repo's own `ROADMAP.md` structure. |

## Validation performed

### Automated

`bench/tests/test-create-phase-tasks.sh` — **29 assertions, 0 failed**, run standalone:

| # | Check | Result |
|---|---|---|
| 1-3 | `--dry-run` enumerates phases correctly, skips the already-linked phase, drafts correct content (title/goal/epic), writes nothing to disk | PASS |
| 4-6 | Real run writes exactly the expected queue rows, matching dry-run's phase set | PASS |
| 7 | Queue rows match the documented `phase-tasks-queue.jsonl` schema | PASS |
| 8 | Idempotency key format is `gsd-recipe:create_subissue:phase={N}:issue={EPIC_KEY}` | PASS |
| 9-10 | Re-running `detect` reports `already_queued`, never duplicates rows | PASS |
| 11-13 | `mark-done` writes `STATE.md`, flips the queue row, and correctly refuses when no queued/failed row exists | PASS |
| 14 | `detect` after `mark-done` treats the phase as `already_linked` via `STATE.md`, not just the queue | PASS |
| 15-16 | `mark-failed` records status+error; fails on an unknown phase_id | PASS |
| 17-19 | `detect` retries (requeues) a previously-failed row in place — no duplicate line, error cleared, status back to `queued` | PASS |
| 20 | Dry-run and real-run `to_create` entries carry the same fields (schema parity) | PASS |
| 21 | Missing `## Tracker` epic fails fast with an actionable error | PASS |
| 22 | `ROADMAP.md` with no phase headings fails fast with an actionable error | PASS |
| 23 | A phase with no `**Goal:**` line drafts with fallback text, no crash | PASS |
| 24 | `--roadmap`/`--state`/`--queue` overrides honored; nothing written to default `.gsd-recipe/` paths | PASS |
| 25 | Phases enumerated in numeric order (2 before 10, not lexicographic) | PASS |
| 26 | Parses this repo's own real `.planning/ROADMAP.md` phase headings without error | PASS |
| 27 | `errors` array empty on a clean, valid run | PASS |
| 28 | Unknown subcommand exits 2 with usage | PASS |
| 29 | `detect` never modifies `STATE.md` (mtime check) — only `mark-done` does | PASS |

`bench/tests/test-parse-state.sh` — extended with **7 new assertions** for `add-phase-task`
(20 → 27 total), **0 failed**: appends to an existing table, preserves pre-existing rows,
refuses to overwrite a duplicate `phase_id`, creates a well-formed section when absent entirely,
the newly-created section resolves correctly via `get-phase-issue`, fails when `## Tracker` is
missing, rejects an empty `issue_key`.

`bench/tests/test-sync-ledger.sh` — run standalone to confirm zero regression (this file was not
modified): **10 assertions, 0 failed**, unchanged from before this task.

Full `bench/tests/` suite was **not** run, per the task's explicit instruction (sibling agents
editing files concurrently) — only this task's new test file plus the two "no regression" checks
named in the brief were run.

### Manual (real-environment)

Ran against a fresh scratch git repo at `/tmp/task-007-manual-01` (deleted afterward) — every
command used absolute `--roadmap`/`--state`/`--queue`/`REPO_ROOT` paths, no `cd` relied upon to
persist across separate tool calls, per the task's explicit safety constraint.

Seeded a real `ROADMAP.md` (4 phases: 0, 1, 2, 3 — mirroring this repo's own real
`.planning/ROADMAP.md` phase-heading style) and a real `STATE.md` (epic `MAN-500`, phase 1
already linked to `MAN-501`, phases 0/2/3 unlinked), committed to a real scratch git repo.

| Step | What happened | Real or traced? |
|---|---|---|
| `detect --dry-run` | Genuinely resolved epic `MAN-500` via a real `parse-state.sh get-tracker` call, genuinely parsed the real `ROADMAP.md`'s 4 phase headings + goals, genuinely skipped phase 1 (already linked), genuinely drafted phase 0/2/3's summaries+descriptions from the real template, genuinely wrote nothing to disk (confirmed: `.gsd-recipe/` didn't exist afterward) | **Real** |
| `detect` (real, no `--dry-run`) | Genuinely wrote 3 real queue rows to a real `.gsd-recipe/phase-tasks-queue.jsonl` | **Real** |
| `createJiraIssue` ×3 (one per phase) + `createIssueLink`/parent-field | Would create phase 0/2/3's sub-tasks under `MAN-500` and link them, mirroring the exact `createJiraIssue` call shape proven live in [gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md)'s step 2 | **Traced, not executed** — no live Jira call was made this pass, per the task's explicit "optional" framing for the live-MCP leg |
| `mark-done 0 MAN-510` (simulating "as if `createJiraIssue` had just returned `MAN-510`") | Genuinely called `parse-state.sh add-phase-task 0 MAN-510` against the real scratch `STATE.md`, genuinely wrote the new row, genuinely flipped the real queue row to `done` | **Real** (the MCP call it stands in for is the traced part; the bookkeeping it performs is fully real) |
| `parse-state.sh resolve-issue plan_complete --phase 0` | Genuinely resolved to `MAN-510` — proving the write-back is immediately usable by the rest of the traceability chain (`gsd-jira-sync`, `sync-reconcile.sh`) with no further glue needed | **Real** |
| Cleanup | `/tmp/task-007-manual-01` deleted; `git -C /Users/vs72964/Projects/gsd-benchmark status --porcelain` re-checked afterward — no stray files from the scratch run leaked into the real repo | **Real** |

**What was truly exercised vs. traced:** every step with no MCP dependency was genuinely
executed against real on-disk files in a real (disposable) git repo — `ROADMAP.md` parsing,
epic/tracker resolution, drafting, queuing, idempotency (`already_queued`/requeue), and the full
`mark-done` write-back loop closing STATE.md's `## Phase tasks` table. Only the `createJiraIssue`
+ `createIssueLink` MCP calls themselves were traced/reasoned about rather than executed — this
task deliberately did not run a live Jira test, unlike the optional live-MCP leg the brief
allowed; if a live test is wanted later, [gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md)'s
pattern (disposable `[TEST - safe to ignore/delete]` issues, never production issues) is the
template to follow, and `create-phase-tasks.sh detect`'s drafted `drafted_summary`/
`drafted_description` fields are already shaped to be passed directly as `createJiraIssue`'s
`summary`/`description` fields.

## Files

- `bench/runners/create-phase-tasks.sh` (new)
- `bench/lib/parse-state.sh` (edited — new `add-phase-task` subcommand)
- `bench/recipe/templates/jira-phase-tasks/_phase_task.template.md` (new)
- `bench/tests/test-create-phase-tasks.sh` (new, 29 assertions)
- `bench/tests/test-parse-state.sh` (edited — 7 new assertions, 20 → 27)
- `bench/tests/fixtures/roadmap-sample.md` (new)
- `bench/tests/fixtures/state-partial-phase-tasks.md` (new)
- `bench/report/create-phase-tasks-integration-report.md` (new, this file)

`docs/netapp-recipe/BACKLOG.md` and `docs/netapp-recipe/README.md` need updates (TASK-007 row +
"Built vs spec" row) but were **not edited directly** — both are on this task's shared-file
avoidance list (4 sibling tasks editing them concurrently). Copy-paste-ready snippets are
provided in the final response instead.

## Deviations from the task brief

None in substance. Two judgment calls, both flagged inline above rather than silently made:

1. **Queue file is separate from `sync-queue.jsonl`**, per the brief's own fallback guidance
   ("if that requires meaningfully changing `sync-drain-queue.sh`'s existing schema/behavior...
   prefer a separate, simpler output file/format instead and document why") — documented above.
2. **`mark-done`/`mark-failed` are subcommands of `create-phase-tasks.sh` itself**, not a second
   dedicated drain script — the brief explicitly allowed this ("no need to build a full separate
   drain script unless you think it's warranted"); a third file felt unwarranted given the whole
   detect→draft→queue→mark-done loop fits cleanly in one script, mirroring how
   `sync-drain-queue.sh` itself bundles `list`/`mark-done`/`mark-failed` as subcommands of one file.
