# E2E diary: new-hire install + onboard (retest2)

**Date:** 2026-08-24  
**Operator role:** new hire (no prior recipe work, no AgentStudio, no prior chats)  
**Recipe source:** `/Users/vs72964/Projects/gsd-benchmark`  
**Dummy product:** `/Users/vs72964/Projects/recipe-sandbox-e2e-retest2` (stayed on `main`)  
**Sources used:** README.md (and README-linked `docs/RECIPE-ONBOARD.md` for `--skip-tracker`), then staged `recipe-*` skills and helpers in the product repo only.

## Verdict

| Item | Result |
|------|--------|
| Overall | **FRICTION** (completed; not blocked) |
| Pass/fail: new hire can install + start + get PRD/planning without Jira, using README or recipe commands only | **PASS** |

## Time-ordered actions

1. **Read** `gsd-benchmark/README.md` only as the start. Install command discovered there: `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes --no-open-start`. Did **not** type `recipe-install` before skills existed.
2. Confirmed dummy product is a git repo on **`main`**.
3. **Installed** from the recipe clone into the dummy product (`--yes --no-open-start`). Install completed; next hint printed: `recipe-start`.
4. **Followed `recipe-start`:** read product `.cursor/skills/recipe-start/SKILL.md`. Ran `.gsd-recipe/scripts/recipe-next.sh` in the product.
5. Helper recommended **`recipe-onboard`** (no `docs/PRD.md`). That default chain would create Jira Epic + phase tasks. Per manager rules and README light path, did **not** Yes the default; used documented **`recipe-onboard --skip-tracker`**.
6. Preview (skill): PRD intake **run**, project bootstrap **run**, Epic **skip (flag)**, phase tasks **skip (flag)**. Confirmed that plan.
7. **`recipe-prd-intake`:** freeform brief “Hello Widget CLI” / print `hello widget` / one phase / no production. Wrote `docs/PRD.md` from `.templates/PRD.template.md`. Invoked `fotw-observer-bootstrap` (`can-spawn` allowed).
8. **`recipe-new-project`:** first-init. Native `gsd-new-project` skill present at `~/.cursor/skills/gsd-new-project/SKILL.md`. Ran **`--auto`** with **`commit_docs: false`** (no `git add`/`git commit` of `.planning/*`). **`agents_installed: false`** → warned, skipped research subagents, **inline** roadmap path. Did not fabricate a fake Epic key.
9. Native `generate-claude-md` to `.cursor/rules/` **failed** (ENOENT then EISDIR). Planning artifacts still present. Did **not** auto-advance into `gsd-discuss-phase` (onboard ends at PRD + planning).
10. After skip-tracker success, merged `"onboard": {"skip_tracker": true}` into `.gsd-recipe/config.json`.
11. **End:** ran `recipe-next.sh` and `recipe-status.sh` on the product (verbatim in diary below). Did **not** uninstall, push, or commit.

## README + recipe commands only?

**Yes**, with the README-named onboard doc for the no-Jira flag. Did not read BACKLOG, E2E diaries, or implementer notes as working sources. Did not use AgentStudio or a real product app repo.

## Friction

- **Default next step is Jira-full onboard.** `recipe-next` prints `recipe-onboard` with no `--skip-tracker`. A new hire who Yes’s `recipe-start` would hit Epic creation unless they already saw README’s light path.
- **GSD agents missing** on this machine (`agents_installed: false`). Bootstrap still worked via documented inline path, but the warning is noisy and `generate-claude-md` did not write a project guide.
- **`recipe-status` Knowledge: no** even though install staged `.knowledge/` skeleton (`index.md`). Status likely wants map/graphify, not the empty skeleton — next command is `recipe-bootstrap-knowledge`.
- Install records **Jira check pending**; expected for skip-tracker sandbox.

## Artifacts

| Artifact | Present? |
|----------|----------|
| `docs/PRD.md` | **yes** |
| `.planning/ROADMAP.md` | **yes** |
| `.planning/PROJECT.md` / `STATE.md` / `REQUIREMENTS.md` / `config.json` | **yes** |
| `onboard.skip_tracker` in `.gsd-recipe/config.json` | **yes** (`true`) |
| Epic in `.planning/STATE.md` | **no** (none invented) |
| Knowledge (status helper) | **no** (skeleton yes; mapped graph no) |
| Numbered phases | **Phase 1 only** (Hello Widget CLI) |
| Branch | **`main`**; HEAD still `46fb316` (no commit) |

## Helper output (verbatim)

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

## recipe-onboard `--skip-tracker` summary

| Step | Result |
|------|--------|
| PRD intake | **completed** — `docs/PRD.md` |
| Project bootstrap | **completed** — first-init, `gsd-new-project --auto`, `commit_docs: false`, inline roadmap |
| Epic creation | **skipped** (`--skip-tracker`) |
| Phase-task creation | **skipped** (`--skip-tracker`) |
