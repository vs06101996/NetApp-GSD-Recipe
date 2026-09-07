# recipe-onboard — quick start

Single Cursor skill that runs the full NetApp GSD onboarding chain in one invocation: PRD intake →
project bootstrap → Jira Epic/link → phase tasks → knowledge. With no new source it resumes and
skips completed artifacts. With an explicit source it starts fresh on an isolated initiative branch.

For the full command catalog, invoke **`recipe-help`** or see [docs/RECIPE-COMMANDS.md](RECIPE-COMMANDS.md). After a first install, type **`recipe-start`** (or **`recipe-help --next`**) to see the next command in plain language.

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Clean Git repo root** | Fresh onboarding creates an initiative branch and fails closed on dirty product files, detached HEAD, or a branch-name collision. Gitignored recipe state may exist. |
| **GSD for Cursor (full)** | Installed and verified by recipe install. Manual repair: `npx -y --package=@opengsd/gsd-core@latest -- gsd-core --cursor --global --profile=full` |
| **Recipe skills staged** | At minimum: `recipe-onboard` plus the four skills it chains (see Install below). Full recipe: `recipe-install` or `./.gsd-recipe/scripts/install.sh --yes` |
| **Atlassian MCP** | Authenticated Jira access to fetch a ticket, create an Epic, or link. `--skip-tracker` still needs MCP when the PRD source is a live ticket. |
| **PRD input** (optional) | Jira issue key or browse URL (Atlassian MCP), Jira/Confluence export (`.templates/JIRA-PRD.input.template.md` shape), file path, pasted text, or freeform description. Output is always canonical `docs/PRD.md`. If `docs/PRD.md` already exists, the intake step is skipped. |

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

With an existing Jira ticket (fetch description; **link** the key — do not create a second Epic):

```text
recipe-onboard KAN-53
recipe-onboard https://netapp.atlassian.net/browse/KAN-53
```

With a PRD file already on disk:

```text
recipe-onboard docs/PRD.md
recipe-onboard docs/PRD.md --branch gsd/kb-evaluations
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
2. **One preview-then-confirm gate** — shows the new initiative branch and which of the five
   steps will **run** vs **skip**.
3. **Initiative boundary** — snapshots the current branch's `.planning/`, untracked PRDs,
   tracker queue/ledger, and readiness state; creates `gsd/<slug>`; starts it clean.
4. **Chain** (only missing steps):
   - `recipe-prd-intake` → writes `docs/PRD.md` (skipped if that file already exists)
   - `fotw-observer-bootstrap` → starts the fly-on-the-wall observer once `docs/PRD.md` exists,
     including when intake was skipped. No-op if disabled or already active; never blocks onboard.
   - `recipe-new-project` → creates `.planning/*` via native `gsd-new-project --auto` when `docs/PRD.md` (or another file brief) exists. The wrapper answers native config in-turn (`commit_docs: false`, no `git commit` of gitignored `.planning/`). Missing GSD research agents is a warning plus native's inline roadmap — not a hard stop. Fail closed only if the `gsd-new-project` skill file is missing.
   - `recipe-create-epic` → Jira Epic + `intake_started` sync (skipped with `--skip-tracker`, or when the PRD source was an existing ticket — that path runs `init-tracker` + `gsd-jira-sync intake_started` instead)
   - `recipe-create-phase-tasks` → Jira sub-tasks per ROADMAP phase (skipped with `--skip-tracker` or existing-ticket onboard)
   - `recipe-bootstrap-knowledge` → mandatory map + graph; verifies and writes
     `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`
5. **Stops the whole chain** on the first step that fails or is declined.
6. **Final summary** — skipped / completed / failed per step. Knowledge failure fails onboarding.

### After onboarding

Knowledge is already complete. Continue with planning:

```text
recipe-plan-phase 1
recipe-run-phase 1
```

Or loop multiple phases: `recipe-run-phases` (optionally `--full` for verify/review/settle).

### Second PRD / new initiative in the same repo

Pass the new source to the same command:

```text
recipe-onboard docs/PRD-kb-compare-metrics-backend.md
recipe-onboard KAN-53
```

An explicit source means **fresh onboarding**, never resume:

1. The preview lists the old initiative state and proposed `gsd/<slug>` branch.
2. **Yes** snapshots `.planning/`, untracked `docs/PRD*.md`, phase-task queue, sync ledger,
   knowledge marker, and `onboard.skip_tracker` under
   `.gsd-recipe/workspaces/<current-branch>/`, then creates the clean branch.
   From an existing initiative branch, the new branch is based on `origin/HEAD` (then local
   `main`/`master`) so a second PR never contains the first PR's product commits.
3. Intake and project bootstrap always run from the new source. The old ROADMAP, STATE, plans,
   summaries, Epic, and phase-task keys are not reused.
4. **No** changes nothing.

File input is read before switch-out, so a source under `docs/` remains available to intake.
Calling `recipe-onboard` with **no source** is still resume/idempotent mode.

Use `--branch NAME` to override the derived branch. Use `--no-branch` only when you deliberately
want to stay on the current branch; that path archives the same initiative state under
`.gsd-recipe/workspace-archives/<branch>/<run-id>/` before intake.

Later branch switching is automatic: the installed `post-checkout` hook snapshots the branch
being left and restores the branch being entered. Use `recipe-workspace status` to inspect snapshots.

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
