# NetApp GSD Recipe

NetApp GSD recipe for Cursor: structured feature delivery from PRD through planning, execution, verification, and tracker sync. Install into your project repo with `bench/runners/install-recipe-to-target.sh`.

This repository is the **source of truth** for recipe skills (`.gsd-recipe/`), installers, harness scripts (`bench/`), and integration tests.

**Command reference:** [docs/RECIPE-COMMANDS.md](docs/RECIPE-COMMANDS.md) · In Cursor, invoke **`recipe-help`**

**Benchmarks:** [docs/netapp-recipe/BENCHMARKS.md](docs/netapp-recipe/BENCHMARKS.md) — KB-Evaluations on AgentStudio ([KAN-53](https://netapp.atlassian.net/browse/KAN-53), [PR #465](https://github.com/NetApp-Nemo/AgentStudio/pull/465)): **~3–6 h recipe vs ~2 days ad-hoc** (field benchmark, Jul 2026).

## Quick start (install)

From this repo (or any clone of [NetApp-GSD-Recipe](https://github.com/vs06101996/NetApp-GSD-Recipe.git)):

```bash
./bench/runners/install-recipe-to-target.sh --target /<path-to-repo> --verify
```

Already inside the target repo? Omit `--target` — the installer detects the git root automatically:

```bash
/path/to/gsd-benchmark/bench/runners/install-recipe-to-target.sh --verify
```

Then open the target repo in Cursor and invoke the **`recipe-*`** commands below by name. You do **not** need the benchmark harness scripts in the next section for normal feature delivery.

## Delivery workflow (Cursor)

Typical path for a new feature (example: KB-Evaluations Feature 2). Invoke each command by name in Cursor Agent; `@file` references a file in the chat.

| Command | One-liner use case |
|---------|-------------------|
| `recipe-validate-tokens` | Check GitHub + Jira/Atlassian credentials/scopes before doing recipe work. |
| `recipe-prd-intake KB-Evaluations-Feature2-PRD.md` | Turn the raw PRD into canonical `docs/PRD.md` (+ bootstrap FOTW observer). |
| `recipe-onboard @KB-Evaluations-Feature2-PRD.md` | Full onboarding: project planning + Jira epic + phase tasks in one chain (skips intake if `docs/PRD.md` already exists). |
| `recipe-bootstrap-knowledge` | Build/refresh `.knowledge/` + `/gsd-map-codebase` + **`/gsd-graphify build`** — run once after onboard, before first `recipe-plan-phase` (see Graphify section below). |
| `recipe-plan-phase 1` | Write Phase 1 `PLAN.md` (e.g. TUN architecture & contracts). |
| `recipe-run-phase 1` | Execute Phase 1 plans (implement kb_tune types/contracts). |
| `recipe-run-phases 2 5 --full` | Loop phases 2→5: plan → run → verify → review/ship → settle. |
| `recipe-verify-feature 1` | Verify Phase 1 only (when Phase 1 was planned/run outside the loop above). |
| `recipe-review-ship 1` | Code review + open PR for Phase 1. |
| `recipe-settle 1` | PO accept + CI green gate for Phase 1. |

### How `plan-phase`, `run-phase`, and `run-phases` relate

These are **not** interchangeable — they overlap by scope:

| Pattern | Commands | Meaning |
|---------|----------|---------|
| **AND (same phase)** | `recipe-plan-phase N` **then** `recipe-run-phase N` | Plan first, then execute. Both required when doing one phase manually. |
| **OR (range vs manual)** | `recipe-run-phases 2 5 --full` **instead of** repeating plan/run/verify/ship/settle for phases 2–5 | The loop calls those steps internally per phase. |
| **OR (all phases at once)** | `recipe-run-phases 1 5 --full` **instead of** the split table above | One loop from Phase 1 through 5 (alternative workflow, not additive). |

The table above uses the **split** pattern: Phase 1 manual (plan + run + verify/ship/settle), phases 2→5 via `--full`. Do not also run `recipe-plan-phase 2` … `recipe-run-phase 5` if you already ran `recipe-run-phases 2 5 --full`.

### Graphify — when and where

There is **no** `recipe-graphify` skill. Graphify is wired in three places:

| When | Where | Command |
|------|-------|---------|
| **Once per target repo** (if install reported `graphify: fail`) | Terminal, in the **target repo** | `./.gsd-recipe/scripts/install-graphify.sh` — installs the `graphify` CLI (requires `uv`). Re-run `install.sh --verify` or check `install-report.json`. |
| **After onboard, before planning** | Cursor Agent, **target repo** | `recipe-bootstrap-knowledge` — scaffolds `.knowledge/` and calls native `/gsd-map-codebase [--fast]` + **`/gsd-graphify build`** (writes `.planning/graphs/`). Run once per feature or after large repo changes. |
| **During plan or execute** (explore dependencies) | Cursor Agent, **target repo** | **`/gsd-graphify query <term>`** — ad-hoc lookup while writing or following a `PLAN.md` (optional; use when you need graph context mid-phase). |

`recipe-plan-phase` / `recipe-run-phase` do **not** invoke graphify themselves — bootstrap (or a manual `/gsd-graphify build`) should happen **before** the first `recipe-plan-phase N`. If `graphify` is missing, `recipe-bootstrap-knowledge` still runs map-codebase and warns; planning policy may suggest graphify for complex phases.

Full chain in one line (after install):

```text
recipe-validate-tokens → recipe-onboard → recipe-bootstrap-knowledge  (/gsd-graphify build inside)
  → recipe-plan-phase N → recipe-run-phase N  (AND per phase, OR use recipe-run-phases [<start> <end>] [--full])
  → recipe-sync
```

See [docs/RECIPE-COMMANDS.md](docs/RECIPE-COMMANDS.md) for the complete catalog.

## Benchmark harness (optional)

Only needed if you are running controlled baseline / GSD / recipe benchmark arms in **this** repo — not for installing the recipe into AgentStudio or other target repos.

1. **List / register benchmark tasks:** `./bench/tasks/list.sh` · `./bench/tasks/register.sh --id <name> --path /abs/repo`
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
