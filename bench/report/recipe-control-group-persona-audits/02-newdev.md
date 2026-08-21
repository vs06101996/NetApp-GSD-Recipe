## Persona

- First-week developer on an arbitrary target git repo; never used GSD or the NetApp recipe.
- Opens Cursor Agent, invokes skills **by name** (not slash commands); may or may not have cloned `gsd-benchmark`.
- Wants: install recipe → start a feature → know what to type when stuck.

## Happy path they would attempt

- Read README **Prerequisites** (Cursor, git, python3, soft `gh`/`node`/GSD, Atlassian MCP for Jira).
- Find Quick start: run `./bench/runners/install-recipe-to-target.sh --target /<repo> --verify` from a recipe-source clone.
- Open target repo in Cursor → `recipe-validate-tokens` → `recipe-onboard` (or `recipe-onboard docs/PRD.md`).
- Follow README delivery chain: `recipe-bootstrap-knowledge` → `recipe-plan-phase 1` → `recipe-run-phase 1` → verify/ship/settle.
- When lost, type `recipe-help` expecting a coach; fall back to `docs/RECIPE-COMMANDS.md` or `docs/RECIPE-ONBOARD.md`.

## Friction / problems (severity P0/P1/P2 + evidence)

- **P0 — Install chicken-and-egg:** `docs/RECIPE-ONBOARD.md` recommends full install via `recipe-install` in Cursor, but skills are not staged until install runs; README points to a **bash runner** from the recipe source repo instead. Newbie in target repo only has no `recipe-install` skill to invoke.
- **P0 — Two authoritative install paths, no “pick one” banner:** README Quick start = `bench/runners/install-recipe-to-target.sh`; RECIPE-COMMANDS quick start = `recipe-install → recipe-onboard`; INSTALL-LLD = `install.sh` / `bin/recipe install`. No single decision tree for “I have target repo, never cloned benchmark.”
- **P0 — `recipe-install` catalog vs reality:** `docs/RECIPE-COMMANDS.md` lists `recipe-install` as **built**; no staged `.cursor/skills/recipe-install/SKILL.md` in source tree; template exists only under `.gsd-recipe/templates/`.
- **P1 — No PRD dead-end:** `recipe-prd-intake` § D: zero input → stop; tell operator to run native `gsd-discuss-phase`, then re-invoke. Newbie who typed `recipe-onboard` alone gets bounced to an unfamiliar **gsd-** command with no recipe wrapper.
- **P1 — `recipe-help` explicitly not a coach:** `.gsd-recipe/templates/recipe-help-SKILL.md` § C: “Do NOT add … unsolicited next-step suggestions.” README/RECIPE-COMMANDS call it a “guided tour” — that overpromises when stuck.
- **P1 — Jira framed as hard prerequisite:** README prerequisites table marks Atlassian MCP **Yes for Jira path** before Quick start; `recipe-onboard` can stop after PRD + `.planning/` without Epic — easy to over-prepare or abort early.
- **P1 — `recipe-new-project` status mismatch:** `docs/RECIPE-COMMANDS.md` marks it **planned**; README onboarding table and `recipe-onboard` chain treat it as step 2; skill doc allows native `gsd-new-project` fallback — newbie cannot tell if wrapper is required.
- **P1 — Internal benchmark jargon in onboarding doc:** `docs/RECIPE-ONBOARD.md` “Onboard skill only (this repo's benchmark checkout)” with `TASK-036`/`TASK-037` installer script names — irrelevant and confusing on a normal target repo.
- **P2 — Prerequisites wall before first action:** README “Order of operations” is 5 numbered steps (CLI, verify, tokens, Jira record, install-report) before “Quick start (install).”
- **P2 — AgentStudio/KAN-53 noise:** README benchmarks and RECIPE-COMMANDS field-benchmark table anchor to AgentStudio — contradicts repo-agnostic onboarding goal.
- **P2 — Gitignore surprise:** INSTALL-LLD § `.gitignore`: `.gsd-recipe/`, `.templates/`, `.planning/` local-only by default — newbie may think install failed when files do not appear in git status.
- **P2 — `recipe-onboard` vs step count:** README says chain of 4 skills; `recipe-onboard-SKILL.md` internally labels steps 2–7 — minor trust erosion in preview UI.

## Cognitive overload (too many commands / unclear AND vs OR)

- **Install OR matrix:** `install-recipe-to-target.sh` vs `recipe-install` vs `bin/recipe install` vs `.gsd-recipe/scripts/install.sh --yes` — four surfaces, one job.
- **Onboard OR matrix:** `recipe-onboard` **or** four separate `recipe-*` skills **or** (implicitly) `gsd-discuss-phase` → `recipe-prd-intake` when no PRD.
- **Delivery AND vs OR:** README explains AND (`recipe-plan-phase N` then `recipe-run-phase N`) vs OR (`recipe-run-phases 2 5 --full` **instead of** manual loop) vs OR (`recipe-run-phases 1 5 --full` **instead of** split table) — correct but dense; default example is the hardest split pattern.
- **Dual namespaces:** ~20 `recipe-*` invoke-by-name skills plus ~15 native `gsd-*` and slash `/gsd-*` commands in one catalog; recipe skills “delegate to” GSD but onboarding sometimes calls GSD directly (`gsd-new-project`, `gsd-discuss-phase`).
- **Naming asymmetry:** `recipe-run-phase` wraps `gsd-execute-phase`; `recipe-verify-feature` wraps `gsd-audit-*` + `gsd-audit-uat`; table pairs `gsd-plan-phase` with `recipe-plan-phase` but not `gsd-execute-phase` with `recipe-run-phase` at a glance.
- **Sync trio:** `recipe-sync`, `tracker-sync`, `gsd-jira-sync` — three entry points, unclear which an operator ever types.
- **Help duo:** `recipe-help` vs `gsd-help`; GSD already has situational `gsd-progress --next` — never pointed to from recipe docs when recipe operator is stuck.
- **Slash vs name inconsistency:** `/gsd-map-codebase`, `/gsd-graphify build` vs `gsd-plan-phase` without slash — new Cursor user will try wrong invocation style.
- **“Soft” vs “Yes” prerequisite table:** GSD, `node`, `gh`, graphify marked Soft/warn but several skills fail or degrade without them — no single “minimum viable install” list.

## Gaps vs TASK-038 situational help (if mentioned in BACKLOG)

- **TASK-038 planned, not shipped:** BACKLOG Wave 5 — `recipe-help --next` / `--stuck <symptom>` with artifact-based next command; status **Planned**.
- **Current skill contradicts TASK-038:** recipe-help forbids next-step suggestions; TASK-038 wants artifact detection → one recommended skill (`recipe-install` → onboard → bootstrap → plan → run → verify → ship → settle).
- **No fail-open FAQ today:** TASK-038 calls for graphify missing, no epic, CI-blocked settle, plan-policy warn — none in recipe-help default mode.
- **Misleading marketing:** README/RECIPE-COMMANDS say invoke `recipe-help` for guided tour; TASK-038 intent is `--next` as coach — default behavior still catalog-only.
- **Escape hatch undocumented:** Native `gsd-progress --next` exists for GSD-native routing; recipe docs never bridge “stuck on recipe” → “try gsd-progress for GSD layer.”
- **Install-state detection missing:** TASK-038 wants `.gsd-recipe/`, install-report, INSTALL-VERIFIED markers; current help cannot answer “did install work?” or “skill not found — now what?”

## Suggested improvements (repo-agnostic)

- **One front door:** Single “Install into target repo” page: Path A (have recipe clone → bash runner), Path B (already in target → first-time must use runner or `bin/recipe` until skills exist); demote `recipe-install` until post-install.
- **Fix RECIPE-ONBOARD install section:** Remove “type `recipe-install` in Cursor” as step 1 for greenfield target; align with README bash runner; keep `recipe-install` as re-install/verify only after `.gsd-recipe/` exists.
- **Ship TASK-038 or interim stub:** `recipe-help --next` reads generic artifacts only; default `recipe-help` adds one line: “Stuck? Try `recipe-help --next`.”
- **PRD-less playbook:** Document: `recipe-onboard` + paste feature description **or** `recipe-prd-intake <description>`; only mention `gsd-discuss-phase` as advanced/alternate; avoid dead-end without inline example.
- **Prerequisites tiering:** “Start delivery (PRD + planning only)” vs “Full Jira track” vs “Ship PRs” — table at top of README/ONBOARD, not buried.
- **AND/OR cheat sheet:** One visual: onboarding = OR shortcuts; per-phase delivery = AND plan+run OR `recipe-run-phases --full`; place above delivery table.
- **recipe vs gsd decision rule:** “Type `recipe-*` for NetApp workflow gates; type `gsd-*` only when a recipe skill explicitly falls back or `gsd-help --full`.”
- **Hide harness/benchmark from onboarding path:** Move bench runners, AgentStudio rows, TASK-IDs to appendix; keep RECIPE-COMMANDS generated appendix behind `--runners`.
- **Reconcile catalog status:** Mark `recipe-new-project` accurately; if planned, say onboard uses native fallback by design.
- **Post-install smoke line:** After install: “Invoke `recipe-help --brief recipe-onboard`” (or `--next` when built) — single confirmation before feature work.
- **Gitignore callout in install success message:** “Scaffold is local-only by design; re-run install per clone” — prevents false “install broke git” reports.

[REDACTED]
