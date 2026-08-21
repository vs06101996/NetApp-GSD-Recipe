## Persona

- **BUG FIXER / HOTFIX engineer** — UI-only fix, 3 screenshots, rough idea already in `docs/PRD.md`, wants **one phase**, minimal gates, ship today.
- Repo-agnostic; recipe already installed; Jira/GitHub available but not the main goal.

---

## Minimal viable recipe path for a bugfix

**Fastest supported path (assuming recipe installed, `docs/PRD.md` exists):**

1. **`recipe-onboard`** — skips PRD intake; still runs missing steps: `gsd-new-project` (if no `.planning/ROADMAP.md`), `recipe-create-epic`, `recipe-create-phase-tasks` (if no tracker rows).
2. **Optional:** `recipe-bootstrap-knowledge` — recommended in `RECIPE-ONBOARD.md`, not hard-required.
3. **`recipe-plan-phase 1`** — produces `PLAN.md`; post-hoc 7-section + Prerequisites soft gate.
4. **`recipe-run-phase 1`** — executes fix; pre-hoc same soft gate.
5. **Ship (manual):** `recipe-review-ship 1` → `recipe-settle` — only if you want full traceability + PO/CI gate.

**Tighter alternative (skip onboard orchestrator):**

- Hand-create `.planning/ROADMAP.md` with **one phase**, link Epic/phase task in `STATE.md`, then **`recipe-plan-phase 1` → `recipe-run-phase 1`** only.
- **Do not** run bare `recipe-run-phases` without args if ROADMAP has multiple phases — auto-detect runs them all.

**Native escape hatch (outside recipe traceability):**

- **`gsd-quick`** — lives in `.planning/quick/`, skips ROADMAP/Epic/Jira recipe wrappers; **not integrated** with recipe Jira sync.

---

## Friction / problems (P0/P1/P2 + evidence)

**P0**

- **No bugfix/quick recipe path** — v1 locked rule: *Epic → PRD → GSD phase → Jira task* (`README.md` § Locked rules); same weight for a CSS fix as a feature.
- **PRD template is feature-sized** — 6 required sections (`PRD.template.md`); screenshots + one sentence still need Problem/Goals/Non-Goals/Requirements/Out of Scope or clarifying questions (`recipe-prd-intake-SKILL.md` § C step 3).
- **7-section PLAN mandatory for execute** — Security, Performance, Learning extraction, filled Prerequisites table checked by `recipe-plan-phase` / `recipe-run-phase` (`PLANNING-POLICY.md` § Mandatory plan sections; soft but noisy for UI-only).

**P1**

- **`recipe-onboard` still pushes full tracker stack** — Epic + per-phase Jira sub-tasks even when PRD exists (`recipe-onboard-SKILL.md` § C steps 5–6; only skips present artifacts).
- **`gsd-new-project` may multi-phase ROADMAP** — one-phase intent not guaranteed at bootstrap (`recipe-onboard` step 4 → native `gsd-new-project`).
- **`recipe-run-phases` (no args) runs every phase** — auto-detect from all `## Phase N` headings (`recipe-run-phases-SKILL.md` § C step 1); easy foot-gun vs `recipe-run-phases 1 1`.
- **`gsd-quick` orphaned from recipe** — no `recipe-quick`, no Jira milestone wiring; traceability gap for small fixes.
- **`recipe-bootstrap-knowledge` before plan** — map-codebase + graphify + ingest is heavy pre-work for a 3-screenshot fix (`RECIPE-ONBOARD.md` § After onboarding).

**P2**

- **`fotw-observer-bootstrap` on PRD intake** — extra side effect even for tiny PRDs (`recipe-prd-intake-SKILL.md` § C step 6).
- **Prerequisites table even with no prior phases** — policy expects rows with `Gap found: none` / `Resolution: n/a`, not omission (`PLANNING-POLICY.md` § Per-phase prerequisite workflow).
- **SPEC/TDD policy for net-new** — may apply if no existing LLD to cite (`PLANNING-POLICY.md` § Supporting artifacts).
- **`recipe-run-phases --full`** — verify → review → settle per phase; PO + CI gate overkill unless you opt in (`recipe-run-phases-SKILL.md` § C step 4.d).

---

## Overkill / ceremony that hurts small fixes

- Full **PRD intake** when `docs/PRD.md` already exists (skipped by onboard, but template still feature-shaped if you re-intake).
- **Epic + phase Jira sub-task** creation for a one-line UI fix (locked v1 traceability model).
- **7 PLAN sections + Prerequisites table** for a screenshot-driven CSS/layout bug.
- **`.knowledge/` + graphify** context pass before planning (`PLANNING-POLICY.md` § Context gathering — soft but steers agents).
- **`recipe-verify-feature`** conversational UAT + **`recipe-settle`** PO accept + CI — appropriate for features, heavy for hotfixes.
- **Multiple confirm gates** — onboard preview, plan-policy warn, run-policy warn, epic confirm, phase-task confirm (all soft, but cumulative).

---

## What works well for bugfixes

- **`recipe-onboard` artifact-aware skips** — existing `docs/PRD.md` → skip intake (`recipe-onboard-SKILL.md` § C step 3).
- **Single-phase wrappers** — `recipe-plan-phase N` / `recipe-run-phase N`; no multi-phase loop required.
- **`gsd-discuss-phase` not forced** — explicitly deferred from onboard; `recipe-prd-intake` won't invoke it (`BACKLOG.md` TASK-037; `recipe-onboard-SKILL.md` § Why recipe-discuss-phase…).
- **Soft planning-policy gates** — warn-and-confirm, never hard-block; operator can proceed (`recipe-run-phase-SKILL.md` § C step 2).
- **Fail-open Jira sync** — missing Epic/phase task → warn, still plan/execute (`recipe-plan-phase-SKILL.md` § B).
- **Skip onboard entirely** if ROADMAP + STATE + Epic + phase row already wired — go straight to plan/run.
- **Native `gsd-quick`** available for truly minimal work (outside recipe KPI/traceability).

---

## Suggested improvements

- **TASK-039 PRD light template** — e.g. `PRD.bugfix.template.md`: Problem, Repro (screenshots), Expected/Actual, Acceptance, Out of scope; resolver in `recipe-prd-intake`.
- **TASK-038 `recipe-help --next`** — detect single-phase ROADMAP + existing PRD → recommend `recipe-plan-phase 1` → `recipe-run-phase 1`, not full onboard.
- **`recipe-quick` wrapper** — thin layer on `gsd-quick` with optional minimal Jira comment (`execute_complete` only) and skip Epic/7-section PLAN when flagged `--bugfix`.
- **Planning-policy tier** — `--light` or bugfix profile: drop Security/Performance/Learning sections; shrink Prerequisites to "N/A — phase 1" single row.
- **Single-phase bootstrap** — `recipe-new-project --single-phase "Fix X"` or onboard flag to avoid multi-phase ROADMAP for hotfixes.
- **Document explicit hotfix path** in `RECIPE-ONBOARD.md` / README delivery section: *PRD exists → 1-phase ROADMAP → optional skip Epic if baseline arm → plan 1 → run 1*.
- **Guard `recipe-run-phases`** — warn when auto-detect range > 1 and no `--force-range` for hotfix contexts.
- **Defer `recipe-bootstrap-knowledge`** — mark optional for phase-1-only / quick work in delivery workflow docs.

[REDACTED]
