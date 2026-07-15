# `recipe-bootstrap-knowledge` skill (TASK-022)

**Picked up per the approved task brief**, matching the standalone-installer precedent already used
by `recipe-prd-intake` (TASK-016), `recipe-planning-policy` (TASK-012), `recipe-run-phase`
(TASK-024), and `recipe-plan-phase` (TASK-017) — built ahead of/alongside the full `install.sh`
(TASK-010, already built and composing five sub-installers). `BACKLOG.md` lists TASK-022 as
depending on TASK-010; per the same "standalone installer, composed into `install.sh` later"
pattern every prior `recipe-*` skill in this backlog has used, this task proceeds now on that basis
rather than waiting.

**Concurrency note:** this task ran in parallel with four sibling tasks (TASK-007, TASK-011,
TASK-021, TASK-023) editing the repo at the same time. Per an explicit constraint on this task, the
four shared files those siblings were also touching (`install.sh`, `test-install.sh`,
`BACKLOG.md`, `README.md`) were **not** edited here — every change that would normally land in
those four files instead ships as a copy-paste-ready snippet at the bottom of this report, for a
follow-up integration pass to apply once all five parallel tasks have landed.

## Scope decisions

1. **Option B — direct same-turn native calls for all three commands.**
   `recipe-bootstrap-knowledge` calls native `/gsd-map-codebase [--fast]`, `/gsd-graphify build`,
   and `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly, in the same turn.
   The operator's own act of invoking `recipe-bootstrap-knowledge` **is** the manual GSD trigger —
   the exact same precedent `recipe-plan-phase-SKILL.md` and `recipe-run-phase-SKILL.md` already
   establish for `gsd-plan-phase`/`gsd-execute-phase`, applied here unchanged to a third distinct
   trio of native commands. See "Why Option B" below for the full reasoning, mirrored from those
   two skills' own explanatory sections per the task brief's explicit instruction to do so.
2. **The `.knowledge/` skeleton scaffold is additive-only and per-piece, not all-or-nothing.**
   `index.md`, `log.md`, and each of the four subdirectories (`architecture/`,
   `dependency-graph/`, `hot-files/`, `risk-register/`) are checked and filled independently, so a
   partially-populated `.knowledge/` (e.g. after a prior partial run, or after `install.sh` already
   created some of it) only ever gets its remaining gaps filled — nothing pre-existing is ever
   regenerated or overwritten. `.knowledge/dag/` is deliberately excluded from this skill's
   scaffolding scope (see out-of-scope table below).
3. **The ingest step is the only conditionally-skippable one.** `.gsd-recipe/ingest-manifest.yaml`
   may not exist yet (confirmed: it doesn't exist anywhere in this repo today — see verification
   below). When absent, step 4 warns and skips itself only; `/gsd-map-codebase` and
   `/gsd-graphify build` have no equivalent missing-input condition and always run.
4. **`code_base_details/` is read-only from this skill's perspective.** Per
   `docs/netapp-recipe/lld/INSTALL-LLD.md`'s "If directory exists, update only — installer does
   not overwrite human files" rule, this skill never creates, edits, or deletes anything there —
   only `/gsd-ingest-docs` reads it.
5. **`gsd-extract-learnings`/`gsd-capture` wrapping is explicitly out of scope**, per the task
   brief's explicit instruction not to fold `OBSERVER-LLD.md`'s pilot-scoped manual fallback into
   this task.
6. **File list and installer/test shape as scoped** in the task brief — a single-file Cursor
   invoke-by-name skill (mirroring `recipe-run-phase`/`recipe-plan-phase`'s staging shape), a
   standalone installer, a standalone test file (installer behavior only, no `install.sh`
   composition assertions — deferred to the follow-up integration pass, see below), and this
   report.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| `gsd-extract-learnings`/`gsd-capture` wrapping | `OBSERVER-LLD.md` line 14 explicitly names these as the pilot's manual fallback — a different task/skill's scope entirely. Confirmed by re-reading `OBSERVER-LLD.md` before building; no conflicting content found. |
| `.knowledge/dag/` scaffolding or population | Owned by `install.sh`'s own Step 2 scaffolding (already creates `.knowledge/dag/.gitkeep`) and by the parked Tier-1 DAG work (TASK-009, `dag-build.sh`), locked "not required for v1" in `DECISIONS.md`. This skill never creates, reads, or writes `.knowledge/dag/*`. |
| `code_base_details/` writes | Human-authored content per `INSTALL-LLD.md`'s "update only" rule — this skill never touches it; only `/gsd-ingest-docs` reads it. |
| Manifest fabrication | A missing `.gsd-recipe/ingest-manifest.yaml` triggers a warn-and-skip of the ingest step alone, never an invented manifest. |
| Tracker/Jira sync (`gsd-jira-sync`) | `bench/recipe/trackers/jira-events.json` defines no event for a knowledge bootstrap/refresh — it isn't a phase/epic milestone. Confirmed by inspecting the events catalog: no `knowledge_*` event exists. This skill never calls `gsd-jira-sync` or touches `sync-ledger.sh`. |
| `install.sh`/`test-install.sh`/`BACKLOG.md`/`README.md` edits | Explicit constraint for this task run (four sibling tasks concurrently editing those files) — see the copy-paste-ready snippets at the bottom of this report instead. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-plan-phase-SKILL.md`'s format and its "Why Option B" explanatory section style) implementing the 5-step workflow: check `.knowledge/` and scaffold any missing piece (additive-only) → call native `/gsd-map-codebase [--fast]` → call native `/gsd-graphify build` → check for `.gsd-recipe/ingest-manifest.yaml` and call native `/gsd-ingest-docs` if present, else warn-and-skip → one-report summary. |
| Installer | `.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s structure/functions (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` — the invoke-by-name Cursor skill path. Component name `"recipe-bootstrap-knowledge"`. Never touches `.gsd-recipe/config.json`, `.planning/config.json`, `.knowledge/`, or `code_base_details/` — those are the staged skill's own runtime job, not the installer's. |
| Tests | `bench/tests/test-install-recipe-bootstrap-knowledge.sh` (27 assertions) | Standalone installer behavior only (fresh install, idempotency, uninstall, self-install, fail-closed, never touches config.json/.knowledge/code_base_details, staged-content assertions for every documented step/gate/behavior). Deliberately omits `install.sh` composition assertions — see "Deferred composition" below. |
| Doc updates | `docs/netapp-recipe/lld/INSTALL-LLD.md` | None required — confirmed no conflicting content on re-read; the existing "Populate `.knowledge/` from GSD" section already fully describes the 3 commands this skill wraps, verbatim. No scope-annotation edit was needed. |
| Self-install | `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` | Live staged copy in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`, `recipe-run-phase`, `recipe-plan-phase`). |
| This report | `bench/report/recipe-bootstrap-knowledge-integration-report.md` | Full validation record + the four deferred snippets. |

### Deferred composition (`install.sh` / `test-install.sh` / `BACKLOG.md` / `README.md`)

Unlike every prior `recipe-*` task's report (which shipped its `install.sh`/`test-install.sh`/
`BACKLOG.md`/`README.md` edits directly, since no sibling tasks were concurrently editing those
files at the time), this task's constraints explicitly forbid touching those four files — four
sibling tasks (TASK-007, TASK-011, TASK-021, TASK-023) are editing them right now. The exact
snippets that a follow-up integration pass should apply — sized and shaped identically to how
TASK-017's own report documented its fifth-sub-installer wiring — are reproduced verbatim at the
bottom of this report.

### Why this installer stages under `.cursor/skills/`, not plain `skills/`

Same rationale as every prior invoke-by-name `recipe-*` skill's report: `recipe-planning-policy`
(TASK-012) is GSD's own **injected-context** mechanism (`.planning/config.json`'s
`agent_skills.<agentType>` array) — nothing ever invokes it by name, so it stages to a plain
top-level `skills/` directory with no `<cursor_skill_adapter>` block. `recipe-bootstrap-knowledge`
is the opposite case: an operator genuinely types `recipe-bootstrap-knowledge` (optionally
`--fast`) to invoke it, exactly like `recipe-run-phase`/`recipe-plan-phase`/`tracker-sync`/
`recipe-prd-intake`. So this installer mirrors those skills' `.cursor/skills/<name>/SKILL.md`
staging path and full A/B/C/D adapter format.

## Why Option B (direct same-turn calls), not a background/async trigger

This is the third `recipe-*` skill in this backlog to apply the same approved reasoning, so it's
worth stating precisely, mirroring `recipe-plan-phase-SKILL.md`'s and `recipe-run-phase-SKILL.md`'s
own "Why Option B" sections almost verbatim (per the task brief's explicit instruction to do so):

**The standing rule** (`docs/netapp-recipe/AGENTS.md` line 11): "User runs GSD skills manually —
do not invoke `gsd-plan-phase`, `gsd-execute-phase`, etc. on the user's behalf." This governs
*autonomous, unrequested* invocation of native GSD commands on the operator's behalf — an agent
deciding on its own, mid-turn, unprompted, to run `gsd-plan-phase` or similar.

**The precedent** (already approved for `recipe-plan-phase`/`recipe-run-phase`): invoking a
`recipe-*` skill *by name* is not autonomous or unrequested — it is the operator's own deliberate,
explicit act of asking for exactly the workflow that skill documents. `recipe-plan-phase N`'s
SKILL.md states this directly: "the operator's own act of invoking `recipe-plan-phase` already is
the 'human decided to plan this phase' gate `RUNTIME-LLD.md` describes for `gsd-plan-phase`."
`recipe-run-phase N`'s SKILL.md states the identical reasoning for `gsd-execute-phase`.

**Applied here, unchanged:** `docs/netapp-recipe/lld/INSTALL-LLD.md` § "Populate `.knowledge/` from
GSD" describes exactly this same shape of manual trigger — "After install, **operator or agent
runs** (once per repo, refresh on major change): `/gsd-map-codebase [--fast]`, `/gsd-graphify
build`, `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml`." The operator's own act of
invoking `recipe-bootstrap-knowledge` **is** that manual run — the same "human decided to do this
now" gate, applied to a third distinct trio of native commands rather than a first or second. No
new precedent is created; this is a direct, narrow reapplication of an already-approved pattern.

**The one deliberate contrast**, named explicitly (same as both prior reports do): unlike
`recipe-prd-intake`'s deliberate *non*-invocation of `gsd-discuss-phase` (that skill explicitly
defers to the operator to run discuss themselves — see its own SKILL.md § D), this skill —
like `recipe-plan-phase` and `recipe-run-phase` before it — is explicitly approved to call all
three native knowledge commands on the operator's behalf, because `recipe-bootstrap-knowledge`
*is* the operator's request to bootstrap/refresh knowledge right now.

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4-7 | Install never creates `.gsd-recipe/config.json`, `.planning/config.json`, `.knowledge/`, or `code_base_details/` (those are the staged skill's own runtime job, not the installer's) | PASS (all 4) |
| 8-19 | Staged content references native `/gsd-map-codebase`, `/gsd-graphify build`, `/gsd-ingest-docs`, `.gsd-recipe/ingest-manifest.yaml`, a graceful skip/warn for a missing manifest, a "never hard-fail" disclaimer, all 4 `.knowledge/` subdirectories, a "never overwrite" idempotency disclaimer, `code_base_details/` preservation, the "manual GSD trigger" Option-B reasoning, OKF frontmatter placeholders, the `gsd-extract-learnings`/`gsd-capture` out-of-scope disclaimer, and `.knowledge/dag/` out-of-scope (12 separate `grep` assertions) | PASS (all 12) |
| 20 | Re-running install does not duplicate ledger rows | PASS |
| 21 | Uninstall removes the staged skill | PASS |
| 22 | Uninstall clears the component's ledger entry | PASS |
| 23 | Uninstall cleans up the now-empty skill directory | PASS |
| 24 | Self-install into a copy of this repo does not error (src==dest collision handled) | PASS |
| 25 | Self-install uninstall does not error | PASS |
| 26 | Self-uninstall preserves the canonical skill template source | PASS |

`bench/tests/test-install-recipe-bootstrap-knowledge.sh` total run, standalone: **27 assertions,
0 failed.**

```text
$ ./bench/tests/test-install-recipe-bootstrap-knowledge.sh
ok - refuses to install into a non-git directory
ok - fresh install stages .cursor/skills/recipe-bootstrap-knowledge/SKILL.md
ok - fresh install records exactly 1 ledger row (the skill file)
ok - install never creates .gsd-recipe/config.json
ok - install never creates .planning/config.json
ok - install never creates .knowledge/ itself (that's the staged skill's runtime job)
ok - install never creates code_base_details/ itself
ok - staged skill references native /gsd-map-codebase
ok - staged skill references native /gsd-graphify build
ok - staged skill references native /gsd-ingest-docs
ok - staged skill references .gsd-recipe/ingest-manifest.yaml
ok - staged skill documents a graceful skip/warn for a missing ingest manifest
ok - staged skill disclaims hard-failing when the manifest is missing
ok - staged skill enumerates all 4 .knowledge/ subdirectories to scaffold
ok - staged skill disclaims overwriting existing .knowledge/ content (idempotent)
ok - staged skill references preserving human-authored code_base_details/
ok - staged skill documents the Option-B same-turn-call reasoning
ok - staged skill references OKF frontmatter placeholders
ok - staged skill disclaims wrapping gsd-extract-learnings/gsd-capture (out of scope)
ok - staged skill documents .knowledge/dag/ as explicitly out of scope
ok - re-running install does not duplicate ledger rows
ok - uninstall removes the staged skill
ok - uninstall clears the component's ledger entry
ok - uninstall cleans up the now-empty skill directory
ok - self-install into a copy of this repo does not error (src==dest collision handled)
ok - self-install uninstall does not error
ok - self-uninstall preserves the canonical skill template source
---
27 passed, 0 failed
```

**Per this task's explicit instruction, the full `bench/tests/` suite was NOT run** — four sibling
tasks are editing files under `bench/tests/`/`bench/lib/`/`.gsd-recipe/` concurrently, and running
the full suite risked reading half-written sibling files mid-edit. Only this task's own new test
file was run, standalone, exactly as instructed.

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/task-022-manual-01` (never the real `gsd-benchmark`
repo for the scratch scenarios below — every command used an absolute path, either
`--target /tmp/task-022-manual-01` for the installer or a plain absolute path for the standalone
scaffold-logic script; no `cd` was relied upon to survive across separate tool calls, per this
task's explicit safety requirement). Setup:

```bash
rm -rf /tmp/task-022-manual-01 && mkdir -p /tmp/task-022-manual-01 \
  && git -C /tmp/task-022-manual-01 init -q \
  && git -C /tmp/task-022-manual-01 commit --allow-empty -qm init
```

**Step 1 — real installer execution** (not simulated):

```bash
/Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh \
  --yes --target /tmp/task-022-manual-01
```

Confirmed for real: `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` staged in the scratch
repo; `.gsd-recipe/ledger.json` created there with exactly 1 row under
`"recipe-bootstrap-knowledge"`; `.knowledge/` and `code_base_details/` genuinely **not** created
by the installer (confirmed by real `ls`) — exactly as documented (that scaffolding is the staged
skill's own runtime job, not the installer's).

**Step 2 — the `.knowledge/` skeleton-fill logic (step 1 of the skill's own workflow), executed for
real.** Per this task's explicit instruction not to invoke `/gsd-map-codebase`,
`/gsd-graphify build`, or `/gsd-ingest-docs` for real, but to genuinely exercise the
directory-skeleton creation, idempotency, and human-file-preservation logic — I wrote a small
standalone script (`/tmp/task-022-manual-01/scaffold-knowledge.sh`) that implements *exactly* the
check-then-create-only-if-missing logic the staged `SKILL.md`'s § C.1 documents (same
`type: index`/`type: log` OKF frontmatter placeholders, same 4 subdirectories, same
`.gitkeep`-if-empty rule), and ran it for real, multiple times, against the real scratch repo:

| Run | Scenario | Real result |
|---|---|---|
| 1 | Fresh repo, `.knowledge/` doesn't exist at all | **Created all 6 pieces**: `index.md`, `log.md`, `architecture/`, `dependency-graph/`, `hot-files/`, `risk-register/` (each with `.gitkeep`). Verified via real `find`. |
| 2 | Re-run, everything now exists (including a manual human edit appended to `index.md`) | **Nothing created** — every piece reported "already exists, left untouched." Real `md5` of `index.md` before and after the re-run is **byte-for-byte identical** (`9b2a4ca2526194bd973564687da3bc7c` both times), confirming the human edit survived untouched. |
| 3 | Partial state: `hot-files/` deleted, `architecture/` given real content (`notes.md`, standing in for `/gsd-map-codebase`'s eventual output) | **Only `hot-files/` recreated.** `architecture/notes.md`'s content is confirmed still present afterward (real `cat`); `index.md`'s md5 confirmed still unchanged from run 2. This is the genuinely additive/per-piece behavior the task brief specifically asked to be verified, not just a whole-directory existence check. |

**Step 3 — `code_base_details/` preservation, executed for real.** Created a real
`code_base_details/README.md` with placeholder human content, recorded its md5, re-ran the
skeleton-fill script, and confirmed via real `md5` comparison that the file is **byte-for-byte
unchanged** — the skeleton-fill logic never touches this path at all (it has no code path that
even references `code_base_details/`).

**Step 4 — the manifest-presence branch, exercised for real up to the trace boundary.** Confirmed
for real (`ls`/`[ -f ... ]`) that `.gsd-recipe/ingest-manifest.yaml` genuinely does not exist yet
anywhere in the scratch repo — the real condition step 4 would evaluate, "missing," matching this
repo's own real state today (confirmed separately: no such file exists anywhere under
`gsd-benchmark` either, via `grep -r` across the repo finding zero actual `.yaml` files at that
path, only doc references to the *path string*). Then created a real, schema-conformant
`.gsd-recipe/ingest-manifest.yaml` (matching `DATA-CONTRACTS.md`'s example shape) in the scratch
repo and confirmed the condition would flip to "present" for a subsequent invocation.

**What was truly exercised vs. traced:**

- **Truly executed** (real tool calls, real files, on the scratch repo only): the installer
  itself (staged a real file, wrote a real ledger row, real fail-closed check against a non-git
  temp dir); the full `.knowledge/` skeleton-fill logic across all 3 scenarios above (fresh
  create, byte-identical idempotent re-run including a genuine human-edit-survives check, and a
  genuine partial-gap-fill scenario); the `code_base_details/` non-interference check (byte-level
  diff); the manifest absent-vs-present condition check that step 4 would branch on.
- **Traced/reasoned about, not executed** (per the task's explicit instruction, and this
  environment's inability to spawn a nested Cursor agent turn to run the skill end-to-end as an
  operator would): the three native calls themselves —
  - `/gsd-map-codebase [--fast]` would walk the real `gsd-benchmark` codebase and populate
    `.knowledge/architecture/`, `dependency-graph/`, `hot-files/` with real analysis output
    (exact shape depends on GSD's own internal mapping logic, not reproducible here).
  - `/gsd-graphify build` would build a dependency/knowledge graph, likely also populating
    `.knowledge/dependency-graph/` and/or a graphify-specific store (per
    `docs/netapp-recipe/lld/PLANNING-POLICY.md`'s own reference to `gsd-graphify query`, this is
    consumed later by the planning-policy skill's optional graphify read).
  - `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` would read `docs/PRD.md`,
    `code_base_details/`, and `docs/` per the manifest's `sources` list and produce ingested
    summaries — again, GSD-internal logic not reproducible outside a real invocation.
  
  None of these three calls were actually invoked — consistent with the standing project rule
  that GSD skill invocation is reserved for genuine operator-invoked turns, not test/verification
  passes, and with this task's own explicit instruction to trace rather than execute them.

**Confirmed outcomes for the 3 required manual-verification properties:**

1. **Directory-skeleton creation genuinely works.** Confirmed for real (run 1): a fresh scratch
   repo with no `.knowledge/` at all ends up with the exact 6 pieces the SKILL.md documents,
   correctly shaped (OKF frontmatter, `.gitkeep`s).
2. **Idempotency genuinely holds.** Confirmed for real (run 2): re-running the identical logic
   against an already-complete `.knowledge/` — including one file with genuine human-appended
   content — produces zero writes, verified at the byte level via `md5`, not just "the file still
   exists."
3. **Human-file-preservation genuinely holds**, for both the in-scope case (`.knowledge/`'s own
   pre-existing pieces, run 2/3) and the explicitly-named case in the task brief
   (`code_base_details/`, step 3) — confirmed via real byte-level `md5` comparison in both cases,
   not just an existence check.

Cleaned up afterward: `rm -rf /tmp/task-022-manual-01` (scratch dir only; never touched the real
repo's own filesystem state for any of the scenarios above).

### Self-install into the real repo

As a final, deliberate step — the same expected side effect every prior `recipe-*` installer's
report documents (`recipe-prd-intake`, `fotw-observer`, `tracker-sync`, `recipe-run-phase`,
`recipe-plan-phase`) — the installer was also run for real against this repo itself:

```bash
/Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh \
  --yes --target /Users/vs72964/Projects/gsd-benchmark
```

This staged `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` and added exactly one new
top-level key (`"recipe-bootstrap-knowledge": [".cursor/skills/recipe-bootstrap-knowledge/SKILL.md"]`)
to the shared `.gsd-recipe/ledger.json` — confirmed by re-reading that file afterward that every
pre-existing sibling-task component key (`fotw-observer`, `recipe-prd-intake`, `tracker-sync`,
`recipe-run-phase`, `recipe-plan-phase`) is byte-for-byte unchanged. `.gsd-recipe/ledger.json` is
not one of the four files this task was told to avoid editing, and its merge is a targeted
per-component JSON key addition (the same mechanism every prior self-install already used), not a
wholesale rewrite.

`git status --porcelain` in the real repo, filtered to just this task's own paths, confirms
exactly the expected 5 new paths and nothing else:

```text
?? .cursor/skills/recipe-bootstrap-knowledge/
?? .gsd-recipe/ledger.json
?? .gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh
?? .gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md
?? bench/tests/test-install-recipe-bootstrap-knowledge.sh
```

(`.gsd-recipe/report...` new report file and the rest of the pre-existing untracked/modified tree
from concurrent sibling tasks are additional, expected, and outside this task's scope — see the
full unfiltered `git status --porcelain` in the final response.)

## Files

- `.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh` (new)
- `bench/tests/test-install-recipe-bootstrap-knowledge.sh` (new, 27 assertions)
- `bench/report/recipe-bootstrap-knowledge-integration-report.md` (new, this file)
- `.cursor/skills/recipe-bootstrap-knowledge/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` (self-install side effect, real repo — additive JSON merge only)

**Deliberately NOT edited** (per this task's explicit constraint, sibling tasks concurrently
editing these): `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`. See the snippets below.

## Deviations from the plan

None against the task brief's approved scope. The one interpretive judgment call, called out
explicitly rather than glossed over: the task brief's manual-verification instruction to "actually
create/verify the `.knowledge/` directory skeleton logic works" was satisfied by writing a
standalone script that implements the SKILL.md's own documented step-1 logic verbatim and running
it for real (since the skill itself has no independent CLI entry point outside of an actual Cursor
agent turn invoking it by name) — this is the same interpretive approach `recipe-plan-phase`'s and
`recipe-run-phase`'s own manual-verification sections used for their non-native-call steps.

---

## Snippets for the follow-up integration pass

The four snippets below are sized and placed to apply cleanly once TASK-007/011/021/023 have
landed — each is a straightforward addition alongside the existing 5th-sub-installer
(`recipe-plan-phase`) wiring already in these files, following the identical pattern.

### `install.sh`

**1. New path variable** — add immediately after the existing `RECIPE_PLAN_PHASE_INSTALLER` line:

```bash
RECIPE_PLAN_PHASE_INSTALLER="$SCRIPT_DIR/install-recipe-plan-phase.sh"
RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER="$SCRIPT_DIR/install-recipe-bootstrap-knowledge.sh"
```

**2. Header comment** — extend the component-separation list (in the top-of-file comment block):

```bash
#   - Ledger-tracked: every file this script *directly* creates is recorded
#     in .gsd-recipe/ledger.json under component "install-core" — separate
#     from "fotw-observer"/"tracker-sync"/"recipe-prd-intake"/
#     "recipe-planning-policy"/"recipe-run-phase"/"recipe-plan-phase"/
#     "recipe-bootstrap-knowledge", which the sub-installers/skills track
#     under their own component names.
```

**3. Consent prompt** — in `install()`, update the `read -r -p` line:

```bash
    read -r -p "Install NetApp GSD recipe scaffold (install-core + observer + tracker-sync + recipe-planning-policy + recipe-run-phase + recipe-plan-phase + recipe-bootstrap-knowledge) into $TARGET? [y/N] " reply
```

**4. Composition call** — in `install()`, update the echo and add the new sub-installer call:

```bash
  echo "install.sh: composing sub-installers (observer, tracker-sync, recipe-planning-policy, recipe-run-phase, recipe-plan-phase, recipe-bootstrap-knowledge)..."
  "$OBSERVER_INSTALLER" --yes --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --yes --target "$TARGET"
```

**5. `verify()`** — add immediately after the existing `recipe-plan-phase composed` block:

```bash
  if ledger_has_component "recipe-plan-phase"; then
    echo "    recipe-plan-phase composed — pass"
  else
    echo "    recipe-plan-phase composed — FAIL (recipe-plan-phase ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-bootstrap-knowledge"; then
    echo "    recipe-bootstrap-knowledge composed — pass"
  else
    echo "    recipe-bootstrap-knowledge composed — FAIL (recipe-bootstrap-knowledge ledger component absent)"
    ok=0
  fi
```

**6. `uninstall()`** — add immediately after the existing `RECIPE_PLAN_PHASE_INSTALLER --uninstall` line:

```bash
  "$OBSERVER_INSTALLER" --uninstall --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --uninstall --target "$TARGET"
```

### `test-install.sh`

**1. Fresh-install composition check** — add immediately after the existing
`install.sh composes install-recipe-plan-phase.sh` block:

```bash
[ -f "$TARGET1/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "install.sh composes install-recipe-plan-phase.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "install.sh composes install-recipe-bootstrap-knowledge.sh (skill staged)" "$?"
```

**2. Ledger disjointness check** — extend the existing python block (do not duplicate it — add
the new component to the existing asserts, matching how TASK-017 extended this same block):

```bash
python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/ledger.json'))
assert 'fotw-observer' in d and d['fotw-observer'], d
assert 'tracker-sync' in d and d['tracker-sync'], d
assert 'recipe-planning-policy' in d and d['recipe-planning-policy'], d
assert 'recipe-run-phase' in d and d['recipe-run-phase'], d
assert 'recipe-plan-phase' in d and d['recipe-plan-phase'], d
assert 'recipe-bootstrap-knowledge' in d and d['recipe-bootstrap-knowledge'], d
assert 'install-core' in d and d['install-core'], d
# install.sh must not re-ledger files the sub-installers already track under
# their own component names.
assert set(d['install-core']).isdisjoint(set(d['fotw-observer'])), d
assert set(d['install-core']).isdisjoint(set(d['tracker-sync'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-planning-policy'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-run-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-plan-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-bootstrap-knowledge'])), d
"
check "ledger separates install-core from fotw-observer/tracker-sync/recipe-planning-policy/recipe-run-phase/recipe-plan-phase/recipe-bootstrap-knowledge components (no cross-tracking)" "$?"
```

**3. `--verify` output mention** — add immediately after the existing
`recipe-plan-phase composed — pass` check:

```bash
echo "$VERIFY_OUT1" | grep -q "recipe-plan-phase composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-plan-phase composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-bootstrap-knowledge composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-bootstrap-knowledge composition" "$rc"
```

**4. `--uninstall` cascade check** — add immediately after the existing
`uninstall cascades to install-recipe-plan-phase.sh --uninstall` check:

```bash
[ ! -f "$TARGET3/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "uninstall cascades to install-recipe-plan-phase.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "uninstall cascades to install-recipe-bootstrap-knowledge.sh --uninstall" "$?"
```

Net effect once applied: **+3 new assertions** (fresh-stage check, `--verify` mention check,
`--uninstall` cascade check — the ledger-disjointness assertion is extended in place, not
duplicated, same convention TASK-017's own `install.sh` composition used).

### `BACKLOG.md`

Replace the existing TASK-022 row:

```markdown
| TASK-022 | `recipe-bootstrap-knowledge` | S | 010 | [INSTALL-LLD](lld/INSTALL-LLD.md) |
```

with:

```markdown
| TASK-022 | `recipe-bootstrap-knowledge` | S | 010 | [INSTALL-LLD](lld/INSTALL-LLD.md) — **Built**, standalone installer ahead of full `install.sh` composition (composed into it as a 6th sub-installer via a follow-up snippet — this task ran in parallel with TASK-007/011/021/023 and was constrained from editing `install.sh`/`test-install.sh`/`BACKLOG.md`/`README.md` directly): idempotently scaffolds any missing piece of the OKF-shaped `.knowledge/` skeleton (`index.md`, `log.md`, `architecture/`, `dependency-graph/`, `hot-files/`, `risk-register/` — minimal frontmatter placeholders, additive-only, never overwrites), then calls native `/gsd-map-codebase [--fast]`, `/gsd-graphify build`, and `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly in the same turn (Option-B precedent, same reasoning as TASK-017/024); the ingest step alone gracefully warns-and-skips when the manifest doesn't exist yet, never hard-fails, never fabricates one. `gsd-extract-learnings`/`gsd-capture` wrapping (`OBSERVER-LLD.md`) stays explicitly out of scope. See [bench/report/recipe-bootstrap-knowledge-integration-report.md](../../bench/report/recipe-bootstrap-knowledge-integration-report.md). |
```

### `README.md`

**1. "Built vs spec" table** — add a new row immediately after the existing `recipe-plan-phase`
row:

```markdown
| `recipe-bootstrap-knowledge` skill (TASK-022) | **Built** — narrowed scope: idempotent knowledge bootstrap/refresh wrapper (`.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh`, standalone installer intended to also be composed into `install.sh` as a 6th sub-installer via a follow-up snippet); scaffolds any missing piece of the OKF-shaped `.knowledge/` skeleton (additive-only, never overwrites human/native-command output), then calls native `/gsd-map-codebase [--fast]`, `/gsd-graphify build`, and `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly in the same turn (Option-B precedent); the ingest step alone gracefully warns-and-skips when the manifest is absent. `gsd-extract-learnings`/`gsd-capture` wrapping is explicitly out of scope (different task, `OBSERVER-LLD.md`) — see [bench/report/recipe-bootstrap-knowledge-integration-report.md](../../bench/report/recipe-bootstrap-knowledge-integration-report.md) |
```

**2. Commands table** — add a new row to the **Built** table:

```markdown
| `recipe-bootstrap-knowledge [--fast]` (TASK-022) | Idempotent knowledge bootstrap/refresh wrapper — [.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md](../../.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md) · [report](../../bench/report/recipe-bootstrap-knowledge-integration-report.md) |
```

No corresponding row needs removing from the **Spec** `recipe-*` table — `recipe-bootstrap-
knowledge` was never explicitly named there (the "Populate `.knowledge/` from GSD" section lives
under `INSTALL-LLD.md`'s `recipe-install` umbrella row, not the `RUNTIME-LLD.md` row this table
otherwise tracks), so this is a pure addition, not a move.
