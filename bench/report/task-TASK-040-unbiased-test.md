# TASK-040 unbiased operator test (New-dev + Platform)

**Persona:** New-dev + Platform engineer who only has the public docs. Did not implement. Did not search agent transcripts. Did not open AgentStudio. Did not invoke native `gsd-*` skills.  
**Date:** 2026-08-24  
**Allowed sources:** `README.md` (Quick start / install decision tree), `docs/netapp-recipe/CLONE.md`, `docs/netapp-recipe/AGENTS.md` (boot sequence only), `.gsd-recipe/templates/recipe-install-SKILL.md`, then staged `<sandbox>/.cursor/skills/recipe-install/SKILL.md`.  
**Sandbox:** `/Users/vs72964/Projects/recipe-sandbox-040` (reset via `--dir`; did **not** `--reset` `$HOME/Projects/recipe-sandbox`).  
**Not run:** `recipe-install` (skills did not exist until after bash install), native GSD skills, AgentStudio, uninstall.

**Overall: PASS** (AC 1–6). Residual friction is operational (`--help` missing, `bin/recipe` is alias-only in prose, installer stdout still sounds like a first-install skill).

---

## Acceptance criteria

| # | Criterion | Result |
|---|-----------|--------|
| 1 | Root README has a one-page decision tree: first clone vs restage vs verify vs uninstall | **PASS** |
| 2 | Chicken-and-egg is explicit: do not type `recipe-install` before skills exist | **PASS** |
| 3 | After install, next command is `recipe-start` (`recipe-status` optional snapshot) | **PASS** |
| 4 | CLONE.md and AGENTS.md boot item 3c agree with README (no third competing story) | **PASS** |
| 5 | `recipe-install` skill text matches: re-run/restage after skills exist, not first clone | **PASS** |
| 6 | What you typed for first install matches the docs (bash runner from recipe source, not `recipe-install`) | **PASS** |

---

## AC1 — README decision tree

`README.md` **Quick start: install into any repo** is the one-pager. **Install decision tree** (four rows):

| Your situation | Use this path |
|----------------|---------------|
| First clone, new laptop, or target has no recipe skills | `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes` from recipe source |
| Recipe skills already exist; re-run or restage | In Cursor on the target: `recipe-install` |
| Recipe is installed; verify health | `recipe-install-verify` |
| Recipe is installed; uninstall | `recipe-install --uninstall` |

That is first clone vs restage vs verify vs uninstall on one page. A new-dev can pick a row without reading INSTALL-LLD.

---

## AC2 — chicken-and-egg

README (immediately above the table): *This runner is the **only first-install front door**. Do **not** type `recipe-install` before the recipe skills exist: it is itself one of the skills created by this command.*

CLONE.md **Do not:** *Expect `recipe-install` to work **before** skills exist (chicken-and-egg). First time = bash runner above.*

AGENTS.md boot **3c:** bash `install-recipe-to-target.sh --target /path/to/product --yes` first; do not type `recipe-install` before skills exist.

Template + staged skill **First-install boundary:** *Do not type `recipe-install` before recipe skills exist.*

Explicit enough for a new-dev who actually opens Quick start or CLONE.

---

## AC3 — next command after install

README Order of operations + Quick start: after the runner, type **`recipe-start`**; **`recipe-status`** is an optional read-only snapshot.

CLONE.md: interactive install prefills `recipe-start`; headless/non-interactive: type `recipe-start`. (Does not name `recipe-status`; not a competing next command.)

AGENTS.md 3c: **then** type **`recipe-start`**.

Staged skill: *After that succeeds, invoke `recipe-start` (or optionally `recipe-status`).*

Live installer stdout (this run): `Next in Cursor Agent:  recipe-start` then `Status anytime:        recipe-status`.

Agreed: start is next; status is optional.

---

## AC4 — no third competing story

Same two-command model everywhere:

- **No skills** → bash `install-recipe-to-target.sh --target ... --yes` from recipe source.
- **Skills exist** → `recipe-install` restage (or verify/uninstall variants).
- **After first install** → `recipe-start`.

CLONE.md adds clone/gitignore rows (skills still present vs missing, optional chore PR). Those are refinements of the same two paths, not a third installer. README and CLONE both demote `install.sh` to an implementation detail and call `bin/recipe install` a thin compatibility alias of the runner.

AGENTS.md 3c points at CLONE.md with the same bash-then-`recipe-start` order and restage-only `recipe-install`. No third story.

---

## AC5 — `recipe-install` skill text

**Template path:** `.gsd-recipe/templates/recipe-install-SKILL.md`  
**Staged path (actual):** `/Users/vs72964/Projects/recipe-sandbox-040/.cursor/skills/recipe-install/SKILL.md`

YAML description: *not the first-install entry point*; on a target with no recipe skills, run `bench/runners/install-recipe-to-target.sh` from a recipe source clone first.

Examples: `recipe-install` = re-run/restage; `--target` = restage where skills already exist.

**First-install boundary** + Prerequisites: chicken-and-egg; this skill is re-run/restage, not the canonical first-install front door.

Matches AC5. Staged file matches the template on these points.

---

## AC6 — what was actually typed

`--help` on the runner is **not** implemented (`Unknown argument: --help`). Flag name `--no-open-start` is what README Quick start documents; the runner header comment lists the same pair (`--open-start` / `--no-open-start`). Used README’s name.

Exact commands (from `/Users/vs72964/Projects/gsd-benchmark`):

```bash
./bench/runners/setup-recipe-sandbox.sh --dir "$HOME/Projects/recipe-sandbox-040" --reset
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox-040" --yes --no-open-start
```

Did **not** type `recipe-install` for first install. That matches README / CLONE / AGENTS 3c / the skill’s own first-install boundary.

Setup printed a suggested install line **without** `--no-open-start`; this test appended it per README + the TASK-040 brief. Install exited 0. Cursor was not opened.

---

## `bin/recipe install` (friction only)

README and CLONE agree: **thin compatibility alias of the same runner**, not a separate workflow, not retired.

AGENTS.md boot 3c does not mention it. A Platform engineer who only follows boot 3c never sees the alias; a new-dev who greps `bin/recipe` still gets “same runner, not another door.” Consistent alias story in the two operator-facing install docs. No copy-paste block for `bin/recipe install` on the Quick start page — which is the right bias (don’t compete with the bash runner).

---

## Surprises / friction

1. **`./bench/runners/install-recipe-to-target.sh --help` fails** (`Unknown argument: --help`). New-dev cannot discover flags from `--help`; they must trust README. `--no-open-start` is still the documented name and it worked.
2. First install must run **from the recipe source clone**, not from the empty product repo. Stated in README/CLONE; still the easy miss if you only cloned the product.
3. **CLONE dummy** still uses `"$HOME/Projects/recipe-sandbox"` (shared). This TASK-040 run used `recipe-sandbox-040` as required; a copy-paste from CLONE would hit the shared sandbox.
4. **Installer stdout** for the `recipe-install` sub-installer still says invoke it “to run the **full end-to-end install flow**.” The staged SKILL.md is restage-only; the live log is slightly more first-install-sounding than the skill. A rushed reader of terminal output (not README) could still try `recipe-install` as a synonym for the runner — but only *after* this run has already staged the skill, so the chicken-and-egg for *this* sandbox is closed.
5. CLONE.md does not mention optional `recipe-status`; README, skill, and install footer do. Harmless omission.
6. `gh` missing on this machine: warn-only, install continued (as README prereqs table already allows).

---

## Verdict

TASK-040 front door is a one-page README tree, chicken-and-egg is explicit, first install is the bash runner from recipe source, restage is `recipe-install`, and post-install next step is `recipe-start`. **PASS.** Remaining friction is `--help` missing and a leftover first-install tone in installer stdout / no `bin/recipe` copy-paste (alias, not retired).

---

## 10-line summary

1. README Quick start decision tree covers first clone, restage (`recipe-install`), verify, uninstall.  
2. Chicken-and-egg is explicit in README, CLONE **Do not**, AGENTS 3c, and the skill First-install boundary.  
3. After install: `recipe-start`; `recipe-status` optional (README, skill, installer footer).  
4. CLONE.md and AGENTS 3c use the same bash-then-start / restage-only split as README.  
5. Staged skill is at `.cursor/skills/recipe-install/SKILL.md` and matches restage-not-first-clone.  
6. First install typed: `install-recipe-to-target.sh --target ... --yes --no-open-start` from `gsd-benchmark`.  
7. `--help` is unknown; `--no-open-start` matches README and worked.  
8. `bin/recipe install` is a thin alias in README and CLONE, not a third door and not retired.  
9. Friction: CLONE dummy still names shared `recipe-sandbox`; installer log still says “full end-to-end install flow.”  
10. **PASS** AC1–AC6 for a skeptical new-dev + Platform engineer using only public docs.
