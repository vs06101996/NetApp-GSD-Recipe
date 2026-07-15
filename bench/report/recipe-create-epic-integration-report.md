# `recipe-create-epic` skill (TASK-033)

Closes the "PRD → Epic" gap: `recipe-prd-intake` (TASK-016) produces `docs/PRD.md`, but until this
task there was no recipe-native way to turn that PRD into a real Jira Epic and get it linked into
`.planning/STATE.md`'s `## Tracker` section — an operator had to hand-craft that section (per
`gsd-jira-sync-SKILL.md`'s own "Linking Jira to the project" example) and drive `createJiraIssue`
themselves.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| `parse-state.sh` extension | `bench/lib/parse-state.sh` — new `init-tracker` write subcommand | Writes/overwrites the `## Tracker` section's 5 required fields (`epic`/`system`/`url`/`run_id`/`arm`, DATA-CONTRACTS.md copy-paste order, `issue` omitted since it's optional/legacy). Creates `STATE.md` from scratch (both sections) if absent; inserts a `## Tracker` section preserving everything else byte-for-byte if the file exists but has none; no-ops idempotently on an identical re-run; fails non-zero with an actionable message naming the existing epic on a genuine conflict without `--force`; overwrites cleanly with `--force`, preserving `## Phase tasks` (including its data rows) and any other section untouched. |
| Tests (parser) | `bench/tests/test-parse-state.sh` — 14 new assertions (27 → 41 total) | Fresh-create with both sections; insert into a Phase-tasks-only file preserving its data row; idempotent no-op; conflict-without-force failure naming the existing epic + `--force`; conflict result never mutates the file; `--force` overwrite of all 5 fields while preserving pre-existing Phase-tasks rows; missing-required-field rejection. |
| Draft script (new) | `bench/runners/draft-jira-epic.sh` | Real, standalone, unit-testable script (bash + python3, `create-phase-tasks.sh`'s own style). Reads `docs/PRD.md` (or `--prd PATH`), emits `{"summary": "...", "description": "..."}` on stdout. `summary` = the file's first `# ` (H1) heading, trimmed, truncated to Jira's 255-char limit with a trailing `…` marker if longer, falling back to `"Untitled PRD"` (+ a stderr warning) if no H1 is found — never hard-fails on that account. `description` = every real `## `-level section from `.templates/PRD.template.md`'s actual heading names (Problem/Goals/Non-Goals/Requirements/Out of Scope/Open Questions), concatenated in file order as plain markdown — same simple-text approach `draft-jira-comment.sh` already uses, no ADF. Fails non-zero only when the PRD file itself doesn't exist. `--project KEY` is accepted (forwarded by the skill) but does not change the drafted body — only the agent-mediated `createJiraIssue` call needs it. |
| Tests (draft script) | `bench/tests/test-draft-jira-epic.sh` (17 assertions) + 4 new fixtures (`prd-normal.md`, `prd-missing-h1.md`, `prd-overlong-title.md`, plus the nonexistent-path case) | Nonexistent PRD fails closed with an actionable message; normal PRD emits exactly `{summary, description}`, summary from the real H1, description carries the real template section names in file order with real filled content; missing-H1 PRD falls back to the placeholder + a stderr warning, still exits 0; overlong title truncates to ≤255 chars with a trailing ellipsis; `--project` accepted without erroring; default `--prd` path resolves to `docs/PRD.md` under `REPO_ROOT`. |
| Skill content | `.gsd-recipe/templates/recipe-create-epic-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (10-step workflow) plus a prose body with `## Workflow`, three `## Why …` rationale sections, and a `## What this does NOT do` section — same structural convention as `recipe-plan-phase-SKILL.md`/`recipe-verify-feature-SKILL.md`. |
| Installer | `.gsd-recipe/scripts/install-recipe-create-epic.sh` | Standalone installer mirroring `install-recipe-pr-comment.sh`'s exact two-file-staging structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard). Stages both files under ledger component `"recipe-create-epic"`. Never touches `.gsd-recipe/config.json`, `.planning/STATE.md`, or `.planning/config.json` — those are the staged skill's own runtime concern whenever actually invoked, not the installer's job. **Additive beyond the mirrored shape:** also implements a light, read-only `--verify` mode (checks the ledger component + both staged files/executable bit) — the task's own validation checklist explicitly asked for "the installer's own `--verify` mode," and no existing standalone `recipe-*` installer implements one as a real CLI flag (only `install.sh` itself does) to mirror instead, so this is a small, deliberate, non-conflicting addition on top of the mirrored `install()`/`uninstall()` shape. |
| Tests (installer) | `bench/tests/test-install-recipe-create-epic.sh` (29 assertions) | Fail-closed non-git target, fresh install stages both files + exactly 2 ledger rows, never touches config/STATE/planning-config files, staged-content assertions covering every documented workflow step (draft delegation, fail-closed PRD-missing case, `createJiraIssue`, `init-tracker` linkage, `gsd-jira-sync intake_started` sync, live project/issue-type MCP resolution, `--force`, the no-direct-posting disclaimer), idempotent re-install, `--verify` pass/fail on installed/never-installed/uninstalled targets, uninstall removes both files + clears the ledger entry + cleans up the empty directory, self-install collision safety, self-uninstall canonical-source preservation. |

## Locked design decisions worth flagging explicitly

### `init-tracker`'s field order and scope

The 5 required `## Tracker` fields are written in `epic, system, url, run_id, arm` order — the same
order `DATA-CONTRACTS.md`'s copy-paste example uses once the optional legacy `issue` field is
removed (`epic, issue, system, url, run_id, arm` → drop `issue` → `epic, system, url, run_id, arm`).
`init-tracker` only ever manages these 5 fields: a `--force` overwrite replaces the entire
`## Tracker` block wholesale, which means a pre-existing `issue` convenience field (not part of
`init-tracker`'s own 5-field contract) would be dropped on overwrite. This wasn't exercised by any
of this task's required test cases and is called out here explicitly as a scope boundary, not an
oversight — `init-tracker`'s job is the 5 normative fields, not preserving every possible optional
extra key a hand-edited `## Tracker` section might have accumulated.

### Blank-line preservation on `--force` overwrite

The first implementation of the `--force` overwrite path accidentally consumed the blank separator
line between `## Tracker` and the next section (`## Phase tasks`) into the replaced range, because
the original "find where the tracker block ends" scan stopped at the next `##` heading inclusive of
any blank line immediately before it. Fixed by scanning backward from that boundary to keep any
trailing blank line(s) out of the replaced range — confirmed both by a direct manual repro
(`cat`/`Read` on the resulting file) and by the "still validates cleanly" / "preserves pre-existing
Phase tasks rows" assertions in `test-parse-state.sh`.

### Why `draft-jira-epic.sh` extracts *all* `## `-level sections, not a fixed whitelist

`.templates/PRD.template.md` defines exactly six `## `-level sections (`Problem`, `Goals`,
`Non-Goals`, `Requirements`, `Out of Scope`, `Open Questions (optional)`). Rather than hard-coding
that list and only extracting those specific headings by name (which would silently drop content if
an operator's real `docs/PRD.md` deviates slightly — extra sections, renamed headings, etc.),
`draft-jira-epic.sh` extracts *every* `## `-level section present in the actual file, in file order.
For a `docs/PRD.md` produced by `recipe-prd-intake` from the unmodified template, this produces
exactly the same six sections in exactly the same order — the task's own required test coverage
(fixture `prd-normal.md`) confirms this. The more general approach is strictly more resilient and
never invents section names that aren't actually in the file.

### Why this skill's installer gets an additive `--verify` mode

`install-recipe-pr-comment.sh` (this task's own mirrored reference) has no `--verify` flag at all —
verification for that component only exists inside `install.sh`'s own `verify()` function via
`ledger_has_component`. The task's validation checklist explicitly asked to "run your installer's
own `--verify` mode to confirm" as the final live sanity check, which the mirrored reference doesn't
support as a standalone flag. Rather than skip that requested check or silently deviate from the
mirror by inventing an incompatible shape, `install-recipe-create-epic.sh` adds a small, purely
additive `--verify` mode (read-only: ledger-component check + both staged files' existence/exec-bit)
on top of the otherwise-identical `install()`/`uninstall()` functions — it changes nothing about the
mirrored install/uninstall behavior itself, and a deferred integration pass composing this installer
into `install.sh` can simply ignore this installer's own `--verify` and continue relying on
`install.sh`'s own `ledger_has_component` check, exactly like every sibling sub-installer.

## Deferred integration snippets (NOT applied by this task — apply in a follow-up pass)

Per the task's own hard constraint, `.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`,
`bench/tests/test-install.sh`, `bench/tests/test-capability-schema.sh`,
`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, and `.gsd-recipe/capability.json`
were deliberately **not** touched by this task, to avoid merge conflicts with sibling agents building
TASK-034/TASK-035 concurrently. The exact, ready-to-copy-paste snippets for a deferred integration
pass follow.

### 1. `install.sh` composition — as the 18th sub-installer

Path variable (add alongside the existing `RECIPE_OBSERVE_INSTALLER` line):

```bash
RECIPE_CREATE_EPIC_INSTALLER="$SCRIPT_DIR/install-recipe-create-epic.sh"
```

`install()` — append to the composition list (after the `recipe-observe` call), and add
`recipe-create-epic` to both the header comment's ledger-component list and the consent-prompt
string:

```bash
  echo "install.sh: composing sub-installers (observer, tracker-sync, recipe-planning-policy, recipe-run-phase, recipe-plan-phase, recipe-validate-tokens, recipe-bootstrap-knowledge, recipe-install-verify, recipe-run-phases, recipe-verify-feature, recipe-review-ship, recipe-settle, gsd-jira-sync, recipe-sync, recipe-pr-comment, recipe-install, recipe-observe, recipe-create-epic)..."
  "$OBSERVER_INSTALLER" --yes --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VALIDATE_TOKENS_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASES_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VERIFY_FEATURE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_REVIEW_SHIP_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_SETTLE_INSTALLER" --yes --target "$TARGET"
  "$GSD_JIRA_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PR_COMMENT_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_OBSERVE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_CREATE_EPIC_INSTALLER" --yes --target "$TARGET"
```

Also update the operator consent-prompt string (the `read -r -p "Install NetApp GSD recipe scaffold
(... + recipe-observe)` line) to append `+ recipe-create-epic` at the end.

`verify()` — append a new ledger-component check block (after the existing `recipe-observe` block):

```bash
  if ledger_has_component "recipe-create-epic"; then
    echo "    recipe-create-epic composed — pass"
  else
    echo "    recipe-create-epic composed — FAIL (recipe-create-epic ledger component absent)"
    ok=0
  fi
```

`uninstall()` — append to the cascade (after the existing `recipe-observe` uninstall call):

```bash
  "$RECIPE_CREATE_EPIC_INSTALLER" --uninstall --target "$TARGET"
```

### 2. `bench/lib/capability-schema.sh` — new `CATALOG` entry

Append to the `CATALOG` list (after the existing `recipe-observe` entry):

```python
    {
        "id": "recipe-create-epic",
        "task_id": "TASK-033",
        "kind": "cursor-skill",
        "description": "PRD -> Jira Epic bridge: drafts summary/description from docs/PRD.md (bench/runners/draft-jira-epic.sh), resolves the Jira project/issue type (optional flags or live MCP questions via getVisibleJiraProjects/getJiraProjectIssueTypesMetadata), creates the Epic via createJiraIssue, links it into .planning/STATE.md's '## Tracker' section via parse-state.sh's new init-tracker write subcommand, and syncs intake_started via gsd-jira-sync (never posts/transitions Jira issues directly itself). Stages both the skill and its bench/runners/draft-jira-epic.sh runtime dependency, so no single canonical staged_path exists.",
        "invoke_name": "recipe-create-epic",
        "staged_path": None,
        "installer": ".gsd-recipe/scripts/install-recipe-create-epic.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-create-epic",
    },
```

### 3. `docs/netapp-recipe/BACKLOG.md` — new TASK-033 row

Append to the `### Wave 4 — observer` table (after the existing TASK-032 row), matching the existing
row style exactly:

```markdown
| TASK-033 | `recipe-create-epic` | S | 002, 016 | [DATA-CONTRACTS](contracts/DATA-CONTRACTS.md#state-md) — **Built**: closes the "PRD → Epic" gap — an invoke-by-name skill that reads `docs/PRD.md` (fails closed with an actionable message if absent, pointing at `recipe-prd-intake`), resolves the Jira project (optional `--project`, else a live, non-skippable `getVisibleJiraProjects` question — never defaults to "the first one returned") and the Epic issue type (optional `--issue-type`, else `getJiraProjectIssueTypesMetadata` with a safe case-insensitive "Epic" default, falling back to a live question only if genuinely absent), drafts the summary/description via the new `bench/runners/draft-jira-epic.sh` (real script; H1 heading -> summary with a 255-char Jira-limit truncation, the real `.templates/PRD.template.md` `## ` sections -> description, in file order), asks a soft yes/no confirm gate previewing everything before creating anything remote, calls `createJiraIssue` via the Atlassian MCP, links the result into `.planning/STATE.md`'s `## Tracker` section via `bench/lib/parse-state.sh`'s new `init-tracker` write subcommand (idempotent no-op on an identical relink; fails closed on a genuine conflict without `--force`; `--force` overwrites cleanly, preserving `## Phase tasks`), and syncs `intake_started` by invoking the `gsd-jira-sync` skill by name — never calling `addCommentToJiraIssue`/`transitionJiraIssue` directly itself. `.gsd-recipe/scripts/install-recipe-create-epic.sh` (standalone, ledger-tracked, stages both the skill and the runner under one `recipe-create-epic` ledger component — no single `staged_path`, same shape as `recipe-pr-comment`'s two-file case; also adds a small additive `--verify` mode beyond the mirrored shape), composed into `install.sh` as an 18th sub-installer. See [bench/report/recipe-create-epic-integration-report.md](../../bench/report/recipe-create-epic-integration-report.md). |
```

(`Depends: 002, 016` — `bench/lib/parse-state.sh`'s TASK-002 for the new `init-tracker` subcommand,
and TASK-016's `recipe-prd-intake` for the `docs/PRD.md` this skill reads.)

### 4. `docs/netapp-recipe/README.md` — "Built vs spec" table addition

Append one row to the "Built vs spec" table (after the existing `recipe-observe` row), matching the
existing row style exactly:

```markdown
| `recipe-create-epic` skill (TASK-033) | **Built** — closes the "PRD → Epic" gap: an invoke-by-name skill that reads `docs/PRD.md` (fails closed via `recipe-prd-intake` if absent), resolves the Jira project/issue type (optional flags or live `getVisibleJiraProjects`/`getJiraProjectIssueTypesMetadata` MCP questions), drafts the Epic body via the new `bench/runners/draft-jira-epic.sh` (H1 -> summary with a 255-char truncation, the real PRD template's `## ` sections -> description), asks a soft confirm gate, calls `createJiraIssue` via the Atlassian MCP, links the result into `.planning/STATE.md`'s `## Tracker` section via `bench/lib/parse-state.sh`'s new `init-tracker` write subcommand, and syncs `intake_started` via `gsd-jira-sync` by name — never posts/transitions Jira issues directly. `.gsd-recipe/scripts/install-recipe-create-epic.sh` (standalone installer composed into `install.sh` as an 18th sub-installer, staging both the skill and the runner under one ledger component) — see [bench/report/recipe-create-epic-integration-report.md](../../bench/report/recipe-create-epic-integration-report.md) |
```

## Validation performed

### Automated

```
$ ./bench/tests/test-parse-state.sh
...
41 passed, 0 failed

$ ./bench/tests/test-draft-jira-epic.sh
...
17 passed, 0 failed

$ ./bench/tests/test-install-recipe-create-epic.sh
...
29 passed, 0 failed
```

Full `bench/tests/*.sh` suite (every test file in the directory, run after this task's edits landed,
including `test-parse-state.sh`'s 14 new `init-tracker` assertions): **every file exits 0, zero
regressions**, including the pre-existing `test-install.sh` (126 assertions, unmodified — this task
never touched `install.sh`), `test-capability-schema.sh` (30 assertions, unmodified), and every other
sibling `recipe-*`/`install-*` test file already in the repo. `test-parse-state.sh` alone went from
27 → 41 assertions (the 14 new `init-tracker` cases), with zero changes to any of its 27 pre-existing
assertions' behavior.

### Manual (real-environment)

Every `init-tracker` branch (fresh-create, insert-into-Phase-tasks-only-file, idempotent no-op,
rejected conflict, `--force` overwrite, blank-line preservation) was additionally exercised by hand
against real scratch files (not just the automated fixtures) to catch the blank-line-preservation bug
described above before it reached the test suite.

### Self-install into the real repo

```bash
$ ./.gsd-recipe/scripts/install-recipe-create-epic.sh --yes --target /Users/vs72964/Projects/gsd-benchmark
recipe-create-epic installer: staged. Files tracked in .../.gsd-recipe/ledger.json:
  - .cursor/skills/recipe-create-epic/SKILL.md
  - bench/runners/draft-jira-epic.sh
...

$ ./.gsd-recipe/scripts/install-recipe-create-epic.sh --verify --target /Users/vs72964/Projects/gsd-benchmark
recipe-create-epic installer --verify: checking staged files for component 'recipe-create-epic'
  [pass] ledger component 'recipe-create-epic' present in .../.gsd-recipe/ledger.json
  [pass] .../.cursor/skills/recipe-create-epic/SKILL.md exists
  [pass] .../bench/runners/draft-jira-epic.sh exists
  [pass] .../bench/runners/draft-jira-epic.sh is executable
recipe-create-epic installer --verify: OK
```

`recipe-create-epic` is now a real, invokable Cursor skill at
`.cursor/skills/recipe-create-epic/SKILL.md` in this repo, staged the same way every prior `recipe-*`
skill in this repo was installed for real.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Editing `.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`, `bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `.gsd-recipe/capability.json` | Explicit task constraint — a deferred integration pass applies the snippets above together, to avoid merge conflicts with sibling agents building TASK-034/TASK-035 concurrently. |
| Creating phase sub-tasks | `create-phase-tasks.sh` (TASK-007)'s own job, run separately once phases exist in `ROADMAP.md` — this skill only ever creates the top-level Epic and the `## Tracker` linkage. |
| Posting/transitioning Jira issues directly | Exclusively `gsd-jira-sync`'s job (Option B) — this skill's only direct Jira-API call is `createJiraIssue`. |
| A skip/auto-answer mechanism for the step-6 confirm gate | Deliberately absent, same precedent as `recipe-settle`'s PO-accept gate — creating a Jira Epic is a real, not-cheaply-reversible remote action. |
| Preserving a pre-existing optional `issue` field across an `init-tracker --force` overwrite | Genuine scope boundary, not an oversight — see "Locked design decisions" above. |

## Files

- `bench/lib/parse-state.sh` (modified — new `init-tracker` subcommand)
- `bench/tests/test-parse-state.sh` (modified — 14 new assertions)
- `bench/runners/draft-jira-epic.sh` (new)
- `bench/tests/test-draft-jira-epic.sh` (new, 17 assertions)
- `bench/tests/fixtures/prd-normal.md` (new)
- `bench/tests/fixtures/prd-missing-h1.md` (new)
- `bench/tests/fixtures/prd-overlong-title.md` (new)
- `.gsd-recipe/templates/recipe-create-epic-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-create-epic.sh` (new)
- `bench/tests/test-install-recipe-create-epic.sh` (new, 29 assertions)
- `bench/report/recipe-create-epic-integration-report.md` (new — this file)
- `.cursor/skills/recipe-create-epic/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` (self-install side effect, real repo — additive only; was already untracked at session start)

**Not touched (per the task's hard constraint — snippets deferred above):**
`.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`, `.gsd-recipe/capability.json`.

**Not touched (called/read only, never edited — no bug found in any of them during this
integration):** `bench/lib/sync-ledger.sh`, `bench/runners/draft-jira-comment.sh`,
`bench/recipe/trackers/jira-events.json`, `.gsd-recipe/templates/gsd-jira-sync-SKILL.md`, or any
other already-built `recipe-*`/`gsd-jira-sync` skill's own files.

## Deviations from the task

None in scope or design. One judgment call worth flagging explicitly (a locked decision, documented
in-line in the installer's own header comment, not hidden):

1. **`install-recipe-create-epic.sh` adds a small additive `--verify` mode** beyond
   `install-recipe-pr-comment.sh`'s exactly-mirrored `install()`/`uninstall()` shape, specifically to
   satisfy the task's own validation checklist ("run your installer's own `--verify` mode to
   confirm") — see "Why this skill's installer gets an additive `--verify` mode" above for the full
   rationale.
