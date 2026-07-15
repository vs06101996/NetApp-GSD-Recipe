# recipe-prd-intake — standalone PRD intake, wired to the FOTW observer

**Built ahead of its formal dependency, at explicit operator request.** `docs/netapp-recipe/BACKLOG.md` lists TASK-016 (`recipe-prd-intake`) as depending on TASK-010 (`install.sh`, size L — token validation, full directory scaffold, MCP registration, 10-point verification checklist), which is still spec-only. This work bypasses that dependency using the exact standalone-installer pattern already established for the FOTW observer (`bench/report/fotw-observer-install-integration-report.md`), which itself bypassed TASK-010 the same way.

## Why this shape

Two things were true going into this pass:

1. **The actual goal all along was closing the loop:** the FOTW observer's `fotw-observer-bootstrap` skill has been built, tested, and sitting idle since the previous session — nothing calls it. `.cursor/skills/fotw-observer-bootstrap/SKILL.md` even documents its own intended caller-side integration line verbatim: *"After PRD intake completes, invoke the `fotw-observer-bootstrap` skill."* Nothing implemented that caller until now.
2. **Building the full TASK-010 first was assessed as the riskier path.** `install.sh` is sized "L" for a reason — building a "minimal" version of it risked either quietly reabsorbing the full spec's scope, or being so thin it would need rework the moment the real TASK-010 lands. Confirmed with the operator: de-risk by mirroring the observer's own precedent (`INSTALL-LLD.md` Step 3's documented standalone fallback path) instead.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| PRD template | `.gsd-recipe/templates/PRD.template.md` | Canonical source for `.templates/PRD.template.md` (RUNTIME-LLD §1.a's named output format) — Problem, Goals, Non-Goals, Requirements, Out of Scope, Open Questions. Did not exist anywhere in the repo before this pass. |
| Skill | `.gsd-recipe/templates/recipe-prd-intake-SKILL.md` | Source of truth; installer stages a copy to `.cursor/skills/recipe-prd-intake/SKILL.md`. Same `<cursor_skill_adapter>` convention as `fotw-observer-bootstrap/SKILL.md` and `gsd-jira-sync/SKILL.md`. |
| Installer | `.gsd-recipe/scripts/install-recipe-prd-intake.sh` | Standalone, ledger-tracked, idempotent, `--yes`/`--uninstall`/`--target` flags — same structure as `install-observer.sh`. |
| Tests | `bench/tests/test-install-recipe-prd-intake.sh` | 17 assertions (see below). |

### Skill workflow (`recipe-prd-intake`)

1. Accept a PRD file, pasted text, or freeform description from the operator.
2. Fill in `.templates/PRD.template.md`'s sections; ask clarifying questions for anything required and left blank (human gate, per `RUNTIME-LLD.md` §1.a).
3. If no PRD input at all is given, tell the operator to run native `gsd-discuss-phase` first and re-invoke — explicitly not orchestrated programmatically here (keeps this skill's size small, matching `BACKLOG.md`'s own "S" sizing for TASK-016; also preserves the "GSD stays orchestrator" principle from `ARCHITECTURE.md`).
4. Write `docs/PRD.md` — chosen over `.planning/intake/PRD.md` (RUNTIME-LLD allows either) specifically because it's the first path the observer's reactive hook (`.cursor/hooks/fotw-observer-nudge.sh`) already matches on. No hook changes were needed.
5. **Final step, always:** invoke `fotw-observer-bootstrap`. If the observer isn't installed or is disabled, that skill's own `can-spawn` guard silently no-ops — treated as success here, not an error.

This closes the loop described across this session: PRD intake → `recipe-prd-intake` → `fotw-observer-bootstrap` → `can-spawn` guard → background observer subagent.

## Explicitly deferred (do not mistake for oversights)

| Deferred | Why | Real owner |
|---|---|---|
| `.planning/STATE.md` epic-key stamping (RUNTIME-LLD's `Stamps: started @ intake`) | Depends on conventions TASK-002 (`parse-state`) / TASK-008 (`state-tracker.sh`) haven't defined yet. Inventing an ad hoc STATE.md format now would conflict with the real parser later. | TASK-002, TASK-008 |
| `gsd-ingest-docs --manifest` routing for "existing repo docs" intake | Out of scope for a size-S skill; native `gsd-ingest-docs` already exists — operator can run it first and hand the result to this skill as pasted text. | Native GSD (already built) |
| Full TASK-010 `install.sh` | This skill's installer is a narrower, standalone fallback per `INSTALL-LLD.md` Step 3's documented pattern — same choice already made for the observer. | TASK-010 |

## Validation performed

All discovered via testing each level before moving to the next, per operator instruction mid-session ("each level should have some test to identify whether the dev phase was success or no, since it can disrupt later phases"):

| # | Check | Result |
|---|---|---|
| 1 | PRD template has all 6 required section headers | PASS |
| 2 | Skill frontmatter well-formed, `<cursor_skill_adapter>` has all 4 required subsections | PASS |
| 3 | Skill references `fotw-observer-bootstrap` and documents both deferred-scope items | PASS |
| 4 | Installer refuses a non-git target | PASS |
| 5 | Fresh install stages both files, records exactly 2 ledger rows | PASS |
| 6 | Idempotent re-run does not duplicate ledger rows | PASS |
| 7 | Re-install never overwrites an operator-customized `PRD.template.md` | PASS (bug found and fixed — see below) |
| 8 | Uninstall removes the skill, preserves the template, never touches `docs/PRD.md` | PASS (bug found and fixed — see below) |
| 9 | Self-install into a copy of this repo (src==dest collision) does not error, and uninstall preserves canonical template sources | PASS |

**Bug found during step-by-step testing:** the first installer draft's `uninstall()` blindly removed every ledger-tracked file, including `.templates/PRD.template.md` — even after it had been hand-customized by an operator. `install-observer.sh`'s precedent special-cases `observer-config.json` (operator data, always preserved on uninstall) but not its hook script or lib copy (installed code, always removed). `PRD.template.md` is closer to the config category — an operator's customized template is exactly the kind of hand-edited state that shouldn't be silently deleted. Fixed by adding the same "always preserve" special case used for `observer-config.json`. Caught immediately because the installer was tested end-to-end before being marked done, rather than deferring all testing to the end of the plan.

54 (observer) + 17 (this component) = 71 assertions across the full `bench/tests/` suite, all passing after the fix.

## Files

- `.gsd-recipe/templates/PRD.template.md`
- `.gsd-recipe/templates/recipe-prd-intake-SKILL.md`
- `.gsd-recipe/scripts/install-recipe-prd-intake.sh`
- `bench/tests/test-install-recipe-prd-intake.sh`
- Installed into this repo: `.templates/PRD.template.md`, `.cursor/skills/recipe-prd-intake/SKILL.md`, `.gsd-recipe/ledger.json` (component `recipe-prd-intake`)

## First live end-to-end run (2026-07-07, session `dacfd001-6f61-464e-82b1-d728e81f9b37`)

Everything above through "Validation performed" tested *staging* — installer file
placement, hook path matching, `can-spawn` exit codes. It never exercised an LLM
agent actually following `recipe-prd-intake` → `fotw-observer-bootstrap`'s
instructions live, end-to-end, in a real conversation. This run closed that gap.
`tick_interval_seconds` was temporarily lowered from `300` to `20` in
`.gsd-recipe/observer-config.json` beforehand (restored to `300` afterward) so
end-triggers would fire within a reasonable test window.

**What happened, in order:**

1. `recipe-prd-intake` was invoked in this same chat with a freeform description
   ("one-click dashboard PDF export feature"). A complete PRD was drafted against
   `.templates/PRD.template.md`'s section structure (Problem, Goals, Non-Goals,
   Requirements, Out of Scope, Open Questions) and written to `docs/PRD.md` — no
   required section was left underspecified, so the clarifying-question human gate
   (step 3 of the skill's Tool Usage) did not trigger this run.
2. As its final step, `recipe-prd-intake`'s workflow invoked `fotw-observer-bootstrap`
   for real: ran the `can-spawn` guard (`.gsd-recipe/lib/observer-lib.sh can-spawn` —
   exit 0, "allowed"), wrote `.gsd-recipe/.observer-target.json` with this session's
   real `session_id` and `transcript_path`, spawned a real `Task` subagent with
   `subagent_type=generalPurpose`, `run_in_background=true` carrying the
   `fotw-observer-task-prompt.md` instructions, and wrote
   `.gsd-recipe/.observer-active.json`.
3. The background subagent read its inputs, then ran the tick loop for real: **4
   real ticks, 20 seconds apart (actual `sleep 20`, not simulated)**, tailing this
   session's own live transcript file. Tick 1 drained the entire pre-existing
   backlog (offset 0 → 447) and classified all 447 lines: **144 signal → `ticks.jsonl`,
   303 noise (hedge + irrelevant) → `noise-log.jsonl`**. Ticks 2–4 each found zero
   new lines (the transcript only grows at conversation-turn boundaries — see
   "What didn't behave as documented" below) and correctly incremented
   `consecutive_empty_ticks`.
4. Tick 4 hit `inactivity_consecutive_empty_ticks_threshold` (3) and triggered
   **finalize via the `inactivity` end-trigger** — not the `explicit_stop`
   sentinel the test plan called for (see deviation below). Finalize ran 2 more
   margin ticks (both empty, no trailing burst), then read all 5 existing
   playbooks and 3 existing session summaries under `.learnings/kb/` before
   writing anything new (the conflict-check step) — found no cross-session
   contradiction (those files cover an unrelated synthetic fixture from the
   earlier feasibility spike), but did flag one **within-session** contradiction
   inline (the "LLD bundle permanently lost" conclusion, reversed later in the
   same session) into the new session summary.
5. Wrote `.learnings/kb/sessions/dacfd001-2026-07-07.md` (session summary), and
   — since signal count (144) far exceeded `rollup_threshold_signal_lines` (6) —
   proposed two new playbooks: `fotw-observer-trigger-mechanism.md` and
   `netapp-recipe-repo-layers.md`. Removed `.gsd-recipe/.observer-active.json` as
   the last finalize step, confirmed gone.

**Verified working, for real, not just staged:** PRD write → hook-independent
skill-triggered bootstrap → `can-spawn` guard → target descriptor → background
`Task` spawn → multi-tick continuous loop (not one-shot) → classification against
a real transcript → JSONL durability → offset-tracked incremental reads →
finalize → pre-write conflict check against existing KB → session summary +
playbook proposal → active-marker cleanup.

**What didn't behave as the skill docs describe:**

- **Finalize trigger mismatch.** The test plan called for triggering finalize
  explicitly via `touch .learnings/observer/.stop`. In practice, real wall-clock
  time elapsed while polling for tick progress (each tick's classification pass
  itself took real time), and the `inactivity` trigger fired on its own before
  the `.stop` sentinel was touched. This is not a bug — `inactivity` is an
  equally valid, documented end-trigger, and this run incidentally validated it
  instead of `explicit_stop`. The `explicit_stop` path itself remains covered
  only by the earlier synthetic-fixture spike runs and `bench/tests/`, not by
  this live run.
- **Transcript growth is turn-scoped, not tool-call-scoped.** The observer
  subagent's own inspection of the transcript format confirmed intermediate
  tool calls/results within a single long agent turn do not appear as new
  transcript lines until the turn resolves — only user/assistant messages at
  turn boundaries do. During a long, uninterrupted tool-calling turn (like the
  one that ran this very test), the observer will correctly see several
  consecutive empty ticks and may finalize via `inactivity` even though the
  primary agent is actively working, not idle. This is a real characteristic of
  the current design worth flagging for `TASK-013` scoping, not a defect in
  this implementation.
- **First-tick backlog cost.** Because no offset file existed yet, tick 1 had
  to classify the session's entire prior history (447 lines) in one pass rather
  than a small incremental batch — a `bench/tests/fixtures`-only spike would not
  have surfaced this. Real deployments will only hit this once, at first
  install, but it's worth noting for `TASK-013`'s real-world sizing.

Test artifacts from this run were left in place as evidence, per the test plan's
own cleanup note: `docs/PRD.md`, the new `.learnings/kb/sessions/dacfd001-2026-07-07.md`
and two new playbooks, and the grown `.learnings/observer/ticks.jsonl` /
`noise-log.jsonl`. `.gsd-recipe/.observer-target.json` was left in place (not
listed as removed by the finalize spec); `.gsd-recipe/.observer-active.json` was
removed by the subagent itself, as designed.
