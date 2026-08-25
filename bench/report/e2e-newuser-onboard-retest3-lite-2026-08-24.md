# E2E new-user onboard — retest3 lite (2026-08-24)

**Persona:** New hire, never worked on recipe.  
**Recipe source:** `/Users/vs72964/Projects/gsd-benchmark`  
**Dummy product:** `/Users/vs72964/Projects/recipe-sandbox-e2e-retest3` (branch `main`)  
**Feature:** Hello Widget CLI — small CLI printing `hello widget`, one phase, no production systems.

## Sources used

| Allowed | Used |
|---------|------|
| `README.md` (+ links it names) | Yes — install command, onboard `--skip-tracker` mention |
| Staged `recipe-*` skills + helpers | Yes — `recipe-start`, `recipe-onboard`, `recipe-prd-intake`, `recipe-new-project` |
| `docs/RECIPE-SEQUENCE.md` (after install) | Yes — opened after `recipe-start` / install staged it |
| BACKLOG, E2E diaries, implementer notes | No |

## Time-ordered actions

| Time (approx) | Action | Result |
|---------------|--------|--------|
| T0 | Read `README.md` | Found first-install runner: `./bench/runners/install-recipe-to-target.sh --target … --yes --no-open-start` |
| T1 | Verified product repo | Git repo on `main`, clean working tree |
| T2 | Ran install runner into product | Exit 0; recipe skills staged; `recipe-start` suggested as next step |
| T3 | Read `recipe-start` skill; ran `recipe-next.sh` | Recommended `recipe-onboard` (no PRD yet); printed No-Jira hint |
| T4 | Opened `docs/RECIPE-SEQUENCE.md` | Confirmed segment 1: `recipe-onboard --skip-tracker` for no-Jira path |
| T5 | Read `recipe-onboard` skill; chose `--skip-tracker` | Preview: PRD intake RUN, project bootstrap RUN, Epic SKIP (flag), phase tasks SKIP (flag) |
| T6 | Invoked `recipe-prd-intake` (Hello Widget CLI description) | Wrote `docs/PRD.md` |
| T7 | Invoked `recipe-new-project` → native `gsd-new-project --auto @docs/PRD.md` | GSD skill found at user-global `~/.cursor/skills/gsd-new-project`; agents missing → inline roadmap; wrote `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`; `commit_docs: false` |
| T8 | Set `onboard.skip_tracker: true` in `.gsd-recipe/config.json` | Per `recipe-onboard` step 7 |
| T9 | Ran `recipe-next.sh` and `recipe-status.sh` | Next: `recipe-bootstrap-knowledge`; status shows PRD yes, ROADMAP yes, Epic skipped, Knowledge no |

## RECIPE-SEQUENCE.md

- **Seen:** Yes — staged at `docs/RECIPE-SEQUENCE.md` during install; opened while following `recipe-start`.
- **Used:** Yes — confirmed no-Jira onboard command before running `recipe-onboard --skip-tracker`.

## Friction

1. **Install command not given in Slack** — discoverable from README first paragraph (OK).
2. **`gsd-new-project` not copied into product repo** — `recipe-new-project` correctly points to user-global GSD; new hire must have GSD installed separately (README soft prereq).
3. **GSD agents missing** — inline roadmap path worked; warning expected per skill.
4. **`.planning/` gitignored** — artifacts exist on disk but not in git status (by design).

No blockers. Did not type `recipe-install` before skills existed. Did not create Jira issues.

## Artifacts

| Artifact | Present | Notes |
|----------|---------|-------|
| `docs/PRD.md` | Yes | Hello Widget CLI PRD |
| `.planning/ROADMAP.md` | Yes | 1 numbered phase |
| `.gsd-recipe/config.json` → `onboard.skip_tracker` | Yes | `true` |
| Jira Epic | No | Skipped via `--skip-tracker` |
| `recipe-bootstrap-knowledge` / `.knowledge/` | No | Next step per `recipe-next.sh` |
| Phase tasks (Jira) | No | Skipped |

## Script output (final)

### `recipe-next.sh`

```
=== Recipe next step ===

Why: Onboarding looks done; next is repo context for planning.

Type this in Cursor Agent:

  recipe-bootstrap-knowledge

Command: recipe-bootstrap-knowledge

This is for files on your current git checkout (branch).
recipe-start may offer to run the command after Yes.
recipe-help --next only prints it.
Catalog:  recipe-help
```

### `recipe-status.sh`

```
=== Recipe status ===

Branch:          main
Recipe skills:   yes
PRD:             yes  (docs/PRD.md)
ROADMAP:         yes
Knowledge:       no
Epic:            (skipped)
Phase tasks:     (none)
Current phase:    1
Phases:
  1: PLAN=no  SUMMARY=no
Install Jira:    pending
Verified:        no
Sync queue:      0 pending
Sync ledger:     0 entries
Last sync:       (none)

Suggest next: recipe-start   (offers to run it)
Catalog:      recipe-help
```

## Overall rating

**FRICTION** (not BLOCKED) — install and onboard path worked; minor friction around separate GSD install and inline roadmap when agents absent.

## Pass/fail: new hire can install + start + get PRD/planning without Jira

**PASS** — Using README install command and recipe commands only (`recipe-start` → `recipe-onboard --skip-tracker`), obtained `docs/PRD.md` and `.planning/ROADMAP.md` with one phase, no Epic, `skip_tracker` set, staying on `main`. No commits, push, or Jira creation.
