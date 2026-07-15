# `recipe-verify-feature` skill (TASK-025)

**Picked up per locked design decisions confirmed with the operator this session** — implemented
exactly as specified, not re-derived. Matches the standalone-installer precedent already used by
`recipe-prd-intake` (TASK-016), `recipe-planning-policy` (TASK-012), `recipe-run-phase`
(TASK-024), `recipe-plan-phase` (TASK-017), and `recipe-bootstrap-knowledge` (TASK-022) — built
ahead of/alongside the full `install.sh` (TASK-010, already built and composing 8 sub-installers as
of this task's start). `BACKLOG.md` lists TASK-025 with no dependencies ("—"), size M.

**Concurrency note:** this task ran in parallel with three sibling tasks (TASK-018
`recipe-run-phases`, TASK-026 `recipe-review-ship`, TASK-027 `recipe-settle`) editing the repo at
the same time. Per an explicit constraint on this task, the four shared files those siblings (and
prior sibling batches) were also touching — `install.sh`, `test-install.sh`, `BACKLOG.md`,
`README.md` — were **not** edited here. Every change that would normally land in those four files
instead ships as a copy-paste-ready snippet at the bottom of this report, for a follow-up
integration pass to apply once all concurrently-running tasks have landed.

## Scope decisions (locked this session — implemented exactly, not re-derived)

1. **Option B — 3 chained native calls in the same turn**, the operator's own act of invoking
   `recipe-verify-feature` by name being the manual GSD trigger (identical reasoning already
   approved for `recipe-plan-phase`/`recipe-run-phase`/`recipe-bootstrap-knowledge`):
   (a) `gsd-audit-milestone` (informational gap analysis vs ROADMAP DoD — no stamp per spec,
   non-blocking, never fails the flow), (b) `gsd-audit-uat` (cross-phase UAT), (c)
   `gsd-verify-work N` (the native, **conversational/interactive** UAT command — the operator
   interacts with it live during this same skill invocation; the skill's own instructions are
   explicit that this step is interactive and the agent should let the native command's own
   conversational flow run, not try to script/automate it).
2. **After `gsd-verify-work N` completes, sync the `verify_complete` event via the `gsd-jira-sync`
   skill** (skill-to-skill invocation by name, idempotent via `sync-ledger.sh`, fail-open when no
   tracker issue is linked to the phase — same precedent `recipe-plan-phase`/`recipe-run-phase`
   already establish).
3. **Explicitly out of scope**: Bootstrap Gate A/B (`bare_metal.template.md` re-run — feasibility
   caveat: commands are repo-specific), the `gsd-debug` recovery loop, and any
   benchmark/project-specific grader hook (explicitly deferred/parked for v1, same precedent as the
   DAG work).
4. **Never fabricates verification results.** If `gsd-audit-milestone`/`gsd-audit-uat` aren't
   applicable/available in a given context, warn-and-skip gracefully — never hard-fail the whole
   flow (same graceful-degradation precedent `recipe-bootstrap-knowledge` uses for its
   missing-ingest-manifest branch).
5. **File list and installer/test shape as scoped**: single-file Cursor invoke-by-name skill
   (mirroring `recipe-bootstrap-knowledge`'s chain-3-native-calls shape for structure, plus
   `recipe-plan-phase`/`recipe-run-phase`'s Jira-sync-at-the-end shape), a standalone installer, a
   standalone test file (installer behavior only, no `install.sh` composition assertions —
   deferred to the follow-up integration pass, see below), and this report.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Bootstrap Gate A/B (`RUNTIME-LLD.md` §3.c.1, `bare_metal.template.md` re-run) | Locked decision #3. Feasibility caveat carried verbatim from the spec: "Commands are repo-specific; template is generic" — a general-purpose skill cannot safely auto-run repo-specific bootstrap commands. |
| `gsd-debug` recovery loop (`RUNTIME-LLD.md` §3.c.2) | Locked decision #3. Stays a separate, operator-triggered call for environment failures surfaced during `gsd-verify-work N`'s own conversation; never invoked by this skill. |
| Benchmark/project-specific grader hook (e.g. `bench/grade/grade.sh`) | Locked decision #3, "same precedent as the DAG work" (parked, not required for v1). `RUNTIME-LLD.md`/`docs/GSD-COMMANDS.md` are both explicit that `gsd-verify-work` alone is never production sign-off; wiring a grader call in here would blur that line. |
| `gsd-audit-fix` (with or without `--dry-run`) | `RUNTIME-LLD.md` §3.b lists it as a separate, operator-invoked follow-up to `gsd-audit-uat`'s findings, not part of the audit call itself. |
| Scripting/automating `gsd-verify-work N`'s conversation | Locked decision #1(c) — this step is genuinely interactive; the skill invokes it and then defers entirely to the native command's own back-and-forth with the operator. |
| Fabricating `gsd-audit-milestone`/`gsd-audit-uat` results when skipped | Locked decision #4 — a skip is reported with a reason, never filled in with an invented finding. |
| `install.sh`/`test-install.sh`/`BACKLOG.md`/`README.md` edits | Explicit constraint for this task run (three sibling tasks — TASK-018/026/027 — concurrently editing those files) — see the copy-paste-ready snippets at the bottom of this report instead. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-verify-feature-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-bootstrap-knowledge-SKILL.md`'s chain-3-native-calls structure and `recipe-plan-phase-SKILL.md`'s/`recipe-run-phase-SKILL.md`'s Jira-sync-at-the-end shape) implementing the 6-step workflow: resolve tracker issue key → call native `gsd-audit-milestone` (warn-and-skip if inapplicable) → call native `gsd-audit-uat` (warn-and-skip if inapplicable) → call native `gsd-verify-work N` (genuinely interactive — let its own conversation run) → once that concludes, emit `verify_complete` via `gsd-jira-sync` (idempotent, fail-open) → one-report summary. Includes an explicit "Why Option B" section mirroring the prior skills' own sections, plus an explicit "one genuinely new wrinkle" callout naming that step (c) is a meaningfully different shape from every other native call in this recipe (interactive/conversational, not one-shot). |
| Installer | `.gsd-recipe/scripts/install-recipe-verify-feature.sh` | Standalone installer mirroring `install-recipe-bootstrap-knowledge.sh`'s/`install-recipe-run-phase.sh`'s structure/functions (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-verify-feature/SKILL.md` — the invoke-by-name Cursor skill path. Component name `"recipe-verify-feature"`. Never touches `.gsd-recipe/config.json`, `.planning/config.json`, `.planning/STATE.md`, or `.gsd-recipe/sync-ledger.jsonl` — tracker resolution and idempotent sync are the staged skill's own runtime job, not the installer's. |
| Tests | `bench/tests/test-install-recipe-verify-feature.sh` (31 assertions) | Standalone installer behavior only (fresh install, idempotency, uninstall, self-install, fail-closed, never touches config.json/STATE.md/sync-ledger.jsonl, staged-content assertions for every documented gate/behavior/decision above). Deliberately omits `install.sh` composition assertions — see "Deferred composition" below. |
| This report | `bench/report/recipe-verify-feature-integration-report.md` | Full validation record + the four deferred snippets. |
| Self-install | `.cursor/skills/recipe-verify-feature/SKILL.md` | Live staged copy in this repo — same expected self-install side effect as every prior installer (`recipe-prd-intake`, `recipe-planning-policy`, `tracker-sync`, `fotw-observer`, `recipe-run-phase`, `recipe-plan-phase`, `recipe-bootstrap-knowledge`, `recipe-validate-tokens`, `recipe-install-verify`). |

### Deferred composition (`install.sh` / `test-install.sh` / `BACKLOG.md` / `README.md`)

Unlike some earlier `recipe-*` tasks' reports (which shipped their `install.sh`/`test-install.sh`/
`BACKLOG.md`/`README.md` edits directly, when no sibling tasks were concurrently editing those
files at the time), this task's constraints explicitly forbid touching those four files — three
sibling tasks (TASK-018, TASK-026, TASK-027) are editing them right now. `install.sh` currently
composes 8 sub-installers (`observer`, `tracker-sync`, `recipe-planning-policy`, `recipe-run-phase`,
`recipe-plan-phase`, `recipe-validate-tokens`, `recipe-bootstrap-knowledge`,
`recipe-install-verify`) — the exact snippets a follow-up integration pass should apply, sized and
shaped identically to how those 8 wirings were each added in turn, are reproduced verbatim at the
bottom of this report, adding `recipe-verify-feature` as the **9th**.

### Why this installer stages under `.cursor/skills/`, not plain `skills/`

Same rationale as every prior invoke-by-name `recipe-*` skill's report: `recipe-planning-policy`
(TASK-012) is GSD's own **injected-context** mechanism (`.planning/config.json`'s
`agent_skills.<agentType>` array) — nothing ever invokes it by name, so it stages to a plain
top-level `skills/` directory with no `<cursor_skill_adapter>` block. `recipe-verify-feature` is
the opposite case: an operator genuinely types `recipe-verify-feature N` to invoke it, exactly like
`recipe-run-phase`/`recipe-plan-phase`/`recipe-bootstrap-knowledge`/`tracker-sync`/
`recipe-prd-intake`. So this installer mirrors those skills' `.cursor/skills/<name>/SKILL.md`
staging path and full A/B/C/D adapter format.

## Why Option B (direct same-turn calls), not a background/async trigger

This is the fourth `recipe-*` skill in this backlog to apply the same approved reasoning, so it's
worth stating precisely, mirroring `recipe-plan-phase-SKILL.md`'s, `recipe-run-phase-SKILL.md`'s,
and `recipe-bootstrap-knowledge-SKILL.md`'s own "Why Option B" sections (per the task brief's
explicit instruction to do so):

**The standing rule** (`docs/netapp-recipe/AGENTS.md` line 11): "User runs GSD skills manually —
do not invoke `gsd-plan-phase`, `gsd-execute-phase`, etc. on the user's behalf." This governs
*autonomous, unrequested* invocation of native GSD commands on the operator's behalf.

**The precedent** (already approved for `recipe-plan-phase`/`recipe-run-phase`/
`recipe-bootstrap-knowledge`): invoking a `recipe-*` skill *by name* is not autonomous or
unrequested — it is the operator's own deliberate, explicit act of asking for exactly the workflow
that skill documents.

**Applied here, unchanged:** `RUNTIME-LLD.md` §3 describes exactly this same shape of manual
trigger for `gsd-audit-milestone`, `gsd-audit-uat`, and `gsd-verify-work N`. The operator's own act
of invoking `recipe-verify-feature N` **is** that manual run — the same "human decided to do this
now" gate, applied to a fourth distinct trio of native commands.

**The one genuinely new wrinkle**, named explicitly rather than glossed over (per the task brief's
explicit instruction that step (c) is a meaningfully different shape from every prior native-call
step in this recipe): every prior Option-B native call in this recipe — `gsd-plan-phase`,
`gsd-execute-phase`, `gsd-map-codebase`, `gsd-graphify build`, `gsd-ingest-docs`, and this skill's
own `gsd-audit-milestone`/`gsd-audit-uat` — is a one-shot command that runs to completion and
returns a result for the calling skill to inspect. `gsd-verify-work N` is not — it is
`docs/GSD-COMMANDS.md`'s own "Conversational UAT from SUMMARYs; may create fix plans," a live,
multi-turn exchange with the operator that this skill does not own or control the shape of. Option
B still applies (the operator's invocation of `recipe-verify-feature` is still the manual trigger
for calling it), but this skill's job at that step is narrower: invoke it, then step back and let
the native command's own conversational contract with the operator run unmodified. The skill's own
SKILL.md § C.4 and § D are both explicit about this distinction, per the task brief's instruction
to call it out in the skill's own text, not just in this report.

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-verify-feature/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4-7 | Install never creates `.gsd-recipe/config.json`, `.planning/config.json`, `.planning/STATE.md`, or `.gsd-recipe/sync-ledger.jsonl` (those are the staged skill's own runtime job, not the installer's) | PASS (all 4) |
| 8-24 | Staged content references native `gsd-audit-milestone`, native `gsd-audit-uat`, native `gsd-verify-work`, the conversational/interactive disclaimer, the "never script the conversation" disclaimer, `verify_complete`, `gsd-jira-sync` (skill-to-skill), `sync-ledger.sh` idempotency, `parse-state.sh resolve-issue`, fail-open tracker behavior, the Option-B "manual trigger" reasoning, the "never fabricate" disclaimer, the warn-and-skip graceful-degradation disclaimer, Bootstrap Gate A/B out-of-scope, the `gsd-debug` recovery loop out-of-scope, any grader hook out-of-scope, and `gsd-audit-fix` out-of-scope (17 separate `grep` assertions) | PASS (all 17) |
| 25 | Re-running install does not duplicate ledger rows | PASS |
| 26 | Uninstall removes the staged skill | PASS |
| 27 | Uninstall clears the component's ledger entry | PASS |
| 28 | Uninstall cleans up the now-empty skill directory | PASS |
| 29 | Self-install into a copy of this repo does not error (src==dest collision handled) | PASS |
| 30 | Self-install uninstall does not error | PASS |
| 31 | Self-uninstall preserves the canonical skill template source | PASS |

`bench/tests/test-install-recipe-verify-feature.sh` total run, standalone: **31 assertions,
0 failed.**

```text
$ ./bench/tests/test-install-recipe-verify-feature.sh
ok - refuses to install into a non-git directory
ok - fresh install stages .cursor/skills/recipe-verify-feature/SKILL.md
ok - fresh install records exactly 1 ledger row (the skill file)
ok - install never creates .gsd-recipe/config.json
ok - install never creates .planning/config.json
ok - install never creates .planning/STATE.md
ok - install never creates .gsd-recipe/sync-ledger.jsonl itself (that's the staged skill's runtime job)
ok - staged skill references native gsd-audit-milestone
ok - staged skill references native gsd-audit-uat
ok - staged skill references native gsd-verify-work
ok - staged skill documents gsd-verify-work as conversational/interactive
ok - staged skill disclaims scripting/automating gsd-verify-work's conversation
ok - staged skill references the verify_complete tracker event
ok - staged skill invokes the gsd-jira-sync skill (not inlined Jira logic)
ok - staged skill references sync-ledger.sh idempotency
ok - staged skill resolves the tracker issue key via parse-state.sh resolve-issue
ok - staged skill documents fail-open behavior when no tracker issue is linked
ok - staged skill documents the Option-B same-turn-call reasoning
ok - staged skill disclaims fabricating audit/verification results
ok - staged skill documents graceful warn-and-skip for gsd-audit-milestone/gsd-audit-uat
ok - staged skill documents Bootstrap Gate A/B as explicitly out of scope
ok - staged skill documents the gsd-debug recovery loop as explicitly out of scope
ok - staged skill documents any benchmark/project-specific grader hook as explicitly out of scope
ok - staged skill documents gsd-audit-fix as explicitly out of scope (separate operator follow-up)
ok - re-running install does not duplicate ledger rows
ok - uninstall removes the staged skill
ok - uninstall clears the component's ledger entry
ok - uninstall cleans up the now-empty skill directory
ok - self-install into a copy of this repo does not error (src==dest collision handled)
ok - self-install uninstall does not error
ok - self-uninstall preserves the canonical skill template source
---
31 passed, 0 failed
```

**Per this task's explicit instruction, the full `bench/tests/` suite was NOT run** — three sibling
tasks (TASK-018/026/027) are editing files under `bench/tests/`/`bench/lib/`/`.gsd-recipe/`
concurrently, and running the full suite risked reading half-written sibling files mid-edit. Only
this task's own new test file was run, standalone, exactly as instructed.

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/task-025-manual-01` (never the real `gsd-benchmark` repo
for the scratch scenarios below — every command used an absolute path, either
`--target /tmp/task-025-manual-01` for the installer, or `--state`/`--ledger`/`REPO_ROOT`-scoped
absolute paths for the standalone `bench/lib/` calls; no `cd` was relied upon to survive across
separate tool calls, per this task's explicit safety requirement). Setup:

```bash
rm -rf /tmp/task-025-manual-01 && mkdir -p /tmp/task-025-manual-01 \
  && git -C /tmp/task-025-manual-01 init -q \
  && git -C /tmp/task-025-manual-01 commit --allow-empty -qm init
```

**Step 1 — real installer execution** (not simulated):

```bash
/Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install-recipe-verify-feature.sh \
  --yes --target /tmp/task-025-manual-01
```

Confirmed for real: `.cursor/skills/recipe-verify-feature/SKILL.md` staged in the scratch repo;
`.gsd-recipe/ledger.json` created there with exactly 1 row under `"recipe-verify-feature"`;
`.gsd-recipe/config.json`/`.planning/` genuinely **not** created by the installer (confirmed by
real `ls`) — exactly as documented (tracker resolution/sync are the staged skill's own runtime
job, not the installer's).

**Step 2 — the tracker-issue-resolution and idempotent-sync mechanics (steps 1 and 5 of the
skill's own workflow), executed for real.** Per this task's explicit instruction not to invoke
`gsd-audit-milestone`, `gsd-audit-uat`, `gsd-verify-work`, or real `gsd-jira-sync`/MCP calls, but to
genuinely exercise the scriptable scaffolding logic — the two `bench/lib/` primitives this skill's
own step 1 and step 5 call directly (`parse-state.sh resolve-issue`, `sync-ledger.sh
key`/`has`/`append`) were run for real, against the real scratch repo, tracing exactly the branches
the staged skill documents:

| Scenario | Real command | Real result |
|---|---|---|
| No `.planning/STATE.md` at all (fail-open trigger) | `parse-state.sh resolve-issue verify_complete --phase 3 --state /tmp/task-025-manual-01/.planning/STATE.md` | **Real exit 1**: `ERROR: STATE.md not found at .../.planning/STATE.md`. Per the skill's own step 1: warn and continue straight to step 2 regardless — confirmed this is a genuine non-zero exit, not a hypothetical. |
| Real `STATE.md` seeded with `## Tracker` (epic `PROJ-100`) + `## Phase tasks` (phase 3 → `PROJ-103`) | `parse-state.sh resolve-issue verify_complete --phase 3 --state <scratch STATE.md>` | **Real exit 0**, resolved issue key: `PROJ-103`. |
| Compute the `verify_complete` idempotency key for that issue/phase | `sync-ledger.sh key verify_complete PROJ-103 --phase 3` | Real output: `gsd-recipe:verify_complete:phase=3:issue=PROJ-103`. |
| Check that key against an empty scratch ledger (before any post) | `sync-ledger.sh has <key> --ledger <scratch ledger>` | **Real exit 1** (not found) — matches the "not yet posted" branch step 5 checks before invoking `gsd-jira-sync`. |
| Simulate the ledger side-effect of a real `gsd-jira-sync verify_complete PROJ-103 --phase 3` post (the MCP call itself traced, not executed — see below) | `sync-ledger.sh append <key> jira --external-id jira-comment-999 --result posted --ledger <scratch ledger>` | Real append succeeded; ledger file now contains one real JSON-line record with `"result": "posted"`. |
| Re-check the same key after the append (idempotency) | `sync-ledger.sh has <key> --ledger <scratch ledger>` | **Real exit 0** (found) — confirms a second `recipe-verify-feature 3` invocation would correctly report `duplicate_skipped` instead of re-posting, exactly as step 5 documents. |

**Step 3 — the three native calls and the `gsd-jira-sync` skill invocation, traced (not
executed), the same way `recipe-bootstrap-knowledge`'s report traced its own 3 native calls.** Per
this task's explicit instruction never to actually invoke `gsd-audit-milestone`, `gsd-audit-uat`,
`gsd-verify-work`, or real `gsd-jira-sync`/MCP calls during verification:

| Native call | What it would do (traced/reasoned, not executed) |
|---|---|
| `gsd-audit-milestone` | Would read `ROADMAP.md`'s milestone DoD and the current `.planning/` state, producing an informational gap-analysis report (per `RUNTIME-LLD.md` §3.a's own table: "Outputs: Gap analysis vs ROADMAP DoD", "Stamps: None"). This scratch repo has no `ROADMAP.md`, so a real invocation here would hit exactly the "not applicable" branch the skill's own step 2 documents — warn and continue to step 3, never a fabricated gap-analysis result. |
| `gsd-audit-uat` | Would cross-check UAT debt across phases already executed in this project (per `RUNTIME-LLD.md` §3.b). This scratch repo has no other executed phases to cross-check, so a real invocation would similarly hit the "not applicable" branch — warn and continue to step 4. |
| `gsd-verify-work 3` | Would open a live conversational UAT exchange with the operator per `docs/GSD-COMMANDS.md`'s own description ("Conversational UAT from SUMMARYs; may create fix plans"). Not scriptable, not simulable outside a real Cursor agent turn where an actual operator answers actual questions — this is the whole point of locked decision #1(c) and the skill's own § C.4/§ D disclaimers. Not attempted here, consistent with the standing project rule that GSD skill invocation is reserved for genuine operator-invoked turns, and with this task's explicit instruction to trace rather than execute it. |
| `gsd-jira-sync verify_complete PROJ-103 --phase 3` (step 5, only after the above conversation genuinely concludes) | Would invoke that skill's own documented single-event workflow: draft a comment body from `.planning/` artifacts, call `addCommentToJiraIssue` via the Atlassian MCP, and run `emit-stamp.sh` (a no-op for `verify_complete` specifically, since `jira-events.json` sets its `stamp` to `null` — the comment still posts, there's simply no KPI stamp tied to this event). Not attempted here — no real Atlassian MCP call, no real Jira issue exists for `PROJ-103` (it is a placeholder key used only for the local idempotency-mechanics trace above). |

**What was truly exercised vs. traced:**

- **Truly executed** (real tool calls, real files, on the scratch repo only): the installer itself
  (staged a real file, wrote a real ledger row, real fail-closed check against a non-git temp
  dir); the fail-open trigger condition (`resolve-issue` genuinely failing non-zero against a
  missing `STATE.md`); the resolved-issue-key path (`resolve-issue` genuinely succeeding against a
  real, hand-seeded `STATE.md`); the full `sync-ledger.sh key`/`has`/`append`/`has` idempotency
  round-trip for the `verify_complete` event — including the genuine before/after `has` exit-code
  flip that proves the duplicate-skip branch would actually fire on a second invocation.
- **Traced/reasoned about, not executed** (per the task's explicit instruction, and this
  environment's inability to spawn a nested Cursor agent turn to run the skill end-to-end as an
  operator would, including the genuinely-interactive `gsd-verify-work` conversation): all three
  native GSD calls (`gsd-audit-milestone`, `gsd-audit-uat`, `gsd-verify-work N`) and the
  `gsd-jira-sync verify_complete` skill-to-skill invocation. None of these were actually invoked —
  consistent with the standing project rule that GSD skill invocation is reserved for genuine
  operator-invoked turns, not test/verification passes.

**Confirmed outcomes for the properties this task's manual verification specifically targeted:**

1. **The installer genuinely stages and ledgers correctly**, and genuinely never touches tracker
   state (`.planning/STATE.md`, `.gsd-recipe/sync-ledger.jsonl`) — confirmed by real `ls`/absence
   checks immediately after a real install run.
2. **The fail-open trigger condition is real, not assumed** — `resolve-issue` against a missing
   `STATE.md` genuinely exits non-zero with a specific, actionable error, matching exactly the
   condition the skill's own step 1 branches on.
3. **The idempotency mechanics for `verify_complete` genuinely hold** — the same `key`/`has` check
   this skill's step 5 uses before ever invoking `gsd-jira-sync` was run twice for real, before and
   after a real `append`, and flipped from "not found" to "found" exactly as required for the
   duplicate-skip guarantee to actually work in practice, not just in the SKILL.md's prose.

Cleaned up afterward: `rm -rf /tmp/task-025-manual-01` (scratch dir only; never touched the real
repo's own filesystem state for any of the scenarios above).

### Self-install into the real repo

As a final, deliberate step — the same expected side effect every prior `recipe-*` installer's
report documents — the installer was also run for real against this repo itself:

```bash
/Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install-recipe-verify-feature.sh \
  --yes --target /Users/vs72964/Projects/gsd-benchmark
```

This staged `.cursor/skills/recipe-verify-feature/SKILL.md` and added exactly one new top-level key
(`"recipe-verify-feature": [".cursor/skills/recipe-verify-feature/SKILL.md"]`) to the shared
`.gsd-recipe/ledger.json` — confirmed by re-reading that file afterward that every pre-existing
sibling-task component key (`fotw-observer`, `recipe-prd-intake`, `tracker-sync`,
`recipe-run-phase`, `recipe-plan-phase`, `recipe-bootstrap-knowledge`, `recipe-install-verify`,
`recipe-run-phases`) is byte-for-byte unchanged. `.gsd-recipe/ledger.json` is not one of the four
files this task was told to avoid editing, and its merge is a targeted per-component JSON key
addition (the same mechanism every prior self-install already used), not a wholesale rewrite.

`git status --porcelain` in the real repo, filtered to just this task's own paths, confirms
exactly the expected new path (the other 3 new files sit under already-untracked parent
directories from this task's own prior untracked state, so they don't surface as separate
top-level entries):

```text
?? .cursor/skills/recipe-verify-feature/
```

Directly confirmed present via `ls` (not `git status`, since their parent directories were already
untracked): `.gsd-recipe/templates/recipe-verify-feature-SKILL.md`,
`.gsd-recipe/scripts/install-recipe-verify-feature.sh`,
`bench/tests/test-install-recipe-verify-feature.sh`.

## Files

- `.gsd-recipe/templates/recipe-verify-feature-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-verify-feature.sh` (new)
- `bench/tests/test-install-recipe-verify-feature.sh` (new, 31 assertions)
- `bench/report/recipe-verify-feature-integration-report.md` (new, this file)
- `.cursor/skills/recipe-verify-feature/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` (self-install side effect, real repo — additive JSON merge only)

**Deliberately NOT edited** (per this task's explicit constraint, sibling tasks concurrently
editing these): `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`. See the snippets below.

## Deviations from the plan

None against the task brief's approved scope. One interpretive judgment call, called out
explicitly rather than glossed over: the task brief's manual-verification instruction to "genuinely
exercise the installer + any scriptable scaffolding logic" was satisfied by running this skill's
own two documented `bench/lib/` calls (`parse-state.sh resolve-issue`, `sync-ledger.sh
key`/`has`/`append`) for real against a hand-seeded scratch `STATE.md` and ledger, since this
skill — unlike `recipe-bootstrap-knowledge`'s `.knowledge/` skeleton scaffolding — has no
independent file-scaffolding logic of its own to exercise; its only scriptable surface besides the
installer is the tracker-resolution/idempotency plumbing it shares with `recipe-plan-phase`/
`recipe-run-phase`. This is the same interpretive approach those two skills' own manual-verification
sections used for their non-native-call steps.

---

## Snippets for the follow-up integration pass

The four snippets below are sized and placed to apply cleanly once TASK-018/026/027 have landed —
each is a straightforward addition alongside the existing 8th-sub-installer
(`recipe-install-verify`) wiring already in these files, following the identical pattern.

### `install.sh`

**1. New path variable** — add immediately after the existing `RECIPE_INSTALL_VERIFY_INSTALLER`
line:

```bash
RECIPE_INSTALL_VERIFY_INSTALLER="$SCRIPT_DIR/install-recipe-install-verify.sh"
RECIPE_VERIFY_FEATURE_INSTALLER="$SCRIPT_DIR/install-recipe-verify-feature.sh"
```

**2. Header comment** — extend the component-separation list (in the top-of-file comment block):

```bash
#   - Ledger-tracked: every file this script *directly* creates is recorded
#     in .gsd-recipe/ledger.json under component "install-core" — separate
#     from "fotw-observer"/"tracker-sync"/"recipe-prd-intake"/
#     "recipe-planning-policy"/"recipe-run-phase"/"recipe-plan-phase"/
#     "recipe-validate-tokens"/"recipe-bootstrap-knowledge"/
#     "recipe-install-verify"/"recipe-verify-feature", which the
#     sub-installers/skills track under their own component names.
```

**3. Consent prompt** — in `install()`, update the `read -r -p` line:

```bash
    read -r -p "Install NetApp GSD recipe scaffold (install-core + observer + tracker-sync + recipe-planning-policy + recipe-run-phase + recipe-plan-phase + recipe-validate-tokens + recipe-bootstrap-knowledge + recipe-install-verify + recipe-verify-feature) into $TARGET? [y/N] " reply
```

**4. Composition call** — in `install()`, update the echo and add the new sub-installer call:

```bash
  echo "install.sh: composing sub-installers (observer, tracker-sync, recipe-planning-policy, recipe-run-phase, recipe-plan-phase, recipe-validate-tokens, recipe-bootstrap-knowledge, recipe-install-verify, recipe-verify-feature)..."
  "$OBSERVER_INSTALLER" --yes --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VALIDATE_TOKENS_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VERIFY_FEATURE_INSTALLER" --yes --target "$TARGET"
```

**5. `verify()`** — add immediately after the existing `recipe-install-verify composed` block:

```bash
  if ledger_has_component "recipe-install-verify"; then
    echo "    recipe-install-verify composed — pass"
  else
    echo "    recipe-install-verify composed — FAIL (recipe-install-verify ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-verify-feature"; then
    echo "    recipe-verify-feature composed — pass"
  else
    echo "    recipe-verify-feature composed — FAIL (recipe-verify-feature ledger component absent)"
    ok=0
  fi
```

**6. `uninstall()`** — add immediately after the existing
`RECIPE_INSTALL_VERIFY_INSTALLER --uninstall` line:

```bash
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_VERIFY_FEATURE_INSTALLER" --uninstall --target "$TARGET"
```

### `test-install.sh`

**1. Fresh-install composition check** — add immediately after the existing
`install.sh composes install-recipe-install-verify.sh` block:

```bash
[ -f "$TARGET1/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "install.sh composes install-recipe-install-verify.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "install.sh composes install-recipe-verify-feature.sh (skill staged)" "$?"
```

**2. Ledger disjointness check** — extend the existing python block (do not duplicate it — add
the new component to the existing asserts, matching how every prior sub-installer addition
extended this same block):

```bash
python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/ledger.json'))
assert 'fotw-observer' in d and d['fotw-observer'], d
assert 'tracker-sync' in d and d['tracker-sync'], d
assert 'recipe-planning-policy' in d and d['recipe-planning-policy'], d
assert 'recipe-run-phase' in d and d['recipe-run-phase'], d
assert 'recipe-plan-phase' in d and d['recipe-plan-phase'], d
assert 'recipe-validate-tokens' in d and d['recipe-validate-tokens'], d
assert 'recipe-bootstrap-knowledge' in d and d['recipe-bootstrap-knowledge'], d
assert 'recipe-install-verify' in d and d['recipe-install-verify'], d
assert 'recipe-verify-feature' in d and d['recipe-verify-feature'], d
assert 'install-core' in d and d['install-core'], d
# install.sh must not re-ledger files the sub-installers already track under
# their own component names.
assert set(d['install-core']).isdisjoint(set(d['fotw-observer'])), d
assert set(d['install-core']).isdisjoint(set(d['tracker-sync'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-planning-policy'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-run-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-plan-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-validate-tokens'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-bootstrap-knowledge'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-install-verify'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-verify-feature'])), d
"
check "ledger separates install-core from fotw-observer/tracker-sync/recipe-planning-policy/recipe-run-phase/recipe-plan-phase/recipe-validate-tokens/recipe-bootstrap-knowledge/recipe-install-verify/recipe-verify-feature components (no cross-tracking)" "$?"
```

**3. `--verify` output mention** — add immediately after the existing
`recipe-install-verify composed — pass` check:

```bash
echo "$VERIFY_OUT1" | grep -q "recipe-install-verify composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-install-verify composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-verify-feature composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-verify-feature composition" "$rc"
```

**4. `--uninstall` cascade check** — add immediately after the existing
`uninstall cascades to install-recipe-install-verify.sh --uninstall` check:

```bash
[ ! -f "$TARGET3/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "uninstall cascades to install-recipe-install-verify.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "uninstall cascades to install-recipe-verify-feature.sh --uninstall" "$?"
```

Net effect once applied: **+3 new assertions** (fresh-stage check, `--verify` mention check,
`--uninstall` cascade check — the ledger-disjointness assertion is extended in place, not
duplicated, same convention every prior sub-installer addition used).

### `BACKLOG.md`

Replace the existing TASK-025 row:

```markdown
| TASK-025 | `recipe-verify-feature` | M | — | [RUNTIME-LLD](lld/RUNTIME-LLD.md) |
```

with:

```markdown
| TASK-025 | `recipe-verify-feature` | M | — | [RUNTIME-LLD](lld/RUNTIME-LLD.md) — **Built**, standalone installer ahead of full `install.sh` composition (composed into it as a 9th sub-installer via a follow-up snippet — this task ran in parallel with TASK-018/026/027 and was constrained from editing `install.sh`/`test-install.sh`/`BACKLOG.md`/`README.md` directly): resolves the phase's tracker issue key, chains native `gsd-audit-milestone` (informational gap analysis vs ROADMAP DoD, no stamp, warn-and-skip if inapplicable) → `gsd-audit-uat` (cross-phase UAT, warn-and-skip if inapplicable) → `gsd-verify-work N` (genuinely conversational/interactive — this skill lets its own back-and-forth with the operator run unscripted) directly in the same turn (Option-B precedent, same reasoning as TASK-017/024/022), then syncs `verify_complete` via `gsd-jira-sync` once that conversation concludes (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked). Bootstrap Gate A/B, the `gsd-debug` recovery loop, and any benchmark/project-specific grader hook stay explicitly out of scope. See [bench/report/recipe-verify-feature-integration-report.md](../../bench/report/recipe-verify-feature-integration-report.md). |
```

### `README.md`

**1. "Built vs spec" table** — add a new row immediately after the existing
`recipe-install-verify` row:

```markdown
| `recipe-verify-feature` skill (TASK-025) | **Built** — narrowed scope: single-phase gate-and-verify wrapper (`.gsd-recipe/scripts/install-recipe-verify-feature.sh`, standalone installer intended to also be composed into `install.sh` as a 9th sub-installer via a follow-up snippet); resolves the phase's tracker issue key, then chains native `gsd-audit-milestone` → `gsd-audit-uat` (each warn-and-skip if inapplicable, never hard-fail, never fabricate a result) → `gsd-verify-work N` directly in the same turn (Option-B precedent); the `gsd-verify-work N` step is explicitly documented as genuinely conversational/interactive — this skill invokes it and then defers entirely to its own live exchange with the operator, never scripting or shortcutting it. Once that conversation concludes, syncs `verify_complete` via `gsd-jira-sync` (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked). Bootstrap Gate A/B, the `gsd-debug` recovery loop, and any benchmark/project-specific grader hook are explicitly out of scope — see [bench/report/recipe-verify-feature-integration-report.md](../../bench/report/recipe-verify-feature-integration-report.md) |
```

**2. Commands table** — add a new row to the **Built** table:

```markdown
| `recipe-verify-feature N` (TASK-025) | Gated single-phase verify wrapper (audit-milestone → audit-uat → conversational verify-work → Jira sync) — [.gsd-recipe/templates/recipe-verify-feature-SKILL.md](../../.gsd-recipe/templates/recipe-verify-feature-SKILL.md) · [report](../../bench/report/recipe-verify-feature-integration-report.md) |
```

No corresponding row needs removing from the **Spec** `recipe-*` table — `recipe-verify-feature`
was never explicitly named there under a different heading, so this is a pure addition, not a
move.
