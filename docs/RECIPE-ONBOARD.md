# recipe-onboard — quick start

Single Cursor skill that runs the full NetApp GSD onboarding chain in one invocation: PRD intake →
project bootstrap → Jira Epic → phase tasks. Skips any step whose artifact already exists.

For the full command catalog, invoke **`recipe-help`** or see [docs/RECIPE-COMMANDS.md](RECIPE-COMMANDS.md). After a first install, type **`recipe-start`** (or **`recipe-help --next`**) to see the next command in plain language.

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Git repo root** | Recipe installers fail closed outside a git repository. |
| **GSD for Cursor (full)** | Installed and verified by recipe install. Manual repair: `npx -y --package=@opengsd/gsd-core@latest -- gsd-core --cursor --global --profile=full` |
| **Recipe skills staged** | At minimum: `recipe-onboard` plus the four skills it chains (see Install below). Full recipe: `recipe-install` or `./.gsd-recipe/scripts/install.sh --yes` |
| **Atlassian MCP** (Epic + phase tasks only) | Authenticated Jira access when steps 4–5 of the chain actually run. Not needed if you only need PRD + `.planning/` bootstrap. |
| **PRD input** (optional) | Jira/Confluence export (`.templates/JIRA-PRD.input.template.md` shape), file path, pasted text, or freeform description. Output is always canonical `docs/PRD.md`. If `docs/PRD.md` already exists, the intake step is skipped. |

## Install

**Full recipe (recommended for a new repo):**

```bash
cd /path/to/your/repo
# In Cursor Agent chat:
recipe-install
```

**Onboard skill only (this repo's benchmark checkout):**

```bash
cd ~/Projects/gsd-benchmark
./.gsd-recipe/scripts/install-recipe-new-project.sh --yes   # bootstrap wrapper (TASK-036)
./.gsd-recipe/scripts/install-recipe-onboard.sh --yes         # orchestrator (TASK-037)

# Chain dependencies if not already staged:
./.gsd-recipe/scripts/install-recipe-prd-intake.sh --yes
./.gsd-recipe/scripts/install-recipe-create-epic.sh --yes
./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh --yes
```

Verify staged skills exist:

```bash
ls .cursor/skills/recipe-onboard/SKILL.md
ls .cursor/skills/recipe-prd-intake/SKILL.md   # chain step 1
ls .cursor/skills/recipe-new-project/SKILL.md  # chain step 2 (optional; native fallback exists)
ls .cursor/skills/recipe-create-epic/SKILL.md  # chain step 3
ls .cursor/skills/recipe-create-phase-tasks/SKILL.md  # chain step 4
```

## How to use (Cursor Agent)

Open your repo in Cursor. In Agent chat, invoke by **name** (not `/slash`):

```text
recipe-onboard
```

With a PRD file already on disk:

```text
recipe-onboard docs/PRD.md
```

With Jira project pre-selected (skips live project picker when Epic step runs):

```text
recipe-onboard --project KAN
```

PRD + planning + knowledge, without Jira Epic or phase tasks:

```text
recipe-onboard --skip-tracker
```

That flag still uses one preview-then-confirm gate. Epic and phase-task steps show **skip (flag)**;
knowledge bootstrap still runs. After PRD + `.planning/` succeed, the skill sets
`"onboard": {"skip_tracker": true}`. `recipe-start` opens gitignored
`docs/RECIPE-SEQUENCE.md` with Jira vs skip options.

### What happens

1. **Read-only check** — PRD, ROADMAP, Epic, phase tasks, and knowledge-ready marker.
2. **One preview-then-confirm gate** — shows which of the five steps will **run** vs **skip**.
3. **Chain** (only missing steps):
   - `recipe-prd-intake` → writes `docs/PRD.md` (skipped if that file already exists)
   - `fotw-observer-bootstrap` → starts the fly-on-the-wall observer once `docs/PRD.md` exists,
     including when intake was skipped. No-op if disabled or already active; never blocks onboard.
   - `recipe-new-project` → creates `.planning/*` via native `gsd-new-project --auto` when `docs/PRD.md` (or another file brief) exists. The wrapper answers native config in-turn (`commit_docs: false`, no `git commit` of gitignored `.planning/`). Missing GSD research agents is a warning plus native's inline roadmap — not a hard stop. Fail closed only if the `gsd-new-project` skill file is missing.
   - `recipe-create-epic` → Jira Epic + `intake_started` sync (skipped with `--skip-tracker`)
   - `recipe-create-phase-tasks` → Jira sub-tasks per ROADMAP phase (skipped with `--skip-tracker`)
   - `recipe-bootstrap-knowledge` → mandatory map + graph; verifies and writes
     `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`
4. **Stops the whole chain** on the first step that fails or is declined.
5. **Final summary** — skipped / completed / failed per step. Knowledge failure fails onboarding.

### After onboarding

Knowledge is already complete. Continue with planning:

```text
recipe-plan-phase 1
recipe-run-phase 1
```

Or loop multiple phases: `recipe-run-phases` (optionally `--full` for verify/review/settle).

### Second PRD / new initiative in the same repo

Today `recipe-onboard` **silently skips** when `docs/PRD.md`, `.planning/ROADMAP.md`, Epic, or phase-task keys already exist — so a second feature PRD cannot become the active cycle via onboard alone.

**Planned (TASK-054 / [OD-17](netapp-recipe/DECISIONS.md)):** same command, with a warn + Yes/No gate when planning already exists and you pass a new PRD source:

```text
recipe-onboard docs/PRD-kb-compare-metrics-backend.md
```

- **Yes** → overwrite PRD + re-init `.planning/` + force-relink Epic/phase tasks  
- **No** → keep current planning; agent suggests continuing on the existing ROADMAP (`recipe-bootstrap-knowledge` → `recipe-plan-phase N` …) or settling the current Epic first  

**Until TASK-054 ships**, do it manually:

1. Promote the new PRD into `docs/PRD.md` (`recipe-prd-intake <path>` — confirm overwrite).
2. `recipe-new-project docs/PRD.md` — confirm **re-init**.
3. `recipe-create-epic --force` then `recipe-create-phase-tasks`.
4. Continue with bootstrap → plan → run as usual.

## Step-by-step alternative

Instead of `recipe-onboard`, invoke each skill separately in order:

```text
recipe-prd-intake
recipe-new-project
recipe-create-epic
recipe-create-phase-tasks
```

Use this when you want per-step control or only need one slice of onboarding.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Skill not found | Run the install commands above; restart Cursor or open a new Agent chat. |
| Epic step fails | Confirm Atlassian MCP is authenticated; ensure `docs/PRD.md` exists. |
| Bootstrap uses native GSD directly | Install `recipe-new-project` — `recipe-onboard` falls back to `gsd-new-project` when that sibling skill is missing. |
| `recipe-create-epic` / phase-tasks missing | Run their installers or full `install.sh --yes`. |

## Spec references

- Skill: [.gsd-recipe/templates/recipe-onboard-SKILL.md](../.gsd-recipe/templates/recipe-onboard-SKILL.md)
- Integration report: [bench/report/recipe-onboard-integration-report.md](../bench/report/recipe-onboard-integration-report.md)
- TASK-037: [docs/netapp-recipe/BACKLOG.md](netapp-recipe/BACKLOG.md)
