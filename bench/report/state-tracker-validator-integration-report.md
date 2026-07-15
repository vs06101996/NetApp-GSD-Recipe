# STATE.md validator (TASK-008)

**Picked next per the user's explicit ordering** (TASK-015 → TASK-008 →
TASK-006), immediately after TASK-015 was fully closed out. `BACKLOG.md` lists
TASK-008 (`state-tracker.sh` validator, size `S`, depends on TASK-002) in
Wave 2, and its own spec pointer — `DATA-CONTRACTS.md`'s `## .planning/STATE.md`
§ "Validation rules" — says outright: **"Validation implementation target:
TASK-008."**

## Finding: the spec was absorbed into TASK-002's `parse-state.sh validate`, not a separate script

No `state-tracker.sh` file exists anywhere in this repo, and — per explicit
user direction — none was written for this task. Investigation confirms
TASK-008's entire functional deliverable already exists as the `validate`
subcommand of `bench/lib/parse-state.sh` (built under TASK-002), plus the
`resolve-issue` subcommand for rule 8's specific enforcement point. This is a
**formalize only** task: verify the absorption is real and complete, not
build a duplicate script under a different name.

`parse-state.sh`'s own header comment already documents this split
explicitly (`# Rule 8: resolving a phase-routed event with no matching
phase_id fails non-zero...`), and its normative-contract line points straight
back at `DATA-CONTRACTS.md#state-md`, so there is no ambiguity in the source
that `validate`/`resolve-issue` *is* the TASK-008 deliverable, just delivered
inside the TASK-002 lib rather than as its own file.

## Rule-by-rule verification (live commands against fixtures)

`DATA-CONTRACTS.md`'s `## .planning/STATE.md` § "Validation rules" lists 8
rules. Each was independently re-verified with a live command run in this
session (not assumed from the existing test suite), against the fixture that
exercises it:

| Rule | Requirement | Mechanism | Fixture | Live result |
|---|---|---|---|---|
| 1 | `## Tracker` exists exactly once, all required fields present | `validate` | `state-tracker-valid.md` (pass), `state-tracker-no-tracker-section.md` (fail: `no '## Tracker' section found`), `state-tracker-duplicate-tracker-section.md` (fail: `appears 2 times`) | PASS |
| 2 | `system` must be a supported tracker string | `validate` | `state-tracker-unsupported-system.md` | fail: `system 'trello' is not supported in v1 (supported: jira)` — PASS |
| 3 | `arm` must be set and non-empty | `validate` (via the same required-field loop as rule 1) | `state-tracker-missing-field.md` (omits `arm`) | fail: `missing required field 'arm'` — PASS |
| 4 | `## Phase tasks` table must exist for p1/p3 phase-level events | `validate` — deliberately interpreted as *structurally optional*; only enforced at the point an event actually needs to resolve a `phase_id` (see rule 8) | `state-tracker-no-phase-table.md` | `validate` still returns `OK` (table entirely absent) — confirms the interpretation; see rule 8b below for why this isn't a gap |
| 5 | `phase_id` values unique | `validate` | `state-tracker-duplicate-phase.md` | fail: `duplicate phase_id '1' in '## Phase tasks' (rows 0 and 1)` — PASS |
| 6 | `issue_key` non-empty per phase row | `validate` | `state-tracker-empty-issue-key.md` | fail: `phase_id '1' has an empty issue_key in '## Phase tasks'` — PASS |
| 7 | Event routing: epic-routed vs phase-routed vocabulary | `resolve-issue` | `state-tracker-valid.md` | `resolve-issue settled` → `PROJ-100` (epic); `resolve-issue plan_complete --phase 1` → `PROJ-101` (phase) — PASS |
| 8 | Unresolved phase-routed event fails non-zero, actionable | `resolve-issue` (explicitly *not* `validate` — see `parse-state.sh` header comment) | `state-tracker-valid.md` with `--phase 99` (no such row) | fail: `unresolved phase-routed event: phase_id '99' for event_id 'plan_complete' has no matching row...` — PASS |

### Rule 4 / rule 8 interpretation — confirmed, not a gap

The one rule that reads ambiguously on paper is rule 4 ("`## Phase tasks`
table must exist for p1/p3 phase-level events") versus `test-parse-state.sh`'s
assertion that `validate` passes even when the table is **absent entirely**.
This session ran the missing check that would prove or disprove that this is
a real gap: does `resolve-issue` (rule 8's actual enforcement point) still
fail correctly for a phase-routed event when the table isn't just missing a
row, but missing *entirely*?

```
$ parse-state.sh resolve-issue plan_complete --phase 1 --state state-tracker-no-phase-table.md
ERROR: unresolved phase-routed event: phase_id '1' for event_id 'plan_complete' has no matching row in '## Phase tasks' in ...
rc=1
```

Confirmed: yes. An entirely-absent table degrades to "zero rows," and
`resolve-issue`'s row-scan loop finds no match regardless of whether the
table is missing 1 row or all of them — same actionable non-zero failure
either way. So rule 4's requirement ("table must exist for p1/p3 phase-level
events") is satisfied in effect: nothing ever silently succeeds or no-ops for
a phase-routed event on a table-less STATE.md. `validate` staying structurally
lenient here is a deliberate design choice (a STATE.md with no phase table
yet, e.g. before phase 1 has been planned, is a legitimate transient state
that shouldn't itself fail CI), not an unenforced rule.

**Conclusion: no genuine gap found.** All 8 rules are enforced by
`parse-state.sh`'s `validate`/`resolve-issue`, confirmed live against
fixtures, not just by reading code.

## Why no `state-tracker.sh` file was created

Per explicit user decision for this task: since the functionality already
exists and is already fully covered (`bench/tests/test-parse-state.sh`, 20
assertions, see TASK-015's report), writing a second script under the
`state-tracker.sh` name specified in `BACKLOG.md` would be pure duplication —
two entry points enforcing the same 8 rules, with no reason for one to ever
diverge from the other. `BACKLOG.md`'s literal filename is treated as the
Wave-2 planning-time guess at a deliverable shape; the actual shape that
shipped (validation folded into TASK-002's parser, since a validator and a
parser share every one of the same fixtures and the same rule logic) is
recorded here instead of forced to match the original guess.

## Validation performed

| # | Check | Result |
|---|---|---|
| 1–8 | Live rule-by-rule walk above (table) | All 8 rules confirmed enforced |
| 9 | `test-parse-state.sh` re-run | 20 passed, 0 failed |
| 10 | Full `bench/tests/` suite re-run | 150 assertions, all passing, zero regressions |

## Files

- `bench/lib/parse-state.sh` (unchanged — TASK-002; this task verifies, does not modify)
- `bench/tests/test-parse-state.sh` (unchanged — verified sufficient)
- `bench/tests/fixtures/state-tracker-*.md` (unchanged — all 8 fixtures already existed and were used above)
- No `state-tracker.sh` created (see "Why no `state-tracker.sh` file was created" above)
