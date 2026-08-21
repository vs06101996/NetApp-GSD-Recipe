# TASK-041 unbiased operator test (Platform)

**Persona:** Platform engineer. Did not implement. Did not search agent transcripts.  
**Date:** 2026-08-20  
**Allowed sources:** `docs/netapp-recipe/CLONE.md`, `SANDBOX.md`, `AGENTS.md` (boot sequence only), `README.md` (doc map / clone mentions).  
**Sandbox:** `/Users/vs72964/Projects/recipe-sandbox`  
**Not run:** `install --uninstall`, push, AgentStudio.

**Overall: PASS** (AC 1–4). Residual friction is operational, not a missing playbook.

---

## Acceptance criteria

| # | Criterion | Result |
|---|-----------|--------|
| 1 | One-pager with a “which path?” table (reinstall per clone vs chore PR) | **PASS** |
| 2 | Copy-paste uses `install-recipe-to-target.sh --target ...`; does not tell people to type `recipe-install` before skills exist | **PASS** |
| 3 | Playbook linked from `AGENTS.md` and `README.md` | **PASS** |
| 4 | On `feat/gitignore-reset`, recovery is understandable: re-run the same install command | **PASS** (with switch friction; see below) |

---

## AC1 — one-pager + table

`docs/netapp-recipe/CLONE.md` is a short playbook (~40 lines).

**Which path?** table:

| Situation | What to run |
|-----------|-------------|
| New laptop / `git clone` of the product | Install recipe into that clone |
| Switched git branch and `.gitignore` lost recipe lines | **Same install command again** (idempotent; does not wipe `.planning/`) |
| Want ROADMAP/PRD shared with the team | Optional **chore PR** that tracks `.planning/` / `docs/PRD.md` — default still local-only |

That is the clone/reinstall path vs the optional tracked-artifact chore PR. Skeptical note: “chore PR” is one row, not a competing install method — which is the right split.

---

## AC2 — copy-paste is the bash runner, not `recipe-install`

Documented commands (from recipe **source** repo):

```bash
./bench/runners/install-recipe-to-target.sh --target /path/to/product-repo --yes
./bench/runners/install-recipe-to-target.sh --target /path/to/product-repo --verify
```

Dummy target:

```bash
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox" --yes
```

**Do not** section is explicit: do not expect `recipe-install` to work **before** skills exist; first time = bash runner.

`recipe-start` is only after that, in the **product repo** Cursor window. That is the correct order.

SANDBOX.md repeats the same `install-recipe-to-target.sh --target ...` pair and points at CLONE.md.

---

## AC3 — links

- **AGENTS.md boot sequence 3c:** `Fresh clone / lost skills: [CLONE.md](CLONE.md) — then type **recipe-start**`
- **README.md Built vs spec:** `Clone / reinstall playbook (TASK-041) — Built — [CLONE.md](CLONE.md)`
- **README.md Doc map:** `[CLONE.md](CLONE.md)` — Team clone / reinstall playbook (TASK-041)

SANDBOX.md also links CLONE.md (not required by AC, useful for testers).

**Friction:** AGENTS 3c says “then type `recipe-start`” on the same line as the CLONE link. A rushed reader could type `recipe-start` before the bash install. CLONE.md itself sequences this correctly.

---

## AC4 — `feat/gitignore-reset` recovery

### What the playbook says

Same table row: branch switch that drops recipe `.gitignore` lines → **re-run the same `install-recipe-to-target.sh --target ...` command**. Idempotent; does not wipe `.planning/`.

SANDBOX.md branch table: `feat/gitignore-reset` = product `.gitignore` **without** recipe installer lines.

### What git actually shows (read-only)

Intended sequence `git switch feat/gitignore-reset` **failed**: sandbox `main` working tree has a dirty `.gitignore` (installer-appended ignore block). Checkout would overwrite it. Stash was not used (would mutate operator state). Committed trees were compared with `git show`.

**Committed `feat/gitignore-reset:.gitignore`:**

```
# recipe-sandbox — product ignores only (recipe installer adds more later)
__pycache__/
*.pyc
.venv/
.env
.DS_Store

# marker: incomplete gitignore branch (recipe lines not here)
```

`grep gsd-recipe` → **no matches** (expected). Marker comment is obvious to a Platform engineer.

**Committed `main:.gitignore`:** same product-only stub **without** `.gsd-recipe/` / `.planning/` / installer block. Recipe ignore lines exist only in the **working tree** after a prior install (`git diff` vs HEAD on `main` shows `.gsd-recipe/`, `.planning/`, `.templates/`, `docs/RECIPE-*.md`, `bench/`, GSD cursor paths, etc.).

So:

- The reset branch is a real, inspectable fixture: no recipe ignore lines.
- Recovery in docs matches the failure mode: after checkout, installer lines are gone; restage with the same bash command.
- **Tester/operator friction:** you cannot `git switch` onto the fixture while a live install has dirtied `.gitignore`. That is realistic (the scenario *is* “branch reset of gitignore”), but the playbook does not mention “stash or accept overwrite of `.gitignore`”. A Platform engineer still understands *what to run* after they land on the branch.

Did not run install/uninstall. Did not verify idempotency empirically — only that the documented recovery path is the same copy-paste command.

---

## Chicken-and-egg leftover

**Closed for first install:** CLONE.md forbids `recipe-install` until skills exist; copy-paste is `install-recipe-to-target.sh --target`.

**Still in the catalog (not this playbook’s job, but still a trap):** README Commands table still lists `recipe-install [--target <path>]` as a built operator command. Someone who never opens CLONE.md can still try the skill on a recipe-less clone. AGENTS boot 3c mitigates if they follow boot order.

**Post-install:** `recipe-start` / `recipe-help --next` is the intended next step, not a second install skill.

**gitignore-reset:** skills may still sit untracked/ignored on disk after checkout even if `.gitignore` no longer lists them — playbook does not explain that restage is about **ignore rules + restaging skills**, not only the ignore file. For Platform, “run the same installer” is enough; for a confused clone user it is slightly underspecified.

---

## Friction (Platform)

1. Must run install **from the recipe source repo**, not from the product clone. Stated, easy to miss on a new laptop if you only cloned the product.
2. Placeholder `/path/to/product-repo` vs dummy `$HOME/Projects/recipe-sandbox` — two blocks; dummy is copy-paste-ready.
3. Dirty `.gitignore` blocks switching to the recovery-demo branch without stash/commit.
4. Committed `main` also has no recipe ignore lines; the “lost lines” demo only appears after an install has mutated the working tree, then you switch to `feat/gitignore-reset`.

---

## Verdict

TASK-041 playbook exists, is linked, uses the bash runner, and documents gitignore-reset recovery as re-run install. **PASS.** Remaining chicken-and-egg is README still advertising `recipe-install` for people who skip CLONE.md — not a playbook failure.

---

## 10-line summary

1. CLONE.md is the one-pager; “Which path?” covers clone install, gitignore-reset restage, and optional chore PR.  
2. Copy-paste is `./bench/runners/install-recipe-to-target.sh --target ... --yes` / `--verify`, not `recipe-install`.  
3. Explicit “Do not” for `recipe-install` before skills exist.  
4. AGENTS.md boot 3c and README (Built + Doc map) both link CLONE.md.  
5. `feat/gitignore-reset` committed `.gitignore` has no `gsd-recipe` lines plus a marker comment.  
6. Committed `main` also lacks installer ignore lines; they appear only in the dirty working tree after install.  
7. `git switch feat/gitignore-reset` aborted: dirty `.gitignore` would be overwritten (realistic, undocumented stash/overwrite).  
8. Documented recovery is still the same installer; did not re-run install to prove it.  
9. Leftover trap: README Commands still lists `recipe-install` if you skip the playbook.  
10. **PASS** AC1–AC4 for a skeptical Platform engineer.

---

## Follow-up (implementer, after this report)

CLONE.md now notes dirty `.gitignore` can block `git switch`, and that restage restores skills as well as ignore lines. AGENTS.md 3c says bash install **then** `recipe-start`.
