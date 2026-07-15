---
name: recipe-validate-tokens
description: "Recipe: standalone, re-invokable credential/scope check for the NetApp GSD recipe (TASK-021). Formalizes INSTALL-LLD.md Step 1's token validation (and Step 5 checklist item 4's 're-run step 1 probes') into its own skill: runs a real, scriptable gh auth status / gh api user probe for GitHub, and instructs the invoking agent to check Atlassian MCP auth state directly (agent-mediated, not scriptable) for Jira. Reports PASS/FAIL/WARN per credential with soft remediation suggestions — never fixes anything itself, never prints token values, never touches .gsd-recipe/config.json or .planning/config.json."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-validate-tokens`) with no arguments — this skill takes none.

Examples:
- `recipe-validate-tokens`

Re-invokable at any time: before `install.sh` has ever run, right after it, or standalone months
later to re-check credentials that may have expired or been revoked (the same "re-run step 1
probes" checklist item `INSTALL-LLD.md` Step 5 #4 describes).

## B. Prerequisites

None. This skill *is* the prerequisite check other flows (`install.sh` Step 1, `gsd-jira-sync`'s
own "Atlassian MCP enabled and authenticated" prerequisite) depend on — it has no prerequisites of
its own, and is safe to invoke on a repo that hasn't been scaffolded yet.

## C. Tool Usage

1. **GitHub check (scriptable — run the real script, do not reimplement it inline).** `Shell`: run
   `.gsd-recipe/scripts/install-recipe-validate-tokens.sh --check-github` (bundled path once
   staged; if this skill hasn't been installed yet in the current repo, the canonical source is
   `.gsd-recipe/scripts/install-recipe-validate-tokens.sh` in the recipe's own source tree). This
   mirrors `install.sh`'s own `github_check()` — real `gh auth status` + `gh api user`, warn-only —
   extended to also surface OAuth scopes when determinable. Read its `PASS`/`WARN`/`FAIL` line and
   any `Scopes:`/`Remediation:` detail lines verbatim into your summary in step 3. Never re-derive
   the check yourself from a raw `gh` call inline — always go through the script so there is exactly
   one implementation of the check logic.

2. **Jira/Atlassian MCP check (agent-mediated — this is NOT scriptable).** A bash script has no
   MCP tool-calling access — the same architectural split `bench/runners/sync-reconcile.sh`
   documents for why it can queue but never post ("a bash script has no MCP tool-calling access").
   Only an agent turn (you, right now) can see this session's real Atlassian MCP auth state. Do
   this directly, in this turn, using your own `GetMcpTools`/`CallMcpTool` access:
   a. Call `GetMcpTools` for the Atlassian server (id `plugin-atlassian-atlassian`, or whichever
      Atlassian-flavored MCP server is present in this environment's catalog). If no such server
      exists, or its `serverStatus` is `needsAuth`/`error`/`loading`, that alone is enough to
      report `Jira/Atlassian: FAIL` — do not proceed to (b) with a server known to be unusable.
   b. If the server looks usable, call a single **lightweight, read-only** probe —
      `CallMcpTool` with `server: "plugin-atlassian-atlassian"`, `toolName:
      "getAccessibleAtlassianResources"`, empty `arguments`. A successful call returning at least
      one accessible resource (site `url`/`cloudId`) → report `Jira/Atlassian: PASS`, citing the
      resolved site `url` (never any token/credential value). An error, or a response with zero
      resources → report `Jira/Atlassian: WARN` (server present and apparently authenticated per
      `GetMcpTools`, but the live probe didn't confirm real access — could be a stale session,
      network blip, or an account with genuinely no accessible sites).
   c. Never call `mcp_auth` as *part of* this check — that is a remediation action (it can trigger
      a real OAuth consent flow), not a read-only probe. Only *suggest* it in the summary (step 3)
      when the result isn't `PASS`.
   d. Be explicit that an unrelated Bearer PAT (e.g. an env var like `JIRA_NGAGE_TOKEN`, scoped to
      a self-hosted Jira Server/Data Center instance such as `jira.ngage.netapp.com`) does **not**
      satisfy this check, even if it happens to be set and valid — per
      `bench/report/gsd-jira-sync-live-test-report.md` § "Prerequisite: MCP auth vs.
      JIRA_NGAGE_TOKEN", that token is a completely different product/account namespace from the
      Atlassian Cloud OAuth session (`netapp.atlassian.net` or the target site's cloudId) that
      `gsd-jira-sync`/`TRACEABILITY-LLD.md` actually requires. If you notice such an env var is
      set, do not treat its presence as evidence of Jira/Atlassian readiness.

3. **Summarize.** Report exactly one line per credential:
   - `GitHub: PASS|WARN|FAIL (<one-line detail from the script's output>)`
   - `Jira/Atlassian MCP: PASS|WARN|FAIL (<one-line detail from your own MCP probe>)`

   For anything not `PASS`, add a soft, non-blocking remediation suggestion on the next line —
   `gh auth login` for GitHub, `mcp_auth` (naming the specific server) for Jira/Atlassian. Never
   print or log actual token/credential values in this summary, even partially or masked-looking.

## D. Do NOT

- Do not attempt to fix or authenticate anything yourself — no running `gh auth login`, no calling
  `mcp_auth`, no editing any credential/config file. Remediation is always a suggestion for a human
  to act on, never an action this skill takes on their behalf.
- Do not print, log, or echo actual token/credential values for either credential, even partially.
  `gh auth status`'s own output already masks its token; this skill's script goes further and never
  surfaces the raw `Token:` line at all — only `Logged in to ...` (username) and `Token scopes:`.
- Do not touch `.gsd-recipe/config.json` or `.planning/config.json` — this skill never writes a
  report artifact of its own (unlike `install.sh`'s `install-report.json`); it is a same-turn,
  on-screen check only.
- Do not treat a `FAIL`/`WARN` result as blocking anything outside this skill's own turn — this
  skill only reports. Whatever invoked it (a human, or another skill like `install.sh`'s own
  separate warn-only Gate A) decides what to do with the result; `recipe-validate-tokens` itself
  never aborts a workflow.
- Do not shell out to probe Jira/Atlassian directly (`curl` against its REST API, etc.). The entire
  reason the Jira check is agent-mediated is that only the MCP tool-calling surface can see this
  session's real auth state — a raw HTTP probe would need its own separately-sourced credentials,
  which is explicitly not this skill's job to hold or manage.
- Do not duplicate `install.sh`'s own prerequisite bootstrap (`preflight()`/`ensure_prereq()` for
  `python3`/`git`/`node`/`gsd_core`/`graphify`) or its `--record-jira-check` hand-off mechanism.
  Those are install-time gates for a *specific install run*; this skill is a narrower, standalone,
  repeatedly-invokable credential check that exists independently of any particular install.
</cursor_skill_adapter>

# recipe-validate-tokens — standalone credential/scope check (TASK-021)

Formalizes `docs/netapp-recipe/lld/INSTALL-LLD.md` Step 1 ("Token validation [X]") and Step 5's
verification checklist item 4 ("Token still valid — Re-run step 1 probes") into its own
invoke-by-name Cursor skill, so an operator (or another skill) can re-check GitHub/Jira credentials
at any time without re-running the full `install.sh`.

**Spec:** `docs/netapp-recipe/lld/INSTALL-LLD.md` § Step 1, § Step 5 #4 · `docs/netapp-recipe/BACKLOG.md` TASK-021.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) ahead of/alongside the full `install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-validate-tokens.sh`.

## Workflow

1. Run the real, scriptable GitHub check (`install-recipe-validate-tokens.sh --check-github`) —
   `gh auth status` + `gh api user`, warn-only, with scopes surfaced when determinable.
2. Directly probe Atlassian MCP auth state in this same agent turn (`GetMcpTools` +
   `CallMcpTool getAccessibleAtlassianResources`) — this cannot be scripted, since a bash process
   has no MCP tool-calling access.
3. Report one `PASS`/`WARN`/`FAIL` line per credential, with soft remediation suggestions for
   anything not `PASS`. Never fixes anything, never prints token values.

## Why the GitHub check is scriptable but the Jira check isn't

Same architectural split already documented in `bench/runners/sync-reconcile.sh` ("a bash script
has no MCP tool-calling access") and confirmed in `bench/report/install-scaffold-integration-report.md`
for `install.sh`'s own Step 1 implementation: `gh` is a local CLI a plain shell process can invoke
directly, so the GitHub half of this check is a real, standalone, testable script. The Atlassian
MCP session, by contrast, only exists inside a live agent turn — `CallMcpTool`/`GetMcpTools` are
capabilities of the *agent*, not of a `bash`/`python3` subprocess this skill could shell out to.
This skill's own instructions are explicit about that split so the invoking agent does the Jira
check itself rather than trying (and failing) to script it.

## Relationship to `install.sh`'s own token checks

`install.sh` (TASK-010) already performs a warn-only GitHub check via its own `github_check()`
function and records a Jira check as `"pending"` pending an agent-mediated
`--record-jira-check <pass|fail>` call — see
`bench/report/install-scaffold-integration-report.md`. `recipe-validate-tokens` is a **narrower,
standalone, re-invokable sibling** of that logic, not a replacement:

- It mirrors (does not source) `install.sh`'s `github_check()` GitHub-check approach in its own
  `--check-github` mode, extended to surface OAuth scopes.
- It performs the Jira/Atlassian check itself (agent-mediated, same-turn) rather than deferring to
  a later `--record-jira-check` call — useful for a quick standalone credential sanity-check that
  doesn't require running (or having already run) `install.sh` at all.
- It never writes `.gsd-recipe/install-report.json` or any other artifact — this is an on-screen,
  same-turn report only. `install.sh` remains the sole owner of `install-report.json` and
  `INSTALL-VERIFIED.json`.
- It does not implement `install.sh`'s prerequisite bootstrap (`python3`/`git`/`node`/`gsd_core`/
  `graphify` detection+auto-fix) — that machinery is specific to a scaffolding install run, not a
  credential check.

A future integration pass could compose `install-recipe-validate-tokens.sh --check-github` *into*
`install.sh`'s own `github_check()` (or vice versa) to have exactly one implementation shared by
both call sites — deliberately left as a follow-up rather than done here, since this task's scope
was constrained to avoid editing `install.sh` (parallel work by another task on that same file).

## What this does NOT do

- **Does not fix or authenticate anything.** No `gh auth login`, no `mcp_auth` call, no writing to
  any credential store — remediation is always a suggestion, never an action.
- **Does not print token values.** The GitHub check's script never surfaces `gh auth status`'s
  `Token:` line; the Jira check never asks for or echoes a credential.
- **Does not touch `.gsd-recipe/config.json` or `.planning/config.json`.** No report artifact is
  written by this skill.
- **Does not block anything.** `PASS`/`WARN`/`FAIL` is purely informational — the invoking
  operator or skill decides what to do with the result.
