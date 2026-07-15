# `recipe-settle` skill (TASK-027)

Built per direct task assignment, formalizing `docs/netapp-recipe/lld/TRACEABILITY-LLD.md`'s
locked rule 4 ("**Settled** = PO + CI green"), `docs/netapp-recipe/lld/RUNTIME-LLD.md` § 4.c Ship's
human gate ("**PO accept + CI green** before `settled`"), and
`docs/netapp-recipe/lld/FAILURE-MATRIX.md`'s "CI red at settle gate" row ("blocks `recipe-settle`
... No `settled` event should be posted") into its own standalone, invoke-by-name Cursor skill.
`BACKLOG.md` lists TASK-027 with `Depends: —`, matching the standalone-installer precedent already
used by `recipe-validate-tokens` (TASK-021), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) — built ahead of/alongside the full `install.sh` (TASK-010).

**This task ran in parallel with three sibling tasks** (TASK-018, TASK-025, TASK-026) editing the
same repo concurrently. Per the explicit shared-file-avoidance constraint, **none** of
`.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`,
or `docs/netapp-recipe/README.md` were edited by this task — copy-paste-ready snippets for all four
are provided at the end of this report for a follow-up integration pass to apply. Nor were any of
`recipe-validate-tokens`'s own files touched (read-only reference only, per the task's explicit
constraint).

## Locked design decisions (operator-approved this session — implemented exactly, not re-derived)

These four decisions were confirmed with the operator before this task began building anything,
and are carried verbatim into the skill's own documentation (its "Why this is a genuine human gate,
not skippable" and "Why Option B" sections) rather than re-derived here:

1. `recipe-settle N` runs a real, scriptable, testable `gh`-based CI check — a net-new
   `--check-ci <owner/repo> <ref>` mode on the installer, mirroring `recipe-validate-tokens`'s own
   `--check-github` precedent — plus an explicit interactive PO-accept y/n confirmation prompt
   before ever syncing the `settled` event.
2. If CI is not green: block clearly and do **not** call `gsd-jira-sync` at all — no `settled`
   event is posted, matching `FAILURE-MATRIX.md`'s row exactly.
3. The PO-accept prompt is a genuine human gate — never auto-confirmed, never skippable via a flag
   (deliberately stricter than `install.sh`'s own `--yes` convention).
4. Any project-specific/benchmark grader hook is explicitly out of scope for v1 (parked, same
   precedent as the DAG work) — this skill relies solely on the real `gh`-based CI check plus the
   human PO gate.

## Scope decisions made while implementing

1. **`N` is required but informational-only for tracker routing.** `settled` is an **epic-routed**
   event per `docs/netapp-recipe/contracts/DATA-CONTRACTS.md` rule 7
   (`EPIC_ROUTED_EVENTS = {intake_started, discuss_complete, settled}` in `bench/lib/parse-state.sh`
   — confirmed by reading that script directly). `parse-state.sh resolve-issue settled` takes no
   `--phase` argument at all. So `N` (the phase number in the `recipe-settle N` invocation, mirroring
   every other `recipe-*` skill's own `N` argument) is used only to enrich the human-facing summary
   and Jira comment with "which phase's shipped work is being accepted right now" — never to
   resolve the tracker issue key.
2. **CI check is scriptable; the PO-accept gate is not — and deliberately not implemented as a
   `read -p` bash prompt either.** `gh` is a real local CLI a plain shell process can invoke
   directly, so `--check-ci` mirrors `--check-github`'s shape exactly. A genuine "did a human
   actually accept this" question has no local scriptable oracle: a bash process spawned by a tool
   call has no real human typing at its stdin, so a `read -p` there would only ever be answered by
   the invoking agent itself, silently defeating the entire point of a human gate. The skill's own
   instructions therefore route this question through the live conversation between the operator
   and the agent — the one channel where a real human is provably present — and explicitly disclaim
   the `read -p` approach in its own § D ("Do NOT"). This is the same "only a live agent turn can
   reach the real actor" principle `recipe-validate-tokens`'s SKILL.md already documents for its
   Jira/Atlassian MCP check, applied to a different kind of check.
3. **`--owner-repo`/`--ref` are resolvable defaults, not required arguments.** The skill's own step
   1 resolves `owner/repo` from `git remote get-url origin` and `ref` from the current branch's open
   PR (`gh pr view --json number -q .number`) or the current branch name itself, so
   `recipe-settle N` works standalone with no prior recipe step. Explicit overrides
   (`--owner-repo`, `--ref`) are supported for when the operator wants to settle against a specific
   PR/ref that isn't the current branch's.
4. **`gh pr checks` exit-code semantics are load-bearing and were verified against the real `gh`
   CLI before being encoded**, not assumed: `gh help exit-codes` plus a live `gh pr checks --help`
   call confirmed `0` = all checks passed, `8` = checks pending, `1`/other = failing or "no pull
   request found for this ref." `check_ci()` branches on exactly those codes, falling back to
   `gh api repos/<owner>/<repo>/commits/<ref>/check-runs` (parsed for `status`/`conclusion`) when
   `gh pr checks` can't resolve a PR for the given ref at all (e.g. settling directly against a
   branch/SHA with no open PR) — this fallback was exercised for real against this machine's actual
   `gh` session (see "Validation performed" below), not just assumed to work.
5. **A hard-to-anticipate bash 3.2 heredoc-in-pipe quirk was found and fixed during implementation,
   not left latent.** The first draft of the JSON-rendering helpers used an inline
   `python3 -c "$(cat <<'PY' ... )"` pattern to keep stdin free for piped JSON data. That pattern
   silently corrupted its own script text when the enclosing shell function was itself the
   receiving end of a pipe (`printf ... | render_checks_json ""`) — reproduced and confirmed via
   `bash -x` tracing, and root-caused to macOS's still-shipped ancient bash 3.2 (`GNU bash, version
   3.2.57(1)-release`), not a logic bug in the python itself. Fixed by writing the python helpers to
   real `mktemp`'d files (cleaned up via an `EXIT` trap) instead of inline heredocs, then re-verified
   against real `gh` output to confirm the fix. See the script's own comment above
   `write_check_ci_helpers()` for the in-code explanation, so a future editor doesn't reintroduce
   the pattern.
6. **`--check-ci` needs no `--target`/git-repo check**, same rationale
   `recipe-validate-tokens`'s own report documents for `--check-github`: it's a pure, read-only
   introspection of a specific `owner/repo`/`ref`, completely unrelated to any local scaffolding —
   requiring a git repo for it would be an arbitrary, unhelpful restriction.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-settle-SKILL.md` | Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-validate-tokens-SKILL.md`'s/`recipe-run-phase-SKILL.md`'s format). Instructs the invoking agent to (1) resolve `owner/repo`/`ref` via `git`/`gh pr view` if not passed explicitly, (2) run the real `--check-ci` script and treat anything but `CI: PASS` as a hard block (no PO prompt, no Jira sync, ever), (3) ask the operator an explicit, non-fabricated, non-skippable y/n PO-accept question in the live conversation, and only then (4) resolve the epic-routed issue key and sync `settled` via the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open on a missing tracker epic). Includes dedicated "Why this is a genuine human gate, not skippable" and "Why Option B" sections per the task's explicit ask. |
| Installer | `.gsd-recipe/scripts/install-recipe-settle.sh` | Standalone installer mirroring `install-recipe-validate-tokens.sh`'s structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard) staging to `.cursor/skills/recipe-settle/SKILL.md`. Component name `"recipe-settle"`. Also ships a net-new `--check-ci <owner/repo> <ref>` mode: the real, standalone, testable CI-status probe (`gh pr checks`, falling back to `gh api .../check-runs` when no PR is found for the ref). Never touches `.gsd-recipe/config.json` or `.planning/config.json`. Does **not** implement the PO-accept gate itself (see scope decision #2 above) — that stays entirely a skill-instruction concern. |
| Tests | `bench/tests/test-install-recipe-settle.sh` (47 assertions) | Installer behavior (fresh install, idempotency, uninstall, self-install, fail-closed, staged-content assertions for every documented gate/behavior/decision) plus `--check-ci` exercised against fake `gh` stubs covering: all checks green (PASS), some checks genuinely failing (FAIL), some checks still pending via `gh pr checks`'s real exit-code-8 semantics (FAIL, never PASS), `gh` completely absent (FAIL, with remediation), the no-PR-found fallback to the check-runs API both succeeding (PASS) and failing (WARN), and an explicit no-token-leak assertion. Deliberately excludes `install.sh` composition assertions (that file isn't edited by this task). |
| Self-install | `.cursor/skills/recipe-settle/SKILL.md` | Not committed as a lasting side effect — this task's manual verification used its own disposable `/tmp/task027-manual-01` scratch repo (installed, exercised against real `gh`, then fully uninstalled and removed) rather than self-installing into the real `gsd-benchmark` repo. |

### Why `--check-ci` needs no `--target`/git-repo check

Same rationale `recipe-validate-tokens`'s own report documents for `--check-github`: every other
mode in this installer (`install`, `--uninstall`) writes files into a target repo and so fail-closes
on a non-git `--target`. `--check-ci` writes nothing anywhere — it's a pure, read-only probe of a
specific `<owner/repo>`/`<ref>` pair passed explicitly on the command line, completely unrelated to
any local repo. An operator should be able to run `recipe-settle --check-ci some-org/some-repo 42`
from anywhere, so this mode is dispatched before the `--target`/git-repo resolution block runs.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Editing `install.sh` to wire in a ninth sub-installer | Shared-file-avoidance constraint — three sibling tasks (TASK-018, TASK-025, TASK-026) are editing `install.sh` concurrently. Copy-paste-ready snippet provided below. |
| Editing `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md` | Same constraint. Copy-paste-ready snippets provided below. |
| Editing `recipe-validate-tokens`'s own skill/installer/test files | Explicit task constraint — read-only reference only. |
| A project-specific/benchmark grader hook | Explicitly parked for v1 per the locked design decisions — same precedent as the DAG work (`TASK-009`, parked per `DECISIONS.md`). This skill's quality floor is exactly "real `gh`-based CI check + human PO accept," nothing project-specific. |
| Any flag, environment variable, or non-interactive mode that skips or auto-answers the PO-accept prompt | Deliberately, per locked decision #3 — see the skill's own "Why this is a genuine human gate, not skippable" section. |
| Creating, pushing, or opening a PR | Out of scope for this skill — it assumes a PR/branch already exists (from `recipe-review-ship`, TASK-026, or an equivalent manual `gsd-ship` step) and only ever checks CI status + gates human acceptance on top of what already exists. |
| Composing `--check-ci` into `install.sh`'s own GitHub-check function, or into `recipe-validate-tokens`'s `--check-github` | Different checks entirely (auth/scope probe vs. CI status probe) — no shared implementation to extract; kept as two separate, independently testable probes. |

## Validation performed

### Automated

`bench/tests/test-install-recipe-settle.sh` total: **47 assertions, 0 failed**, run standalone
(not as part of the full `bench/tests/` suite, per this task's explicit instruction):

```
$ ./bench/tests/test-install-recipe-settle.sh
...
47 passed, 0 failed
```

| # | Check | Result |
|---|---|---|
| 1 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 2 | Fresh install stages `.cursor/skills/recipe-settle/SKILL.md` | PASS |
| 3 | Fresh install records exactly 1 ledger row | PASS |
| 4-5 | Install never creates `.gsd-recipe/config.json` / `.planning/config.json` | PASS |
| 6-23 | Staged content documents: real `gh pr checks` probe, `--check-ci` invocation, `check-runs` fallback, `CI: PASS`/`CI: FAIL` summary format, the PO-accept gate + explicit y/n question, the "no skip flag" disclaimer, the "genuine human gate" section, `FAILURE-MATRIX.md`'s "no settled event" quote, never calling `gsd-jira-sync` when CI isn't green, the `gsd-jira-sync` skill-to-skill invocation + "Why Option B" section, `sync-ledger.sh` idempotency, `resolve-issue settled` (epic-routed), fail-open on a missing tracker epic, never fabricating a CI result, the parked grader hook, and the explicit `read -p`-implementation disclaimer (18 separate `grep` assertions) | PASS (all 18) |
| 24 | Re-running install does not duplicate ledger rows | PASS |
| 25-27 | Uninstall removes the staged skill, clears the ledger entry, cleans up the now-empty skill directory | PASS |
| 28-30 | Self-install into a copy of this repo does not error; self-install uninstall does not error; self-uninstall preserves the canonical skill template source | PASS |
| 31-33 | `--check-ci` with `gh` completely absent: exits 0, reports `FAIL`, suggests `gh auth login` | PASS |
| 34-37 | `--check-ci` all checks green: exits 0, reports `PASS`, surfaces each check's real name, **never leaks a fake `GH_TOKEN` value** into stdout | PASS (all 4) |
| 38-39 | `--check-ci` some checks genuinely failing: exits 0, reports `FAIL` | PASS |
| 40-42 | `--check-ci` some checks still pending (`gh pr checks` real exit code `8`): exits 0, reports `FAIL` (never `PASS`), mentions "pending" | PASS |
| 43-44 | `--check-ci` no PR found for ref, check-runs API fallback succeeds and is green: exits 0, reports `PASS` via the fallback | PASS |
| 45-46 | `--check-ci` no PR found for ref, check-runs API fallback also fails: exits 0, reports `WARN` (never `PASS`) | PASS |

### Manual (real-environment)

Ran against a fresh scratch repo at `/tmp/task027-manual-01`, created and torn down entirely within
this task — never the real `gsd-benchmark` repo's own tree.

1. **Real install.** `git init` the scratch repo, then the real
   `.gsd-recipe/scripts/install-recipe-settle.sh --yes --target /tmp/task027-manual-01` — a genuine
   execution, not simulated. Staged a real `.cursor/skills/recipe-settle/SKILL.md` (19,070 bytes)
   and recorded exactly 1 ledger row. Confirmed `.gsd-recipe/` contains only `ledger.json` (no
   `config.json`).
2. **Real `--check-ci` — genuine `gh pr checks` PASS, against a real public merged PR.** This
   machine's `gh` on `PATH` is broken (same pre-existing symlink issue independently documented in
   `bench/report/install-scaffold-integration-report.md` and
   `bench/report/recipe-validate-tokens-integration-report.md`: `~/homebrew/bin/gh` points at a
   `2.92.0` keg that no longer exists, while the real installed keg is `2.96.0`). A scratch `PATH`
   was built with a symlink pointing directly at the real, working keg
   (`~/homebrew/Cellar/gh/2.96.0/bin/gh`), and `--check-ci cli/cli 13864` was run from within the
   scratch repo — a **real, live `gh pr checks` call against a real, public, merged GitHub pull
   request** (`cli/cli` PR #13864, resolved live via `gh pr list --state merged`, not invented).
   Result:
   ```
   CI: PASS (all checks green for cli/cli @ 13864)
     pass: CodeQL
     pass: integration-tests (windows-latest)
     pass: build (windows-latest)
     pass: CodeQL-Build (go)
     pass: lint
     pass: build (ubuntu-latest)
     pass: CodeQL-Build (actions)
     pass: build (macos-latest)
     pass: govulncheck
     pass: integration-tests (ubuntu-latest)
     pass: integration-tests (macos-latest)
   ```
3. **Real `--check-ci` — genuine check-runs API fallback, against a real live commit, with a real
   non-green result.** Ran `--check-ci cli/cli <sha>` against `cli/cli`'s real, live `trunk` branch
   HEAD commit SHA (resolved live via `gh api repos/cli/cli/commits/trunk --jq .sha`, not invented).
   Since that commit has no associated open PR, this exercised the real check-runs API fallback path
   (`check_ci_via_api()`), not the primary `gh pr checks` path. Result — a genuinely non-green,
   real-world outcome, not manufactured for the test:
   ```
   CI: FAIL (2 of 30 check run(s) still pending)
     pending: Dependabot
     pending: Dependabot
   ```
   This is a materially stronger verification than a fake-stub `FAIL`/pending case: it demonstrates
   the fallback path, the JSON parsing, and the "pending is never treated as green" rule all working
   correctly against real, live GitHub API data with a genuine non-PASS outcome, on the very first
   real ref tried.
4. **Real `--check-ci` — `gh` absent.** Confirmed separately (same broken-symlink finding as #2
   above, and as already independently documented for `install.sh`'s own GitHub check and
   `recipe-validate-tokens`'s `--check-github`): with this machine's actual, unmodified `PATH`,
   `command -v gh` genuinely fails, so `CI: FAIL (gh CLI not found on PATH)` is the correct, real
   answer — not a fabricated test artifact.
5. **Real uninstall.** Ran `--uninstall --target /tmp/task027-manual-01` — removed the staged skill
   file and cleared the ledger back to `{}`. The entire scratch repo was then `rm -rf`'d; nothing was
   left under `/tmp`.

**What was truly exercised vs. traced:**

- **Truly executed, real, no mocks:** the installer itself (real install + real uninstall against a
  real scratch git repo); the real `gh pr checks`/`gh api .../check-runs` CI check against a real
  public GitHub repository, in both its genuine `PASS` state (a real merged PR, all checks green)
  and a genuine non-green state (a real live commit with real pending Dependabot check runs,
  reached via the real check-runs API fallback) — not fake `gh` stubs for either of those two real
  cases; the real `gh`-absent `FAIL` state on this machine's actual broken symlink.
- **Traced/reasoned about, not separately re-executed in the manual pass:** the genuinely-failing
  (non-pending) `gh pr checks` branch and the no-PR/API-also-fails `WARN` branch — no real public PR
  with outright failing checks was found within a reasonable search window (several recent `cli/cli`
  PRs were checked and were all green), and manufacturing a real failing CI run for this verification
  was out of scope/unsafe. Both are already covered by real script executions against faithful fake
  `gh` stubs in the automated test suite (assertions 38-39 and 45-46 above), whose exit-code
  semantics (`0`/`1`/`4`/`8`) were themselves verified against `gh help exit-codes` and a live
  `gh pr checks --help` call before being encoded into `check_ci()` — not guessed at. The PO-accept
  conversational gate itself (step 4 of the skill's own workflow) was traced through its own written
  instructions rather than re-executed, since it is not a shell-scriptable action to begin with (see
  scope decision #2) — the skill's own "Why this is a genuine human gate, not skippable" section
  documents exactly how and why an invoking agent must ask this for real, in-conversation, every
  time. Native `gsd-ship`/`gsd-jira-sync`/MCP calls were likewise never actually invoked during this
  verification, per the task's explicit constraint — traced through their own documented workflows
  instead, same as prior reports.

## Real repo git status (confirms only intended new files)

```
$ git -C /Users/vs72964/Projects/gsd-benchmark status --porcelain --untracked-files=all -- .gsd-recipe/ bench/tests/ bench/report/
```

shows exactly (among the many pre-existing/sibling-task untracked files already present before this
task started, per the conversation's initial `git_status` snapshot and the three sibling tasks
running concurrently):

- `.gsd-recipe/scripts/install-recipe-settle.sh` (new, this task)
- `.gsd-recipe/templates/recipe-settle-SKILL.md` (new, this task)
- `bench/tests/test-install-recipe-settle.sh` (new, this task)
- `bench/report/recipe-settle-integration-report.md` (new, this task — this file)

None of `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
`docs/netapp-recipe/BACKLOG.md`, or `docs/netapp-recipe/README.md` show as modified (`M`) by this
task — they remain exactly as this task found them. Nor were any of `recipe-validate-tokens`'s own
files touched.

## Copy-paste-ready snippets for a follow-up integration pass

Not applied by this task (shared-file-avoidance constraint). A follow-up pass should apply these
once the sibling tasks editing the same files have landed.

### `.gsd-recipe/scripts/install.sh`

Add the path variable alongside the existing eight (near `RECIPE_INSTALL_VERIFY_INSTALLER`):

```bash
RECIPE_SETTLE_INSTALLER="$SCRIPT_DIR/install-recipe-settle.sh"
```

In `install()`, alongside the existing eight `--yes --target "$TARGET"` calls:

```bash
"$RECIPE_SETTLE_INSTALLER" --yes --target "$TARGET"
```

(Also update the operator-facing consent prompt string and the "composing sub-installers..." echo
line to name `recipe-settle` as the ninth sub-installer, matching how each prior addition updated
those strings.)

In `uninstall()`, alongside the existing eight `--uninstall --target "$TARGET"` cascades:

```bash
"$RECIPE_SETTLE_INSTALLER" --uninstall --target "$TARGET"
```

In `verify()`, alongside the existing eight `ledger_has_component` checks:

```bash
if ledger_has_component "recipe-settle"; then
  echo "    recipe-settle composed — pass"
else
  echo "    recipe-settle composed — FAIL (recipe-settle ledger component absent)"
  ok=0
fi
```

### `bench/tests/test-install.sh`

Composition assertions, matching the exact shape of the existing installer-declaration checks:

```bash
grep -q "RECIPE_SETTLE_INSTALLER" "$INSTALLER" && rc=0 || rc=$?
check "install.sh declares RECIPE_SETTLE_INSTALLER" "$rc"
grep -q 'RECIPE_SETTLE_INSTALLER" --yes' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's install() invokes RECIPE_SETTLE_INSTALLER --yes" "$rc"
grep -q 'RECIPE_SETTLE_INSTALLER" --uninstall' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's uninstall() cascades to RECIPE_SETTLE_INSTALLER --uninstall" "$rc"
grep -q 'ledger_has_component "recipe-settle"' "$INSTALLER" && rc=0 || rc=$?
check "install.sh's verify() checks the recipe-settle ledger component" "$rc"
```

(Where `$INSTALLER` is that test file's existing variable pointing at `install.sh`. If that file
already has a ledger-cross-tracking-disjointness assertion enumerating each sub-installer's
component name, extend that list to include `"recipe-settle"` too, rather than adding a new
standalone assertion for it.)

### `docs/netapp-recipe/BACKLOG.md`

Replace the TASK-027 row (currently `| TASK-027 | recipe-settle | S | — |
[TRACEABILITY-LLD](lld/TRACEABILITY-LLD.md) |`) with a narrated-scope note, matching the style
already used for TASK-017/TASK-021/TASK-024:

```markdown
| TASK-027 | `recipe-settle` | S | — | [TRACEABILITY-LLD](lld/TRACEABILITY-LLD.md) — **Built**: quality-floor settle gate formalizing "Settled = PO + CI green" (also `RUNTIME-LLD.md` § 4.c, `FAILURE-MATRIX.md`'s "CI red at settle gate" row). Real, scriptable, testable CI check via its own `--check-ci <owner/repo> <ref>` mode (`gh pr checks`, falling back to `gh api .../check-runs`) — never fabricated. If CI isn't green: hard block, `gsd-jira-sync` is never called, no `settled` event is posted. Only when CI is green AND an explicit, non-skippable, interactive PO-accept y/n question (asked live in the operator's conversation — never a bash `read -p`, never a flag, never auto-answered) is affirmed does it sync `settled` (epic-routed, idempotent via `sync-ledger.sh`, fail-open on a missing tracker epic). Project-specific/benchmark grader hook explicitly parked for v1. See [bench/report/recipe-settle-integration-report.md](../../bench/report/recipe-settle-integration-report.md). |
```

### `docs/netapp-recipe/README.md`

Add a "Built vs spec" row (alongside the existing `recipe-validate-tokens`/`recipe-run-phase` rows):

```markdown
| `recipe-settle` skill (TASK-027) | **Built** — quality-floor settle gate (`.gsd-recipe/scripts/install-recipe-settle.sh`, standalone installer intended to also be composed into `install.sh` as a 9th sub-installer); real, scriptable CI check (`gh pr checks`/`gh api .../check-runs`, via its own `--check-ci` mode) plus an explicit, non-skippable, interactive PO-accept gate asked live in the operator's conversation (never a script prompt); syncs `settled` via `gsd-jira-sync` only when both gates pass, never otherwise — see [bench/report/recipe-settle-integration-report.md](../../bench/report/recipe-settle-integration-report.md) |
```

Add to the "Built" Commands table:

```markdown
| `recipe-settle` (TASK-027) | Quality-floor settle gate: real `gh`-based CI check + non-skippable human PO-accept gate — [.gsd-recipe/templates/recipe-settle-SKILL.md](../../.gsd-recipe/templates/recipe-settle-SKILL.md) · [report](../../bench/report/recipe-settle-integration-report.md) |
```

## Files

- `.gsd-recipe/templates/recipe-settle-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-settle.sh` (new)
- `bench/tests/test-install-recipe-settle.sh` (new, 47 assertions)
- `bench/report/recipe-settle-integration-report.md` (new — this file)

**Not edited** (shared-file-avoidance constraint — see snippets above for the intended follow-up):
`.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`. **Also not edited** (explicit read-only-reference constraint):
any of `recipe-validate-tokens`'s own files.

## Deviations from the task

None in scope or design — all four required files were created per the locked decisions. Two
implementation-level findings worth flagging explicitly (both already folded into "Scope decisions
made while implementing" above, not hidden):

1. A macOS bash-3.2 heredoc-in-pipe corruption bug was discovered while first implementing the JSON
   detail-rendering helpers, root-caused, and fixed (mktemp'd files + `EXIT` trap instead of inline
   `python3 -c "$(cat <<'PY' ...)"`) — re-verified against real `gh` output afterward to confirm the
   fix actually resolved it, not just silenced the symptom.
2. The manual verification's non-green CI result (assertion-equivalent #3 above) turned out to be a
   **real, live, genuinely-pending** GitHub check state (`cli/cli`'s real `trunk` HEAD, live
   Dependabot check runs still pending at verification time) rather than a fabricated example —
   flagged here so it's clear this wasn't cherry-picked or staged, it's what the real API returned
   on the first ref tried.
