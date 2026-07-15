# gsd-jira-sync installer (TASK-028)

## The gap

`tracker-sync-SKILL.md` (TASK-014) explicitly says: "tracker: jira → invoke
the `gsd-jira-sync` skill... Follow *its* `SKILL.md`". Every already-built
`recipe-*` skill (`recipe-plan-phase`, `recipe-run-phase`,
`recipe-verify-feature`, `recipe-review-ship`, `recipe-settle`) also invokes
`gsd-jira-sync` "by name" for its own Jira sync step. But `gsd-jira-sync`
only ever existed as documentation at
`docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md` — nothing staged
it into `.cursor/skills/gsd-jira-sync/SKILL.md` on a fresh install, so on a
brand-new target repo every one of those "invoke `gsd-jira-sync` by name"
instructions would silently fail to resolve. This task closes that gap:
purely install-time staging/packaging, not a rewrite of the skill's
documented behavior.

## Scope decisions

| Decision | Rationale |
|---|---|
| Packaging task, not a rewrite | Preserve every documented behavior of the original skill (single-event mode, Drain mode, workflow steps 1-6, the "When to invoke" checklist, the STATE.md linking contract, MCP posting reference, the ic-* relationship note) — only path references were adapted. |
| Path references adapted to this repo's own canonical implementations | This repo (`gsd-benchmark`) already has `bench/runners/draft-jira-comment.sh`, `bench/runners/emit-stamp.sh`, `bench/runners/sync-drain-queue.sh`, `bench/lib/sync-ledger.sh`, `bench/lib/parse-state.sh`, `bench/recipe/trackers/jira-events.json` as first-class implementations — gsd-benchmark *is* the reference implementation host for this harness, not merely a copy target. The canonical template (`.gsd-recipe/templates/gsd-jira-sync-SKILL.md`) references those `bench/` paths directly, with the `docs/netapp-recipe/reference/harness/...` bundled mirrors called out as the fallback for a target that hasn't ported the `bench/` scripts yet — same "bundled path before copy, otherwise use the installed path" convention `tracker-sync-SKILL.md` § C already established for `tracker-sync-config.sh`. |
| Installer never touches `.gsd-recipe/config.json`'s `tracker` field | That's `install-tracker-sync.sh`'s own job (already built, TASK-014). This installer's only responsibility is staging the skill file itself. Never touches `.planning/config.json` either. |
| Ledger component name `"gsd-jira-sync"` | Matches the skill's own invoke-by-name identifier, same convention every other sub-installer already follows. |
| Composed into `install.sh` as the 13th sub-installer | No sibling tasks were running concurrently at the time of this pass, so — unlike several of the most recent `recipe-*` batches, which deferred composition to avoid merge conflicts — this task edited `install.sh`/`test-install.sh`/`capability-schema.sh`/`test-capability-schema.sh`/`BACKLOG.md`/`README.md` directly. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Canonical skill source | `.gsd-recipe/templates/gsd-jira-sync-SKILL.md` | Adapted from `docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md`; same `<cursor_skill_adapter>` convention as every other staged skill. Installer stages a copy to `.cursor/skills/gsd-jira-sync/SKILL.md`. |
| Installer | `.gsd-recipe/scripts/install-gsd-jira-sync.sh` | Standalone, ledger-tracked, idempotent, `--yes`/`--uninstall`/`--target` flags — mirrors `install-tracker-sync.sh`'s structure/functions (`ledger_init`/`ledger_record`/`ledger_files`/`safe_copy`/`is_canonical_source`) minus the `config.json`/`tracker` logic, since this installer owns none of that. |
| Composition | `.gsd-recipe/scripts/install.sh` | New `GSD_JIRA_SYNC_INSTALLER` path var, composed as the 13th sub-installer in `install()`, cascaded in `uninstall()`, checked in `verify()` via `ledger_has_component "gsd-jira-sync"`, consent-prompt string / "composing sub-installers" echo line / header comment's component-name list all updated to name it. |
| Capability catalog entry | `bench/lib/capability-schema.sh` | New `CATALOG` entry: `id: "gsd-jira-sync"`, `task_id: "TASK-028"`, `kind: "cursor-skill"`, `staged_path: ".cursor/skills/gsd-jira-sync/SKILL.md"`, `composed_by_install_sh: True`. |
| Tests | `bench/tests/test-install-gsd-jira-sync.sh` (31 assertions) | Fail-closed non-git target, fresh install, never touches `.gsd-recipe/config.json`/`.planning/config.json`/`.planning/STATE.md`/`.gsd-recipe/sync-ledger.jsonl`, ~16 staged-content assertions (single-event mode, Drain mode, `mark-done`/`mark-failed`, the epic-vs-phase routing rule, the "no empty comments"/"don't skip the Jira comment" disclaimers, the ic-* relationship note, the STATE.md linking contract), idempotent re-install, uninstall + directory cleanup, self-install collision safety. |
| Test additions | `bench/tests/test-install.sh`, `bench/tests/test-capability-schema.sh` | Extended in place (not duplicated) with the standard 4 checks (composition-staged, ledger-disjointness, `--verify` mention, `--uninstall` cascade) and the catalog-count/task_id/non-staged assertions respectively. |
| Docs | `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md` | New TASK-028 row in Wave 4 (right after TASK-014); new Built-vs-spec row; new Commands→Built row. |

## Explicitly out of scope

| Item | Why |
|---|---|
| Rewriting or "improving" `gsd-jira-sync`'s documented workflow | This is a packaging/staging task. See "Deviations" below for the one genuine ambiguity flagged rather than silently resolved. |
| Copying `bench/runners/*.sh`/`bench/lib/*.sh` themselves to a fresh non-gsd-benchmark target | Out of scope for this installer — it stages exactly one file, the skill doc. A truly fresh external target that isn't gsd-benchmark itself would need those harness scripts ported separately (pre-existing gap, not introduced or worsened by this task — same gap `tracker-sync-integration-report.md` already documents for its own runtime scripts). |
| `install-tracker-sync.sh`'s `config.json`/`tracker` logic | Owned entirely by TASK-014, unchanged by this task. |
| A `recipe-sync` orchestrator or `recipe-pr-comment` | Separate, out-of-scope future tasks (BACKLOG.md's Spec table). |
| Touching any other already-built component's files | `recipe-*` skills, `recipe-validate-tokens`, `recipe-bootstrap-knowledge`, `recipe-install-verify` were not modified. |

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1-31 | `bench/tests/test-install-gsd-jira-sync.sh` (new, standalone) | **PASS**, 31/31 |
| — | Full `bench/tests/*.sh` suite (26 files, run individually) | **PASS**, 0 failed across every file |
| — | `bash -n` on every shell file created/touched (`install-gsd-jira-sync.sh`, `install.sh`, `capability-schema.sh`, `test-install.sh`, `test-capability-schema.sh`, `test-install-gsd-jira-sync.sh`) | **PASS**, no syntax errors |

Full-suite per-file assertion counts (26 files, run individually, all exit 0):
`test-capability-schema.sh` 29, `test-create-phase-tasks.sh` 29,
`test-draft-github-pr-comment.sh` 13, `test-fotw-observer-nudge.sh` 10,
`test-install-gsd-jira-sync.sh` 31, `test-install-observer.sh` 17,
`test-install-recipe-bootstrap-knowledge.sh` 27,
`test-install-recipe-install-verify.sh` 40, `test-install-recipe-plan-phase.sh` 28,
`test-install-recipe-planning-policy.sh` 16, `test-install-recipe-prd-intake.sh` 17,
`test-install-recipe-review-ship.sh` 30, `test-install-recipe-run-phase.sh` 28,
`test-install-recipe-run-phases.sh` 26, `test-install-recipe-settle.sh` 47,
`test-install-recipe-validate-tokens.sh` 37, `test-install-recipe-verify-feature.sh` 31,
`test-install-tracker-sync.sh` 16, `test-install.sh` 114, `test-observer-lib.sh` 12,
`test-observer-tick-loop.sh` 6, `test-parse-state.sh` 27, `test-sync-drain-queue.sh` 18,
`test-sync-ledger.sh` 10, `test-sync-reconcile.sh` 14, `test-tracker-sync-config.sh` 10.

**Total: 26 files, 683 assertions, 0 failed, zero regressions.**

### Real-environment manual verification (disposable `/tmp` scratch repos, never this repo's own tree)

| # | Check | Result |
|---|---|---|
| 1 | Fresh `install-gsd-jira-sync.sh --yes` against a scratch git repo stages `.cursor/skills/gsd-jira-sync/SKILL.md`, records exactly 1 ledger row | PASS |
| 2 | Idempotent re-run against the same scratch repo — ledger row count unchanged | PASS |
| 3 | `--uninstall` against the scratch repo removes the staged file, clears the ledger entry to `{}` | PASS |
| 4 | Full `install.sh --yes` against a second scratch repo composes `install-gsd-jira-sync.sh` as its 13th sub-installer — `.cursor/skills/gsd-jira-sync/SKILL.md` staged, ledger row present | PASS |
| 5 | `install.sh`'s own `generate-capability` call reports `gsd-jira-sync` `staged: true`, 15 total catalog entries | PASS |
| 6 | That scratch `capability.json` validates against `capability.schema.json` | PASS (`OK`) |
| 7 | `install.sh --uninstall` against the scratch repo cascades to `install-gsd-jira-sync.sh --uninstall` — skill file removed | PASS |
| 8 | Scratch repos fully `rm -rf`'d after each check | PASS |

### Real-repo self-install

Ran `./.gsd-recipe/scripts/install-gsd-jira-sync.sh --yes --target <this repo>` directly against
`gsd-benchmark` itself — staged `.cursor/skills/gsd-jira-sync/SKILL.md` (a real, distinct copy of
the canonical `.gsd-recipe/templates/gsd-jira-sync-SKILL.md` source; `safe_copy`'s same-file
short-circuit does not apply here since the two paths are genuinely different files, same as every
prior self-install precedent for `tracker-sync`/`recipe-verify-feature`/etc.), and recorded it under
`.gsd-recipe/ledger.json`'s `"gsd-jira-sync"` component.

Then ran `./bench/lib/capability-schema.sh generate-capability --target <this repo>`:
wrote `.gsd-recipe/capability.json` with **15 capabilities, 12 staged** — `gsd-jira-sync` reports
`staged: true`, `ledger_tracked: true`, `task_id: "TASK-028"`. Validated the regenerated file with
`validate-capability --capability .gsd-recipe/capability.json --schema .gsd-recipe/capability.schema.json`
→ `OK`.

`git status --porcelain` afterward shows only the files this task was expected to touch
(`.cursor/skills/gsd-jira-sync/SKILL.md`, `.gsd-recipe/templates/gsd-jira-sync-SKILL.md`,
`.gsd-recipe/scripts/install-gsd-jira-sync.sh`, `.gsd-recipe/scripts/install.sh`,
`.gsd-recipe/capability.json`, `.gsd-recipe/ledger.json`, `bench/lib/capability-schema.sh`,
`bench/tests/test-install-gsd-jira-sync.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`, this report) plus the large pre-existing pile of untracked
`netapp-recipe`-feature files this whole multi-session effort has never committed yet (unrelated to
this task, present before this pass began). No other already-built component's files changed.

## Deviations / judgment calls

- **`gsd-jira-sync`'s own doc lists no explicit prerequisite check for whether the Atlassian MCP is
  even *reachable* before drafting a comment** — it reads MCP tool schemas in step 1 of § C, but
  the first real failure mode (unauthenticated/unreachable MCP) only surfaces once
  `CallMcpTool`/`addCommentToJiraIssue` is actually attempted. This is unchanged from the original
  doc (not introduced by this adaptation) and is consistent with every other `recipe-*` skill's own
  "fail-open, warn and continue" precedent for tracker/MCP issues — flagged here rather than
  silently tightened, per this task's "packaging, not a rewrite" scope.
- **Bundled-vs-canonical path phrasing.** The task's own precedent
  (`tracker-sync-SKILL.md` § C item 1) hedges with "bundled harness path before copy... if present —
  otherwise use the installed path" for a script (`tracker-sync-config.sh`) that in fact has *no*
  real `reference/harness/` mirror at all today. `gsd-jira-sync`'s three referenced scripts
  (`draft-jira-comment.sh`, `emit-stamp.sh`) *do* have real `reference/harness/runners/` mirrors, so
  the adapted template's phrasing was written to reflect that more precisely: "this repo's own
  canonical implementation... bundled mirror at `docs/netapp-recipe/reference/harness/...`, if
  present — only relevant on a target that hasn't ported the `bench/` scripts yet." This is the same
  underlying convention, phrased to match what's actually true of these three files rather than
  copying tracker-sync's exact wording verbatim. `sync-drain-queue.sh` intentionally has **no**
  bundled mirror at all (same as the original doc states, "no `reference/harness/` bundling for this
  script, matching TASK-001–003's precedent") — left unchanged.
- **README.md "~86% shipped" header left unchanged.** Recomputing per the task's own worked example
  (25 Built / 29 ≈ 86.2%, rounds to 86%) keeps the header text identical to before this addition —
  no numeric edit was needed, only the table rows.

## Files

- `.gsd-recipe/templates/gsd-jira-sync-SKILL.md` (new)
- `.gsd-recipe/scripts/install-gsd-jira-sync.sh` (new)
- `.gsd-recipe/scripts/install.sh` (modified — 13th sub-installer)
- `bench/lib/capability-schema.sh` (modified — new `CATALOG` entry)
- `bench/tests/test-install-gsd-jira-sync.sh` (new, 31 assertions)
- `bench/tests/test-install.sh` (modified — 4 new checks)
- `bench/tests/test-capability-schema.sh` (modified — count bump 14→15, non-staged list, task_id assertion)
- `docs/netapp-recipe/BACKLOG.md` (modified — new TASK-028 row)
- `docs/netapp-recipe/README.md` (modified — new Built-vs-spec row, new Commands→Built row)
- Installed into this repo: `.cursor/skills/gsd-jira-sync/SKILL.md`, `.gsd-recipe/ledger.json` (component `gsd-jira-sync`), `.gsd-recipe/capability.json` (regenerated, 15 entries)
