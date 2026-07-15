# parse-state — `.planning/STATE.md` parser + validator (TASK-002)

**Picked first, deliberately, out of the remaining backlog.** With the FOTW
observer (TASK-013) and `recipe-prd-intake` (TASK-016) both built ahead of
schedule this session, the next candidates per `BACKLOG.md`'s own dependency
graph were TASK-002 (`parse-state`, size S, no dependencies) and TASK-010
(`install.sh`, size L). TASK-002 was chosen because it's the highest-leverage
single unlock left in Wave 1 — it feeds directly into TASK-003
(`sync-reconcile.sh`), TASK-007 (`create-phase-tasks.sh`), and TASK-008
(`state-tracker.sh` validator) — and because it's a small, spec-grounded,
test-verified increment matching the same formula that made TASK-013/016 go
smoothly, rather than a big-bang build like `install.sh`.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Library | `bench/lib/parse-state.sh` | Parses and validates `.planning/STATE.md` against the normative schema in [DATA-CONTRACTS.md#state-md](../../docs/netapp-recipe/contracts/DATA-CONTRACTS.md#state-md). Same "contract carried in-code, no separate spec doc" convention as `sync-ledger.sh` and `observer-lib.sh`. |
| Fixtures | `bench/tests/fixtures/state-tracker-*.md` | 8 fixtures — 1 valid, 1 valid-without-phase-table, 6 invalid variants, one per validation rule being tested. Named per `BACKLOG.md`'s own proposed fixture naming (`state-tracker-valid.md`). |
| Tests | `bench/tests/test-parse-state.sh` | 20 assertions (see below). |

### Subcommands

```text
parse-state.sh get-tracker [--state PATH]
parse-state.sh get-phase-issue <phase_id> [--state PATH]
parse-state.sh resolve-issue <event_id> [--phase N] [--state PATH]
parse-state.sh validate [--state PATH]
parse-state.sh dump [--state PATH]
```

- **`get-tracker`** — extracts the `## Tracker` key-value block as JSON. Pure parse, no field-level enforcement (that's `validate`'s job — kept separate on purpose, unix-philosophy style).
- **`get-phase-issue`** — looks up a single `phase_id` row in `## Phase tasks`, prints its `issue_key`.
- **`resolve-issue`** — the actual event-routing logic `TRACEABILITY-LLD.md`'s "STATE.md routing" section points at: given an `event_id`, decides whether it's epic-routed (prints `tracker.epic`) or phase-routed (requires `--phase N`, prints that phase's `issue_key`), per `DATA-CONTRACTS.md` rule 7's fixed vocabulary. Fails non-zero with an actionable stderr message on an unresolved phase, a missing `--phase`, or an unrecognized `event_id` — this is rule 8, implemented literally, not approximated.
- **`validate`** — runs the full structural rule set (rules 1, 2, 3, 5, 6) and prints every violation found (not just the first), `OK` on stdout and exit 0 when clean. This is the logic `TASK-008`'s `state-tracker.sh` validator is meant to wrap — `DATA-CONTRACTS.md` line 88 names TASK-008 as the "validation implementation target," so this subcommand is the reusable core that task will call rather than reimplement.
- **`dump`** — full structured JSON (`tracker` + `phase_tasks`) for debugging/downstream scripting.

### A design decision worth flagging

`DATA-CONTRACTS.md` rule 7's epic-routed / phase-routed event lists are
**hardcoded directly in `parse-state.sh`** (with a comment citing the rule),
rather than read from `jira-events.json`. Checked first: the canonical event
vocabulary file (`docs/netapp-recipe/reference/harness/recipe/trackers/jira-events.json`)
does **not** carry a routing field per event — only `DATA-CONTRACTS.md`'s prose
does. Hardcoding matches the existing in-code-contract convention (same as
`sync-ledger.sh`'s key-format comment) and keeps this task self-contained
without editing a shared vocabulary file other components also depend on. If
`jira-events.json` ever gains a `routes_to` field, `parse-state.sh` should be
updated to read it dynamically instead — flagged here so it isn't mistaken for
an oversight later.

## Validation performed

Same "test before moving on" discipline used for TASK-013/016:

| # | Check | Result |
|---|---|---|
| 1 | `get-tracker` returns all present fields as JSON | PASS |
| 2 | `get-tracker` fails on a missing STATE.md | PASS |
| 3 | `get-phase-issue` resolves a known `phase_id` | PASS |
| 4 | `get-phase-issue` fails on an unknown `phase_id` | PASS |
| 5 | `resolve-issue` routes an epic-routed event to `tracker.epic` | PASS |
| 6 | `resolve-issue` routes a phase-routed event to its matching row | PASS |
| 7 | `resolve-issue` fails non-zero, actionably, on an unresolved phase (rule 8) | PASS |
| 8 | `resolve-issue` fails when a phase-routed event is missing `--phase` | PASS |
| 9 | `resolve-issue` fails on an `event_id` outside the known vocabulary | PASS |
| 10 | `validate` passes on a well-formed STATE.md | PASS |
| 11 | `validate` passes with no `## Phase tasks` table at all (optional section, rule 4 is contextual not universal) | PASS |
| 12 | `validate` fails with an actionable message on a missing required Tracker field | PASS |
| 13 | `validate` fails on duplicate `phase_id` rows | PASS |
| 14 | `validate` fails on an empty `issue_key` | PASS |
| 15 | `validate` fails when `## Tracker` is missing entirely | PASS (bug found and fixed — see below) |
| 16 | `validate` fails when `## Tracker` appears more than once | PASS |
| 17 | `validate` fails on an unsupported tracker `system` | PASS |
| 18 | `dump` emits structured `tracker` + `phase_tasks` JSON | PASS |
| 19 | Defaults to the fixed path `.planning/STATE.md` under `REPO_ROOT` when `--state` is omitted | PASS |

**Bug found during step-by-step testing:** the first draft's `validate`
reported 6 errors for a STATE.md with no `## Tracker` section at all — the
"section missing" error, plus one "missing required field" error per field,
since an absent section parses to an empty tracker dict. Technically all true,
but noisy and redundant (the 5 field errors add no new information once the
section-missing error is already reported). Fixed by only running the
per-field / per-system checks when the Tracker section was actually found at
least once, so a missing section now reports exactly one, clear error. Caught
by asserting on line-count of the error output in the test, not just "did it
fail" — the same "test before moving on" habit that caught bugs in TASK-013/016.

Full `bench/tests/` suite after this addition: 10 (nudge) + 17
(install-observer) + 17 (install-recipe-prd-intake) + 12 (observer-lib) + 6
(observer-tick-loop) + 20 (parse-state, this task) + 9 (sync-ledger) = **91
assertions total, all passing, zero regressions.**

## Explicitly deferred (do not mistake for oversights)

| Deferred | Why | Real owner |
|---|---|---|
| CLI-facing validator with its own pass/fail report format | `validate`'s output (line-per-error to stderr, `OK`/exit-0 on success) is the reusable core; a friendlier operator-facing wrapper is TASK-008's job, not this task's. | TASK-008 |
| `create-phase-tasks.sh` writing `## Phase tasks` rows back into STATE.md | This task only *reads* STATE.md; writing rows back after tracker-issue creation is TASK-007's job. | TASK-007 |
| `sync-reconcile.sh` calling `resolve-issue` against real `.planning/` mtimes + `git log` inference | This task provides the primitive; wiring it into a watch loop is TASK-003. | TASK-003 |
| Reading routing from `jira-events.json` instead of a hardcoded list | See "A design decision worth flagging" above — revisit if the vocabulary file ever adds a `routes_to` field. | Future `parse-state.sh` revision |

## Files

- `bench/lib/parse-state.sh`
- `bench/tests/test-parse-state.sh`
- `bench/tests/fixtures/state-tracker-valid.md`
- `bench/tests/fixtures/state-tracker-no-phase-table.md`
- `bench/tests/fixtures/state-tracker-missing-field.md`
- `bench/tests/fixtures/state-tracker-duplicate-phase.md`
- `bench/tests/fixtures/state-tracker-empty-issue-key.md`
- `bench/tests/fixtures/state-tracker-no-tracker-section.md`
- `bench/tests/fixtures/state-tracker-duplicate-tracker-section.md`
- `bench/tests/fixtures/state-tracker-unsupported-system.md`
