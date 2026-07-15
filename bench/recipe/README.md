# Recipe customizations (rung 3)

GSD carries the lifecycle; this directory holds **specialization** the orchestrator does not provide out of the box.

## Layout (planned)

```
bench/recipe/
  templates/       # PRD/EPIC structural validators
  kb/              # Seeded team knowledge (read-first, write-back proposals)
  validators/      # Deterministic + semantic checks per step
  stamps/          # emit-stamp helpers → results/recipe/run-NN/stamps.jsonl
  upgrades/        # Banked misses → new checks/skills (compounding)
```

## Built


| Piece       | Path                                              | Purpose                                                                                                                                                                                        |
| ----------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sync ledger | [bench/lib/sync-ledger.sh](../lib/sync-ledger.sh) | Idempotent Jira/GitHub milestone-comment tracking (`key` / `has` / `append`). Contract documented in the script header. Tests: [bench/tests/test-sync-ledger.sh](../tests/test-sync-ledger.sh) |




## First step implemented in docs

[docs/RECIPE-STEP-PRD-TO-STORIES.md](../../docs/RECIPE-STEP-PRD-TO-STORIES.md) — PRD → engineering-ready stories.

## Tracker integration

Recipe stamps should mirror tracker state (Jira EPIC/sub-tasks or GitHub issues). Use Atlassian MCP / `create-jira-ticket` skill when Jira is the SSOT.