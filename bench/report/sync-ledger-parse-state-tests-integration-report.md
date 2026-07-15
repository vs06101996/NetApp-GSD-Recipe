# `bench/tests/` ledger + parser coverage (TASK-015)

**Picked next per the user's explicit ordering** (TASK-015 → TASK-008 →
TASK-006), and per `BACKLOG.md`'s own "Testing" table, which maps "Ledger /
idempotency" coverage to **TASK-001 + TASK-015 together** — i.e. TASK-015 was
never meant to be a new test *runner*, just the formal closing of the loop on
tests TASK-001/TASK-002 already wrote for their own libs.

## Finding: deliverable already satisfied by TASK-001/TASK-002's own suites

`bench/tests/test-sync-ledger.sh` (`bench/lib/sync-ledger.sh`, TASK-001) and
`bench/tests/test-parse-state.sh` (`bench/lib/parse-state.sh`, TASK-002)
already exist and already pass in full. No new library or runner code was
written for this task — per explicit user direction, this is a **formalize
only** pass: confirm current counts, spot-check real coverage against each
lib's documented contract, close any small gap found, and record the result.

## Current assertion counts (re-run, not assumed)

| File | Assertions before this task | Assertions after this task |
|---|---|---|
| `test-sync-ledger.sh` | 9 | **10** (added 1 — see gap below) |
| `test-parse-state.sh` | 20 | 20 (no gap found, no change) |

Both files pass in full: `10 passed, 0 failed` and `20 passed, 0 failed`
respectively.

## Spot-check against each lib's documented contract

### `sync-ledger.sh` (header comment contract: key format, `has`/`append`, record shape)

| Contract element | Covered by | Result |
|---|---|---|
| Key format: phase segment | assertion 1 (`phase-routed key format`) | covered |
| Key format: epic-routed omits phase | assertion 2 | covered |
| Key format: wave+commit ordering | assertion 3 | covered |
| `has()` on missing ledger → not-found | assertion 4 | covered |
| `has()` finds key after `append()` | assertion 5 | covered |
| `has()` does not false-positive on unrelated key | assertion 6 | covered |
| `duplicate_skipped` result recorded as its own line | assertion 7 | covered |
| `append()` rejects invalid `target` | assertion 8 | covered |
| `append()` rejects invalid `result` | assertion 9 | covered |
| **Record shape** — `{"key","ts","target","external_id"?,"result"?,"detail"?}` | *(gap — nothing parsed the raw JSONL line before this task)* | **gap found, closed** |

**Gap found:** every existing assertion drove `append()`/`has()` through their
CLI exit codes and line counts, but none of them actually parsed a resulting
ledger line's JSON and checked that `ts`, `target`, and `external_id` were
written correctly per the header comment's documented record shape. This is a
real (if minor) coverage gap — not a naming mismatch — so a small additive
assertion was written rather than silently left alone: assertion 10 now reads
back the exact line written by assertion 5's `append()` call and asserts
`ts` is non-empty, `target == "jira"`, and `external_id ==
"jira-comment-88421"`.

### `parse-state.sh` (header comment contract: get-tracker / get-phase-issue / resolve-issue / validate / dump)

| Contract element | Covered by | Result |
|---|---|---|
| `get-tracker` returns fields as JSON | assertion 1 | covered |
| `get-tracker` fails on missing file | assertion 2 | covered |
| `get-phase-issue` resolves known/unknown phase_id | assertions 3–4 | covered |
| `resolve-issue` epic-routed / phase-routed routing | assertions 5–6 | covered |
| `resolve-issue` rule 8 (unresolved phase-routed event fails non-zero) | assertion 7 | covered |
| `resolve-issue` phase-routed event without `--phase` fails | assertion 8 | covered |
| `resolve-issue` unknown `event_id` fails | assertion 9 | covered |
| `validate` — all 8 DATA-CONTRACTS.md rules | assertions 10–18 | covered (full rule-by-rule confirmation done under TASK-008 below) |
| `dump` emits structured tracker + phase_tasks JSON | assertion 19 | covered |
| Fixed-path default (`.planning/STATE.md` under `REPO_ROOT`) | assertion 20 | covered |

No gap found in `test-parse-state.sh` against `parse-state.sh`'s own header
contract — every documented subcommand and every one of `BACKLOG.md`/
`DATA-CONTRACTS.md`'s validation rules has at least one fixture-backed
assertion. One adjacent question — whether `resolve-issue` (not `validate`)
correctly enforces rule 8 even when the `## Phase tasks` table is **entirely
absent** (not just missing a row) — was verified live as part of TASK-008's
rule-by-rule walk (see `state-tracker-validator-integration-report.md`) rather
than added here, since it's a rule-8-enforcement question that belongs with
that task's systematic pass, not a gap in TASK-002's own test file.

## Validation performed

| # | Check | Result |
|---|---|---|
| 1 | `test-sync-ledger.sh` re-run before any change | 9 passed, 0 failed |
| 2 | `test-sync-ledger.sh` re-run after additive assertion | 10 passed, 0 failed |
| 3 | `test-parse-state.sh` re-run | 20 passed, 0 failed |
| 4 | Full `bench/tests/` suite re-run (all 11 files) after this task's change | 150 assertions, all passing, zero regressions |

## Files

- `bench/tests/test-sync-ledger.sh` (1 additive assertion — record-shape check)
- `bench/tests/test-parse-state.sh` (unchanged — reviewed, no gap found)
- `bench/lib/sync-ledger.sh` (unchanged — TASK-001)
- `bench/lib/parse-state.sh` (unchanged — TASK-002)
