# `recipe-onboard` skill (TASK-037)

Closes the "no single on-ramp" gap flagged in the same SDLC coverage audit that motivated
`recipe-new-project` (TASK-036, built in the same pass): even with every individual onboarding piece
now recipe-native (`recipe-prd-intake`, `recipe-new-project`, `recipe-create-epic`,
`recipe-create-phase-tasks`), an operator still had to know and manually sequence four separate
invocations, in the right order, with no single command tying them together.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-onboard-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (7-step workflow) plus a prose body with `## Workflow`, `## Why one preview gate, not four nested ones`, `## Why it stops immediately on the first blocked step`, and `## What this does NOT do` sections — same structural convention as `recipe-install-SKILL.md`/`recipe-run-phases-SKILL.md`, the two closest existing thin-orchestrator precedents. |
| Installer | `.gsd-recipe/scripts/install-recipe-onboard.sh` | Standalone installer mirroring `install-recipe-run-phases.sh`'s exact single-file-staging structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard). Stages the skill under ledger component `"recipe-onboard"`. Never touches `.gsd-recipe/config.json`, `.planning/*`, or `docs/PRD.md` itself — those are the four invoked skills' own runtime concern. |
| Tests (installer) | `bench/tests/test-install-recipe-onboard.sh` (28 assertions) | Fail-closed non-git target, fresh install stages the one file + exactly 1 ledger row, never touches config/planning files, staged-content assertions covering every documented workflow step (invoking all four sub-skills by name, the single preview-then-confirm gate, stop-on-first-failure, skip-if-already-present, the never-re-implement/never-fabricate disclaimers, `intake_started` ownership relay, and the explicit `recipe-discuss-phase`/`recipe-complete-milestone` deferral notes), idempotent re-install, uninstall removes the file + clears the ledger entry + cleans up the empty directory, self-install collision safety, self-uninstall canonical-source preservation, and composition assertions against `install.sh`. |
| `install.sh` composition | `.gsd-recipe/scripts/install.sh` | Composed as the **21st** sub-installer, immediately after `recipe-new-project` (TASK-036): new `RECIPE_ONBOARD_INSTALLER` path variable, header-comment ledger-component list updated, `install()`'s composition list + consent-prompt string updated, `verify()`'s ledger-component checks extended, `uninstall()`'s cascade extended. |
| Catalog entry | `bench/lib/capability-schema.sh` + regenerated `.gsd-recipe/capability.json` | New `CATALOG` entry (`id: recipe-onboard`, `task_id: TASK-037`, `staged_path: .cursor/skills/recipe-onboard/SKILL.md`, `composed_by_install_sh: True`). `capability.json` regenerated via `generate-capability` (now 23 entries total, 3 staged in the real repo) and re-validated against `capability.schema.json` (`OK`). |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-037 row), `docs/netapp-recipe/README.md` (new "Built vs spec" row + new "Commands" table row + new note under "Spec (`recipe-*`)" explaining the `recipe-discuss-phase`/`recipe-complete-milestone` deferral) | Same row style/verbosity as every prior `recipe-*` task's documentation entries. |

## Locked design decisions worth flagging explicitly

### Why one preview-then-confirm gate, not four nested ones

Every one of the four invoked skills (`recipe-prd-intake`, `recipe-new-project`,
`recipe-create-epic`, `recipe-create-phase-tasks`) already has its own internal, appropriately-scoped
confirm/decline gate before doing anything consequential. Re-asking "are you sure?" a second time
immediately before each of those own gates would be pure noise stacked on top of already-adequate
protection. `recipe-onboard` instead shows exactly one gate, above all four, previewing the whole
chain (which steps will run vs skip) before anything happens — the same single-preview shape
`recipe-run-phases` already established for its own per-phase-range loop, deliberately lighter than
`recipe-install`'s heavier one-time first-scaffolding gate (onboarding a possibly-partially-set-up
repo is a lower-stakes, more-frequently-re-run action than writing brand-new scaffolding into an
unfamiliar repo for the very first time).

### Why the whole chain stops on the first blocked step

A missing PRD makes `recipe-new-project`'s own `docs/PRD.md`-as-input convenience meaningless (it
would fall through to native `gsd-new-project`'s own conversational flow anyway — not wrong, but not
"onboarding finished" either). A missing Epic makes `recipe-create-phase-tasks` meaningless — that
skill already fails closed on exactly that precondition (its own § B Prerequisites). Continuing past
a failed/declined step to a later one that depends on it would just relay a second, redundant
failure instead of stopping cleanly at the first one — same "stop the whole loop on first failure"
precedent `recipe-run-phases` already established for its own per-phase loop.

### Why `recipe-discuss-phase` and `recipe-complete-milestone` were evaluated but not built

Both were explicitly considered during this same gap-closing pass (per direct operator direction):
`recipe-discuss-phase` was judged not required right now, on the basis that PRD-level Q&A
(`recipe-prd-intake`'s own clarifying-question gate) is assumed to cover the gray areas a
phase-level discuss would otherwise surface; `recipe-complete-milestone` was judged out of scope for
this pass. Neither is silently folded into `recipe-onboard`'s own steps — this skill's own §D
explicitly disclaims doing so, and `docs/netapp-recipe/README.md`'s "Spec (`recipe-*`)" section now
carries a permanent note recording this decision for future reference.

## Validation performed

### Automated

```
$ ./bench/tests/test-install-recipe-onboard.sh
...
28 passed, 0 failed
```

Full `bench/tests/*.sh` suite (all 37 files) run after this task's edits landed:
`test-install-recipe-onboard.sh` (28/28), `test-install-recipe-new-project.sh` (28/28, companion
TASK-036 landed in the same pass), `test-install.sh` (all `recipe-onboard`-specific composition
assertions pass — one pre-existing, unrelated environment flake noted below), and
`test-capability-schema.sh` (31/31, including the updated 23-entry-catalog assertion). Zero
regressions introduced in any of the other 33 pre-existing test files.

**Two pre-existing, unrelated test-infra issues identified and confirmed NOT caused by this task**
(both investigated in depth, since they surfaced during this task's own full-suite run):

1. `bench/tests/test-install.sh`'s step-12 "fake npx" scratch-PATH helper
   (`make_scratch_path_excluding`) symlinks every real binary on `$PATH` into a scratch directory,
   then `cat >`s a fake script over the `npx` entry — on a machine where the real `npx` is a
   Homebrew-managed file, that write follows the symlink into the real, Homebrew-owned file and
   fails with `Permission denied`. Reproduced identically via `git stash --include-untracked` on the
   pristine, pre-task checkout, confirming this is a latent, environment-dependent bug unrelated to
   TASK-036/037.
2. `bench/tests/test-install-recipe-observe.sh`'s self-install-copy assertion
   (`self-install/uninstall never removes this repo's own bench/lib/observer-lib.sh copy under
   .gsd-recipe/lib`) fails because `.gsd-recipe/lib/observer-lib.sh` was never actually staged into
   this exact repo checkout — that file is only created by a real `install-observer.sh --yes` run
   against this repo, which was never run standalone here (only individual other sub-installers
   were self-installed during prior sessions). Confirmed via direct inspection
   (`.gsd-recipe/lib/` does not exist in this checkout) that this is a pre-existing environment gap,
   not something this task's changes touched or caused (this task never modified
   `install-observer.sh`, `install-recipe-observe.sh`, `observer-lib.sh`, or their templates).

Both left unfixed as explicitly out of scope for this task (see "Explicitly out of scope" below).

### Self-install into the real repo

```bash
$ ./.gsd-recipe/scripts/install-recipe-onboard.sh --yes
recipe-onboard installer: staged. Files tracked in .../.gsd-recipe/ledger.json:
  - .cursor/skills/recipe-onboard/SKILL.md
```

`recipe-onboard` is now a real, invokable Cursor skill at `.cursor/skills/recipe-onboard/SKILL.md`
in this repo, staged the same way every prior `recipe-*` skill in this repo was installed for real,
and composed into `install.sh --verify`'s own output (`recipe-onboard composed — pass`).

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Re-implementing any of `recipe-prd-intake`'s/`recipe-new-project`'s/`recipe-create-epic`'s/`recipe-create-phase-tasks`'s own logic | Pure orchestration — this skill's entire job is deciding *whether* to invoke each of the four, in order, and relaying the real result. |
| Emitting any Jira sync event itself | Every sync event in the chain is emitted by the skill that owns it (`recipe-create-epic` owns `intake_started`; `recipe-create-phase-tasks` owns its own per-task `createJiraIssue`/link calls). |
| Building `recipe-discuss-phase` or `recipe-complete-milestone` | Both explicitly evaluated and deferred per direct operator direction in this same pass — see "Locked design decisions" above. |
| Gating per-phase planning/execution | Onboarding ends once a PRD, `.planning/`, an Epic, and phase tasks all exist — `recipe-plan-phase`/`recipe-run-phase`/`recipe-run-phases` take over from there, entirely unchanged by this task. |
| Fixing `test-install.sh`'s pre-existing "fake npx" `Permission denied` flake, or `test-install-recipe-observe.sh`'s pre-existing missing-`observer-lib.sh` gap | Both confirmed pre-existing and unrelated to this task (see "Validation performed" above) — fixing unrelated test-infra bugs is out of scope for TASK-036/037. |

## Files

- `.gsd-recipe/templates/recipe-onboard-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-onboard.sh` (new)
- `bench/tests/test-install-recipe-onboard.sh` (new, 28 assertions)
- `.gsd-recipe/scripts/install.sh` (modified — composed as 21st sub-installer: path variable, header comment, `install()` composition + consent prompt, `verify()` ledger check, `uninstall()` cascade)
- `bench/lib/capability-schema.sh` (modified — new `recipe-onboard` catalog entry)
- `bench/tests/test-install.sh` (modified — composition/ledger/uninstall/verify-output assertions extended for `recipe-onboard`)
- `bench/tests/test-capability-schema.sh` (modified — catalog-id list, entry count 21→23, `task_id` assertion)
- `docs/netapp-recipe/BACKLOG.md` (modified — new TASK-037 row)
- `docs/netapp-recipe/README.md` (modified — new "Built vs spec" row, new "Commands" row, new "Spec (`recipe-*`)" deferral note)
- `bench/report/recipe-onboard-integration-report.md` (new — this file)
- `.cursor/skills/recipe-onboard/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/capability.json` (regenerated — 23 catalog entries)
- `.gsd-recipe/ledger.json` (self-install side effect, real repo — additive only)

## Deviations from the task

None. Built and fully integrated in the same pass as `recipe-new-project` (TASK-036) — both tasks
share the same `install.sh`/`capability-schema.sh`/`BACKLOG.md`/`README.md` edits, applied once,
sequentially, with no concurrent sibling agents in this pass to conflict with (unlike several prior
tasks, e.g. TASK-033/034, which deferred those same edits specifically to avoid concurrent-agent
merge conflicts).
