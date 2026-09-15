---
name: recipe-settle
description: "Recipe: quality-floor settle gate. After CI green and explicit PO acceptance, marks phase N's Jira task Done; gsd-jira-sync then closes the Epic only when every phase task recorded in STATE is Done."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-settle`) with:
- `N` — the phase number whose shipped work is being settled (required). `settled` is
  **phase-routed**: it marks that phase task Done. `gsd-jira-sync` performs a status-only roll-up
  and marks the Epic Done only when all phase tasks in STATE are Done.
- `--owner-repo OWNER/REPO` — optional. The GitHub `owner/repo` to check CI against. Default:
  parsed from `git remote get-url origin` (Shell) in step 1 below.
- `--ref REF` — optional. A PR number, branch name, or commit SHA to check CI against. Default:
  the open PR for the current branch if one exists (`gh pr view --json number -q .number`), else
  the current branch name itself (`git rev-parse --abbrev-ref HEAD`).
- `--transition "Name"` — optional override forwarded to
  `gsd-jira-sync settled <issue_key> --transition "Name"`. Default catalog status for `settled`
  is **Done**.

Examples:
- `recipe-settle 5`
- `recipe-settle 5 --owner-repo my-org/my-repo --ref 42`
- `recipe-settle 5 --transition "Done"`

## B. Prerequisites

- A shipped PR or pushable branch for the work being settled — `recipe-review-ship` (TASK-026)
  or an equivalent manual `gsd-ship` step should already have run. This skill does not create or
  push anything; it only checks CI status on what already exists.
- `gh` CLI installed and authenticated, for the real CI check in step 2 (a missing/unauthenticated
  `gh` degrades to `CI: FAIL`, per decision #2 below — it does **not** silently skip the gate).
- `.planning/STATE.md` may or may not map phase `N` to a Jira task. If it doesn't, this skill
  still runs the CI check and PO-accept gate, but skips Jira sync (fail-open on tracker linkage,
  warn-and-continue) — see step 5.

## C. Tool Usage

1. **Resolve `<owner/repo>` and `<ref>`** (only if not passed explicitly via `--owner-repo`/
   `--ref`). `Shell`:
   - `git remote get-url origin` → parse the typical GitHub SSH (`git@github.com:owner/repo.git`)
     or HTTPS (`https://github.com/owner/repo.git` / `https://github.com/owner/repo`) forms into
     `owner/repo`. If this fails or doesn't look like a GitHub remote, stop and tell the operator
     to pass `--owner-repo` explicitly — never guess.
   - `gh pr view --json number -q .number` (from the current branch) → if it prints a number, use
     that as `ref`. If it errors (no open PR for the current branch), fall back to
     `git rev-parse --abbrev-ref HEAD` for `ref`.

2. **Run the real, scriptable CI check (do not reimplement it inline).** `install-recipe-settle.sh`
   is not duplicated into every target by design — resolve its real path through
   `.gsd-recipe/scripts/recipe-paths.sh` (same mechanism `recipe-validate-tokens` uses, see its own
   SKILL.md § C step 1 for the full resolution-order rationale) rather than assuming the naive
   relative path is staged locally. `Shell`:
   ```
   RESOLVED="$(.gsd-recipe/scripts/recipe-paths.sh resolve .gsd-recipe/scripts/install-recipe-settle.sh)"
   "$RESOLVED" --check-ci <owner/repo> <ref>
   ```
   This mirrors `recipe-validate-tokens`'s own `--check-github` precedent — a real `gh pr checks`/
   `gh api .../check-runs` probe, never fabricated, reported as exactly one of `CI: PASS` /
   `CI: FAIL` / `CI: WARN`. Read its output verbatim into your summary in step 6. Never re-derive
   the check yourself from a raw `gh` call inline — always go through the script so there is exactly
   one implementation of the check logic. If `recipe-paths.sh` itself fails to resolve (stderr will
   say why), tell the operator plainly and stop — do not fabricate a `CI:` result.

3. **CI gate (hard block on anything but PASS).** Per `FAILURE-MATRIX.md`'s "CI red at settle
   gate" row ("blocks `recipe-settle` ... No `settled` event should be posted"):
   - `CI: PASS` → continue to step 4.
   - `CI: FAIL` or `CI: WARN` → **stop here.** Print the script's own detail lines verbatim, tell
     the operator plainly that settling is blocked until CI is green ("Fix CI, rerun checks, then
     settle" per the same FAILURE-MATRIX row), and **do not proceed to step 4, do not prompt for
     PO acceptance, and do not call `gsd-jira-sync` under any circumstance.** `WARN` (inconclusive
     — e.g. no PR/check-runs data found for `<ref>`) is treated exactly like `FAIL` for this gate:
     the quality floor is "CI green", and an unconfirmed result is not green.

4. **PO-accept gate — a genuine, real-time human question in this conversation, never
   fabricated, never auto-answered, never skippable.** Ask the operator directly, in your own
   response, something equivalent to: "CI is green for `<owner/repo>@<ref>`. As the Product
   Owner, do you accept this work as done? [y/n]" — then **stop and wait for their actual next
   message.** Do not answer on their behalf, do not assume "yes" because CI passed, do not
   proceed to step 5 without an explicit affirmative reply appearing in the conversation. See
   "Why this is a genuine human gate, not skippable" below for the full rationale.
   - Affirmative (y/yes) → continue to step 5.
   - Negative (n/no) or the operator otherwise declines → stop here. Report "PO declined — not
     settled, no sync performed" in your summary. Do not call `gsd-jira-sync`.

5. **Sync `settled`** (only reached when step 3 was `PASS` and step 4 was affirmative).
   `bench/lib/parse-state.sh` and `bench/lib/sync-ledger.sh` are not duplicated into every target by
   design — resolve both real paths via `.gsd-recipe/scripts/recipe-paths.sh` first (same mechanism
   `recipe-validate-tokens-SKILL.md` § C step 1 documents in full):
   ```
   PARSE_STATE="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/parse-state.sh)"
   SYNC_LEDGER="$(.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/sync-ledger.sh)"
   ```
   Resolve the issue key with `"$PARSE_STATE" resolve-issue settled --phase N`.
   Unresolved (no phase-task row for N) → do not block;
   warn the operator ("No tracker task linked for phase N — skipping Jira sync, settle still recorded
   locally in this summary") and skip straight to step 6 — same fail-open precedent every prior
   `recipe-*` sync call already uses for a missing tracker linkage. Resolved → compute the
   idempotency key via `"$SYNC_LEDGER" key settled <issue_key> --phase N` and check
   `"$SYNC_LEDGER" has <key>` first. Already present → skip (report
   `duplicate_skipped`, no re-post). Otherwise, invoke the `gsd-jira-sync` skill's own documented
   single-event workflow (`gsd-jira-sync settled <issue_key> --phase N
   [--transition "Name"]`) — do not inline `draft-jira-comment.sh`'s
   draft/post/stamp or Epic roll-up steps here. The child transitions to Done first; the sync
   skill then transitions the Epic only if every recorded child is Done.

6. **Summarize**, in one final block to the operator: phase `N`, resolved `<owner/repo>@<ref>`,
   the CI result (`PASS`/`FAIL`/`WARN` with the script's own detail), the PO-accept decision
   (`accepted` / `declined` / not reached because CI blocked), the resolved issue key (or "none
   linked"), and the sync result (`posted` / `duplicate_skipped` / `skipped-no-issue` /
   `not-attempted-ci-blocked` / `not-attempted-po-declined`).

## D. Do NOT

- Do not call `gsd-jira-sync` at all when CI is not `PASS` — no draft, no post, no stamp, not even
  a "blocked" comment. `FAILURE-MATRIX.md` is explicit: "No `settled` event should be posted."
  This is the one hard rule this entire skill exists to enforce.
- Do not call `gsd-jira-sync` at all when the PO-accept prompt hasn't received a real affirmative
  reply from the operator in this conversation — never proceed on a timeout, an assumed default,
  or because "CI passed so they'd probably say yes anyway."
- Do not implement a flag, environment variable, or any other mechanism that skips or
  auto-answers the PO-accept prompt. Unlike `install.sh`'s own `--yes` (which only ever skips a
  *scaffolding* consent prompt), this gate has **no** skip-prompt equivalent — see "Why this is a
  genuine human gate, not skippable" below.
- Do not implement the CI check as a `read -p`-style bash prompt, and do not implement the
  PO-accept gate as a bash script prompt either. The CI check is scriptable (`gh` is a real local
  CLI); the PO-accept gate is not — a bash process spawned by a tool call has no real human typing
  at its stdin, so a `read -p` there would only ever be answered by the agent itself, silently
  defeating the entire point of a *human* gate. Only the live conversation between the operator
  and this agent turn is a real human-reachable surface — same architectural reasoning
  `recipe-validate-tokens`'s own SKILL.md documents for why its Jira/Atlassian check is
  agent-mediated rather than scriptable, applied here to a different kind of check.
- Do not fabricate, guess at, or infer a `gh pr checks`/`check-runs` result. If `gh` is missing,
  unauthenticated, or the API call fails outright, that is `CI: FAIL`/`WARN` — never silently
  treated as green, and never worked around with a fallback heuristic (e.g. "the last commit
  looked fine so I'll assume it passed").
- Do not implement or invoke any project-specific/benchmark grader hook. Explicitly parked for v1
  (see the integration report's "Explicitly out of scope" table) — this skill relies solely on the
  real `gh`-based CI check plus the human PO gate, same precedent as the DAG work being parked
  per `DECISIONS.md`.
- Do not inline Jira drafting/posting/stamping logic (`draft-jira-comment.sh`'s steps) directly —
  always call into `gsd-jira-sync`'s documented workflow instead.
- Do not guess `<owner/repo>`/`<ref>` when `git remote get-url origin` doesn't resolve to a
  recognizable GitHub remote — stop and ask the operator to pass `--owner-repo`/`--ref` explicitly.

## Why this is a genuine human gate, not skippable

`TRACEABILITY-LLD.md`'s own locked rule is unambiguous: **"Settled = PO + CI green"** — both
halves are mandatory, and neither can be inferred from the other. CI passing says nothing about
whether a human Product Owner actually reviewed and accepted the work; a PO saying "looks good"
says nothing about whether the code that will ship is actually green. `RUNTIME-LLD.md` § 4.c Ship
lists "**PO accept + CI green**" as the human gate for this exact step, and `FAILURE-MATRIX.md`'s
"CI red at settle gate" row is explicit that no `settled` event should ever be posted without it.

This is deliberately **stricter** than `install.sh`'s own `--yes` convention. `install.sh --yes`
skips a *scaffolding* consent prompt ("may I copy these files into your repo?") — a low-stakes,
reversible, purely mechanical action with an `--uninstall` undo path. Accepting a feature as
*done* is neither mechanical nor reversible in the same way: it is the literal quality floor this
whole recipe locks in, and `DECISIONS.md`/`README.md`'s own "Locked rules" section names it as
such. Giving this gate a skip flag would let a scripted/CI-driven run silently rubber-stamp every
settle, which defeats the entire reason the gate exists. So, unlike every other `--yes`-bearing
installer flag in this recipe, **there is no flag, environment variable, or non-interactive mode
that answers this prompt on the operator's behalf** — not on the installer (which doesn't
implement this gate at all — see below), and not on the skill's own invocation syntax in § A.

The mechanism matters as much as the policy. A Cursor skill invocation is a conversation between
an operator and an agent turn — there is no live human sitting at a spawned bash process's stdin
for a `read -p` to reach. If this gate were implemented as a shell script prompt, the *agent*
would be the only thing capable of answering it (there being no other process attached to that
terminal), which would make it a rubber stamp indistinguishable from no gate at all. Routing the
question through the actual chat turn — the one channel where a real human operator is
provably on the other end — is what makes this a genuine gate rather than a cosmetic one. This is
the same "only an agent turn can reach the real actor" reasoning `recipe-validate-tokens`'s own
SKILL.md already documents for its Jira/Atlassian MCP check (only a live agent turn has MCP
tool-calling access) — here, the "real actor" happens to be the human operator instead of an MCP
session, but the underlying architectural principle (don't fake a check a script can't actually
perform) is identical.

## Why Option B (skill-to-skill `gsd-jira-sync` invocation), not inlined posting logic

Same choice, and the same rationale, `recipe-run-phase` (TASK-024) and `recipe-plan-phase`
(TASK-017) already made for their own `execute_started`/`execute_complete`/`plan_complete` sync
calls: this skill decides **whether** and **with what arguments** to sync (only after both the CI
gate and the PO-accept gate have genuinely passed), but the actual drafting
(`draft-jira-comment.sh`), the `addCommentToJiraIssue`/`transitionJiraIssue` MCP calls, and the
`emit-stamp.sh` KPI stamp remain entirely `gsd-jira-sync`'s own documented, single-event workflow.
Inlining that logic here would create a second, drifting implementation of Jira posting — instead,
`recipe-settle` composes with `gsd-jira-sync` by name, exactly like every other `recipe-*` skill
that ever needs to post a lifecycle event. The idempotency mechanism is identical too:
`bench/lib/sync-ledger.sh key settled <issue_key> --phase N` then `sync-ledger.sh has <key>` before ever
invoking `gsd-jira-sync`, so re-running `recipe-settle` after a crash or an operator re-invocation
never double-posts the same `settled` comment.

## What this does NOT do (see the integration report for the full rationale)

- **No project-specific/benchmark grader hook.** Parked for v1, same precedent as the DAG work
  (`TASK-009`, parked per `DECISIONS.md`) — this skill's quality floor is exactly "real `gh`-based
  CI check + human PO accept," nothing more, nothing project-specific.
- **No auto-answer, flag, or timeout for the PO-accept prompt.** See "Why this is a genuine human
  gate" above.
- **No fallback heuristic when `gh` is unavailable or the API call fails.** That state is `CI:
  FAIL`, full stop — never silently treated as green.
- **No inlined Jira posting logic.** `settled` is emitted by invoking `gsd-jira-sync`'s documented
  workflow, not by calling `draft-jira-comment.sh` and the Atlassian MCP directly from within this
  skill.
</cursor_skill_adapter>

# recipe-settle — quality-floor settle gate (TASK-027)

Formalizes `docs/netapp-recipe/lld/TRACEABILITY-LLD.md`'s locked rule 4 ("**Settled** = PO + CI
green"), `docs/netapp-recipe/lld/RUNTIME-LLD.md` § 4.c Ship's human gate ("**PO accept + CI
green** before `settled`"), and `docs/netapp-recipe/lld/FAILURE-MATRIX.md`'s "CI red at settle
gate" row ("blocks `recipe-settle` ... No `settled` event should be posted") into its own
invoke-by-name Cursor skill: a real, scriptable, testable `gh`-based CI check, followed by an
explicit, non-skippable, interactive human PO-accept confirmation, and only then a sync of the
`settled` event to the linked phase task, followed by aggregate Epic status roll-up.

**Spec:** `docs/netapp-recipe/lld/TRACEABILITY-LLD.md` rule 4 · `docs/netapp-recipe/lld/RUNTIME-LLD.md`
§ 4.c · `docs/netapp-recipe/lld/FAILURE-MATRIX.md` "CI red at settle gate" row ·
`docs/netapp-recipe/BACKLOG.md` TASK-027.

**Built standalone**, the same pattern already used by `recipe-validate-tokens` (TASK-021),
`recipe-run-phase` (TASK-024), and `recipe-plan-phase` (TASK-017) ahead of/alongside the full
`install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-settle.sh`.

## Workflow

1. Resolve `<owner/repo>`/`<ref>` (explicit flags, or `git remote`/`gh pr view`/current branch).
2. Run the real, scriptable CI check (`install-recipe-settle.sh --check-ci <owner/repo> <ref>`) —
   `gh pr checks`/`gh api .../check-runs`, never fabricated.
3. Hard-block on anything but `CI: PASS` — no PO prompt, no Jira sync, ever, per
   `FAILURE-MATRIX.md`'s exact wording.
4. Ask the operator, in the live conversation, an explicit y/n PO-accept question. Wait for a real
   reply — never fabricated, never auto-answered, never skippable via any flag.
5. Only when both gates passed: resolve phase N's task key, check idempotency via
   `sync-ledger.sh`, and sync `settled` via `gsd-jira-sync`; the sync's status-only roll-up closes
   the Epic only after all recorded phase tasks are Done.
6. Summarize phase/CI-result/PO-decision/issue/sync-result in one block.

## Why the CI check is scriptable but the PO-accept gate isn't

Same architectural split `recipe-validate-tokens`'s own SKILL.md already documents for its
GitHub-vs-Jira/Atlassian check, applied to a different pair of checks here: `gh` is a real local
CLI a plain shell process can invoke directly, so the CI half of this gate is a real, standalone,
testable script (`--check-ci`). A genuine "did a human actually accept this" question has no
equivalent local, scriptable oracle — the only surface where a real human is provably present
during a Cursor skill invocation is the conversation itself, so that check is necessarily
agent-mediated, asked directly of the operator in this turn, never answered by a spawned process.

## Relationship to `recipe-review-ship` (TASK-026) and `recipe-verify-feature` (TASK-025)

`recipe-settle` is the last step in the ship sequence `RUNTIME-LLD.md` § 3/§ 4 describes: verify
→ review/ship (open the PR) → settle (CI green + PO accept). This skill does not create, push, or
open anything — it assumes a PR/branch already exists (from `recipe-review-ship` or an equivalent
manual `gsd-ship` step) and only ever checks its CI status and gates the human acceptance on top of
that. No dependency is declared in `BACKLOG.md` (`Depends: —`) because this skill degrades
gracefully if invoked standalone: pass `--owner-repo`/`--ref` explicitly and it works with no prior
recipe step having run at all.

## What this does NOT do

- **Does not implement a project-specific/benchmark grader hook.** Parked for v1 — see the
  integration report's "Explicitly out of scope" table.
- **Does not skip or auto-answer the PO-accept prompt**, ever, under any flag or environment
  variable.
- **Does not fabricate a CI result.** A missing/unauthenticated `gh`, or a failed API probe, is
  always `CI: FAIL`/`WARN` — never silently treated as green.
- **Does not post to Jira directly.** `settled` is emitted via `gsd-jira-sync`'s own documented
  workflow, never inlined posting logic.
