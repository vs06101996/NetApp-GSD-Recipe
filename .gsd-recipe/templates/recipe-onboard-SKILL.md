---
name: recipe-onboard
description: "Recipe: single onboarding orchestrator. An explicit PRD source starts a fresh cycle on a new initiative branch by default, isolating all prior planning and tracker state. Use --no-branch for archive-in-place. Without a source, resume artifact-aware onboarding."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-onboard`) with:
- A PRD source (optional) — Jira issue key or browse URL, Jira/Confluence export, file path,
  pasted text, or a freeform description. Supplying a source explicitly means **start a new
  onboarding cycle**. Existing branch-local recipe context is archived and switched out before
  intake; it is never used to decide or build the new roadmap. An existing file is read into
  memory before switch-out so it remains valid even when it is under `docs/`.
  A Jira key/URL that is also an existing file path is a **file**.
- `--branch NAME` — optional fresh-onboarding override for the new initiative branch.
  Without it, derive `feat/<feature-title>[-<Ticket>]` (or `fix/...` with `--fix`) via
  `.gsd-recipe/lib/derive-initiative-branch.sh`. Validate with `git check-ref-format`;
  never silently add a numeric suffix.
- `--fix` — optional. Use the `fix/` prefix instead of `feat/` when deriving the branch.
- `--no-branch` — optional fresh-onboarding escape hatch. Stay on the current branch and
  archive the prior initiative in place before intake. This retains TASK-054 behavior for
  operators who deliberately do not want an initiative branch.
- `--project KEY` / `--issue-type NAME` / `--assignee NAME` / `--force` — optional. Forwarded
  verbatim to `recipe-create-epic` (and `--assignee` also to `recipe-create-phase-tasks`) when
  those steps actually **create** issues. `--force` is also forwarded to `init-tracker` on the
  existing-ticket link path when STATE already names a different epic.
- `--skip-tracker` — optional. Light path (TASK-042): skip Epic creation, existing-ticket
  linking, and phase-task creation even if those artifacts are missing. A Jira key/URL still
  feeds PRD intake. PRD intake, project bootstrap, and knowledge bootstrap still run when needed.
  After those succeed, merge `"onboard": {"skip_tracker": true}` into `.gsd-recipe/config.json`
  (do not invent an Epic key in `.planning/STATE.md`). The full Jira path stays the default;
  knowledge is mandatory on both paths.

Examples:
- `recipe-onboard` — no PRD source given; onboard whatever is missing, asking for PRD input live
  if that step is reached and nothing was provided.
- `recipe-onboard KAN-53` or `recipe-onboard https://netapp.atlassian.net/browse/KAN-53` —
  switch out any prior active recipe context, fetch the ticket for PRD intake, then **link**
  that key into STATE (do not create a second Epic). Skip automatic phase-task creation.
- `recipe-onboard docs/PRD.md` — already-written PRD file; skips intake's own file/paste/freeform
  question if that step runs.
- `recipe-onboard docs/PRD.md --branch feat/object-store-reconcile-KAN-53` — choose the initiative branch.
- `recipe-onboard "Null pointer in ingest" --fix --skip-tracker` — derive `fix/<title>`.
- `recipe-onboard docs/PRD.md --no-branch` — archive and restart on the current branch.
- `recipe-onboard --skip-tracker` — PRD + `.planning/` + knowledge; no Jira Epic, link, or phase tasks.
- `recipe-onboard --project KAN --assignee "Ada Lovelace"` — skips the live Jira-project question if the Epic **create** step runs; assigns created tickets.

## B. Prerequisites

- Cursor GSD full profile must be installed (the recipe installer installs/verifies it by default).
- None of the project artifacts are required before invocation — this skill's first phase (§ C step 1) is
  determining, per artifact, whether a prerequisite is already satisfied. Any combination of
  present/missing artifacts across the five steps is a valid starting state, including "all five
  already present" (in which case the preview gate shows an all-skip plan and nothing is invoked).
- Atlassian MCP enabled and authenticated — needed if the PRD source is a Jira issue key/URL
  (intake fetch), or if Epic **create** / phase-task steps actually run. Not needed for
  `--skip-tracker` unless the PRD source is a live Jira ticket.
  Empty tool discovery is inconclusive for an idle-suspended transport: invoke the known
  `getAccessibleAtlassianResources` operation once to wake it and retry. Only a real invocation
  failure means Jira is unavailable.
- `recipe-workspace` runtimes staged at `.gsd-recipe/lib/workspace-swap.sh`,
  `.gsd-recipe/lib/initiative-branch.sh`, `.gsd-recipe/lib/derive-initiative-branch.sh`,
  and `.gsd-recipe/lib/recipe-gitignore.sh` when an explicit PRD source is supplied. Re-run
  `recipe-update` / recipe install if missing; never fall back to deleting prior state directly.

## C. Tool Usage

1. **Determine mode and inspect active artifacts — read-only, no gate yet.**
   - If the operator supplied a PRD source, set **fresh-onboarding mode**. For a file source,
     `Read` and retain its contents now, before any switch-out. Do not classify recipe flags
     (`--skip-tracker`, `--project`, etc.) as a PRD source.
     - Unless `--no-branch` was passed, set **initiative-branch mode**. Resolve a branch:
       use `--branch NAME` verbatim when present; otherwise run
       `.gsd-recipe/lib/derive-initiative-branch.sh` with `--kind feat` (or `--kind fix` when
       `--fix` was passed), `--ticket <KEY>` for Jira input, `--file <path>` for a file, and/or
       `--title <concise-title>` for pasted/freeform input. The derived name is
       `feat|fix/<feature-title>[-<Ticket>]`. Do not invent a `gsd/` prefix.
     - Run `.gsd-recipe/lib/initiative-branch.sh validate <branch> --target <root>` during
       reconnaissance and retain the base ref it reports. From `main`/`master`, the base is the
       current branch; from an initiative branch, it resolves `origin/HEAD`, then local
       `main`/`master`. This prevents initiative 2 / PR 2 from inheriting initiative 1 / PR 1.
       A dirty product worktree, tracked initiative-local artifacts, detached
       HEAD, existing local/remote branch, invalid branch name, or missing workspace runtime is
       a hard pre-preview failure. Do not stash, discard, reuse an existing branch, or invent
       a suffix. Recipe-install dirt is not product work: `.gitignore` (recipe ignore
       lines), `.cursor/hooks.json`, recipe hook scripts, and `.cursor/rules/recipe-*`.
   - If no PRD source was supplied, set **resume mode**. Existing artifacts may be skipped
     idempotently as documented below.
   - `Glob`/`Read` for `docs/PRD.md`. Present → step 2 ("PRD intake") will be **skipped**. Missing →
     step 2 will **run**.
   - `Glob`/`Read` for `.planning/ROADMAP.md`. Present → step 3 ("project bootstrap") will be
     **skipped**. Missing → step 3 will **run**.
   - Resolve `bench/lib/parse-state.sh` via `.gsd-recipe/scripts/recipe-paths.sh resolve` (same
     mechanism `recipe-create-epic-SKILL.md` § C step 2 documents in full) and run
     `get-tracker --state .planning/STATE.md`. A non-empty `epic` field → step 4 ("Epic creation")
     will be **skipped**. Missing/empty (including when `.planning/STATE.md` doesn't exist yet) →
     step 4 will **run** — *unless* step 3 above is also going to run, in which case step 4's
     eligibility can't be determined until step 3 actually produces a `ROADMAP.md`; note this
     dependency in the preview (step 1e below) rather than resolving it early.
   - If step 4 is not going to run (an Epic is already linked) or step 3 will run first: resolve
     `bench/runners/create-phase-tasks.sh` the same way, run its `list` subcommand, and check
     whether it reports zero pending phase-task rows. Zero pending → step 5 ("phase-task creation")
     will be **skipped**. One or more pending (or `list` itself fails closed because no Epic is
     linked yet, or `ROADMAP.md` doesn't exist yet) → step 5 will **run**.
   - Read `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`. Valid JSON with `status: "ready"` → the final
     "knowledge bootstrap" step will be **skipped**. Missing, invalid, or any other status → it
     will **run**. The install-time `.knowledge/index.md` skeleton does not satisfy this check.
     Prefer running `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` for the skip/run
     decision — it also requires map + graph artifacts and rejects no-op graphify stubs.
   - Detect **existing-ticket mode**: if a PRD source was given, it is not an existing file path,
     and it parses as a Jira issue key or browse URL (run `bench/lib/parse-jira-issue-ref.sh`
     via `recipe-paths.sh resolve` when possible; else the same regex rules as that script),
     set existing-ticket mode with `KEY` and optional browse `URL`. File paths win over keys.
   - In fresh-onboarding mode, prior active context includes `.planning/`, `.gsd/`, untracked
     `docs/PRD.md` / `docs/PRD-*.md`, `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`,
     `.gsd-recipe/phase-tasks-queue.jsonl`, `.gsd-recipe/sync-ledger.jsonl`, and
     `onboard.skip_tracker`. All artifact-derived skip decisions belong to the old cycle and
     must not be used for the new cycle. In `--no-branch` mode, mark **archive-in-place** when
     any prior context exists. Initiative-branch mode snapshots the current branch even when
     there is no prior context and never also invokes archive.
   - This step never writes anything and never asks the operator anything yet — it is purely
     read-only reconnaissance for the single preview gate in step 2 below.

2. **Single soft preview-then-confirm gate — before invoking anything.**
   In fresh-onboarding mode, begin the preview with:
   - current branch;
   - in initiative-branch mode, the exact new branch, resolved base ref, and prior active paths that will be
     snapshotted under `.gsd-recipe/workspaces/<current-branch>/` before the new branch starts
     clean;
   - in `--no-branch` mode, prior active paths that will be archived under
     `.gsd-recipe/workspace-archives/<branch>/<run-id>/` and cleared;
   - that recipe `.gitignore` entries will be re-applied **after** the initiative
     boundary (additive). Do not treat the current branch's `.gitignore` as proof the
     new trunk-based branch has them — last PR's ignore updates may be unmerged.
   - explicit statement that the prior PRD, ROADMAP, STATE, plans, summaries, phase keys, and
     GSD runtime state, tracker queue/ledger, and knowledge-ready marker will **not** be reused.
   Then print, plainly, all five
   steps in their fixed order (PRD intake → project bootstrap → Epic creation → phase-task
   creation → knowledge bootstrap) and, for each, whether it will **run** or **skip** (and why — e.g. "skip: docs/PRD.md
   already exists"). When `--skip-tracker` was passed, print Epic and phase-task steps as **skip (flag:
   --skip-tracker)** — not provisional "will run". When existing-ticket mode is on and
   `--skip-tracker` was *not* passed, print Epic as **skip (link existing KEY; do not create)** and
   phase-task as **skip (existing ticket; run `recipe-create-phase-tasks` later if this issue is
   an Epic)**. When `--skip-tracker` was *not* passed and existing-ticket mode is off, add one
   line: "No Jira this time: `recipe-onboard --skip-tracker`." When project bootstrap will run and tracker
   steps are not skipped by flag or existing-ticket mode, note explicitly that Epic/phase-task
   skip/run determination is provisional until bootstrap completes (their `ROADMAP.md`/`STATE.md`
   inputs don't exist yet to check). Ask the operator to confirm (yes/no) — one gate for the whole
   chain, not nested per-step gates (see "Why one preview gate" below). In fresh-onboarding
   mode PRD intake and project bootstrap show **run (new cycle)** regardless of old artifacts.
   - **Decline** → stop here entirely. Nothing has been invoked. Report "operator declined —
     onboarding not run" as the final summary.
   - **Confirm, initiative-branch mode** → run:
     ```
     "$ROOT/.gsd-recipe/lib/initiative-branch.sh" create "$BRANCH" --target "$ROOT"
     ```
     A non-zero result is a hard failure: stop before intake. This helper explicitly snapshots
     the current branch, creates the branch, restores/clears its independent initiative state,
     and rolls back if initialization fails. Verify `git branch --show-current` equals the
     requested branch and that none of the old initiative-local paths remain active. Never also
     run `archive` in this mode. Then continue to step 2c.
   - **Confirm, `--no-branch` mode** → if archive-in-place was marked, resolve
     `.gsd-recipe/lib/workspace-swap.sh` and run:
     ```
     "$LIB" archive "$(git rev-parse --abbrev-ref HEAD)" --target "$(git rev-parse --show-toplevel)"
     ```
     A missing lib or non-zero archive is a hard failure: stop before intake. Never `rm` the
     old context as a fallback. The archive command also removes stale tracker queue/ledger and
     `onboard.skip_tracker`.
     Then continue to step 2c.
   - **Confirm, resume mode** → continue to step 2c.

2c. **Recipe `.gitignore` ensure — every onboard, after the initiative boundary.**
    The new branch is based on trunk, so ignore lines from an unmerged previous initiative
    PR will not be present. Run:
    ```
    "$ROOT/.gsd-recipe/lib/recipe-gitignore.sh" ensure --target "$ROOT"
    ```
    Additive only: append missing recipe lines, never delete or rewrite existing ignores.
    Missing helper is a hard failure: stop before intake. Do not commit `.gitignore` here;
    it rides with the initiative's later commits/PR. Then continue to step 3. Also note in
    the preview (not a sixth confirmable step):
     once `docs/PRD.md` exists, this chain will invoke `fotw-observer-bootstrap` even if PRD
     intake is skipped.

3. **Step "PRD intake" — in fresh-onboarding mode, always run; in resume mode, only if
   step 1 determined `docs/PRD.md` is missing.** Invoke
   `recipe-prd-intake` by name (skill-to-skill, same turn), forwarding whatever PRD source was
   given to this invocation (Jira key/URL / preloaded file text / pasted text / freeform description), or nothing if none
   was given (that skill's own "no PRD" fallback then applies — see its § D). Follow
   `recipe-prd-intake-SKILL.md`'s own full documented workflow exactly, including its own
   clarifying-question human gate for underspecified required sections.
   - `docs/PRD.md` still doesn't exist after this call returns → **this step failed.** Stop the
     whole chain immediately. Record "PRD intake" as the blocking step with reason
     "recipe-prd-intake did not produce docs/PRD.md", then print the final summary.
   - `docs/PRD.md` now exists → continue to the FOTW observer hook (next), then step 4.
   - **Resume mode only, if step 1 determined this step should skip:** do not invoke `recipe-prd-intake` at all;
     still run the FOTW observer hook below, then continue to step 4.

3b. **FOTW observer hook — once `docs/PRD.md` exists, whether intake ran or was skipped.**
    Invoke `fotw-observer-bootstrap` by name (skill-to-skill, same turn). Do not inline its
    guard, target-descriptor write, or `Task` spawn — that skill owns `can-spawn` and will
    no-op when the observer is uninstalled, disabled, or already active for this session.
    Treat any no-op as **success for this chain**, not a blocking failure. This closes the
    gap where skipping PRD intake (because `docs/PRD.md` already existed) never started the
    observer. If intake just ran, a second invoke in the same turn is expected and harmless.

4. **Step "project bootstrap" — in fresh-onboarding mode, always run; in resume mode, only
   if step 1 determined `.planning/ROADMAP.md` is missing.**
   Invoke `recipe-new-project` by name (skill-to-skill, same turn) if it is staged at
   `.cursor/skills/recipe-new-project/SKILL.md` in this repo — follow its own documented workflow
   exactly (first-init-vs-re-init routing, `docs/PRD.md`-as-input preference, native
   `gsd-new-project`/`gsd-import` call, re-verification). **If `recipe-new-project` is not staged**
   (it is a separate, independently-installed skill, TASK-036 — this is a real, currently-common
   state, not an error condition), fall back to calling native `gsd-new-project` directly in this
   same turn instead, preferring `docs/PRD.md` as its input when present (same preference
   `recipe-new-project` itself documents) — this is the one and only step in this skill's chain
   where a native GSD call is made directly, and only as an explicit, narrow fallback for a sibling
   skill that may not exist yet on a given install.
   - `.planning/ROADMAP.md` still doesn't exist after this call returns → **this step failed.**
     Stop the whole chain immediately: do not invoke tracker or knowledge steps. Record "project bootstrap" as the
     blocking step with reason "neither recipe-new-project nor native gsd-new-project produced
     .planning/ROADMAP.md", then print the final summary.
   - `.planning/ROADMAP.md` now exists → run
     `.gsd-recipe/scripts/recipe-enable-defaults.sh --target .` (circuit breaker: tries
     `workflow.tdd_mode` and `graphify.enabled`; never fail onboard if it cannot set them). Then if
     `--skip-tracker` was passed, skip re-checking Epic/phase tasks and continue to the skip-tracker
     persistence step below. Otherwise re-run step 1's Epic/phase-task checks (they were provisional
     per step 1's own note) before continuing to step 5.
   - **Resume mode only, if step 1 determined this step should skip:** still run
     `recipe-enable-defaults.sh` if `.planning/ROADMAP.md` exists (same circuit breaker). Do not
     invoke `recipe-new-project`; continue straight to step 5 with step 1's original
     (non-provisional) determination for steps 5/6 (or persistence when `--skip-tracker`).

5. **Step "Epic creation / existing-ticket link"**
   - **`--skip-tracker`:** skip entirely (flag); do not invoke `recipe-create-epic` and do not
     `init-tracker`. Continue to step 6.
   - **Existing-ticket mode (no `--skip-tracker`):** do **not** invoke `recipe-create-epic`. After
     `.planning/ROADMAP.md` exists (step 4 succeeded or was already present), link the fetched key:
     1. If browse `URL` is empty, build `https://<site>/browse/<KEY>` from Atlassian resource
        metadata / the issue URL host — never guess a hostname.
     2. Resolve `bench/lib/parse-state.sh` via `recipe-paths.sh`. `Shell`:
        ```
        "$RESOLVED" init-tracker --epic <KEY> --system jira --url <URL> \
          --run-id <date-slug> --arm recipe --state .planning/STATE.md [--force]
        ```
        Pass `--force` only when this invocation included `--force` **and** `get-tracker` already
        names a different epic. Identical key → idempotent success.
     3. `init-tracker` non-zero → **this step failed.** Stop; do not invent a key.
     4. Invoke `gsd-jira-sync intake_started <KEY>` by name (create-epic is skipped, so this
        chain owns that one sync). Do not call `addCommentToJiraIssue` directly.
     Record the step as **completed (linked existing KEY)**. Continue to step 6.
   - **Otherwise** (create path): only if the (possibly re-checked, per step 4) determination is
     that no Jira Epic is linked yet: invoke `recipe-create-epic` by name
   (skill-to-skill, same turn), forwarding `--project`/`--issue-type`/`--force` exactly as given to
   this invocation (or omitted, letting `recipe-create-epic`'s own live MCP questions run). Follow
   `recipe-create-epic-SKILL.md`'s own full 9-step documented workflow exactly, including its own
   fail-closed check on `docs/PRD.md` (already guaranteed present by this point via step 3) and its
   own soft confirm gate immediately before creating anything remote.
   - `parse-state.sh get-tracker` still reports no non-empty `epic` field after this call returns
     → **this step failed.** Stop the whole chain immediately: do not invoke step 6. Record "Epic
     creation" as the blocking step with the specific reason `recipe-create-epic` itself reported
     (e.g. "operator declined the confirm gate", "no Jira project resolved"), then print the final
     summary without running knowledge.
   - An Epic is now linked → continue to step 6.
   - **If skipped** (already linked, and not existing-ticket relink): do not invoke anything;
     continue straight to step 6.

6. **Step "phase-task creation" — skip entirely when `--skip-tracker` was passed** (record skipped
   (flag); do not invoke `recipe-create-phase-tasks`) **or when existing-ticket mode is on**
   (record skipped: existing ticket may not be an Epic; operator can run
   `recipe-create-phase-tasks` later). Otherwise, only if the (possibly re-checked)
   determination is that one or more `ROADMAP.md` phases have no linked Jira sub-task yet: invoke
   `recipe-create-phase-tasks` by name (skill-to-skill, same turn) with no arguments of its own.
   Follow `recipe-create-phase-tasks-SKILL.md`'s own full documented workflow exactly (detect → list
   → issue-type resolution → confirm gate → per-row create+link → mark-done/mark-failed).
   - Any row in that skill's own final summary reports `mark-failed` → **this step failed.**
     Stop before knowledge bootstrap and report the failed rows in the final summary.
   - Otherwise — all pending rows resolved to `mark-done`, or there were zero pending rows to begin
     with — this step is complete.

7. **When `--skip-tracker` was passed and steps 3–4 did not fail:** merge into
   `.gsd-recipe/config.json` (create the file if needed; preserve unrelated keys):
   `"onboard": { "skip_tracker": true }`. Do **not** write a fake Epic key into `.planning/STATE.md`.
   Then continue to knowledge bootstrap.

8. **Mandatory final "knowledge bootstrap" step.** If step 1 found knowledge already ready via
   `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` (exit 0), skip with reason
   "already ready". Otherwise invoke `recipe-bootstrap-knowledge` by name in this same turn.
   After it returns, **must** run `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` again;
   exit 0 → record knowledge bootstrap **completed** (graphify may be `skipped` in the marker —
   that is success). Non-zero → knowledge bootstrap **failed**;
   report overall onboarding failed. Never treat a hand-written marker as success.
   `--skip-tracker` never skips this step.

9. **Print the final summary, always** (whether the chain completed all five steps, stopped early,
   or found every artifact already present): for each of the five steps,
   report **skipped** (with the reason, including `--skip-tracker` when that flag caused the skip),
   **completed** (carrying forward that sibling skill's own one-line summary), or — for at most one
   step, the one that blocked — **failed** (with the specific reason recorded at that step). Never
   invoke `gsd-jira-sync` except on the **existing-ticket link path** in step 5
   (`gsd-jira-sync intake_started <KEY>`). On the create path, `recipe-create-epic` still owns
   `intake_started`; `recipe-create-phase-tasks` owns its own events.

## D. Do NOT

- Do not re-implement any step `recipe-prd-intake`/`recipe-new-project`/`recipe-create-epic`/
  `recipe-create-phase-tasks` already documents for itself — clarifying-question gates, first-init
  routing, live Jira project/issue-type questions, per-row create+link logic, or any of their own
  tracker syncs. This skill only ever decides, per artifact, *whether* to invoke each one, in what
  order, and whether to keep going or stop. Do not inline `fotw-observer-bootstrap` spawn logic;
  invoke it by name after PRD exists (step 3b).
- Do not fabricate `docs/PRD.md`, `.planning/ROADMAP.md`, a Jira Epic key, or any phase-task issue
  key — every one of those is a real file, MCP fetch, `init-tracker` of an existing key, or a
  sibling skill's output. If a step's own call doesn't produce its artifact, that is a failure
  to report (§ C), never a value to invent.
- Do not invoke `recipe-create-epic` when the PRD source was an existing Jira issue (link via
  `init-tracker` instead). Do not create a second ticket for the same work.
- Do not reuse or silently skip against an old `docs/PRD.md`, ROADMAP, STATE, PLAN, SUMMARY,
  phase-task key, or knowledge-ready marker when an explicit new PRD source was supplied.
  Archive and switch out the active context first. If the workspace runtime is unavailable,
  fail closed and ask the operator to update/restage the recipe.
- Do not clear an explicit file source before reading it. Preload it before workspace
  switch-out, then pass the retained contents to `recipe-prd-intake`.
- Do not sync `intake_started` from this skill on the **create** path — that stays
  `recipe-create-epic`'s job. The existing-ticket link path is the exception (§ C step 5).
- Do not implement `recipe-discuss-phase` or `recipe-complete-milestone` as part of this chain, and
  do not fold either's intent into any of the five existing steps — both were explicitly evaluated
  and deferred (see "Why `recipe-discuss-phase` and `recipe-complete-milestone` were evaluated but
  not built" below). This skill's chain is exactly five steps, no more.
- Do not ask separate confirm questions per step — exactly one preview-then-confirm gate
  (§ C step 2), shown once, before any step runs.
- Do not continue past a failed/declined step to a later one that depends on it (steps 3/4/5 each
  depend on the previous one's artifact) — stop the whole chain immediately and report exactly
  which step blocked and why (§ C, per-step "this step failed" language). `--skip-tracker` is the
  only way to omit Epic/phase-task steps without declining the whole gate.
- Do not call native `gsd-new-project`/`gsd-import` directly when `recipe-new-project` **is**
  staged — the native fallback in step 4 is a narrow, explicitly-scoped exception for when that
  sibling skill isn't installed yet, not a general shortcut.
</cursor_skill_adapter>

# recipe-onboard — single onboarding orchestrator (TASK-037)

Recipe configuration on top of five independently-invokable `recipe-*` skills — closes the
"no single on-ramp" gap: even with `recipe-prd-intake`, `recipe-new-project`, `recipe-create-epic`,
`recipe-create-phase-tasks`, and `recipe-bootstrap-knowledge` individually recipe-native, an
operator still had to know and manually sequence all five.

**Spec:** `docs/netapp-recipe/BACKLOG.md` TASK-037.

## Workflow

1. Select mode. Explicit PRD source → fresh onboarding: preload file input, inspect prior
   active context, then create a clean initiative branch after confirmation (`--no-branch`
   explicitly archives in place instead). No source → resume:
   read-only check of existing PRD, ROADMAP, tracker, phase tasks, and knowledge marker.
2. One preview-then-confirm gate showing all five steps and their run/skip determination. With
   `--skip-tracker`, Epic and phase-task steps show **skip (flag)**. Without it, mention
   `recipe-onboard --skip-tracker` as the no-Jira option. Decline → stop, nothing invoked.
3. PRD intake (always for fresh onboarding; skip only in resume mode when `docs/PRD.md`
   exists) → invoke `recipe-prd-intake` by name (Jira key/URL, file, paste, or description).
3b. FOTW observer → invoke `fotw-observer-bootstrap` once `docs/PRD.md` exists (run **or** skip
    of intake). No-op if already active/disabled; never fails the chain.
4. Project bootstrap (always for fresh onboarding; artifact-aware in resume mode) → invoke
   `recipe-new-project` by name, or fall back to native `gsd-new-project` directly if that
   sibling skill isn't staged. After ROADMAP exists, run `recipe-enable-defaults.sh` (TDD +
   graphify config; circuit breaker, never fails onboard).
5. Epic: `--skip-tracker` → skip. Existing Jira ticket → `init-tracker` + `gsd-jira-sync
   intake_started` (do **not** `recipe-create-epic`). Else if no Epic linked → invoke
   `recipe-create-epic` by name.
6. Phase-task creation (skip if `--skip-tracker`, existing-ticket mode, or if no `ROADMAP.md`
   phase is missing a linked sub-task) → invoke `recipe-create-phase-tasks` by name.
7. If `--skip-tracker` succeeded through PRD + planning: set `onboard.skip_tracker` in
   `.gsd-recipe/config.json`.
8. Knowledge bootstrap (skip only when marker is ready) → invoke `recipe-bootstrap-knowledge`,
   then verify `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`.
9. Final combined summary: skipped / completed / failed, per step.

The chain stops immediately on the first step that fails or is declined — never continues to a
later step that depends on it.

## Why one preview-then-confirm gate, not nested ones

The invoked skills already have their own internal, appropriately-scoped
confirm/decline gate before doing anything consequential (`recipe-prd-intake`'s overwrite
confirmation, `recipe-create-epic`'s pre-create confirm, `recipe-create-phase-tasks`'s batch
confirm). Re-asking "are you sure?" a second time immediately before each of those own gates would
be pure noise stacked on top of already-adequate protection. `recipe-onboard` instead shows exactly
one gate, above all five, previewing the whole chain (which steps will run vs skip) before anything
happens — the same single-preview shape `recipe-run-phases` already established for its own
per-phase-range loop.

## Why the whole chain stops on the first blocked step

A missing PRD makes `recipe-new-project`'s own `docs/PRD.md`-as-input convenience meaningless. A
missing `ROADMAP.md` makes `recipe-create-phase-tasks` meaningless (it fails closed on exactly that
precondition). A missing Epic makes `recipe-create-phase-tasks` meaningless for the same reason
(fails closed on `get-tracker` returning no epic). Continuing past a failed/declined step to a later
one that depends on it would just relay a second, redundant failure instead of stopping cleanly at
the first one — same "stop the whole loop on first failure" precedent `recipe-run-phases` already
established for its own per-phase loop.

## Why step 4 has a native-call fallback (the one exception to "always invoke by name")

`recipe-new-project` (TASK-036) and `recipe-onboard` (TASK-037) were designed in the same pass and
are meant to be installed together, but nothing in this recipe's install composition *guarantees*
`recipe-new-project` is staged before `recipe-onboard` is invoked — a target repo may have
`recipe-onboard` staged (this file) without `recipe-new-project` staged alongside it. Rather than
failing closed on a missing sibling skill for a step whose only real job is calling native
`gsd-new-project`/`gsd-import` anyway, step 4 checks whether `recipe-new-project` is actually
present and, if not, makes the exact same native call directly. This is the **only** step in this
chain with such a fallback — steps 3/5/6 (`recipe-prd-intake`/`recipe-create-epic`/
`recipe-create-phase-tasks`) have no native-call equivalent to fall back to, so they are always
invoked by name, with no exception.

## Why `recipe-discuss-phase` and `recipe-complete-milestone` were evaluated but not built

Both were explicitly considered during the same gap-closing pass that produced this skill:
`recipe-discuss-phase` was judged not required, on the basis that PRD-level Q&A
(`recipe-prd-intake`'s own clarifying-question gate) is assumed to cover the gray areas a
phase-level discuss would otherwise surface; `recipe-complete-milestone` was judged out of scope for
this pass. Neither is silently folded into this skill's own steps — this skill's chain is exactly
the five steps documented above, no more.

## What this does NOT do

- **No development on `main`/`master` by default.** Fresh onboarding creates an initiative
  branch before intake. Only explicit `--no-branch` keeps the new cycle on the current branch.
- **No planning/execution step.** `recipe-plan-phase`/`recipe-run-phase`/`recipe-run-phases` starts
  only after onboarding has completed mandatory knowledge bootstrap (and, unless
  `--skip-tracker`, created the Epic and phase tasks).
- **No DAG involvement.** Phase-task creation order follows `ROADMAP.md`'s own phase numbering,
  exactly as `recipe-create-phase-tasks` itself already implements — no topo-sort, no
  `depends_on`/`touches` handling here.
- **No re-derivation of any sibling skill's own pass/fail definition.** Each step's "did this
  genuinely conclude successfully" question is answered by re-checking that step's own artifact
  (a file existing, `get-tracker` returning a non-empty epic, zero pending phase-task rows) — never
  by re-parsing that sibling skill's own internal reasoning.
- **No duplicated Jira sync on the create path** — `recipe-create-epic` owns `intake_started`
  when it creates an Epic. Existing-ticket onboard is the exception: this skill links STATE and
  calls `gsd-jira-sync intake_started <KEY>` because create-epic is skipped.
