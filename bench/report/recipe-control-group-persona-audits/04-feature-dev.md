## Persona

- **Mid/senior feature developer** delivering a multi-phase feature end-to-end: onboard → bootstrap → plan → run → verify → ship → settle → sync.
- Goal: one feature, 3–5 ROADMAP phases, Jira epic + phase tasks, PRs per phase, PO sign-off at settle.
- Assumes install + `recipe-validate-tokens` already done; working in Cursor Agent by invoking `recipe-*` by name.

## Happy path command sequence

- `recipe-validate-tokens` → `recipe-onboard` (or step-by-step intake/epic/tasks) → **`recipe-bootstrap-knowledge`** (once per feature / after major repo change).
- **Split pattern** (README example): Phase 1 manual, phases 2→N batched:
  - `recipe-plan-phase 1` **AND** `recipe-run-phase 1` → `recipe-verify-feature 1` → `recipe-review-ship 1` → `recipe-settle 1`
  - `recipe-run-phases 2 5 --full` (plan-if-missing + run + verify + ship + settle per phase)
- **Monolithic alternative**: `recipe-run-phases 1 5 --full` instead of the split — not additive with it.
- **Default loop without `--full`**: `recipe-run-phases N M` = plan-if-missing + run only; verify/ship/settle are separate manual steps.
- End-of-loop hygiene: `recipe-sync` / `tracker-sync` as needed.
- Ad-hoc during plan/execute: `/gsd-graphify query <term>` (optional; bootstrap already ran `/gsd-graphify build`).

## Friction / problems (P0/P1/P2 + evidence)

**P0**

- **No batch plan-only workflow** — `recipe-run-phases` always invokes `recipe-run-phase N` after any missing plan; no `recipe-plan-phases` exists (only repeated `recipe-plan-phase N` calls). Evidence: `recipe-run-phases-SKILL.md` §4.c "always invoke `recipe-run-phase`."
- **Double-work trap if AND/OR rules ignored** — README warns: after `recipe-run-phases 2 5 --full`, do not also run `recipe-plan-phase 2` … `recipe-run-phase 5`. Evidence: README "How plan-phase, run-phase, and run-phases relate" table.
- **`recipe-settle` hard-blocks on CI ≠ PASS** — `CI: WARN` treated like FAIL; no PO prompt, no Jira sync. Evidence: `recipe-settle-SKILL.md` step 3 + `FAILURE-MATRIX.md` "CI red at settle gate."

**P1**

- **`--full` is opt-in but easy to miss** — without it, `recipe-run-phases` stops after execute; developer may assume verify/ship/settle ran. Evidence: `recipe-run-phases-SKILL.md` §A default = plan+run only.
- **Split vs monolithic workflow not obvious at invoke time** — README documents both; no `recipe-help --next` situational guide yet (TASK-038 planned). Evidence: BACKLOG TASK-038.
- **`depends_on` declared but never enforced** — sequential numeric order only; DAG gating parked (TASK-009). Evidence: all plan/run skills print reminder only; `DECISIONS.md`.
- **`recipe-verify-feature` emits `verify_complete` even when audits skipped** — `gsd-audit-milestone` / `gsd-audit-uat` warn-and-skip; only `gsd-verify-work` is blocking in `--full` loop. Gap between "verify ran" stamp and audit gaps undocumented for operators.
- **`recipe-review-ship` does not re-check verify pass** — relies on `gsd-ship` native prerequisite; can fail mid-chain after code review + Jira `review_complete` already posted. Evidence: `recipe-review-ship-SKILL.md` §B/C step 4.
- **AGENTS.md vs recipe-wrapper contradiction** — AGENTS.md: "do not invoke `gsd-plan-phase` on user's behalf"; recipe skills explicitly call native GSD same-turn (Option B). Confusing for developers reading AGENTS.md first.

**P2**

- **Graphify split across three surfaces** — no `recipe-graphify`; install script + bootstrap + ad-hoc query. Evidence: README "Graphify — when and where."
- **`recipe-run-phases` cannot pass `--wave`** — whole-phase only; wave debugging requires per-phase `recipe-run-phase N --wave W`.
- **Soft compliance gates asymmetric in loop** — plan-policy decline in `recipe-plan-phase` does not fail loop if PLAN.md exists; decline in `recipe-run-phase` does fail loop. Evidence: `recipe-run-phases-SKILL.md` "Why plan-existence, not soft-gate outcomes."
- **`recipe-new-project` catalog status "planned"** but onboard chain depends on it — minor trust gap in RECIPE-COMMANDS.md vs onboard flow.

## Command confusion matrix (pairs people mix up)

| Pair | Confusion | Correct rule |
|------|-----------|----------------|
| `recipe-plan-phase N` vs `recipe-run-phase N` | Same thing / either order | **AND**, same phase: plan **then** run |
| `recipe-run-phase N` vs `recipe-run-phases A B` | Plural = faster single-phase | Plural = **loop** over range; always runs execute |
| `recipe-run-phases` vs `recipe-run-phases --full` | `--full` is default | Default = plan+run only; `--full` adds verify→ship→settle |
| `recipe-run-phases 1 5 --full` vs split (P1 manual + `2 5 --full`) | Can combine both | **OR** — pick one pattern; split is documented alternative |
| `recipe-plan-phase N` vs `gsd-plan-phase N` | Skip recipe wrapper | Use **recipe-** variant for tracker sync + policy gate |
| `recipe-verify-feature N` vs `gsd-verify-work N` | Verify = one-shot command | Recipe chains audits + **live conversational** UAT |
| `recipe-review-ship N` vs `recipe-settle N` | Ship = done | Ship opens PR; **settle** = CI green + PO accept |
| `recipe-bootstrap-knowledge` vs `/gsd-graphify build` | Duplicate graphify step | Bootstrap bundles map + graphify + optional ingest |
| `recipe-onboard` vs step-by-step intake/epic/tasks | Must run all separately | Onboard chains skips-if-exists; equivalent to table steps |
| `recipe-sync` vs `gsd-jira-sync` | Same sync | `recipe-sync` = detect→queue→drain; `gsd-jira-sync` = single event |

## Failure modes poorly documented

- **UAT rejected in `gsd-verify-work`** — `--full` stops loop; recovery path (fix → re-run verify vs re-run phase) not in README quick start; only in skill §4.d.
- **CI red at settle** — blocks with no Jira `settled`; fix-and-retry documented in skill/FAILURE-MATRIX but not README delivery table.
- **PO decline at settle** — no sync; no guidance on reopening PR or Jira transition rollback.
- **`gh` missing/unauthenticated at settle** — degrades to `CI: FAIL`; not surfaced in prerequisites table (only "soft" for install).
- **`gsd-ship` unmet verify prerequisite** — fails after `review_complete` already synced; no doc on whether to re-verify or manual ship.
- **Tracker/MCP fail-open everywhere except settle CI** — work continues without Jira stamps; operator may think sync happened. Fail-open is in skills but not README.
- **Bootstrap Gate A/B + `gsd-debug` loop** — in RUNTIME-LLD §3.c but explicitly out of scope for `recipe-verify-feature`; brownfield repos hit env failures with no recipe wrapper.
- **Partial `--full` never allowed** — verified-but-not-shipped stops whole range; no "resume from ship" flag on `recipe-run-phases`.
- **Auto-range `recipe-run-phases --full` with wrong ROADMAP headings** — fails closed if no `## Phase N — Title` headings; heading grammar mismatch undocumented in README.

## Suggested improvements

- Add **`recipe-help --next`** (TASK-038) — artifact-presence → one recommended command; highest leverage for stuck developers.
- Add README **decision tree**: "one phase manual" vs "`run-phases --full`" vs "plan-only (repeat `recipe-plan-phase`)" with explicit **no batch plan-only** callout.
- Resolve **AGENTS.md vs Option-B** — one line: "recipe-* wrappers may call native GSD when operator invoked the wrapper."
- Document **`--full` default-off** prominently in delivery table footnote.
- Add **recovery playbook** rows: UAT rejected → `recipe-run-phase N` or fix plans; CI red → fix + `recipe-settle N`; ship blocked → `recipe-verify-feature N` then `recipe-review-ship N`.
- Consider **`recipe-run-phases --plan-only`** or `--through plan` flag if "plan all then execute" is a real workflow (currently unsupported intentionally).
- Surface **`depends_on` manual ordering** in README AND/OR section — "range must respect dependencies; recipe does not topo-sort."
- Clarify **`verify_complete` vs audit gaps** — stamp fires after conversational UAT, not after milestone audit pass.
- Unify **prerequisites table** — add `gh` as required-for-settle (not just soft-for-install).

[REDACTED]
