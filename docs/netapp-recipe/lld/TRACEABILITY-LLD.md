# Traceability LLD (p3)

Run flow: [README.md](../README.md). Agents: [AGENTS.md](../AGENTS.md).

Related: [DATA-CONTRACTS.md](../contracts/DATA-CONTRACTS.md) · [FAILURE-MATRIX.md](FAILURE-MATRIX.md) · [BACKLOG.md](../BACKLOG.md)

---

## Principles

1. Milestone comments on Jira + GitHub — not every commit.
2. GSD stays orchestrator; traceability mirrors artifacts.
3. Idempotent posts via `.gsd-recipe/sync-ledger.jsonl`.
4. **Settled** = PO + CI green.
5. Jira sync is **comment + status**: when `jira-events.json` names a `transition`, `gsd-jira-sync` must apply it (warn-and-continue if the board has no matching transition). New tickets are assigned (`--assignee` / config `assignee` / git user.name) and moved to **To Do**.

---

## Event catalogs

| Tracker | File |
|---------|------|
| Jira | [reference/harness/recipe/trackers/jira-events.json](../reference/harness/recipe/trackers/jira-events.json) |
| GitHub PR | [reference/harness/recipe/trackers/github-events.json](../reference/harness/recipe/trackers/github-events.json) |

### Jira events → stamp (summary)

| `event_id` | GSD trigger | Post to |
|------------|-------------|---------|
| `intake_started`, `discuss_complete` | project / discuss | **Epic** |
| `plan_complete`, `execute_*`, `verify_complete`, `review_complete`, `settled`, … | phase milestones | **Phase task** |

Phase-task transitions roll up status-only: active child work starts a To Do Epic; `settled`
marks its phase task Done; the Epic reaches Done only when every phase task recorded in
`.planning/STATE.md` is in Jira's Done status category. Roll-up adds no second comment or stamp.

Full table + stamps: see `jira-events.json`.

<a id="github-pr-events"></a>
### GitHub PR events

`execute_wave`, `execute_complete`, `review_complete`, `phase_complete` — template: `_comment.template.md` in [github-pr-comments/](../reference/harness/recipe/templates/github-pr-comments/).

---

## Templates

Single placeholder skeleton per channel (agent fills from `.planning/`):

- Jira: [jira-comments/_comment.template.md](../reference/harness/recipe/templates/jira-comments/_comment.template.md)
- GitHub: [github-pr-comments/_comment.template.md](../reference/harness/recipe/templates/github-pr-comments/_comment.template.md)

Install copies (v1 jira + github):

- `.templates/jira-comment.template.md` ← [jira-comments/_comment.template.md](../reference/harness/recipe/templates/jira-comments/_comment.template.md)
- `.templates/github-pr-comment.template.md` ← [github-pr-comments/_comment.template.md](../reference/harness/recipe/templates/github-pr-comments/_comment.template.md)

---

## Draft scripts

| Script | Purpose |
|--------|---------|
| [draft-jira-comment.sh](../reference/harness/runners/draft-jira-comment.sh) | stdout only; no Jira post |
| [draft-github-pr-comment.sh](../reference/harness/runners/draft-github-pr-comment.sh) | stdout only; then `gh pr comment` |
| [emit-stamp.sh](../reference/harness/runners/emit-stamp.sh) | Append KPI stamp |

Skill: [gsd-jira-sync](../reference/skills/gsd-jira-sync/SKILL.md) posts via Atlassian MCP.

---

## Idempotency

Key format (see [DATA-CONTRACTS](../contracts/DATA-CONTRACTS.md#sync-ledger-jsonl)):

```text
gsd-recipe:{event_id}:phase={N}:wave={W}:commit={SHORT_SHA}:issue={ISSUE_KEY}
```

1. Compute key → check ledger → skip if exists (`duplicate_skipped`).
2. On successful post → append ledger line with `target: jira` or `github`.

---

## Near-RT reconciler (spec — TASK-003)

`sync-reconcile.sh` watches `.planning/` mtimes + `git log`, infers `event_id`, runs draft + post + stamp. Queue backlog: `.gsd-recipe/sync-queue.jsonl` on MCP failure.

---

## Tracker adapter ops

| Op | Purpose |
|----|---------|
| `pull_issue` | Fetch epic/body |
| `create_subissue` | Phase tasks under epic |
| `link` | Parent/child |
| `transition` | Status on approve |
| `comment` | Milestone body |

Jira: Atlassian MCP. GitHub: `gh` CLI.

---

## STATE.md routing

Normative schema: [DATA-CONTRACTS § STATE](../contracts/DATA-CONTRACTS.md#state-md). Parser: TASK-002.

---

## KPI stamps

Emit via `emit-stamp.sh` after successful Jira post. See [README.md](../README.md).

---

## See also

- [BACKLOG.md](../BACKLOG.md) § Testing — P-1–P-3 verification
- [BACKLOG.md](../BACKLOG.md) — TASK-001, 003, 006
