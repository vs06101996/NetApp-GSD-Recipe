# `recipe-run-phase` skill (TASK-024)

**Picked up per approved plan** (`recipe_run_phase_skill`), matching the standalone-installer
precedent already used by `recipe-prd-intake` (TASK-016) and `recipe-planning-policy` (TASK-012)
— built ahead of the full `install.sh` (TASK-010, already built and now composing a fourth
sub-installer). `BACKLOG.md` lists TASK-024 as depending on TASK-003 (`sync-reconcile.sh`, already
built) — this task calls `bench/lib/parse-state.sh` and `bench/lib/sync-ledger.sh` directly rather
than depending on `sync-reconcile.sh` itself, since it only ever needs the same two idempotency
primitives `sync-reconcile.sh` already reuses, not its detection heuristics.

## Scope decisions (confirmed with the user before building)

1. **Option B — direct same-turn native call.** `recipe-run-phase N [--wave W]` calls native
   `gsd-execute-phase N [--wave W]` directly within the same turn. The operator's own act of
   invoking `recipe-run-phase` **is** the manual GSD trigger — this is not an unapproved
   autonomous invocation, unlike `recipe-prd-intake`'s deliberate *non*-invocation of
   `gsd-discuss-phase`.
2. **Prerequisites-table gate is a soft warn-and-confirm**, never a hard block. Missing sections or
   an unfilled table produce a specific warning and a yes/no confirmation prompt; declining stops
   before `gsd-execute-phase` is called, but there is no code path that silently proceeds without
   asking, and no code path that refuses outright.
3. **Tracker posting is skill-to-skill.** `execute_started`/`execute_complete` are emitted by
   invoking the existing `gsd-jira-sync` skill's documented workflow — never by inlining
   `draft-jira-comment.sh`'s draft/post/stamp steps directly inside `recipe-run-phase`.
4. **File list and installer/test shape as scoped** in the plan's §3.3/§4/§8 — a single-file
   Cursor invoke-by-name skill (mirroring `recipe-prd-intake`'s staging shape, not
   `recipe-planning-policy`'s plain top-level `skills/` agent_skills-injection shape, since this
   skill genuinely is invoked by name).

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| DAG pre-req/post-op gating (`RUNTIME-LLD.md` §1.c.2.a/b) | Parked pending TASK-009 (`dag-build.sh`), locked in `DECISIONS.md`: "Tier-1 DAG … dependent tasks (e.g. TASK-017 `recipe-plan-phase`, TASK-024 `recipe-run-phase`) are narrowed to skip DAG pre-req/post-op gating". `recipe-run-phase` never reads or writes `.knowledge/dag/*` — that directory does not exist in this recipe's shipped state. |
| `execute_wave` handling | `gsd-execute-phase --wave W` already owns intra-phase wave orchestration; `recipe-run-phase` only ever forwards `--wave W` verbatim. `bench/runners/sync-reconcile.sh`'s own header comments (lines ~26-27, ~296-311) independently document why `execute_wave` isn't auto-inferred there either — this task doesn't reintroduce that heuristic. |
| Filling/fabricating the Prerequisites table | Strictly the planner's job, gated by the `recipe-planning-policy` skill (TASK-012). This skill's gate is read-only. |
| Inlining `draft-jira-comment.sh`'s draft/post/stamp logic | Decision #3 above — always routed through `gsd-jira-sync`. |
| `recipe-run-phases` (plural, TASK-018) | Separate, not-yet-built multi-phase loop wrapper. Untouched by this task. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-run-phase-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-prd-intake-SKILL.md`'s format) implementing the 8-step workflow: resolve `PLAN.md` → soft planning-policy gate → `depends_on` reminder → resolve issue key → emit `execute_started` (skill-to-skill) → call native `gsd-execute-phase N [--wave W]` → emit `execute_complete` (skill-to-skill) → one-line summary. |
| Installer | `.gsd-recipe/scripts/install-recipe-run-phase.sh` | Standalone installer mirroring `install-recipe-planning-policy.sh`'s structure/functions (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) but staging to `.cursor/skills/recipe-run-phase/SKILL.md` — the invoke-by-name Cursor skill path, not the plain top-level `skills/` agent_skills-injection path `recipe-planning-policy` uses. Component name `"recipe-run-phase"`. Never touches `.gsd-recipe/config.json` or `.planning/config.json`. |
| Composition | `.gsd-recipe/scripts/install.sh` | Added `RECIPE_RUN_PHASE_INSTALLER` path variable; composed into `install()` (`--yes --target` call alongside the other three sub-installers), `uninstall()` (cascade), and `verify()` (`ledger_has_component "recipe-run-phase"` check) — identical pattern to the existing three sub-installer wirings. |
| Fixtures | `bench/tests/fixtures/plan-with-filled-prereqs-table.md`, `bench/tests/fixtures/plan-missing-prereqs-table.md` | Minimal `PLAN.md` fixtures for gate-check testing/manual verification — one with all 7 mandatory sections + a filled Prerequisites table, one deliberately missing 3 sections and the table entirely, both carrying `depends_on`/`touches` frontmatter matching `RUNTIME-LLD.md`'s documented schema. |
| Tests | `bench/tests/test-install-recipe-run-phase.sh` (28 assertions), `bench/tests/test-install.sh` (+3 assertions, 81 → 84) | Standalone installer behavior (fresh install, idempotency, uninstall, self-install, fail-closed, never touches either config.json, staged-content assertions for every documented gate/behavior) and `install.sh`'s composition of the fourth sub-installer (staged/removed/ledgered/verified alongside the other three). |
| Doc updates | `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `docs/netapp-recipe/lld/RUNTIME-LLD.md` | TASK-024 row narrowed-scope note in BACKLOG.md; "Built vs spec" row + Commands table fix (added the previously-missing `recipe-run-phase` singular row, moved it Spec→Built) in README.md; one-line annotations on §2.a and §1.c.2.a/b in RUNTIME-LLD.md. |
| Self-install | `.cursor/skills/recipe-run-phase/SKILL.md` | Live staged copy in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`). |

### Why this installer stages under `.cursor/skills/`, not plain `skills/`

`recipe-planning-policy` (TASK-012) is GSD's own **injected-context** mechanism
(`.planning/config.json`'s `agent_skills.<agentType>` array, resolved relative to project root) —
nothing ever invokes it by name, so it stages to a plain top-level `skills/` directory with no
`<cursor_skill_adapter>` block. `recipe-run-phase` is the opposite case: an operator (or an agent
on the operator's behalf) genuinely types `recipe-run-phase 3` to invoke it, exactly like
`tracker-sync`/`recipe-prd-intake`. So this installer mirrors those two's `.cursor/skills/<name>/SKILL.md`
staging path and their full A/B/C/D adapter format instead.

### Why the installer doesn't need a template-copying loop

`recipe-prd-intake` stages two artifacts (the skill file *and* `.templates/PRD.template.md`, since
the skill's own output depends on a template the operator might customize). `recipe-run-phase` has
no analogous second artifact — it only ever writes tracker comments (via `gsd-jira-sync`, which
owns its own templates) and calls native GSD; there's nothing here for the installer to stage
besides the one skill file. So its installer's structure follows
`install-recipe-planning-policy.sh`'s simpler single-file shape (functions, ledger, flags) even
though its *staging path* follows `recipe-prd-intake`'s Cursor-skill convention rather than
`recipe-planning-policy`'s agent_skills convention.

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-run-phase/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4 | Install never creates `.gsd-recipe/config.json` | PASS |
| 5 | Install never creates `.planning/config.json` | PASS |
| 6-16 | Staged content references `execute_started`/`execute_complete`, the soft Prerequisites-table gate, the non-blocking `depends_on` reminder, the "never fill the table" disclaimer, `gsd-jira-sync` (skill-to-skill), the "do not inline" disclaimer, native `gsd-execute-phase`, DAG-out-of-scope, `execute_wave`-out-of-scope, and fail-open tracker/MCP behavior (11 separate `grep` assertions) | PASS (all 11) |
| 17 | Re-running install does not duplicate ledger rows | PASS |
| 18 | Uninstall removes the staged skill | PASS |
| 19 | Uninstall clears the component's ledger entry | PASS |
| 20 | Uninstall cleans up the now-empty skill directory | PASS |
| 21 | Self-install into a copy of this repo does not error (src==dest collision handled) | PASS |
| 22 | Self-install uninstall does not error | PASS |
| 23 | Self-uninstall preserves the canonical skill template source | PASS |
| 24-27 | `install.sh` declares `RECIPE_RUN_PHASE_INSTALLER`, invokes it with `--yes` in `install()`, cascades to it with `--uninstall`, and checks its ledger component in `verify()` (4 composition assertions) | PASS (all 4) |

`bench/tests/test-install-recipe-run-phase.sh` total: **28 assertions, 0 failed.**

`bench/tests/test-install.sh` composition additions (4th sub-installer, mirroring exactly how
TASK-012's `recipe-planning-policy` installer was added): fresh-install staging check, ledger
cross-tracking disjointness (extended to include `recipe-run-phase`), `--verify` output mention,
and `--uninstall` cascade check — **+3 net new assertions** (one existing ledger-disjointness
assertion body was extended rather than duplicated), taking that file from **81 → 84 assertions,
0 failed**.

**Full `bench/tests/` suite, run file-by-file** (no shared pytest/CI runner exists in this repo —
confirmed `python3 -m pytest bench/tests/ -q` reports "No module named pytest", and no
`bench/tests/*.py` files exist; each `bench/tests/test-*.sh` is invoked standalone, matching every
prior task's own verification method):

| Test file | Before this task | After this task |
|---|---|---|
| `test-draft-github-pr-comment.sh` | 13 passed | 13 passed |
| `test-fotw-observer-nudge.sh` | 10 passed | 10 passed |
| `test-install-observer.sh` | 17 passed | 17 passed |
| `test-install-recipe-planning-policy.sh` | 16 passed | 16 passed |
| `test-install-recipe-prd-intake.sh` | 17 passed | 17 passed |
| `test-install-recipe-run-phase.sh` (new) | — | **28 passed** |
| `test-install-tracker-sync.sh` | 16 passed | 16 passed |
| `test-install.sh` | 81 passed | **84 passed** |
| `test-observer-lib.sh` | 12 passed | 12 passed |
| `test-observer-tick-loop.sh` | 6 passed | 6 passed |
| `test-parse-state.sh` | 20 passed | 20 passed |
| `test-sync-drain-queue.sh` | 18 passed | 18 passed |
| `test-sync-ledger.sh` | 10 passed | 10 passed |
| `test-sync-reconcile.sh` | 14 passed | 14 passed |
| `test-tracker-sync-config.sh` | 10 passed | 10 passed |
| **Total** | **260 assertions across 14 files** | **291 assertions across 15 files** |

**Zero regressions** — every pre-existing test file's assertion count is byte-for-byte unchanged
except `test-install.sh` (which gained exactly the 3 composition assertions this task added), and
every file, old and new, reports 0 failures on this run.

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/recipe-run-phase-manual-01` (never the real
`gsd-benchmark` repo — every command below used an absolute `--target`/`--state`/`REPO_ROOT`
pointing at the scratch path, per the task's safety constraint; no `cd` was relied upon to survive
across separate tool calls). Confirmed no side effects leaked into the real repo afterward: `git
-C /Users/vs72964/Projects/gsd-benchmark status --porcelain` and `... config --list --local` show
only the intended files for this task plus the pre-existing untracked tree from prior tasks — no
stray `.knowledge/`, no stray git config.

Setup: `git init` the scratch repo; ran the real
`.gsd-recipe/scripts/install-recipe-run-phase.sh --yes --target /tmp/recipe-run-phase-manual-01`
(this is a real installer execution, not simulated — it staged a real
`.cursor/skills/recipe-run-phase/SKILL.md` in the scratch repo and recorded 1 ledger row there,
verified after the fact); seeded a scratch `.planning/STATE.md` (phase 3 linked to `MAN-103`,
phase 4 deliberately **not** linked); seeded two `PLAN.md` fixtures under
`.planning/phases/03-payments/` (compliant — copy of
`plan-with-filled-prereqs-table.md`) and `.planning/phases/04-notifications/` (non-compliant —
copy of `plan-missing-prereqs-table.md`), named so they satisfy the documented glob pattern (see
note below).

I then actually followed the staged skill's own instructions turn-by-turn against these fixtures,
as an operator invoking `recipe-run-phase 3` / `recipe-run-phase 4` / `recipe-run-phase 5` would,
executing every step that has no MCP/native-GSD dependency for real, and tracing (not executing)
every step that would call `gsd-execute-phase` or post to Jira:

| Step | Phase 5 (no PLAN.md) | Phase 4 (non-compliant, unlinked) | Phase 3 (compliant, linked) |
|---|---|---|---|
| 1. Resolve `PLAN.md` (real `Glob`, both the primary and fallback pattern) | **0 files found either pattern** → correct stop message: *"No PLAN.md found for phase 5 — run `gsd-plan-phase 5` first."* Workflow halts here for real; steps 2-8 never run — traced only as "would not run." | 1 file found: `phase-04-review-PLAN.md` | 1 file found: `phase-03-review-PLAN.md` |
| 2. Planning-policy gate (real `Read` + manual section/table check against `PLANNING-POLICY.md`) | n/a | **Non-compliant**: 3 of 7 sections missing (Performance considerations, Expected review concerns, Learning extraction opportunities) and the Prerequisites table is absent entirely. Traced warning: *"Phase 4's PLAN.md is missing 3 of 7 mandatory sections and has no Prerequisites table at all — continue anyway? [y/N]"* — a real invocation would stop here on "N"; this trace assumes an operator answers "y" so the remaining steps can also be exercised. | **Compliant**: all 7 sections present, Prerequisites table present with 2 filled data rows, no blank/placeholder cells. No prompt shown; noted silently for the final summary. |
| 3. `depends_on` reminder (hand-parsed frontmatter, real `Read`) | n/a | Frontmatter has `depends_on: [03-payments]` → printed as an informational, non-blocking reminder. Never touched `.knowledge/dag/*` (doesn't exist in this scratch repo). | Frontmatter has `depends_on: [01-auth, 02-schema]` → printed the same way. |
| 4. Resolve issue key (real `bench/lib/parse-state.sh resolve-issue execute_started --phase N --state <scratch STATE.md>`) | n/a | **Real execution, exit 1**: `ERROR: unresolved phase-routed event: phase_id '4' ... has no matching row in '## Phase tasks'`. Per the skill's own step 4: warn and continue straight to step 6 — does **not** block. | **Real execution, exit 0**: resolves to `MAN-103`. |
| 5. Emit `execute_started` | n/a — skipped per step 4 (no issue key) | **Skipped** (no issue key resolved) | Computed the real idempotency key via `bench/lib/sync-ledger.sh key execute_started MAN-103 --phase 3` → `gsd-recipe:execute_started:phase=3:issue=MAN-103`; real `sync-ledger.sh has` check against a scratch ledger path returned exit 1 (not found — no prior post). **Traced, not executed** from here: would invoke the `gsd-jira-sync` skill's documented single-event workflow (`gsd-jira-sync execute_started MAN-103 --phase 3`), which owns drafting/posting/stamping — no real Jira post or MCP call was made. |
| 6. Call native `gsd-execute-phase N [--wave W]` | n/a | **Traced, not executed**: would call `gsd-execute-phase 4` directly, no DAG check, no wave-handling logic added. | **Traced, not executed**: would call `gsd-execute-phase 3` directly. |
| 7. Emit `execute_complete` | n/a | **Traced, not executed**: same skill-to-skill pattern as step 5, once (traced) `gsd-execute-phase` returns. | **Traced, not executed**: same. |
| 8. Summary | *"Phase 5: no PLAN.md — stopped before any other step."* | *(assuming operator confirmed step 2)* *"Phase 4, issue: none linked, gate: warned-and-confirmed, execute_started: skipped-no-issue, execute_complete: skipped-no-issue."* | *"Phase 3, issue: MAN-103, gate: compliant, execute_started: (traced) posted, execute_complete: (traced) posted."* |

**What was truly exercised vs. traced:**

- **Truly executed** (real tool calls, real scripts, real files, on the scratch repo only): the
  installer itself (staged a real file, wrote a real ledger row); both `Glob` resolution attempts
  for all three phases (including the genuine 0-result case for phase 5); both `Read` calls
  against the two `PLAN.md` fixtures; the manual section/table compliance check against those real
  contents; the `depends_on` frontmatter reads; `parse-state.sh resolve-issue` for both phase 3
  (success) and phase 4 (real failure, real error message) against a real scratch `STATE.md`;
  `sync-ledger.sh key` and `sync-ledger.sh has` for phase 3's `execute_started` key against a real
  (empty) scratch ledger path.
- **Traced/reasoned about, not executed**: every step that would call `gsd-execute-phase` (native
  GSD, would actually start real phase execution against a scratch repo with no real codebase to
  build) or invoke `gsd-jira-sync` (would attempt a real Atlassian MCP call) — per the task's
  explicit instruction not to trigger these for real during this dry verification, and per this
  environment's inability to spawn a nested Cursor agent turn to actually run the skill end-to-end
  as an operator would. The soft-gate "operator confirms" branch in step 2 for phase 4 was also
  reasoned through rather than answered by a real human at a real prompt (there is no real
  operator in this dry run) — the trace assumes "yes" specifically so the downstream steps could
  still be walked through for phase 4.

**Confirmed outcomes for the 4 required scenario checks:**

1. **Missing `PLAN.md` → correct stop message.** Confirmed for real (phase 5): both glob patterns
   return zero files; the documented stop message is the correct, only next action.
2. **Missing prereqs table → warns and asks for confirmation (soft gate, not hard block).**
   Confirmed for real content (phase 4's fixture genuinely lacks 3 sections and the whole table);
   the gate is soft by construction — the skill's own §C.2/§D explicitly forbid a hard block and
   explicitly forbid fabricating the table, and there is no code/instruction path in the staged
   skill that skips the confirmation prompt when non-compliant.
3. **`depends_on` prints as informational only.** Confirmed for both phase 3 and phase 4's real
   frontmatter — the reminder step exists independently of, and after, the compliance gate, and
   the skill's own instructions (§C.3, §D) explicitly disclaim ever reading/writing
   `.knowledge/dag/*` or blocking on this reminder.
2b. **Unresolved issue key → warns and continues, does not block.** Confirmed for real (phase 4):
   `parse-state.sh resolve-issue` genuinely exits 1 with a real, specific error; the skill's own
   step 4 instructions route that failure to "warn and skip straight to step 6," never to a stop.

## Note on the glob pattern's real-world naming fit

The plan explicitly instructs mirroring `draft-jira-comment.sh`'s `PLAN.md` glob shape verbatim
(`*-{NN}-*-PLAN.md`), which this task does. During manual verification, constructing fixture
filenames that actually satisfy that pattern surfaced that it requires the phase number to be
followed by **additional** content before a trailing `-PLAN.md` (e.g. `phase-03-review-PLAN.md`
matches; a bare `03-payments-PLAN.md` or GSD's own native `{phase}-{plan}-PLAN.md` two-segment
convention, e.g. `03-01-PLAN.md`, does not, confirmed via direct `fnmatch` testing). This is a
pre-existing characteristic of the precedent this task was told to mirror exactly, not a defect
introduced here, and fixing/relaxing the glob is out of this task's approved scope — flagged here
for visibility rather than silently worked around. The scratch fixtures above were named to
satisfy the documented pattern so the downstream Read/gate logic could still be exercised for
real.

## Files

- `.gsd-recipe/templates/recipe-run-phase-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-run-phase.sh` (new)
- `.gsd-recipe/scripts/install.sh` (edited — fourth sub-installer composed)
- `bench/tests/test-install-recipe-run-phase.sh` (new, 28 assertions)
- `bench/tests/test-install.sh` (edited — 3 new assertions, 81 → 84)
- `bench/tests/fixtures/plan-with-filled-prereqs-table.md` (new)
- `bench/tests/fixtures/plan-missing-prereqs-table.md` (new)
- `docs/netapp-recipe/BACKLOG.md` (edited — TASK-024 narrowed-scope note)
- `docs/netapp-recipe/README.md` (edited — TASK-024 row in "Built vs spec" + Commands table fix)
- `docs/netapp-recipe/lld/RUNTIME-LLD.md` (edited — §2.a and §1.c.2.a/b annotations)
- `.cursor/skills/recipe-run-phase/SKILL.md` (self-install side effect, real repo)
