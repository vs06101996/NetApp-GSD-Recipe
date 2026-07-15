# `recipe-run-phases` skill (TASK-018)

**All scope decisions below were confirmed with the operator this session before any implementation
work started** (see the task prompt's own "LOCKED DESIGN DECISIONS" block) — none were re-derived
or independently chosen during this task. This matches the standalone-installer precedent already
used by `recipe-prd-intake` (TASK-016), `recipe-planning-policy` (TASK-012), `recipe-run-phase`
(TASK-024), and `recipe-plan-phase` (TASK-017) — built ahead of the full `install.sh` (TASK-010).
`BACKLOG.md` lists TASK-018 as depending on TASK-017 and TASK-024, both already built and staged;
this task read both as its structural + idempotency-mechanics template, per the task prompt's own
instruction, and invokes them **by name, skill-to-skill**, never touching their source files.

## Scope decisions (operator-approved this session, implemented exactly as locked)

1. **Sequential ascending phase-number loop, not a DAG topo-sort.** `recipe-run-phases <start>
   <end>` walks `[start, end]` in plain ascending order — DAG-derived ordering stays parked
   pending TASK-009, same precedent TASK-017/024 already established for themselves. This is
   Option-B same-turn orchestration: the skill invokes `recipe-plan-phase`/`recipe-run-phase`
   **by name** (skill-to-skill), the same way `recipe-run-phase` already invokes `gsd-jira-sync` —
   never raw native `gsd-plan-phase`/`gsd-execute-phase` directly, and never `gsd-autonomous`.
2. **Per-phase plan-exists check before invoking `recipe-plan-phase`.** For each phase `N`, glob for
   `PLAN.md` using the exact same shape `recipe-plan-phase-SKILL.md` already documents for its own
   first-plan/re-plan determination. Missing → invoke `recipe-plan-phase N` first. Then, regardless,
   always invoke `recipe-run-phase N`.
3. **Stop the whole loop immediately on the first failure** (plan step or run step) for phase `N` —
   never proceed to `N+1`. Report exactly which phase blocked and why. This is the one unconditional
   rule in an otherwise entirely soft-gated skill (see "Stop-on-failure behavior" in the shipped
   `SKILL.md`).
4. **No duplicated Jira sync.** `recipe-run-phases` never invokes `gsd-jira-sync` itself —
   `plan_complete`/`plan_revised`/`execute_started`/`execute_complete` are already emitted per
   phase by the two invoked skills, each idempotent via `sync-ledger.sh` on their own terms. This
   skill only orchestrates the loop and prints a final summary (phases completed; the blocking
   phase and reason, if any).
5. **Soft warn-and-confirm gate before the loop starts.** Shows the full range and what will happen
   for each phase, mirroring `install.sh`'s own consent-prompt precedent and
   `recipe-plan-phase`'s/`recipe-run-phase`'s own soft-gate precedent — never a hard block,
   informational confirmation only.
6. **DAG eligibility gating and `depends_on`/`touches` stay explicitly out of scope / print-only.**
   Same parked-pending-TASK-009 precedent already established for TASK-017/024. `recipe-run-phases`
   never re-parses, aggregates, or acts on either invoked skill's own `depends_on`/`touches`
   reminder — those are printed once, per phase, by the invoked skills themselves.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| DAG topo-sort/cycle detection, DAG eligibility gating (`RUNTIME-LLD.md` §1.c.2.a/b/c, and the very "auto-loop" framing of §2.b itself) | Tier-1 DAG work, parked pending TASK-009 (`dag-build.sh`), locked in `DECISIONS.md`. `recipe-run-phases` never reads or writes `.knowledge/dag/*`; the loop is always plain ascending over `[start, end]`, decision #1/#6 above. |
| `gsd-autonomous` | `RUNTIME-LLD.md` §2.b's own command block shows `gsd-autonomous --from 3 --to 5` as the native primitive this row conceptually maps to — but the locked decision is Option-B skill-to-skill orchestration (this skill invokes `recipe-plan-phase`/`recipe-run-phase` by name), not a call into `gsd-autonomous`, which stays a separate, unwrapped GSD-native unattended-autonomy primitive. |
| Re-implementing `recipe-plan-phase`'s/`recipe-run-phase`'s own steps | First-plan/re-plan determination, issue-key resolution, either skill's own compliance gate, `depends_on`/`touches` reminders, and both tracker syncs are each already fully specified in their own `SKILL.md`s — `recipe-run-phases` only decides *whether*/*when* to invoke them and whether to keep looping. |
| Duplicated Jira sync | Decision #4 above — `plan_complete`/`plan_revised`/`execute_started`/`execute_complete` are each already emitted exactly once per phase by the two invoked skills. |
| `--wave` passthrough / `execute_wave` handling | `recipe-run-phase`'s own single-phase concern; `recipe-run-phases` always runs a phase as a whole and never accepts or forwards `--wave`. |
| Automatic retry of a failed phase, or skipping past it | Decision #3 — the loop stops, full stop, on the first plan-step or run-step failure; the operator decides what to do next. |
| Composing into `install.sh` (TASK-010), `test-install.sh`, `BACKLOG.md`, `README.md` edits | 3 sibling tasks (TASK-025/026/027) are editing those 4 shared files concurrently this session — this task's hard constraints explicitly forbid touching them. All 4 deferred snippets are provided below, verbatim copy-paste-ready, for the parent integration pass to apply. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-run-phases-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-plan-phase-SKILL.md`'s/`recipe-run-phase-SKILL.md`'s format) implementing the loop: validate range → soft pre-loop warn-and-confirm gate → for each phase N ascending: glob-check `PLAN.md` → invoke `recipe-plan-phase N` if missing, re-check → always invoke `recipe-run-phase N` → stop the whole loop immediately on the first plan-step or run-step failure → final summary. Includes an explicit "Why Option B" section (noting this is the third `recipe-*` skill in the `RUNTIME-LLD.md` §1.c/§2.a/§2.b lineage applying the same already-approved precedent), a "Why sequential ascending, not a DAG topo-sort" section, and a "Why plan-existence … decides pass/fail" section explaining the asymmetric plan-step-vs-run-step failure definitions. |
| Installer | `.gsd-recipe/scripts/install-recipe-run-phases.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s/`install-recipe-plan-phase.sh`'s structure/functions exactly (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-run-phases/SKILL.md` — the invoke-by-name Cursor skill path. Component name `"recipe-run-phases"`. Never touches `.gsd-recipe/config.json` or `.planning/config.json`. Not composed into `install.sh` by this task (hard constraint) — see the deferred `RECIPE_RUN_PHASES_INSTALLER` snippet below. |
| Tests | `bench/tests/test-install-recipe-run-phases.sh` (26 assertions) | Standalone installer behavior (fresh install, idempotency, uninstall, self-install, fail-closed, never touches either config.json) plus staged-content assertions for every documented gate/behavior/decision above. Deliberately omits the install.sh-composition assertion block `test-install-recipe-run-phase.sh`'s/`test-install-recipe-plan-phase.sh`'s own §8 carries — those assertions would fail against an unmodified `install.sh` (this task's hard constraint forbids editing it); the equivalent composition assertions are provided as a deferred `test-install.sh` snippet below instead. |
| Self-install | `.cursor/skills/recipe-run-phases/SKILL.md` | Live staged copy in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`, `recipe-run-phase`, `recipe-plan-phase`). |

### Why this installer stages under `.cursor/skills/`, not plain `skills/`

Same rationale as `recipe-run-phase`'s and `recipe-plan-phase`'s own reports: `recipe-planning-policy`
(TASK-012) is GSD's own **injected-context** mechanism (`.planning/config.json`'s
`agent_skills.<agentType>` array) — nothing ever invokes it by name. `recipe-run-phases` is the
opposite case: an operator genuinely types `recipe-run-phases 3 5` to invoke it, exactly like
`recipe-plan-phase`/`recipe-run-phase`/`tracker-sync`/`recipe-prd-intake`. So this installer mirrors
those skills' `.cursor/skills/<name>/SKILL.md` staging path and full A/B/C/D adapter format.

### Why the installer/test shape mirrors TASK-017/024's exactly, byte-for-byte where possible

The task prompt's own instruction was to mirror the TASK-017/024 shape exactly. The installer's
functions (`ledger_init`/`ledger_record`/`ledger_files`/`safe_copy`/`is_canonical_source`/
`install`/`uninstall`) are structurally identical to `install-recipe-run-phase.sh`'s and
`install-recipe-plan-phase.sh`'s own — only the component name, skill name, and the operator-facing
echo strings describing what the skill does differ. This keeps the three sub-installers'
maintenance surface identical, and is why the deferred `install.sh`/`test-install.sh` snippets below
follow the exact same "+N assertions" pattern those two tasks' own reports used.

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-run-phases/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4 | Install never creates `.gsd-recipe/config.json` | PASS |
| 5 | Install never creates `.planning/config.json` | PASS |
| 6-19 | Staged content references invoking `recipe-plan-phase`/`recipe-run-phase` (skill-to-skill), disclaims `gsd-autonomous`, documents the sequential-ascending/no-DAG-topo-sort design, documents DAG-eligibility-gating-out-of-scope, references the per-phase `PLAN.md`-exists check, documents stopping the whole loop immediately on first failure, distinguishes plan-step vs run-step failure, documents never proceeding to `N+1` after a failure, documents the pre-loop range confirmation as a soft gate, disclaims invoking `gsd-jira-sync` directly, documents not duplicating Jira sync, references `depends_on` as print-only/owned-by-the-invoked-skills, and disclaims accepting/forwarding `--wave` itself (14 separate `grep` assertions) | PASS (all 14) |
| 20 | Re-running install does not duplicate ledger rows | PASS |
| 21 | Uninstall removes the staged skill | PASS |
| 22 | Uninstall clears the component's ledger entry | PASS |
| 23 | Uninstall cleans up the now-empty skill directory | PASS |
| 24 | Self-install into a copy of this repo does not error (src==dest collision handled) | PASS |
| 25 | Self-install uninstall does not error | PASS |
| 26 | Self-uninstall preserves the canonical skill template source | PASS |

`bench/tests/test-install-recipe-run-phases.sh` total: **26 assertions, 0 failed.**

Per the task's explicit instruction, only this new test file was run standalone — **not** the full
`bench/tests/` suite, since 3 sibling tasks (TASK-025/026/027) are editing shared files
(`install.sh`, `test-install.sh`, `BACKLOG.md`, `README.md`) concurrently this session and a
full-suite run would race against their in-flight edits. `test-install.sh` itself was not run or
modified by this task — the composition assertions it would eventually gain are provided as a
deferred snippet below rather than applied.

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/recipe-run-phases-manual-01` (never the real
`gsd-benchmark` repo for the scratch-fixture work — every scratch command below used an absolute
`--target`/`REPO_ROOT` pointing at the scratch path, per the task's safety constraint; no `cd` was
relied upon to survive across separate tool calls other than within a single `Shell` call's own
`set -e` sequence). The real repo *was* deliberately self-installed into once (staging
`.cursor/skills/recipe-run-phases/SKILL.md` via the real installer with no `--target`, i.e.
defaulting to this repo) — the same expected self-install side effect every prior installer's report
documents; confirmed afterward via `git status --porcelain` that this is the only
`recipe-run-phases`-related change in the real repo (no stray `.knowledge/`, no stray git config).

**Setup:** `git init` the scratch repo; ran the real
`.gsd-recipe/scripts/install-recipe-run-phases.sh --yes --target /tmp/recipe-run-phases-manual-01`
(a real installer execution, not simulated — it staged a real
`.cursor/skills/recipe-run-phases/SKILL.md` there and recorded 1 real ledger row, verified after the
fact via `python3 -c "import json; print(json.load(...))"`); seeded a `PLAN.md` fixture for phase 3
(`.planning/phases/03-payments/phase-03-review-PLAN.md`, copied from the existing
`bench/tests/fixtures/plan-with-filled-prereqs-table.md`), named to satisfy `recipe-plan-phase`'s
documented glob pattern (same naming quirk `recipe-run-phase`'s and `recipe-plan-phase`'s own manual
verifications already surfaced — see their reports' "Note on the glob pattern" sections).

Per the task's explicit instruction — **never actually invoke real native GSD commands or real
`gsd-jira-sync`/MCP calls for a live phase during verification** — the loop *mechanics themselves*
(range iteration, the per-phase `PLAN.md`-exists glob check, conditional `recipe-plan-phase`
invocation, unconditional `recipe-run-phase` invocation, and stop-on-first-failure control flow)
were exercised for real using a small standalone harness script
(`/tmp/recipe-run-phases-manual-01/harness.sh` and `harness-run-step-fail.sh`, both deleted after
this run along with the rest of the scratch repo) that implements `recipe-run-phases`'s documented
algorithm exactly — real `Glob`-equivalent `compgen -G` checks against the real scratch
`.planning/phases/` tree, a real ascending `for` loop over the real range, real early-`break`
stop-on-failure logic — while stubbing out only the two calls that would otherwise need a live
nested agent turn or real native GSD/MCP access: `plan_phase_stub()` (stands in for "invoke
`recipe-plan-phase N` by name") and `run_phase_stub()` (stands in for "invoke `recipe-run-phase N`
by name"), each pre-scripted per scenario to return success or failure so the *surrounding* loop
logic could be proven out for real. This mirrors exactly how the TASK-017/024/022 reports traced
their own native-GSD-call steps rather than executing them for real.

**Confirmed outcomes for the 3 required scenario checks (all exercised for real via the harness,
against the real scratch `.planning/phases/` tree):**

| Scenario | Range | Result |
|---|---|---|
| A. Range iteration + plan-exists detection, full success | `3 4` | Phase 3: real glob found the pre-seeded `PLAN.md` → plan step correctly skipped. Phase 4: real glob found nothing (both patterns) → plan step correctly invoked (stub simulates success, writes a real `PLAN.md` fixture into the scratch tree) → real re-glob correctly found it → run step invoked (stub simulates success). Final summary correctly reported `Phases completed: 3 4`, exit 0. |
| B. Stop-on-plan-step-failure | `3 5` | Phases 3 and 4 (now both with real `PLAN.md`s on disk from scenario A) correctly skipped the plan step and completed their run steps. Phase 5: real glob found nothing → plan step invoked (stub simulates a **failure** — no `PLAN.md` written) → real re-glob correctly confirmed still nothing → loop correctly stopped immediately with `Blocked at phase 5 (plan step): recipe-plan-phase did not produce a PLAN.md`, `Loop stopped immediately — did not proceed to phase 6`, exit 1. Phase 6 was never touched (range's own upper bound was 5, but the message text itself confirms the stop-before-increment logic). |
| C. Stop-on-run-step-failure | `3 5` (fresh harness variant) | Phase 3: real glob found its `PLAN.md` → run step succeeded (stub). Phase 4: real glob found the `PLAN.md` scenario A had left behind → run step **failed** (stub simulates "operator declined its planning-policy gate; native `gsd-execute-phase` never called") → loop correctly stopped immediately with `Blocked at phase 4 (run step): recipe-run-phase stopped before completing`, `Loop stopped immediately — did not proceed to phase 5`, exit 1. Confirmed for real afterward: `ls .planning/phases/` showed only `03-payments`/`04-notifications` — no `05-*` directory was ever created, proving phase 5's plan step was genuinely never reached. |

**What was truly exercised vs. stubbed:**

- **Truly executed** (real tool calls, real scripts, real files, on the scratch repo only): the
  installer itself (staged a real file, wrote a real ledger row, later a real uninstall removed
  both); every `Glob`-equivalent check in all three scenarios (both the primary and fallback pattern
  shape, both the initial check and the post-invocation re-check); the real ascending loop
  control-flow, including the real early-`break` on first failure and the real final-summary
  branch logic; the real on-disk confirmation that phase 5/6 were never touched in scenarios B/C.
- **Stubbed, not executed for real**: the two calls that would otherwise require either a live
  nested agent turn (to genuinely invoke `recipe-plan-phase`/`recipe-run-phase` skill-to-skill, which
  this environment cannot spawn) or real native GSD/`gsd-jira-sync`/Atlassian MCP access — per the
  task's explicit safety constraint. Each stub's pre-scripted outcome directly maps to a real
  documented stop condition in `recipe-plan-phase-SKILL.md`'s/`recipe-run-phase-SKILL.md`'s own
  "Fail-open behavior" sections (a `PLAN.md` genuinely not existing after the call; the operator
  genuinely declining a soft gate before native execution starts), not an invented failure mode.

**Cleanup:** the scratch repo's installed skill was uninstalled via the real
`--uninstall --target /tmp/recipe-run-phases-manual-01` (confirmed removed), then the entire scratch
directory was deleted (`rm -rf`). Re-confirmed afterward that the real repo's `git status
--porcelain` shows no `recipe-run-phases`-related changes besides the deliberate self-install
mentioned above, and `git config --list --local` shows no stray entries.

## Note on the glob pattern's real-world naming fit

Same pre-existing characteristic `recipe-run-phase`'s and `recipe-plan-phase`'s own manual
verifications already surfaced (inherited, not introduced here): `recipe-plan-phase`'s documented
`PLAN.md` glob shape (`*-{NN}-*-PLAN.md`) requires additional content between the phase number and
the trailing `-PLAN.md` — e.g. `phase-03-review-PLAN.md` matches; a bare `03-payments-PLAN.md` or
GSD's own native `{phase}-{plan}-PLAN.md` two-segment convention (e.g. `03-01-PLAN.md`) does not.
`recipe-run-phases` reuses that exact glob shape verbatim for its own step-3.a check (per decision
#2/the task's own instruction to mirror `recipe-plan-phase`'s check), so this scratch verification's
fixture filenames were named to satisfy it, matching the two prior tasks' own precedent.

## Files

- `.gsd-recipe/templates/recipe-run-phases-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-run-phases.sh` (new)
- `bench/tests/test-install-recipe-run-phases.sh` (new, 26 assertions)
- `bench/report/recipe-run-phases-integration-report.md` (this file, new)
- `.cursor/skills/recipe-run-phases/SKILL.md` (self-install side effect, real repo)

**Not edited, per this task's hard constraints** (deferred to a parent integration pass — exact
snippets below): `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`. Also not edited (read-only
dependency, invoked by name only): `.gsd-recipe/templates/recipe-plan-phase-SKILL.md`,
`.gsd-recipe/templates/recipe-run-phase-SKILL.md`, and their installers.

## Deviations from the plan

None. The task prompt's locked design decisions, file list, and installer/test shape were followed
exactly as scoped. The only interpretive judgment call (flagged explicitly, not silently glossed
over) was defining what "the plan step failing" / "the run step failing" concretely means given that
`recipe-plan-phase`/`recipe-run-phase` are skill invocations without a formal exit code — resolved by
tying each failure definition to that sibling skill's own already-documented stop conditions (a
`PLAN.md` genuinely still missing after the call; the operator genuinely declining that skill's own
soft compliance gate before its native call fires; or, for the run step only, the native call itself
erroring/aborting partway through). This reasoning is written out in full in the shipped
`SKILL.md`'s own "Why plan-existence … decides pass/fail" section, not just in this report.

---

## Deferred snippets for the 4 shared files (provide only — not applied by this task)

These are copy-paste-ready, following the exact shape `recipe-run-phase-integration-report.md`'s
and `recipe-plan-phase-integration-report.md`'s own reports used for their 4th/5th sub-installer
additions. This would be the **ninth** sub-installer composed into `install.sh` (after
`install-observer.sh`, `install-tracker-sync.sh`, `install-recipe-planning-policy.sh`,
`install-recipe-run-phase.sh`, `install-recipe-plan-phase.sh`, `install-recipe-validate-tokens.sh`,
`install-recipe-bootstrap-knowledge.sh`, `install-recipe-install-verify.sh`).

### 1. `.gsd-recipe/scripts/install.sh`

Add a ninth installer path variable, alongside the existing eight (near the other
`RECIPE_*_INSTALLER` declarations):

```bash
RECIPE_RUN_PHASES_INSTALLER="$SCRIPT_DIR/install-recipe-run-phases.sh"
```

In `install()`, add to the sub-installer composition call block (after
`"$RECIPE_INSTALL_VERIFY_INSTALLER" --yes --target "$TARGET"`):

```bash
  "$RECIPE_RUN_PHASES_INSTALLER" --yes --target "$TARGET"
```

Update the umbrella consent prompt string and the "composing sub-installers" echo line to name it
(both currently end with `... + recipe-install-verify)` / `... recipe-install-verify)...`) — append
`+ recipe-run-phases` / `, recipe-run-phases` respectively.

In `uninstall()`, add to the cascade block (after
`"$RECIPE_INSTALL_VERIFY_INSTALLER" --uninstall --target "$TARGET"`):

```bash
  "$RECIPE_RUN_PHASES_INSTALLER" --uninstall --target "$TARGET"
```

In `verify()`, add alongside the other `ledger_has_component` checks (after the
`recipe-install-verify` block):

```bash
  if ledger_has_component "recipe-run-phases"; then
    echo "    recipe-run-phases composed — pass"
  else
    echo "    recipe-run-phases composed — FAIL (recipe-run-phases ledger component absent)"
    ok=0
  fi
```

Also update the header comment's component-name list (currently ending
`"recipe-validate-tokens"/"recipe-bootstrap-knowledge"/"recipe-install-verify"`) to append
`/"recipe-run-phases"`.

### 2. `bench/tests/test-install.sh`

Add a fresh-install staging check (alongside the other 8, after the `recipe-install-verify` one):

```bash
[ -f "$TARGET1/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "install.sh composes install-recipe-run-phases.sh (skill staged)" "$?"
```

Extend the ledger cross-tracking `python3` block (add both an `assert 'recipe-run-phases' in d`
line and a new disjointness line, mirroring the other 8):

```python
assert 'recipe-run-phases' in d and d['recipe-run-phases'], d
...
assert set(d['install-core']).isdisjoint(set(d['recipe-run-phases'])), d
```

and extend that assertion's own `check` description string to append
`/recipe-run-phases`.

Add a `--verify` output-mention check (alongside the other 8):

```bash
echo "$VERIFY_OUT1" | grep -q "recipe-run-phases composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-run-phases composition" "$rc"
```

Add an `--uninstall` cascade check (alongside the other 8):

```bash
[ ! -f "$TARGET3/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "uninstall cascades to install-recipe-run-phases.sh --uninstall" "$?"
```

This is **+4 net new assertions** (one existing ledger-disjointness assertion body extended rather
than duplicated, same pattern the prior two tasks used) — the exact new total depends on wherever
`test-install.sh` lands after TASK-025/026/027's own concurrent edits; apply relative to that
file's state at integration time, not the count in this report.

### 3. `docs/netapp-recipe/BACKLOG.md`

Replace the current TASK-018 row:

```markdown
| TASK-018 | `recipe-run-phases` | M | 017, 024 | [RUNTIME-LLD](lld/RUNTIME-LLD.md) |
```

with:

```markdown
| TASK-018 | `recipe-run-phases` | M | 017, 024 | [RUNTIME-LLD](lld/RUNTIME-LLD.md) — **Built**, narrowed scope: sequential ascending multi-phase loop wrapper around `recipe-plan-phase N`/`recipe-run-phase N`, invoked skill-to-skill (Option B), never raw native `gsd-plan-phase`/`gsd-execute-phase` and never `gsd-autonomous`. No DAG topo-sort/eligibility gating (§1.c.2.a/b/c and the "auto-loop" framing in §2.b itself) — parked pending TASK-009, same narrowed-scope precedent TASK-017/024 already established; `depends_on`/`touches` stay print-only, owned by the two invoked skills. Stops the whole loop immediately on the first phase whose plan step or run step fails; never duplicates Jira sync (already emitted per-phase by the invoked skills); a soft warn-and-confirm gate shows the full range before starting. See [bench/report/recipe-run-phases-integration-report.md](../../bench/report/recipe-run-phases-integration-report.md). |
```

### 4. `docs/netapp-recipe/README.md`

In the "Built vs spec" table, add a row (after the `recipe-plan-phase` row, before
`create-phase-tasks.sh`):

```markdown
| `recipe-run-phases` skill (TASK-018) | **Built** — narrowed scope: sequential ascending multi-phase loop wrapper (`.gsd-recipe/scripts/install-recipe-run-phases.sh`, standalone installer also composed into `install.sh` as a 9th sub-installer); for each phase N in `[start, end]` ascending, checks whether `PLAN.md` already exists and invokes `recipe-plan-phase N` by name first only if missing, then always invokes `recipe-run-phase N` by name — skill-to-skill (Option B), never raw native `gsd-plan-phase`/`gsd-execute-phase`, never `gsd-autonomous`; stops the whole loop immediately on the first phase whose plan step or run step fails, reporting exactly which phase blocked and why; never duplicates Jira sync (already emitted per-phase by the two invoked skills); DAG topo-sort/eligibility gating is explicitly out of scope (parked pending TASK-009) — see [bench/report/recipe-run-phases-integration-report.md](../../bench/report/recipe-run-phases-integration-report.md) |
```

In the "Commands" → "Built" table, add a row (after the `recipe-plan-phase N` row):

```markdown
| `recipe-run-phases <start> <end>` (TASK-018) | Sequential ascending multi-phase loop wrapper — [.gsd-recipe/templates/recipe-run-phases-SKILL.md](../../.gsd-recipe/templates/recipe-run-phases-SKILL.md) · [report](../../bench/report/recipe-run-phases-integration-report.md) |
```

In the "Commands" → "Spec (`recipe-*`)" table, remove `recipe-run-phases` from its current row
(since it's no longer spec-only):

```markdown
| `recipe-prd-intake`, `recipe-verify-feature` | p1 | [RUNTIME-LLD](lld/RUNTIME-LLD.md) |
```

(replacing the current `| \`recipe-prd-intake\`, \`recipe-run-phases\`, \`recipe-verify-feature\` |
p1 | [RUNTIME-LLD](lld/RUNTIME-LLD.md) |` row), and extend the existing "moved to Built" note
below that table (currently ending "...it's no longer spec-only.") to also mention
`recipe-run-phases` (TASK-018) alongside `recipe-run-phase`/`recipe-plan-phase`.
