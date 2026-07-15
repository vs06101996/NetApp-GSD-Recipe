# `recipe-validate-tokens` skill (TASK-021)

Built per direct task assignment, formalizing `docs/netapp-recipe/lld/INSTALL-LLD.md` Step 1
("Token validation [X]") and Step 5 checklist item 4 ("Token still valid — Re-run step 1 probes")
into its own standalone, re-invokable Cursor skill. `BACKLOG.md` lists TASK-021 with `Depends: —`,
matching the standalone-installer precedent already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) — built ahead of/alongside the full `install.sh` (TASK-010).

**This task ran in parallel with four sibling tasks** (TASK-007, TASK-011, TASK-022, TASK-023)
editing the same repo concurrently. Per the explicit shared-file-avoidance constraint, **none** of
`.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`,
or `docs/netapp-recipe/README.md` were edited by this task — copy-paste-ready snippets for all four
are provided at the end of this report for a follow-up integration pass to apply.

## Scope decisions

1. **Reuse, don't duplicate, `install.sh`'s GitHub-check approach — but mirror it, don't `source`
   it.** `install.sh` has no safe sourceable entry point: its own case-statement dispatch
   (`case "$MODE" in install) install ;; ... esac`) runs unconditionally the instant the file is
   loaded, defaulting to `MODE="install"` — `source`-ing it as a way to borrow its `github_check()`
   function would trigger a live install as a side effect. Editing `install.sh` to extract a
   sourceable helper was also out of scope (shared-file constraint). So
   `install-recipe-validate-tokens.sh --check-github` reimplements the same real
   `gh auth status` + `gh api user`, warn-only check `install.sh`'s `github_check()` already does,
   extended to surface OAuth scopes and the logged-in username while explicitly never surfacing
   `gh auth status`'s own `Token:` line. This is intentional, narrow duplication — not a rewrite of
   the underlying approach — and the skill's own doc calls out that a future integration pass could
   compose the two into one shared implementation once `install.sh` is free to edit again.
2. **Jira/Atlassian check is agent-mediated, not scriptable — same architectural constraint already
   documented for `sync-reconcile.sh` and `install.sh`'s own `--record-jira-check` hand-off.** A
   bash process has no MCP tool-calling access; only a live agent turn can call `GetMcpTools`/
   `CallMcpTool`. Unlike `install.sh` (which defers this to a separate `--record-jira-check`
   call after the fact), `recipe-validate-tokens`'s own skill instructions tell the invoking agent
   to do the real MCP probe **directly, in the same turn** — `GetMcpTools` to check server status,
   then a single lightweight `CallMcpTool getAccessibleAtlassianResources` probe if the server
   looks usable.
3. **Never writes an artifact.** Unlike `install.sh`'s `install-report.json`, this skill's check is
   purely on-screen/same-turn — no `.gsd-recipe/install-report.json`, no new file, ever. Confirmed
   by an explicit test assertion (`--check-github` writes nothing; the installer itself never
   creates `.gsd-recipe/config.json` or `.planning/config.json`).
4. **Never prints token values.** `gh auth status`'s own output line `Token: gho_****...` is never
   even read by the script into its filtered summary — only `Logged in to ...` (username) and
   `Token scopes:` are extracted and echoed. Verified with a fake `gh` stub whose fake token value
   is asserted absent from the script's real stdout.
5. **CLI shape mirrors `install-recipe-run-phase.sh`'s installer/uninstaller precedent, plus a
   net-new `--check-github` mode** that needs no `--target`/git-repo check at all (it's a pure,
   read-only local credential probe, unrelated to any scaffolding) and never fails closed — a
   missing/unauthenticated `gh` is reported as `FAIL`/`WARN`, but the script itself always exits 0.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-validate-tokens-SKILL.md` | Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-run-phase-SKILL.md`'s format). Instructs the invoking agent to (1) run the real `--check-github` script for the GitHub check, (2) do the Jira/Atlassian MCP check itself in the same turn (`GetMcpTools` status check, then `CallMcpTool getAccessibleAtlassianResources`), being explicit about the OAuth-vs-Bearer-PAT distinction (`JIRA_NGAGE_TOKEN` does not count), and (3) report one `PASS`/`WARN`/`FAIL` line per credential with soft, non-blocking remediation suggestions (`gh auth login`, `mcp_auth`) — never fixing anything, never printing token values, never touching `.gsd-recipe/config.json`/`.planning/config.json`. |
| Installer | `.gsd-recipe/scripts/install-recipe-validate-tokens.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-validate-tokens/SKILL.md`. Component name `"recipe-validate-tokens"`. Also ships a net-new `--check-github` mode: the real, standalone, testable GitHub credential/scope probe. Never touches `.gsd-recipe/config.json` or `.planning/config.json`. |
| Tests | `bench/tests/test-install-recipe-validate-tokens.sh` (37 assertions) | Installer behavior (fresh install, idempotency, uninstall, self-install, fail-closed, never touches either config.json, staged-content assertions for every documented gate/behavior) plus `--check-github` mode exercised against fake `gh` stubs covering FAIL (absent)/WARN (unauthenticated)/WARN (api probe fails)/PASS (fully authenticated) paths, including an explicit no-token-leak assertion. Deliberately excludes `install.sh` composition assertions (that file isn't edited by this task). |
| Self-install | `.cursor/skills/recipe-validate-tokens/SKILL.md` | Not committed as a lasting side effect — this task's manual verification used its own disposable `/tmp/task-021-manual-01` scratch repo (installed, exercised, then fully uninstalled and removed) rather than self-installing into the real `gsd-benchmark` repo, since a live self-install here would add another untracked file this task didn't need to leave behind. |

### Why `--check-github` needs no `--target`/git-repo check

Every other mode in this installer (`install`, `--uninstall`) writes files into a target repo and
so fail-closes on a non-git `--target`, matching every prior `recipe-*` installer's precedent.
`--check-github` writes nothing anywhere — it's a pure, read-only introspection of the local `gh`
CLI's own auth state, completely unrelated to any specific repo. Requiring a git repo for it would
be an arbitrary, unhelpful restriction (an operator should be able to run
`recipe-validate-tokens --check-github` from anywhere, even before cloning a target repo), so this
mode is dispatched before the `--target`/git-repo resolution block runs at all.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Editing `install.sh` to wire in a sixth sub-installer, or to extract a sourceable `github_check()` helper both scripts could share | Shared-file-avoidance constraint — four sibling tasks (TASK-007, TASK-011, TASK-022, TASK-023) are editing `install.sh` concurrently. Copy-paste-ready snippet provided below. |
| Editing `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md` | Same constraint. Copy-paste-ready snippets provided below. |
| Replacing or removing `install.sh`'s own `github_check()`/`--record-jira-check` mechanism | This skill is a narrower, standalone sibling, not a replacement — `install.sh` remains the sole owner of `install-report.json`/`INSTALL-VERIFIED.json`. |
| Automating `gh auth login` or `mcp_auth` | Both are explicitly remediation actions a human must trigger — this skill only ever suggests them, per the task's own constraint #3 ("without ever attempting to fix things itself"). |
| A raw HTTP probe of Jira/Atlassian (`curl` against its REST API) as a scriptable alternative to the MCP check | Would need its own separately-sourced credentials this skill has no business holding — the entire point of routing the Jira check through the agent turn is that only the MCP tool-calling surface can see the session's real OAuth state. |

## Validation performed

### Automated

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-validate-tokens/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row (the skill file) | PASS |
| 4-5 | Install never creates `.gsd-recipe/config.json` / `.planning/config.json` | PASS |
| 6-17 | Staged content references the real `gh auth status` probe, `--check-github` invocation, `CallMcpTool`, `getAccessibleAtlassianResources`, `mcp_auth` remediation, the bash-has-no-MCP-access split, the PASS/WARN/FAIL summary format, the no-token-printing disclaimer, the no-self-fix disclaimer, the OAuth-vs-Bearer-PAT distinction, and never touching either config.json (12 separate `grep` assertions) | PASS (all 12) |
| 18 | Staged content documents non-blocking behavior | PASS |
| 19 | Re-running install does not duplicate ledger rows | PASS |
| 20-22 | Uninstall removes the staged skill, clears the ledger entry, cleans up the now-empty skill directory | PASS |
| 23-25 | Self-install into a copy of this repo does not error; self-install uninstall does not error; self-uninstall preserves the canonical skill template source | PASS |
| 26-28 | `--check-github` with `gh` completely absent: exits 0, reports `FAIL`, suggests `gh auth login` | PASS |
| 29-30 | `--check-github` with `gh` present but unauthenticated: exits 0, reports `WARN` | PASS |
| 31-32 | `--check-github` with `gh auth status` succeeding but `gh api user` failing: exits 0, reports `WARN` | PASS |
| 33-37 | `--check-github` fully authenticated: exits 0, reports `PASS`, surfaces real parsed scopes, surfaces the logged-in username, and **never leaks the fake token value** into stdout | PASS (all 5) |

`bench/tests/test-install-recipe-validate-tokens.sh` total: **37 assertions, 0 failed**, run
standalone (not as part of the full `bench/tests/` suite, per this task's explicit instruction not
to run the full suite while sibling agents are concurrently editing shared files):

```
$ ./bench/tests/test-install-recipe-validate-tokens.sh
...
37 passed, 0 failed
```

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/task-021-manual-01`, created and torn down entirely
within this task — never the real `gsd-benchmark` repo's own tree. Every command used a single
self-contained absolute-path invocation (either an explicit `--target`, or `PATH=... <absolute
script path>`), never relying on `cd`/exported-variable persistence across separate tool calls, per
this task's explicit safety instruction.

1. **Real install.** `git init` the scratch repo, then the real
   `.gsd-recipe/scripts/install-recipe-validate-tokens.sh --yes --target /tmp/task-021-manual-01` —
   a genuine execution, not simulated. Staged a real
   `.cursor/skills/recipe-validate-tokens/SKILL.md` (11,770 bytes — the full skill content) and
   recorded exactly 1 ledger row. Confirmed `.gsd-recipe/` contains only `ledger.json` (no
   `config.json`) and `.planning/` was never created — matching the "never touches either
   config.json" requirement for real, not just in the unit tests.
2. **Real GitHub check — FAIL path.** Ran `--check-github` from within the scratch repo against
   this machine's actual, unmodified `PATH`. Result: `GitHub: FAIL (gh CLI not found on PATH)`.
   This is a **genuinely accurate** real-environment result, not a test artifact: this exact
   machine has a broken `gh` symlink (`~/homebrew/bin/gh` → `../Cellar/gh/2.92.0/bin/gh`, but the
   installed keg is `2.96.0` — the `2.92.0` target no longer exists), already independently
   discovered and documented in `bench/report/install-scaffold-integration-report.md`'s "Real-world
   discrepancy found" section for `install.sh`'s own GitHub check. `command -v gh` genuinely fails
   on this machine right now, so `FAIL` is the correct, real answer.
3. **Real GitHub check — PASS path.** To prove the script's `PASS` branch against a genuinely
   working `gh` binary (without touching the broken symlink or running any destructive
   fix), a scratch `PATH` was built with a symlink pointing directly at the real, working keg
   (`~/homebrew/Cellar/gh/2.96.0/bin/gh`), and `--check-github` was re-run with that `PATH`
   prepended, from within the scratch repo. This is a **real `gh auth status`/`gh api user` call
   against this developer's actual, live GitHub OAuth session** — not mocked. Result:
   ```
   GitHub: PASS (gh CLI authenticated, API probe succeeded)
     Logged in to github.com account vs06101996 (keyring)
     Token scopes: 'gist', 'read:org', 'repo', 'workflow'
   ```
   No token value was printed in either the raw `gh auth status` output (which self-masks as
   `gho_************************************`) or the script's own filtered summary above.
4. **Real Jira/Atlassian MCP check.** Traced the skill's own step 2 instructions and then actually
   executed them, since this session has genuine `CallMcpTool`/`GetMcpTools` access and the probe
   is read-only:
   - `GetMcpTools` for `plugin-atlassian-atlassian` → real result: `serverStatus: "ready"` (not
     `needsAuth`/`error`/`loading`), so per the skill's own step 2(a) logic, the check proceeds to
     the live probe rather than stopping at `FAIL`.
   - `CallMcpTool getAccessibleAtlassianResources` with empty arguments → **real, live call**,
     not simulated. Result: one accessible site, `https://netapp.atlassian.net`
     (cloudId `cb69b23c-616e-461b-9cf1-b3015880f8dd` — the same cloudId independently confirmed in
     `bench/report/gsd-jira-sync-live-test-report.md`'s live Jira test), with Jira/Confluence read
     and write scopes listed. Per the skill's own step 2(b) logic, a successful call returning at
     least one accessible resource → `Jira/Atlassian: PASS`. No token/credential value was returned
     or printed — only a public cloudId, site URL, and scope list.
5. **Real uninstall.** Ran `--uninstall --target /tmp/task-021-manual-01` — removed the staged
   skill file, cleared the ledger back to `{}`, and the (now-empty) component skill directory was
   cleaned up. The entire scratch repo was then `rm -rf`'d; nothing was left under `/tmp`.

**What was truly exercised vs. traced:**

- **Truly executed, real, no mocks:** the installer itself (real install + real uninstall against a
  real scratch git repo); the real `gh auth status`/`gh api user` GitHub check in both its genuine
  `FAIL` state (this machine's actual broken symlink) and its genuine `PASS` state (this developer's
  actual authenticated GitHub session, reached via a symlink to the real working binary — never a
  fake `gh` stub for this part of the manual verification); the real, live Atlassian MCP probe
  (`GetMcpTools` status check + `CallMcpTool getAccessibleAtlassianResources`), which is the exact
  mechanism the skill's own instructions describe an invoking agent doing.
- **Traced/reasoned about, not separately re-executed in the manual pass:** the `WARN` paths (`gh`
  present-but-unauthenticated, `gh auth status` succeeds but `gh api user` fails) — these are
  already covered by real script executions against fake `gh` stubs in the automated test suite
  (assertions 29-32 above), and re-deriving them again by tampering with this developer's real `gh`
  auth state would violate the task's explicit "safe read-only introspection... not a destructive
  action" boundary. The `FAIL`/`needsAuth` branch of the Jira/Atlassian check (server absent or not
  authenticated) was not separately exercised for real in this pass either, since the real
  Atlassian MCP in this session is genuinely `ready` right now — reasoned through instead: the
  skill's step 2(a) instruction to short-circuit straight to `FAIL` without attempting the probe is
  a simple, directly-readable conditional in its own text, not complex logic that needed a live
  negative-case rehearsal to validate.

## Real repo git status (confirms only intended new files)

```
$ git -C /Users/vs72964/Projects/gsd-benchmark status --porcelain --untracked-files=all -- .gsd-recipe/ bench/tests/ bench/report/
```

shows exactly (among the many pre-existing/sibling-task untracked files already present before this
task started, per the conversation's initial `git_status` snapshot and the four sibling tasks
running concurrently):

- `.gsd-recipe/scripts/install-recipe-validate-tokens.sh` (new, this task)
- `.gsd-recipe/templates/recipe-validate-tokens-SKILL.md` (new, this task)
- `bench/tests/test-install-recipe-validate-tokens.sh` (new, this task)
- `bench/report/recipe-validate-tokens-integration-report.md` (new, this task — this file)

None of `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, or `docs/netapp-recipe/README.md` show as modified (`M`) by this
task — they remain exactly as this task found them.

## Copy-paste-ready snippets for a follow-up integration pass

Not applied by this task (shared-file-avoidance constraint). A follow-up pass should apply these
once the sibling tasks editing the same files have landed.

### `.gsd-recipe/scripts/install.sh`

Add the path variable alongside the existing five (near `RECIPE_PLAN_PHASE_INSTALLER`):

```bash
RECIPE_VALIDATE_TOKENS_INSTALLER="$SCRIPT_DIR/install-recipe-validate-tokens.sh"
```

In `install()`, alongside the existing five `--yes --target "$TARGET"` calls:

```bash
"$RECIPE_VALIDATE_TOKENS_INSTALLER" --yes --target "$TARGET"
```

(Also update the operator-facing consent prompt string and the "composing sub-installers..." echo
line to name `recipe-validate-tokens` as the sixth sub-installer, matching how each prior addition
updated those strings.)

In `uninstall()`, alongside the existing five `--uninstall --target "$TARGET"` cascades:

```bash
"$RECIPE_VALIDATE_TOKENS_INSTALLER" --uninstall --target "$TARGET"
```

In `verify()`, alongside the existing five `ledger_has_component` checks:

```bash
if ledger_has_component "recipe-validate-tokens"; then
  echo "    recipe-validate-tokens composed — pass"
else
  echo "    recipe-validate-tokens composed — FAIL (recipe-validate-tokens ledger component absent)"
  ok=0
fi
```

### `bench/tests/test-install.sh`

Composition assertions, matching the exact shape of the existing `RECIPE_PLAN_PHASE_INSTALLER`
checks:

```bash
grep -q "RECIPE_VALIDATE_TOKENS_INSTALLER" "$INSTALLER" && rc=0 || rc=$?
check "install.sh declares RECIPE_VALIDATE_TOKENS_INSTALLER" "$rc"
grep -q 'RECIPE_VALIDATE_TOKENS_INSTALLER" --yes' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_VALIDATE_TOKENS_INSTALLER --yes" "$rc"
grep -q 'RECIPE_VALIDATE_TOKENS_INSTALLER" --uninstall' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_VALIDATE_TOKENS_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-validate-tokens"' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-validate-tokens ledger component" "$rc"
```

(Where `$INSTALLER` is that test file's existing variable pointing at `install.sh`. If that file
already has a ledger-cross-tracking-disjointness assertion enumerating each sub-installer's
component name, extend that list to include `"recipe-validate-tokens"` too, rather than adding a
new standalone assertion for it — matching how TASK-017's addition to this same file was described
in its own report.)

### `docs/netapp-recipe/BACKLOG.md`

Replace the TASK-021 row (currently `| TASK-021 | recipe-validate-tokens | S | — |
[INSTALL-LLD](lld/INSTALL-LLD.md) |`) with a narrated-scope note, matching the style already used
for TASK-017/TASK-024:

```markdown
| TASK-021 | `recipe-validate-tokens` | S | — | [INSTALL-LLD](lld/INSTALL-LLD.md) — **Built**: standalone, re-invokable credential/scope check formalizing Step 1's token validation and Step 5 checklist item 4 ("re-run step 1 probes"). GitHub check is real and scriptable (`gh auth status`/`gh api user`, warn-only, via its own `--check-github` mode); Jira/Atlassian check is agent-mediated (same architectural constraint as `sync-reconcile.sh`/`install.sh`'s own `--record-jira-check`) — the skill's own instructions tell the invoking agent to call `GetMcpTools`/`CallMcpTool getAccessibleAtlassianResources` directly. Reports PASS/WARN/FAIL per credential with soft remediation suggestions only; never fixes anything, never prints token values, never touches `.gsd-recipe/config.json`/`.planning/config.json`. See [bench/report/recipe-validate-tokens-integration-report.md](../../bench/report/recipe-validate-tokens-integration-report.md). |
```

### `docs/netapp-recipe/README.md`

Add a "Built vs spec" row (alongside the existing `recipe-run-phase`/`recipe-plan-phase` rows):

```markdown
| `recipe-validate-tokens` skill (TASK-021) | **Built** — standalone, re-invokable credential/scope check (`.gsd-recipe/scripts/install-recipe-validate-tokens.sh`, standalone installer intended to also be composed into `install.sh` as a 6th sub-installer); real, scriptable GitHub check (`gh auth status`/`gh api user`, warn-only, via its own `--check-github` mode) plus an agent-mediated Jira/Atlassian MCP check (`GetMcpTools`/`CallMcpTool getAccessibleAtlassianResources`, since a bash script has no MCP tool-calling access); reports PASS/WARN/FAIL per credential with soft remediation suggestions only, never fixes anything itself, never prints token values, never touches `.gsd-recipe/config.json`/`.planning/config.json` — see [bench/report/recipe-validate-tokens-integration-report.md](../../bench/report/recipe-validate-tokens-integration-report.md) |
```

Move `recipe-validate-tokens` out of the "Spec (`recipe-*`)" Commands table (it isn't listed there
individually today — it's only implicit in the generic `recipe-install` / p0 row) and add it to the
"Built" Commands table:

```markdown
| `recipe-validate-tokens` (TASK-021) | Standalone GitHub + Jira/Atlassian credential check — [.gsd-recipe/templates/recipe-validate-tokens-SKILL.md](../../.gsd-recipe/templates/recipe-validate-tokens-SKILL.md) · [report](../../bench/report/recipe-validate-tokens-integration-report.md) |
```

## Files

- `.gsd-recipe/templates/recipe-validate-tokens-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-validate-tokens.sh` (new)
- `bench/tests/test-install-recipe-validate-tokens.sh` (new, 37 assertions)
- `bench/report/recipe-validate-tokens-integration-report.md` (new — this file)

**Not edited** (shared-file-avoidance constraint — see snippets above for the intended follow-up):
`.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`.

## Deviations from the task

None. All four required files were created; the manual verification exercised the real `gh` CLI's
genuine auth state (both its real `FAIL` state on this machine's broken symlink and its real `PASS`
state via a symlink to the actual working binary) and made a real, live Atlassian MCP call
(`getAccessibleAtlassianResources`) rather than only tracing it, since this session had genuine,
safe, read-only access to do so. The only interpretive judgment call was scope decision #1 above
(mirror, not `source`, `install.sh`'s `github_check()`) — called out explicitly rather than silently
glossed over, since the task text left open whether reuse should mean sourcing or mirroring.
