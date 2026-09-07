# NetApp GSD Recipe

Self-contained bundle for engineers and dev agents. Share `docs/netapp-recipe/` as one unit.

**Agents:** read [AGENTS.md](AGENTS.md) first.

---

## What this is

A **wrapper on GSD** — codebase-agnostic SDLC scaffolding plus Jira/GitHub traceability. GSD remains the orchestrator (`gsd-plan-phase`, `gsd-execute-phase`, …). This recipe adds harness scripts, schemas, and (when built) install + reconciler automation.

---

## Built vs spec (100% shipped)

| Component | Status |
|-----------|--------|
| Native GSD | **Built** |
| `gsd-jira-sync`, draft scripts, templates | **Built** — single-event mode (manual invoke after milestones) + drain mode (TASK-005, see below) |
| `emit-stamp.sh`, GitHub PR draft harness | **Built** |
| `recipe-prd-intake` (TASK-016) | **Built** — ahead of schedule, standalone installer bypassing TASK-010; see [bench/report/recipe-prd-intake-integration-report.md](../../bench/report/recipe-prd-intake-integration-report.md) |
| FOTW observer (TASK-013) | **Built** — ahead of schedule, standalone installer bypassing TASK-010; see [bench/report/fotw-observer-install-integration-report.md](../../bench/report/fotw-observer-install-integration-report.md) |
| `parse-state` (TASK-002) | **Built** — `bench/lib/parse-state.sh`; see [bench/report/parse-state-integration-report.md](../../bench/report/parse-state-integration-report.md) |
| `sync-ledger` (TASK-001) | **Built** — `bench/lib/sync-ledger.sh` |
| `sync-reconcile.sh` (TASK-003) | **Built** — `bench/runners/sync-reconcile.sh`; detect+draft+queue only (does not post — see report for the reconcile/drain split); see [bench/report/sync-reconcile-integration-report.md](../../bench/report/sync-reconcile-integration-report.md) |
| `sync-drain-queue.sh` (TASK-005) | **Built** — `bench/runners/sync-drain-queue.sh`; drains `sync-reconcile.sh`'s queue (list/mark-done/mark-failed), wired into `gsd-jira-sync` skill's Drain mode; see [bench/report/sync-drain-queue-integration-report.md](../../bench/report/sync-drain-queue-integration-report.md) |
| `tracker-sync` (TASK-014) | **Built** — narrowed scope: install-time registration + thin dispatch skill only (`bench/lib/tracker-sync-config.sh`, `.gsd-recipe/scripts/install-tracker-sync.sh`), ahead of schedule via standalone installer bypassing TASK-010; `sync-reconcile.sh`/`sync-drain-queue.sh`/`sync-ledger.sh` stay Jira-literal — see [bench/report/tracker-sync-integration-report.md](../../bench/report/tracker-sync-integration-report.md) |
| `bench/tests/` ledger + parser (TASK-015) | **Built** — formalize only: deliverable already satisfied by `bench/tests/test-sync-ledger.sh` (10 assertions) + `bench/tests/test-parse-state.sh` (20 assertions); one small additive assertion closed a record-shape coverage gap — see [bench/report/sync-ledger-parse-state-tests-integration-report.md](../../bench/report/sync-ledger-parse-state-tests-integration-report.md) |
| STATE.md validator (TASK-008) | **Built** — formalize only: spec absorbed into `parse-state.sh`'s (TASK-002) `validate`/`resolve-issue` subcommands, no separate `state-tracker.sh` created; all 8 `DATA-CONTRACTS.md` validation rules confirmed live rule-by-rule — see [bench/report/state-tracker-validator-integration-report.md](../../bench/report/state-tracker-validator-integration-report.md) |
| `draft-github-pr-comment.sh` + templates (TASK-006) | **Built** — `bench/runners/draft-github-pr-comment.sh`; bundle-copied from `reference/harness/` (same precedent as TASK-003's Jira copy) and polished — fixed a hardcoded `commit=HEAD` idempotency-key bug; stdout only, does not call `gh pr comment` (posting out of scope, no GitHub drain task exists yet) — see [bench/report/draft-github-pr-comment-integration-report.md](../../bench/report/draft-github-pr-comment-integration-report.md) |
| `install.sh` umbrella scaffold (TASK-010) | **Built** — narrowed scope: local directory/template/`.gsd-recipe/config.json` scaffolding + composes `install-observer.sh`/`install-tracker-sync.sh` + real `gh`-based GitHub check (warn-only) + `--verify`/`--record-jira-check`/`--uninstall`; **extended with a prerequisite bootstrap** — `preflight()`/`ensure_prereq()` implement a unified check→auto-fix-attempt→verify→prompt-and-reverify→warn-fallback flow for `python3`/`git` (hard fail-closed), `node`/`gh`/GSD core/**graphify** (soft, warn-only, `brew`/`npx`/`uv`-based auto-fix attempts), recorded in `install-report.json`'s `prereqs` object and surfaced in `--verify`; **graphify uniquely also auto-enables `graphify.enabled` in the target project's `.planning/config.json` when present**, routed exclusively through GSD's own `gsd-tools config-set` (never a hand-rolled JSON merge), with a `GSD_TOOLS_CJS_PATH`-overridable resolution and print-only fallback; live Jira scope check and `mcpServers`/`agent_skills` injection stay agent-mediated/print-only (architecturally unscriptable) — see [bench/report/install-scaffold-integration-report.md](../../bench/report/install-scaffold-integration-report.md) |
| `recipe-planning-policy` skill (TASK-012) | **Built** — ahead of schedule, standalone installer bypassing TASK-010 (also composed into it); folds in the per-phase prerequisite-verification workflow, mandatory SPEC.md/TDD.md usage, and `.knowledge/`/graphify context-gathering as an expanded `PLANNING-POLICY.md` policy plus an injectable `gsd-planner` context file (GSD's `agent_skills` mechanism, not an invoke-by-name Cursor skill) — see [bench/report/recipe-planning-policy-integration-report.md](../../bench/report/recipe-planning-policy-integration-report.md) |
| `recipe-run-phase` skill (TASK-024) | **Built** — narrowed scope: single-phase gate-and-invoke wrapper (`.gsd-recipe/scripts/install-recipe-run-phase.sh`, standalone installer also composed into `install.sh` as a 4th sub-installer); resolves the phase's `PLAN.md`, runs a read-only soft warn-and-confirm planning-policy compliance gate (7 sections + Prerequisites table — never fills it), prints a non-blocking `depends_on` reminder, syncs `execute_started`/`execute_complete` by invoking the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked), then calls native `gsd-execute-phase N [--wave W]` directly in the same turn; DAG pre-req/post-op gating and `execute_wave` handling are explicitly out of scope (parked pending TASK-009) — see [bench/report/recipe-run-phase-integration-report.md](../../bench/report/recipe-run-phase-integration-report.md) |
| `recipe-plan-phase` skill (TASK-017) | **Built** — narrowed scope: single-phase gate-and-invoke wrapper (`.gsd-recipe/scripts/install-recipe-plan-phase.sh`, standalone installer also composed into `install.sh` as a 5th sub-installer); determines first-plan vs re-plan (informational, via a `PLAN.md` glob), resolves the phase's tracker issue key, calls native `gsd-plan-phase N` directly in the same turn, then runs a read-only soft warn-and-confirm post-hoc planning-policy compliance gate (7 sections + Prerequisites table — never fills it) that gates the tracker stamp, prints a non-blocking `depends_on`/`touches` reminder, and syncs `plan_complete`/`plan_revised` by invoking the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked); DAG topo-sort/cycle-detection and pre-req/post-op gating are explicitly out of scope (parked pending TASK-009) — see [bench/report/recipe-plan-phase-integration-report.md](../../bench/report/recipe-plan-phase-integration-report.md) |
| `create-phase-tasks.sh` (TASK-007) | **Built** — `bench/runners/create-phase-tasks.sh`; `detect [--dry-run]` reads `ROADMAP.md` + `STATE.md` and drafts+queues one Jira sub-task per phase without an `issue_key` yet (idempotent via a purpose-built `.gsd-recipe/phase-tasks-queue.jsonl`, not `sync-queue.jsonl` — schema mismatch, see report); `mark-done`/`mark-failed` close the loop after an agent turn's `createJiraIssue`+`createIssueLink`; does not post to Jira itself (detect+draft+queue only, same split as `sync-reconcile.sh`); `parse-state.sh` gained a new `add-phase-task` write subcommand for this — see [bench/report/create-phase-tasks-integration-report.md](../../bench/report/create-phase-tasks-integration-report.md) |
| `capability.json` / `config.schema.json` (TASK-011) | **Built** — `.gsd-recipe/config.schema.json`, `.gsd-recipe/capability.json`, `.gsd-recipe/capability.schema.json`, `bench/lib/capability-schema.sh` (`validate-config`/`validate-capability`/`generate-capability`); `install.sh` calls `generate-capability` after composing every sub-installer, and `--verify` additionally runs a strict `validate-config` schema check — see [bench/report/capability-config-schema-integration-report.md](../../bench/report/capability-config-schema-integration-report.md) |
| `recipe-validate-tokens` skill (TASK-021) | **Built** — standalone, re-invokable credential/scope check (`.gsd-recipe/scripts/install-recipe-validate-tokens.sh`, standalone installer composed into `install.sh` as a 6th sub-installer); real, scriptable GitHub check (`gh auth status`/`gh api user`, warn-only, via its own `--check-github` mode) plus an agent-mediated Jira/Atlassian MCP check (`GetMcpTools`/`CallMcpTool getAccessibleAtlassianResources`, since a bash script has no MCP tool-calling access); reports PASS/WARN/FAIL per credential with soft remediation suggestions only, never fixes anything itself, never prints token values, never touches `.gsd-recipe/config.json`/`.planning/config.json` — see [bench/report/recipe-validate-tokens-integration-report.md](../../bench/report/recipe-validate-tokens-integration-report.md) |
| `recipe-bootstrap-knowledge` skill (TASK-022) | **Built** — idempotent knowledge bootstrap/refresh wrapper (`.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh`, standalone installer composed into `install.sh` as a 7th sub-installer); scaffolds any missing piece of the OKF-shaped `.knowledge/` skeleton (additive-only, never overwrites human/native-command output), then calls native `/gsd-map-codebase [--fast]`, `/gsd-graphify build`, and `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly in the same turn (Option-B precedent); the ingest step alone gracefully warns-and-skips when the manifest is absent. `gsd-extract-learnings`/`gsd-capture` wrapping is explicitly out of scope (different task, `OBSERVER-LLD.md`) — see [bench/report/recipe-bootstrap-knowledge-integration-report.md](../../bench/report/recipe-bootstrap-knowledge-integration-report.md) |
| `recipe-install-verify` skill (TASK-023) | **Built** — narrowed scope: post-install verification wrapper (`.gsd-recipe/scripts/install-recipe-install-verify.sh`, standalone installer composed into `install.sh` as an 8th sub-installer); delegates checklist items 5-7 to `install.sh --verify`'s real output, runs items 1-3 directly via native GSD commands (Option B), delegates item 4 to `recipe-validate-tokens` (TASK-021) or a minimal `gh auth status` fallback, and checks items 8-10 read-only/warn-only (never fabricating `bare_metal.template.md` bootstrap commands); writes an additive `install_verified` marker into `.gsd-recipe/install-report.json` gated on items 1-7 only — see [bench/report/recipe-install-verify-integration-report.md](../../bench/report/recipe-install-verify-integration-report.md) |
| `recipe-run-phases` skill (TASK-018) | **Built** — narrowed scope: sequential ascending multi-phase loop wrapper (`.gsd-recipe/scripts/install-recipe-run-phases.sh`, standalone installer also composed into `install.sh` as a 9th sub-installer); for each phase N in `[start, end]` ascending, checks whether `PLAN.md` already exists and invokes `recipe-plan-phase N` by name first only if missing, then always invokes `recipe-run-phase N` by name — skill-to-skill (Option B), never raw native `gsd-plan-phase`/`gsd-execute-phase`, never `gsd-autonomous`; stops the whole loop immediately on the first phase whose plan step or run step fails, reporting exactly which phase blocked and why; never duplicates Jira sync (already emitted per-phase by the two invoked skills); DAG topo-sort/eligibility gating is explicitly out of scope (parked pending TASK-009); **extended (TASK-035)** with optional auto-range detection from `ROADMAP.md`'s `## Phase N` headings (when `<start>`/`<end>` are both omitted) and an optional `--full` flag that additionally chains `recipe-verify-feature N` → `recipe-review-ship N` → `recipe-settle N` per phase — see [bench/report/recipe-run-phases-integration-report.md](../../bench/report/recipe-run-phases-integration-report.md) and [bench/report/recipe-run-phases-auto-range-integration-report.md](../../bench/report/recipe-run-phases-auto-range-integration-report.md) |
| `recipe-verify-feature` skill (TASK-025) | **Built** — narrowed scope: single-phase gate-and-verify wrapper (`.gsd-recipe/scripts/install-recipe-verify-feature.sh`, standalone installer also composed into `install.sh` as a 10th sub-installer); resolves the phase's tracker issue key, then chains native `gsd-audit-milestone` → `gsd-audit-uat` (each warn-and-skip if inapplicable, never hard-fail, never fabricate a result) → `gsd-verify-work N` directly in the same turn (Option-B precedent); the `gsd-verify-work N` step is explicitly documented as genuinely conversational/interactive — this skill invokes it and then defers entirely to its own live exchange with the operator, never scripting or shortcutting it. Once that conversation concludes, syncs `verify_complete` via `gsd-jira-sync` (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked). Bootstrap Gate A/B, the `gsd-debug` recovery loop, and any benchmark/project-specific grader hook are explicitly out of scope — see [bench/report/recipe-verify-feature-integration-report.md](../../bench/report/recipe-verify-feature-integration-report.md) |
| `recipe-review-ship` skill (TASK-026) | **Built** — gate-and-invoke wrapper (`.gsd-recipe/scripts/install-recipe-review-ship.sh`, standalone installer, composed into `install.sh` as an 11th sub-installer); calls native `gsd-code-review N` directly, syncs `review_complete` by invoking the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked, optional `"In Review"` transition), then calls native `gsd-ship N [--draft]` directly and surfaces the resulting PR link; no distinct sync event for the ship step itself (stays `settled`'s job, TASK-027), no re-verification of `gsd-ship`'s own prerequisite (TASK-025's job), and `draft-github-pr-comment.sh`/`gsd-review`/`gsd-ui-review N` stay explicitly out of scope (informational-only or standalone) — see [bench/report/recipe-review-ship-integration-report.md](../../bench/report/recipe-review-ship-integration-report.md) |
| `recipe-settle` skill (TASK-027) | **Built** — quality-floor settle gate (`.gsd-recipe/scripts/install-recipe-settle.sh`, standalone installer also composed into `install.sh` as a 12th sub-installer); real, scriptable CI check (`gh pr checks`/`gh api .../check-runs`, via its own `--check-ci` mode) plus an explicit, non-skippable, interactive PO-accept gate asked live in the operator's conversation (never a script prompt); syncs `settled` via `gsd-jira-sync` only when both gates pass, never otherwise — see [bench/report/recipe-settle-integration-report.md](../../bench/report/recipe-settle-integration-report.md) |
| `gsd-jira-sync` installer (TASK-028) | **Built** — closes the install-time staging gap: `gsd-jira-sync` previously existed only as documentation (`reference/skills/gsd-jira-sync/SKILL.md`), so `tracker-sync` and every `recipe-*` skill that invokes it "by name" would silently fail to resolve on a fresh target. Adds `.gsd-recipe/templates/gsd-jira-sync-SKILL.md` (canonical source, path references adapted only — documented single-event/Drain-mode workflow unchanged) and `.gsd-recipe/scripts/install-gsd-jira-sync.sh` (standalone, ledger-tracked, mirrors `install-tracker-sync.sh`'s shape; stages the skill only, never touches `.gsd-recipe/config.json`'s `tracker` field or `.planning/config.json`), composed into `install.sh` as a 13th sub-installer — see [bench/report/gsd-jira-sync-installer-integration-report.md](../../bench/report/gsd-jira-sync-installer-integration-report.md) |
| `recipe-sync` skill (TASK-029) | **Built** — one-shot orchestration skill (`.gsd-recipe/scripts/install-recipe-sync.sh`, standalone installer composed into `install.sh` as a 14th sub-installer) wrapping the detect→queue→drain pipeline into a single invoke-by-name command (`recipe-sync [--dry-run]`); step 1 runs `sync-reconcile.sh` directly via `Shell` (real script call, `--dry-run` passed through unchanged, stopping there on dry-run); step 2 invokes the `gsd-jira-sync` skill's own Drain mode by name (`gsd-jira-sync --drain`), never reimplementing `sync-drain-queue.sh`'s subcommands or the `addCommentToJiraIssue` MCP call itself; step 3 reports a combined queued/posted/failed/skipped-duplicate summary. Per `DECISIONS.md` OD-05's "loop-first" framing, implements no internal loop/scheduler/hooks — recurrence is the operator's job or Cursor's own `/loop` automation, composed externally — see [bench/report/recipe-sync-integration-report.md](../../bench/report/recipe-sync-integration-report.md) |
| `recipe-pr-comment` skill (TASK-030) | **Built** — closes the posting gap `draft-github-pr-comment.sh` (TASK-006) deliberately left open. Unlike Jira posting, `gh pr comment` is a real local CLI call, not an MCP call, so the entire draft→idempotency-check→post→ledger pipeline is a single real, standalone, testable script, `bench/runners/post-github-pr-comment.sh` — calls `draft-github-pr-comment.sh` for the body, `sync-ledger.sh` for the idempotency key/dup-check (synthetic `pr-<PR_NUMBER>` issue key when no `--issue` is linked), then the real `gh pr comment --repo <owner/repo> --body-file <tmp>` CLI, appending a `posted` row only after a real `gh` exit `0`; never emits a stamp (`github-events.json` has no `"stamp"` field at all). Thin invoke-by-name skill wrapper delegates entirely to the script (`.gsd-recipe/scripts/install-recipe-pr-comment.sh`, standalone installer composed into `install.sh` as a 15th sub-installer, staging both the skill and the runner under one ledger component) — see [bench/report/recipe-pr-comment-integration-report.md](../../bench/report/recipe-pr-comment-integration-report.md) |
| `recipe-install` skill (TASK-031) | **Built** — the last remaining unbuilt named `recipe-*` skill. Thin, invoke-by-name end-to-end install orchestrator (`.gsd-recipe/scripts/install-recipe-install.sh`, standalone installer composed into `install.sh` as a 16th sub-installer) chaining `recipe-validate-tokens` (TASK-021, informational, never blocks) → a genuine, live, non-skippable human consent gate asked in the operator's own conversation (a different, higher-level gate than `install.sh`'s own `--yes`-skippable nested prompt) → the real `install.sh --yes --target <repo>` (TASK-010, already composing every sub-installer this repo has built) → `recipe-install-verify` (TASK-023, Step 5's checklist) → one combined summary, never fabricating any sub-result. `--uninstall` delegates to `install.sh --uninstall --yes --target <repo>` directly, behind its own equally-explicit live-conversation confirm gate. Never calls `install.sh --record-jira-check` — see [bench/report/recipe-install-integration-report.md](../../bench/report/recipe-install-integration-report.md) |
| `recipe-observe` skill (TASK-032) | **Built** — the true last remaining unbuilt named `recipe-*` skill (`recipe-install`, TASK-031, was believed to be the last one, but this row itself — "All other `recipe-*` wrappers (`recipe-observe`)" — still named one more). Thin, invoke-by-name front door (`.gsd-recipe/scripts/install-recipe-observe.sh`, standalone installer composed into `install.sh` as a 17th sub-installer) for the FOTW observer's (TASK-013) operator-facing lifecycle: `status`/`start`/`stop`/`enable`/`disable`. Adds four new `bench/lib/observer-lib.sh` subcommands (`status` — read-only, always-exit-0 report; `enable`/`disable` — atomic `"enabled"` JSON toggle; `request-stop` — idempotently creates the stop-sentinel file the tick loop's `session_end_triggers.explicit_stop` trigger already watched for before this task). `start` delegates entirely to `fotw-observer-bootstrap` by name — zero new spawn logic. `stop` is a graceful-finalize signal only: it cannot forcibly kill an already-running background `Task` subagent (no such capability exists anywhere in this recipe or in Cursor's own `Task` tool) — the skill's own doc calls this out as its own dedicated section, not a footnote. Never touches `.gsd-recipe/observer-config.json`, `.gsd-recipe/lib/observer-lib.sh`, or `install-observer.sh` at install time — those remain exclusively `install-observer.sh`'s job — see [bench/report/recipe-observe-integration-report.md](../../bench/report/recipe-observe-integration-report.md) |
| `recipe-create-epic` skill (TASK-033) | **Built** — closes the "PRD → Epic" gap: an invoke-by-name skill that reads `docs/PRD.md` (fails closed via `recipe-prd-intake` if absent), resolves the Jira project/issue type (optional flags or live `getVisibleJiraProjects`/`getJiraProjectIssueTypesMetadata` MCP questions), drafts the Epic body via the new `bench/runners/draft-jira-epic.sh` (H1 -> summary with a 255-char truncation, the real PRD template's `## ` sections -> description), asks a soft confirm gate, calls `createJiraIssue` via the Atlassian MCP, links the result into `.planning/STATE.md`'s `## Tracker` section via `bench/lib/parse-state.sh`'s new `init-tracker` write subcommand, and syncs `intake_started` via `gsd-jira-sync` by name — never posts/transitions Jira issues directly. `.gsd-recipe/scripts/install-recipe-create-epic.sh` (standalone installer composed into `install.sh` as an 18th sub-installer, staging both the skill and the runner under one ledger component) — see [bench/report/recipe-create-epic-integration-report.md](../../bench/report/recipe-create-epic-integration-report.md) |
| `recipe-create-phase-tasks` skill (TASK-034) | **Built** — closes TASK-007's own documented "does not call `createJiraIssue`/`createIssueLink`" gap. Extends `create-phase-tasks.sh` with a `list` subcommand (self-heal-then-return-work, sourced from `parse-state.sh dump`) and adds a thin invoke-by-name skill wrapper (`.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh`, standalone installer composed into `install.sh` as a 19th sub-installer) chaining `detect` → `list` → once-per-batch issue-type resolution → a soft confirm gate → per-row `createJiraIssue`+link → `mark-done`/`mark-failed` — see [bench/report/recipe-create-phase-tasks-integration-report.md](../../bench/report/recipe-create-phase-tasks-integration-report.md) |
| `recipe-onboard` skill (TASK-037/054) | **Built** — no source resumes artifact-aware onboarding; an explicit Jira/file/paste/description source starts fresh. After the existing preview gate it archives and clears the prior active branch-local recipe context through TASK-059, then runs intake + project bootstrap without reusing the old PRD, ROADMAP, STATE, plans, summaries, or tracker keys. Jira issue input links the existing issue instead of creating a duplicate Epic. |
| `recipe-workspace` skill (TASK-059) | **Built** — per-branch `.planning/` + untracked `docs/PRD*.md` snapshot/restore through git `post-checkout` and Cursor fallback hooks. Restore clears a branch with no snapshot, preventing cross-branch planning leakage. Manual `save`, `restore`, `archive`, and `status`; `archive` is also the fresh-onboarding switch-out primitive. |
| `recipe-start` skill (TASK-056) | **Built** — first-run coach: after install, type `recipe-start` to see the next friendly command (usually `recipe-onboard`). Read-only unless you answer Yes to invoke it. Resolver: `recipe-next.sh`. |
| `recipe-status` skill (TASK-060) | **Built** — read-only snapshot (branch, PRD/ROADMAP/Epic/phase keys, PLAN/SUMMARY, install and sync hints) plus the same next-step as `recipe-start`. Never invokes another skill. Helper: `recipe-status.sh`. |
| `recipe-help --next` (TASK-038) | **Built** — same resolver as `recipe-start`; default `recipe-help` stays the catalog. Optional `--stuck` FAQ. |
| Install front door (TASK-040) | **Built** — root [README install decision tree](../../README.md#install-decision-tree) is canonical: first install uses `install-recipe-to-target.sh` from the recipe source clone; `recipe-install` is re-run/restage-only after skills exist; next command is `recipe-start`. |
| Clone / reinstall playbook (TASK-041) | **Built** — [CLONE.md](CLONE.md) |
| Install doctor (TASK-044) | **Built** — extends `recipe-install-verify` and `install.sh --verify`: paste snippets list only real staged skills and include restart/confirmation steps; external reinstall refreshes `recipe_source` from the active recipe clone; a live Jira MCP pass is recorded and consumed by a same-turn verify rerun so `INSTALL-VERIFIED.json` needs no separate operator command. `--record-jira-check` remains available for scripts/CI. |
| `recipe-new-project` skill (TASK-036) | **Planned** — repo-bootstrap wrapper around native `gsd-new-project`/`gsd-import`; catalogued (`bench/lib/capability-schema.sh`) and referenced by `recipe-onboard`'s own fallback path, but not yet built — no `.gsd-recipe/templates/recipe-new-project-SKILL.md`/installer exists in this repo yet. |
| `dag-build.sh` | **Parked** — future enhancement, not required for the current build sequence; see [BACKLOG.md](BACKLOG.md) |

Implement in **gsd-benchmark** under `bench/runners/`, `bench/recipe/`. Canonical copy: [reference/harness/](reference/harness/).

---

## Benchmarks

| Tier | Doc | Status |
|------|-----|--------|
| **Field benchmarks** (recipe vs ad-hoc on real repos) | [BENCHMARKS.md](BENCHMARKS.md) | **1 recorded** — KB-Evaluations on AgentStudio ([KAN-53](https://netapp.atlassian.net/browse/KAN-53), [PR #465](https://github.com/NetApp-Nemo/AgentStudio/pull/465)): **~3–6 h recipe vs ~2 days ad-hoc** (~2.7–5.3×) |
| **Harness benchmarks** (baseline / GSD / recipe + grader) | [../../PROJECT-SUMMARY.md](../../PROJECT-SUMMARY.md) · [../../KPI-REPORT.md](../../KPI-REPORT.md) | Pending N=5 runs |

Structured records: [benchmarks/](benchmarks/) · Regenerate: `bench/lib/generate-recipe-benchmarks.sh`

Staged on target install as `docs/RECIPE-BENCHMARKS.md` (with `recipe-help`).

---

## Locked rules

- **v1:** Jira + GitHub · Epic → PRD · GSD phase → Jira task
- **Settled** = human PO + **CI green** (not `gsd-verify-work` alone)
- **One orchestrator per repo** — do not run recipe + **ic-*** together
- Open choices: [DECISIONS.md](DECISIONS.md)

---

## Run / smoke test

**Prerequisites:** GSD (`/gsd-health`), Atlassian MCP, `gh auth status`.

**Harness paths (bundled):**

```text
reference/harness/runners/draft-jira-comment.sh
reference/harness/runners/emit-stamp.sh
```

After copy to target repo: `./bench/runners/draft-jira-comment.sh`

**STATE.md** ([schema](contracts/DATA-CONTRACTS.md#state-md)):

```markdown
## Tracker
- epic: PROJ-100
- system: jira
- url: https://your-org.atlassian.net/browse/PROJ-100
- run_id: dev-01
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-101 |
```

**Flow:** native GSD milestones → `gsd-jira-sync <event_id> <issue> [--phase N]`

**P-1:** every row below that fires during a feature needs a Jira comment. Authoritative list: [jira-events.json](reference/harness/recipe/trackers/jira-events.json) · [SKILL.md](reference/skills/gsd-jira-sync/SKILL.md).

| After GSD step | `event_id` | Post to |
|----------------|------------|---------|
| `gsd-new-project` / link epic | `intake_started` | Epic |
| `gsd-discuss-phase N` | `discuss_complete` | Epic |
| `gsd-plan-phase N` (plan-check pass) | `plan_complete` | Phase task |
| Plan revision after plan-checker | `plan_revised` | Phase task |
| `gsd-execute-phase N` start | `execute_started` | Phase task |
| Execute wave (optional) | `execute_wave` | Phase task |
| `gsd-execute-phase N` end | `execute_complete` | Phase task |
| `gsd-verify-work N` | `verify_complete` | Phase task |
| `gsd-code-review N` | `review_complete` | Phase task |
| `gsd-extract-learnings N` | `learning_stored` | Phase task |
| PO + CI green | `settled` | Epic |
| Rework requested | `reopened` | Phase task |

```bash
# Bundled harness (from docs/netapp-recipe/):
reference/harness/runners/draft-jira-comment.sh plan_complete PROJ-101 --phase 1
# After copy to gsd-benchmark / target repo:
./bench/runners/draft-jira-comment.sh plan_complete PROJ-101 --phase 1
gsd-jira-sync plan_complete PROJ-101 --phase 1
```

Native GSD detail: [GSD-COMMANDS.md](GSD-COMMANDS.md) (bundled subset).

---

## Commands

### Built

| Command | Notes |
|---------|--------|
| `gsd-jira-sync` | [SKILL.md](reference/skills/gsd-jira-sync/SKILL.md) · events: [jira-events.json](reference/harness/recipe/trackers/jira-events.json) |
| `recipe-run-phase N [--wave W]` (TASK-024) | Gate-and-invoke single-phase execute wrapper — [.gsd-recipe/templates/recipe-run-phase-SKILL.md](../../.gsd-recipe/templates/recipe-run-phase-SKILL.md) · [report](../../bench/report/recipe-run-phase-integration-report.md) |
| `recipe-plan-phase N` (TASK-017) | Gate-and-invoke single-phase plan wrapper — [.gsd-recipe/templates/recipe-plan-phase-SKILL.md](../../.gsd-recipe/templates/recipe-plan-phase-SKILL.md) · [report](../../bench/report/recipe-plan-phase-integration-report.md) |
| `recipe-validate-tokens` (TASK-021) | Standalone GitHub + Jira/Atlassian credential check — [.gsd-recipe/templates/recipe-validate-tokens-SKILL.md](../../.gsd-recipe/templates/recipe-validate-tokens-SKILL.md) · [report](../../bench/report/recipe-validate-tokens-integration-report.md) |
| `recipe-bootstrap-knowledge [--fast]` (TASK-022) | Idempotent knowledge bootstrap/refresh wrapper — [.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md](../../.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md) · [report](../../bench/report/recipe-bootstrap-knowledge-integration-report.md) |
| `recipe-install-verify` (TASK-023) | Post-install Step-5 verification checklist — [.gsd-recipe/templates/recipe-install-verify-SKILL.md](../../.gsd-recipe/templates/recipe-install-verify-SKILL.md) · [report](../../bench/report/recipe-install-verify-integration-report.md) |
| `recipe-run-phases [<start> <end>] [--full]` (TASK-018, extended TASK-035) | Sequential ascending multi-phase loop wrapper, with optional `ROADMAP.md`-based auto-range detection and an optional `--full` verify→review→settle chain per phase — [.gsd-recipe/templates/recipe-run-phases-SKILL.md](../../.gsd-recipe/templates/recipe-run-phases-SKILL.md) · [report](../../bench/report/recipe-run-phases-integration-report.md) · [auto-range report](../../bench/report/recipe-run-phases-auto-range-integration-report.md) |
| `recipe-verify-feature N` (TASK-025) | Gated single-phase verify wrapper (audit-milestone → audit-uat → conversational verify-work → Jira sync) — [.gsd-recipe/templates/recipe-verify-feature-SKILL.md](../../.gsd-recipe/templates/recipe-verify-feature-SKILL.md) · [report](../../bench/report/recipe-verify-feature-integration-report.md) |
| `recipe-review-ship N [--draft]` (TASK-026) | Gate-and-invoke single-phase review-and-ship wrapper — [.gsd-recipe/templates/recipe-review-ship-SKILL.md](../../.gsd-recipe/templates/recipe-review-ship-SKILL.md) · [report](../../bench/report/recipe-review-ship-integration-report.md) |
| `recipe-settle` (TASK-027) | Quality-floor settle gate: real `gh`-based CI check + non-skippable human PO-accept gate — [.gsd-recipe/templates/recipe-settle-SKILL.md](../../.gsd-recipe/templates/recipe-settle-SKILL.md) · [report](../../bench/report/recipe-settle-integration-report.md) |
| `gsd-jira-sync` (TASK-028) | Posts GSD lifecycle milestones as Jira comments/transitions via Atlassian MCP (single-event + Drain mode); now installable by name, closing the staging gap every `recipe-*` skill's "invoke `gsd-jira-sync`" instruction assumed — [.gsd-recipe/templates/gsd-jira-sync-SKILL.md](../../.gsd-recipe/templates/gsd-jira-sync-SKILL.md) · [report](../../bench/report/gsd-jira-sync-installer-integration-report.md) |
| `recipe-sync [--dry-run]` (TASK-029) | One-shot detect→queue→drain sync pass wrapping `sync-reconcile.sh` + `gsd-jira-sync --drain`; never loops/schedules/hooks itself (OD-05) — [.gsd-recipe/templates/recipe-sync-SKILL.md](../../.gsd-recipe/templates/recipe-sync-SKILL.md) · [report](../../bench/report/recipe-sync-integration-report.md) |
| `recipe-pr-comment <event_id> <pr_number> --phase N [...]` (TASK-030) | Real, scriptable draft→idempotency-check→post→ledger GitHub PR lifecycle comment poster; delegates entirely to `bench/runners/post-github-pr-comment.sh` (a plain local `gh pr comment` CLI call, never MCP) — [.gsd-recipe/templates/recipe-pr-comment-SKILL.md](../../.gsd-recipe/templates/recipe-pr-comment-SKILL.md) · [report](../../bench/report/recipe-pr-comment-integration-report.md) |
| `recipe-install [--target <path>] [--uninstall]` (TASK-031) | Re-run/restage only after skills already exist. **Do not type it for first install:** run `./bench/runners/install-recipe-to-target.sh --target /path/to/product --yes` from the recipe source clone, then invoke `recipe-start` — [decision tree](../../README.md#install-decision-tree) · [.gsd-recipe/templates/recipe-install-SKILL.md](../../.gsd-recipe/templates/recipe-install-SKILL.md) · [report](../../bench/report/recipe-install-integration-report.md) |
| `recipe-observe <status\|start\|stop\|enable\|disable>` (TASK-032) | Thin front door for the FOTW observer's operator-facing lifecycle; `start` delegates to `fotw-observer-bootstrap` by name, `status`/`enable`/`disable`/`stop` delegate to new `observer-lib.sh` subcommands — `stop` is a graceful-finalize signal only, it cannot forcibly kill an already-running observer subagent — [.gsd-recipe/templates/recipe-observe-SKILL.md](../../.gsd-recipe/templates/recipe-observe-SKILL.md) · [report](../../bench/report/recipe-observe-integration-report.md) |
| `recipe-create-epic [--project KEY] [--issue-type NAME] [--force]` (TASK-033) | PRD → Jira Epic bridge: drafts summary/description from `docs/PRD.md` (`bench/runners/draft-jira-epic.sh`), resolves project/issue type live via MCP if not passed, creates the Epic via `createJiraIssue`, links it into `.planning/STATE.md`'s `## Tracker` section (`parse-state.sh init-tracker`), and syncs `intake_started` via `gsd-jira-sync` — [.gsd-recipe/templates/recipe-create-epic-SKILL.md](../../.gsd-recipe/templates/recipe-create-epic-SKILL.md) · [report](../../bench/report/recipe-create-epic-integration-report.md) |
| `recipe-create-phase-tasks [--issue-type NAME]` (TASK-034) | Agent-mediated phase-task creation: `detect` → `list` (self-heals anything already linked out-of-band) → once-per-batch issue-type resolution → soft confirm gate → per-row `createJiraIssue`+link → `mark-done`/`mark-failed` — [.gsd-recipe/templates/recipe-create-phase-tasks-SKILL.md](../../.gsd-recipe/templates/recipe-create-phase-tasks-SKILL.md) · [report](../../bench/report/recipe-create-phase-tasks-integration-report.md) |
| `recipe-onboard [<PRD source>] [--project KEY] [--issue-type NAME] [--force] [--skip-tracker]` (TASK-037) | Single onboarding orchestrator: one preview-then-confirm gate, then chains PRD intake → project bootstrap → create Epic **or link an existing Jira issue** → optional phase tasks — stops on first failure/decline. PRD source may be a Jira key/URL. — [.gsd-recipe/templates/recipe-onboard-SKILL.md](../../.gsd-recipe/templates/recipe-onboard-SKILL.md) |
| `recipe-start` (TASK-056) | First-run coach — prints the next Cursor command; optional Yes to invoke it — [.gsd-recipe/templates/recipe-start-SKILL.md](../../.gsd-recipe/templates/recipe-start-SKILL.md) |
| `recipe-status` (TASK-060) | Read-only project snapshot plus shared next-step recommendation — [.gsd-recipe/templates/recipe-status-SKILL.md](../../.gsd-recipe/templates/recipe-status-SKILL.md) |
| `recipe-help [--next] [--stuck]` (TASK-038) | Catalog tour; `--next` is the same coach as `recipe-start`; `--stuck` covers clone, assignee, and Jira status — [.gsd-recipe/templates/recipe-help-SKILL.md](../../.gsd-recipe/templates/recipe-help-SKILL.md) |
| Native GSD | `gsd-new-project`, `gsd-discuss-phase`, … — [GSD-COMMANDS.md](GSD-COMMANDS.md) |

### Spec (`recipe-*`)

`recipe-onboard` (TASK-037) has moved to **Built** above. `recipe-new-project` (TASK-036) remains
the one outstanding named `recipe-*` skill still spec-only — see its own **Planned** row in the
Built-vs-spec table above; `recipe-onboard`'s own project-bootstrap step falls back to native
`gsd-new-project` directly whenever `recipe-new-project` isn't staged, so onboarding is fully
functional today even without it. Every other named `recipe-*` skill is **Built** — see the
Built-vs-spec table above.

`recipe-run-phase` (singular, TASK-024) and `recipe-plan-phase` (TASK-017) have moved to **Built**
above — `recipe-run-phase` was previously missing from this Spec table entirely (this table only
ever listed `recipe-run-phases`, plural, TASK-018, the not-yet-built multi-phase loop wrapper);
`recipe-plan-phase` is removed from this row for the same reason it was listed here in the first
place — it's no longer spec-only. `recipe-run-phases` (TASK-018), `recipe-verify-feature`
(TASK-025), and `recipe-settle` (TASK-027) have likewise moved to **Built** above and are removed
from this table for the same reason; `recipe-review-ship` (TASK-026) was never separately
enumerated here. `recipe-sync` (TASK-029) and `recipe-pr-comment` (TASK-030) have moved to **Built**
above too and are removed from this table for the same reason. `recipe-install` (TASK-031) and
`recipe-observe` (TASK-032, previously p2/post-pilot per `OBSERVER-LLD.md`) have likewise moved to
**Built** above and are removed from this table for the same reason — `recipe-observe` was the true
last remaining unbuilt named `recipe-*` skill; every named `recipe-*` item in this spec is now
**Built**. `recipe-prd-intake` was also removed from this table as part of this cleanup pass — it
had remained listed here as still-spec even though it was already independently marked **Built**
further up this doc; that inconsistency is now resolved, and the table above (with this note) is the
single source of truth for `recipe-prd-intake`'s status.

---

## Doc map

| Doc | Purpose |
|-----|---------|
| [SANDBOX.md](SANDBOX.md) | Dummy external repo for pickup + unbiased tester |
| [CLONE.md](CLONE.md) | Team clone / reinstall playbook (TASK-041) |
| [GSD-COMMANDS.md](GSD-COMMANDS.md) | Native GSD subset (self-contained) |
| [AGENTS.md](AGENTS.md) | Agent boot sequence + constraints |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Phase model (p0–p3), tracker layout |
| [BACKLOG.md](BACKLOG.md) | Implementation tasks (start Wave 1) — priority-ranked |
| [CONTROL-GROUP.md](CONTROL-GROUP.md) | Persona control-group evaluation (2026-08-18) → priorities + new tasks |
| [DECISIONS.md](DECISIONS.md) | Locked + open decisions |
| [BENCHMARKS.md](BENCHMARKS.md) | Field + harness benchmark catalog |
| [PILOT-EVIDENCE.md](PILOT-EVIDENCE.md) | Redirect to BENCHMARKS.md |
| [DATA-CONTRACTS.md](contracts/DATA-CONTRACTS.md) | Schemas (STATE, ledger, config) |
| **lld/** | INSTALL · RUNTIME · TRACEABILITY · OBSERVER · PLANNING-POLICY · FAILURE-MATRIX |
| **reference/** | Harness scripts, JSON catalogs, templates, skills |

---

## Verification (P-1–P-3)

| # | Criterion |
|---|-----------|
| P-1 | Milestone Jira comments on correct issue (epic vs phase task) |
| P-2 | Re-run sync → `duplicate_skipped`, no duplicate posts |
| P-3 | Comments align with artifact timing (same session if manual sync) |

Failures: [lld/FAILURE-MATRIX.md](lld/FAILURE-MATRIX.md)
