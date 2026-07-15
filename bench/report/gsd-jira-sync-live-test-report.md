# gsd-jira-sync — live end-to-end traceability test

**Goal:** prove, against a real `netapp.atlassian.net` Jira site (not mocks),
that the recipe's traceability chain — `.planning/STATE.md` routing →
`draft-jira-comment.sh` → Atlassian MCP `addCommentToJiraIssue` →
`sync-ledger.sh` idempotency — actually works end-to-end for both event
classes defined in `DATA-CONTRACTS.md` rule 7 (epic-routed and phase-routed).

## Why this test needed its own tracker issues

A search of the only Jira project this MCP session can see (`KAN`, "My
Kanban Space") turned up real production issues (e.g. `KAN-19`, an active
epic about S3 buckets on cache volumes). Posting synthetic test comments onto
someone else's live work would be noise pollution, so two disposable,
clearly-labeled issues were created instead:

| Issue | Type | Role |
|---|---|---|
| [`KAN-39`](https://netapp.atlassian.net/browse/KAN-39) | Epic | `## Tracker` epic — target for epic-routed events |
| [`KAN-40`](https://netapp.atlassian.net/browse/KAN-40) | Task | Phase-1 row in `## Phase tasks` — target for phase-routed events |

Both summaries are prefixed `[TEST - safe to ignore/delete]` and their
descriptions state they're disposable GSD recipe test fixtures.

## Prerequisite: MCP auth vs. `JIRA_NGAGE_TOKEN`

The Atlassian MCP (`plugin-atlassian-atlassian`) started this session in a
needs-auth state. `JIRA_NGAGE_TOKEN` — used successfully in the past for the
`create-noc-jira-ticket` skill — could **not** substitute for it: that token
is a Bearer PAT scoped to `jira.ngage.netapp.com` (self-hosted Jira
Server/Data Center), a completely different product/account namespace from
`netapp.atlassian.net` (Atlassian Cloud, OAuth-based), which is what
`gsd-jira-sync` / `TRACEABILITY-LLD.md` actually targets. Resolved by calling
the `mcp_auth` tool, which completed instantly once the user had already
accepted the Cursor↔Atlassian OAuth consent screen in-browser (scopes: read,
search, write on `netapp.atlassian.net`).

## What was exercised (real calls, no mocks)

| # | Step | Mechanism | Result |
|---|---|---|---|
| 1 | Resolve `cloudId` for `netapp.atlassian.net` | `getAccessibleAtlassianResources` | `cb69b23c-616e-461b-9cf1-b3015880f8dd` |
| 2 | Create disposable Epic + phase Task | `createJiraIssue` ×2 | `KAN-39`, `KAN-40` created |
| 3 | Write a real `.planning/STATE.md` pointing at them | manual, per `DATA-CONTRACTS.md#state-md` schema | epic=`KAN-39`, phase 1=`KAN-40` |
| 4 | Validate it | `bench/lib/parse-state.sh validate` | `OK` |
| 5 | Resolve epic-routed event | `parse-state.sh resolve-issue discuss_complete` | → `KAN-39` |
| 6 | Resolve phase-routed event | `parse-state.sh resolve-issue plan_complete --phase 1` | → `KAN-40` |
| 7 | Draft both comment bodies | `draft-jira-comment.sh discuss_complete KAN-39` / `plan_complete KAN-40 --phase 1` | rendered from `_comment.template.md` incl. stamp hint line |
| 8 | Compute idempotency keys | `sync-ledger.sh key ...` | `gsd-recipe:discuss_complete:issue=KAN-39`, `gsd-recipe:plan_complete:phase=1:issue=KAN-40` |
| 9 | Check ledger before posting | `sync-ledger.sh has ...` | both absent (correct — first run) |
| 10 | Post both comments for real | `addCommentToJiraIssue` ×2 | Jira comment ids `10000` (KAN-39), `10001` (KAN-40) |
| 11 | Append to ledger | `sync-ledger.sh append ... --result posted` | 2 lines written to `.gsd-recipe/sync-ledger.jsonl` |
| 12 | Simulate a repeat trigger | `sync-ledger.sh has` on the same key again | returns true → real flow would emit `duplicate_skipped`, not re-post |
| 13 | Independently verify the post landed | fresh `getJiraIssue` read (`fields: comment`) on both issues | comment bodies match byte-for-byte what was posted |
| 14 | Close the loop with lifecycle stamps | `emit-stamp.sh recipe gsd-jira-sync-live-test-01 prd-approved prd KAN-39 agent jira` and the `plan_complete` equivalent for `KAN-40` | 2 lines written to `results/recipe/gsd-jira-sync-live-test-01/stamps.jsonl` |

Every step above hit a real network service (Atlassian Cloud REST API via
MCP) or a real on-disk artifact — nothing was stubbed.

## Result

**PASS.** The full chain works exactly as `TRACEABILITY-LLD.md` /
`DATA-CONTRACTS.md` specify:

- `STATE.md` routing correctly distinguishes epic-routed vs. phase-routed
  events and resolves to the right issue key in both cases.
- The comment template renders and posts cleanly through the real Atlassian
  MCP (markdown → Jira's ADF-backed rendering, confirmed via read-back).
- The idempotency ledger correctly reports "not yet posted" before the first
  post and "already posted" after — which is the exact signal `gsd-jira-sync`
  needs to avoid duplicate comments on repeat triggers.
- Lifecycle stamps write correctly per-arm/run/issue.

## Gaps observed (not bugs — expected, given no real phase artifacts existed)

- `draft-jira-comment.sh`'s template placeholders that depend on
  `.planning/phases/**/PLAN.md`, `CONTEXT.md`, `REVIEW.md`, `SUMMARY.md` all
  rendered as their fallback strings (`(PLAN.md not found yet)`, etc.) since
  this test never ran a real `gsd-plan-phase`/`gsd-execute-phase` cycle
  against the test issues. This is correct fallback behavior, not a defect —
  a real recipe run would have those files and the template would fill in.
- The actual `gsd-jira-sync` **skill** (the Cursor-facing orchestration that
  calls `draft-jira-comment.sh` → MCP → `sync-ledger.sh` in sequence,
  triggered by GSD lifecycle hooks) was exercised here by manually chaining
  its constituent primitives in the same order it would use, rather than by
  invoking the skill's own trigger surface (since no live `gsd-plan-phase`/
  `gsd-execute-phase` run was in flight). The primitives it depends on are
  now proven live; wiring/triggering coverage of the skill's hook surface
  itself is a separate, smaller follow-up if desired.

## Cleanup

`KAN-39` and `KAN-40` are disposable and labeled as such; safe to close or
delete. `.planning/STATE.md`, `.gsd-recipe/sync-ledger.jsonl`, and
`results/recipe/gsd-jira-sync-live-test-01/stamps.jsonl` in this repo are
local test artifacts from this run.
