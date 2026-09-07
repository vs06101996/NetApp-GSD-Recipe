# Decisions — NetApp GSD Recipe

---

## Locked (v1)

| Decision | Value |
|----------|--------|
| Platforms | Jira + GitHub |
| Tracker mapping | Epic → PRD; GSD phase → Jira task |
| Settled gate | Human PO + CI green |
| Orchestrator | One per repo — **not** recipe + ic-* |
| GSD role | Orchestrator; recipe wraps, does not replace |
| Tier-1 DAG (`dag-build.sh`, TASK-009) | **Not required for v1** — parked as future enhancement (see [BACKLOG.md](BACKLOG.md)); dependent tasks (e.g. TASK-017 `recipe-plan-phase`, TASK-024 `recipe-run-phase`) are narrowed to skip DAG pre-req/post-op gating rather than blocking on it |
| Target-repo scaffold in git | **Gitignored by default** on external targets (`.gsd-recipe/`, `.knowledge/`, `.templates/`, `.planning/`, `code_base_details/`, `skills/`, recipe-owned docs). Re-run `install-recipe-to-target.sh` per clone. Source repo (`gsd-benchmark`) keeps `.gsd-recipe/` tracked. |

---

## Open / deferred

| ID | Topic | Recommendation | Status |
|----|-------|----------------|--------|
| OD-01 | Org KPI thresholds | P-1–P-3 first; org targets after baseline | Open |
| OD-02 | GSD version floor | Pin at install → `INSTALL-VERIFIED.json` | Open |
| OD-03 | Capability vs fallback installer | Capability-first, fallback when unavailable | Open |
| OD-04 | sync-ledger in git | Default gitignore; team override | Open |
| OD-05 | `recipe-sync` trigger | Loop-first; hooks later | Open |
| OD-06 | ic-* + recipe coexistence | Strict mutual exclusion | Open |
| OD-07 | Bitbucket/GitLab | Deferred post-v1 | Deferred |
| OD-08 | pgvector learnings | Optional bridge | Open |
| OD-09 | PR comment cadence | Wave + phase milestones | Open |
| OD-10 | Tier-2 DAG auto agents | Parked until Tier-1 stable | Parked |
| OD-11 | First-run coach + situational next | Ship **`recipe-start`** as the post-install first-run front door (how to onboard a PRD, what to invoke next). Share one repo-agnostic next-step resolver with `recipe-help --next` / optional `--stuck`. Read-only guidance by default; may offer to invoke the recommended skill only after an explicit Yes. Default `recipe-help` (no args) stays the catalog. Install success message points operators to `recipe-start`. See [BACKLOG TASK-056](BACKLOG.md) (first) and [TASK-038](BACKLOG.md). | Open |
| OD-12 | Swappable recipe templates | Allow targets/orgs to override `.templates/*` (PRD, tracker/VCS comment templates, SPEC/TDD, bare_metal) without forking the recipe; re-install must not clobber customizations; resolve via config or documented overlay + shared path resolver. See [BACKLOG TASK-039](BACKLOG.md). | Open |
| OD-13 | Claude Code dual-runtime port | Support running the same recipe under **Claude Code** as well as Cursor via one recipe source with parameterized install paths and `install.sh --runtime cursor\|claude\|both`. Core harness (`.planning/`, `bench/runners/*`, `bench/lib/*`, Jira/GitHub sync, ledger, STATE) is already runtime-agnostic; GSD core already supports `--claude`. Cursor-shaped pieces (`.cursor/skills/` vs `.claude/skills/` + `.claude/settings.json`; `Task` tool, `/loop`, `hooks.json` vs `settings.json`) are adapted, not 1:1 ported. **Phase 1 MVP:** runtime-aware install + Claude MCP snippet + GSD `--claude` detection. **Phase 3:** FOTW observer hook adapter (deferred). See [CONTROL-GROUP § Claude Code port](CONTROL-GROUP.md) and [BACKLOG TASK-047](BACKLOG.md). | Open |
| OD-14 | Install front door | One canonical install entry point + a one-page "install into any repo" decision tree in README, replacing competing front doors (README bash runner vs `recipe-install` vs `install.sh` vs `bin/recipe`). Resolve the chicken-and-egg where `recipe-install` needs skills that only exist post-install. See [BACKLOG TASK-040](BACKLOG.md). | Open |
| OD-15 | Light / bugfix path | Add a low-ceremony path for small fixes — optional `--skip-tracker` / light onboard so a one-line UI fix doesn't require Epic + per-phase Jira sub-tasks + 7-section PLAN; optionally a `recipe-quick` wrapper bringing `gsd-quick` into recipe traceability. Repo-agnostic; full path stays default. See [BACKLOG TASK-042](BACKLOG.md); pairs with OD-12 (light templates). | Open |
| OD-16 | Install doctor | Collapse install verification friction into one re-runnable "doctor": fix the MCP/`agent_skills` paste snippet (remove phantom skill paths, add a paste checklist), make `recipe_source` refresh on reinstall / env override, and merge the three-step Jira verify (`pending` → agent → `--record-jira-check`) into `recipe-install-verify`. See [BACKLOG TASK-044](BACKLOG.md). | Open |
| OD-17 | Re-init / switch initiative | An explicit PRD source on `recipe-onboard` means **fresh onboarding**, not resume. After the existing single preview/Yes-No gate, archive the active branch-local `.planning/`, untracked `docs/PRD*.md`, and knowledge-ready marker through TASK-059's workspace runtime; clear stale `onboard.skip_tracker`; then run intake and project bootstrap from the new source. With no source, retain artifact-aware resume behavior. Never reuse the previous ROADMAP/STATE/plans for the new cycle. See [BACKLOG TASK-054](BACKLOG.md). | Implemented (TASK-054) |
| OD-18 | Ephemeral test/validation artifacts | Any files generated **only** for testing, smoke checks, or validity (not product feature/bug code) must live under a **pre-created, gitignored** folder staged at install — never repo root, `src/`, or ad-hoc paths that pollute feature PRs. Default: `.gsd-recipe/scratch/` (parent `.gsd-recipe/` already gitignored on external targets). Document in PLANNING-POLICY + AGENTS; soft-warn in plan/run/verify skills. Real project tests/fixtures that ship with the feature stay in the repo's normal test layout. See [BACKLOG TASK-055](BACKLOG.md). | Open |
| OD-19 | `recipe-start` is first-run, not a second workflow | `recipe-start` does **not** replace `recipe-onboard` or invent a parallel delivery path. It only detects generic artifacts and recommends (or, on confirm, invokes) the existing recipe skill. One resolver powers `recipe-start` and `recipe-help --next`. See [BACKLOG TASK-056](BACKLOG.md). | Open |
| OD-20 | DAG conflict handling: LLM merge skill, not live OT | For parallel DAG / workstream production, prefer **git branches/worktrees + Tier-1 `touches` serialization** first. Residual same-file conflicts → a gated **LLM merge skill** (GitHub-style conflict resolution with PLAN intent as context; Yes/No before write). **Reject** Google Docs–style OT/CRDT live multi-writer as the recipe control plane — wrong fit for bisectable commits, Jira settle, and agent burst edits. Practical spike after Tier-1 DAG (`TASK-009`). See [BACKLOG TASK-057](BACKLOG.md), [RUNTIME-LLD §1.c.2](lld/RUNTIME-LLD.md). | Open |
| OD-21 | In-place recipe update | Ship **`recipe-update`** (mirrors native `gsd-update`): pull latest recipe source then **restage** skills/scripts without `--uninstall` and without wiping `.planning/`, `STATE.md`, Epic links, or customized `.templates/`. Distinct from first-install (`recipe-install` / bash runner) and from clone reinstall (TASK-041). Refresh `recipe_source` on success. `recipe-start` may **check** (nudge only). See [BACKLOG TASK-058](BACKLOG.md), [INSTALL-LLD § Removal / upgrade](lld/INSTALL-LLD.md). | Implemented (TASK-058) |
| OD-22 | Per-branch local workspace swap | Use a **local git `post-checkout` hook** (not an HTTP webhook) to snapshot/restore gitignored recipe working files when `HEAD` moves: save `.planning/` + active `docs/PRD.md` under `.gsd-recipe/workspaces/<branch>/`, restore on checkout with `--clear` so a new branch cannot inherit the previous branch's context. Cursor gets a post-tool fallback. The same runtime exposes `archive` for TASK-054 fresh onboarding. Skip file-only checkouts; `RECIPE_WORKSPACE_SWAP=0` opt-out. Never push workspace snapshots. See [BACKLOG TASK-059](BACKLOG.md). | Implemented (TASK-059) |
