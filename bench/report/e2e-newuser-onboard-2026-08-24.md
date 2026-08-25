# E2E new-user onboard diary — 2026-08-24

**Persona:** New engineer. Never implemented this recipe. Did not read prior agent chats. Did not open AgentStudio.

**Told in Slack:** Recipe source is `/Users/vs72964/Projects/gsd-benchmark`. Dummy product is `/Users/vs72964/Projects/recipe-sandbox-e2e-newuser` (already a git repo). Figure out install from the recipe README, then start, then onboard.

**Dummy feature:** Hello Widget CLI — print `hello widget`. One phase. No production systems.

**Branch:** `main` (stayed). No uninstall. No push. No commit.

---

## Verdict

| Question | Result |
|----------|--------|
| **Overall** | **FRICTION** |
| Pass/fail: new user can install + start + get a PRD/planning onboard **without Jira** | **FAIL unassisted** / **PASS only with a coach** who knows the missing skill, the template workaround, and to split onboard vs tracker |

Install and `recipe-start` are discoverable. Getting `docs/PRD.md` + `.planning/*` without creating a Jira Epic is **not** a documented path. The onboard skill uses **one yes/no for PRD + planning + Epic + phase tasks**. There is no “skip tracker” flag. After a human fills PRD + planning anyway, `recipe-next.sh` sends them **back to `recipe-onboard`** because no Epic is linked.

---

## Time-ordered actions

### 1. Read public install docs (no Slack command given)

Read:

- `/Users/vs72964/Projects/gsd-benchmark/README.md` — Quick start + install tree
- `/Users/vs72964/Projects/gsd-benchmark/docs/netapp-recipe/CLONE.md`

**What I typed from those docs:**

```bash
cd /Users/vs72964/Projects/gsd-benchmark
./bench/runners/install-recipe-to-target.sh --target /Users/vs72964/Projects/recipe-sandbox-e2e-newuser --yes --no-open-cursor
```

**Surprises at this step**

- README copy-paste is `--yes` only. `--no-open-cursor` is in the prose + CLONE.md, not in the first code fence. Easy to miss; Cursor would have opened if I had pasted the fence blindly.
- CLONE.md dummy path is `$HOME/Projects/recipe-sandbox`, not this Slack sandbox. Harmless, but a new hire might install into the wrong folder.
- Chicken-egg is **clearly** documented: do not type `recipe-install` before skills exist. I did not.
- Installer ran a long composition log (observer, tracker-sync, many `recipe-*` skills). Noise, but it finished with `recipe-start` as next.
- `gh` missing → automated brew attempt → still missing → recorded fail, install continued (`--yes`).
- `graphify_config_enabled`: `skipped_no_planning_config` (no `.planning/config.json` yet). Easy to read as “graphify broken.”
- `jira_check`: `pending`. Print-only MCP JSON for `mcp.json`. A new user does not know if they must paste that before onboard.
- Product `README.md` already had an install one-liner (this sandbox is a recipe test fixture). A real empty product would only have the recipe-source README.

**Dummy repo before install:** `main`, clean, `src/app.py` + short README. After install: `.gitignore` modified (recipe ignores); `.cursor/skills/` untracked; `.gsd-recipe/` gitignored.

### 2. Behaved as if I typed `recipe-start`

Read staged: `/Users/vs72964/Projects/recipe-sandbox-e2e-newuser/.cursor/skills/recipe-start/SKILL.md`

Ran (as the skill requires):

```bash
cd /Users/vs72964/Projects/recipe-sandbox-e2e-newuser
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/.gsd-recipe/scripts/recipe-next.sh" --target "$ROOT"
```

**Stdout (verbatim, first run — no PRD yet):**

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

Answered **Yes** to “run that command” → proceed to `recipe-onboard` only (did not chain the rest of delivery).

**Friction:** `recipe-start` is a good coach. Plain language. This part is EASY.

### 3. Followed `recipe-onboard` (preview gate)

Read staged: `.cursor/skills/recipe-onboard/SKILL.md`

Recon (as the skill says, read-only):

| Artifact | Present? | Step |
|----------|----------|------|
| `docs/PRD.md` | no | **run** PRD intake |
| `.planning/ROADMAP.md` | no | **run** project bootstrap |
| Tracker epic in `STATE.md` | n/a (no STATE yet) | **run** Epic create (provisional until bootstrap) |
| Phase-task rows | n/a | **run** phase-task create (provisional) |

**Preview I would have shown a human:**

1. PRD intake — **run** (no `docs/PRD.md`)
2. Project bootstrap — **run** (no `.planning/ROADMAP.md`)
3. Epic creation — **run** (provisional; needs ROADMAP/STATE from step 2)
4. Phase-task creation — **run** (provisional)

One yes/no for the **whole chain**, including Jira.

**Would a new user know how to skip Jira?** **No.** The skill forbids four nested confirms. There is no `--skip-jira`. README onboard table lists Epic + phase tasks as steps 3–4. Declining the one gate stops **everything**, including PRD.

**What I did (test rules):** Declined the **combined** gate so I would not create a real/production Epic. Then continued **only** PRD + `.planning/` by invoking the sibling skills / workarounds, and **stopped before** `recipe-create-epic` / `recipe-create-phase-tasks`.

### 4. PRD intake — skill missing

Looked for staged `.cursor/skills/recipe-prd-intake/SKILL.md` — **not installed**.

`ls .cursor/skills` after install (23 dirs): `fotw-observer-bootstrap`, `gsd-jira-sync`, `recipe-bootstrap-knowledge`, `recipe-create-epic`, `recipe-create-phase-tasks`, `recipe-help`, `recipe-install`, `recipe-install-verify`, `recipe-new-project`, `recipe-observe`, `recipe-onboard`, `recipe-plan-phase`, `recipe-pr-comment`, `recipe-review-ship`, `recipe-run-phase`, `recipe-run-phases`, `recipe-settle`, `recipe-start`, `recipe-status`, `recipe-sync`, `recipe-validate-tokens`, `recipe-verify-feature`, `tracker-sync`.

**No `recipe-prd-intake`.** Catalog `docs/RECIPE-COMMANDS.md` still lists `recipe-prd-intake` as **built**. Observer skill text even says `recipe-prd-intake` is a “future” caller. Conflicting stories.

**New-user dead end:** Onboard step 3 says invoke `recipe-prd-intake` by name. That skill is not on disk. A new user cannot complete the documented chain.

**Coach workaround used for this test:** Filled `.templates/PRD.template.md` → wrote `docs/PRD.md` for Hello Widget CLI. Did **not** spawn `fotw-observer-bootstrap` (config has observer enabled false in `.gsd-recipe/config.json`; extra subagents out of scope).

### 5. `recipe-new-project` / native `gsd-new-project`

Read staged `.cursor/skills/recipe-new-project/SKILL.md`. First-init (no ROADMAP) → skip re-init confirm → prefer `docs/PRD.md` → call native **`gsd-new-project`**.

**Surprise:** Dummy product has **no** `gsd-new-project` skill. Only native GSD skill staged is `gsd-jira-sync`. Install report says `gsd_core: pass` (machine/source check), which a new user will read as “GSD is ready in *this* repo.”

This Cursor session can see GSD skills under `gsd-benchmark` / `~/.claude/skills`. A hire who only opened the **product** repo in Cursor would not.

**What I did:** Did **not** run the full GSD questioning/research/roadmapper agent circus (one-phase dummy; no extra subagents; no commits). Wrote first-init artifacts the wrapper re-verifies:

- `.planning/PROJECT.md`
- `.planning/REQUIREMENTS.md`
- `.planning/ROADMAP.md` (`## Phase 1: Hello Widget CLI`)
- `.planning/STATE.md` (no Epic key)
- `.planning/config.json` (`commit_docs: false`)

Stopped. Did **not** invoke `recipe-create-epic`.

`.planning/` is gitignored. `docs/PRD.md` is **not** ignored (`?? docs/PRD.md`). `.cursor/` is also untracked — a new user `git add .` would commit recipe skills.

### 6. End-state helpers (verbatim)

```bash
bash .gsd-recipe/scripts/recipe-next.sh --target /Users/vs72964/Projects/recipe-sandbox-e2e-newuser
bash .gsd-recipe/scripts/recipe-status.sh --target /Users/vs72964/Projects/recipe-sandbox-e2e-newuser
```

**`recipe-next.sh`:**

```
=== Recipe next step ===

Why: Planning exists, but no Jira Epic is linked in .planning/STATE.md yet.

Type this in Cursor Agent:

  recipe-onboard

Command: recipe-onboard

This is for files on your current git checkout (branch).
recipe-start may offer to run the command after Yes.
recipe-help --next only prints it.
Catalog:  recipe-help
```

**`recipe-status.sh`:**

```
=== Recipe status ===

Branch:          main
Recipe skills:   yes
PRD:             yes  (docs/PRD.md)
ROADMAP:         yes
Knowledge:       yes
Epic:            (none)
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

Why: Planning exists, but no Jira Epic is linked in .planning/STATE.md yet.

Type this in Cursor Agent:

  recipe-onboard

Command: recipe-onboard
…
```

**Extra friction:** `Knowledge: yes` is a **stub** `.knowledge/index.md` from install (“not populated by install.sh”). Status looks like bootstrap already ran. It did not.

**Buglet:** If `STATE.md` contains `- epic: ` (empty) immediately followed by another `- …` line, `recipe-next`’s regex `^-\s*epic:\s*\S+` can match across the newline and treat tracker as linked. I removed the empty `epic:` line so next-step is honest.

---

## Friction catalog

| Kind | What happened |
|------|----------------|
| Wrong first command | Avoided: README/CLONE say bash runner first, not `recipe-install`. |
| Missing flags | `--no-open-cursor` not in the first README fence. |
| Chicken-egg | Documented well. |
| Jargon | GSD vs recipe, graphify skip, FOTW observer, MCP paste-only, `intake_started`, capability.json. |
| Catalog lie | `recipe-prd-intake` “built” but not staged. |
| Missing native GSD in product | `recipe-new-project` cannot call a local `gsd-new-project`. |
| Single onboard gate | Cannot confirm PRD+planning without also agreeing to Jira create. |
| No skip-Jira docs | New user would not know to run intake + new-project separately (and intake is missing anyway). |
| Coach loop | After PRD+planning without Epic, next command is still `recipe-onboard`. |
| Knowledge false yes | Stub index.md. |
| Git | Skills under `.cursor/` untracked; `.planning/` ignored. Easy to commit the wrong tree. |
| `gh` fail | Soft; install continues. Ship path would surprise later. |

---

## Would a new user succeed without a coach?

**Install + `recipe-start`:** Yes, if they start from the recipe-source README (not the empty product README).

**Onboard to PRD + `.planning/` without Jira:** No, not from the happy path:

1. They would **Yes** the onboard preview (includes Jira) *or* **No** and do nothing.
2. `recipe-prd-intake` is missing → chain fails even if they Yes.
3. Native `gsd-new-project` is not in the product skills.
4. After a coach workaround, `recipe-next` still says onboard (Epic).

---

## Artifacts created

| Path | How |
|------|-----|
| `.cursor/skills/*` (23 skills) | Installer |
| `.gsd-recipe/` (gitignored) | Installer |
| `.templates/PRD.template.md` | Installer |
| `docs/RECIPE-COMMANDS.md`, `docs/RECIPE-BENCHMARKS.md` | Installer (gitignored per product `.gitignore`) |
| `docs/PRD.md` | Manual fill from PRD template (intake skill missing) |
| `.planning/PROJECT.md`, `ROADMAP.md`, `STATE.md`, `REQUIREMENTS.md`, `config.json` | Manual first-init stand-in for `gsd-new-project` |
| Jira Epic / phase tasks | **Not created** |

---

## Overall: **FRICTION**

Not blocked on install. Blocked on the documented onboard chain without a coach: missing `recipe-prd-intake`, missing in-repo `gsd-new-project`, and Jira welded to the only confirm gate.

**Pass/fail:** **FAIL** — “new user can install + start + get a PRD/planning onboard without Jira” is not true unassisted. Install + start work. PRD/planning without Jira requires undocumented workarounds and still leaves the coach pointing at `recipe-onboard`.
