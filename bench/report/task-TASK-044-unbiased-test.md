# TASK-044 unbiased operator test (Platform)

**Persona:** Platform engineer. Did not implement. Did not search agent transcripts.  
**Date:** 2026-08-24  
**Allowed sources:** `.gsd-recipe/templates/recipe-install-verify-SKILL.md`; staged sandbox skill; install stdout; `install.sh` print-only MCP / `agent_skills` snippets plus `--record-jira-check` / `--verify` usage (not rewritten); `docs/netapp-recipe/SANDBOX.md`.  
**Sandbox:** `/Users/vs72964/Projects/recipe-sandbox-044` (reset this dir only; did **not** reset `$HOME/Projects/recipe-sandbox`).  
**Not run:** `install --uninstall`, AgentStudio, production Jira epic create, `recipe-install-verify` as a skill invocation (this session is a bash/MCP operator test).  
**Recipe source used:** `/Users/vs72964/Projects/gsd-benchmark`; alt clone `/tmp/gsd-benchmark-044-alt`.

**Overall: PASS** (AC 1, 2, 4, and AC3 skill-text). Live Atlassian MCP probe: **PASS** (read-only).

---

## Acceptance criteria

| # | Criterion | Result |
|---|-----------|--------|
| 1 | Print-only MCP / `agent_skills` paste snippet: no phantom skill paths; only real staged paths; paste checklist (where, restart Agent, how to confirm tools) | **PASS** |
| 2 | Reinstall from a different recipe clone refreshes `recipe_source`; unrelated config keys remain | **PASS** |
| 3 | `recipe-install-verify` documents live read-only Jira MCP → `--record-jira-check pass` → same-turn `--verify` so INSTALL-VERIFIED is reachable without a separate operator command | **PASS** (skill-text). Live probe: **PASS** (read-only; no epic create) |
| 4 | `install.sh --verify` fail-closed while `jira_check` pending; `--record-jira-check` remains a script/CI hatch | **PASS** |

---

## Commands run

```bash
cd /Users/vs72964/Projects/gsd-benchmark
./bench/runners/install-recipe-to-target.sh --help
# → exit 2: Unknown argument: --help  (flag --no-open-start still present in the runner)

./bench/runners/setup-recipe-sandbox.sh --dir "$HOME/Projects/recipe-sandbox-044" --reset
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox-044" --yes --no-open-start

# AC4
./.gsd-recipe/scripts/install.sh --verify --target "$HOME/Projects/recipe-sandbox-044"
./.gsd-recipe/scripts/install.sh --record-jira-check   # missing value; hatch exists, no write

# AC2 — sentinel key added on target config.json, then:
git clone --local /Users/vs72964/Projects/gsd-benchmark /tmp/gsd-benchmark-044-alt
/tmp/gsd-benchmark-044-alt/bench/runners/install-recipe-to-target.sh \
  --target "$HOME/Projects/recipe-sandbox-044" --yes --no-open-start
```

Read-only Atlassian MCP (this session): `getAccessibleAtlassianResources`; `getVisibleJiraProjects` with `action=view`, `searchString=sandbox`. Did not create issues. Did not use KAN keys.

---

## Staged verify skill (actual path)

`/Users/vs72964/Projects/recipe-sandbox-044/.cursor/skills/recipe-install-verify/SKILL.md`

Matches the source template’s doctor workflow (same-turn `--record-jira-check pass` then `--verify`).

Also staged (for AC1 path check): `skills/recipe-planning-policy/SKILL.md` (GSD `agent_skills` injection, not a Cursor invoke-by-name skill).

---

## AC1 — paste snippets, no phantom paths

Install stdout (and the same blocks on reinstall) printed:

**MCP (print-only):** `mcpServers.chrome-devtools` via `npx chrome-devtools-mcp@latest`. Mentions adding `gsd-browser` and a `{TRACKER}-mcp` (e.g. Atlassian) as operator choices — not fake recipe skill directories.

**Paste checklist (MCP):**

1. Open Cursor Settings > Tools & MCP, then open mcp.json.  
2. Merge the mcpServers entry; preserve existing servers and JSON keys.  
3. Save mcp.json and restart the Cursor Agent (new Agent chat).  
4. Ask the restarted Agent to list MCP tools and confirm the configured server and its tools appear.

**agent_skills (print-only):**

```json
"agent_skills": {
  "gsd-planner": ["skills/recipe-planning-policy"]
}
```

That path **was staged** (`skills/recipe-planning-policy/SKILL.md` in the ledger). No `recipe-repo-conventions`, `recipe-acceptance-criteria`, or similar unstaged names in install stdout or the staged tree.

**Paste checklist (agent_skills):**

1. Open this target repo’s `.planning/config.json`.  
2. Merge the entry; preserve existing JSON keys.  
3. Save and restart the Cursor Agent.  
4. Run `gsd-surface status` and confirm the planner lists `skills/recipe-planning-policy`.

Skeptical note: `.planning/config.json` did not exist in this dummy sandbox (graphify auto-set skipped). The checklist still tells the operator *where* to paste; first-init of GSD is a separate step. Not an AC1 fail.

---

## AC2 — `recipe_source` refresh

**Before** (after first install from `/Users/vs72964/Projects/gsd-benchmark`), plus tester sentinel:

```json
{
  "traceability": { "enabled": true, "reason": "" },
  "observer": { "enabled": false, "interval_minutes": 10 },
  "recipe_source": "/Users/vs72964/Projects/gsd-benchmark",
  "tracker": "jira",
  "task044_sentinel": "keep-me"
}
```

**After** reinstall from `/tmp/gsd-benchmark-044-alt`:

```json
{
  "traceability": { "enabled": true, "reason": "" },
  "observer": { "enabled": false, "interval_minutes": 10 },
  "recipe_source": "/tmp/gsd-benchmark-044-alt",
  "tracker": "jira",
  "task044_sentinel": "keep-me"
}
```

`recipe_source` changed to the clone that actually ran. Sentinel, `tracker`, `traceability`, and `observer` unchanged.

No `RECIPE_SOURCE` env override appeared in `.gsd-recipe/` (install usage header lists `--verify` / `--record-jira-check` / `--uninstall` only). Clone-path refresh is the implemented behavior; that satisfies AC2.

---

## AC3 — skill text + live probe

**Skill text (template and staged copy):** Item 8 requires a live non-mutating Atlassian call (`getAccessibleAtlassianResources`), then **immediately** in the same `recipe-install-verify` turn:

```
$INSTALL_SH --record-jira-check pass --target <target>
$INSTALL_SH --verify --target <target>
```

Frontmatter and workflow §6 say INSTALL-VERIFIED is reachable in one Agent turn without a separate operator command. If the live call fails, leave `jira_check` pending; never record a pass from schema listing alone.

**Live probe (this tester session):** `getAccessibleAtlassianResources` returned accessible site `https://netapp.atlassian.net` (cloud id present; no secrets copied here). `getVisibleJiraProjects` with `action=view` and query `sandbox` returned **0** projects (HTTP search succeeded; empty list). No issues created. Did **not** run `--record-jira-check pass` in this unbiased bash test (that belongs to the skill turn, not a silent hatch write).

---

## AC4 — fail-closed verify + hatch

`--verify` while `jira_check` is `pending`:

```
[X] 4b. Jira token/scope check — pending (blocks INSTALL-VERIFIED.json while pending)
...
One or more checks failed or are pending — .../INSTALL-VERIFIED.json NOT written.
VERIFY_EXIT=1
```

`INSTALL-VERIFIED.json` absent. Local template/OKF/gitignore/config checks passed; the pending Jira gate kept the script fail-closed.

`--record-jira-check` still exists: install stdout after stage prints Scripts/CI may use `--record-jira-check <pass|fail> --target ...`. Invoking with no value: ` --record-jira-check requires 'pass' or 'fail'` (exit 1). `jira_check` remained `"pending"` after both installs (`setdefault` on reinstall).

---

## Stdout excerpts (redacted)

First install closed with:

```
--- MCP registration (print-only — paste into your mcp.json by hand) ---
...
Paste checklist:
  1. Open Cursor Settings > Tools & MCP, then open mcp.json.
  ...
  4. Ask the restarted Agent to list MCP tools and confirm ...

--- agent_skills injection (print-only — paste into .planning/config.json by hand) ---
  "gsd-planner": ["skills/recipe-planning-policy"]
...
Jira check is recorded as 'pending' in .../install-report.json.
In Cursor Agent, invoke recipe-install-verify: it performs the live
Atlassian MCP check, records a pass, and reruns --verify in one turn.
Scripts/CI may still use:
  .../install.sh --record-jira-check <pass|fail> --target ...
```

`gh` was missing (`github_check: skipped`, warn-only). No token values printed.

---

## Surprises / friction (Platform)

1. `install-recipe-to-target.sh --help` is not implemented (unknown argument). `--no-open-start` still works; confirmed from the runner’s usage comments.
2. Installer tries `brew install gh` then continues warn-only when `gh` is absent.
3. Dummy sandbox has no `.planning/config.json`; paste checklist assumes that file exists after GSD init.
4. No `RECIPE_SOURCE` env in the installer tree; refresh is clone-path only.
5. Project search `sandbox` on netapp.atlassian.net returned empty — live auth works, no obvious sandbox Jira project by that name.
6. Reinstall from `/tmp/...` updates uninstall/hatch paths in stdout to the **alt** clone (`/tmp/gsd-benchmark-044-alt/.gsd-recipe/scripts/install.sh`). Correct for `recipe_source`, easy to miss if the operator expected the original laptop path.

---

## Verdict

TASK-044 doctor behavior is observable from install paste, `recipe_source` refresh, fail-closed `--verify`, and the staged verify skill’s same-turn Jira collapse. **PASS.**

---

## 10-line summary

1. MCP + `agent_skills` snippets include paste/restart/confirm checklists and only `skills/recipe-planning-policy` as a recipe skill path (staged).  
2. No phantom names (`recipe-repo-conventions`, `recipe-acceptance-criteria`).  
3. First install wrote `recipe_source` = `/Users/vs72964/Projects/gsd-benchmark`.  
4. Reinstall from `/tmp/gsd-benchmark-044-alt` refreshed it; sentinel and other keys stayed.  
5. Staged skill documents `--record-jira-check pass` then `--verify` in one Agent turn.  
6. `--verify` exit 1 while `jira_check=pending`; INSTALL-VERIFIED not written.  
7. `--record-jira-check` hatch still in usage and post-install copy.  
8. Live MCP: resources listed; sandbox project query empty; no epics filed.  
9. `--help` on the target installer is missing; `--no-open-start` is real.  
10. **PASS** AC1, AC2, AC3 skill-text (+ live probe), AC4.
