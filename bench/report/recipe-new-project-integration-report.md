# `recipe-new-project` skill (TASK-036)

Closes the "make my current repo ready" gap flagged in the recipe's own SDLC coverage audit: of
every step in the onboarding flow (PRD intake → project bootstrap → Epic creation → phase-task
creation), project bootstrap was the one step with **no** `recipe-*` equivalent at all — an operator
following the recipe end to end still had to type native `gsd-new-project` (or `gsd-import`)
directly, making native GSD look like a permanent manual step rather than the one-time bootstrap it
actually is.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-new-project-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (5-step workflow) plus a prose body with `## Workflow`, a `## Why this skill never syncs intake_started itself` rationale section, a `## Relationship to recipe-onboard` section, and a `## What this does NOT do` section — same structural convention as `recipe-plan-phase-SKILL.md`/`recipe-create-epic-SKILL.md`. |
| Installer | `.gsd-recipe/scripts/install-recipe-new-project.sh` | Standalone installer mirroring `install-recipe-plan-phase.sh`'s exact single-file-staging structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard). Stages the skill under ledger component `"recipe-new-project"`. Never touches `.gsd-recipe/config.json`, `.planning/*`, or `docs/PRD.md` itself — those are the staged skill's own runtime concern whenever actually invoked, not the installer's job. |
| Tests (installer) | `bench/tests/test-install-recipe-new-project.sh` (28 assertions) | Fail-closed non-git target, fresh install stages the one file + exactly 1 ledger row, never touches config/planning files, staged-content assertions covering every documented workflow step (native `gsd-new-project`/`gsd-import` calls, first-init-vs-re-init routing, the soft warn-and-confirm gate, `docs/PRD.md` preference, re-verifying `PROJECT.md`, the `intake_started` non-sync disclaimer + `recipe-create-epic` ownership note, the `recipe-onboard` cross-reference, the fabrication disclaimer, DAG-out-of-scope), idempotent re-install, uninstall removes the file + clears the ledger entry + cleans up the empty directory, self-install collision safety, self-uninstall canonical-source preservation, and composition assertions against `install.sh` (declares `RECIPE_NEW_PROJECT_INSTALLER`, `install()`/`uninstall()` wiring, `verify()`'s `ledger_has_component` check). |
| `install.sh` composition | `.gsd-recipe/scripts/install.sh` | Composed as the **20th** sub-installer: new `RECIPE_NEW_PROJECT_INSTALLER` path variable, header-comment ledger-component list updated, `install()`'s composition list + consent-prompt string updated, `verify()`'s ledger-component checks extended, `uninstall()`'s cascade extended. |
| Catalog entry | `bench/lib/capability-schema.sh` + regenerated `.gsd-recipe/capability.json` | New `CATALOG` entry (`id: recipe-new-project`, `task_id: TASK-036`, `staged_path: .cursor/skills/recipe-new-project/SKILL.md`, `composed_by_install_sh: True`). `capability.json` regenerated via `generate-capability` and re-validated against `capability.schema.json` (`OK`). |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-036 row), `docs/netapp-recipe/README.md` (new "Built vs spec" row + new "Commands" table row + updated "Native GSD" row noting `gsd-new-project`/`gsd-import` are now wrapped) | Same row style/verbosity as every prior `recipe-*` task's documentation entries. |

## Locked design decisions worth flagging explicitly

### Why this skill never syncs `intake_started` itself

`bench/recipe/trackers/jira-events.json` lists `intake_started`'s `gsd_trigger` as "`gsd-new-project`
or `gsd-import`" — which could read as this skill's job to emit, since it's the one calling that
native command. It deliberately isn't: at the point this skill runs there may be no Jira Epic yet to
attach a comment to (Epic creation is `recipe-create-epic`'s job, TASK-033, one step later in the
onboarding chain). `recipe-create-epic` already owns emitting `intake_started` once the Epic
actually exists (see its own step 9). Having `recipe-new-project` also try to emit the same event
would either fail closed (no tracker issue to resolve yet) or, worse, risk a double-post once an
epic is eventually linked. One event, one owner — same principle every other `recipe-*` skill's sync
call in this repo already follows.

### Why `--import` was added rather than deferred

`jira-events.json`'s own trigger list names both `gsd-new-project` *and* `gsd-import` for the same
`intake_started` event — both are structurally identical wrappers (gate, resolve input, call one
native command, verify, report) from this skill's point of view, differing only in which native
command step 3 actually calls. Building only `gsd-new-project` support and leaving `gsd-import`
(brownfield/external-plan ingestion) as a permanent native-only gap would have reintroduced exactly
the coverage hole this task exists to close, for a case this skill was already 90% built to handle.
`--import` is purely additive — omitting it is byte-for-byte the pre-`--import` behavior.

### Why the re-init check is a soft warn-and-confirm, never a hard block

Re-running `gsd-new-project`/`gsd-import` against an already-initialized `.planning/ROADMAP.md` is
entirely native GSD's own business to allow, prompt about, or refuse — this skill has no authority
over `.planning/`'s own overwrite semantics (same narrowed-scope precedent `recipe-plan-phase`/
`recipe-run-phase` already established for themselves regarding `PLAN.md`/execute-phase). The step-1
check exists purely so the operator isn't surprised by native re-init behavior they didn't
anticipate — it is informational-and-confirmatory, not a gate this skill enforces on native GSD's
behalf.

## Validation performed

### Automated

```
$ ./bench/tests/test-install-recipe-new-project.sh
...
28 passed, 0 failed
```

Full `bench/tests/*.sh` suite (all 37 files) run after this task's edits landed:
`test-install-recipe-new-project.sh` (28/28), `test-install-recipe-onboard.sh` (28/28, companion
TASK-037 landed in the same pass), `test-install.sh` (all `recipe-new-project`-specific composition
assertions pass — see below for one pre-existing, unrelated environment flake), and
`test-capability-schema.sh` (31/31, including the updated 23-entry-catalog assertion). Zero
regressions introduced in any of the other 33 pre-existing test files.

**One pre-existing, unrelated test-infra flake identified and confirmed NOT caused by this task:**
`bench/tests/test-install.sh`'s own step-12 "fake npx" scratch-PATH helper
(`make_scratch_path_excluding`) symlinks every real binary already on the operator's `$PATH` into a
scratch directory, then tries to `cat >` a fake script over the `npx` entry. On a machine where the
real `npx` is a Homebrew-managed file (this environment), that `cat >` follows the symlink into the
real, Homebrew-owned file and fails with `Permission denied` — reproduced identically via
`git stash --include-untracked` on the pristine, pre-task checkout (i.e. before any TASK-036/037
files existed), confirming this is a latent, environment-dependent bug in `test-install.sh`'s own
helper, unrelated to and not introduced by this task. Left unfixed as explicitly out of scope for
this task (see "Explicitly out of scope" below); `bench/tests/test-install-recipe-observe.sh` was
separately confirmed to have its own, similarly pre-existing and unrelated gap
(`.gsd-recipe/lib/observer-lib.sh` was never staged into this exact repo checkout by a standalone
`install-observer.sh --yes` run, so its self-install-copy assertion fails independent of any
TASK-036/037 change).

### Self-install into the real repo

```bash
$ ./.gsd-recipe/scripts/install-recipe-new-project.sh --yes
recipe-new-project installer: staged. Files tracked in .../.gsd-recipe/ledger.json:
  - .cursor/skills/recipe-new-project/SKILL.md
```

`recipe-new-project` is now a real, invokable Cursor skill at
`.cursor/skills/recipe-new-project/SKILL.md` in this repo, staged the same way every prior
`recipe-*` skill in this repo was installed for real, and composed into `install.sh --verify`'s own
output (`recipe-new-project composed — pass`).

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Fabricating `.planning/PROJECT.md`/`ROADMAP.md`/`STATE.md` itself | Exclusively native `gsd-new-project`'s/`gsd-import`'s own output — this skill only gates the call and re-verifies the result. |
| Chaining to `recipe-prd-intake`/`recipe-create-epic`/`recipe-create-phase-tasks` | `recipe-onboard`'s job (TASK-037), built in this same pass but as a separate, distinct skill — not folded into this one. |
| Syncing `intake_started` | Exclusively `recipe-create-epic`'s job, once an Epic actually exists — see "Locked design decisions" above. |
| DAG frontmatter validation / Tier-1 topo-sort / `.knowledge/dag/*` read-write | Parked pending TASK-009, same precedent every other narrowed-scope `recipe-*` wrapper in this repo already established. |
| Fixing `test-install.sh`'s pre-existing "fake npx" `Permission denied` flake, or `test-install-recipe-observe.sh`'s pre-existing missing-`observer-lib.sh` gap | Both confirmed pre-existing and unrelated to this task (see "Validation performed" above) — fixing unrelated test-infra bugs is out of scope for TASK-036/037. |

## Files

- `.gsd-recipe/templates/recipe-new-project-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-new-project.sh` (new)
- `bench/tests/test-install-recipe-new-project.sh` (new, 28 assertions)
- `.gsd-recipe/scripts/install.sh` (modified — composed as 20th sub-installer: path variable, header comment, `install()` composition + consent prompt, `verify()` ledger check, `uninstall()` cascade)
- `bench/lib/capability-schema.sh` (modified — new `recipe-new-project` catalog entry)
- `bench/tests/test-install.sh` (modified — composition/ledger/uninstall/verify-output assertions extended for `recipe-new-project`)
- `bench/tests/test-capability-schema.sh` (modified — catalog-id list, entry count 21→23, `task_id` assertion)
- `docs/netapp-recipe/BACKLOG.md` (modified — new TASK-036 row)
- `docs/netapp-recipe/README.md` (modified — new "Built vs spec" row, new "Commands" row, updated "Native GSD" row, new "Spec (`recipe-*`)" deferred-items note)
- `bench/report/recipe-new-project-integration-report.md` (new — this file)
- `.cursor/skills/recipe-new-project/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/capability.json` (regenerated — 23 catalog entries)
- `.gsd-recipe/ledger.json` (self-install side effect, real repo — additive only)

## Deviations from the task

None. This task was built and fully integrated in the same pass (unlike several prior sibling tasks
which deferred `install.sh`/`capability-schema.sh`/`BACKLOG.md`/`README.md` edits to a follow-up
integration pass to avoid concurrent-agent merge conflicts) — there were no concurrently-building
sibling tasks in this pass, so the full integration (installer composition, catalog regeneration,
docs, tests) was completed directly rather than deferred.
