# NetApp GSD Recipe

Structured feature delivery in Cursor: PRD → planning → execution → verification → Jira/GitHub sync.

In Cursor, type **`recipe-help`** for the command catalog, **`recipe-start`** for the next step (it also **checks** for recipe-source updates and tells you to type `recipe-update` if any; it does not restage).

## 1. Install

From a clone of this repo, into your product repo:

```bash
./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes --no-open-start
```

Then open the target repo in Cursor and type:

```text
recipe-start
```

This runner is the **only** first-install front door. Do **not** type `recipe-install` before the recipe skills exist — it is one of the skills this command creates.

## 2. Start work

Type these by name in Cursor Agent (not `/slash`).

| You have | Type this |
|----------|-----------|
| A Jira/Confluence PRD export | `recipe-onboard @docs/input/my-feature-prd.md` |
| An existing Jira ticket | `recipe-onboard KAN-53` or a browse URL (links the ticket; does not create a second Epic) |
| A bug or small fix, no Jira | `recipe-onboard --skip-tracker` |
| A feature and you want Jira Epic + tasks | `recipe-onboard` |
| Nothing written yet | `recipe-onboard` (it asks you to paste or describe) |

Onboard runs PRD intake → FOTW observer bootstrap → planning bootstrap → optional Jira → knowledge bootstrap. It skips steps whose artifacts already exist and stops on the first failure. Observer bootstrap still runs when intake is skipped because `docs/PRD.md` already exists.

**PRD input:** Jira/Confluence 15-section PRDs are **input only**. Fill or paste one using `.templates/JIRA-PRD.input.template.md`; intake always writes canonical `docs/PRD.md`.

## 3. Deliver

```text
recipe-plan-phase N → recipe-run-phase N → recipe-verify-feature N → recipe-review-ship N → recipe-settle N
```

Or run a range end-to-end: `recipe-run-phases 1 5 --full`

## 4. What you need

| Requirement | Note |
|-------------|------|
| Cursor with Agent mode, target is a **git repo** | Install fails closed otherwise |
| `python3`, `git` | Hard requirement |
| GSD for Cursor (full profile) | Installed automatically; install fails if it can't verify |
| `graphify` | Required to finish onboard — fix with `./.gsd-recipe/scripts/install-graphify.sh`. `install.sh` prepends `$HOME/bin` for the rest of that process after auto-install; new shells still need that PATH. |
| Atlassian MCP | Jira ticket fetch, Epic create, and sync |
| `gh` + `gh auth login` | Only for PR / ship |

Stuck? `recipe-help --stuck` · Health check: `recipe-install-verify` · Snapshot: `recipe-status`

---

# Reference

Everything below is detail. The four sections above are enough to install and ship.

## Full prerequisites

| Category | Requirement | Required? | Checked by |
|----------|-------------|-----------|------------|
| **Environment** | [Cursor](https://cursor.com) with Agent mode | Yes | You |
| **Environment** | Target path is a **git repo** | Yes | `install.sh` (fail closed) |
| **CLI** | `python3` | Yes | `install.sh` preflight |
| **CLI** | `git` | Yes | `install.sh` preflight |
| **CLI** | `node` / `npx` (GSD install) | Soft | `install.sh` preflight (warn) |
| **CLI** | `gh` + `gh auth login` (PR, CI, ship) | Soft | `install.sh` + `recipe-validate-tokens` |
| **CLI** | **GSD for Cursor, full profile** (`gsd-new-project`, knowledge commands + agents) | Yes | `install.sh` auto-installs and fails closed if verification fails |
| **CLI** | `graphify` (knowledge graph) | Required to finish onboard | Install auto-fix prepends `$HOME/bin` for the rest of that `install.sh` process; knowledge bootstrap fails closed if still missing — fix: `./.gsd-recipe/scripts/install-graphify.sh` |
| **CLI** | `uv` (only if installing graphify) | Optional | `install-graphify.sh` |
| **Integrations** | **Atlassian MCP** authenticated in Cursor (Jira epic, sync, phase tasks) | Yes for Jira path | `recipe-validate-tokens` + `install.sh --record-jira-check pass` |
| **Integrations** | GitHub repo access (push branch, open PR) | Yes for ship path | `gh auth status` |

After install, check `.gsd-recipe/install-report.json` → `prereqs` for `python3`, `git`, `gh`, `gsd_core`, `graphify` pass/warn/fail.

Spec detail: [docs/netapp-recipe/lld/INSTALL-LLD.md](docs/netapp-recipe/lld/INSTALL-LLD.md) Steps 0–1.

## Install decision tree

| Your situation | Use this path | Why |
|---|---|---|
| **First clone, new laptop, or target has no recipe skills** | From the recipe source clone: `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes --no-open-start` | Bootstraps the skills needed by every `recipe-*` command. |
| **Recipe skills already exist; re-run or restage** | In Cursor on the target: `recipe-install` | Restages through the existing skill after the chicken-and-egg bootstrap is solved. |
| **Recipe is installed; verify health** | In Cursor on the target: `recipe-install-verify` | Runs the post-install checklist without presenting another install front door. |
| **Recipe is installed; uninstall** | In Cursor on the target: `recipe-install --uninstall` | Uses the staged skill's confirmation gate and delegates removal to the installer. |

On an interactive install, the runner may open Cursor with `recipe-start` prefilled. Review it and press **Enter**; the deeplink never submits it automatically. Pass `--no-open-start` to skip opening Cursor.

`install.sh` is an implementation detail already called by the runner and staged skills; operators should not choose it as a competing install command. `bin/recipe install` remains a compatibility-only thin alias of the same runner, not a separate workflow.

## Onboarding chain (`recipe-onboard`)

One preview-then-confirm gate. With no new PRD source, it resumes and chains whichever steps
are missing. An explicit source starts fresh on a new `gsd/<slug>` initiative branch by default,
so an old ROADMAP/STATE/tracker queue can never drive the new work.

```text
recipe-prd-intake → recipe-new-project → recipe-create-epic → recipe-create-phase-tasks
→ recipe-bootstrap-knowledge
```

| Step | Skill | Artifact |
|------|-------|----------|
| 1 | `recipe-prd-intake` | `docs/PRD.md` (from Jira issue key/URL, Jira/Confluence export, canonical PRD, or freeform) |
| 1b | `fotw-observer-bootstrap` | Starts the observer once a PRD exists (also when intake is skipped; no-op if already active) |
| 2 | `recipe-new-project` | `.planning/PROJECT.md`, `ROADMAP.md`, `STATE.md` |
| 3 | `recipe-create-epic` | Jira Epic + `intake_started` sync (skipped with `--skip-tracker`) |
| 4 | `recipe-create-phase-tasks` | Jira sub-tasks per ROADMAP phase (skipped with `--skip-tracker`) |
| 5 | `recipe-bootstrap-knowledge` | Verified codebase map + graph; writes knowledge-ready marker |

`--skip-tracker` skips only Epic/tasks; intake, planning, and knowledge bootstrap still run, then it sets `onboard.skip_tracker`. After Yes on onboard, it asks whether to create Jira. `recipe-start` opens gitignored `docs/RECIPE-SEQUENCE.md`.

`recipe-onboard <source>` always means a new cycle. Before intake it snapshots the current
initiative and creates `gsd/<slug>` (`--branch NAME` overrides). The new branch starts without
the prior `.planning/`, untracked PRDs, phase-task queue, sync ledger, knowledge marker, or
`onboard.skip_tracker`. `--no-branch` explicitly stays on the current branch and archives that
state under `.gsd-recipe/workspace-archives/`. `recipe-onboard` with no source remains resume
mode. Branch switching saves/restores each initiative automatically.

Variants:

```text
recipe-onboard
recipe-onboard KAN-53
recipe-onboard https://netapp.atlassian.net/browse/KAN-53
recipe-onboard @docs/input/my-feature-prd.md
recipe-onboard docs/PRD.md
recipe-onboard docs/PRD.md --branch gsd/object-store-reconcile
recipe-onboard docs/PRD.md --no-branch
recipe-onboard --skip-tracker
recipe-onboard --project KAN
```

Full install, troubleshooting, and spec links: **[docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md)**.

## PRD input (Jira / Confluence)

NetApp 15-section Jira/Confluence PRDs are **input only**. `recipe-prd-intake` (and onboard) map them to canonical `docs/PRD.md`.

| What | Path |
|------|------|
| Input skeleton | `.templates/JIRA-PRD.input.template.md` |
| Section mapping | `.templates/JIRA-PRD.input.MAPPING.md` |
| Canonical output | `.templates/PRD.template.md` → `docs/PRD.md` |

Do not write the 15-section form to `docs/PRD.md`. Discover this path with `recipe-help` (or `recipe-help --stuck`).

## Command catalog

| Command | One-liner use case |
|---------|-------------------|
| `recipe-validate-tokens` | Check GitHub + Jira/Atlassian credentials/scopes before doing recipe work. |
| `recipe-prd-intake KAN-53` | Fetch a Jira issue (or map a file/paste) → canonical `docs/PRD.md` (+ FOTW observer). |
| `recipe-new-project` | Bootstrap `.planning/*` via native `gsd-new-project` (first-init vs re-init gate; prefers `docs/PRD.md` as input). |
| `recipe-onboard [source]` | Resume with no source; with a source, create a clean initiative branch and onboard fresh. |
| `recipe-workspace status` | Show per-branch initiative snapshots; branch checkout swaps planning and tracker state automatically. |
| `recipe-bootstrap-knowledge` | Build/refresh `.knowledge/` + `/gsd-map-codebase` + **`/gsd-graphify build`** — automatic during onboard; run manually to refresh. |
| `recipe-plan-phase 1` | Write Phase 1 `PLAN.md`. |
| `recipe-run-phase 1` | Execute Phase 1 plans. |
| `recipe-run-phases 2 5 --full` | Loop phases 2→5: plan → run → verify → review/ship → settle. |
| `recipe-verify-feature 1` | Verify Phase 1 only (when planned/run outside the loop). |
| `recipe-review-ship 1` | Code review + open PR for Phase 1. |
| `recipe-settle 1` | PO accept + CI green gate for Phase 1. |

Complete generated catalog: [docs/RECIPE-COMMANDS.md](docs/RECIPE-COMMANDS.md)

### How `plan-phase`, `run-phase`, and `run-phases` relate

These are **not** interchangeable — they overlap by scope:

| Pattern | Commands | Meaning |
|---------|----------|---------|
| **AND (same phase)** | `recipe-plan-phase N` **then** `recipe-run-phase N` | Plan first, then execute. Both required when doing one phase manually. |
| **OR (range vs manual)** | `recipe-run-phases 2 5 --full` **instead of** repeating plan/run/verify/ship/settle for phases 2–5 | The loop calls those steps internally per phase. |
| **OR (all phases at once)** | `recipe-run-phases 1 5 --full` **instead of** the split table above | One loop from Phase 1 through 5 (alternative workflow, not additive). |

Do not also run `recipe-plan-phase 2` … `recipe-run-phase 5` if you already ran `recipe-run-phases 2 5 --full`.

## Graphify — when and where

There is **no** `recipe-graphify` skill. Graphify is wired in three places:

| When | Where | Command |
|------|-------|---------|
| **Once per target repo** (if install reported `graphify: fail`) | Terminal, in the **target repo** | `./.gsd-recipe/scripts/install-graphify.sh` — installs the `graphify` CLI (requires `uv`; `uv tool install` is `--quiet` unless `GRAPHIFY_INSTALL_VERBOSE=1`). Re-run `install.sh --verify` or check `install-report.json`. New shells need `export PATH="$HOME/bin:$PATH"`. |
| **During `recipe-onboard` (automatic)** | Cursor Agent, **target repo** | `recipe-bootstrap-knowledge` — mandatory final onboard step; maps code, builds the graph, then writes the readiness marker. |
| **During plan or execute** (explore dependencies) | Cursor Agent, **target repo** | **`/gsd-graphify query <term>`** — ad-hoc lookup while writing or following a `PLAN.md`. |

`recipe-plan-phase` / `recipe-run-phase` do **not** invoke graphify themselves. Onboard must verify knowledge first via `recipe-verify-knowledge.sh`; if graphify cannot run, onboarding fails.

Guardrails (staged under `.gsd-recipe/scripts/`): `recipe-verify-knowledge.sh`, `recipe-verify-planning.sh`, `graphify-probe.sh`, `recipe_knowledge.py`.

## Benchmarks

[docs/netapp-recipe/BENCHMARKS.md](docs/netapp-recipe/BENCHMARKS.md) — KB-Evaluations on AgentStudio ([KAN-53](https://netapp.atlassian.net/browse/KAN-53), [PR #465](https://github.com/NetApp-Nemo/AgentStudio/pull/465)): **~3–6 h recipe vs ~2 days ad-hoc** (field benchmark, Jul 2026).

### Benchmark harness (optional)

Only needed if you are running controlled baseline / GSD / recipe benchmark arms in **this** repo — not for installing the recipe into target repos.

1. **List / register benchmark tasks:** `./bench/tasks/list.sh` · `./bench/tasks/register.sh --id <name> --path /abs/repo`
2. **Validate grading (no LLM):** `./bench/runners/validate-pipeline.sh`
3. **Prepare a run:** `./bench/runners/prepare-run.sh runs/baseline/run-01`
4. **Grade an artifact:** `./bench/grade/grade.sh results/baseline/run-01/artifact`
5. **Full workflow:** [RUNBOOK.md](RUNBOOK.md)
6. **Aggregate results:** `python3 bench/report/aggregate.py`

## Repository layout

This repository is the **source of truth** for recipe skills (`.gsd-recipe/`), installers, harness scripts (`bench/`), and integration tests.

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

Pinned settings: [config.yaml](config.yaml). Override active task: `BENCH_TASK=<id>` or edit `active_task`.

## Documentation index

**[PROJECT-SUMMARY.md](PROJECT-SUMMARY.md)** — benchmark goals, setup, and results.

| Doc | Contents |
|-----|----------|
| [docs/RECIPE-COMMANDS.md](docs/RECIPE-COMMANDS.md) | Generated command catalog |
| [docs/RECIPE-ONBOARD.md](docs/RECIPE-ONBOARD.md) | `recipe-onboard` quick start — prerequisites, install, chain behavior, troubleshooting |
| [docs/GSD-COMMANDS.md](docs/GSD-COMMANDS.md) | Full GSD command list + Cursor usage (standard vs full profile) |
| [docs/GSD-TUTORIAL.md](docs/GSD-TUTORIAL.md) | Live tutorial playbook (you run all GSD skills) |
| [docs/GSD-TUTORIAL-PLAYBOOKS.md](docs/GSD-TUTORIAL-PLAYBOOKS.md) | Greenfield PRD vs brownfield feature/bug workflows |
| [docs/GSD-TUTORIAL-SANDBOX.md](docs/GSD-TUTORIAL-SANDBOX.md) | Sibling repo `~/Projects/gsd-tutorial-sandbox` setup |
| [docs/EXPERIMENT-AGENDA.md](docs/EXPERIMENT-AGENDA.md) | Why / what / how — three rungs, metrics, pilot |
| [.planning/ROADMAP.md](.planning/ROADMAP.md) | Implementation phases |
| [docs/GSD-PRODUCT-CONTEXT.md](docs/GSD-PRODUCT-CONTEXT.md) | GSD Core findings |
| [.planning/CONTEXT.md](.planning/CONTEXT.md) | Operator constraints |
