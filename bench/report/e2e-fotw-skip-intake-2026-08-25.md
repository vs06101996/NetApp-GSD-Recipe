# E2E: FOTW bootstrap when onboard skips PRD intake (2026-08-25)

**Persona:** Unbiased new-hire ([FOTW skip-intake tester](0c4f40bc-9c20-4a36-961f-13a1c2913031))  
**Recipe source:** `/Users/vs72964/Projects/gsd-benchmark`  
**Target:** `/tmp/gsd-recipe-fotw-skip-intake-wTYuY3`

## AC

Onboard with an existing `docs/PRD.md` must still invoke `fotw-observer-bootstrap`. It must not skip bootstrap merely because intake was skipped.

## Setup

- Fresh git repo; install via `install-recipe-to-target.sh --yes --no-open-start`
- Canonical `docs/PRD.md` pre-written (intake must skip)
- Observer `enabled: true`
- `recipe-onboard --skip-tracker` (preview confirmed)

## Result

| Check | Outcome |
|-------|---------|
| Staged `recipe-onboard` requires FOTW after skipped intake | PASS — “still run the FOTW observer hook below, then continue to step 4.” |
| Invoked `fotw-observer-bootstrap` | yes |
| `can-spawn` | `allowed: enabled and no active marker for session test-session-fotw-skip-intake` |
| `.observer-target.json` / `.observer-active.json` | both present |
| `observer-lib.sh status` `active:` | `true` |
| Scripted `test-install-recipe-onboard.sh` | 36 passed, 0 failed |

**PASS**

## Friction

- Did not complete project bootstrap / knowledge (no fabricated ROADMAP).
- Nested agent did not spawn the long-running observer `Task`; marker writes still ran (same limitation as prior onboard E2E diaries).
