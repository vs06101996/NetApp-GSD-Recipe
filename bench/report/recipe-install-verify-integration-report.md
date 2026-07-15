# `recipe-install-verify` skill (TASK-023)

**Picked up per the task brief** (`TASK-023: recipe-install-verify`), matching the standalone-installer
precedent already used by `recipe-prd-intake` (TASK-016), `recipe-planning-policy` (TASK-012),
`recipe-run-phase` (TASK-024), and `recipe-plan-phase` (TASK-017) — built ahead of full composition
into `install.sh` (TASK-010, already built). Built **in parallel** with four sibling tasks
(TASK-007, TASK-011, TASK-021, TASK-022); per the task's explicit shared-file-avoidance constraint,
this task never edits `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, or `docs/netapp-recipe/README.md` — it only *invokes*
`install.sh --verify` read-only. Composition into those four files is proposed as copy-paste-ready
snippets for a human maintainer to apply (see "Proposed edits" below), not applied by this task.

## Scope decisions (confirmed against the source docs before building)

1. **Delegation boundary — `install.sh --verify` is the foundation for items 5-7, not a
   reimplementation target.** Read `.gsd-recipe/scripts/install.sh`'s actual `verify()` function in
   full: it already correctly and completely implements checklist items **5** (Templates present),
   **6** (OKF index), and **7** (Gitignore entries) as `test -f`/`grep` assertions — genuinely
   bash-checkable work, no agent/MCP dependency. It also checks `config.json` parses (a bonus check
   beyond the literal 10-item table) and its own install-time `github_check`/`jira_check` pair
   (distinct from, and not the same artifact as, this checklist's item 4 — see decision 3). This
   task's `recipe-install-verify` skill therefore calls `install.sh --verify` as a subprocess and
   parses its stdout for items 5-7, rather than re-implementing `test -f .templates/*.md` a second
   time. Items 1-3 and 8-10 are handled directly by this skill because none of them are
   bash-scriptable at all: 1-3 need native GSD commands, 8 needs an MCP tool-listing call, 9 needs a
   different read (observer *scheduling* state, not just "did the observer installer run" — see
   decision 4), and 10 needs a genuine one-time command execution gated on real repo-specific
   content existing. This mirrors the exact "a bash script has no MCP tool-calling access" split
   `bench/runners/sync-reconcile.sh`'s header comments document for why that script only *queues*
   Jira posts rather than posting them itself — the same category of bash-vs-agent capability
   boundary, applied to a different checklist.
2. **Items 1-3 call native GSD commands directly, same turn (Option B).** `docs/netapp-recipe/AGENTS.md`
   line 11's "do not invoke GSD skills on the user's behalf" rule has an already-approved exception,
   established in `.gsd-recipe/templates/recipe-plan-phase-SKILL.md`'s (and originally
   `recipe-run-phase-SKILL.md`'s) "Why Option B" section: the operator's own act of invoking a
   `recipe-*` skill by name **is** the manual GSD trigger. This task applies that same reasoning to
   `/gsd-health`, `/gsd-health --context`, and `/gsd-surface status` — all three are read-only,
   side-effect-free diagnostic commands (unlike the *mutating* `gsd-plan-phase`/`gsd-execute-phase`
   calls Option B already covers), so calling them directly under the same precedent is at least as
   safe. Documented explicitly in the skill's own "Why this skill may call native GSD commands
   directly" section, mirroring `recipe-plan-phase-SKILL.md`'s justification style per the task's
   instruction.
3. **Item 4 delegates to TASK-021 (`recipe-validate-tokens`), never duplicates it.** TASK-021 is
   being built in parallel and owns the full "token still valid" scope (`docs/netapp-recipe/lld/INSTALL-LLD.md`
   § "Step 1: Token validation [X]" — token presence, API probe, scope probe, GSD-version probe).
   This skill's item-4 logic is exactly two branches: if `.cursor/skills/recipe-validate-tokens/SKILL.md`
   is staged, invoke it skill-to-skill (identical shape to `recipe-run-phase` invoking
   `gsd-jira-sync` rather than inlining its posting logic) and use its verdict verbatim; if not
   staged, fall back to a **minimal** `gh auth status` check only — explicitly labeled in the
   recorded detail as a fallback, never a substitute for TASK-021's real scope. This is distinct
   from `install.sh`'s own install-time `github_check`/`jira_check` pair (which records install-time
   credential state in `install-report.json` under different keys, `github_check`/`jira_check`, not
   this checklist's item 4) — no collision, two different concerns living in the same file.
4. **Item 9 checks observer *scheduling*, complementing (not duplicating) `install.sh --verify`'s
   ledger-composition check.** `install.sh --verify`'s own "[X] 9. Observer loop composed" line only
   confirms the `fotw-observer` ledger component is non-empty — i.e. the installer *ran* — not
   whether the loop is actually `enabled`/scheduled right now. This skill instead reads
   `.gsd-recipe/observer-config.json` directly (per `docs/netapp-recipe/lld/OBSERVER-LLD.md`) and
   checks its `enabled` field — a different, complementary signal. Per OBSERVER-LLD.md's own
   "post-pilot, do not implement for v1 pilot" framing, this file's absence is `warn`, not `fail` —
   the checklist itself marks item 9 "optional v1".
5. **Item 10 never fabricates repo-specific bootstrap commands.** If `.templates/bare_metal.template.md`
   still holds its generic skeleton (the installer's own "Delete this comment block when filling in
   real bootstrap commands" marker, or any `` `<command>` `` placeholder in the four required rows),
   this skill warns and skips — matching `docs/netapp-recipe/lld/INSTALL-LLD.md`'s own documented
   feasibility caveat for this exact item verbatim. Only when the template is genuinely
   human-filled does this skill actually run the declared `install_deps`/`build`/`unit_tests`/`smoke`
   commands once.
6. **The `INSTALL-VERIFIED` marker lives inside `.gsd-recipe/install-report.json`, reusing that
   file's existing shape — never a third competing artifact.** `docs/netapp-recipe/lld/INSTALL-LLD.md`
   Step 5's own output row literally names `.gsd-recipe/install-report.json` as where the marker
   goes. `install.sh --verify` already writes to that file (`github_check`, `jira_check`, `prereqs`,
   `graphify_config_enabled`, `installed_at`, `last_install_at`) — this task's new
   `bench/lib/install-verify-report.sh` only ever *adds* two new keys, additive-only: a top-level
   `install_verified` boolean (the literal marker) and a `recipe_install_verify` object holding the
   full item-by-item detail. It never touches or overwrites install.sh's own fields. (`install.sh
   --verify` separately writes a **sibling** file, `.gsd-recipe/INSTALL-VERIFIED.json`, when its own
   narrower bash-checkable subset passes — that file remains install.sh's own artifact, untouched
   by this task. Two markers, two owners, no collision, both documented explicitly in the skill's
   own "Do NOT" section.)
7. **Never hard-blocks.** Per Step 5's own failure-handling row ("Block p1 usage until checks 1-7
   pass; 8-10 may warn-only"), the blocking semantics live entirely in the `install_verified`
   boolean's computed value — `install_verified` is `true` iff items 1-7 are *all* recorded
   `pass`; items 8-10 never affect it either way, even on `fail`. The skill's own execution never
   raises an error or stops early on any item's outcome — every item is always checked (or, for
   items requiring a native GSD call, explicitly reported as "not run this turn" rather than
   silently skipped) and reported.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-install-verify-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-plan-phase-SKILL.md`'s format) implementing the 9-step workflow: run `install.sh --verify` and parse items 5-7 → call native `/gsd-health` (item 1) → `/gsd-health --context` (item 2) → `/gsd-surface status` (item 3) → delegate to `recipe-validate-tokens` or fall back to `gh auth status` (item 4) → list MCP tools on the tracker server (item 8) → check `observer-config.json` (item 9) → gated `bare_metal.template.md` Gate A run (item 10) → record everything and summarize. Includes explicit "Delegation boundary", "Item 4 delegation relationship", "Why this skill may call native GSD commands directly", and "Never hard-blocks" sections. |
| Report writer (new runtime dependency) | `bench/lib/install-verify-report.sh` | `record`/`summary` subcommands. `record <item_number> <item_name> <pass\|warn\|fail> [--detail TEXT] [--report PATH]` merges one item's verdict into `.gsd-recipe/install-report.json`'s `recipe_install_verify.items` map and recomputes the `install_verified` marker (both the nested and the literal top-level key) from items 1-7 only, exactly matching Step 5's blocking rule. `summary [--report PATH]` reads back a formatted pass/warn/fail table plus the overall marker. Additive-only against the shared report file; validates item numbers (1-10) and status values (`pass`/`warn`/`fail`), fails closed on bad input. |
| Installer | `.gsd-recipe/scripts/install-recipe-install-verify.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s structure/functions (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging **two** files under component `"recipe-install-verify"`: the skill itself (`.cursor/skills/recipe-install-verify/SKILL.md`) and its runtime dependency (`bench/lib/install-verify-report.sh`, made executable). Never touches `.gsd-recipe/config.json`, `.gsd-recipe/install-report.json`, or `.planning/config.json` — writing into `install-report.json` is the *staged skill's* runtime job (via the lib it just staged), not this installer's. |
| Tests | `bench/tests/test-install-recipe-install-verify.sh` (40 assertions) | Standalone installer behavior (fresh install of both files, ledger row count, idempotency, uninstall, self-install, fail-closed, never touches any of the three config/report files, staged-content assertions for every documented gate/behavior/delegation) **plus** a standalone functional test of `bench/lib/install-verify-report.sh` itself: `record`/`summary` round-trip, the 1-7-blocking / 8-10-warn-only `install_verified` computation in both directions (all-pass-1-7-with-a-10-fail → still `true`; a single 1-7 failure → flips to `false`), and input validation (bad status value, out-of-range item number, missing report file). |
| Doc updates | none of the 4 forbidden files edited | Per the shared-file-avoidance constraint — see "Proposed edits" below for the exact snippets a human maintainer should apply to `install.sh`, `test-install.sh`, `BACKLOG.md`, and `README.md`. |
| Self-install | `.cursor/skills/recipe-install-verify/SKILL.md`, `bench/lib/install-verify-report.sh` | Live staged copies in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`, `recipe-run-phase`, `recipe-plan-phase`). |

### Why this installer stages two files, not one

Every prior standalone `recipe-*` installer (`recipe-run-phase`, `recipe-plan-phase`) stages exactly
one file: the skill itself, because all of their runtime logic is either inline instructions or
calls into *pre-existing* libs (`parse-state.sh`, `sync-ledger.sh`). This skill's item-writing logic
(merging pass/warn/fail verdicts into `install-report.json` and recomputing the blocking marker) is
genuinely new logic with no pre-existing lib to call into — so this task creates one
(`bench/lib/install-verify-report.sh`) and the installer stages it alongside the skill, both tracked
under the same `"recipe-install-verify"` ledger component for atomic install/uninstall.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Re-implementing `install.sh --verify`'s items 5-7 (or its bonus `config.json` check) | Decision 1 above — pure duplication with zero benefit; always parses that script's real output instead. |
| Re-implementing TASK-021's (`recipe-validate-tokens`) token/scope-probe scope for item 4 | Decision 3 above — the fallback is strictly `gh auth status`, nothing richer, ever, regardless of whether `recipe-validate-tokens` ends up staged. |
| Fabricating `bare_metal.template.md` bootstrap commands | Decision 5 above / `docs/netapp-recipe/lld/INSTALL-LLD.md`'s own documented feasibility caveat for this exact item — warn-and-skip is a hard rule, not a judgment call. |
| A second, competing `INSTALL-VERIFIED` artifact | Decision 6 above — `install.sh --verify`'s own `.gsd-recipe/INSTALL-VERIFIED.json` is left standing untouched; this task's marker lives inside `install-report.json` as an additive `install_verified` key. |
| Editing `install.sh`, `test-install.sh`, `BACKLOG.md`, or `README.md` | Explicit shared-file-avoidance constraint for this parallel-work task — see "Proposed edits" below for the deferred snippets. |
| Scheduling/automating the native GSD calls (items 1-3) | They only ever run once, inline, during a genuine operator-invoked `recipe-install-verify` turn — never backgrounded or auto-repeated. |
| Hard-blocking the operator on any outcome | Decision 7 above — every item is always checked and reported; only the `install_verified` *value* communicates blocking status downstream. |

## Validation performed

### Automated

`bench/tests/test-install-recipe-install-verify.sh` run standalone (per the task's explicit
instruction not to run the full `bench/tests/` suite while sibling tasks are editing shared files
concurrently):

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2-5 | Fresh install stages both `.cursor/skills/recipe-install-verify/SKILL.md` and `bench/lib/install-verify-report.sh` (executable), records exactly 2 ledger rows | PASS (all 4) |
| 6-8 | Install never creates `.gsd-recipe/config.json`, `.gsd-recipe/install-report.json`, or `.planning/config.json` | PASS (all 3) |
| 9-22 | Staged skill content references `install.sh --verify`, `/gsd-health`, `/gsd-health --context`, `/gsd-surface status`, `recipe-validate-tokens`, `gh auth status`, MCP tool listing, `observer-config.json`, `bare_metal.template.md`, the "never fabricate" disclaimer, `install_verified`, the "never hard-block" disclaimer, "Option B", `install-verify-report.sh`, and the "never duplicate" disclaimer (14 separate `grep` assertions) | PASS (all 14) |
| 23 | Re-running install does not duplicate ledger rows | PASS |
| 24-27 | Uninstall removes both staged files, clears the ledger entry, cleans up the now-empty skill directory | PASS (all 4) |
| 28-31 | Self-install into a copy of this repo does not error; self-uninstall does not error and preserves both canonical template sources | PASS (all 4) |
| 32-34 | `install-verify-report.sh` functional round-trip: `install_verified` is `true` when items 1-7 all pass regardless of items 8-10 (including a genuine item-10 `fail`); the nested `recipe_install_verify.install_verified` mirrors the top-level marker; item 10's individual `fail` status is preserved even though it never gates the marker | PASS (all 3) |
| 35 | `install_verified` flips to `false` the moment any of items 1-7 is recorded non-`pass` | PASS |
| 36-37 | `install-verify-report.sh` rejects an invalid status value and an out-of-range item number (input validation) | PASS (both) |
| 38-39 | `summary` runs cleanly against a populated report and fails (non-zero) against a missing one | PASS (both) |

`bench/tests/test-install-recipe-install-verify.sh` total: **40 assertions, 0 failed.**

Per the task's explicit instruction, the full `bench/tests/` suite was **not** run — four sibling
tasks are editing shared files (`install.sh`, `test-install.sh`, `BACKLOG.md`, `README.md`)
concurrently, and running the whole suite risks reading half-written files mid-edit.

### Manual (real-environment)

Ran against two fresh scratch repos, `/tmp/task-023-manual-01` and `/tmp/task-023-manual-02`, never
the real `gsd-benchmark` repo for the *verification-target* role (every command below used an
absolute path — `--target /tmp/task-023-manual-0N`, absolute installer/lib paths — in a single
self-contained invocation per tool call; no `cd` or exported variable was relied upon to survive
across separate tool calls, per the task's explicit safety constraint). This repo's own
`.gsd-recipe/scripts/install.sh` and `.gsd-recipe/scripts/install-recipe-install-verify.sh` were
invoked read-only against those scratch targets — never edited.

**Scratch-01 (full `install.sh --yes` run first, exercising the presence branches):**

1. `GSD_SIGNAL_PATH=/tmp/task-023-manual-01/.scratch-gsd-signal/SKILL.md
   /Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install.sh --yes --target
   /tmp/task-023-manual-01` — **real execution**, the actual `install.sh` (read-only invocation,
   not edited). `GSD_SIGNAL_PATH` was overridden to a scratch, nonexistent path per `install.sh`'s
   own documented test-safety convention ("tests must always override this to a scratch path, never
   the real one") — this avoided probing/mutating the real `~/.cursor/skills/gsd-help/SKILL.md`.
   Composed all five existing sub-installers (observer, tracker-sync, recipe-planning-policy,
   recipe-run-phase, recipe-plan-phase) for real, staged real templates/`.knowledge/`/
   `code_base_details/`, wrote a real `install-report.json`. Noted for transparency: the script's
   own `gh`/`gsd_core` prerequisite auto-fix attempts (`brew install gh`,
   `npx -y --package=@opengsd/gsd-core@latest -- gsd-core --claude --global`) genuinely ran (this is
   `install.sh`'s own pre-existing, already-shipped behavior, invoked read-only, not something this
   task added or modified) and returned quickly without actually installing `gh` — confirmed
   afterward via a real `command -v gh` check showing `gh` still absent from this machine, so no
   unintended side effect landed.
2. `install-recipe-install-verify.sh --yes --target /tmp/task-023-manual-01` — **real execution**,
   staged the real skill and lib into the scratch repo.
3. `.gsd-recipe/scripts/install.sh --verify --target /tmp/task-023-manual-01` — **real execution**.
   Real output: items 5/6/7 all `pass`, `config.json` check `pass`, all five ledger-composition
   checks `pass`, item 4b `jira_check: pending` (so the script's own exit code was 1 — expected,
   since the live Atlassian probe is architecturally agent-mediated and was never run against this
   scratch repo). This is the skill's own step 1 in action, for real — confirming the delegation to
   `install.sh --verify` genuinely works end to end.
4. Real `Read` of `/tmp/task-023-manual-01/.gsd-recipe/observer-config.json` — **present** (staged
   by the real `install-observer.sh` sub-installer in step 1), `enabled: true`,
   `tick_interval_seconds: 300` — the **presence branch** of item 9's logic, confirmed for real.
5. Real `Glob`/existence check for `/tmp/task-023-manual-01/.cursor/skills/recipe-validate-tokens/SKILL.md` —
   **not staged** (TASK-021 hasn't landed a file here) — confirmed for real, routing item 4 to the
   fallback branch.
6. Real `gh auth status` — exited 127, `gh` genuinely not installed on this machine — confirmed the
   fallback branch's real failure mode for item 4 (`fail`, detail: "gh CLI not found").
7. Real `GetMcpTools` call against the `plugin-atlassian-atlassian` server (the tracker's MCP server
   for the default `jira` tracker) — succeeded, returned a large non-empty tool catalog — item 8
   `pass`, genuinely exercised (this is an MCP meta-tool call, not a native GSD command, so it was
   not excluded by the task's "do not invoke native GSD commands for real" instruction).
8. Real `Read` of `/tmp/task-023-manual-01/.templates/bare_metal.template.md` — confirmed still
   generic (the installer's own "Delete this comment block..." marker present, all four required
   rows still hold the literal `` `<command>` `` placeholder) — item 10 correctly routed to
   `warn`/skip, never fabricated.
9. Recorded all of steps 3/4/6/7/8's real findings via the real, staged
   `/tmp/task-023-manual-01/bench/lib/install-verify-report.sh record ...` calls (items 4-10) and
   confirmed the resulting `install_verified` marker via `summary` — `false`, because items 1-3
   (native `/gsd-health`, `/gsd-health --context`, `/gsd-surface status`) were correctly **traced,
   not executed**, per the task's explicit instruction, leaving them unrecorded and therefore
   correctly counted as "not pass" by the blocking rule.

**Scratch-02 (no prior `install.sh` run at all, exercising the absence branches):**

1. `install-recipe-install-verify.sh --yes --target /tmp/task-023-manual-02` — **real execution**,
   staged the skill/lib with no other install-time state present.
2. Real existence check for `/tmp/task-023-manual-02/.gsd-recipe/observer-config.json` — **absent**
   — the **absence branch** of item 9's logic, confirmed for real (correctly routes to `warn`,
   "expected for v1" per `OBSERVER-LLD.md`).
3. `.gsd-recipe/scripts/install.sh --verify --target /tmp/task-023-manual-02` — **real execution**
   against a target that was never `install.sh`-installed at all. Confirmed the script degrades
   gracefully rather than crashing: prints "(none recorded yet — run install.sh first)" for
   prereqs, and reports items 5/6/7 and the `config.json` check as real `FAIL` (genuinely missing
   files) rather than erroring. This is exactly the scenario this skill's own § B "Prerequisites"
   section describes ("if it doesn't exist, warn the operator... and still proceed with whatever
   checks remain possible") — confirmed the underlying script itself already behaves that way, so
   the skill's instruction to keep going is realistic, not aspirational.
4. Recorded items 5/6/7/9's real `fail`/`fail`/`fail`/`warn` findings; confirmed `install_verified`
   remained `false` (as expected — items 1-4/8/10 were never recorded in this scenario either).

**Uninstall, both scratch repos:** `install-recipe-install-verify.sh --uninstall --target
/tmp/task-023-manual-0N` for both — real execution, confirmed both staged files removed from both
scratch repos afterward via `test ! -f`.

**What was truly exercised vs. traced:**

- **Truly executed** (real tool calls, real scripts, real files, on the scratch repos and via a
  real MCP meta-tool call only): the real `install.sh --yes` full install against scratch-01
  (composing all five existing sub-installers for real); the real
  `install-recipe-install-verify.sh` installer (both fresh-install and uninstall paths, both
  scratch repos); real `install.sh --verify` against both a freshly-installed target (scratch-01)
  and a never-installed target (scratch-02), including its real, non-crashing degraded-state
  behavior; real presence/absence checks of `.gsd-recipe/observer-config.json` in both directions;
  real `gh auth status` (genuine failure, `gh` absent) and a real `Glob`/existence check confirming
  `recipe-validate-tokens` isn't staged, correctly routing item 4 to its fallback branch; a real
  `GetMcpTools` call against the Atlassian MCP server for item 8; a real `Read` of
  `bare_metal.template.md` confirming it's still generic; and the full real `record`/`summary`
  round-trip against both scratch repos' `install-report.json` files, including both the
  all-pass-1-7 (well, 4-7 given 1-3 were traced) case and the observing-only-fails case.
- **Traced/reasoned about, not executed**: items 1-3 (`/gsd-health`, `/gsd-health --context`,
  `/gsd-surface status`) — per the task's explicit instruction to reserve these for a genuine
  operator-invoked turn. Reasoning: these are read-only, side-effect-free diagnostic commands; a
  real `/gsd-health` run against either scratch repo would report on *this* GSD installation's
  health (not the scratch repo's), so tracing rather than executing them here changes nothing about
  their eventual real behavior — the trace is: on a genuine invocation, `/gsd-health` would run,
  its pass/fail verdict would be recorded via `install-verify-report.sh record 1 ...`, and the same
  for items 2/3.

**Confirmed outcomes for the required scenario checks:**

1. **`install.sh --verify` delegation genuinely works.** Confirmed for real against scratch-01: the
   skill's step 1 (running `install.sh --verify --target <scratch>` and parsing its `[C] 5.`/
   `[C] 6.`/`[C] 7.` lines) produced real `pass` verdicts for all three items, sourced from the
   actual script's actual stdout, not fabricated.
2. **`.gsd-recipe/observer-config.json` presence/absence logic works in both directions.** Confirmed
   for real: scratch-01 (post-full-install) has the file, `enabled: true`, correctly routes to
   `pass`; scratch-02 (never installed) lacks the file entirely, correctly routes to `warn` per
   OBSERVER-LLD.md's own "post-pilot" framing.
3. **The `install_verified` blocking rule (1-7 gate, 8-10 never gate) computes correctly.** Confirmed
   both by the automated test's synthetic all-pass/one-fail cases (§ Automated, checks 32-35) and by
   the manual run's real partial data (both scratch repos correctly show `install_verified: false`
   given items 1-3 were never recorded — the correct behavior for an incomplete run, not a bug).
4. **Item 10 never fabricates.** Confirmed for real against scratch-01's genuinely-generic
   `bare_metal.template.md` — routed to `warn`/skip exactly as documented, no command invented.

## Proposed edits (deferred — not applied by this task)

Per the task's shared-file-avoidance constraint, the following four snippets are proposed for a
human maintainer (or a follow-up task once the four sibling tasks have landed) to apply by hand.
They are not applied here.

### `.gsd-recipe/scripts/install.sh`

Add a sixth sub-installer path variable, alongside the existing five:

```bash
RECIPE_PLAN_PHASE_INSTALLER="$SCRIPT_DIR/install-recipe-plan-phase.sh"
RECIPE_INSTALL_VERIFY_INSTALLER="$SCRIPT_DIR/install-recipe-install-verify.sh"
```

In `install()`, alongside the existing five composition calls:

```bash
  "$RECIPE_PLAN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --yes --target "$TARGET"
```

In `uninstall()`, alongside the existing five cascade calls:

```bash
  "$RECIPE_PLAN_PHASE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --uninstall --target "$TARGET"
```

In `verify()`, alongside the existing five ledger-composition checks:

```bash
  if ledger_has_component "recipe-plan-phase"; then
    echo "    recipe-plan-phase composed — pass"
  else
    echo "    recipe-plan-phase composed — FAIL (recipe-plan-phase ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-install-verify"; then
    echo "    recipe-install-verify composed — pass"
  else
    echo "    recipe-install-verify composed — FAIL (recipe-install-verify ledger component absent)"
    ok=0
  fi
```

Also update the operator-facing consent prompt and the header comment listing composed
sub-installers (both currently name five; append `+ recipe-install-verify` to each), matching the
exact wording pattern already used when `recipe-plan-phase` was added as the fifth.

### `bench/tests/test-install.sh`

Add composition assertions immediately after the existing `RECIPE_PLAN_PHASE_INSTALLER` block (same
four-assertion shape used for every prior sub-installer addition):

```bash
grep -q "RECIPE_INSTALL_VERIFY_INSTALLER" "$INSTALLER" && rc=0 || rc=$?
check "install.sh declares RECIPE_INSTALL_VERIFY_INSTALLER" "$rc"
grep -q 'RECIPE_INSTALL_VERIFY_INSTALLER" --yes' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_INSTALL_VERIFY_INSTALLER --yes" "$rc"
grep -q 'RECIPE_INSTALL_VERIFY_INSTALLER" --uninstall' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_INSTALL_VERIFY_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-install-verify"' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-install-verify ledger component" "$rc"
```

Also extend any existing "ledger components stay disjoint" assertion (if present) to include
`"recipe-install-verify"` in its checked set, same pattern used for every prior sub-installer
addition — search for where `"recipe-plan-phase"` was added to that set and add
`"recipe-install-verify"` alongside it.

### `docs/netapp-recipe/BACKLOG.md`

Update the TASK-023 row (Wave 1b table) with a narrowed-scope note, matching TASK-017/TASK-024's
row style:

```markdown
| TASK-023 | `recipe-install-verify` | S | 010 | [INSTALL-LLD](lld/INSTALL-LLD.md) — **Built**, scoped as a thin wrapper: delegates items 5-7 (templates/OKF-index/gitignore) to the existing `install.sh --verify`'s real output rather than re-checking them; runs items 1-3 (`/gsd-health`, `/gsd-health --context`, `/gsd-surface status`) directly via the approved Option-B precedent (`recipe-plan-phase-SKILL.md` § "Why Option B"); item 4 delegates to `recipe-validate-tokens` (TASK-021) if staged, else falls back to a minimal `gh auth status` only — never duplicates TASK-021's fuller probe; items 8-10 (MCP listing, observer-config.json, bare_metal Gate A) are read-only/warn-only checks, with item 10 never fabricating repo-specific bootstrap commands when the template is still generic. Writes an additive `install_verified` marker into `.gsd-recipe/install-report.json` (1-7 gate it, 8-10 never do), reusing that file's existing shape rather than inventing a competing artifact. See [bench/report/recipe-install-verify-integration-report.md](../../bench/report/recipe-install-verify-integration-report.md). |
```

### `docs/netapp-recipe/README.md`

Add a "Built vs spec" table row (insert after the `recipe-plan-phase` row):

```markdown
| `recipe-install-verify` skill (TASK-023) | **Built** — narrowed scope: post-install verification wrapper (`.gsd-recipe/scripts/install-recipe-install-verify.sh`, standalone installer proposed as a 6th sub-installer for `install.sh` — see the integration report's snippets); delegates checklist items 5-7 to `install.sh --verify`'s real output, runs items 1-3 directly via native GSD commands (Option B), delegates item 4 to `recipe-validate-tokens` (TASK-021) or a minimal `gh auth status` fallback, and checks items 8-10 read-only/warn-only (never fabricating `bare_metal.template.md` bootstrap commands); writes an additive `install_verified` marker into `.gsd-recipe/install-report.json` gated on items 1-7 only — see [bench/report/recipe-install-verify-integration-report.md](../../bench/report/recipe-install-verify-integration-report.md) |
```

Move `recipe-install-verify` from the "Spec" Commands table (it currently only appears there,
folded into the generic `recipe-install` p0 row's `INSTALL-LLD` reference) into the "Built" Commands
table:

```markdown
| `recipe-install-verify` (TASK-023) | Post-install Step-5 verification checklist — [.gsd-recipe/templates/recipe-install-verify-SKILL.md](../../.gsd-recipe/templates/recipe-install-verify-SKILL.md) · [report](../../bench/report/recipe-install-verify-integration-report.md) |
```

## Files

- `.gsd-recipe/templates/recipe-install-verify-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-install-verify.sh` (new)
- `bench/lib/install-verify-report.sh` (new)
- `bench/tests/test-install-recipe-install-verify.sh` (new, 40 assertions)
- `bench/report/recipe-install-verify-integration-report.md` (new, this file)
- `.cursor/skills/recipe-install-verify/SKILL.md` (self-install side effect, real repo)
- `bench/lib/install-verify-report.sh` (also present at the real-repo path as a self-install side
  effect of the installer step above — same file, already listed)
- **Not edited**: `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
  `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md` — see "Proposed edits" above.

## Deviations from the plan

None from the task brief's approved scoping. One interpretive judgment call, called out explicitly
rather than glossed over: the task brief said the report-writer logic should "reuse/extend"
`install-report.json`'s shape without specifying an exact mechanism; this task introduces one new
file, `bench/lib/install-verify-report.sh`, to own that write path (rather than embedding raw
`python3` heredocs directly in the skill's own instructions) — matching the existing convention of
`sync-ledger.sh`/`parse-state.sh`/`tracker-sync-config.sh` as small, testable, single-purpose libs
that skills shell out to, rather than every skill hand-rolling its own JSON-merge logic inline.
