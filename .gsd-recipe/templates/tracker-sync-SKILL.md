---
name: tracker-sync
description: "Recipe: tracker-agnostic front door for GSD lifecycle sync (TASK-014). Reads .gsd-recipe/config.json's tracker field and dispatches to the tracker-specific skill — today that's gsd-jira-sync for tracker: jira; github is not yet wired (needs TASK-006)."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke when the user says `tracker-sync` (or expects the recipe to "just know"
which tracker to post to, without having to name `gsd-jira-sync` directly).

Arguments: `{{GSD_ARGS}}` — passed through unchanged to whichever
tracker-specific skill this dispatches to.

## B. Prerequisites

- `.gsd-recipe/config.json` may or may not exist. If missing (or missing a
  `tracker` key), the configured tracker defaults to `jira` — the only
  fully-built path today (see § Scope below).
- Whatever the dispatched-to skill's own prerequisites are (e.g.
  `gsd-jira-sync`'s Atlassian MCP requirement).

## C. Tool Usage

1. `Shell`: `bench/lib/tracker-sync-config.sh get-tracker` (bundled harness
   path before copy: `docs/netapp-recipe/reference/harness/lib/tracker-sync-config.sh`,
   if present — otherwise use the installed `bench/lib/tracker-sync-config.sh`).
2. Branch on the result:
   - **`jira`** — invoke the `gsd-jira-sync` skill with `{{GSD_ARGS}}`
     unchanged. Follow *its* `SKILL.md` for everything from here (single-event
     mode and Drain mode both apply). `tracker-sync` does not duplicate any of
     that logic — it is a naming/dispatch layer only.
   - **`github`** — **stop** and tell the operator: "GitHub tracker sync isn't
     implemented yet (needs TASK-006, `draft-github-pr-comment.sh`). Use
     `gh pr comment` manually for now, or run
     `tracker-sync-config.sh set-tracker jira` to switch back." Do not attempt
     to post via `gh` yourself as a substitute — that would silently diverge
     from the ledger/stamp/queue machinery every other event goes through.
   - **anything else** — the config accessor already fails closed on this
     (see its own error message); surface that error to the operator rather
     than guessing a tracker.

## D. Do NOT

- Reimplement Jira-posting logic here — always delegate to `gsd-jira-sync`
  for `tracker: jira`. This skill's only job is reading config and routing.
- Silently fall back to `gh pr comment` (or any other ad hoc posting) when
  `tracker: github` — that bypasses the ledger and queue entirely, breaking
  idempotency for every subsequent event on that issue.
- Assume `tracker: jira` without checking config first, even though it's the
  default — an operator may have deliberately set `github` and expects the
  "not implemented" message, not a silent Jira post to the wrong tracker.
</cursor_skill_adapter>

# tracker-sync — GSD recipe: tracker-agnostic dispatch (TASK-014)

## Scope (read this before extending)

This skill is deliberately narrow. `INSTALL-LLD.md`'s `{TRACKER}` placeholder
table lists `jira`, `github_issues`, `linear` as illustrative examples, but
`DECISIONS.md`'s **locked v1 decision** is only **Jira + GitHub** — and today
only the Jira path is fully built end to end (`gsd-jira-sync` skill,
`jira-events.json`, `draft-jira-comment.sh`, `sync-reconcile.sh`,
`sync-drain-queue.sh`, `sync-ledger.sh`). GitHub tracker-sync needs TASK-006
(`draft-github-pr-comment.sh`) before it can do anything real, and none of the
already-shipped scripts were rewritten to be tracker-parameterized as part of
this task — `sync-reconcile.sh`/`sync-drain-queue.sh` still write/expect
`target: "jira"` literally.

So TASK-014, as built, is **install-time registration + a thin dispatch
skill**, not a runtime rewrite of the underlying sync machinery. See
[bench/report/tracker-sync-integration-report.md](../../../bench/report/tracker-sync-integration-report.md)
for the full scope decision and what a future full-generalization pass would
still need to touch.

## Workflow

1. Read the configured tracker: `tracker-sync-config.sh get-tracker`.
2. `tracker: jira` → hand off entirely to `gsd-jira-sync` (single-event or
   Drain mode, per its own `SKILL.md`).
3. `tracker: github` → report "not implemented yet, needs TASK-006" and stop.
4. Unsupported value → surface the config accessor's own error.

## Switching trackers

```bash
bench/lib/tracker-sync-config.sh set-tracker jira    # default, fully built
bench/lib/tracker-sync-config.sh set-tracker github  # not yet functional (TASK-006)
```

## Relationship to gsd-jira-sync

`tracker-sync` is a thin front door; `gsd-jira-sync` remains the actual
implementation for Jira and is unchanged by this task. Operators who already
know they're on Jira can keep invoking `gsd-jira-sync` directly — nothing
about this skill is required. `tracker-sync` exists for flows (or future
install tooling) that shouldn't need to know which tracker is configured.
