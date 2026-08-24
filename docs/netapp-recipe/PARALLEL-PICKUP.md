# Parallel pickup — TASK-040 + TASK-044

**Status:** implementation landed on `main` (TASK-040 merge `b023a97`, TASK-044 merge `af65850`). Unbiased testers **PASS** — [task-TASK-040-unbiased-test.md](../../bench/report/task-TASK-040-unbiased-test.md), [task-TASK-044-unbiased-test.md](../../bench/report/task-TASK-044-unbiased-test.md). **Do not** share one working tree or one sandbox.

Historical exception to BACKLOG “one TASK at a time”: these two closed remaining first-success install friction and **did not share implementation files** if the ownership table below was followed.

Specs: [BACKLOG TASK-040](BACKLOG.md) (OD-14) · [BACKLOG TASK-044](BACKLOG.md) (OD-16) · [INSTALL-LLD](lld/INSTALL-LLD.md) · [CONTROL-GROUP](CONTROL-GROUP.md) P0#1 / P1 doctor.

---

## Merge order

1. Land **TASK-040** first (docs, small).
2. Rebase **TASK-044** onto that merge if it drifted.
3. Regenerate `docs/RECIPE-COMMANDS.md` **once** after both land (`bench/lib/generate-recipe-help.sh`).
4. Unbiased testers: **fresh agents**, not the implementers. Reports: `bench/report/task-TASK-040-unbiased-test.md` and `bench/report/task-TASK-044-unbiased-test.md`.

Never AgentStudio. Sandboxes: [SANDBOX.md](SANDBOX.md).

---

## File ownership (do not cross)

| Path | 040 | 044 |
|------|:---:|:---:|
| `README.md` (repo root) | **own** | one-line pointer only if doctor UX changes the verify step |
| `docs/netapp-recipe/README.md` Built/commands rows | **own** | Built row for doctor only |
| `docs/netapp-recipe/CLONE.md` | **own** | no |
| `docs/netapp-recipe/AGENTS.md` boot sequence | **own** | no |
| `bin/recipe` + its comments | **own** (keep or retire in docs; if keep, point at bash first-install) | no |
| `.gsd-recipe/templates/recipe-install-SKILL.md` | **docs only** — chicken-and-egg | no behavior change except “verify may record Jira” after 044 |
| `.gsd-recipe/scripts/install.sh` | **forbidden** | **own** |
| `.gsd-recipe/templates/recipe-install-verify-SKILL.md` | no | **own** |
| `.gsd-recipe/scripts/install-recipe-install-verify.sh` | no | if skill/installer must restage |
| `config_json_merge` / `recipe_source` in `install.sh` | no | **own** |
| `print_mcp_snippet` / `print_agent_skills_snippet` | no | **own** |
| `bench/tests/test-install.sh` | grep-only for README/success copy if needed | **own** (jira_check, recipe_source refresh, snippet) |
| `bench/tests/test-install-recipe-install.sh` | skill-doc assertions | no |
| `bench/tests/test-install-recipe-install-verify.sh` | no | **own** |
| `docs/RECIPE-COMMANDS.md` | regenerate at end of *your* branch if catalog text in generate-recipe-help changes | same; last merge regenerates |
| `docs/netapp-recipe/BACKLOG.md` Built row | your task only | your task only |
| `docs/netapp-recipe/PARALLEL-PICKUP.md` | neither (this file) | neither |

If you need a file the other agent owns: stop, comment on the PR, do not “just edit it.”

---

## Agent A — TASK-040 (install front door)

**Branch:** `task/TASK-040-install-front-door` from `main`.

**Goal:** One canonical first-install path so New-dev + Platform are not misled. **No new runtime** (BACKLOG).

**Canonical story (must appear on root README Quick start):**

1. First install from the **recipe source clone:**  
   `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes`
2. Interactive install may open Cursor with `recipe-start` prefilled (Enter to send). `--no-open-start` to skip.
3. `recipe-install` is **re-run / restage after skills exist**, not first clone.
4. `install.sh` is the composed implementation `install-recipe-to-target.sh` already calls — operators should not pick among three commands.
5. `bin/recipe install` — document as a thin alias of the runner **or** retire the mention if you choose keep-vs-retire; pick one and be consistent in README + CLONE + `bin/recipe` header.

**AC (tester will use these):**

- [ ] Root README has a one-page decision tree: first clone vs restage vs verify vs uninstall.
- [ ] Chicken-and-egg is explicit: do not type `recipe-install` before skills exist.
- [ ] After install, next command is `recipe-start` (and `recipe-status` as optional snapshot).
- [ ] CLONE.md and AGENTS.md 3c agree with README (no third story).
- [ ] `recipe-install` skill text matches (re-run after staged).
- [ ] Tests: `bench/tests/test-install-recipe-install.sh` (and any new grep tests). Do not rewrite `test-install.sh` Jira/MCP cases.

**Sandbox:** `./bench/runners/setup-recipe-sandbox.sh --dir "$HOME/Projects/recipe-sandbox-040" --reset`  
Install from recipe source with `--yes`. Confirm first-install docs match what you typed. Confirm `recipe-install` is not the first command.

**Unbiased tester persona:** New-dev + Platform. Give only README + CLONE + `recipe-install` SKILL.md.

**Out of scope:** MCP paste, `recipe_source` refresh, collapsing `--record-jira-check` (TASK-044).

---

## Agent B — TASK-044 (install doctor)

**Branch:** `task/TASK-044-install-doctor` from `main`.

**Goal:** One re-runnable doctor so Jira/MCP/`recipe_source` do not silently fail after install. Extends `recipe-install-verify` / `install.sh --verify` — **no new `recipe-doctor` command**.

**(a) MCP / `agent_skills` paste**

Today: `print_mcp_snippet` / `print_agent_skills_snippet` in `.gsd-recipe/scripts/install.sh`. Phantom paths include `skills/recipe-repo-conventions` and `skills/recipe-acceptance-criteria` (not staged). Fix to only real staged paths (at minimum `recipe-planning-policy` as already installed). Add a short paste checklist (where to paste, restart Agent, how to confirm tools listed). Still print-only — do not auto-edit Cursor `mcp.json` or `.planning/config.json` except existing graphify `gsd-tools` exception.

**(b) `recipe_source`**

Today write-once (`"recipe_source" not in data`). On reinstall, if `self_root` differs, update it (or honor env e.g. `RECIPE_SOURCE` — document one). Fail closed in `recipe-paths.sh` stays. Add/adjust `test-install.sh` assertions.

**(c) Jira verify collapse**

Today: `jira_check: pending` until `install.sh --record-jira-check pass`. Collapse into **`recipe-install-verify`**: that skill already can run `recipe-validate-tokens` / Atlassian MCP; on live pass it should record pass (call `--record-jira-check` or equivalent) so `INSTALL-VERIFIED.json` is reachable in **one** agent turn. Keep `--record-jira-check` as a low-level escape hatch. Update `recipe-install-verify` skill; keep `install.sh --verify` fail-closed while still pending **unless** verify skill just recorded pass in the same turn.

**AC:**

- [ ] Paste snippet has no phantom skill paths; checklist present.
- [ ] Reinstall from a different recipe clone path refreshes `recipe_source` (or env override wins).
- [ ] `recipe-install-verify` with live MCP can complete INSTALL-VERIFIED without a separate operator `--record-jira-check` command.
- [ ] `--record-jira-check` still works for scripts/CI.
- [ ] Tests: `test-install.sh`, `test-install-recipe-install-verify.sh`; fixture for snippet paths.

**Sandbox:** `--dir "$HOME/Projects/recipe-sandbox-044" --reset`. Live Atlassian MCP required for (c). Do not file production KAN epics.

**Unbiased tester persona:** Platform. Give install output snippet + `recipe-install-verify` SKILL.md + AC.

**Out of scope:** README decision tree (040). `recipe-update` (058) may *use* refreshed `recipe_source` later — do not build 058.

---

## Shared rules

- Repo-agnostic: no product repo names, no hardcoded Jira keys.
- Do not invoke native GSD skills unless the skill you own documents same-turn Option B.
- Do not commit the other agent’s files.
- If blocked on ownership: leave a PR comment, do not expand scope.

## How to spawn (operator)

Two Cursor Agent chats (or Task agents), each pasted **only** its section (Agent A or Agent B), plus: “Follow `docs/netapp-recipe/PARALLEL-PICKUP.md`. Branch from `main`. Unbiased tester is a separate later agent.”
