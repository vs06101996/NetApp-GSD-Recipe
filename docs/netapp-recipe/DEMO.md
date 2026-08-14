# Live demo — `gsd-benchmark` as target (Alex path)

Use **`gsd-benchmark` itself** as the demo repo. Scrape GSD + operator artifacts first so
`recipe-install` visibly creates `.templates/`, `.knowledge/`, `code_base_details/`, and all
`recipe-*` skills in real time (scaffold is local-only / gitignored on external targets; this
demo uses `gsd-benchmark` itself as the install target, where `.gsd-recipe/` stays tracked).

**Operator rule:** **you** (Alex) invoke every skill in Cursor Agent. This doc is the script.

**Skips:** GitHub/`gh` — Jira-only path. Atlassian MCP must be connected.

---

## What gets removed vs kept

| Removed (scrape) | Recreated by |
|------------------|--------------|
| `.planning/` | `gsd-new-project` (GSD) |
| `docs/PRD.md` | `recipe-prd-intake` (you + agent) |
| `.templates/` | `install.sh` (recipe-install) |
| `.knowledge/` | `install.sh` |
| `code_base_details/` | `install.sh` |
| `.cursor/skills/recipe-*` | `install.sh` (via uninstall + reinstall) |
| Jira tracker rows in `STATE.md` | `recipe-create-epic` / `recipe-create-phase-tasks` |

| Kept (never touched) | Why |
|----------------------|-----|
| `.gsd-recipe/scripts/` | Installer source — demo runs from here |
| `.gsd-recipe/templates/` | Skill templates source |
| `bench/` | Harness + runners |
| `docs/netapp-recipe/` | Product docs |

---

## Step 0 — Reset for live install (terminal)

From repo root:

```bash
cd ~/Projects/gsd-benchmark

# Preview what will be deleted
./bench/runners/demo-reset-target.sh --dry-run

# Apply reset (uninstalls recipe skills + scrapes GSD/operator artifacts)
./bench/runners/demo-reset-target.sh --yes

# Confirm clean slate
./bench/runners/demo-reset-target.sh --verify
```

**Alex should see:** every scrape target `OK absent`, keepers `OK keep`.

**Optional — prove harness still works:**

```bash
bash bench/tests/test-install-recipe-create-epic.sh
```

---

## Step 1 — Install recipe (Cursor Agent, same workspace)

Open **`gsd-benchmark`** in Cursor. In Agent chat:

```text
recipe-validate-tokens
```

Expect: `Jira/Atlassian MCP: PASS`.

Then either **skill** (with live consent gate):

```text
recipe-install
```

Or **terminal** (same effect, good for screen-share — watch folders appear):

```bash
cd ~/Projects/gsd-benchmark
.gsd-recipe/scripts/install.sh --yes
```

**Watch in the file tree (real time):**

- `.templates/` — PRD, SPEC, TDD templates
- `.knowledge/index.md`, `.knowledge/log.md`, subdirs
- `code_base_details/README.md`
- `.cursor/skills/recipe-*` — all recipe skills

**Terminal proof:**

```bash
ls .templates .knowledge code_base_details
ls .cursor/skills | grep '^recipe-'
```

---

## Step 2 — GSD bootstrap (Cursor Agent — you run GSD)

`.planning/` was scraped. Alex runs native GSD to recreate project memory:

```text
gsd-new-project
```

When prompted, paste a short product description, e.g.:

```text
Build the GSD benchmark KPI instrument: stamp schema, emit-stamp runner, and
aggregate report. Three arms (baseline, gsd, recipe). See docs/EXPERIMENT-AGENDA.md.
```

**Expect:** `.planning/PROJECT.md`, `REQUIREMENTS.md`, `ROADMAP.md`, `STATE.md`, `config.json`.

**Terminal proof:**

```bash
ls .planning/
head -20 .planning/ROADMAP.md
```

---

## Step 3 — PRD intake (recipe)

```text
recipe-prd-intake
```

Paste the same description (or `@docs/EXPERIMENT-AGENDA.md` if you prefer). Answer any clarifying
questions.

**Expect:** `docs/PRD.md` created.

```bash
test -f docs/PRD.md && echo "OK PRD"
```

---

## Step 4 — PRD → Jira Epic

```text
recipe-create-epic
```

Pick Jira project (e.g. `KAN`), confirm at the soft gate → **y**.

```bash
grep -A6 '^## Tracker' .planning/STATE.md
```

---

## Step 5 — Phases → Jira sub-tasks

```text
recipe-create-phase-tasks
```

Confirm → **y**. Creates one sub-task per `## Phase N` heading in `ROADMAP.md` without a linked key.

```bash
grep -A15 '^## Phase tasks' .planning/STATE.md
```

---

## Step 6 — Sync milestones to Jira

```text
recipe-sync
```

Run twice — second run should show `duplicate_skipped`.

---

## Alex cheat sheet (full live demo)

```bash
# Terminal — reset
cd ~/Projects/gsd-benchmark
./bench/runners/demo-reset-target.sh --yes
./bench/runners/demo-reset-target.sh --verify
```

```text
# Cursor Agent — in order
recipe-validate-tokens
recipe-install                    # or: shell install.sh --yes for visible tree
gsd-new-project                   # paste product description
recipe-prd-intake                 # paste same description
recipe-create-epic                # pick project, confirm y
recipe-create-phase-tasks         # confirm y
recipe-sync
recipe-sync                       # idempotency
```

---

## Alternate target: `gsd-tutorial-sandbox`

If you prefer a disposable app repo instead of scraping `gsd-benchmark`, use
`~/Projects/gsd-tutorial-sandbox` with `recipe-install --target <path>` and skip the reset script.
See [GSD-TUTORIAL-SANDBOX.md](../GSD-TUTORIAL-SANDBOX.md).

---

## Reset again after demo

```bash
./bench/runners/demo-reset-target.sh --yes
```

Jira issues created during the demo are **not** deleted — only local files.
