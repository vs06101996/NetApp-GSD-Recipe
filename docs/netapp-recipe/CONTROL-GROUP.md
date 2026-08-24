# Control-group evaluation — NetApp GSD Recipe

**Date:** 2026-08-18  
**Status:** Filed into [BACKLOG.md](BACKLOG.md) with priorities · decisions in [DECISIONS.md](DECISIONS.md)  
**Raw synthesis:** [bench/report/recipe-control-group-synthesis.md](../../bench/report/recipe-control-group-synthesis.md)  
**Persona audits:** [bench/report/recipe-control-group-persona-audits/](../../bench/report/recipe-control-group-persona-audits/)

---

## What this is

Five parallel **doc/skill walkthroughs** (repo-agnostic). No live delivery run.

Findings are **usability / control-group signals** for recipe performance — not harness KPIs (P-1–P-3) and not field cycle-time (e.g. KB-Evaluations).

| Persona | Lens | Raw report |
|---------|------|------------|
| Project manager | Jira epic, mid-flight status, settle | [`01-pm.md`](../../bench/report/recipe-control-group-persona-audits/01-pm.md) |
| New developer | First install, what to type | [`02-newdev.md`](../../bench/report/recipe-control-group-persona-audits/02-newdev.md) |
| Bug fixer | Small UI fix, minimal ceremony | [`03-bugfixer.md`](../../bench/report/recipe-control-group-persona-audits/03-bugfixer.md) |
| Feature developer | Full multi-phase delivery | [`04-feature-dev.md`](../../bench/report/recipe-control-group-persona-audits/04-feature-dev.md) |
| Platform / DevX | Install, gitignore, team clones | [`05-platform.md`](../../bench/report/recipe-control-group-persona-audits/05-platform.md) |

---

## Severity legend (same as backlog Priority)

| Priority | Meaning |
|----------|---------|
| **P0** | Blocks first success or actively misleads operators |
| **P1** | High friction or silent failure later |
| **P2** | Polish / jargon / inconsistency |
| **P3** | Parked / deferred / future enhancement |

---

## Cross-persona themes

### P0 — blocks first success

| # | Theme | Personas | Backlog |
|---|-------|----------|---------|
| 1 | **Install front-door fractured** — README bash runner vs `recipe-install` vs `install.sh` vs `bin/recipe`; chicken-and-egg (`recipe-install` needs skills that only exist after install) | New-dev, Platform | **TASK-040** |
| 2 | **Local-only scaffold ⇒ every clone is recipe-less** — correct for feature PRs; team playbook (“re-run install per clone”) under-documented | Platform, New-dev | **TASK-041** |
| 3 | **No situational “what next”** — `recipe-help` forbids next-step suggestions; stuck operators have no coach; no post-install first-run tip | All | **TASK-056**, **TASK-038**, OD-11 / OD-19 |
| 4 | **No bugfix / light path** — same Epic→PRD→phase→7-section PLAN weight as a full feature; `gsd-quick` outside recipe traceability | Bugfixer | **TASK-042**, **TASK-039**, OD-12 / OD-15 |
| 5 | **No plan-all-without-execute** — `recipe-run-phases` always executes after planning; no `--plan-only` | Feature-dev | **TASK-043** |

### P1 — high friction / silent failure later

| Issue | Personas | Backlog |
|-------|----------|---------|
| MCP + `agent_skills` print-only; phantom skill paths in paste snippet | Platform | **TASK-044** |
| `recipe_source` write-once, stale across machines | Platform | **TASK-044** |
| Jira verify split (`pending` → agent → `--record-jira-check`) | PM, Platform | **TASK-044** |
| Onboard still pushes Epic + phase tasks for tiny work | Bugfixer, PM | **TASK-042** |
| `--full` opt-in easy to miss on `recipe-run-phases` | Feature-dev | **TASK-045**, TASK-038 tip |
| AND/OR plan/run/run-phases dense | New-dev, Feature-dev | **TASK-045** |
| PRD template too heavy; no swap/light template | Bugfixer | **TASK-039** |
| Graphify soft-fail vs bootstrap “always run graphify” mismatch | Platform | **TASK-045** |
| `recipe-new-project` catalog “planned” vs onboard uses it | New-dev, Feature-dev | **TASK-036** |
| Second PRD / new initiative while ROADMAP+Epic already exist — `recipe-onboard` soft-skips, leaves old planning | Field (multi-PRD repos) | **TASK-054**, OD-17 |
| Agent-generated test/validity dumps pollute feature PRs (not under a gitignored scratch dir) | Field / Platform | **TASK-055**, OD-18 |

### P2 — polish

| Issue | Backlog |
|-------|---------|
| AgentStudio / TASK-ID jargon in onboarding docs | **TASK-046** |
| Dual verify paths (`install.sh --verify` vs `recipe-install-verify`) | **TASK-046** |
| Gitignore verify list missing `graphify-out/` | **TASK-046** |
| AGENTS.md “don’t invoke GSD” vs recipe Option-B wrappers | **TASK-046** |
| Sync trio (`recipe-sync` / `tracker-sync` / `gsd-jira-sync`) clarity | **TASK-046** |

---

## What the recipe does well (control positives)

- Artifact-aware `recipe-onboard` skips (PRD / ROADMAP / Epic / phase tasks)
- Fail-open tracker sync on plan/run (work continues without Jira)
- Soft planning-policy gates (warn, don’t hard-block)
- `recipe-settle` quality floor (CI + PO) is clear once found
- Single-phase `recipe-plan-phase` / `recipe-run-phase` for focused work
- Discuss not forced (good for bugfix speed)

---

## Verdict by persona

| Persona | Recipe fit today | Biggest gap |
|---------|------------------|-------------|
| New developer | Poor until install docs unified + TASK-056 / TASK-038 | Front door / first-run coach |
| Platform / DevX | Fair install; weak team clone story | Local-only ops playbook |
| Bug fixer | Usable but over-ceremonial | Light PRD + optional tracker |
| Feature developer | Strong once onboarded | AND/OR + `--full` clarity |
| Project manager | Strong on settle/sync *if* Jira wired | Status when stuck; Jira setup maze |

**Implication:** Field speedups (e.g. KB-Evaluations ~3–6 h vs ~2 days) likely assume an operator who already cleared install + Jira wiring. Control group shows **time-to-first-command** and **stuck recovery** as the main unmeasured losses — what Wave 5 / Wave 6 target.

---

## Recommended targeting order

Use [BACKLOG.md § Next up](BACKLOG.md#next-up-post-v1-operator-ux--control-group) as the live queue. Directional order from this evaluation:

1. **TASK-056** — `recipe-start` first-run coach (**take first**; ~1.5–2.5 d)
2. **TASK-038** — `recipe-help --next` (reuse resolver; ~0.5–1 d)
3. **TASK-040** — Unify install front door (one-page decision tree) (**Built**; unbiased tester PASS)
4. **TASK-041** — Team clone / reinstall playbook (**Built**)
5. **TASK-039** — Swappable / light templates
6. **TASK-042** — Light / bugfix path (`--skip-tracker`, optional `recipe-quick`)
7. **TASK-054** — Extend `recipe-onboard`: warn + Yes/No overwrite when planning already exists
8. **TASK-055** — Ephemeral test/validation artifacts only under gitignored `.gsd-recipe/scratch/`
9. **TASK-058** — `recipe-update` in-place upgrade (~1.5–2.5 d)
10. **TASK-059** — Per-branch snapshot/restore of gitignored PRD + `.planning/` on checkout
11. **TASK-044** — Install doctor (MCP paste, `recipe_source`, Jira verify collapse) (**Built**; unbiased tester PASS)
12. **TASK-043** — `--plan-only` on `recipe-run-phases`
13. **TASK-045** — Operator cheat-sheet + graphify doc align + `--full` prominence
14. **TASK-036** — Build or reconcile `recipe-new-project` catalog status
15. **TASK-046** — P2 polish cluster
16. **TASK-047 – TASK-051** — Claude Code dual-runtime install MVP (P1; see OD-13)
17. **TASK-052 – TASK-053** — Claude observer hook adapter + pilot runbook (P2)
18. **TASK-057** — DAG parallel conflicts: LLM merge skill spike (~1–2 d; after TASK-009 / OD-20)

### Still-repo-agnostic experiments (not full product yet)

1. Usability N=5 timed: same greenfield PRD; measure time-to-first `recipe-plan-phase` and wrong-command count
2. Re-run control-group after Wave 5 ships
3. **TASK-057** practical spike: two parallel worktrees collide on one file → gated LLM merge vs serialize (see OD-20)

---

## Mapping summary

| Finding cluster | Backlog | Decision |
|-----------------|---------|----------|
| First-run coach + situational next | TASK-056, TASK-038 | OD-11, OD-19 |
| Swappable / light templates | TASK-039 | OD-12 |
| Install front door | TASK-040 | OD-14 |
| Team clone playbook | TASK-041 | (locked: local-only scaffold) |
| Light / bugfix path | TASK-042 | OD-15 |
| Re-init / switch initiative (extend `recipe-onboard` Yes/No overwrite) | TASK-054 | OD-17 |
| Ephemeral test/validation artifacts → gitignored scratch | TASK-055 | OD-18 |
| `--plan-only` | TASK-043 | — |
| In-place recipe update | TASK-058 | OD-21 |
| Per-branch local workspace swap | TASK-059 | OD-22 |
| Install doctor cluster | TASK-044 | OD-16 |
| Operator docs / cheat-sheet | TASK-045 | — |
| P2 polish | TASK-046 | — |
| `recipe-new-project` | TASK-036 | — |
| DAG / depends_on | TASK-009 (parked) | Locked: not required for v1 |
| DAG residual conflicts → LLM merge (not live OT) | TASK-057 | OD-20 |
| Claude Code dual-runtime port | TASK-047 – TASK-053 | OD-13 |

---

## Companion research — Claude Code port (dual-runtime)

Sibling research evaluated running the same recipe under **Claude Code** as well as Cursor. Summary (full decision: [DECISIONS.md OD-13](DECISIONS.md)):

**What ports cleanly**
- Core harness is runtime-agnostic: `.planning/`, `bench/runners/*`, `bench/lib/*`, Jira/GitHub sync, ledger, STATE parsing
- GSD core already supports `--claude` (native command layer is not Cursor-locked)

**What is Cursor-shaped today**
- Recipe skills install under `.cursor/skills/` (Claude Code uses `.claude/skills/` + `.claude/settings.json` for MCP)
- Cannot 1:1 port: Cursor `Task` tool, `/loop` automation, `hooks.json` (vs Claude `settings.json` hooks) — these underpin the FOTW observer

**Port shape (OD-13):** single recipe source, parameterized install paths, `install.sh --runtime cursor|claude|both`.
- **Phase 1 MVP (P1):** runtime-aware install + Claude MCP snippet + GSD `--claude` detection — TASK-047 – TASK-051
- **Phase 3 (P2):** observer hook adapter — TASK-052
- Pilot runbook — TASK-053

**Priority rationale:** Cursor operator-UX gaps (Wave 5 P0) come first; dual-runtime is **P1** — high value for NetApp Claude Code users but not blocking the Cursor path already in field use.
