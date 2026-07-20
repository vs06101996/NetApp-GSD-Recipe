---
name: recipe-sync
description: "Recipe: one-shot detect→queue→drain sync pass for the NetApp GSD recipe (TASK-029). Runs bench/runners/sync-reconcile.sh directly (real shell call, passing --dry-run through unchanged) to detect new .planning/ lifecycle events and enqueue them, then — unless --dry-run was passed — invokes the gsd-jira-sync skill's own Drain mode (gsd-jira-sync --drain) by name to actually post the queued backlog via the Atlassian MCP. Reports a combined queued/posted/failed/skipped-duplicate summary. Per DECISIONS.md OD-05 ('recipe-sync trigger: Loop-first; hooks later'), this skill is deliberately one-shot — it never loops, schedules, or hooks itself; recurrence is the operator's job (invoke it again) or Cursor's own generic /loop automation, composed externally."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-sync`) with:

Arguments: `{{GSD_ARGS}}` = `[--dry-run]`

Examples:
- `recipe-sync` — full pass: detect + queue, then drain (posts to Jira).
- `recipe-sync --dry-run` — detect + draft only, no queue writes, no posts. "Show me what would happen."

## B. Prerequisites

- `bench/runners/sync-reconcile.sh` (TASK-003) and `bench/runners/sync-drain-queue.sh` (TASK-005)
  must exist at their standard `bench/` paths — this skill does not vendor or reimplement either.
- For a real (non-`--dry-run`) pass: Atlassian MCP enabled and authenticated, same requirement
  `gsd-jira-sync`'s own Drain mode already documents — `recipe-sync` does not re-check this itself,
  it surfaces whatever `gsd-jira-sync --drain` reports.
- `.gsd-recipe/config.json`/`.planning/config.json`/`.gsd-recipe/sync-queue.jsonl`/
  `.gsd-recipe/sync-ledger.jsonl` may or may not exist yet — all four are the invoked
  scripts'/skill's own runtime concern, not something this skill creates or validates itself.

## C. Tool Usage

1. **Step 1 — detect + queue (`Shell`, real script call, not agent-mediated).** `bench/runners/
   sync-reconcile.sh` is not duplicated into every target by design — resolve its real path first
   via `.gsd-recipe/scripts/recipe-paths.sh` (same mechanism `recipe-validate-tokens-SKILL.md` § C
   step 1 documents in full):
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/sync-reconcile.sh)"
   "$RESOLVED" [--dry-run]
   ```
   Pass `--dry-run` through unchanged if the operator passed it to `recipe-sync`.
   This is the same category of direct shell call `recipe-install-verify` makes to
   `install.sh --verify` — a real, scriptable, testable script invocation, not "Option B"
   native-GSD-call territory. Capture and report its `queued`/`duplicate_skipped`/`errors` counts.
2. **Stop here if `--dry-run` was passed.** Report step 1's output as the final summary and stop —
   never proceed to step 3. Dry-run means "detect + draft only", never a post, per § D.
3. **Step 2 — drain (skill-to-skill, Option B, agent-mediated).** Invoke the `gsd-jira-sync` skill's
   own Drain mode by name: `gsd-jira-sync --drain`. Follow its `SKILL.md`'s
   [Drain mode (TASK-005)](../../.cursor/skills/gsd-jira-sync/SKILL.md#drain-mode-task-005) section
   exactly as documented there — `sync-drain-queue.sh list`, then for each work item read MCP tool
   schemas and call `addCommentToJiraIssue`, then `mark-done`/`mark-failed` per outcome.
   `recipe-sync` does not call `sync-drain-queue.sh list`/`mark-done`/`mark-failed` itself, and does
   not call `addCommentToJiraIssue` itself — it delegates the entire drain step to `gsd-jira-sync`,
   exactly like `tracker-sync` delegates entirely to `gsd-jira-sync` for single-event mode.
4. **Step 3 — combined summary.** Report, in one combined report to the operator: step 1's
   queued-this-pass count (plus `duplicate_skipped`/`errors` if any), and step 3's posted/failed/
   skipped-duplicate counts (from `gsd-jira-sync --drain`'s own summary line, § "Report a summary" in
   its `SKILL.md`). `target: github` rows surfaced by drain mode's `errors` are reported plainly, not
   silently dropped or retried against a workaround.

## D. Do NOT

- Do not implement any internal loop, `--interval`/`--watch` flag, cron, or background daemon mode
  — per `DECISIONS.md` OD-05 ("`recipe-sync` trigger: Loop-first; hooks later"), this skill is a
  single one-shot pass every time it's invoked. See "Why this doesn't loop itself" below.
- Do not implement hooks-based auto-triggering (reacting to GSD lifecycle events automatically
  without an explicit invocation) — also explicitly out of scope per OD-05's "hooks later".
- Do not reimplement any of `sync-reconcile.sh`'s own detect/draft/queue logic, or any of
  `sync-drain-queue.sh`'s own `list`/`mark-done`/`mark-failed` subcommands, or the
  `addCommentToJiraIssue` MCP call itself — always delegate to the real script (step 1) or the
  `gsd-jira-sync` skill (step 3). This skill's only job is running one, then the other, then
  combining their reports.
- Do not proceed to step 3 (drain) when `--dry-run` was passed — dry-run stops after step 1, full
  stop, no exceptions.
- Do not fabricate a posted/success result. If MCP is unreachable or a post genuinely fails
  mid-drain, that surfaces as a real failure via `gsd-jira-sync --drain`'s own `mark-failed` call
  (its own § D already forbids calling `mark-done` before a post actually succeeds) — `recipe-sync`
  never treats a failed or partial drain as a clean success in its own combined summary.
- Do not attempt to post `target: github` rows via `gh pr comment` or any other workaround —
  GitHub tracker sync isn't built yet (TASK-006 only built the draft/polish script, not a posting
  path). Surface those rows under `errors` exactly as `gsd-jira-sync --drain`'s own `list` step
  already does; do not silently drop them or mis-post them to Jira instead.
</cursor_skill_adapter>

# recipe-sync — one-shot detect→queue→drain sync pass (TASK-029)

Thin orchestration skill wrapping the already-built detect→queue→drain traceability pipeline
(`sync-reconcile.sh` TASK-003 → `sync-queue.jsonl` → `sync-drain-queue.sh`/`gsd-jira-sync --drain`
TASK-005) into a single invoke-by-name command. GSD stays the orchestrator of `.planning/`; this
skill (and everything it delegates to) owns the Jira/GitHub audit trail.

**Spec:** `docs/netapp-recipe/lld/TRACEABILITY-LLD.md` § "Near-RT reconciler" · `docs/netapp-recipe/DECISIONS.md` OD-05 · `docs/netapp-recipe/BACKLOG.md` TASK-029.

**Built standalone**, the same pattern already used by `recipe-run-phases` (TASK-018),
`recipe-validate-tokens` (TASK-021), and `gsd-jira-sync`'s own installer (TASK-028) — this skill has
its own installer, `.gsd-recipe/scripts/install-recipe-sync.sh`, composed into `install.sh`
(TASK-010) as its 14th sub-installer.

## Workflow

1. Run `bench/runners/sync-reconcile.sh` directly via `Shell` (passing `--dry-run` through unchanged
   if given). Report its `queued`/`duplicate_skipped`/`errors` output.
2. If `--dry-run` was passed — **stop here.** Report step 1's output as the final summary.
3. Otherwise, invoke the `gsd-jira-sync` skill's Drain mode by name: `gsd-jira-sync --drain`. Let it
   run its own full `list` → per-item `addCommentToJiraIssue` → `mark-done`/`mark-failed` workflow
   exactly as documented in its own `SKILL.md`.
4. Report a combined summary: queued-this-pass (step 1) + posted/failed/skipped-duplicate (step 3).

## Why this doesn't loop itself (OD-05)

`docs/netapp-recipe/DECISIONS.md` records **OD-05** — "`recipe-sync` trigger: Loop-first; hooks
later" — as an **open** decision, but the "loop-first" half of that framing is a firm scope
boundary this skill honors from day one: `recipe-sync` is a single, one-shot "run one sync pass
now" primitive. It has no `--interval`/`--watch` flag, no internal `while` loop, no cron
registration, and no background daemon mode. The *recurring* triggering of that one-shot pass is a
separate, still-open concern (the other half of OD-05) that this task deliberately does not
implement:

- An operator who wants recurring behavior can simply invoke `recipe-sync` repeatedly themselves
  (e.g. after every few GSD milestones, or on whatever cadence suits their workflow).
- Or they can compose it with Cursor's own generic `/loop` automation feature — a pre-existing
  Cursor capability, entirely unrelated to this recipe, that already knows how to re-run a prompt or
  skill on a recurring or variable interval. `recipe-sync` does not need to know about, integrate
  with, or special-case `/loop` in any way — it is just an ordinary one-shot skill from `/loop`'s
  point of view, exactly as any other invoke-by-name skill would be.
- Hooks-based auto-triggering — reacting automatically to GSD lifecycle events (a new `SUMMARY.md`,
  a new commit, etc.) without an explicit invocation — is explicitly the "hooks later" half of
  OD-05 and stays out of scope for this task entirely. No `.cursor/hooks.json` entry, no file
  watcher, and no event listener are added by this skill or its installer.

Building any of the above into `recipe-sync` itself would mean maintaining a competing scheduler
alongside Cursor's own `/loop` primitive — solving a problem the platform already solves, and
pre-empting OD-05's still-open "hooks later" half before it's actually decided. `recipe-sync`'s job
ends at "run one pass, faithfully, and report what happened."

## Combined summary shape

```text
Step 1 (detect + queue): N queued, M duplicate_skipped, K errors
Step 2 (drain):          P posted, Q failed, R skipped_duplicate
  target: github rows (not posted, TASK-006 unbuilt): [...]
```

When `--dry-run` is passed, only the "Step 1" line is printed — there is no "Step 2" section at all,
never a stubbed-out "0 posted" placeholder standing in for a step that never ran.

## GitHub tracker limitation

`gsd-jira-sync --drain`'s own `list` step already surfaces any `target: github` queue row under
`errors` rather than posting it or dropping it — GitHub tracker sync isn't built yet (TASK-006 only
built `draft-github-pr-comment.sh`, no posting path exists). `recipe-sync` surfaces this the exact
same way its delegate already does: those rows appear in step 2's summary as errors, plainly, with
no workaround attempted (no `gh pr comment` substitution, no silent drop).

## Never fabricates a result

Every "posted" in this skill's combined summary corresponds to a real, successful
`addCommentToJiraIssue` call that `gsd-jira-sync --drain` already confirmed before calling
`mark-done` (its own § D rule: never call `mark-done` before the post actually succeeds). If the
Atlassian MCP is unreachable, or an individual post fails partway through the drain, that item
comes back as `failed` (via `mark-failed`) in step 2's summary — `recipe-sync` reports it as a
failure, not a success, and never retries it silently or substitutes a placeholder "done".

## Relationship to sync-reconcile.sh / sync-drain-queue.sh / gsd-jira-sync

`recipe-sync` reimplements none of the underlying machinery:

| Concern | Owned by |
|---------|----------|
| Detect lifecycle events, resolve issue, draft comment, enqueue | `bench/runners/sync-reconcile.sh` (TASK-003) |
| Re-verify queue against ledger, re-draft, self-heal, return work list | `bench/runners/sync-drain-queue.sh` (TASK-005) via `gsd-jira-sync --drain` |
| Actual `addCommentToJiraIssue` MCP call, `mark-done`/`mark-failed` | `gsd-jira-sync` skill's own Drain mode |
| Running step 1 then step 3 in order, combining their reports | `recipe-sync` (this skill) — its only job |

This mirrors `tracker-sync-SKILL.md`'s own precedent exactly: a thin, invoke-by-name
dispatch/orchestration skill that delegates entirely to other already-built pieces, never
reimplementing their logic.
