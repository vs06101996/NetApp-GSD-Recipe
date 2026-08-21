# Recipe control-group synthesis (persona audits)

**Date:** 2026-08-18  
**Method:** Five parallel doc/skill walkthroughs (repo-agnostic). No live delivery run; findings are usability/control-group signals for recipe performance, not harness KPIs.

> **Canonical write-up:** these raw findings are documented and mapped to priorities + backlog tasks in [`docs/netapp-recipe/CONTROL-GROUP.md`](../../docs/netapp-recipe/CONTROL-GROUP.md). New tasks TASK-040–TASK-046 (control-group) and TASK-047–TASK-053 (Claude Code port, [OD-13](../../docs/netapp-recipe/DECISIONS.md)) are filed in [`BACKLOG.md`](../../docs/netapp-recipe/BACKLOG.md).

| Persona | Agent | Raw report |
|---------|-------|------------|
| Project manager | [PM audit](7504438d-4277-4bec-85c3-811c9d851b0f) | [`01-pm.md`](recipe-control-group-persona-audits/01-pm.md) |
| New developer | [New-dev audit](593b85ec-4223-4894-ad1c-1e2403fe57bd) | [`02-newdev.md`](recipe-control-group-persona-audits/02-newdev.md) |
| Bug fixer | [Bugfixer audit](8376463e-9973-4991-8764-b3e542ec26e9) | [`03-bugfixer.md`](recipe-control-group-persona-audits/03-bugfixer.md) |
| Feature developer | [Feature-dev audit](271a3e4f-3e1f-4e81-ad57-e9d5b0bacb14) | [`04-feature-dev.md`](recipe-control-group-persona-audits/04-feature-dev.md) |
| Platform / DevX | [Platform audit](26cd3622-8b61-44df-8ef4-7104c81dfba5) | [`05-platform.md`](recipe-control-group-persona-audits/05-platform.md) |

---

## Cross-persona themes (ranked)

### P0 — blocks first success or misleads operators

1. **Install front-door is fractured** (New-dev, Platform)  
   README bash runner vs `recipe-install` vs `install.sh` vs `bin/recipe` — chicken-and-egg: `recipe-install` needs skills that only exist after install.

2. **Local-only scaffold ⇒ every clone is recipe-less** (Platform, New-dev)  
   `.gsd-recipe/`, `.planning/`, `.templates/`, `skills/` gitignored on targets — correct for feature PRs, but team playbook (“re-run install per clone”) is under-documented as a first-class ops requirement.

3. **No situational “what next”** (all personas; validates TASK-038)  
   `recipe-help` forbids next-step suggestions; README calls it a guided tour. Stuck operators have no coach.

4. **No bugfix / light path** (Bugfixer)  
   Same Epic→PRD→phase→7-section PLAN weight as a full feature; `gsd-quick` exists but is outside recipe traceability.

5. **No plan-all-without-execute** (Feature-dev)  
   `recipe-run-phases` always executes after planning; no `--plan-only`.

### P1 — high friction / silent failure later

| Issue | Who hit it | Backlog / fix lean |
|-------|------------|-------------------|
| MCP + `agent_skills` print-only; phantom skill paths in snippet | Platform | Fix snippet; document paste checklist |
| `recipe_source` write-once, stale across machines | Platform | Update on reinstall / env override |
| Jira verify split (`pending` → agent → `--record-jira-check`) | PM, Platform | Collapse into `recipe-install-verify` / doctor |
| Onboard still pushes Epic + phase tasks for tiny work | Bugfixer, PM | Optional `--skip-tracker` / light onboard |
| `--full` opt-in easy to miss on `recipe-run-phases` | Feature-dev | Docs + TASK-038 tip |
| AND/OR plan/run/run-phases dense | New-dev, Feature-dev | One cheat-sheet visual |
| PRD template too heavy; no swap/light template | Bugfixer | **TASK-039** |
| Graphify soft-fail vs bootstrap “always run graphify” mismatch | Platform | Align skill with README warn-skip |
| `recipe-new-project` catalog “planned” vs onboard uses it | New-dev, Feature-dev | Reconcile status |

### P2 — polish

- AgentStudio / TASK-ID jargon in onboarding docs  
- Dual verify paths (`install.sh --verify` vs `recipe-install-verify`)  
- Gitignore verify list missing `graphify-out/`  
- AGENTS.md “don’t invoke GSD” vs recipe Option-B wrappers  
- Sync trio (`recipe-sync` / `tracker-sync` / `gsd-jira-sync`)  

---

## What the recipe does well (control positives)

- Artifact-aware `recipe-onboard` skips (PRD / ROADMAP / Epic / phase tasks)  
- Fail-open tracker sync on plan/run (work continues without Jira)  
- Soft planning-policy gates (warn, don’t hard-block)  
- `recipe-settle` quality floor (CI + PO) is clear once found  
- Single-phase `recipe-plan-phase` / `recipe-run-phase` for focused work  
- Discuss not forced (good for bugfix speed)  

---

## Control-group verdict (directional)

| Persona | Recipe fit today | Biggest gap |
|---------|------------------|-------------|
| New developer | Poor until install docs unified + TASK-038 | Front door / stuck coach |
| Platform / DevX | Fair install; weak team clone story | Local-only ops playbook |
| Bug fixer | Usable but over-ceremonial | Light PRD + optional tracker |
| Feature developer | Strong once onboarded | AND/OR + `--full` clarity |
| Project manager | Strong on settle/sync *if* Jira wired | Status when stuck; Jira setup maze |

**Implication for “how recipe performs”:** field speedups (e.g. KB-Evaluations) likely assume an operator who already cleared install + Jira wiring. Control group shows **time-to-first-command** and **stuck recovery** as the main unmeasured losses — exactly what TASK-038 / clearer install docs / TASK-039 target.

---

## Recommended next experiments (still repo-agnostic)

1. **Usability N=5 timed:** same greenfield PRD, five operators (or five persona scripts), measure time-to-first `recipe-plan-phase` and wrong-command count.  
2. **Ship TASK-038 stub** (`recipe-help --next`) before further field pilots.  
3. **Ship TASK-039 light PRD + comment template override** for bugfix arm.  
4. **One-page “Install into any repo”** decision tree in README (replace competing front doors).  
5. **Team clone playbook** one-pager: reinstall per machine vs chore PR to share `.planning/`.

---

## Mapping to backlog already filed

| Finding cluster | Backlog |
|-----------------|---------|
| Situational help / stuck | **TASK-038**, OD-11 |
| Swappable / light templates | **TASK-039**, OD-12 |
| DAG / plan-all / depends_on | TASK-009 (parked); optional `--plan-only` not yet tasked |
| recipe-new-project status | TASK-036 reconcile |

---

## Raw persona files

See [`recipe-control-group-persona-audits/`](recipe-control-group-persona-audits/).
