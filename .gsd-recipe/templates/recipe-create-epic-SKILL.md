---
name: recipe-create-epic
description: "Recipe: PRD -> Jira Epic bridge for the NetApp GSD recipe (TASK-033). Fails closed if docs/PRD.md doesn't exist (tells the operator to run recipe-prd-intake first); resolves an already-linked-but-different epic as a conflict requiring an explicit --force; resolves the Jira project (optional --project, else a live, non-skippable getVisibleJiraProjects question) and the Epic issue type (optional --issue-type, else getJiraProjectIssueTypesMetadata, defaulting silently to a case-insensitive 'Epic' match if present); drafts summary/description from docs/PRD.md via bench/runners/draft-jira-epic.sh (real script, Option B split); asks a soft yes/no confirm gate previewing project/issue-type/summary/description before creating anything remote; calls createJiraIssue via the Atlassian MCP; writes the result into .planning/STATE.md's '## Tracker' section via bench/lib/parse-state.sh init-tracker (new write subcommand); and invokes the gsd-jira-sync skill by name with intake_started <EPIC_KEY> — never posting/transitioning Jira issues directly itself."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-create-epic`) with:
- `--project KEY` — optional. Skips the live `getVisibleJiraProjects` question in step 3 if provided.
- `--issue-type NAME` — optional. Skips the `getJiraProjectIssueTypesMetadata` lookup in step 4 if
  provided.
- `--force` — optional. Forwarded to step 8's `parse-state.sh init-tracker --force` call — only
  needed when `.planning/STATE.md` already has a `## Tracker` section linked to a *different* epic
  than the one this invocation is about to create (step 2).
- `--run-id ID` / `--arm ARM` — optional. Override the low-friction defaults step 8 otherwise
  proposes (a date-based run-id slug, `arm: recipe`) in the same confirm turn as step 6.

Examples:
- `recipe-create-epic`
- `recipe-create-epic --project PROJ`
- `recipe-create-epic --project PROJ --issue-type Epic --run-id pilot-02`
- `recipe-create-epic --force` (after confirming with the operator that relinking is intentional)

## B. Prerequisites

- `docs/PRD.md` must already exist — this skill never fabricates a PRD. If it's missing, fail
  closed in step 1 and tell the operator to run `recipe-prd-intake` first.
- Atlassian MCP enabled and authenticated, with permission to create issues in the resolved
  project.
- `.planning/STATE.md` may or may not exist, and may or may not already have a `## Tracker`
  section — both are valid starting states (see step 2 and step 8's `init-tracker` semantics).

## C. Tool Usage

1. **Fail closed if `docs/PRD.md` doesn't exist.** `Glob`/`Read` for `docs/PRD.md`. Missing → stop
   here with an actionable message: "No `docs/PRD.md` found — run `recipe-prd-intake` first, then
   retry `recipe-create-epic`." Never fabricate a PRD to work around this.

2. **Resolve any pre-existing, possibly-conflicting linked epic.** `bench/lib/parse-state.sh` is not
   duplicated into every target by design — resolve its real path via
   `.gsd-recipe/scripts/recipe-paths.sh` first (same mechanism `recipe-validate-tokens-SKILL.md` §
   C step 1 documents in full; steps 8 and 9 below reuse the same resolved path). `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   "$RESOLVED" get-tracker --state .planning/STATE.md
   ```
   Three outcomes:
   - Fails (no `.planning/STATE.md`, or no `## Tracker` section yet) → nothing to conflict with;
     continue straight to step 3.
   - Succeeds with an empty `epic` field → same as above, nothing to conflict with; continue.
   - Succeeds with a non-empty `epic` field → this is a potential relink. Surface it plainly to the
     operator now, *before* doing anything remote: "`.planning/STATE.md` is already linked to epic
     `<EXISTING_EPIC>`. This invocation will create a *new* Jira Epic and, unless you pass
     `--force`, `init-tracker` will refuse to overwrite that link in step 8." If `--force` was not
     passed on this invocation, ask the operator here whether they meant to pass it — do not
     silently proceed only to have step 8 fail after an issue has already been created remotely.
     Continue to step 3 either way (this is a surface-early warning, not a hard block by itself —
     the actual enforcement is `init-tracker`'s own conflict check in step 8).

3. **Resolve the Jira project.**
   - `--project KEY` passed → use it directly, skip the live question.
   - Not passed → `GetMcpTools` server `plugin-atlassian-atlassian` tool `getVisibleJiraProjects`,
     then `CallMcpTool` it. Present the returned project list to the operator and ask them, live in
     this conversation, which one to use — a genuine, non-skippable question (same posture as
     `recipe-settle`'s PO-accept gate: only a live agent turn can reach the real human here). Never
     default to "the first project returned" — that is exactly the shortcut this step exists to
     prevent.

4. **Resolve the Epic issue type.**
   - `--issue-type NAME` passed → use it directly, skip the lookup.
   - Not passed → `GetMcpTools` then `CallMcpTool` `getJiraProjectIssueTypesMetadata` for the
     project resolved in step 3. Look for an issue type named "Epic" (case-insensitive).
     - Found → use it directly, no operator question (safe, unambiguous default — every Jira
       project in practice has exactly one issue type that means "Epic").
     - Not found → list the issue types that *are* available for this project and ask the operator,
       live, which one to use instead. Never guess or silently substitute a different type.

5. **Draft the Epic body.** `bench/runners/draft-jira-epic.sh` is not duplicated into every target
   by design — resolve its real path via `.gsd-recipe/scripts/recipe-paths.sh` the same way step 2
   does. `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/draft-jira-epic.sh)"
   "$RESOLVED" --project <KEY>
   ```
   (the project resolved in step 3). Returns `{"summary": "...", "description": "..."}` — a real,
   standalone, testable script; do not re-derive this from `docs/PRD.md` inline.

6. **Soft confirm gate — non-skippable but declinable.** Print, in this conversation: the resolved
   project, the resolved issue type, the drafted `summary`, and a truncated preview of the drafted
   `description` (a few lines is enough — the operator can ask to see the full body if they want
   it). In the same turn, also present the low-friction defaults for `run_id` (a date-based slug,
   e.g. `epic-YYYY-MM-DD`) and `arm` (`recipe`) that step 8 will use unless overridden via
   `--run-id`/`--arm`. Ask a plain yes/no: "Create this Jira Epic?"
   - Decline → stop cleanly here. Nothing created, nothing written to `.planning/STATE.md`. Report
     "declined — no Epic created" in the final summary.
   - Affirm → continue to step 7.

7. **Create the Epic.** `GetMcpTools` server `plugin-atlassian-atlassian` tool `createJiraIssue`,
   then `CallMcpTool` it with the resolved project key, the resolved issue type, and the drafted
   `summary`/`description` from step 5. Always read the tool's schema first — never assume its
   field names from memory.

8. **Link the result into `.planning/STATE.md`.** Derive the created issue's key from
   `createJiraIssue`'s response. Derive a browsable URL as `https://<site>/browse/<KEY>`, where
   `<site>` comes from whatever Atlassian resource/cloud metadata step 3's `getVisibleJiraProjects`
   call (or, if `--project` skipped that call, a fresh `getAccessibleAtlassianResources` call made
   right here) already returned — never fabricate a URL by guessing a hostname. Re-resolve
   `bench/lib/parse-state.sh` the same way step 2 did (same `recipe-paths.sh resolve` command).
   `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   "$RESOLVED" init-tracker --epic <KEY> --system jira --url <URL> \
     --run-id <RUN_ID> --arm <ARM> --state .planning/STATE.md [--force]
   ```
   forwarding `--force` only when step 2 identified a genuine relink the operator confirmed. Report
   whichever of `init-tracker`'s own outcomes it printed (created fresh / inserted / no-op /
   overwrote) verbatim in the final summary — never paraphrase away a conflict-refusal into a
   silent success.

9. **Sync `intake_started`.** Invoke the `gsd-jira-sync` skill by name —
   `gsd-jira-sync intake_started <EPIC_KEY>` — exactly the "`gsd-new-project` / link ticket ->
   `intake_started`" row `gsd-jira-sync-SKILL.md`'s own operator checklist already documents.
   Do **not** call `addCommentToJiraIssue`/`transitionJiraIssue` directly here — drafting, posting,
   and stamping are exclusively `gsd-jira-sync`'s job (Option B, same split every other `recipe-*`
   sync call in this repo already uses).

10. **Summarize**, in one final block to the operator: the created Epic's key and URL, the
    resolved project/issue type, whether `.planning/STATE.md` was created fresh / had a `## Tracker`
    section inserted / was a no-op / was overwritten via `--force`, and the `gsd-jira-sync` sync
    result (posted / duplicate_skipped / whatever that skill itself reports).

## D. Do NOT

- Never call any MCP tool without first reading its schema (`GetMcpTools` before every
  `CallMcpTool`) — `getVisibleJiraProjects`, `getJiraProjectIssueTypesMetadata`, `createJiraIssue`,
  and (if needed) `getAccessibleAtlassianResources` all apply.
- Never fabricate a project key, issue type, Epic key, or Jira instance URL when a live/resolvable
  value exists instead. If `getVisibleJiraProjects`/`getJiraProjectIssueTypesMetadata` can answer
  the question, use them — never guess, and never silently default to "the first one returned".
- Never call `addCommentToJiraIssue` or `transitionJiraIssue` directly from this skill — that is
  exclusively `gsd-jira-sync`'s job (step 9). This skill's only direct Jira-API call is
  `createJiraIssue`.
- Never proceed past the step-6 confirm gate on a decline — no `createJiraIssue` call, no
  `init-tracker` write, no `gsd-jira-sync` invocation.
- Never overwrite a different already-linked epic in `.planning/STATE.md` without an explicit
  `--force` that the operator affirmatively provided or confirmed in step 2 — `init-tracker` itself
  enforces this at the parser layer, but this skill must not paper over a refusal by re-running with
  `--force` on the operator's behalf.
- Never fabricate a PRD when `docs/PRD.md` doesn't exist — fail closed in step 1 and point the
  operator at `recipe-prd-intake`, full stop.
- Never re-derive `draft-jira-epic.sh`'s summary/description logic inline — always shell out to the
  real script.
</cursor_skill_adapter>

# recipe-create-epic — PRD -> Jira Epic bridge (TASK-033)

Closes the "PRD -> Epic" gap: until this skill existed, an operator who had already run
`recipe-prd-intake` (TASK-016) to produce `docs/PRD.md` had no recipe-native way to turn that PRD
into a real Jira Epic and get it linked into `.planning/STATE.md`'s `## Tracker` section — they had
to hand-craft that section (per `gsd-jira-sync-SKILL.md`'s own "Linking Jira to the project"
example) and drive `createJiraIssue` themselves. `recipe-create-epic` automates every step of that
bridge except the two genuinely human decisions (which project, and whether to actually create the
Epic) and the two MCP calls only a live agent turn can make.

**Spec:** `docs/netapp-recipe/contracts/DATA-CONTRACTS.md#state-md` ·
`docs/netapp-recipe/BACKLOG.md` TASK-033.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-plan-phase` (TASK-017), and `recipe-settle` (TASK-027) ahead of/alongside the full
`install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-create-epic.sh`, intended to also be composed into `install.sh`
as a sub-installer in a follow-up integration pass (see the integration report for the exact
`install.sh` wiring snippet, held back from this task's own diff to avoid a merge conflict with
sibling tasks editing `install.sh` concurrently).

## Workflow

1. Fail closed if `docs/PRD.md` doesn't exist — point the operator at `recipe-prd-intake`.
2. Resolve any pre-existing linked epic in `.planning/STATE.md` and surface a potential relink
   plainly, before anything remote happens.
3. Resolve the Jira project — `--project`, or a live, non-skippable `getVisibleJiraProjects`
   question.
4. Resolve the Epic issue type — `--issue-type`, or `getJiraProjectIssueTypesMetadata` with a
   safe case-insensitive "Epic" default, falling back to a live question only if genuinely absent.
5. Draft the summary/description from `docs/PRD.md` via `bench/runners/draft-jira-epic.sh`.
6. Soft confirm gate: preview project/issue-type/summary/description, ask yes/no.
7. Create the Epic via `createJiraIssue` (Atlassian MCP).
8. Link the result into `.planning/STATE.md` via `bench/lib/parse-state.sh init-tracker`.
9. Sync `intake_started` by invoking `gsd-jira-sync` by name.
10. Summarize.

## Why Option B (script drafts, agent posts) for the Epic body

Same split every other Jira-posting `recipe-*` skill in this repo already uses, applied to a new
target (an Epic's summary/description instead of a milestone comment body): a plain bash process
has no MCP tool-calling access, so it can never itself call `createJiraIssue`. What it *can* do
safely and testably is read `docs/PRD.md` and render `{summary, description}` — pure text
transformation, no network call, fully unit-testable against fixtures without a live Jira
connection. So `bench/runners/draft-jira-epic.sh` owns exactly that transformation (mirroring
`draft-jira-comment.sh`'s own "draft, never post" contract), and this skill's own job is narrower:
call the script for the body, then make the one MCP call the script architecturally cannot make
itself. This is the same reasoning `gsd-jira-sync-SKILL.md`'s own `draft-jira-comment.sh` step
already documents, and the same reasoning `recipe-pr-comment`'s own README table cites for why
*its* posting pipeline differs (a real local CLI, `gh`, can be called directly by a script — Jira
posting cannot, since it is exclusively an MCP-mediated call).

## Why the Jira project/issue-type resolution is a mix of live questions and safe defaults

Two genuinely different kinds of ambiguity get two different resolutions, deliberately:

- **Which Jira project?** has no safe default at all — "the first one `getVisibleJiraProjects`
  happens to return" is not a meaningful proxy for "the project the operator actually meant," and
  guessing wrong here creates a real Jira issue in the wrong project, which is not a
  cheaply-reversible mistake. So this is always a genuine, live, non-skippable question unless the
  operator already told this skill the answer via `--project`.
- **Which issue type means "Epic"?** almost always has exactly one unambiguous answer — Jira's own
  convention is a literal issue type named "Epic" — so silently picking it when it's present isn't
  a guess, it's resolving a naming lookup with only one sane match. The live question is reserved
  for the genuine edge case where a project's issue-type scheme doesn't include one named "Epic" at
  all, at which point there truly is no safe default left and the operator has to choose.

## Why `init-tracker` enforces the relink conflict, and this skill only surfaces it early

`bench/lib/parse-state.sh init-tracker` (this task's own new write subcommand) is the single source
of truth for "does writing this epic into `.planning/STATE.md` conflict with what's already there,"
and it fails closed on a genuine conflict without `--force` — see its own header comment and
`bench/tests/test-parse-state.sh`. This skill's step 2 exists purely so the operator isn't surprised
by that refusal *after* a brand-new Jira Epic has already been created remotely (step 7) — better
to warn before the irreversible remote call than to let `init-tracker` be the only thing that
catches a relink mistake, after the fact, with an orphaned Epic already sitting in Jira. The
skill never bypasses or duplicates `init-tracker`'s own enforcement; it only makes the eventual
outcome visible earlier.

## What this does NOT do

- **Does not create phase sub-tasks.** That's `create-phase-tasks.sh` / `bench/runners/create-phase-tasks.sh`
  (TASK-007)'s job, run separately once phases exist in `ROADMAP.md` — this skill only ever creates
  the top-level Epic and the `## Tracker` linkage.
- **Does not post or transition Jira issues directly.** `intake_started` is emitted by invoking
  `gsd-jira-sync`'s own documented workflow (step 9) — this skill's only direct Jira-API call is
  `createJiraIssue` (step 7).
- **Does not fabricate a PRD, a project, an issue type, an Epic key, or a Jira URL** under any
  circumstance — every one of those either comes from a real file on disk, a live MCP response, or
  an explicit operator answer.
- **Does not skip the step-6 confirm gate** under any flag — unlike `install.sh`'s `--yes`, there is
  no non-interactive mode for "create this Epic without asking," matching `recipe-settle`'s own
  PO-accept-gate precedent for irreversible remote actions.
