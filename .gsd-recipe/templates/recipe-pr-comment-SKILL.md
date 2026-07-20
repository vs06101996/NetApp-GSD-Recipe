---
name: recipe-pr-comment
description: "Recipe: draft->idempotency-check->post->ledger GitHub PR lifecycle comment poster for the NetApp GSD recipe (TASK-030). Thin invoke-by-name wrapper around a real, scriptable, testable runner (bench/runners/post-github-pr-comment.sh) that calls draft-github-pr-comment.sh (TASK-006) for the body, computes the idempotency key via sync-ledger.sh, checks the shared ledger, and — unless --dry-run or already posted — calls the real local `gh pr comment` CLI directly (never an MCP call, unlike Jira posting). Never emits a stamp (github-events.json has no stamp field at all; the linked Jira side, when present, already owns the canonical KPI stamp for the same milestone)."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-pr-comment`) with:

Arguments: `{{GSD_ARGS}}` = `<event_id> <pr_number> --phase N [--wave W] [--issue KEY] [--repo owner/repo] [--arm recipe] [--run run-01] [--ledger PATH] [--dry-run]`

- `<event_id>` — must exist in `bench/recipe/trackers/github-events.json`
  (`execute_wave`, `execute_complete`, `review_complete`, `phase_complete`).
- `<pr_number>` — the GitHub PR number this comment is about (required, positional —
  mirrors `gsd-jira-sync <event_id> <issue_key>`'s own shape, with a PR number standing in
  for the issue key since GitHub PRs have no Jira issue key of their own).
- `--phase N` — required, forwarded unchanged to the underlying draft script.
- `--issue KEY` — optional. If this PR's phase is also linked to a Jira issue, pass it here
  so the drafted comment body and the ledger key both reference the real cross-linked issue
  (see "Synthetic issue-key convention" below for what happens when it's omitted).
- `--repo owner/repo` — optional. Default: parsed from `git remote get-url origin` by the
  runner itself, only at the point a real post is about to happen (never required for
  `--dry-run` or an already-posted key).
- `--dry-run` — draft + compute the idempotency key + report whether it's already posted,
  but never call `gh pr comment`. Same "detect only, never post" precedent
  `sync-reconcile.sh --dry-run` already established for the Jira side.

Examples:
- `recipe-pr-comment execute_complete 42 --phase 3 --issue PROJ-101`
- `recipe-pr-comment execute_wave 42 --phase 3 --wave 2 --dry-run`
- `recipe-pr-comment review_complete 42 --phase 3 --repo my-org/my-repo`

## B. Prerequisites

- `bench/runners/post-github-pr-comment.sh` (TASK-030) and `bench/runners/draft-github-pr-comment.sh`
  (TASK-006) must exist at their standard `bench/` paths — this skill does not vendor or
  reimplement either.
- `gh` CLI installed and authenticated, for any real (non-`--dry-run`, non-duplicate) post —
  a missing/unauthenticated `gh` surfaces as a real, clearly-reported failure from the runner
  itself (never silently skipped, never fabricated as a success).
- `.gsd-recipe/sync-ledger.jsonl` may or may not exist yet — the runner creates it on first
  append; this skill does not create or validate it itself.
- A `git remote origin` pointed at a real GitHub `owner/repo` — only needed for a real post
  when `--repo` isn't passed explicitly.

## C. Tool Usage

1. **Resolve args and run the real script (`Shell`, direct call — not agent-mediated, not an
   MCP call).** `bench/runners/post-github-pr-comment.sh` is not duplicated into every target by
   design — resolve its real path first via `.gsd-recipe/scripts/recipe-paths.sh` (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full). Translate the positional
   `<pr_number>` into the runner's `--pr` flag, and forward every other flag unchanged:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/runners/post-github-pr-comment.sh)"
   "$RESOLVED" <event_id> --pr <pr_number> --phase N [--wave W]
   [--issue KEY] [--repo owner/repo] [--arm recipe] [--run run-01] [--ledger PATH] [--dry-run]
   ```
   This is the same category of direct shell call `recipe-sync`'s own step 1 makes to
   `sync-reconcile.sh` — a real, scriptable, testable script invocation, never "Option B"
   native-GSD-call or MCP-call territory, because `gh pr comment` (unlike
   `addCommentToJiraIssue`) is a plain local CLI a script can call directly. See "Why this is
   a real script, not an Option-B agent-mediated call" below.
2. **Report the runner's output verbatim** — `posted` (with the real comment URL if `gh`
   printed one), `duplicate_skipped`, the drafted body + idempotency key + already-posted
   status (`--dry-run`), or a real failure (`gh` missing/unauthenticated, PR not found, repo
   unresolvable, API error) — exactly as the script reported it, never softened, never
   silently retried.

## D. Do NOT

- Do not reimplement `draft-github-pr-comment.sh`'s templating/git-log/short-SHA logic, the
  idempotency-key computation, the `sync-ledger.sh has`/`append` calls, or the `gh pr comment`
  invocation itself inline in this skill's own instructions — always delegate to
  `post-github-pr-comment.sh`, so there is exactly one implementation of this pipeline.
- Do not call `mark-done`-equivalent (i.e. never let the runner append a `posted` ledger row)
  before `gh pr comment` has actually exited `0` — same "never call mark-done before a post
  actually succeeds" precedent `gsd-jira-sync`'s Drain mode already documents for Jira. The
  runner itself already enforces this; this skill never works around it or calls
  `sync-ledger.sh append` directly on the runner's behalf.
- Do not invent a stamp-emission step for this event. `bench/recipe/trackers/github-events.json`'s
  4 entries have no `"stamp"` field at all (unlike `jira-events.json`'s entries, which each
  carry `"stamp": {...}` or `"stamp": null`) — there is nothing to key a stamp off, and when
  this PR's phase is also linked to a Jira issue, the Jira side already owns the canonical KPI
  stamp for that same milestone (see "Why no stamp emission" below).
- Do not pass `--dry-run` through as anything other than a hard stop before any `gh` call —
  the runner already enforces "detect + draft only, never a post" for `--dry-run`; this skill
  never second-guesses that or calls `gh pr comment` itself when `--dry-run` was requested.
- Do not fabricate a `posted` result if the runner reports a failure. A missing/unauthenticated
  `gh`, an unresolvable `--repo`, or a real `gh pr comment` API error are all real failures —
  report them plainly, never as a soft warning standing in for success.
</cursor_skill_adapter>

# recipe-pr-comment — GitHub PR lifecycle comment poster (TASK-030)

Closes the gap `draft-github-pr-comment.sh` (TASK-006) deliberately left open — its own header
comment says "Does NOT post to GitHub — use `gh pr comment` after reviewing output." This skill
is the thin invoke-by-name wrapper around the real script that now does exactly that, safely and
idempotently: draft → compute idempotency key → check the shared ledger → (unless `--dry-run` or
already posted) call the real `gh pr comment` CLI → record the outcome.

**Spec:** `docs/netapp-recipe/lld/TRACEABILITY-LLD.md` § "GitHub PR events" ·
`docs/netapp-recipe/BACKLOG.md` TASK-030 (`Depends: 001, 006`).

**Built standalone**, the same pattern already used by `recipe-sync` (TASK-029) — this skill has
its own installer, `.gsd-recipe/scripts/install-recipe-pr-comment.sh`, composed into `install.sh`
(TASK-010) as its 15th sub-installer.

## Workflow

1. Translate the positional `<pr_number>` into `--pr <pr_number>` and forward every other flag
   unchanged to `bench/runners/post-github-pr-comment.sh <event_id> --pr <pr_number> --phase N
   [...]` via `Shell` (a real, direct script call).
2. Report the script's own output verbatim: `posted` (+ comment URL if one was printed),
   `duplicate_skipped`, the dry-run report (drafted body + idempotency key + already-posted
   status), or a real failure.

## Why this is a real script, not an Option-B agent-mediated call

Every other `recipe-*` skill that posts a lifecycle comment (`recipe-settle`, `recipe-run-phase`,
`recipe-plan-phase`, …) invokes the `gsd-jira-sync` skill by name for the actual post, because
`addCommentToJiraIssue` is an MCP tool call — only a live agent turn has MCP tool-calling access,
so that half of the pipeline can never be a plain shell script. `gh pr comment`, by contrast, is a
real, local CLI binary a plain shell process can invoke directly — the same category as
`install.sh`'s own `gh auth status`/`gh api user` GitHub check and `recipe-settle`'s `--check-ci`
`gh pr checks`/`gh api .../check-runs` probe. So, unlike the Jira side, the **entire** GitHub
posting pipeline — draft, idempotency check, post, ledger — is a single real, standalone,
testable script (`post-github-pr-comment.sh`), and this skill's only job is translating its own
invocation syntax into that script's flags and reporting the result. There is no MCP call
anywhere in this skill's own workflow.

## Synthetic issue-key convention

GitHub PRs have no Jira issue key of their own, but `sync-ledger.sh key <event_id> <issue_key>
[--phase N] [--wave W]`'s signature needs an `<issue_key>`-shaped argument to compute a ledger key.
`post-github-pr-comment.sh` resolves this as:

- if `--issue KEY` was passed (this PR's phase is also linked to a real Jira issue) — use that
  real key, exactly matching the convention the Jira side already uses;
- otherwise — use a synthetic `pr-<PR_NUMBER>` value instead.

This keeps every GitHub-only PR (no linked tracker issue) idempotent on its own terms, without
inventing a fake Jira-shaped key or silently colliding two unrelated PRs' ledger rows. The ledger
key deliberately never includes a `:commit=` segment (unlike `draft-github-pr-comment.sh`'s own
*displayed* idempotency key in the rendered comment body, which does include one) — a milestone
comment is meant to post once per `(event, phase, wave)` tuple, not once per commit, matching
every other `recipe-*` skill's own `sync-ledger.sh key <event> <issue> --phase N [--wave W]` call
shape (e.g. `recipe-settle`'s `sync-ledger.sh key settled <issue_key>`, with no `--commit` either).

## Why no stamp emission

`bench/recipe/trackers/github-events.json`'s 4 entries (`execute_wave`, `execute_complete`,
`review_complete`, `phase_complete`) have **no `"stamp"` field at all** — a structural difference
from `jira-events.json`, whose entries each carry either `"stamp": {...}` or an explicit
`"stamp": null`. This is a real, deliberate difference this skill respects rather than papering
over: there is nothing configured to key a stamp emission off for the GitHub side, and per
`docs/netapp-recipe/lld/TRACEABILITY-LLD.md`'s "GitHub PR events" section, GitHub PR comments are
a **secondary/parallel visibility channel** — when a PR's phase is also linked to a Jira issue,
the Jira side (via `sync-drain-queue.sh mark-done` or `gsd-jira-sync`'s single-event flow) already
owns the canonical KPI stamp for that same milestone. So `post-github-pr-comment.sh` never calls
`emit-stamp.sh`, and this skill never invents a step to do so on its behalf.

## Relationship to draft-github-pr-comment.sh / sync-ledger.sh / gh

| Concern | Owned by |
|---------|----------|
| Templating, git-log/short-SHA resolution, rendering the comment body | `bench/runners/draft-github-pr-comment.sh` (TASK-006) — called, never duplicated |
| Idempotency key computation, ledger read/write | `bench/lib/sync-ledger.sh` (TASK-001) — called, never duplicated |
| Real `gh pr comment` invocation, exit-code/output handling, `--repo` resolution | `bench/runners/post-github-pr-comment.sh` (this task's own new script) |
| Translating `<event_id> <pr_number> [...]` into the runner's flags, reporting the result | `recipe-pr-comment` (this skill) — its only job |

## What this does NOT do

- **Does not post via MCP.** There is no Jira/Atlassian call anywhere in this pipeline —
  `gh pr comment` is a real local CLI call, made directly by the script, never by an agent
  tool call.
- **Does not emit a KPI stamp.** See "Why no stamp emission" above.
- **Does not fabricate a result.** Every `posted` this skill ever reports corresponds to a real,
  successful `gh pr comment` exit `0`, confirmed by the runner before it ever appends a ledger row.
- **Does not touch `.gsd-recipe/config.json`, `.planning/config.json`, or any already-built
  `recipe-*`/`gsd-jira-sync`/`tracker-sync` skill's own files.**
