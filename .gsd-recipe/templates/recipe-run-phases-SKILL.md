---
name: recipe-run-phases
description: "Recipe: sequential ascending multi-phase loop wrapper for the NetApp GSD recipe (TASK-018; extended TASK-035 with auto-range detection and an optional --full chain). Given a phase range <start> <end> (both optional — auto-detected as [min, max] of every '## Phase N' heading in .planning/ROADMAP.md when omitted), loops phases in ascending order (no DAG topo-sort, parked pending TASK-009) — for each phase N, checks whether PLAN.md already exists (same glob recipe-plan-phase uses for its own first-plan/re-plan determination); if missing, invokes recipe-plan-phase N by name first, then always invokes recipe-run-phase N by name (skill-to-skill Option-B orchestration, not raw native gsd-plan-phase/gsd-execute-phase, and not gsd-autonomous); when --full is passed, also chains recipe-verify-feature N -> recipe-review-ship N -> recipe-settle N per phase before advancing. Stops the whole loop immediately on the first phase whose plan step, run step, or (with --full) verify/review/settle sub-step fails, reporting exactly which phase blocked, at which sub-step, and why. Never duplicates Jira sync — every invoked skill already emits its own tracker events per phase. Prints a soft warn-and-confirm gate showing the full range (and the --full chain, if passed) before starting."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-run-phases`) with:
- `<start>` — first phase number in the range (optional). Omit both `<start>` and `<end>` together
  to auto-detect the full range from `.planning/ROADMAP.md`'s own `## Phase N` headings (see step
  1) — the minimum heading number found becomes `start`, the maximum becomes `end`. Passing only
  one of `<start>`/`<end>` (not both) is an argument error, exactly like an invalid range today —
  stop before the step-3 gate.
- `<end>` — last phase number in the range (optional, same all-or-nothing rule as `<start>`; when
  both are given, `end` must still be `>= start`, inclusive, exactly as before).
- `--full` — optional. When passed, chains `recipe-verify-feature N` → `recipe-review-ship N` →
  `recipe-settle N` (by name, skill-to-skill) immediately after `recipe-run-phase N` reports phase
  `N` complete, before advancing to `N+1` (see step 4.d). Omitted (the default): behavior is
  byte-for-byte identical to before this flag existed — only `recipe-plan-phase`/`recipe-run-phase`
  are ever invoked.

Examples:
- `recipe-run-phases 3 5`
- `recipe-run-phases 3 5 --full`
- `recipe-run-phases` — auto-detects the full range from `.planning/ROADMAP.md`.
- `recipe-run-phases --full` — auto-detects the full range, then chains verify/review/settle per
  phase.

## B. Prerequisites

- None strictly required before invocation — this skill itself decides, per phase, whether a
  `PLAN.md` already exists (see step 4.a), the same informational glob-based check
  `recipe-plan-phase-SKILL.md` already documents for itself. Either outcome per-phase is a valid
  starting state.
- `start` and `end` must both be integers with `end >= start`. Anything else is an argument error —
  stop before printing the step-3 confirmation gate.
- `.planning/STATE.md` may or may not have a tracker section / phase-task rows for any phase in the
  range. This skill never checks that itself — `recipe-plan-phase`/`recipe-run-phase` (and, with
  `--full`, `recipe-verify-feature`/`recipe-review-ship`/`recipe-settle`) each already handle their
  own fail-open tracker-linkage behavior per phase they're invoked for.
- **When both `<start>` and `<end>` are omitted**, `.planning/ROADMAP.md` must exist and contain at
  least one `## Phase N — Title` heading — this becomes a hard prerequisite for auto-detection
  only (step 1). Passing an explicit `<start> <end>` pair never requires `ROADMAP.md` to exist at
  all, exactly as before TASK-035.
- **When `--full` is passed**, CI must eventually go green on the relevant PR/branch for
  `recipe-settle N` (step 4.d) to ever accept and sync `settled` — this skill does not check CI
  itself, informationally or otherwise; it only invokes `recipe-settle N` and treats whatever that
  skill reports as the outcome of that sub-step, the same fail-open, "the invoked skill owns its
  own gate" posture already used for `recipe-plan-phase`/`recipe-run-phase`.

## C. Tool Usage

1. **Determine `start`/`end`.**
   - **Both provided** — use them exactly as given; continue to step 2 unchanged. This is the
     original invocation shape and remains fully backward-compatible: nothing about this step
     changes its behavior.
   - **Exactly one provided** (e.g. only `<start>`) — this is an argument error, the same class as
     an invalid range: report it plainly (e.g. "`<end>` is required when `<start>` is given
     explicitly — pass both, or neither to auto-detect") and stop — do not print the step-3 gate or
     touch anything.
   - **Neither provided — auto-detect the full range from `.planning/ROADMAP.md`.** `Read`
     `.planning/ROADMAP.md`. Collect every line matching the heading grammar
     `bench/runners/create-phase-tasks.sh`'s own comment block documents for its ROADMAP.md phase
     enumeration: `## Phase N — Title` (`N` an integer, optionally followed by an em-dash or hyphen
     and a title — e.g. `## Phase 3 — Payments` or `## Phase 3 - Payments` both count; that
     script's own `PHASE_HEADING`/`ANY_HEADING` regexes are the exact same grammar, applied here by
     hand rather than via a new helper script). Take `start` = the minimum `N` found across all
     matching headings, `end` = the maximum `N` found.
     - If `.planning/ROADMAP.md` doesn't exist, or zero such headings are found — fail closed with
       an actionable error (e.g. "no '## Phase N — Title' headings found in .planning/ROADMAP.md —
       nothing to auto-detect; pass `<start> <end>` explicitly instead") and **stop here** — do not
       proceed to step 2, do not print the step-3 gate, and do not touch anything.
     - Otherwise, continue to step 2 with the detected `start`/`end`, noting in the step-3 gate that
       the range was auto-detected (so the operator can tell at a glance it wasn't typed
       explicitly).

2. **Validate the range.** `start`/`end` (whether explicit from step 1's first branch, or
   auto-detected from its third branch) must both parse as integers with `end >= start`. If not,
   report the specific problem (e.g. "end (2) is less than start (5)") and stop — do not print the
   step-3 gate or touch anything.

3. **Soft warn-and-confirm gate (before touching anything).** Print the full phase list (`start`
   through `end`, inclusive — noting explicitly if it was auto-detected in step 1) and what will
   happen: "For each phase N in [start..end], ascending: if no `PLAN.md` exists yet, invoke
   `recipe-plan-phase N` first, then always invoke `recipe-run-phase N`." When `--full` was passed,
   append: "then also invoke `recipe-verify-feature N` → `recipe-review-ship N` → `recipe-settle
   N`, in that order, before moving on to the next phase." Either way, finish with: "The loop stops
   immediately on the first phase whose plan step, run step, or (with `--full`)
   verify/review/settle sub-step fails." Ask the operator to confirm (yes/no) — this mirrors
   `install.sh`'s own consent-prompt precedent and `recipe-plan-phase`'s/`recipe-run-phase`'s own
   soft-gate precedent. This is a **soft gate**: never a hard, unconditional block — if the
   operator declines, stop here cleanly, nothing has been invoked yet. If they confirm, continue to
   step 4.

4. **For `N = start` to `end`, ascending, one phase at a time** (strictly sequential — no DAG
   topo-sort or dependency-derived reordering; see § D and "Why sequential ascending" below):

   a. **Check whether `PLAN.md` already exists for phase `N`.** `Glob` using the exact same shape
      `recipe-plan-phase-SKILL.md` step 1 documents: `.planning/phases/{NN}-*/*-{NN}-*-PLAN.md`,
      falling back to `.planning/phases/*/*-{NN}-*-PLAN.md` if the padded-prefix directory glob
      finds nothing — where `{NN}` is `N` zero-padded to 2 digits.
      - Found → skip straight to step 4.c (do not invoke `recipe-plan-phase` — a plan already
        exists for this phase).
      - Not found → continue to step 4.b.

   b. **Invoke `recipe-plan-phase N` by name** (skill-to-skill, same turn — read and follow
      `recipe-plan-phase-SKILL.md`'s own full 8-step workflow exactly as documented there:
      first-plan/re-plan determination, issue-key resolution, the direct native `gsd-plan-phase N`
      call, re-resolving `PLAN.md`, the soft post-hoc compliance gate, the `depends_on`/`touches`
      reminder, and the `plan_complete`/`plan_revised` tracker sync). `recipe-run-phases` never
      re-implements any of those steps itself.
      - Once `recipe-plan-phase N` returns, re-`Glob` for phase `N`'s `PLAN.md` using the exact
        same shape as step 4.a.
      - Still not found → **the plan step failed for phase N** (native `gsd-plan-phase` inside that
        call aborted, was declined, or errored — `recipe-plan-phase`'s own step 4 already reports
        this plainly). Stop the whole loop immediately: do not invoke `recipe-run-phase N` for this
        phase, and do not proceed to `N+1`. Record phase `N` as the blocking phase with reason
        `"plan step failed — recipe-plan-phase did not produce a PLAN.md"`, then skip straight to
        step 5 (final summary).
      - Found → continue to step 4.c.

   c. **Invoke `recipe-run-phase N` by name** (skill-to-skill, same turn — read and follow
      `recipe-run-phase-SKILL.md`'s own full 8-step workflow exactly as documented there:
      resolving `PLAN.md`, the soft pre-hoc planning-policy compliance gate, the `depends_on`
      reminder, issue-key resolution, the `execute_started` tracker sync, the direct native
      `gsd-execute-phase N` call, the `execute_complete` tracker sync, and its own one-line
      summary). `recipe-run-phases` never re-implements any of those steps itself, and never passes
      `--wave` (this skill only ever runs a whole phase at a time across the range).
      - **The run step failed for phase N** if any of the following hold: (i) `recipe-run-phase`'s
        own `PLAN.md` resolution unexpectedly fails despite step 4.a/4.b already having confirmed
        one exists (defensive check only — should not normally happen); (ii) the operator declines
        `recipe-run-phase`'s own planning-policy compliance gate, i.e. its own step-8 summary reads
        "operator declined — stopped" and native `gsd-execute-phase N` was never called; or
        (iii) native `gsd-execute-phase N` itself errors, aborts, or reports a failed
        verification/checkpoint partway through. In every one of these cases: stop the whole loop
        immediately, do not proceed to `N+1`. Record phase `N` as the blocking phase with the
        specific reason observed, then skip straight to step 5.
      - Otherwise — `recipe-run-phase` reached its own step-8 summary having actually called native
        `gsd-execute-phase N` and it completed — **phase N is complete.** Record phase `N`'s
        completion (carrying forward both invoked skills' own one-line summaries for the final
        report). If `--full` was **not** passed, loop back to step 4.a for `N+1`, or fall through
        to step 5 if `N` was `end`. If `--full` **was** passed, continue to step 4.d before
        looping.

   d. **(Only when `--full` was passed.) Chain `recipe-verify-feature N` → `recipe-review-ship N`
      → `recipe-settle N` by name, skill-to-skill, in that exact order, in the same turn**, before
      moving on to phase `N+1`. Each is invoked exactly as its own `SKILL.md` documents for a
      standalone call — this skill never re-implements any of their steps, and passes no flags of
      its own to any of the three (`recipe-review-ship N` is called with no `--draft`;
      `recipe-settle N` is called with no `--owner-repo`/`--ref`/`--transition` — an operator who
      needs those should invoke that step manually instead of via `--full`).
      - **`recipe-verify-feature N` failed** if `gsd-verify-work N`'s own live conversational UAT
        (that skill's own step 4) does not conclude with an accepted outcome — i.e. the operator
        and the native command reach a rejected, fix-plans-queued-but-not-accepted, or otherwise
        not-accepted end state. Stop the whole range loop immediately: do not invoke
        `recipe-review-ship N` or `recipe-settle N` for this phase, and do not proceed to `N+1`.
        Record phase `N` as the blocking phase with reason `"--full sub-step failed —
        recipe-verify-feature N: UAT did not conclude accepted"`, then skip straight to step 5.
      - **`recipe-review-ship N` failed** if either of its own two native calls errors or is
        unmet — native `gsd-code-review N` (that skill's own step 1), or native `gsd-ship N` (that
        skill's own step 4, including `gsd-ship` reporting its own unmet prerequisite). Stop the
        whole range loop immediately, same as above. Record phase `N` as the blocking phase with
        reason `"--full sub-step failed — recipe-review-ship N: <the specific native failure
        reported>"`, then skip straight to step 5.
      - **`recipe-settle N` failed/declined** if either of its own two gates does not clear — a CI
        result other than `PASS` (that skill's own step 3 hard block), or a live PO decline on its
        own accept question (that skill's own step 4). Stop the whole range loop immediately, same
        as above. Record phase `N` as the blocking phase with reason `"--full sub-step failed —
        recipe-settle N: CI not green"` or `"--full sub-step failed — recipe-settle N: PO
        declined"` (whichever applies), then skip straight to step 5.
      - Otherwise — all three concluded successfully (verify accepted; review+ship both completed
        with a PR link; settle's CI-`PASS` and PO-accept gates both cleared) — phase `N`'s `--full`
        chain is complete. Record all three skills' own one-line summaries alongside phase `N`'s
        completion for the final report, then loop back to step 4.a for `N+1`, or fall through to
        step 5 if `N` was `end`.

5. **Print the final summary**, always (whether the loop finished the full range or stopped early):
   the list of phases completed successfully (each with the `recipe-plan-phase`/`recipe-run-phase`
   one-line summaries carried forward from steps 4.b/4.c, plus — when `--full` was passed and the
   phase's chain completed — the `recipe-verify-feature`/`recipe-review-ship`/`recipe-settle`
   one-line summaries from step 4.d), and — if the loop stopped early — the exact phase number that
   blocked, which specific sub-step blocked it (plan step / run step / and, with `--full`, verify /
   review / settle), and the specific reason recorded in step 4.b/4.c/4.d. Never invoke
   `gsd-jira-sync` directly from this step or any other step in this skill — every invoked skill
   (`recipe-plan-phase`, `recipe-run-phase`, and, with `--full`, `recipe-verify-feature`,
   `recipe-review-ship`, `recipe-settle`) already syncs its own tracker events per phase (decision
   #4 / § D).

## D. Do NOT

- Do not implement DAG topo-sort, cycle detection, or any dependency-derived execution ordering
  (`RUNTIME-LLD.md` §1.c.2.c / the "auto-loop across phases" framing in §2.b itself) — this skill is
  a strictly sequential ascending phase-number loop over `[start, end]`, parked pending TASK-009's
  `dag-build.sh`, same precedent as `recipe-plan-phase` (TASK-017) and `recipe-run-phase`
  (TASK-024). `depends_on`/`touches` reminders are already printed by the invoked
  `recipe-plan-phase`/`recipe-run-phase` skills themselves per phase — this skill never re-parses,
  re-prints, aggregates, or gates on them, and never reads or writes `.knowledge/dag/*`.
- Do not implement auto-range detection (step 1) via anything other than the documented
  `## Phase N — Title` heading grammar in `.planning/ROADMAP.md` — no DAG involvement, no
  dependency inference, and no fallback to any other source (e.g. `.planning/STATE.md`'s phase-task
  table) to guess a range. If the heading grammar yields nothing, fail closed (step 1) rather than
  falling back to a different detection heuristic.
- Do not call native `gsd-plan-phase`/`gsd-execute-phase`/`gsd-audit-milestone`/`gsd-audit-uat`/
  `gsd-verify-work`/`gsd-code-review`/`gsd-ship` directly, and do not call `gsd-autonomous` —
  always invoke `recipe-plan-phase N` / `recipe-run-phase N` by name (skill-to-skill), and, with
  `--full`, `recipe-verify-feature N` / `recipe-review-ship N` / `recipe-settle N` by name as well,
  per decision #1. This is Option-B same-turn orchestration one level up: the operator's own
  invocation of `recipe-run-phases [start end] [--full]` is itself the "human decided to run this
  range (and, with `--full`, carry it all the way through settle)" gate, the same precedent
  `recipe-plan-phase`'s, `recipe-run-phase`'s, `recipe-verify-feature`'s, `recipe-review-ship`'s,
  and `recipe-settle`'s own direct native calls already established.
- Do not duplicate any Jira sync calls, ever — never invoke `gsd-jira-sync` directly from this
  skill. `plan_complete`/`plan_revised` and `execute_started`/`execute_complete` are already
  emitted by `recipe-plan-phase`/`recipe-run-phase`, per phase, each idempotent via
  `sync-ledger.sh` on their own terms (decision #4); when `--full` is passed, `verify_complete`,
  `review_complete`, and `settled` are likewise already emitted by
  `recipe-verify-feature`/`recipe-review-ship`/`recipe-settle` themselves, on the exact same
  idempotency terms — `--full` adds zero new sync calls of its own. This skill only orchestrates
  the loop and prints a final summary.
- Do not proceed to phase `N+1` once phase `N`'s plan step, run step, or (with `--full`)
  verify/review/settle sub-step has failed — stop immediately and report which phase blocked, at
  which specific sub-step, and why (decision #3). Never silently skip a failed phase and keep going
  with the rest of the range, and never retry a failed phase automatically.
- Do not treat a `--full` sub-step failure or decline (`recipe-verify-feature`/`recipe-review-ship`/
  `recipe-settle` at step 4.d) any differently from a plan-step or run-step failure — same
  unconditional stop-the-loop rule (decision #3), applied a third time to the same three-way
  outcome shape. There is no partial-`--full` state where the loop continues to `N+1` having only
  verified but not shipped, or shipped but not settled, a given phase.
- Do not skip the pre-loop warn-and-confirm gate (step 3), and do not turn it into a hard,
  unconditional block either — soft gate only (decision #5): show the full range (auto-detected or
  explicit) and what will happen (including the `--full` chain, when passed), ask, and either
  proceed on confirm or stop cleanly on decline. There is no code path that starts the loop without
  first showing this gate, and none that refuses outright regardless of what the operator wants.
- Do not re-implement any step `recipe-plan-phase`/`recipe-run-phase`/(with `--full`)
  `recipe-verify-feature`/`recipe-review-ship`/`recipe-settle` already document for
  themselves — first-plan/re-plan determination, issue-key resolution, any of their own
  compliance/CI/PO-accept gates, the `depends_on`/`touches` reminders, or any of their tracker
  syncs. This skill only ever decides (a) *whether* to invoke `recipe-plan-phase N` (based on the
  step-4.a `PLAN.md`-exists check), (b) *when* to invoke `recipe-run-phase N`, (c) *whether* to
  invoke the `--full` chain at all and in what order, and (d) whether to keep looping or stop.
- Do not accept or forward a `--wave` argument — `recipe-run-phase`'s own `--wave W` passthrough is
  a single-phase concern; this skill always runs each phase in the range as a whole.
</cursor_skill_adapter>

# recipe-run-phases — sequential ascending multi-phase loop (TASK-018, extended TASK-035)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §2.b "Auto-loop across phases", tag
**[N]** for the underlying per-phase native calls made indirectly via the invoked skills, **[C]**
for this wrapper's loop/gating layer) — GSD stays the orchestrator for each individual phase; this
skill adds a strictly sequential ascending phase-range loop (optionally auto-detected from
`ROADMAP.md`'s own `## Phase N` headings when no explicit range is given) that decides, per phase,
whether to invoke `recipe-plan-phase` first, always invokes `recipe-run-phase`, optionally (with
`--full`) chains `recipe-verify-feature` → `recipe-review-ship` → `recipe-settle` on top of that,
and stops the whole loop on the first failure at any of these steps.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §2.b, §3, §4 · `docs/netapp-recipe/BACKLOG.md`
TASK-018 (extended TASK-035).

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) ahead of the full `install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-run-phases.sh`, and is designed to also be composed into
`install.sh` as a ninth sub-installer (deferred snippet, not applied by this task — see the
integration report). TASK-035 extends this same skill's content in place — no new installer, no
new staged path; re-running the existing installer re-stages the updated `SKILL.md` unchanged.

## Workflow

1. Determine `start`/`end`: use them as given if both provided (unchanged from before TASK-035);
   argument error if only one is given; auto-detect from `.planning/ROADMAP.md`'s own
   `## Phase N — Title` headings (min/max across all matches) if neither is given — fail closed if
   `ROADMAP.md` is missing or has no such headings.
2. Validate `start`/`end` (integers, `end >= start`). Invalid → report and stop, no gate shown.
3. Print a soft warn-and-confirm gate showing the full `[start, end]` range (noting if it was
   auto-detected) and what the loop will do, including the `--full` chain when passed. Decline →
   stop cleanly, nothing invoked. Confirm → continue.
4. For each phase `N` from `start` to `end`, ascending:
   a. Glob for `N`'s `PLAN.md` (same shape `recipe-plan-phase` uses for its own first-plan/re-plan
      determination).
   b. Missing → invoke `recipe-plan-phase N` by name, then re-glob. Still missing → **plan step
      failed**, stop the loop, report the blocking phase and reason.
   c. Always invoke `recipe-run-phase N` by name once a `PLAN.md` is confirmed present. If it stops
      early (its own gate declined, or native `gsd-execute-phase` errors) → **run step failed**,
      stop the loop, report the blocking phase and reason. Otherwise phase `N` is complete.
   d. **Only when `--full` was passed:** chain `recipe-verify-feature N` → `recipe-review-ship N` →
      `recipe-settle N` by name, in that order. Any of the three failing or being declined → stop
      the loop, report the blocking phase, which of the three sub-steps, and why. Otherwise phase
      `N`'s full chain is complete — continue to `N+1`.
5. Print a final summary: phases completed (with their own carried-forward one-line summaries), and
   — if the loop stopped early — exactly which phase blocked, at which step (and, with `--full`,
   which sub-step), and why.

## Why Option B (direct same-turn skill-to-skill invocation), not a DAG-ordered or background/async loop

Decision #1 (approved this session): the operator's own act of invoking `recipe-run-phases [<start>
<end>] [--full]` already is the "human decided to run this range" gate — the same precedent
`recipe-plan-phase`'s direct call to native `gsd-plan-phase` and `recipe-run-phase`'s direct call to
native `gsd-execute-phase` already established. This skill is the third `recipe-*` skill in the
`RUNTIME-LLD.md` §1.c/§2.a/§2.b lineage to apply that same already-approved precedent, one level up:
instead of calling a native GSD command directly, it calls sibling wrapper skills directly, by
name, in the same turn — `recipe-plan-phase N` and `recipe-run-phase N` always, and, when `--full`
is passed (TASK-035), also `recipe-verify-feature N`, `recipe-review-ship N`, and `recipe-settle N`
— rather than either dropping to raw native `gsd-plan-phase`/`gsd-execute-phase`/
`gsd-audit-milestone`/`gsd-audit-uat`/`gsd-verify-work`/`gsd-code-review`/`gsd-ship` (which would
bypass the sibling skills' own gating/tracker-sync layers entirely) or invoking `gsd-autonomous`
(which is GSD's own unattended-autonomy primitive, explicitly not what this recipe wraps — see "Why
sequential ascending" below).

## Why sequential ascending, not a DAG topo-sort (Option B, not the DAG-ordered alternative)

`RUNTIME-LLD.md` §2.b frames this row as "Auto-loop across phases" and shows `gsd-autonomous --from
3 --to 5` as the native command it wraps conceptually — but this recipe never calls
`gsd-autonomous` itself, and never derives execution order from a dependency graph. Decision #6
(approved this session): DAG eligibility gating and `depends_on`/`touches` handling stay explicitly
out of scope here, the same parked-pending-TASK-009 precedent `recipe-plan-phase` and
`recipe-run-phase` already established for themselves. `recipe-run-phases` only ever walks
`[start, end]` in plain ascending numeric order — it is the operator's own job to pass a range that
already respects whatever dependencies exist between those phases (each invoked skill still prints
its own `depends_on`/`touches` reminder per phase, informationally, exactly as it always does; this
skill just never aggregates or acts on those reminders itself).

Decision #7 (approved this session, TASK-035): the same reasoning extends to auto-range detection
(step 1) — the detected `[start, end]` comes solely from `.planning/ROADMAP.md`'s own heading
numbers (plain min/max across every `## Phase N — Title` match), never from a dependency graph or
any other inference. The operator remains just as responsible for whether that plain numeric range
respects `depends_on` ordering as they already are when passing an explicit range — auto-detection
only removes the need to type the numbers, it does not add any dependency-aware reasoning on top of
them.

## Why plan-existence, not the sibling skills' own soft-gate outcomes, decides pass/fail for the loop

`recipe-plan-phase`'s post-hoc compliance gate and `recipe-run-phase`'s pre-hoc compliance gate are
each about the *quality* of a plan (7 mandatory sections + a filled Prerequisites table) — a
concern this skill deliberately does not re-adjudicate. What `recipe-run-phases` needs to know,
per phase, is much narrower: did the plan step leave behind a real `PLAN.md` to execute against
(step 4.b), and did the run step actually reach native `gsd-execute-phase` and have it complete
(step 4.c)? A soft-gate *decline* inside `recipe-plan-phase` (declining its post-hoc confirm before
the tracker stamp) does not delete the `PLAN.md` `gsd-plan-phase` already produced — so it does not,
by itself, fail the loop's plan step; only a `PLAN.md` that genuinely still doesn't exist after the
call does. A soft-gate decline inside `recipe-run-phase`, by contrast, means native
`gsd-execute-phase` was never called at all for that phase — so it does fail the loop's run step,
per decision #3. This asymmetry is intentional, not an oversight: it mirrors exactly which stop
condition each sibling skill's own "Fail-open behavior" section already documents as the one that
leaves nothing usable behind for the next step to consume.

The same principle extends to the three `--full` sub-steps (step 4.d, TASK-035): each of
`recipe-verify-feature`/`recipe-review-ship`/`recipe-settle` already defines its own narrow stop
condition in its own `SKILL.md` (an unaccepted `gsd-verify-work` conversation; a `gsd-code-review`
error or an unmet `gsd-ship` prerequisite; a CI result short of `PASS`, or a live PO decline).
`recipe-run-phases` does not re-derive or second-guess any of those definitions — it only asks,
after each call returns, whether that specific sibling skill's own documented "did this genuinely
conclude successfully" condition held, exactly the same shape of question steps 4.b/4.c already ask
of `recipe-plan-phase`/`recipe-run-phase`.

## What this does NOT do (see the integration report for the full rationale)

- **No DAG topo-sort/cycle-detection, no DAG eligibility gating.** `RUNTIME-LLD.md` §1.c.2.a/b/c and
  the very "auto-loop" framing of §2.b itself all depend on TASK-009's `dag-build.sh`, which is
  parked per `DECISIONS.md` ("Not required for v1"). This skill never reads or writes
  `.knowledge/dag/*`, and never reorders `[start, end]` — it is always plain ascending.
- **No native GSD calls, no `gsd-autonomous`.** Every native call happens strictly inside the
  invoked skills' own documented workflows; `recipe-run-phases` itself only ever invokes
  `recipe-plan-phase`/`recipe-run-phase` (and, with `--full`, `recipe-verify-feature`/
  `recipe-review-ship`/`recipe-settle`) by name. `gsd-autonomous --from N --to M`/`--converge`
  (shown in `RUNTIME-LLD.md` §2.b's own command block) is a different, GSD-native
  unattended-autonomy primitive this recipe does not wrap or invoke.
- **No duplicated Jira sync.** `plan_complete`/`plan_revised`/`execute_started`/`execute_complete`
  are emitted exactly once per phase by `recipe-plan-phase`/`recipe-run-phase`; when `--full` is
  passed, `verify_complete`/`review_complete`/`settled` are likewise emitted exactly once per phase
  by `recipe-verify-feature`/`recipe-review-ship`/`recipe-settle` — each exactly as it already is
  when that sibling skill is invoked standalone. `recipe-run-phases` adds zero additional tracker
  calls of its own, with or without `--full`.
- **No `--wave` passthrough, no `execute_wave` handling.** Those stay `recipe-run-phase`'s own
  single-phase concern; this skill always runs a phase as a whole.
- **No automatic retry of a failed phase**, and no continuing past it. The loop stops, full stop,
  on the first plan-step, run-step, or (with `--full`) verify/review/settle sub-step failure — the
  operator decides what to do next (fix the plan, fix the code, address the review/CI feedback, or
  re-invoke `recipe-run-phases` starting from the blocked phase once ready).
- **No default-on `--full`.** Omitting the flag is byte-for-byte identical to this skill's behavior
  before TASK-035 — only `recipe-plan-phase`/`recipe-run-phase` are ever invoked unless the
  operator explicitly passes `--full`.
- **No auto-range detection beyond the documented heading grammar.** Step 1 only ever reads
  `## Phase N — Title` headings from `.planning/ROADMAP.md`; it never falls back to
  `.planning/STATE.md`'s phase-task table, a DAG, or any other source to guess a range.

## Stop-on-failure behavior (the one hard rule in an otherwise soft-gated skill)

Every gate in this skill and its invoked siblings is soft (warn-and-confirm, never a hard,
unconditional block) — except the loop's own stop-on-failure rule itself, which is unconditional
once a phase's plan step, run step, or (with `--full`, TASK-035) verify/review/settle sub-step has
genuinely failed per step 4.b/4.c/4.d's definitions: the loop never proceeds to `N+1` after that
point, no matter what. This is decision #3, and it is deliberately not itself a soft/confirmable
gate — a partially-broken phase left behind mid-range with no plan, no successful execution, or (in
the `--full` case) no completed verify/ship/settle chain is not a safe state to build on top of for
the next phase, so there is no "continue anyway?" prompt here the way there is for the
Prerequisites-table compliance gates. The `--full` sub-steps do not soften this rule or add a
"partial success" state — they extend the exact same unconditional stop condition to three more
possible failure points per phase, nothing more.
