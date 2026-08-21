# Agent instructions — NetApp GSD Recipe

Read this before implementing or operating the recipe in Cursor.

---

## Scope

- GSD owns `.planning/` (plans, summaries, reviews).
- Recipe owns **traceability** (Jira/GitHub comments, stamps, ledger) and **harness** under `reference/harness/`.
- User runs GSD skills manually — **do not invoke** `gsd-plan-phase`, `gsd-execute-phase`, etc. on the user's behalf.

---

## Boot sequence

1. [README.md](README.md) — built vs spec, run smoke test, commands
2. [BENCHMARKS.md](BENCHMARKS.md) — field benchmarks (recipe vs ad-hoc) and harness status
3. [BACKLOG.md](BACKLOG.md) — pick `TASK-00N` if implementing (priority-ranked; post-v1 order from [CONTROL-GROUP.md](CONTROL-GROUP.md))
3b. Pickup/tester target: [SANDBOX.md](SANDBOX.md) (`~/Projects/recipe-sandbox`) — not AgentStudio
3c. Fresh clone / lost skills: [CLONE.md](CLONE.md) (bash `install-recipe-to-target.sh` first) — **then** type **`recipe-start`**
4. [DATA-CONTRACTS.md](contracts/DATA-CONTRACTS.md) — required for STATE, ledger, config work
5. **One LLD** for the task:
   - Install → [lld/INSTALL-LLD.md](lld/INSTALL-LLD.md)
   - Runtime / `recipe-*` → [lld/RUNTIME-LLD.md](lld/RUNTIME-LLD.md)
   - Sync / Jira / GitHub → [lld/TRACEABILITY-LLD.md](lld/TRACEABILITY-LLD.md)
   - Observer → [lld/OBSERVER-LLD.md](lld/OBSERVER-LLD.md)

---

## Where to implement

| Artifact | Location |
|----------|----------|
| Canonical harness (share bundle) | `docs/netapp-recipe/reference/harness/` |
| gsd-benchmark implementation | `bench/runners/`, `bench/recipe/` |
| Target repo after install (spec) | `.gsd-recipe/`, `.templates/` (local-only / gitignored on external targets — see INSTALL-LLD) |

Copy pattern: reference → bench; do not invent paths outside [DATA-CONTRACTS](contracts/DATA-CONTRACTS.md) index.

---

## Built workflow — Jira sync

1. Validate `event_id` in [jira-events.json](reference/harness/recipe/trackers/jira-events.json)
2. Resolve issue from args or [STATE.md schema](contracts/DATA-CONTRACTS.md#state-md) (epic vs phase routing)
3. Draft: `reference/harness/runners/draft-jira-comment.sh` (or `./bench/runners/` after copy)
4. Enrich placeholders from `.planning/` artifacts — **no empty comments**
5. Post via Atlassian MCP (`addCommentToJiraIssue`)
6. Stamp: `reference/harness/runners/emit-stamp.sh` per draft footer

Skill detail: [reference/skills/gsd-jira-sync/SKILL.md](reference/skills/gsd-jira-sync/SKILL.md)

---

## Constraints

- **Idempotency:** `.gsd-recipe/sync-ledger.jsonl` per [TRACEABILITY-LLD § Idempotency](lld/TRACEABILITY-LLD.md)
- **Settled:** only after PO confirm + CI green
- **No ic-* + recipe** on the same repo
- **Tests:** `bench/tests/` after TASK-015; CI uses fixtures only (no live Jira)

---

## Suggested task prompts

| Task | Prompt seed |
|------|----------------|
| TASK-001 | Implement sync ledger lib per TRACEABILITY-LLD § Idempotency; tests in `bench/tests/` |
| TASK-002 | Implement STATE parser per DATA-CONTRACTS § STATE; CLI `parse-state.sh --event plan_complete --phase N` |
| TASK-003 | Implement `sync-reconcile.sh --dry-run` per TRACEABILITY-LLD; queue to `sync-queue.jsonl` |
| TASK-010 | Implement idempotent `install.sh` per INSTALL-LLD |
