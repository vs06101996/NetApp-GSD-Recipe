# recipe-onboard — quick start

Single Cursor skill that runs the full NetApp GSD onboarding chain in one invocation: PRD intake →
project bootstrap → Jira Epic → phase tasks. Skips any step whose artifact already exists.

For the full command catalog, invoke **`recipe-help`** or see [docs/RECIPE-COMMANDS.md](RECIPE-COMMANDS.md).

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Git repo root** | Recipe installers fail closed outside a git repository. |
| **GSD for Cursor** | Native skills under `.cursor/skills/gsd-*` (e.g. `gsd-new-project`, `gsd-plan-phase`). Install: `node /path/to/gsd-core/bin/install.js --cursor --local --profile=standard` |
| **Recipe skills staged** | At minimum: `recipe-onboard` plus the four skills it chains (see Install below). Full recipe: `recipe-install` or `./.gsd-recipe/scripts/install.sh --yes` |
| **Atlassian MCP** (Epic + phase tasks only) | Authenticated Jira access when steps 4–5 of the chain actually run. Not needed if you only need PRD + `.planning/` bootstrap. |
| **PRD input** (optional) | File path, pasted text, or freeform description. If `docs/PRD.md` already exists, the intake step is skipped. |

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

### What happens

1. **Read-only check** — which artifacts exist: `docs/PRD.md`, `.planning/ROADMAP.md`, linked Epic in `.planning/STATE.md`, phase-task rows.
2. **One preview-then-confirm gate** — shows which of the four steps will **run** vs **skip**. Decline → nothing runs.
3. **Chain** (only missing steps):
   - `recipe-prd-intake` → writes `docs/PRD.md`
   - `recipe-new-project` → creates `.planning/*` via native `gsd-new-project`
   - `recipe-create-epic` → Jira Epic + `intake_started` sync
   - `recipe-create-phase-tasks` → Jira sub-tasks per ROADMAP phase
4. **Stops the whole chain** on the first step that fails or is declined.
5. **Final summary** — skipped / completed / failed per step.

### After onboarding

Continue with the delivery workflow:

```text
recipe-bootstrap-knowledge
recipe-plan-phase 1
recipe-run-phase 1
```

Or loop multiple phases: `recipe-run-phases` (optionally `--full` for verify/review/settle).

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
