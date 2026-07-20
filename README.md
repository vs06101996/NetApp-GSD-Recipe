# NetApp GSD Recipe

NetApp GSD recipe for Cursor: structured feature delivery from PRD through planning, execution, verification, and tracker sync. Install into your project repo with `bench/runners/install-recipe-to-target.sh`.

This repository is the **source of truth** for recipe skills (`.gsd-recipe/`), installers, harness scripts (`bench/`), and integration tests.

## Quick start (recipe install)

1. **Install recipe into a target repo:** `./bench/runners/install-recipe-to-target.sh --target /path/to/your/repo --verify`
2. **List / register benchmark tasks (optional):** `./bench/tasks/list.sh` · `./bench/tasks/register.sh --id <name> --path /abs/repo`
2. **Validate grading (no LLM):** `./bench/runners/validate-pipeline.sh`
3. **Prepare a run:** `./bench/runners/prepare-run.sh runs/baseline/run-01`
4. **Grade an artifact:** `./bench/grade/grade.sh results/baseline/run-01/artifact`
5. **Full workflow:** [RUNBOOK.md](RUNBOOK.md)
6. **Aggregate results:** `python3 bench/report/aggregate.py`

## Layout

- `config.yaml` — `active_task`, model, runs per arm
- `tasks/<id>/task.yaml` — task manifest (mode, source, go module)
- `tasks/<id>/SPEC.md` — agent-facing PRD
- `tasks/<id>/grader/` — hidden acceptance tests (agents must not read)
- `tasks/<id>/reference/` — bundled oracle (optional for local tasks)
- `runs/{baseline,gsd,recipe}/run-NN/` — per-run workspace (`workspace/` for brownfield)
- `results/{arm}/run-NN/` — artifact, grade.json, optional `stamps.jsonl` (recipe)
- `features/` — Feature A baseline anchor (historical)
- `bench/recipe/` — rung-3 customizations (templates, KB, validators)
- `bench/lib/resolve-task.sh` — shared task resolution

## Config

Pinned settings: [config.yaml](config.yaml). Override active task: `BENCH_TASK=<id>` or edit `active_task`.

## Summary

**[PROJECT-SUMMARY.md](PROJECT-SUMMARY.md)** — benchmark goals, setup, and results.

| Doc | Contents |
|-----|----------|
| [docs/GSD-COMMANDS.md](docs/GSD-COMMANDS.md) | Full GSD command list + Cursor usage (standard vs full profile) |
| [docs/GSD-TUTORIAL.md](docs/GSD-TUTORIAL.md) | Live tutorial playbook (you run all GSD skills) |
| [docs/GSD-TUTORIAL-PLAYBOOKS.md](docs/GSD-TUTORIAL-PLAYBOOKS.md) | Greenfield PRD vs brownfield feature/bug workflows |
| [docs/GSD-TUTORIAL-SANDBOX.md](docs/GSD-TUTORIAL-SANDBOX.md) | Sibling repo `~/Projects/gsd-tutorial-sandbox` setup |
| [docs/EXPERIMENT-AGENDA.md](docs/EXPERIMENT-AGENDA.md) | Why / what / how — three rungs, metrics, pilot |
| [.planning/ROADMAP.md](.planning/ROADMAP.md) | Implementation phases |
| [docs/GSD-PRODUCT-CONTEXT.md](docs/GSD-PRODUCT-CONTEXT.md) | GSD Core findings |
| [.planning/CONTEXT.md](.planning/CONTEXT.md) | Operator constraints |
