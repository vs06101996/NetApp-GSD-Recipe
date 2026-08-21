# NetApp GSD Recipe

NetApp GSD recipe for Cursor: structured feature delivery from PRD through planning, execution, verification, and tracker sync. Install into your project repo with `bench/runners/install-recipe-to-target.sh`.

This repository is the **source of truth** for recipe skills (`.gsd-recipe/`), installers, harness scripts (`bench/`), and integration tests.

**Command reference:** [docs/RECIPE-COMMANDS.md](docs/RECIPE-COMMANDS.md) · **Onboarding:** [docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md) · In Cursor, invoke **`recipe-help`**

**Benchmarks:** [docs/netapp-recipe/BENCHMARKS.md](docs/netapp-recipe/BENCHMARKS.md) — KB-Evaluations on AgentStudio ([KAN-53](https://netapp.atlassian.net/browse/KAN-53), [PR #465](https://github.com/NetApp-Nemo/AgentStudio/pull/465)): **~3–6 h recipe vs ~2 days ad-hoc** (field benchmark, Jul 2026).

## Prerequisites

Before install or delivery, you need the following on the **machine** and in **Cursor**:

| Category | Requirement | Required? | Checked by |
|----------|-------------|-----------|------------|
| **Environment** | [Cursor](https://cursor.com) with Agent mode | Yes | You |
| **Environment** | Target path is a **git repo** | Yes | `install.sh` (fail closed) |
| **CLI** | `python3` | Yes | `install.sh` preflight |
| **CLI** | `git` | Yes | `install.sh` preflight |
| **CLI** | `node` / `npx` (GSD install) | Soft | `install.sh` preflight (warn) |
| **CLI** | `gh` + `gh auth login` (PR, CI, ship) | Soft | `install.sh` + `recipe-validate-tokens` |
| **CLI** | **GSD** (`gsd-new-project`, `gsd-plan-phase`, …) | Soft | `install.sh` preflight (warn) |
| **CLI** | `graphify` (knowledge graph) | Optional | `install.sh` preflight (warn) — fix: `./.gsd-recipe/scripts/install-graphify.sh` |
| **CLI** | `uv` (only if installing graphify) | Optional | `install-graphify.sh` |
| **Integrations** | **Atlassian MCP** authenticated in Cursor (Jira epic, sync, phase tasks) | Yes for Jira path | `recipe-validate-tokens` + `install.sh --record-jira-check pass` |
| **Integrations** | GitHub repo access (push branch, open PR) | Yes for ship path | `gh auth status` |

**Order of operations:**

1. Install CLI tools above (or let `install.sh` attempt auto-fix for `brew`/`npx`/`uv` paths).
2. Run the **first-install runner** shown below.
3. In Cursor on the target repo, press Enter on the prefilled **`recipe-start`** prompt (or type it). `recipe-status` is an optional read-only snapshot.
4. Use **`recipe-validate-tokens`** when you are ready to confirm GitHub + Atlassian access.
5. Check `.gsd-recipe/install-report.json` → `prereqs` for `python3`, `git`, `gh`, `gsd_core`, `graphify` pass/warn/fail.

Spec detail: [docs/netapp-recipe/lld/INSTALL-LLD.md](docs/netapp-recipe/lld/INSTALL-LLD.md) Steps 0–1.

## Quick start: install into any repo

From this repo (or any clone of [NetApp-GSD-Recipe](https://github.com/vs06101996/NetApp-GSD-Recipe.git)):

```bash
./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes
```

This runner is the **only first-install front door**. Do **not** type `recipe-install` before the recipe skills exist: it is itself one of the skills created by this command.

On an interactive install, the runner may open Cursor with `recipe-start` prefilled. Review it and press **Enter**; the deeplink never submits it automatically. Pass `--no-open-start` to skip opening Cursor. After install, `recipe-start` is the next command; `recipe-status` is optional.

### Install decision tree

| Your situation | Use this path | Why |
|---|---|---|
| **First clone, new laptop, or target has no recipe skills** | From the recipe source clone: `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes` | Bootstraps the skills needed by every `recipe-*` command. |
| **Recipe skills already exist; re-run or restage** | In Cursor on the target: `recipe-install` | Restages through the existing skill after the chicken-and-egg bootstrap is solved. |
| **Recipe is installed; verify health** | In Cursor on the target: `recipe-install-verify` | Runs the post-install checklist without presenting another install front door. |
| **Recipe is installed; uninstall** | In Cursor on the target: `recipe-install --uninstall` | Uses the staged skill's confirmation gate and delegates removal to the installer. |

`install.sh` is an implementation detail already called by the runner and staged skills; operators should not choose it as a competing install command. `bin/recipe install` remains a compatibility-only thin alias of the same runner, not a separate workflow.

Then open the target repo in Cursor and invoke the **`recipe-*`** commands below by name. You do **not** need the benchmark harness scripts in the next section for normal feature delivery.

## Onboarding (`recipe-onboard`)

Single on-ramp for new features: one preview-then-confirm gate, then chains whichever steps are still missing:

```text
recipe-prd-intake → recipe-new-project → recipe-create-epic → recipe-create-phase-tasks
```

| Step | Skill | Artifact |
|------|-------|----------|
| 1 | `recipe-prd-intake` | `docs/PRD.md` |
| 2 | `recipe-new-project` | `.planning/PROJECT.md`, `ROADMAP.md`, `STATE.md` |
| 3 | `recipe-create-epic` | Jira Epic + `intake_started` sync |
| 4 | `recipe-create-phase-tasks` | Jira sub-tasks per ROADMAP phase |

**Prerequisites:** git repo root, GSD skills (`.cursor/skills/gsd-*`), recipe skills staged by the first-install runner above (or restaged later with `recipe-install`), Atlassian MCP when Epic/phase-task steps run.

**Invoke in Cursor Agent** (by name, not `/slash`):

```text
recipe-onboard
recipe-onboard docs/PRD.md
recipe-onboard --project KAN
```

Skips any step whose artifact already exists; stops the whole chain on the first failure. Step-by-step alternative: invoke each skill in the table above separately.

Full install, troubleshooting, and spec links: **[docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md)**.

## Delivery workflow (Cursor)

Typical path for a new feature (example: KB-Evaluations Feature 2). Invoke each command by name in Cursor Agent; `@file` references a file in the chat.

| Command | One-liner use case |
|---------|-------------------|
| `recipe-validate-tokens` | Check GitHub + Jira/Atlassian credentials/scopes before doing recipe work. |
| `recipe-prd-intake KB-Evaluations-Feature2-PRD.md` | Turn the raw PRD into canonical `docs/PRD.md` (+ bootstrap FOTW observer). |
| `recipe-new-project` | Bootstrap `.planning/*` via native `gsd-new-project` (first-init vs re-init gate; prefers `docs/PRD.md` as input). |
| `recipe-onboard @KB-Evaluations-Feature2-PRD.md` | Full onboarding chain above in one command — skips steps whose artifacts already exist. |
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
| [docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md) | `recipe-onboard` quick start — prerequisites, install, chain behavior, troubleshooting |
| [docs/GSD-COMMANDS.md](docs/GSD-COMMANDS.md) | Full GSD command list + Cursor usage (standard vs full profile) |
| [docs/GSD-TUTORIAL.md](docs/GSD-TUTORIAL.md) | Live tutorial playbook (you run all GSD skills) |
| [docs/GSD-TUTORIAL-PLAYBOOKS.md](docs/GSD-TUTORIAL-PLAYBOOKS.md) | Greenfield PRD vs brownfield feature/bug workflows |
| [docs/GSD-TUTORIAL-SANDBOX.md](docs/GSD-TUTORIAL-SANDBOX.md) | Sibling repo `~/Projects/gsd-tutorial-sandbox` setup |
| [docs/EXPERIMENT-AGENDA.md](docs/EXPERIMENT-AGENDA.md) | Why / what / how — three rungs, metrics, pilot |
| [.planning/ROADMAP.md](.planning/ROADMAP.md) | Implementation phases |
| [docs/GSD-PRODUCT-CONTEXT.md](docs/GSD-PRODUCT-CONTEXT.md) | GSD Core findings |
| [.planning/CONTEXT.md](.planning/CONTEXT.md) | Operator constraints |
