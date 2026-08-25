# E2E new-user onboard retest diary — 2026-08-24

**Persona:** New hire. Never implemented this recipe. Did not search prior chats or agent transcripts. Did not open AgentStudio or any real product app repo.

**Slack (only):** Recipe lives at `/Users/vs72964/Projects/gsd-benchmark`. Dummy product is `/Users/vs72964/Projects/recipe-sandbox-e2e-retest` (already a git repo). Get the recipe onto that product and onboard a tiny feature.

**Dummy feature:** Hello Widget CLI — a small CLI in this repo that prints `hello widget`. One phase. No production systems.

**Allowed sources used:** Recipe `README.md` (then `docs/RECIPE-ONBOARD.md` because README names it). After install, product `recipe-*` skills and `.gsd-recipe/scripts/recipe-next.sh` / `recipe-status.sh`. Did **not** read BACKLOG, PARALLEL-PICKUP, implementer notes, or other E2E diaries as a guide.

**Branch:** `main` (stayed). No uninstall. No push. No commit. No Jira issues.

---

## Verdict

| Question | Result |
|----------|--------|
| **Overall** | **FRICTION** |
| Pass/fail: new hire can install + start + get PRD/planning **without Jira**, using README or recipe commands only | **PASS with friction** |

Install and `recipe-start` are discoverable from the README. `--skip-tracker` is documented on the README onboard section and on `recipe-onboard` in the product. A new hire can get `docs/PRD.md` + `.planning/ROADMAP.md` without creating an Epic. Native `gsd-new-project` is the painful middle: long interactive workflow, GSD agents not installed on this machine, default wants git commits (forbidden here), and `.planning/` is gitignored by the install.

---

## Time-ordered actions

### 1. README (no install command given in Slack)

Read `/Users/vs72964/Projects/gsd-benchmark/README.md`.

Install command from **Quick start**:

```bash
cd /Users/vs72964/Projects/gsd-benchmark
./bench/runners/install-recipe-to-target.sh --target /Users/vs72964/Projects/recipe-sandbox-e2e-retest --yes --no-open-start
```

Followed README link to `docs/RECIPE-ONBOARD.md` for the no-Jira path: `recipe-onboard --skip-tracker`.

Did **not** type `recipe-install` before skills existed.

**Friction:** README “Onboarding” install subsection still mentions `recipe-install` as if it were the first command in the target repo. The top Quick start + decision tree are clear that the runner is the first-install front door. A skimmer could get stuck. I followed the Quick start table (first clone / no skills → runner).

### 2. Install into dummy product

Ran the runner above. Exit 0. Stayed on `main`.

Skills staged under the product `.cursor/skills/recipe-*`. Install printed: next command `recipe-start`. Jira check recorded `pending` (expected; we are not using Jira).

**Friction:** Long install log. MCP / `agent_skills` paste-only steps. Graphify skipped because project is not GSD-initialized yet.

### 3. `recipe-start` / `recipe-next.sh`

Read product `.cursor/skills/recipe-start/SKILL.md`. Ran:

```bash
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/.gsd-recipe/scripts/recipe-next.sh" --target "$ROOT"
```

**Output (verbatim, first run):**

```
=== Recipe next step ===

Why: There is no docs/PRD.md yet.

Type this in Cursor Agent:

  recipe-onboard
  (no file yet: Agent will ask you to paste or describe the work)

Command: recipe-onboard

This is for files on your current git checkout (branch).
recipe-start may offer to run the command after Yes.
recipe-help --next only prints it.
Catalog:  recipe-help
```

Manager said **Yes** to the recommended command.

**Friction:** Recommended command is `recipe-onboard` **without** `--skip-tracker`. Default preview would **run Epic + phase-task creation** (Jira). README already documents the no-Jira flag. Hard rule: do not create Jira. Declined the default Jira-creating chain and used the documented skip path.

### 4. `recipe-onboard --skip-tracker` (preview)

Read product `recipe-onboard` skill. Artifact check:

| Step | Artifact | Determination |
|------|----------|-----------------|
| PRD intake | `docs/PRD.md` missing | **run** |
| Project bootstrap | `.planning/ROADMAP.md` missing | **run** |
| Epic creation | n/a | **skip (flag: --skip-tracker)** |
| Phase-task creation | n/a | **skip (flag: --skip-tracker)** |

Confirmed this skip-tracker preview (not the default Jira preview).

### 5. `recipe-prd-intake` (chain step)

Read product skill + `.templates/PRD.template.md`. Wrote `docs/PRD.md` from the dummy feature (file/paste/describe path). Required sections filled from the Slack spec (CLI prints `hello widget`, one phase, no production).

Final step: `fotw-observer-bootstrap`. `observer-lib.sh can-spawn` returned allowed. **Did not spawn** a background observer subagent (this session is already a nested agent; spawning a long-running observer would be extra process noise). Record as friction: intake always wants observer spawn.

### 6. `recipe-new-project` → native `gsd-new-project`

`recipe-new-project` is staged. First-init (no ROADMAP yet). Native skill exists at `~/.cursor/skills/gsd-new-project/SKILL.md` (not copied into the product — install says that is expected).

`gsd-tools query init.new-project` from the product repo:

- `planning_exists`: false, `has_git`: true
- `is_brownfield`: true, `needs_codebase_map`: true (tiny dummy tree + recipe files)
- `agents_installed`: **false** (missing `gsd-roadmapper`, researchers, etc.)
- `commit_docs`: true in GSD defaults

**Did not fabricate a fake Epic.** Wrote `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json` as the native workflow’s **inline** path when research subagents are missing. **Did not git commit** (operator hard rule; native GSD wants commits).

**Friction (this is the main one):**

- Native `gsd-new-project` is a long questioning / research / approve-roadmap flow. A new hire with a three-line dummy feature still hits brownfield mapping offer, config questions, and commit gates.
- GSD agents are not installed by recipe install. Workflow says proceed inline.
- `.planning/` is in the product `.gitignore` (install-time). Planning files exist on disk but `git status` does not list them.
- Native GSD ROADMAP template uses `### Phase 1:`; `recipe-status.sh` only numbers phases matching `^## Phase (\d+)`. First status run: `Phases: (none numbered in ROADMAP)`. Adjusted heading to `## Phase 1:` so status could see phase 1. Template mismatch.

### 7. skip_tracker persist

After PRD + planning succeeded with `--skip-tracker`, merged into product `.gsd-recipe/config.json`:

```json
"onboard": { "skip_tracker": true }
```

No Epic key in `.planning/STATE.md`. No KAN issues created.

### 8. End helpers (product repo, `main`)

```bash
bash "$ROOT/.gsd-recipe/scripts/recipe-next.sh" --target "$ROOT"
bash "$ROOT/.gsd-recipe/scripts/recipe-status.sh" --target "$ROOT"
```

**`recipe-next.sh` output:**

```
=== Recipe next step ===

Why: Onboarding looks done; next is repo context for planning.

Type this in Cursor Agent:

  recipe-bootstrap-knowledge

Command: recipe-bootstrap-knowledge

This is for files on your current git checkout (branch).
recipe-start may offer to run the command after Yes.
recipe-help --next only prints it.
Catalog:  recipe-help
```

**`recipe-status.sh` output:**

```
=== Recipe status ===

Branch:          main
Recipe skills:   yes
PRD:             yes  (docs/PRD.md)
ROADMAP:         yes
Knowledge:       yes
Epic:            (skipped)
Phase tasks:     (none)
Current phase:    1
Phases:
  1: PLAN=no  SUMMARY=no
Install Jira:    pending
Verified:        no
Sync queue:      0 pending
Sync ledger:     0 entries
Last sync:       (none)

Suggest next: recipe-start   (offers to run it)
Catalog:      recipe-help

=== Recipe next step ===

Why: Onboarding looks done; next is repo context for planning.

Type this in Cursor Agent:

  recipe-bootstrap-knowledge

Command: recipe-bootstrap-knowledge
```

**Friction:** Status “Suggest next: recipe-start” while the same snapshot’s next-step block says `recipe-bootstrap-knowledge`. Helpers need `--target` when you care about cwd; `--repo` is not a flag (`unknown arg`).

---

## Sources used vs rules

| Rule | Followed? |
|------|-----------|
| Only README + links from README, then product recipe commands | Yes (`RECIPE-ONBOARD.md` linked from README) |
| No BACKLOG / E2E diaries / PARALLEL-PICKUP as a guide | Yes |
| No `recipe-install` before skills | Yes |
| Stay on `main` | Yes |
| No Jira | Yes (`--skip-tracker`) |
| No uninstall / push / commit | Yes |
| No edit of gsd-benchmark except this diary | Yes |
| Do not invent `.planning/*` if native GSD fail-closed | Native skill **was** present; agents missing → inline artifacts. Not a fail-closed “no gsd-new-project skill” stop. |

---

## Artifacts (dummy product)

| Artifact | Present? | Notes |
|----------|----------|--------|
| `docs/PRD.md` | Yes | From `recipe-prd-intake` |
| `.planning/ROADMAP.md` | Yes | One phase; heading adjusted for status parser |
| `.planning/PROJECT.md` / `STATE.md` / `REQUIREMENTS.md` | Yes | Native GSD-shaped; **gitignored** |
| `onboard.skip_tracker` | **true** | `.gsd-recipe/config.json` |
| Epic / KAN | **None** | Intentionally skipped |

---

## Friction list (short)

1. `recipe-start` Yes-path recommends `recipe-onboard` (Jira chain) even when the operator must not create tickets; skip flag is documented but not the default next step.
2. Native `gsd-new-project` is not a one-shot “eat this PRD” command; recipe install does not install GSD agents.
3. Native default wants to commit planning docs; this retest forbids commits.
4. Install gitignores `.planning/`.
5. ROADMAP heading convention (`###` vs `## Phase N`) disagrees with `recipe-status.sh`.
6. `recipe-prd-intake` wants a FOTW observer subagent.
7. `recipe-next.sh` without `--target` can mis-detect root; `--repo` is invalid.

---

## Overall

**FRICTION.** Criterion **PASS with friction**: a new hire who reads the README Quick start + onboard `--skip-tracker` line can install, start, write a PRD, skip Jira, and obtain planning files. They will still struggle with native GSD bootstrap (agents, commits, gitignore, ROADMAP format) unless they treat `gsd-new-project` as a long interactive skill and ignore git commits.
