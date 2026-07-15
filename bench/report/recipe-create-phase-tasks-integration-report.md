# `recipe-create-phase-tasks` — agent-mediated phase-task creation (TASK-034)

Closes the exact gap `BACKLOG.md`'s own TASK-007 row leaves open in writing: `create-phase-tasks.sh`
can detect+draft+queue a phase-task summary/description per unlinked `ROADMAP.md` phase, but
"does not call `createJiraIssue`/`createIssueLink` (agent-mediated, same split as
`sync-reconcile.sh`)". This task builds that agent-mediated step as a thin, invoke-by-name skill —
the same shape `gsd-jira-sync`'s Drain mode (TASK-005) already established for posting queued
lifecycle comments, adapted from "post a comment per queued event" to "create+link a Jira issue
per queued phase task."

## Key design decision: `list` is a new subcommand of the existing script, not a new file

Same precedent `create-phase-tasks.sh`'s own TASK-007 report already set for `mark-done`/
`mark-failed`: "no need to build a full separate drain script unless you think it's warranted."
`sync-drain-queue.sh list` is the closest existing analog for "re-verify pending queue rows
against the source of truth, self-heal duplicates, return a JSON work list" — but it operates on a
structurally different queue (`sync-queue.jsonl`, ledger-keyed by `sync-ledger.sh has`) than
`create-phase-tasks.sh`'s own `phase-tasks-queue.jsonl` (which has no ledger entry at all — its
source of truth for "already linked" is `parse-state.sh dump`'s `phase_tasks` table, exactly the
same source `detect` itself already reads). So `list` was added as a fourth subcommand of
`create-phase-tasks.sh` itself, mirroring `sync-drain-queue.sh list`'s exact
self-heal-then-return-work *pattern* without literally reusing its ledger-based *mechanism* (which
doesn't apply here — there is no `sync-ledger.jsonl` entry for a phase-task row, only a
`STATE.md` row).

### Self-heal source: `parse-state.sh dump`, not a ledger check

`list` calls `parse-state.sh dump --state PATH` **once**, and only when there is at least one
`queued`/`failed` row to check — an empty or fully-`done` queue never even touches `STATE.md`,
confirmed by test #24/#29 (using a deliberately nonexistent `--state` path to prove it). For every
pending row, if that `phase_id` already has a non-empty `issue_key` in `STATE.md`'s `## Phase
tasks` table, the row is self-healed in place (`status: done`, `issue_key` recorded, prior `error`
cleared) and counted under `self_healed` — no MCP call, no duplicate `createJiraIssue`. This
covers exactly the scenario the task named: "a stray manual `add-phase-task` call that happened in
between" — and also a subtler case worth naming explicitly: a prior `recipe-create-phase-tasks`
run that got interrupted *after* `mark-done`'s `STATE.md` write but *before* its own queue-row
flip (a real, if narrow, crash window) self-heals on the very next `list` call rather than
re-creating a duplicate issue.

### Work items reuse `detect`'s own drafted fields verbatim

Per the task's explicit instruction, `list`'s `work` array entries (`phase_id`, `key`, `epic_key`,
`phase_title`, `phase_goal`, `drafted_summary`, `drafted_description`, `target`) are read straight
off each queue row — never re-parsed from `ROADMAP.md`. This keeps `list` cheap (no filesystem
read of `ROADMAP.md`, no re-resolution of the tracker epic) and guarantees the `summary`/
`description` an agent eventually passes to `createJiraIssue` is byte-identical to what `detect`
already drafted and a human could have inspected via `detect`'s own stdout.

### Errors surfaced, not swallowed

Mirroring `sync-drain-queue.sh list`'s own two failure-surfacing rules: a row missing its `key`
field, or one whose `target` isn't `jira` (the only target `create-phase-tasks.sh` currently
drafts, but the schema doesn't forbid others), is pushed to an `errors` array and `list` exits
non-zero — never silently dropped, never mis-processed as if it were a normal pending row.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| `list` subcommand | `bench/runners/create-phase-tasks.sh` (extended) | `list [--queue PATH] [--state PATH]` — self-heal-then-return-work, per the design above. Usage banner/docstring and `usage()` updated to document it alongside `detect`/`mark-done`/`mark-failed`. |
| Skill template | `.gsd-recipe/templates/recipe-create-phase-tasks-SKILL.md` | Full `<cursor_skill_adapter>` + prose body: detect (once) → list (self-healed work) → empty check → resolve batch issue type once → soft confirm gate → read `createJiraIssue` schema once → per-row create+link+mark-done/mark-failed → summary. |
| Installer | `.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh` | Standalone, single-file staging (skill only — `create-phase-tasks.sh` already lives in place, extended not copied), ledger-tracked, fail-closed non-git target, idempotent, uninstall-safe, self-install-collision-safe — mirrors `install-recipe-run-phase.sh`'s exact shape, plus an additive `--verify` mode (light, read-only ledger+staged-file check) matching the precedent the concurrently-built `install-recipe-create-epic.sh` (TASK-033) already set, since this task's own validation checklist explicitly calls for running `--verify`. |
| Tests | `bench/tests/test-create-phase-tasks.sh` (+13 assertions, 23→36), `bench/tests/test-install-recipe-create-phase-tasks.sh` (new, 33 assertions) | See Validation below. |
| This report | `bench/report/recipe-create-phase-tasks-integration-report.md` | — |

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| The actual `createJiraIssue`/`createIssueLink` MCP calls | Bash has no MCP tool-calling access — same constraint every sibling `bench/runners/` script in this recipe has. Documented in the skill's workflow as an agent-turn step; not executed by this task (no live Jira credentials available to a non-interactive subagent run) — see Validation. |
| `bench/lib/parse-state.sh` | Only ever consumed indirectly, via `create-phase-tasks.sh`'s existing `mark-done`/`detect` calls and `list`'s own new `dump` call — never edited, never called directly from the new skill file itself (the skill's own documented workflow calls `create-phase-tasks.sh`, not `parse-state.sh`, for every `STATE.md`-touching step). |
| `.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`, `bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `.gsd-recipe/capability.json` | On this task's explicit shared-file avoidance list (sibling agents editing TASK-033/TASK-035 concurrently). Copy-paste-ready snippets for all of them are below. |
| A separate `mark-done`/`mark-failed` step for `list` itself | `list` never calls `mark-done`/`mark-failed` — those remain exclusively the agent turn's job, invoked per-row after the real MCP calls succeed/fail, per the skill's own step 7-8. `list` only self-heals (a narrower, no-MCP-needed in-place mutation) and reports. |

## Validation performed

### Automated

`bench/tests/test-create-phase-tasks.sh` — **36 assertions, 0 failed** (23 pre-existing + 13 new
for `list`), run standalone:

| # | Check | Result |
|---|---|---|
| 24 | `list` on a missing queue file returns empty `work`/`self_healed`/`errors` without touching `STATE.md` at all | PASS |
| 25 | `list` surfaces genuinely-pending rows, reusing `detect`'s own drafted `epic_key`/`key`/`drafted_summary`/`drafted_description`/`target` fields verbatim | PASS |
| 26 | `list` never mutates the queue file when nothing needs self-healing (byte-identical before/after) | PASS |
| 27 | `list` self-heals a phase manually linked out-of-band via `parse-state.sh add-phase-task` — dropped from `work`, counted under `self_healed`, no MCP call | PASS |
| — | Self-heal writes `issue_key`+`status: done` into the self-healed row only, leaving sibling rows untouched | PASS |
| 28 | `list` surfaces a `failed` row exactly like a `queued` one (both retried/listed) | PASS |
| 29 | `list` on an all-`done` queue returns empty `work` without needing a valid `STATE.md` | PASS |

`bench/tests/test-install-recipe-create-phase-tasks.sh` — **33 assertions, 0 failed**, new file,
mirroring `test-install-recipe-run-phase.sh`'s shape (fail-closed non-git target, fresh-install
staging + ledger count, never touches `config.json`/`.planning/config.json`/
`phase-tasks-queue.jsonl`, staged-content assertions for every documented workflow step/gate,
idempotent re-install, uninstall cleanup, self-install collision safety), plus two additional
`--verify` assertions (passes on a freshly-installed target, fails on one that was never
installed) matching `install-recipe-create-epic.sh`'s own `--verify` precedent — deliberately
**without** `test-install-recipe-run-phase.sh`'s item-8 `install.sh` composition assertions, since
this task's `install.sh` wiring is deferred (see below), not part of this diff.

No-regression checks run in full:

- `bench/tests/test-sync-drain-queue.sh` — **18 assertions, 0 failed** (unmodified; confirms the
  closest existing `list` analog still behaves identically).
- `bench/tests/test-parse-state.sh` — **27 assertions, 0 failed** (unmodified; confirms `dump`,
  which the new `list` subcommand now also consumes, is unaffected).
- Full `bench/tests/` suite — run in full (this task's brief explicitly asked for it, unlike
  TASK-007's own report, which named sibling-agent file contention as a reason to skip it): see
  the exact pass/fail tally in the final response.

### Manual (live self-install)

Ran the new installer against this real repo root
(`/Users/vs72964/Projects/gsd-benchmark`) with `--yes`, confirming `recipe-create-phase-tasks`
became a real, invokable Cursor skill at
`.cursor/skills/recipe-create-phase-tasks/SKILL.md`, then ran the installer's own `--verify` mode,
which reported `[pass]` for both the ledger component and the staged skill file
(`recipe-create-phase-tasks installer --verify: OK`, exit 0). Full command transcript and exit
codes are in the final response.

The `createJiraIssue`/`createIssueLink` MCP calls themselves were **not** exercised live in this
pass (no disposable Jira project/epic was set up for this task, unlike
`gsd-jira-sync-live-test-report.md`'s disposable-issue precedent) — same "traced, not executed"
caveat TASK-007's own report already carries for the identical pair of MCP calls this task's skill
now wraps.

## Files

- `bench/runners/create-phase-tasks.sh` (edited — new `list` subcommand + usage/docstring updates)
- `bench/tests/test-create-phase-tasks.sh` (edited — 13 new assertions, 23 → 36)
- `.gsd-recipe/templates/recipe-create-phase-tasks-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh` (new)
- `bench/tests/test-install-recipe-create-phase-tasks.sh` (new, 33 assertions)
- `bench/report/recipe-create-phase-tasks-integration-report.md` (new, this file)

`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`, `.gsd-recipe/scripts/install.sh`,
`bench/lib/capability-schema.sh`, `.gsd-recipe/capability.json` need updates but were **not edited
directly** — all five are on this task's shared-file avoidance list (sibling agents editing
TASK-033/TASK-035 concurrently). Copy-paste-ready snippets follow.

---

## Deferred integration snippets (apply in a later centralized pass)

### 1. `install.sh` sub-installer composition

**Assumes this is the 18th sub-installer** (the current highest is `RECIPE_OBSERVE_INSTALLER`,
composed as the 17th, per TASK-032's own row in `BACKLOG.md`). TASK-033 (`recipe-create-epic`) is
being built concurrently by another agent and will also need a sub-installer number — **if
TASK-033 also landed and claimed 18th, renumber during the deferred integration pass** (e.g. this
one becomes 19th); this is expected and handled centrally, not coordinated live between agents.

Variable declaration (near the other `RECIPE_*_INSTALLER` declarations, after
`RECIPE_OBSERVE_INSTALLER`):

```bash
RECIPE_CREATE_PHASE_TASKS_INSTALLER="$SCRIPT_DIR/install-recipe-create-phase-tasks.sh"
```

`install()`'s consent prompt — append ` + recipe-create-phase-tasks` to the existing composed-list
string:

```bash
read -r -p "Install NetApp GSD recipe scaffold (install-core + observer + tracker-sync + recipe-planning-policy + recipe-run-phase + recipe-plan-phase + recipe-validate-tokens + recipe-bootstrap-knowledge + recipe-install-verify + recipe-run-phases + recipe-verify-feature + recipe-review-ship + recipe-settle + gsd-jira-sync + recipe-sync + recipe-pr-comment + recipe-install + recipe-observe + recipe-create-phase-tasks) into $TARGET? [y/N] " reply
```

`install()`'s composition log line — append `, recipe-create-phase-tasks`:

```bash
echo "install.sh: composing sub-installers (observer, tracker-sync, recipe-planning-policy, recipe-run-phase, recipe-plan-phase, recipe-validate-tokens, recipe-bootstrap-knowledge, recipe-install-verify, recipe-run-phases, recipe-verify-feature, recipe-review-ship, recipe-settle, gsd-jira-sync, recipe-sync, recipe-pr-comment, recipe-install, recipe-observe, recipe-create-phase-tasks)..."
```

`install()`'s sub-installer invocation loop — append, right after `"$RECIPE_OBSERVE_INSTALLER" --yes --target "$TARGET"`:

```bash
"$RECIPE_CREATE_PHASE_TASKS_INSTALLER" --yes --target "$TARGET"
```

`uninstall()`'s cascade — append, right after `"$RECIPE_OBSERVE_INSTALLER" --uninstall --target "$TARGET"`:

```bash
"$RECIPE_CREATE_PHASE_TASKS_INSTALLER" --uninstall --target "$TARGET"
```

`verify()`'s ledger-component check — append, right after the `recipe-observe` block:

```bash
  if ledger_has_component "recipe-create-phase-tasks"; then
    echo "    recipe-create-phase-tasks composed — pass"
  else
    echo "    recipe-create-phase-tasks composed — FAIL (recipe-create-phase-tasks ledger component absent)"
    ok=0
  fi
```

Top-of-file comment block's ledger-component list (the "separate from ... which the
sub-installers/skills track under their own component names" sentence) — append
`/"recipe-create-phase-tasks"` to that enumerated list.

### 2. `bench/lib/capability-schema.sh` CATALOG entry (source of truth — regenerate `.gsd-recipe/capability.json` from this via `generate-capability`, do not hand-edit the JSON)

Append to the `CATALOG` list in `generate-capability`, right after the `recipe-observe` entry:

```python
    {
        "id": "recipe-create-phase-tasks",
        "task_id": "TASK-034",
        "kind": "cursor-skill",
        "description": "Agent-mediated phase-task creation: closes TASK-007's detect+draft+queue-only gap. Runs create-phase-tasks.sh detect then list (self-heals anything already linked out-of-band), resolves one Jira issue type for the whole batch (prefers Task, then Sub-task), shows a soft confirm gate, then creates+links a Jira issue per pending phase task (createJiraIssue + parent field or createIssueLink) and records each outcome via mark-done/mark-failed.",
        "invoke_name": "recipe-create-phase-tasks",
        "staged_path": ".cursor/skills/recipe-create-phase-tasks/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-create-phase-tasks.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-create-phase-tasks",
    },
```

Once `install.sh`'s snippet above is also applied and `generate-capability` is re-run, the
resulting `.gsd-recipe/capability.json` entry (for reference — do not hand-write this, let
`generate-capability` produce it) will look like:

```json
{
  "id": "recipe-create-phase-tasks",
  "task_id": "TASK-034",
  "kind": "cursor-skill",
  "description": "Agent-mediated phase-task creation: closes TASK-007's detect+draft+queue-only gap. Runs create-phase-tasks.sh detect then list (self-heals anything already linked out-of-band), resolves one Jira issue type for the whole batch (prefers Task, then Sub-task), shows a soft confirm gate, then creates+links a Jira issue per pending phase task (createJiraIssue + parent field or createIssueLink) and records each outcome via mark-done/mark-failed.",
  "invoke_name": "recipe-create-phase-tasks",
  "staged_path": ".cursor/skills/recipe-create-phase-tasks/SKILL.md",
  "installer": ".gsd-recipe/scripts/install-recipe-create-phase-tasks.sh",
  "composed_by_install_sh": true,
  "ledger_component": "recipe-create-phase-tasks",
  "staged": true,
  "ledger_tracked": true,
  "version": "1.0.0"
}
```

### 3. `docs/netapp-recipe/BACKLOG.md` — new TASK-034 row

Append to the "Wave 1b — `recipe-*` skills" table, right after the TASK-032 (`recipe-observe`)
row:

```markdown
| TASK-034 | `recipe-create-phase-tasks` | S | 007 | [RUNTIME-LLD](lld/RUNTIME-LLD.md) § "1.d Tracker epic + tasks [C]" — **Built**: closes the exact gap TASK-007's own row leaves open in writing ("does not call `createJiraIssue`/`createIssueLink`"). Extends `create-phase-tasks.sh` with a new `list` subcommand (mirrors `sync-drain-queue.sh list`'s self-heal-then-return-work pattern, sourced from `parse-state.sh dump` rather than a ledger check, since phase-task rows have no ledger entry) that re-verifies every `queued`/`failed` row against `STATE.md`'s `## Phase tasks` table first, self-healing anything already linked out-of-band before returning the genuinely-pending work. Thin invoke-by-name skill wrapper (`recipe-create-phase-tasks`) chains `detect` (once) → `list` → a once-per-batch `getJiraProjectIssueTypesMetadata` issue-type resolution (prefers Task, then Sub-task) → a soft confirm gate → per-row `createJiraIssue` + link (`parent` field for Sub-task, else `createIssueLink`) → `mark-done`/`mark-failed`. `.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh` (standalone, ledger-tracked, stages the skill only — `create-phase-tasks.sh` already lives in place, extended not copied), composed into `install.sh` as an 18th sub-installer (see integration report for the exact snippet — pending renumbering if TASK-033 also claimed 18th concurrently). See [bench/report/recipe-create-phase-tasks-integration-report.md](../../bench/report/recipe-create-phase-tasks-integration-report.md). |
```

### 4. `docs/netapp-recipe/README.md` — "Built vs spec" table addition

Append to the "Built vs spec (100% shipped)" table, right after the `recipe-observe` row:

```markdown
| `recipe-create-phase-tasks` skill (TASK-034) | **Built** — closes TASK-007's own documented "does not call `createJiraIssue`/`createIssueLink`" gap. Extends `create-phase-tasks.sh` with a `list` subcommand (self-heal-then-return-work, sourced from `parse-state.sh dump`) and adds a thin invoke-by-name skill wrapper (`.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh`, standalone installer composed into `install.sh` as an 18th sub-installer) chaining `detect` → `list` → once-per-batch issue-type resolution → a soft confirm gate → per-row `createJiraIssue`+link → `mark-done`/`mark-failed`. |
```

## Deviations from the task brief

None in substance. One judgment call, flagged inline above rather than silently made: `list`'s
self-heal source of truth is `parse-state.sh dump` (a direct `STATE.md` read), not a
`sync-ledger.sh has` check — `sync-drain-queue.sh list`'s literal ledger-check *mechanism* doesn't
apply to `phase-tasks-queue.jsonl` (no `sync-ledger.jsonl` entry is ever written for a phase-task
row; `STATE.md`'s `## Phase tasks` table is the only durable "already linked" record this queue
has, and it's the exact same source `detect` itself already reads). The task's own required
reading #2 asked to mirror the *pattern* (self-heal-then-return-work), not the literal ledger
call — confirmed this is the correct adaptation, not a shortcut.
