# GSD Benchmark Runbook

## Pluggable tasks

Register **Go** or **Scala/SBT** repos. Full schema: [docs/TASKS.md](docs/TASKS.md).

```bash
./bench/tasks/list.sh

# Scala monorepo (Occm) — SBT root, not occm-go/
./bench/tasks/register.sh --id occm \
  --path /Users/vs72964/Repositories/Occm/cvo/occm-root \
  --scala-compile common/compile

# Go service
./bench/tasks/register.sh --id mysvc --path /absolute/path/to/go/repo

BENCH_TASK=occm ./bench/runners/validate-pipeline.sh   # needs JDK + sbt
```

Brownfield runs copy the repo into `runs/<arm>/run-NN/workspace/` (default). Work there, not in `tasks/<id>/grader/`.

---

## Cursor only (no Claude Code CLI)

Experiment design: [docs/EXPERIMENT-AGENDA.md](docs/EXPERIMENT-AGENDA.md). GSD commands: [docs/GSD-COMMANDS.md](docs/GSD-COMMANDS.md). Live tutorial: [docs/GSD-TUTORIAL.md](docs/GSD-TUTORIAL.md). Workflows (PRD greenfield / brownfield): [docs/GSD-TUTORIAL-PLAYBOOKS.md](docs/GSD-TUTORIAL-PLAYBOOKS.md). **Recipe onboarding:** [docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md). GSD install for **Cursor** (`~/.cursor/skills/gsd-*` and `.cursor/skills/gsd-*`). Limits: [docs/GSD-PRODUCT-CONTEXT.md](docs/GSD-PRODUCT-CONTEXT.md).

**Metrics (baseline / gsd — hand log after run):**

```bash
cp bench/capture/phase-metrics.template.json /tmp/metrics.json
# edit timestamps, reopens, operator
./bench/runners/log-phase-metrics.sh gsd run-01 /tmp/metrics.json
```

**Recipe stamps (rung 3):**

```bash
./bench/runners/emit-stamp.sh recipe run-01 started prd-to-stories EPIC-1
./bench/runners/emit-stamp.sh recipe run-01 engineering-ready prd-to-stories EPIC-1
```

Feature A anchor (already shipped): copy `features/feature-a-baseline.template.json` → `features/feature-a-baseline.json`.

1. Open folder `~/Projects/gsd-benchmark` in Cursor.
2. Check active task: `grep active_task config.yaml` or `./bench/tasks/list.sh`
3. Prepare: `./bench/runners/prepare-run.sh runs/gsd/run-01`
4. **Greenfield:** work in `runs/gsd/run-01/` (SPEC.md at root).
5. **Brownfield:** work in `runs/gsd/run-01/workspace/` (see `RUN_INSTRUCTIONS.md`).
6. Invoke skills by **name** (not `/slash`):
   - **gsd-new-project** (use SPEC.md as brief)
   - **gsd-discuss-phase**, **gsd-plan-phase**, **gsd-execute-phase**, **gsd-verify-work**
7. When done: `./bench/runners/finalize-run.sh gsd run-01`

**Baseline (no GSD):** Same run folder; implement SPEC only; then `finalize-run.sh baseline run-01`.

Reinstall GSD for Cursor:

```bash
node /tmp/gsd-core/bin/install.js --cursor --local --profile=standard
```

---

## Claude Code CLI path (optional)

```bash
claude /login
cd ~/Projects/gsd-benchmark
./bench/runners/run-benchmark.sh 5
```

Exit code `2` means infrastructure OK but login required.

## Prerequisites

- **Cursor:** GSD skills under `.cursor/skills/` (installed)
- **Or** Claude Code: `./bench/runners/check-auth.sh`
- **Go tasks:** Go 1.22+
- **Scala tasks (e.g. occm):** JDK 17+ and **sbt** (`brew install openjdk@17 sbt`, then `./bench/runners/check-sbt.sh`)

## Validate without LLM (any time)

```bash
./bench/runners/validate-pipeline.sh
```

Uses `REF_PATH` from the active task manifest (reference oracle).

## Phase 3 — Smoke

```bash
./bench/runners/smoke-test.sh
```

Copy yolo template after first project init:

```bash
mkdir -p .planning && cp bench/planning/config.yolo.template.json .planning/config.json
```

## Pilot / full — Baseline

```bash
./bench/runners/run-baseline.sh run-01 5
./bench/runners/run-all-baseline.sh 5
```

## Pilot / full — GSD

```bash
./bench/runners/run-gsd.sh run-01
# Follow results/gsd/run-01/GSD_SESSION.md
./bench/runners/finalize-run.sh gsd run-01
```

## Aggregate

```bash
python3 bench/report/aggregate.py
cat REPORT.md
```
