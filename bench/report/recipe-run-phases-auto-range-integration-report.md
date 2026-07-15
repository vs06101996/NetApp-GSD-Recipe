# `recipe-run-phases` auto-range detection + `--full` chaining (TASK-035)

**Extends** the already-built `recipe-run-phases` skill (TASK-018) — this is not a new skill, no new
installer, no new staged path. `.gsd-recipe/templates/recipe-run-phases-SKILL.md` is the same
canonical source file, edited in place; `.gsd-recipe/scripts/install-recipe-run-phases.sh` still
stages it to the same `.cursor/skills/recipe-run-phases/SKILL.md` destination, under the same
`"recipe-run-phases"` ledger component.

## What changed, and why

| Change | Where | Why |
|---|---|---|
| `<start>`/`<end>` are now optional. When both are omitted, the skill auto-detects `[start, end]` as the `[min, max]` of every `## Phase N — Title` heading in `.planning/ROADMAP.md`, using the exact same heading grammar `bench/runners/create-phase-tasks.sh`'s own `PHASE_HEADING`/`ANY_HEADING` regexes document (quoted/paraphrased in the skill itself). Passing only one of the two is an argument error, same class as an invalid range. | New step 1 in `## C. Tool Usage` (existing "Validate the range" step renumbered to step 2; the soft gate renumbered to step 3; the loop renumbered to step 4; the final summary renumbered to step 5) | Operators running a fresh/whole-project loop no longer have to look up and type the phase numbers by hand; this mirrors the same enumeration logic `create-phase-tasks.sh` already uses for its own Jira phase-task detection, so there is exactly one heading grammar in this recipe, not two. |
| New optional `--full` flag. When passed, after `recipe-run-phase N` reports phase `N` complete (existing step, now 4.c), the skill also chains `recipe-verify-feature N` → `recipe-review-ship N` → `recipe-settle N` (by name, skill-to-skill) before advancing to `N+1` (new step 4.d). Any of the three failing/declining stops the whole range loop immediately, exactly like a plan-step/run-step failure. | New step 4.d in `## C. Tool Usage`; `## A. Skill Invocation` examples; the pre-loop gate message (step 3); the final summary (step 5) | Lets an operator run an entire phase range from plan through settle in one invocation, for repos that want the full pipeline automated end-to-end, while keeping every existing gate (compliance checks, CI check, PO-accept) exactly where its owning skill already puts it — `recipe-run-phases` adds no new gating logic of its own, only a fourth/fifth/sixth invocation point per phase. |
| Every cross-referencing section (frontmatter `description`, § B Prerequisites, § D Do NOT, the `## Workflow` list, "Why Option B", "Why sequential ascending", "Why plan-existence…", "What this does NOT do", "Stop-on-failure behavior") | Whole file | The file is deliberately dense and self-referential (step numbers, decision numbers, invoked-skill enumerations); every one of those had to move in lockstep with the step renumbering and the new flag, or the file would contradict itself mid-document. |

## Backward compatibility: byte-for-byte identical when no new args/flags are used

Concretely, for `recipe-run-phases 3 5` (an explicit range, no `--full` — the only invocation shape
that existed before this task):

1. **Step 1 (new)** hits its first branch — "both provided" — and does nothing but pass `3`/`5`
   through unchanged to step 2. No `ROADMAP.md` read happens on this path at all.
2. **Step 2** is the original "Validate the range" step, verbatim in substance (only its ordinal
   changed, from 1 to 2, and its internal "step-2 gate" self-reference became "step-3 gate" to
   match the renumbering — no behavioral change).
3. **Step 3** is the original soft warn-and-confirm gate. Its printed message gained one new
   conditional clause ("When `--full` was passed, append: …") that is a no-op — it simply doesn't
   fire — when `--full` isn't passed. The unconditional parts of the message are otherwise
   unchanged in substance.
4. **Step 4** is the original loop (a/b/c unchanged in substance, only re-lettered as 4.a/4.b/4.c
   instead of 3.a/3.b/3.c). Step 4.c's completion branch now has an explicit fork — "if `--full`
   was **not** passed, loop back to step 4.a… exactly as before" — which is exactly the original
   control flow, just now named as one branch of an if/else instead of being the only path.
5. **Step 4.d** never executes at all without `--full` — there is no code path that reaches it.
6. **Step 5** is the original final summary; its own `--full`-conditional clauses ("plus — when
   `--full` was passed and the phase's chain completed — …") are no-ops on this invocation shape.

So for the pre-existing invocation shape, every step the operator would actually observe running is
identical in substance to before this task — the only differences are cosmetic (step numbers shifted
by one to make room for the new step 1) and additive (new sentences that are conditionally inert
when `--full`/auto-detection aren't in play). This was verified structurally by re-reading the fully
edited file top-to-bottom (see "Validation performed" below) rather than by diffing generated text,
since the original file's own prose was edited in place, not regenerated.

## Installer: confirmed no functional changes needed

Per the task's own instruction to confirm explicitly rather than assume: `install-recipe-run-phases.sh`
stages one content-agnostic file (`safe_copy "$SKILL_SRC" "$SKILL_DEST"`) and records one ledger row.
Neither depends on the skill's content in any way — the installer would behave identically whether
the staged `SKILL.md` were one line or a thousand. **No functional/mechanical changes were made** to
`ledger_init`/`ledger_record`/`ledger_files`/`safe_copy`/`is_canonical_source`/`install`/`uninstall`.

The one edit made to the installer is purely cosmetic: the operator-facing `echo` lines printed after
a successful install (which describe, in prose, what the skill does — previously naming only the
`<start> <end>`-required shape and the plan/run steps) were updated to mention the now-optional range
and the `--full` chain, so the printed guidance doesn't read as stale/incomplete immediately after
install. This does not change any exit code, file written, or ledger row — `bench/tests/test-install-recipe-run-phases.sh`
does not assert on this printed text (it only asserts on staged `SKILL.md` content and installer
mechanics), so this was safe to touch without affecting test behavior either way.

## Test file: extended with 9 new content assertions

`bench/tests/test-install-recipe-run-phases.sh` does do content/`grep` assertions on the staged
`SKILL.md`'s text (§4, 14 assertions covering the original TASK-018 decisions/behaviors). None of
those 14 became stale — every string they check for (`recipe-plan-phase`, `recipe-run-phase N`,
`gsd-autonomous`, `sequential ascending`, `DAG`, `PLAN.md`, `stop the whole loop`, `plan step
failed`/`run step failed`, `do not proceed to phase`, `soft gate`, `gsd-jira-sync`, `never
duplicate`/`does not duplicate`, `depends_on`, `--wave`) is still present, verbatim or in an
equivalent phrasing already matched by the existing regex, in the edited file — confirmed by running
the original 26-assertion suite against the edited content *before* adding any new assertions (see
"Before" row below).

Nine new assertions were added (same `grep`-based style, same `check` helper, inserted as a new
"§4b" block immediately after the original 14), covering the new auto-detection and `--full`
behaviors: `auto-detect`, the `## Phase N` heading grammar, the `create-phase-tasks.sh` cross-reference,
the `--full` flag itself, each of the three newly-invoked skills' own `recipe-*-feature N`/`-ship
N`/`-settle N` call sites, the "byte-for-byte identical" backward-compatibility claim, and the
`--full sub-step failed` blocking-reason phrasing.

| | Before (this task) | After (this task) |
|---|---|---|
| Total assertions | 26 | 35 |
| §4 staged-content assertions | 14 | 23 (14 original + 9 new) |
| Result | 26 passed, 0 failed | 35 passed, 0 failed |

## Validation performed

1. **Full top-to-bottom re-read of the edited `SKILL.md`** after all edits, checking specifically
   for any leftover sentence implying the range is always mandatory, or that only two skills are
   ever invoked. None found — every remaining reference to "the two invoked skills" was updated to
   name `recipe-plan-phase`/`recipe-run-phase` explicitly (with a parenthetical `--full` addendum
   where relevant), and every step-number cross-reference (`step 3.a`/`3.b`/`3.c`/`4` → `4.a`/`4.b`/
   `4.c`/`5`, `step-2 gate` → `step-3 gate`) was located via `grep` and confirmed updated.
2. **`bench/tests/test-install-recipe-run-phases.sh` run twice**: once immediately after the
   `SKILL.md` edits (26/26 passing, confirming zero regressions against the pre-existing
   assertions), and again after adding the 9 new assertions (35/35 passing).
3. **Live re-install against the real repo root** —
   `./.gsd-recipe/scripts/install-recipe-run-phases.sh --yes --target /Users/vs72964/Projects/gsd-benchmark`
   — re-staged `.cursor/skills/recipe-run-phases/SKILL.md` from the edited template (idempotent;
   ledger still shows exactly 1 row for the `recipe-run-phases` component, unchanged). Confirmed via
   `diff .gsd-recipe/templates/recipe-run-phases-SKILL.md .cursor/skills/recipe-run-phases/SKILL.md`
   that the two files are now byte-identical — the live staged copy picked up every edit. This
   standalone installer has no `--verify` mode of its own (unlike the full, composed `install.sh`,
   which this task's hard constraints forbid touching) — the `diff` above is this installer's
   equivalent confirmation.

## Deferred edits for later integration (not applied by this task, per hard constraints)

This task's hard constraints forbid touching `docs/netapp-recipe/BACKLOG.md` and
`docs/netapp-recipe/README.md` directly (a deferred integration pass handles them together with
sibling tasks TASK-033/TASK-034). The exact copy-paste-ready text for that pass:

### `docs/netapp-recipe/BACKLOG.md` — addendum to the existing TASK-018 row

Chosen over a brand-new TASK-035 row: TASK-035 is an in-place extension of the same skill, not a
new deliverable with its own installer/component, so it reads more naturally as an addendum to the
row that already describes what `recipe-run-phases` does, rather than a second row for the same
skill name. Append this sentence to the end of the existing TASK-018 row's cell content (after "...a
soft warn-and-confirm gate shows the full range before starting."):

```markdown
**Extended (TASK-035):** `<start>`/`<end>` are now optional — omitting both auto-detects `[start,
end]` from every `## Phase N — Title` heading in `.planning/ROADMAP.md` (same heading grammar
`create-phase-tasks.sh` already uses), with backward-compatible argument-error handling when only
one is given. A new optional `--full` flag additionally chains `recipe-verify-feature N` →
`recipe-review-ship N` → `recipe-settle N` per phase, after `recipe-run-phase N` completes and
before advancing — any of the three failing/declining stops the whole range loop immediately, same
as a plan-step/run-step failure. `--full` is strictly opt-in; omitting it is byte-for-byte identical
to pre-TASK-035 behavior. See [bench/report/recipe-run-phases-auto-range-integration-report.md](../../bench/report/recipe-run-phases-auto-range-integration-report.md).
```

### `docs/netapp-recipe/README.md` — "Built vs spec" table, TASK-018 row

Append this sentence to the end of the existing `recipe-run-phases` skill (TASK-018) row's cell
content (after "...DAG topo-sort/eligibility gating is explicitly out of scope (parked pending
TASK-009)"), before its closing `— see [...]` report link, replacing that link with two links:

```markdown
; **extended (TASK-035)** with optional auto-range detection from `ROADMAP.md`'s `## Phase N`
headings (when `<start>`/`<end>` are both omitted) and an optional `--full` flag that additionally
chains `recipe-verify-feature N` → `recipe-review-ship N` → `recipe-settle N` per phase — see
[bench/report/recipe-run-phases-integration-report.md](../../bench/report/recipe-run-phases-integration-report.md)
and [bench/report/recipe-run-phases-auto-range-integration-report.md](../../bench/report/recipe-run-phases-auto-range-integration-report.md)
```

### `docs/netapp-recipe/README.md` — "Commands" → "Built" table

Replace the existing `recipe-run-phases <start> <end>` row:

```markdown
| `recipe-run-phases <start> <end>` (TASK-018) | Sequential ascending multi-phase loop wrapper — [.gsd-recipe/templates/recipe-run-phases-SKILL.md](../../.gsd-recipe/templates/recipe-run-phases-SKILL.md) · [report](../../bench/report/recipe-run-phases-integration-report.md) |
```

with:

```markdown
| `recipe-run-phases [<start> <end>] [--full]` (TASK-018, extended TASK-035) | Sequential ascending multi-phase loop wrapper, with optional `ROADMAP.md`-based auto-range detection and an optional `--full` verify→review→settle chain per phase — [.gsd-recipe/templates/recipe-run-phases-SKILL.md](../../.gsd-recipe/templates/recipe-run-phases-SKILL.md) · [report](../../bench/report/recipe-run-phases-integration-report.md) · [auto-range report](../../bench/report/recipe-run-phases-auto-range-integration-report.md) |
```

## Files

- `.gsd-recipe/templates/recipe-run-phases-SKILL.md` (edited — frontmatter description, § A/B/C/D,
  and every prose section below the adapter)
- `.gsd-recipe/scripts/install-recipe-run-phases.sh` (edited — operator-facing `echo` guidance text
  only; no functional/mechanical change)
- `bench/tests/test-install-recipe-run-phases.sh` (edited — 9 new content assertions appended as a
  new §4b block; 26 → 35 total)
- `bench/report/recipe-run-phases-auto-range-integration-report.md` (this file, new)
- `.cursor/skills/recipe-run-phases/SKILL.md` (self-install side effect, real repo — re-staged from
  the edited template via a real re-run of the existing installer)

**Not edited, per this task's hard constraints:** `.gsd-recipe/scripts/install.sh`,
`bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`, `bench/tests/test-capability-schema.sh`,
`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `.gsd-recipe/capability.json`, and
every other `recipe-*-SKILL.md` template (in particular `recipe-verify-feature-SKILL.md`,
`recipe-review-ship-SKILL.md`, `recipe-settle-SKILL.md` — read-only dependencies, invoked by name
only, never edited).

## Deviations from the task prompt

None. `docs/netapp-recipe/BACKLOG.md`'s TASK-018 row vs. a new TASK-035 row was left as an explicit
"your call" by the task prompt — this report chose the addendum-to-TASK-018 approach and states the
reasoning above; the exact alternative (a standalone new row) was not additionally drafted since the
prompt only asked for one or the other, whichever reads better.
