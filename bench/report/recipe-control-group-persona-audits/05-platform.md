## Persona

- **PLATFORM / DEVX engineer** installing the NetApp GSD Recipe into an **arbitrary brownfield git repo** (not gsd-benchmark itself).
- Cares about: **one-command install**, **reinstall after recipe pull**, **gitignore/local-only policy**, **graphify bootstrap**, **MCP + agent_skills wiring**, **clean uninstall**, **team clone ergonomics**.
- Has Cursor Agent, `python3`/`git`, a clone of the recipe source repo, and (for full Jira path) Atlassian MCP authenticated.

---

## Install happy path

1. Clone recipe source (README Quick start): `./bench/runners/install-recipe-to-target.sh --target /some/other/repo --verify`
2. Wrapper auto-adds `--yes`, execs `.gsd-recipe/scripts/install.sh`; resolves target via git root when `--target` omitted (`bench/lib/recipe-target-root.sh`).
3. **Hard gates:** target is git repo root; `python3` + `git` present (`install.sh` preflight, exit 1 if missing).
4. **Soft gates (warn, proceed):** `node`, `gh`, GSD core (`~/.cursor/skills/gsd-help/SKILL.md`), `graphify` — recorded in `.gsd-recipe/install-report.json`.
5. Scaffolds local-only tree: `.templates/`, `.knowledge/`, `code_base_details/README.md`, `.gsd-recipe/config.json` + `ledger.json`, gitignore lines (`GITIGNORE_LINES` in `install.sh` L735–759).
6. Writes **`recipe_source`** (absolute path to installer machine) into `.gsd-recipe/config.json` on first external install; stages `recipe-paths.sh` resolver (`bench/lib/recipe-paths.sh`).
7. Composes **21 sub-installers** → `.cursor/skills/recipe-*` + `skills/recipe-planning-policy` (`install.sh` L778–800).
8. Prints **MCP** + **agent_skills** snippets (print-only, L808–809); leaves Jira as **`jira_check: pending`** until agent runs `--record-jira-check pass|fail`.
9. In Cursor on target: `recipe-validate-tokens` → `recipe-install-verify` (or rely on `--verify` bash checks).
10. Delivery chain: `recipe-onboard` → `recipe-bootstrap-knowledge` → `recipe-plan-phase` / `recipe-run-phase` (README L127–131).

---

## Friction / problems (P0/P1/P2 + evidence)

**P0**

- **Every fresh clone is recipe-less until reinstall.** INSTALL-LLD § gitignore + `install.sh` L720–722: `.gsd-recipe/`, `.planning/`, `.knowledge/`, `.templates/`, `skills/` all gitignored on external targets — `git clone` alone yields zero Cursor skills and no harness.
- **`install.sh --verify` blocks `INSTALL-VERIFIED.json` while `jira_check: pending`** (L852–855) — requires a **live agent turn** + `--record-jira-check`; not scriptable from CI/shell alone.
- **Jira auth is agent-only, split across three mechanisms:** `install.sh` records pending; `recipe-validate-tokens` probes MCP in-session; operator must also run `.gsd-recipe/scripts/install.sh --record-jira-check pass --target <repo>` (README L34, `install.sh` L815–817).

**P1**

- **MCP registration is print-only** (`install.sh` L15–16, L526–541): operator must manually paste `mcpServers` into Cursor `mcp.json` + authenticate Atlassian — install succeeds without Jira ever working.
- **`agent_skills` injection is print-only** (`install.sh` L545–559): `.planning/config.json` never auto-merged; mandatory planning policy (`skills/recipe-planning-policy`) stays unwired until manual paste.
- **Print-only snippet references uninstalled skills:** snippet lists `skills/recipe-repo-conventions` and `skills/recipe-acceptance-criteria` (`install.sh` L551–555) — **no sub-installer stages these**; paste yields broken paths.
- **`recipe_source` is write-once, never updated** (`config_json_merge` L465–466: `"recipe_source" not in data` only) — teammate reinstalling from a different path keeps stale absolute path; `recipe-paths.sh` resolution can fail closed.
- **Reinstall after recipe pull: skills overwrite, templates don't.** Sub-installers use unconditional `safe_copy` for `.cursor/skills/*` (e.g. `install-recipe-help.sh` L114); templates use `stage_template` skip-if-exists (`install.sh` L276–282) — **stale customized templates persist; skills refresh**.
- **Graphify soft-fail leaves bootstrap degraded:** install warns and continues (`PREREQ_GRAPHIFY` soft, L428–435); `graphify_config_enable()` skipped when no `.planning/config.json` yet (L600–602); `recipe-bootstrap-knowledge` says step 3 always runs but only ingest is documented as skippable (SKILL L71–72, L186–188) — missing `graphify` → `/gsd-graphify build` fails or agent must ad-hoc install first.
- **`recipe-install` requires recipe source repo for first bootstrap** (SKILL § C step 3): chicken-and-egg — target has no `.gsd-recipe/` until `install.sh` runs from source via `bench/lib/recipe-paths.sh resolve`.
- **Uninstall is partial by design** (`uninstall()` L1157–1211): removes ledgered skills/scripts; **preserves** `.gitignore` entries, `.gsd-recipe/config.json`, `.knowledge/`, `code_base_details/` — re-install or manual cleanup needed; gitignore pollution persists.
- **TASK-039 not built:** template override contract only partial (PRD template skip in `install-recipe-prd-intake.sh`; general swappable-template story still Planned in BACKLOG L124).

**P2**

- **Verify gitignore list ≠ install gitignore list:** install adds `graphify-out/` (L758) but `--verify` `GITIGNORE_VERIFY` omits it (L888–911) — false FAIL on item 7 if only install ran.
- **`docs/RECIPE-COMMANDS.md` gitignored** (L751) yet copied by `install-recipe-help.sh` — local reference only; not shareable via git without chore PR to un-ignore.
- **`bench/` added to target `.gitignore`** (L753) — harmless on most brownfield repos, but would hide an existing `bench/` tree if present.
- **Dual verify paths confuse operators:** bash `install.sh --verify` (items 1–3 echo "run manually") vs Cursor `recipe-install-verify` (actually runs `/gsd-health`, MCP smoke) — README points to both without clear "use this one."
- **`jira_check` never reset on reinstall** (`install_report_write` L506 `setdefault`) — stale `pass` can mask revoked MCP auth until explicit re-check.
- **README vs SKILL mismatch on graphify:** README L124 says bootstrap "warns" when graphify missing; `recipe-bootstrap-knowledge-SKILL.md` L66–68 says run `install-graphify.sh` first, fail-open section (L186–188) only names ingest as skippable.

---

## Team/clone implications of local-only scaffold

- **Clone → no recipe:** teammate gets product code only; must independently clone recipe source and re-run `install-recipe-to-target.sh --target .` on every machine.
- **No shared `.planning/`:** ROADMAP/STATE/PLAN.md gitignored (INSTALL-LLD L175, L203) — phase plans, epic linkage, and GSD state are **per-developer local** unless team opts into a chore PR to commit them (doc says "re-run install on each clone, or keep a separate chore PR").
- **No shared `.knowledge/`:** bootstrap output (map-codebase, graphify graphs) not in VCS — each dev re-runs `recipe-bootstrap-knowledge` (expensive, divergent snapshots).
- **`recipe_source` encodes installer's filesystem** — not portable across teammates/CI; team needs documented convention (shared mount, env override, or re-install from canonical path).
- **Cursor skills in `.cursor/skills/`** follow target's `.cursor/` policy; recipe stages ~21 skills locally — **not visible in PR review**, easy to drift from upstream recipe version.
- **`skills/recipe-planning-policy` gitignored** but required for GSD planner injection — team must either paste `agent_skills` locally or un-ignore `skills/`.
- **Onboarding docs gitignored** (`docs/RECIPE-COMMANDS.md`, `docs/RECIPE-BENCHMARKS.md`) — new hires can't read command catalog from repo alone.

---

## Security/ops concerns

- **Secrets stay out of repo** (INSTALL-LLD Step 0: tokens via env/MCP, not committed) — good.
- **`.env` / `.env.*` auto-gitignored** on install (L741–742) — additive-only, won't remove if already tracked.
- **MCP consent not automated** — reduces risk of silent MCP registration, but shifts trust boundary to operator paste accuracy.
- **`gh` check warn-only** (`github_check` L288–301) — install completes with unauthenticated GitHub; ship/review paths fail later.
- **`recipe-validate-tokens` never calls `mcp_auth`** (SKILL § C.2.c) — won't trigger OAuth during check; also won't fix auth gaps.
- **Uninstall preserves human data** (`.knowledge/`, `code_base_details/`) — good for safety, but `.gsd-recipe/config.json` (with `recipe_source`, tracker config) left behind — review before sharing repo artifact.
- **Print-only MCP snippet uses `npx …@latest`** (L534–535) — unpinned supply-chain surface on every dev machine.

---

## Suggested improvements

- **Ship a `recipe-doctor` or extend `--verify`** to emit one actionable checklist: reinstall needed?, MCP wired?, agent_skills pasted?, graphify enabled?, `recipe_source` reachable?
- **Update `recipe_source` on reinstall** (or env `RECIPE_SOURCE` override) when resolver path differs from recorded value.
- **Align verify gitignore list with install list** (add `graphify-out/`).
- **Stage or remove phantom `agent_skills` paths** (`recipe-repo-conventions`, `recipe-acceptance-criteria`) from print snippet until built.
- **Document team playbook:** "Day-0: install recipe → Day-1: optional chore PR to un-ignore `.planning/` / share templates" with explicit tradeoffs.
- **Make graphify soft-fail explicit in `recipe-bootstrap-knowledge`:** warn-skip `/gsd-graphify build` when CLI absent (match README L124), continue map-codebase.
- **TASK-039:** formalize template upgrade path on reinstall (version stamp + `--force-templates` flag).
- **Uninstall `--purge-gitignore`** optional flag to remove recipe-added lines without touching unrelated entries.
- **Single verify entry point in README:** "Cursor: `recipe-install-verify`; CI: `install.sh --verify` + documented MCP skip" — reduce dual-path confusion.
- **Pin MCP package versions** in print snippet or document lockfile approach for chrome-devtools-mcp.

[REDACTED]
