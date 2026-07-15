# `recipe-pr-comment` skill (TASK-030)

Built per direct task assignment, closing the posting gap `draft-github-pr-comment.sh` (TASK-006)
deliberately left open — its own header comment says "Does NOT post to GitHub — use `gh pr comment`
after reviewing output." `BACKLOG.md` lists TASK-030 with `Depends: 001, 006` (`sync-ledger.sh`,
`draft-github-pr-comment.sh`).

## Locked design decision: a real script, not an Option-B agent-mediated call

Every other `recipe-*` skill that posts a lifecycle comment (`recipe-settle`, `recipe-run-phase`,
`recipe-plan-phase`, …) invokes `gsd-jira-sync` by name for the actual post, because
`addCommentToJiraIssue` is an MCP tool call — only a live agent turn has MCP tool-calling access.
`gh pr comment`, by contrast, is a real, local CLI binary a plain shell process can invoke directly
— the same category as `install.sh`'s own `gh auth status`/`gh api user` check and `recipe-settle`'s
`--check-ci` probe. So, unlike the Jira side, the **entire** GitHub posting pipeline — draft,
idempotency check, post, ledger — is a single real, standalone, testable script
(`bench/runners/post-github-pr-comment.sh`), and `recipe-pr-comment` (the skill) is a thin wrapper
whose only job is translating its own invocation syntax into that script's flags and reporting the
result verbatim. There is no MCP call anywhere in this skill's own workflow.

## `gh pr comment` semantics verified live before being encoded

Per the task's explicit requirement ("do not assume"), the following was verified live against the
real, working `gh` 2.96.0 keg on this machine (`~/homebrew/Cellar/gh/2.96.0/bin/gh` — this machine's
default `PATH` has a known pre-existing broken `gh` symlink, independently documented in
`bench/report/install-scaffold-integration-report.md` and
`bench/report/recipe-settle-integration-report.md`; a scratch `PATH` with a symlink to the real keg
was built to exercise it for real) **before** any of it was encoded into the runner script:

1. **`gh pr comment --help`** (live call, real output):
   ```
   FLAGS
     -b, --body text        The comment body text
     -F, --body-file file   Read body text from file (use "-" to read from standard input)
     ...
   INHERITED FLAGS
         -R, --repo [HOST/]OWNER/REPO   Select another repository using the [HOST/]OWNER/REPO format
   ```
   Confirms `--body-file`/`-F` and `--repo`/`-R` are the real flag names the runner already used —
   not guessed at.
2. **`gh help exit-codes`** (live call, real output): `0` = success, `1` = failure, `2` = cancelled,
   `4` = auth required. The runner only branches on `0` vs. non-`0` (treats any non-zero as a real,
   reported failure — never tries to special-case `4` differently, since "auth required" is still
   correctly a hard failure for this script's purposes).
3. **Real source inspection of `cli/cli`'s own `pkg/cmd/pr/shared/commentable.go`** (`createComment()`,
   fetched live from `github.com/cli/cli` trunk): confirms `fmt.Fprintln(opts.IO.Out, url)` is the
   **only** thing written to stdout on success — nothing else, no JSON, no extra lines. This is
   exactly what the runner's `EXTERNAL_ID` extraction already assumed (trim newline/whitespace from
   `gh`'s entire stdout capture) — confirmed correct, not just plausible.
4. **Real, read-only failure-path exercise against a real, live, public repo `cli/cli`** — a
   genuinely nonexistent PR number, never a repo this task owns or could accidentally mutate:
   ```
   $ gh pr comment 999999 --repo cli/cli --body "test"
   GraphQL: Could not resolve to a PullRequest with the number of 999999. (repository.pullRequest)
   $ echo $?
   1
   ```
   Confirms the real failure shape (`exit 1`, a real GraphQL error string on stderr) the runner's
   `GH_RC -ne 0` branch already handles — this was a live, unmocked `gh` invocation, not a stub, and
   it never posted anything (the PR number doesn't exist).
5. **Real `git remote get-url origin` resolution against this actual repo** (`vs06101996/GSD_Plan`,
   `https://github.com/vs06101996/GSD_Plan.git`) — confirmed the runner's `resolve_owner_repo()`
   parsing (strip `.git`, strip the `https://github.com/` prefix) correctly yields
   `vs06101996/GSD_Plan` against a real, live remote URL, not a synthetic one.

No real comment was ever posted to any real external GitHub PR during this verification — the
successful-post path was exercised exclusively via fake `gh` stubs on a scratch `PATH` (see
"Validation performed" below), per the task's explicit hard safety constraint.

## Synthetic issue-key convention (a genuine scope decision, not an oversight)

GitHub PRs have no Jira issue key of their own, but `sync-ledger.sh key <event_id> <issue_key>
[--phase N] [--wave W]`'s signature needs an `<issue_key>`-shaped argument to compute a ledger key.
`post-github-pr-comment.sh` resolves this as: use the real `--issue KEY` value if passed (this PR's
phase is also linked to a real Jira issue — matches the Jira side's own convention exactly),
otherwise use a synthetic `pr-<PR_NUMBER>` value. This keeps every GitHub-only PR (no linked tracker
issue) idempotent on its own terms without inventing a fake Jira-shaped key or silently colliding two
unrelated PRs' ledger rows. Documented explicitly in both the runner script's header comment and the
skill's own "Synthetic issue-key convention" section — carried forward here, not re-derived.

The ledger key also deliberately omits a `:commit=` segment (unlike `draft-github-pr-comment.sh`'s
own *displayed* idempotency key inside the rendered comment body, which does include one) — a
milestone comment posts once per `(event, phase, wave)` tuple, not once per commit, matching every
other `recipe-*` skill's own `sync-ledger.sh key <event> <issue> --phase N [--wave W]` call shape.

## Why no stamp emission

`bench/recipe/trackers/github-events.json`'s 4 entries (`execute_wave`, `execute_complete`,
`review_complete`, `phase_complete`) have **no `"stamp"` field at all** — a real, deliberate
structural difference from `jira-events.json`'s entries, which each carry either `"stamp": {...}` or
an explicit `"stamp": null`. There is nothing configured to key a stamp emission off for the GitHub
side, and per `docs/netapp-recipe/lld/TRACEABILITY-LLD.md`'s "GitHub PR events" section, GitHub PR
comments are a **secondary/parallel visibility channel** — when a PR's phase is also linked to a
Jira issue, the Jira side already owns the canonical KPI stamp for that same milestone. So
`post-github-pr-comment.sh` never calls `emit-stamp.sh`, and the skill never invents a step to do so
on its behalf. This decision is carried in-code in the runner's own header comment, not silently
omitted.

## Two-file staging under one capability entry (no single `staged_path`)

`recipe-pr-comment` stages both its skill file (`.cursor/skills/recipe-pr-comment/SKILL.md`) and its
runtime dependency (`bench/runners/post-github-pr-comment.sh`) under a single ledger component
(`"recipe-pr-comment"`), mirroring `recipe-install-verify`'s own precedent for a component with no
single canonical file. The capability catalog entry sets `staged_path: null` for exactly this reason
(same rationale `install-core`'s own entry already documents for "no single canonical file").

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Runner (real script) | `bench/runners/post-github-pr-comment.sh` | Draft (calls `draft-github-pr-comment.sh` directly, never duplicates its templating/git-log logic) → resolve `--repo` (deferred until just before a real post, never blocking `--dry-run`/duplicate-skip) → compute idempotency key (`sync-ledger.sh key`, synthetic `pr-<PR_NUMBER>` issue key when `--issue` is omitted) → check the ledger (`sync-ledger.sh has`) → `--dry-run` (report only, never call `gh`) → real post (`gh pr comment <PR> --repo <owner/repo> --body-file <tmp>`, `mktemp`'d body file + `EXIT` trap cleanup) → on success, append `posted` to the ledger with the real comment URL as `external_id`; on failure, report clearly and never append. Never emits a stamp. |
| Skill content | `.gsd-recipe/templates/recipe-pr-comment-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block: resolves the positional `<pr_number>` into the runner's `--pr` flag and forwards every other flag unchanged, reports the runner's output verbatim, and documents the synthetic issue-key convention, the no-stamp-emission decision, and an ownership table (`draft-github-pr-comment.sh` / `sync-ledger.sh` / `post-github-pr-comment.sh` / this skill) in dedicated sections. |
| Installer | `.gsd-recipe/scripts/install-recipe-pr-comment.sh` | Standalone installer mirroring `install-recipe-install-verify.sh`'s two-file-staging structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard). Stages both files under ledger component `"recipe-pr-comment"`. Never touches `.gsd-recipe/config.json`, `.planning/config.json`, or `.gsd-recipe/sync-ledger.jsonl` — those are the staged skill's own runtime concern whenever it's actually invoked, not the installer's job. |
| Tests (installer) | `bench/tests/test-install-recipe-pr-comment.sh` (26 assertions) | Fail-closed non-git target, fresh install stages both files, exactly 2 ledger rows, never touching config/install-report/sync-ledger files, staged-content assertions covering every documented convention/decision, idempotent re-install, uninstall removes both files + clears the ledger entry + cleans up the empty directory, self-install collision safety, self-uninstall canonical-source preservation. |
| Tests (runner) | `bench/tests/test-post-github-pr-comment.sh` (22 assertions) | Real script logic against fake `gh` stubs on a scratch `PATH` (never the real `gh` CLI, never a real external PR): unknown `event_id` fails closed (propagates `draft-github-pr-comment.sh`'s own error); `--dry-run` never calls `gh`, never touches the ledger, reports the drafted body + idempotency key + not-yet-posted status; an already-posted key reports `duplicate_skipped` and never calls `gh`; a successful stubbed post appends exactly one `posted` row with `target: github` and the real gh-provided comment URL as `external_id`, and `gh pr comment` is invoked with the expected PR number/`--repo`/`--body-file` args; a failing stubbed post never appends a row and surfaces the real error detail; the drafted body is diffed byte-for-byte against a direct call to `draft-github-pr-comment.sh` with the same args, confirming the runner never reimplements the templating logic. |
| Composed into `install.sh` | 15th sub-installer, appended after the existing 14 (`observer`, `tracker-sync`, `recipe-planning-policy`, `recipe-run-phase`, `recipe-plan-phase`, `recipe-validate-tokens`, `recipe-bootstrap-knowledge`, `recipe-install-verify`, `recipe-run-phases`, `recipe-verify-feature`, `recipe-review-ship`, `recipe-settle`, `gsd-jira-sync`, `recipe-sync`) — path var (`RECIPE_PR_COMMENT_INSTALLER`), `install()`/`uninstall()`/`verify()` wiring, consent-prompt string, header comment. | |
| Capability catalog | `bench/lib/capability-schema.sh` — 17th `CATALOG` entry (`id: "recipe-pr-comment"`, `task_id: "TASK-030"`, `kind: "cursor-skill"`, `staged_path: None`, `ledger_component: "recipe-pr-comment"`). | |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-030 row near TASK-029's, `Depends: 001, 006`) and `docs/netapp-recipe/README.md` (Built-vs-spec row, Commands→Built row; `recipe-pr-comment` removed from the Built-vs-spec parenthetical and from the Commands→Spec table since it's no longer spec-only; shipped-percentage header recomputed ~90%→~94%). | |

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Any stamp-emission step for GitHub events | Locked decision — see "Why no stamp emission" above. `github-events.json` has no `"stamp"` field to key one off. |
| Posting a real comment to any real external GitHub PR during verification | Hard safety constraint — verified exclusively via fake `gh` stubs on a scratch `PATH` plus genuinely read-only real `gh` calls (`--help`, `gh help exit-codes`, a real nonexistent-PR failure against `cli/cli`, real `git remote` resolution). |
| Modifying `draft-github-pr-comment.sh`, `sync-ledger.sh`, `sync-reconcile.sh`, `sync-drain-queue.sh`, or any already-built `recipe-*`/`gsd-jira-sync`/`tracker-sync` skill's own files | Explicit task constraint — called, never duplicated or edited. No bug was found in any of them during this integration, so no fix was needed. |
| A ledger-key `:commit=` segment | Deliberately omitted — see "Synthetic issue-key convention" above; a milestone comment posts once per `(event, phase, wave)`, not once per commit. |
| Special-casing `gh`'s exit code `4` (auth required) differently from other failures | The runner treats any non-zero exit as a real, reported failure uniformly — `4` still correctly blocks a ledger append, no extra branching needed. |

## Validation performed

### Automated

`bench/tests/test-install-recipe-pr-comment.sh`: **26 assertions, 0 failed**, run standalone.
`bench/tests/test-post-github-pr-comment.sh`: **22 assertions, 0 failed**, run standalone.

Full `bench/tests/*.sh` suite (29 files, run after this task's composition edits landed):
**all 29 files exit 0, 768 assertions total, 0 failed, zero regressions.**

```
$ ./bench/tests/test-install-recipe-pr-comment.sh
...
26 passed, 0 failed

$ ./bench/tests/test-post-github-pr-comment.sh
...
22 passed, 0 failed
```

Per-file summary of the full suite (29 files):

| File | Assertions |
|---|---|
| test-capability-schema.sh | 30 |
| test-create-phase-tasks.sh | 29 |
| test-draft-github-pr-comment.sh | 13 |
| test-fotw-observer-nudge.sh | 10 |
| test-install-gsd-jira-sync.sh | 31 |
| test-install-observer.sh | 17 |
| test-install-recipe-bootstrap-knowledge.sh | 27 |
| test-install-recipe-install-verify.sh | 40 |
| test-install-recipe-plan-phase.sh | 28 |
| test-install-recipe-planning-policy.sh | 16 |
| test-install-recipe-pr-comment.sh | 26 |
| test-install-recipe-prd-intake.sh | 17 |
| test-install-recipe-review-ship.sh | 30 |
| test-install-recipe-run-phase.sh | 28 |
| test-install-recipe-run-phases.sh | 26 |
| test-install-recipe-settle.sh | 47 |
| test-install-recipe-sync.sh | 30 |
| test-install-recipe-validate-tokens.sh | 37 |
| test-install-recipe-verify-feature.sh | 31 |
| test-install-tracker-sync.sh | 16 |
| test-install.sh | 120 |
| test-observer-lib.sh | 12 |
| test-observer-tick-loop.sh | 6 |
| test-parse-state.sh | 27 |
| test-post-github-pr-comment.sh | 22 |
| test-sync-drain-queue.sh | 18 |
| test-sync-ledger.sh | 10 |
| test-sync-reconcile.sh | 14 |
| test-tracker-sync-config.sh | 10 |
| **Total** | **768** |

### Manual (real-environment)

All against this machine's real, working `gh` 2.96.0 keg (via a scratch `PATH` symlink, since the
default `PATH`'s `gh` is a known pre-existing broken symlink) — see the numbered live checks in
"`gh pr comment` semantics verified live" above (1-5). None of these mutated any real external
GitHub resource: `--help`/`help exit-codes` are pure documentation calls, the `cli/cli` PR-999999
call targets a PR number that doesn't exist (a real, live, unmocked failure — not a stub), the
`commentable.go` source read is a read-only fetch from `github.com/cli/cli`, and the remote-URL
resolution check reads this repo's own already-configured `origin` remote.

The successful-post, duplicate-skip, dry-run, and failure paths of the runner's own pipeline were
all exercised via real script execution against fake `gh` stubs on a scratch `PATH` (never the real
`gh` CLI for the actual posting), per the task's hard safety constraint — see the automated test
results above for the full coverage.

### Self-install into the real repo

```bash
$ ./.gsd-recipe/scripts/install-recipe-pr-comment.sh --yes --target /Users/vs72964/Projects/gsd-benchmark
recipe-pr-comment installer: staged. Files tracked in .../.gsd-recipe/ledger.json:
  - .cursor/skills/recipe-pr-comment/SKILL.md
  - bench/runners/post-github-pr-comment.sh
...

$ ./bench/lib/capability-schema.sh generate-capability --target /Users/vs72964/Projects/gsd-benchmark
generate-capability: wrote .../.gsd-recipe/capability.json (17 capabilities, 14 staged)

$ ./bench/lib/capability-schema.sh validate-capability \
    --capability .gsd-recipe/capability.json --schema .gsd-recipe/capability.schema.json
OK
```

`recipe-pr-comment`'s own catalog entry reports `"staged_path": null`, `"staged": true`,
`"ledger_tracked": true` — matching the two-file, no-single-canonical-path shape by design.

`git status --porcelain` confirms the self-install's only new paths are
`.cursor/skills/recipe-pr-comment/SKILL.md` (newly staged copy) plus the already-untracked
`.gsd-recipe/ledger.json`/`.gsd-recipe/capability.json` (additive, pre-existing untracked files this
session already produced) — the runner file itself (`bench/runners/post-github-pr-comment.sh`) was
already the canonical source at that exact path, so `safe_copy`'s src==dest guard correctly skipped
re-copying it (still ledger-recorded). No pre-existing tracked file (`.gitignore`,
`bench/recipe/README.md` — both already modified before this task started, per this session's
initial `git status` snapshot) was touched by this task.

## Files

- `bench/runners/post-github-pr-comment.sh` (new)
- `.gsd-recipe/templates/recipe-pr-comment-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-pr-comment.sh` (new)
- `bench/tests/test-install-recipe-pr-comment.sh` (new, 26 assertions)
- `bench/tests/test-post-github-pr-comment.sh` (new, 22 assertions)
- `bench/report/recipe-pr-comment-integration-report.md` (new — this file)
- `.cursor/skills/recipe-pr-comment/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` / `.gsd-recipe/capability.json` (self-install side effects, real repo — additive only)

**Modified (composed directly — no concurrent siblings running this session):**
`.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`.

**Not touched:** `bench/lib/sync-ledger.sh`, `bench/runners/draft-github-pr-comment.sh`,
`bench/recipe/trackers/github-events.json`, or any already-built `recipe-*`/`gsd-jira-sync`/
`tracker-sync` skill's own files — called/read only, never edited. No bug was found in any of them
during this integration.

## Deviations from the task

None in scope or design. Two judgment calls worth flagging explicitly (both locked decisions
documented in-line in the code/skill, not hidden):

1. **Synthetic `pr-<PR_NUMBER>` issue-key convention** for the ledger key when no `--issue` is
   passed — a genuine scope decision the task explicitly called out as one, not an oversight. See
   "Synthetic issue-key convention" above.
2. **Two files staged under one capability entry with `staged_path: null`** — mirrors
   `recipe-install-verify`'s own precedent exactly (a component that installs more than one file has
   no single canonical path to report), rather than inventing a new capability-schema shape for this
   task.
