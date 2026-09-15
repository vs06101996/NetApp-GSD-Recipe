---
name: recipe-install-verify
description: "Recipe: post-install verification and install doctor for the NetApp GSD recipe (TASK-023, extended by TASK-044). Runs `install.sh --verify` as the bash-checkable foundation, runs native GSD health checks in the same turn, delegates token validation, performs a live read-only tracker MCP probe, and when Jira passes records it through `install.sh --record-jira-check pass` before rerunning `install.sh --verify` so `.gsd-recipe/INSTALL-VERIFIED.json` is reachable in one Agent turn. Also reports observer and bare-metal checks without fabricating results."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-install-verify`) with no required arguments:
- `--target <path>` — optional, defaults to the current repo root (same convention as every
  `install-recipe-*.sh` installer). Only needed when verifying an install staged into a different
  directory than the one this turn is running in (e.g. a scratch/manual-verification repo).

Examples:
- `recipe-install-verify`
- `recipe-install-verify --target /tmp/scratch-repo`

## B. Prerequisites

- `.gsd-recipe/scripts/install.sh` (or the equivalent staged/installed copy) has been run at least
  once against the target — i.e. `.gsd-recipe/install-report.json` already exists. If it doesn't,
  warn the operator ("no install-report.json found — run install.sh first") and still proceed with
  whatever checks remain possible (native GSD checks, observer-config presence, MCP listing) rather
  than stopping outright; item 5/6/7's bash foundation will simply report against an empty/default
  state.
- No other prerequisite. The checks are read-only except for the existing verification artifacts:
  report entries written through `$REPORT_LIB`, `jira_check=pass` written through
  `install.sh --record-jira-check pass` after a real live Jira probe, and
  `.gsd-recipe/INSTALL-VERIFIED.json` written by the final `install.sh --verify`.

## C. Tool Usage

`install.sh` and `bench/lib/install-verify-report.sh` are not duplicated into every target by
design (only `gsd-benchmark`, the recipe's own source repo, keeps the full `.gsd-recipe/scripts/`
and `bench/` trees) — resolve both real paths once, via `.gsd-recipe/scripts/recipe-paths.sh` (same
mechanism `recipe-validate-tokens-SKILL.md` § C step 1 documents in full), and reuse those resolved
paths for every step below that needs them:
```
INSTALL_SH="$(<target>/.gsd-recipe/scripts/recipe-paths.sh resolve .gsd-recipe/scripts/install.sh --target <target>)"
REPORT_LIB="$(<target>/.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/install-verify-report.sh --target <target>)"
```

1. **Run the bash-checkable foundation (initial pass).** `Shell`: run
   `$INSTALL_SH --verify --target <target>` (absolute paths, no reliance
   on a prior `cd`). This is the delegation boundary decision for this skill (see "Delegation
   boundary" below): `install.sh --verify` already implements items **5** (Templates present), **6**
   (OKF index), and **7** (Gitignore entries) correctly and completely — a bash script can `test -f`
   and `grep` a `.gitignore` line just as well as an agent turn can, so re-implementing those three
   checks here would be pure duplication. It also checks `config.json` parses with the required
   `traceability`/`observer` fields, the recorded prereqs (`python3`/`git`/`node`/`gh`/`gsd_core`/
   `graphify`), and its own `github_check`/`jira_check` pair (see step 5 below for why this skill
   does *not* also duplicate that pair as item 4). Parse its stdout for the `[C] 5.`/`[C] 6.`/
   `[C] 7.` lines' pass/FAIL verdicts (and the `config.json —` line, which is a bonus check beyond
   the 10-item table, worth surfacing in the summary but not itself one of items 1-10) and record
   each with `$REPORT_LIB record <N> "<name>" <pass|fail> --detail "<line>"
   --report <target>/.gsd-recipe/install-report.json`.
   - `install.sh --verify` exits non-zero whenever anything it checks is failing/pending (including
     its own `jira_check: pending` gate) — a non-zero exit here does **not** mean this skill stops.
     Preserve the output, continue every agent-mediated check, and defer the final items 5-7/config
     verdicts until step 6 has had a chance to record a live Jira pass and rerun this command.

2. **Item 1 — GSD integrity.** Call native `/gsd-health` directly, in this same turn. Per the
   approved Option-B precedent (see "Why this skill may call native GSD commands directly" below),
   the operator's own invocation of `recipe-install-verify` is itself the manual trigger — this is
   not an unapproved autonomous invocation of a native GSD command. If `/gsd-health` reports
   failures that `--repair` can address, you may re-run it with `--repair` and note the outcome; if
   it reports failures that are not auto-repairable, record `fail` and surface the exact failure
   text to the operator. Record with `$REPORT_LIB record 1 "GSD integrity" <pass|fail>
   --detail "<summary of /gsd-health output>"`.

3. **Item 2 — Context headroom.** Call native `/gsd-health --context` directly, same turn, same
   Option-B justification. Record `pass` if headroom is reported healthy, `warn` if it flags
   pressure but nothing outright broken, `fail` if it reports a hard problem. Record with
   `$REPORT_LIB record 2 "Context headroom" <pass|warn|fail> --detail "<summary>"`.

4. **Item 3 — Capability surface.** Call native `/gsd-surface status` directly (fall back to `gsd
   capability list --json` if `/gsd-surface` isn't available in this GSD install), same turn, same
   Option-B justification. Record `pass` if the recipe's expected skills/capabilities show up as
   surfaced, `warn` if the command runs but the recipe's own skills are unexpectedly absent from the
   surfaced set, `fail` if the command itself errors. Record with `$REPORT_LIB record 3
   "Capability surface" <pass|warn|fail> --detail "<summary>"`.

5. **Item 4 — Token still valid (delegates to TASK-021, never duplicates it).** `Glob` for
   `<target>/.cursor/skills/recipe-validate-tokens/SKILL.md`.
   - **Staged** → this is the skill-to-skill delegation case (same shape as `recipe-run-phase`
     invoking `gsd-jira-sync`): invoke `recipe-validate-tokens` directly, in this same turn, and use
     *its* reported pass/fail as item 4's status verbatim — do not re-derive or second-guess it.
     Record with `$REPORT_LIB record 4 "Token still valid" <its status> --detail
     "delegated to recipe-validate-tokens"`.
   - **Not staged** → do the **minimal** fallback only: `Shell`: `gh auth status` (absolute, no `gh
     api user` probe, no scope-gap analysis — that richer probe is `recipe-validate-tokens`'s entire
     job, not this skill's business to reimplement). Record `pass` if `gh auth status` exits 0,
     `fail` otherwise, with detail noting this was the minimal fallback, e.g. `$REPORT_LIB
     record 4 "Token still valid" <pass|fail> --detail "recipe-validate-tokens not staged — fallback
     gh auth status only"`.
   - Never implement a fuller token/scope probe than the minimal fallback above inside this skill,
     even temporarily — that duplicates `recipe-validate-tokens`'s (TASK-021) entire scope. See
     "Item 4 delegation relationship" below.
   - If the delegated skill reports that its live Jira/Atlassian
     `getAccessibleAtlassianResources` call passed, retain that exact result for step 6. Do not call
     the same live probe twice in one verification turn.

6. **Item 8 — MCP reachable, then collapse the Jira gate.** Resolve the configured tracker via
   `bench/lib/tracker-sync-config.sh` (also not duplicated into every target — resolve it the same
   `recipe-paths.sh` way as `$INSTALL_SH`/`$REPORT_LIB` above):
   ```
   TRACKER_CFG="$(<target>/.gsd-recipe/scripts/recipe-paths.sh resolve bench/lib/tracker-sync-config.sh --target <target>)"
   "$TRACKER_CFG" get-tracker --config <target>/.gsd-recipe/config.json
   ```
   (default `jira` if unset/missing). Use `GetMcpTools` to list tools on the tracker's MCP server.
   For Jira, discover the Atlassian server/tool schema first, then make one non-mutating live
   `CallMcpTool` call to `getAccessibleAtlassianResources`, unless step 5 already produced that exact
   live result. If discovery is empty, that invocation is still required as a wake probe because
   Cursor can idle-suspend a healthy HTTP transport; empty enumeration alone is inconclusive. A
   non-empty successful response proves both reachability and authentication; record item 8
   `pass`. Merely listing schemas does **not** prove the Jira check passed.
   - After that live Jira pass, immediately run:
     ```
     $INSTALL_SH --record-jira-check pass --target <target>
     $INSTALL_SH --verify --target <target>
     ```
     This is one uninterrupted `recipe-install-verify` turn. The first command uses the existing
     script/CI escape hatch; the second consumes the newly recorded pass and writes
     `.gsd-recipe/INSTALL-VERIFIED.json` when all local checks pass. Parse items 5-7 and the bonus
     config verdict from this final rerun, superseding the initial pending output from step 1.
   - If the live Jira call is unavailable, unauthenticated, or fails, record item 8 `warn`, leave
     `jira_check` as `pending`, and report that `INSTALL-VERIFIED.json` remains blocked. Never record
     a pass from tool discovery alone and never fabricate a live response.
   - For a configured non-Jira tracker, perform its safest available read-only live probe for item
     8, but do not mutate the Jira-named `jira_check` field.

7. **Item 9 — Observer loop scheduled (optional v1, read-only).** `Glob`/`Read`
   `<target>/.gsd-recipe/observer-config.json`.
  - **Missing** → `warn` — per `docs/netapp-recipe/lld/OBSERVER-LLD.md`, the observer is
    "post-pilot, do not implement for v1 pilot"; its absence is expected in most repos today, not a
    defect. Record `$REPORT_LIB record 9 "Observer loop scheduled" warn --detail
     "observer-config.json absent — expected for v1 (OBSERVER-LLD.md: post-pilot)"`.
   - **Present** → check the `enabled` field. `enabled: true` (plus a `tick_interval_seconds` value)
     → `pass`. `enabled: false` → `warn` (observer installed but not currently scheduled — an
     operator choice, not a break). Malformed/unparseable JSON → `fail`. Record accordingly with the
     `enabled`/interval values in `--detail`.

8. **Item 10 — Bare metal Gate A (feasibility-gated, never fabricates).** `Read`
   `<target>/.templates/bare_metal.template.md`.
   - **Still generic** (contains the installer's own "Delete this comment block when filling in real
     bootstrap commands" HTML comment, or any of the four required rows — `install_deps`, `build`,
     `unit_tests`, `smoke` — still hold the literal `` `<command>` `` placeholder)     → **warn and
    skip**. Never invent, guess, or fabricate repo-specific bootstrap commands to make this item
    "pass" — this mirrors `docs/netapp-recipe/lld/INSTALL-LLD.md`'s own documented feasibility
    caveat for this exact item ("Truly zero-touch bootstrap across all stacks is hard; per-repo
    human authorship of commands is expected"). Record `$REPORT_LIB record 10
    "Bare metal Gate A" warn --detail "bare_metal.template.md still generic/unfilled — skipped per
    feasibility caveat, operator sign-off required per Step 5's human-gate row"`.
   - **Genuinely filled in** (all four required rows hold real, non-placeholder commands) → run each
     of `install_deps`, `build`, `unit_tests`, `smoke` once, in order, via `Shell`, stopping at the
     first non-zero exit. All four exit 0 (and, if a `smoke output contains:` substring is declared
     under "Success criteria", that substring is actually present in the `smoke` command's output) →
     `pass`. Any failure → `fail`, with the failing command and its exit code in `--detail`. Either
     way, this is a genuine one-time run of the operator's own declared commands, not a fabrication —
     the operator authored them, this skill only executes what's already written down.

9. **Write the final report and summarize.** `Shell`: `$REPORT_LIB summary
   --report <target>/.gsd-recipe/install-report.json` to read back everything just recorded, then
   report to the operator in one pass/warn/fail table (items 1-10, plus the bonus `config.json`
   check from step 1) and a single explicit closing line stating whether `install_verified` is
   `true` or `false`, and — per the checklist's own failure-handling rule — that **items 1-7 must
   ALL be `pass` for `install_verified` to be true; items 8-10 are warn-only and never affect this
   marker either way, even on `fail`. Also state whether the final `install.sh --verify` wrote
   `.gsd-recipe/INSTALL-VERIFIED.json`; do not conflate that artifact with the report marker.

## D. Do NOT

- Do not duplicate `install.sh --verify`'s bash-checkable items (5, 6, 7, or its bonus `config.json`
  check) with a hand-rolled re-implementation — always delegate to the actual script's actual
  output, per the "Delegation boundary" decision below.
- Do not duplicate TASK-021's (`recipe-validate-tokens`) token/scope-probe scope for item 4, even
  when it isn't staged — the fallback is strictly `gh auth status` and nothing richer. Never add a
  `gh api user` probe, a Jira scope probe, or any other logic that belongs to `recipe-validate-tokens`.
- Do not invoke native GSD commands (`/gsd-health`, `/gsd-health --context`, `/gsd-surface status`)
  outside of a genuine operator-triggered `recipe-install-verify` turn — never schedule, background,
  or auto-repeat these calls. The Option-B precedent only covers this skill's own same-turn,
  operator-invoked call, nothing else.
- Do not fabricate `bare_metal.template.md` bootstrap commands to force item 10 to "pass" when the
  template is still generic — warn and skip, always. This is a hard rule, not a judgment call.
- Do not hard-block the operator on any outcome. Every item — including items 1-7 — is reported as
  pass/warn/fail; this skill never raises an error that stops the turn or refuses to produce a
  summary. The `install_verified` marker communicates blocking status to future tooling/operators;
  this skill's own execution never blocks on it.
- Do not write a second, competing `INSTALL-VERIFIED` artifact or write
  `.gsd-recipe/INSTALL-VERIFIED.json` directly. This skill reruns `install.sh --verify`, which
  remains the sole writer of that file. This skill's checklist marker lives inside
  `.gsd-recipe/install-report.json` (the file `install.sh` already writes and the file the LLD's own
  Step 5 table literally names) as the `install_verified` key — a different file, a different
  scope, no collision, both left standing.
- Do not touch `.gsd-recipe/scripts/install.sh`, `bench/tests/test-install.sh`,
  `docs/netapp-recipe/BACKLOG.md`, or `docs/netapp-recipe/README.md` from within this skill's own
  runtime logic — this skill only *invokes* `install.sh --verify` as a subprocess; it never edits
  it. (Composing this skill's own installer into `install.sh` as a sixth sub-installer is a separate,
  human-reviewed edit to that file — not something this skill does at runtime.)
</cursor_skill_adapter>

# recipe-install-verify — post-install verification checklist (TASK-023)

Recipe configuration on top of native GSD and the existing fallback installer
(`docs/netapp-recipe/lld/INSTALL-LLD.md` § "Step 5: Verification checklist [N]") — this skill is the
single invoke-by-name entry point for running all 10 checklist items and recording a pass/warn/fail
verdict for each, plus the `install_verified` marker, without ever hard-blocking the operator.

**Spec:** `docs/netapp-recipe/lld/INSTALL-LLD.md` § "Step 5: Verification checklist [N]" ·
`docs/netapp-recipe/BACKLOG.md` TASK-023.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) ahead of full composition into `install.sh` (TASK-010) — this skill has its own
installer, `.gsd-recipe/scripts/install-recipe-install-verify.sh`. Composition into `install.sh` as
a sixth sub-installer is a proposed edit for a human maintainer to apply (see the integration
report's copy-paste-ready snippet) — this task does not make that edit itself, per the parallel-work
shared-file constraint it was built under.

## Workflow

1. Run `install.sh --verify` as the bash-checkable foundation for items 5 (templates), 6 (OKF
   index), 7 (gitignore), and a bonus `config.json` check — parse its stdout, record each.
2. Call native `/gsd-health` directly (item 1), same turn (Option B).
3. Call native `/gsd-health --context` directly (item 2), same turn.
4. Call native `/gsd-surface status` (or `gsd capability list --json`) directly (item 3), same turn.
5. Item 4: delegate to `recipe-validate-tokens` if staged (skill-to-skill invocation, its verdict
   used verbatim); otherwise run a minimal `gh auth status` fallback only.
6. Item 8: make a read-only live tracker MCP probe. On a live Jira pass, record it through
   `install.sh --record-jira-check pass` and rerun `install.sh --verify` in the same turn.
7. Item 9: check `.gsd-recipe/observer-config.json` presence and `enabled` field (read-only,
   warn-only, absence expected for v1 per OBSERVER-LLD.md).
8. Item 10: if `bare_metal.template.md` is still generic, warn and skip (never fabricate); if
   genuinely filled in, run the declared bootstrap commands once and record the result.
9. Record every item via `bench/lib/install-verify-report.sh`, then summarize pass/warn/fail per
   item and the overall `install_verified` marker to the operator.

## Delegation boundary: what `install.sh --verify` already covers vs. what this skill adds

`install.sh` already has a `--verify` mode and a `verify()` function (see
`.gsd-recipe/scripts/install.sh`) that correctly implements, in bash, everything a bash script
*can* check:

| Checklist item | Covered by `install.sh --verify`? | This skill's role |
|---|---|---|
| 1. GSD integrity | No — needs `/gsd-health`, agent-mediated | This skill runs it directly (native call) |
| 2. Context headroom | No — needs `/gsd-health --context`, agent-mediated | This skill runs it directly |
| 3. Capability surface | No — needs `/gsd-surface status`, agent-mediated | This skill runs it directly |
| 4. Token still valid | Partially — `install.sh` has its own `github_check`/`jira_check` pair (install-time, not this checklist item) | This skill delegates to `recipe-validate-tokens` (TASK-021) if staged, else a minimal `gh auth status` fallback — see below |
| 5. Templates present | **Yes**, fully (`[C] 5.` line) | This skill parses and reuses that line verbatim |
| 6. OKF index | **Yes**, fully (`[C] 6.` line) | Parses and reuses |
| 7. Gitignore | **Yes**, fully (`[C] 7.` line) | Parses and reuses |
| 8. MCP reachable | No — install-time only prints a registration snippet | This skill discovers tools, performs a read-only live tracker probe, and on Jira pass records it before rerunning shell verification |
| 9. Observer loop scheduled | Partially — `install.sh --verify` checks the `fotw-observer` **ledger component is composed** (i.e. the installer ran), not whether the loop is actually `enabled`/scheduled | This skill checks `.gsd-recipe/observer-config.json`'s `enabled` field directly — a different, complementary check |
| 10. Bare metal Gate A | No — mentions it only as a "run manually" echo line | This skill actually runs the declared bootstrap commands, gated on the template being genuinely filled in |

**The scoping decision (confirmed, not left ambiguous):** this skill calls `install.sh --verify` as
its foundation for the three items a bash script can fully and correctly check on its own (5, 6, 7),
reusing that script's actual output rather than re-implementing `test -f`/`grep` logic a second time
— duplication with zero benefit. Items 1-3 and 8-10 are handled directly by this skill because they
inherently require either a native GSD command, an MCP tool-listing call, or a genuine one-time
bootstrap-command execution — none of which a bash subprocess can perform on its own (the exact
"bash has no MCP tool-calling access" split `bench/runners/sync-reconcile.sh`'s header comments
document for why that script only *queues* Jira posts rather than posting them itself). Item 4 is
neither duplicated nor left to this skill's own judgment — see the delegation section immediately
below.

## Item 4 delegation relationship (never duplicates TASK-021)

`recipe-validate-tokens` (TASK-021, `docs/netapp-recipe/BACKLOG.md`) is being built in parallel with
this task and owns the *entire* "token still valid" checklist item — a fuller probe than a single
`gh auth status` call (see `docs/netapp-recipe/lld/INSTALL-LLD.md` § "Step 1: Token validation [X]"
for the richer scope: token presence, API probe, scope probe, GSD-version probe). This skill
deliberately does **not** re-implement any of that. Its own item-4 logic is exactly two branches:

1. **`recipe-validate-tokens` is staged** (`.cursor/skills/recipe-validate-tokens/SKILL.md` exists)
   → invoke it directly, skill-to-skill, in the same turn (identical pattern to `recipe-run-phase`
   invoking `gsd-jira-sync` rather than inlining its posting logic), and use its verdict verbatim.
2. **Not staged** → fall back to the bare minimum: `gh auth status` only, explicitly labeled in the
   recorded detail as "fallback, not the full probe" so nobody downstream mistakes this narrow
   check for TASK-021's real scope.

This is the intentional non-duplication the task was built to preserve — if TASK-021 lands with a
different invocation shape than assumed here, only this one delegation branch needs updating; the
other 9 items are entirely independent of it.

## Why this skill may call native GSD commands directly (items 1-3) — the Option B precedent

`docs/netapp-recipe/AGENTS.md` line 11's standing rule — "do not invoke GSD skills... on the user's
behalf" — exists to prevent an agent from autonomously triggering `gsd-plan-phase`,
`gsd-execute-phase`, etc. *without* the operator having asked for that specific action right now.
`recipe-run-phase`'s and `recipe-plan-phase`'s own SKILL.md files (`.gsd-recipe/templates/
recipe-run-phase-SKILL.md` § "Why Option B", `recipe-plan-phase-SKILL.md` § "Why Option B") already
establish the approved exception to that rule: **the operator's own act of invoking a `recipe-*`
skill by name IS the manual GSD trigger** — there is nothing autonomous about a native call that
only happens because the operator just typed the recipe skill's name specifically to make it happen.

That reasoning applies identically here. `/gsd-health`, `/gsd-health --context`, and `/gsd-surface
status` are read-only, side-effect-free native GSD commands (unlike `gsd-plan-phase`/
`gsd-execute-phase`, they don't produce artifacts or advance any workflow state) — if calling the
*mutating* native commands directly is approved under Option B, calling these strictly-diagnostic
read-only ones directly is at least as safe, under the exact same "operator's invocation is the
trigger" logic. This skill therefore calls them directly, in the same turn, precisely because
`recipe-install-verify` was itself just invoked by the operator to produce this checklist right now.

## Never hard-blocks

Per `docs/netapp-recipe/lld/INSTALL-LLD.md` Step 5's own failure-handling row ("Block p1 usage until
checks 1-7 pass; 8-10 may warn-only"), the *blocking semantics* live in the `install_verified`
marker this skill writes — not in this skill's own execution. Every one of the 10 items, including
1-7, is always fully checked and reported; a `fail` on item 1 never stops items 2-10 from running,
and this skill never raises an error, aborts the turn, or refuses to produce its final summary
regardless of how many items fail. Downstream tooling/operators are the ones expected to treat
`install_verified: false` as "not yet ready for p1 usage" — this skill's job is only to produce that
signal accurately, not to enforce it.

## What this does NOT do (see the integration report for the full rationale)

- **No re-implementation of `install.sh --verify`'s bash-checkable logic.** Items 5-7 and the bonus
  `config.json` check are always sourced from that script's real output.
- **No re-implementation of `recipe-validate-tokens`'s (TASK-021) token/scope-probe scope.** Item
  4's fallback is strictly `gh auth status`, nothing richer, ever.
- **No fabricated `bare_metal.template.md` bootstrap commands.** Item 10 warns and skips whenever
  the template is still generic — matching `docs/netapp-recipe/lld/INSTALL-LLD.md`'s own documented
  feasibility caveat for this exact item.
- **No scheduling/automation of the native GSD calls in items 1-3.** They only ever run once, inline,
  during a genuine operator-invoked `recipe-install-verify` turn.
- **No hard blocking.** Every item is checked and reported regardless of outcome; the
  `install_verified` marker communicates blocking status to downstream consumers, not this skill's
  own control flow.
