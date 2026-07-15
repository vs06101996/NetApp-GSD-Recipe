# `recipe-plan-phase` skill (TASK-017)

**Picked up per approved plan** (`recipe_plan_phase_skill`), matching the standalone-installer
precedent already used by `recipe-prd-intake` (TASK-016), `recipe-planning-policy` (TASK-012), and
`recipe-run-phase` (TASK-024) — built ahead of the full `install.sh` (TASK-010, already built and
now composing a fifth sub-installer). `BACKLOG.md` originally listed TASK-017 as depending on
TASK-009 (`dag-build.sh`) — per `DECISIONS.md`'s locked decision, Tier-1 DAG is **not required for
v1** and TASK-017 is explicitly named there as narrowed to skip DAG pre-req/post-op gating rather
than blocking on TASK-009. This task proceeds now on that narrowed basis, the same way TASK-024
did for its own `depends_on` reminder.

## Scope decisions (confirmed with the user before building)

1. **Option B — direct same-turn native call.** `recipe-plan-phase N` calls native
   `gsd-plan-phase N` directly within the same turn. The operator's own act of invoking
   `recipe-plan-phase` **is** the manual GSD trigger — same precedent as `recipe-run-phase`'s
   direct call to `gsd-execute-phase`, not `recipe-prd-intake`'s deliberate *non*-invocation of
   `gsd-discuss-phase`.
2. **Post-hoc compliance check is a soft warn-and-confirm.** Since the resulting `PLAN.md` doesn't
   exist until *after* `gsd-plan-phase` returns, this task's compliance gate is necessarily
   post-hoc — it checks the 7 mandatory sections + a filled Prerequisites table once `PLAN.md` is
   resolved, and a non-compliant result gates the tracker stamp (step 7), not a further native
   call (there isn't one left to gate at that point). Never a hard block, never fills/fabricates.
3. **Tracker posting is skill-to-skill.** `plan_complete`/`plan_revised` are emitted by invoking
   the existing `gsd-jira-sync` skill's documented workflow — never by inlining
   `draft-jira-comment.sh`'s draft/post/stamp steps directly inside `recipe-plan-phase`.
4. **TASK-009 dependency is narrowable-now.** DAG frontmatter (`depends_on`/`touches`) handling is
   print-only informational, never reads/writes `.knowledge/dag/*`. No topo-sort, no cycle
   detection, no eligibility gating.
5. **File list and installer/test shape as scoped** in the plan's §3/§4/§8 — a single-file Cursor
   invoke-by-name skill (mirroring `recipe-run-phase`'s staging shape), reusing the existing
   `plan-with-filled-prereqs-table.md`/`plan-missing-prereqs-table.md` fixtures rather than
   creating new ones.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| DAG topo-sort/cycle detection (`RUNTIME-LLD.md` §1.c.2.c) | Tier-1 DAG work, parked pending TASK-009 (`dag-build.sh`), locked in `DECISIONS.md`: "…dependent tasks (e.g. TASK-017 `recipe-plan-phase`, TASK-024 `recipe-run-phase`) are narrowed to skip DAG pre-req/post-op gating". `recipe-plan-phase` never reads or writes `.knowledge/dag/*` — that directory does not exist in this recipe's shipped state. |
| DAG pre-req/post-op gating (`RUNTIME-LLD.md` §1.c.2.a/b) | Same parked status as above. |
| Filling/fabricating the Prerequisites table | Strictly the planner's job, gated by the `recipe-planning-policy` skill (TASK-012). This skill's gate is read-only. |
| Inlining `draft-jira-comment.sh`'s draft/post/stamp logic | Decision #3 above — always routed through `gsd-jira-sync`. |
| A `plan_started` stamp | `bench/recipe/trackers/jira-events.json` only defines `plan_complete`/`plan_revised` for the planning milestone — confirmed no started/complete pairing exists for planning (unlike `recipe-run-phase`'s `execute_started`/`execute_complete`). Not invented here. |
| Spike triggering (`gsd-spike`, `RUNTIME-LLD.md` §1.c.1) | Stays the operator's own separate call before planning, never triggered by this skill — same precedent as `recipe-run-phase` not auto-triggering anything upstream of its own call. |
| `recipe-run-phases`/`recipe-run-phase` (TASK-018/024) | Execute-side siblings, untouched by this task. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-plan-phase-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-run-phase-SKILL.md`'s format) implementing the 8-step workflow: determine first-plan vs re-plan (informational glob) → resolve issue key → call native `gsd-plan-phase N` → re-resolve `PLAN.md` (stop if still absent) → soft post-hoc compliance gate → `depends_on`/`touches` reminder → emit `plan_complete`/`plan_revised` (skill-to-skill, idempotent) → one-line summary. |
| Installer | `.gsd-recipe/scripts/install-recipe-plan-phase.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s structure/functions (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-plan-phase/SKILL.md` — the invoke-by-name Cursor skill path. Component name `"recipe-plan-phase"`. Never touches `.gsd-recipe/config.json` or `.planning/config.json`. |
| Composition | `.gsd-recipe/scripts/install.sh` | Added `RECIPE_PLAN_PHASE_INSTALLER` path variable; composed into `install()` (`--yes --target` call alongside the other four sub-installers), `uninstall()` (cascade), and `verify()` (`ledger_has_component "recipe-plan-phase"` check) — identical pattern to the existing four sub-installer wirings. Updated the install-core ledger-separation header comment and the operator-facing consent/echo strings to name the fifth sub-installer. |
| Fixtures reused | `bench/tests/fixtures/plan-with-filled-prereqs-table.md`, `bench/tests/fixtures/plan-missing-prereqs-table.md` | Not modified — reused as-is for this task's compliance-check and re-plan scenarios (both already carry `depends_on`/`touches` frontmatter matching `RUNTIME-LLD.md`'s schema). The first-plan scenario needs no fixture (absence of a `PLAN.md` is the test condition itself). |
| Tests | `bench/tests/test-install-recipe-plan-phase.sh` (28 assertions), `bench/tests/test-install.sh` (+3 assertions, 84 → 87) | Standalone installer behavior (fresh install, idempotency, uninstall, self-install, fail-closed, never touches either config.json, staged-content assertions for every documented gate/behavior) and `install.sh`'s composition of the fifth sub-installer (staged/removed/ledgered/verified alongside the other four). |
| Doc updates | `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `docs/netapp-recipe/lld/RUNTIME-LLD.md` | TASK-017 row narrowed-scope note in `BACKLOG.md`; "Built vs spec" row + Commands table move (`recipe-plan-phase` moved from the Spec `recipe-*` row into a Built row, alongside `recipe-run-phase`) in `README.md`; one-line annotations on §1.c and §1.c.2.a/b in `RUNTIME-LLD.md`. |
| Self-install | `.cursor/skills/recipe-plan-phase/SKILL.md` | Live staged copy in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`, `recipe-run-phase`). |

### Why this installer stages under `.cursor/skills/`, not plain `skills/`

Same rationale as `recipe-run-phase`'s report: `recipe-planning-policy` (TASK-012) is GSD's own
**injected-context** mechanism (`.planning/config.json`'s `agent_skills.<agentType>` array) —
nothing ever invokes it by name, so it stages to a plain top-level `skills/` directory with no
`<cursor_skill_adapter>` block. `recipe-plan-phase` is the opposite case: an operator genuinely
types `recipe-plan-phase 3` to invoke it, exactly like `recipe-run-phase`/`tracker-sync`/
`recipe-prd-intake`. So this installer mirrors those skills' `.cursor/skills/<name>/SKILL.md`
staging path and full A/B/C/D adapter format.

### Why the compliance check is post-hoc here but pre-hoc in `recipe-run-phase`

`recipe-run-phase`'s planning-policy gate checks an *already-existing* `PLAN.md` before deciding
whether to call `gsd-execute-phase` at all — a genuine pre-flight check. `recipe-plan-phase` has no
equivalent pre-flight moment: for a first-plan invocation there is no `PLAN.md` yet to check before
`gsd-plan-phase` runs, and for a re-plan invocation the entire point of calling `gsd-plan-phase`
again is to produce a *new* `PLAN.md`. So this skill's compliance check necessarily runs after step
3 (the native call), gating the step-7 tracker stamp instead of the native call itself — there is
no further native call left at that point to gate. This is decision #2, and it's the one structural
difference from `recipe-run-phase`'s otherwise-parallel workflow shape.

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-plan-phase/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4 | Install never creates `.gsd-recipe/config.json` | PASS |
| 5 | Install never creates `.planning/config.json` | PASS |
| 6-16 | Staged content references `plan_complete`, `plan_revised`, native `gsd-plan-phase`, the soft warn-and-confirm compliance gate, the "never fill" disclaimer, the non-blocking `depends_on` reminder, the non-blocking `touches` reminder, `gsd-jira-sync` (skill-to-skill), the "do not inline" disclaimer, DAG-out-of-scope, and fail-open/warn-and-continue behavior, and first-plan-vs-re-plan routing language (12 separate `grep` assertions) | PASS (all 12) |
| 17 | Re-running install does not duplicate ledger rows | PASS |
| 18 | Uninstall removes the staged skill | PASS |
| 19 | Uninstall clears the component's ledger entry | PASS |
| 20 | Uninstall cleans up the now-empty skill directory | PASS |
| 21 | Self-install into a copy of this repo does not error (src==dest collision handled) | PASS |
| 22 | Self-install uninstall does not error | PASS |
| 23 | Self-uninstall preserves the canonical skill template source | PASS |
| 24-27 | `install.sh` declares `RECIPE_PLAN_PHASE_INSTALLER`, invokes it with `--yes` in `install()`, cascades to it with `--uninstall`, and checks its ledger component in `verify()` (4 composition assertions) | PASS (all 4) |

`bench/tests/test-install-recipe-plan-phase.sh` total: **28 assertions, 0 failed.**

`bench/tests/test-install.sh` composition additions (5th sub-installer, mirroring exactly how
TASK-024's `recipe-run-phase` installer was added): fresh-install staging check, ledger
cross-tracking disjointness (extended to include `recipe-plan-phase`), `--verify` output mention,
and `--uninstall` cascade check — **+3 net new assertions** (one existing ledger-disjointness
assertion body was extended rather than duplicated, same pattern TASK-024 used), taking that file
from **84 → 87 assertions, 0 failed**.

**Full `bench/tests/` suite, run file-by-file** (no shared pytest/CI runner exists in this repo —
each `bench/tests/test-*.sh` is invoked standalone, matching every prior task's own verification
method):

| Test file | Before this task | After this task |
|---|---|---|
| `test-draft-github-pr-comment.sh` | 13 passed | 13 passed |
| `test-fotw-observer-nudge.sh` | 10 passed | 10 passed |
| `test-install-observer.sh` | 17 passed | 17 passed |
| `test-install-recipe-planning-policy.sh` | 16 passed | 16 passed |
| `test-install-recipe-prd-intake.sh` | 17 passed | 17 passed |
| `test-install-recipe-run-phase.sh` | 28 passed | 28 passed |
| `test-install-recipe-plan-phase.sh` (new) | — | **28 passed** |
| `test-install-tracker-sync.sh` | 16 passed | 16 passed |
| `test-install.sh` | 84 passed | **87 passed** |
| `test-observer-lib.sh` | 12 passed | 12 passed |
| `test-observer-tick-loop.sh` | 6 passed | 6 passed |
| `test-parse-state.sh` | 20 passed | 20 passed |
| `test-sync-drain-queue.sh` | 18 passed | 18 passed |
| `test-sync-ledger.sh` | 10 passed | 10 passed |
| `test-sync-reconcile.sh` | 14 passed | 14 passed |
| `test-tracker-sync-config.sh` | 10 passed | 10 passed |
| **Total** | **291 assertions across 15 files** | **322 assertions across 16 files** |

**Zero regressions** — every pre-existing test file's assertion count is byte-for-byte unchanged
except `test-install.sh` (which gained exactly the 3 composition assertions this task added), and
every file, old and new, reports 0 failures on this run. The 291-assertion/15-file baseline was
confirmed by re-running the full suite before making any of this task's changes, matching the
number reported in `bench/report/recipe-run-phase-integration-report.md`.

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/recipe-plan-phase-manual-01` (never the real
`gsd-benchmark` repo — every command below used an absolute `--target`/`--state`/`REPO_ROOT`
pointing at the scratch path, per the task's safety constraint; no `cd` was relied upon to survive
across separate tool calls). Confirmed no side effects leaked into the real repo afterward: `git -C
/Users/vs72964/Projects/gsd-benchmark status --porcelain` shows only this task's intended new/
modified files plus the real (deliberate) self-install of `.cursor/skills/recipe-plan-phase/
SKILL.md` and the pre-existing untracked/modified tree from prior tasks — no stray `.knowledge/`,
no stray git config, nothing unaccounted for.

Setup: `git init` the scratch repo; ran the real
`.gsd-recipe/scripts/install-recipe-plan-phase.sh --yes --target /tmp/recipe-plan-phase-manual-01`
(a real installer execution, not simulated — it staged a real `.cursor/skills/recipe-plan-phase/
SKILL.md` in the scratch repo and recorded 1 ledger row there); seeded a scratch `.planning/
STATE.md` (phase 3 linked to `MAN-103`, phase 5 linked to `MAN-105`, phase 4 deliberately **not**
linked); seeded two `PLAN.md` fixtures under `.planning/phases/03-payments/` (compliant — copy of
`plan-with-filled-prereqs-table.md`) and `.planning/phases/04-notifications/` (non-compliant —
copy of `plan-missing-prereqs-table.md`), named to satisfy the documented glob pattern (see note
below, same naming quirk `recipe-run-phase`'s manual verification already surfaced); phase 5 has
**no** `PLAN.md` at all (the first-plan scenario's own test condition).

I then actually followed the staged skill's own instructions turn-by-turn against these fixtures,
as an operator invoking `recipe-plan-phase 5` / `recipe-plan-phase 4` / `recipe-plan-phase 3` would,
executing every step that has no native-GSD/MCP dependency for real, and tracing (not executing)
every step that would call `gsd-plan-phase` or post to Jira:

| Step | Phase 5 (first-plan, linked) | Phase 4 (re-plan, non-compliant, unlinked) | Phase 3 (re-plan, compliant, linked) |
|---|---|---|---|
| 1. Determine first-plan vs re-plan (real `Glob`, both the primary and fallback pattern) | **0 files found either pattern** → real, correct determination: **first-plan** (routes to `plan_complete` later). | 1 file found: `phase-04-review-PLAN.md` → **re-plan** (routes to `plan_revised`). | 1 file found: `phase-03-review-PLAN.md` → **re-plan** (routes to `plan_revised`). |
| 2. Resolve issue key (real `bench/lib/parse-state.sh resolve-issue plan_complete --phase N --state <scratch STATE.md>`) | **Real execution, exit 0**: resolves to `MAN-105`. | **Real execution, exit 1**: `ERROR: unresolved phase-routed event: phase_id '4' ... has no matching row in '## Phase tasks'`. Per the skill's own step 2: warn and continue straight to step 3 — does **not** block. | **Real execution, exit 0**: resolves to `MAN-103`. |
| 3. Call native `gsd-plan-phase N` | **Traced, not executed**: would call `gsd-plan-phase 5` directly, no spike handling added. | **Traced, not executed**: would call `gsd-plan-phase 4` directly. | **Traced, not executed**: would call `gsd-plan-phase 3` directly. |
| 4. Re-resolve `PLAN.md` (same glob as step 1) | Since step 3 is only traced, this cannot genuinely re-run post-call — **traced**: if the real call produced a plan, this would find it and continue to step 5; if it didn't (aborted/declined/errored), the skill would stop here and report plainly. | **Traced** analogous to phase 5: assumes the re-plan call regenerated `phase-04-review-PLAN.md` in place, so downstream steps could still be walked through. | **Traced** analogous to phase 5/4. |
| 5. Post-hoc compliance gate (real `Read` + manual section/table check against `PLANNING-POLICY.md`, applied to the existing fixture content as a stand-in for "the plan gsd-plan-phase would have just produced") | n/a (no `PLAN.md` exists to check for real in this trace) | **Non-compliant**: 3 of 7 sections missing (Performance considerations, Expected review concerns, Learning extraction opportunities) and the Prerequisites table is absent entirely — confirmed by real `Read` of the actual fixture content. Traced warning: *"Phase 4's PLAN.md is missing 3 of 7 mandatory sections and has no Prerequisites table at all — continue anyway before syncing the tracker stamp? [y/N]"* — this trace assumes an operator answers "y" so the remaining steps can also be exercised. | **Compliant**: all 7 sections present, Prerequisites table present with 2 filled data rows, no blank/placeholder cells — confirmed by real `Read` of the actual fixture content. No prompt shown; noted silently for the final summary. |
| 6. `depends_on`/`touches` reminder (hand-parsed frontmatter, real `Read`) | n/a (no `PLAN.md`) | Frontmatter has `depends_on: [03-payments]` and `touches: [src/notifications/**]` → printed as an informational, non-blocking reminder. Never touched `.knowledge/dag/*` (doesn't exist in this scratch repo). | Frontmatter has `depends_on: [01-auth, 02-schema]` and `touches: [src/payments/**, db/migrations/003_*]` → printed the same way. |
| 7. Emit `plan_complete`/`plan_revised` | **Real execution** of the idempotency mechanics: computed the real key via `bench/lib/sync-ledger.sh key plan_complete MAN-105 --phase 5` → `gsd-recipe:plan_complete:phase=5:issue=MAN-105`; real `sync-ledger.sh has` check against the scratch ledger path returned exit 1 (not found — no prior post). **Traced, not executed** from here: would invoke `gsd-jira-sync plan_complete MAN-105 --phase 5`. | **Skipped** (no issue key resolved in step 2 — per the skill's own instructions, step 7 never runs without a resolved issue key, regardless of the step-5 gate outcome). | **Real execution**: computed the real key via `bench/lib/sync-ledger.sh key plan_revised MAN-103 --phase 3` → `gsd-recipe:plan_revised:phase=3:issue=MAN-103`; real `sync-ledger.sh has` check returned exit 1 (not found). **Traced, not executed** from here: would invoke `gsd-jira-sync plan_revised MAN-103 --phase 3`. |
| 8. Summary | *"Phase 5, issue: MAN-105, first-plan, gate: n/a (traced), plan_complete: (traced) posted."* | *(assuming operator confirmed step 5)* *"Phase 4, issue: none linked, re-plan, gate: warned-and-confirmed, plan_revised: skipped-no-issue."* | *"Phase 3, issue: MAN-103, re-plan, gate: compliant, plan_revised: (traced) posted."* |

**What was truly exercised vs. traced:**

- **Truly executed** (real tool calls, real scripts, real files, on the scratch repo only): the
  installer itself (staged a real file, wrote a real ledger row); real `Glob` resolution for all
  three phases (including the genuine 0-result case for phase 5 and the genuine 1-result case for
  phases 3 and 4, both patterns each time); real `Read` of both `PLAN.md` fixtures and manual
  section/table compliance checks against their actual content; real `Read` of both fixtures'
  `depends_on`/`touches` frontmatter; `parse-state.sh resolve-issue` for phase 5 (success), phase 3
  (success), and phase 4 (real failure, real error message) against a real scratch `STATE.md`;
  `sync-ledger.sh key` and `sync-ledger.sh has` for phase 5's `plan_complete` key and phase 3's
  `plan_revised` key against a real (empty) scratch ledger path.
- **Traced/reasoned about, not executed**: every step that would call `gsd-plan-phase` (native
  GSD, would actually start a real planning session against a scratch repo with no real codebase
  to plan) or invoke `gsd-jira-sync` (would attempt a real Atlassian MCP call) — per the task's
  explicit instruction not to trigger these for real during this dry verification, and per this
  environment's inability to spawn a nested Cursor agent turn to actually run the skill end-to-end
  as an operator would. Because step 3 (the native call) is only traced, step 4 (re-resolving
  `PLAN.md` after that call) and the compliance check in step 5 could not genuinely re-observe a
  freshly-generated plan — the trace uses the pre-seeded fixture content as a stand-in for "the
  plan `gsd-plan-phase` would have just produced," which is why step 5's checks are marked "real
  `Read` + manual check" against that stand-in content rather than fully real end-to-end. The
  soft-gate "operator confirms" branch for phase 4 was also reasoned through rather than answered
  by a real human at a real prompt (there is no real operator in this dry run) — the trace assumes
  "yes" specifically so the downstream steps could still be walked through for phase 4.

**Confirmed outcomes for the 3 required scenario checks:**

1. **First-plan with a linked issue.** Confirmed for real (phase 5): both glob patterns
   genuinely return zero files (correct first-plan determination), `parse-state.sh resolve-issue`
   genuinely resolves `MAN-105`, and the `plan_complete` idempotency key/has-check genuinely runs
   against a real (empty) scratch ledger, returning "not found" as expected for a phase that has
   never been synced before.
2. **Re-plan, compliant, linked issue.** Confirmed for real (phase 3): the glob genuinely returns
   1 result (correct re-plan determination), the fixture's real content genuinely satisfies all 7
   sections + a filled Prerequisites table (no warning fires — the skill's own instructions
   explicitly gate the warning on a genuine non-compliance finding, and none exists here), issue
   resolution genuinely succeeds (`MAN-103`), and the `plan_revised` idempotency key/has-check
   genuinely runs against the real scratch ledger.
3. **Re-plan, non-compliant, unlinked issue.** Confirmed for real (phase 4): the glob genuinely
   returns 1 result (re-plan), the fixture's real content genuinely lacks 3 of 7 sections and the
   entire Prerequisites table (the compliance gate is soft by construction — the skill's own
   §C.5/§D explicitly forbid a hard block and explicitly forbid fabricating the table, and there is
   no instruction path in the staged skill that skips the confirmation prompt when non-compliant),
   and `parse-state.sh resolve-issue` genuinely exits 1 with a real, specific error — the skill's
   own step 2 instructions route that failure to "warn and continue straight to step 3," never to a
   stop, and step 7 is correctly skipped entirely (`skipped-no-issue`) once no issue key ever
   resolved, independent of whatever the step-5 gate outcome was.

## Note on the glob pattern's real-world naming fit

Same pre-existing characteristic `recipe-run-phase`'s manual verification already surfaced: the
plan explicitly instructs mirroring `draft-jira-comment.sh`'s `PLAN.md` glob shape verbatim
(`*-{NN}-*-PLAN.md`), which this task does. Fixture filenames must place additional content
between the phase number and `-PLAN.md` (e.g. `phase-03-review-PLAN.md` matches; a bare
`03-payments-PLAN.md` or GSD's own native `{phase}-{plan}-PLAN.md` two-segment convention, e.g.
`03-01-PLAN.md`, does not). Not a defect introduced here — inherited verbatim from the precedent
this task was told to mirror, and fixing/relaxing the glob is out of this task's approved scope.

## Files

- `.gsd-recipe/templates/recipe-plan-phase-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-plan-phase.sh` (new)
- `.gsd-recipe/scripts/install.sh` (edited — fifth sub-installer composed)
- `bench/tests/test-install-recipe-plan-phase.sh` (new, 28 assertions)
- `bench/tests/test-install.sh` (edited — 3 new assertions, 84 → 87)
- `docs/netapp-recipe/BACKLOG.md` (edited — TASK-017 narrowed-scope note)
- `docs/netapp-recipe/README.md` (edited — TASK-017 row in "Built vs spec" + Commands table move)
- `docs/netapp-recipe/lld/RUNTIME-LLD.md` (edited — §1.c and §1.c.2.a/b annotations)
- `.cursor/skills/recipe-plan-phase/SKILL.md` (self-install side effect, real repo)

## Deviations from the plan

None. The plan's approved decisions, file list, and installer/test shape were followed exactly as
scoped; the only interpretive judgment call was in the manual verification trace (using the
pre-seeded fixture content as a stand-in for "the plan `gsd-plan-phase` would have just produced"
in step 4/5, since the native call itself is out of scope to actually run) — this is explicitly
called out above rather than silently glossed over.
