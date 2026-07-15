# Native GSD commands (recipe subset)

Invoke by **skill name** in Cursor Agent chat (e.g. `gsd-plan-phase 1`). Not a CLI — the agent runs workflows.

Full catalog: [open-gsd/gsd-core](https://github.com/open-gsd/gsd-core) · parent repo [docs/GSD-COMMANDS.md](../GSD-COMMANDS.md) when cloned in gsd-benchmark.

---

## Commands used in this recipe

| Command | Role in recipe flow |
|---------|---------------------|
| **gsd-new-project** | Greenfield init → REQUIREMENTS, ROADMAP, STATE |
| **gsd-discuss-phase** *N* | Phase vision → `CONTEXT.md` |
| **gsd-plan-phase** *N* | PLAN.md + plan-check |
| **gsd-execute-phase** *N* | Build waves, commits, SUMMARY.md |
| **gsd-verify-work** *N* | Conversational UAT (not production sign-off) |
| **gsd-code-review** *N* | Phase code review → REVIEW.md |
| **gsd-ship** | PR / merge handoff |
| **gsd-extract-learnings** *N* | Learnings after phase (optional) |
| **gsd-import** | Brownfield plan ingest |
| **gsd-progress** | Status / what's next |
| **gsd-help** | Skill discovery |

## Recipe-specific (built)

| Command | Role |
|---------|------|
| **gsd-jira-sync** | Mirror milestones to Jira — [SKILL.md](reference/skills/gsd-jira-sync/SKILL.md) |

## Health

`/gsd-health` in Cursor before pilot work.

## Benchmark only (gsd-benchmark repo)

```text
→ ./bench/runners/finalize-run.sh gsd run-01
→ bench/grade/grade.sh   # not gsd-verify-work
```

Omit when sharing only `docs/netapp-recipe/`.
