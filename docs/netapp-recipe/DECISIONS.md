# Decisions — NetApp GSD Recipe

---

## Locked (v1)

| Decision | Value |
|----------|--------|
| Platforms | Jira + GitHub |
| Tracker mapping | Epic → PRD; GSD phase → Jira task |
| Settled gate | Human PO + CI green |
| Orchestrator | One per repo — **not** recipe + ic-* |
| GSD role | Orchestrator; recipe wraps, does not replace |
| Tier-1 DAG (`dag-build.sh`, TASK-009) | **Not required for v1** — parked as future enhancement (see [BACKLOG.md](BACKLOG.md)); dependent tasks (e.g. TASK-017 `recipe-plan-phase`, TASK-024 `recipe-run-phase`) are narrowed to skip DAG pre-req/post-op gating rather than blocking on it |

---

## Open / deferred

| ID | Topic | Recommendation | Status |
|----|-------|----------------|--------|
| OD-01 | Org KPI thresholds | P-1–P-3 first; org targets after baseline | Open |
| OD-02 | GSD version floor | Pin at install → `INSTALL-VERIFIED.json` | Open |
| OD-03 | Capability vs fallback installer | Capability-first, fallback when unavailable | Open |
| OD-04 | sync-ledger in git | Default gitignore; team override | Open |
| OD-05 | `recipe-sync` trigger | Loop-first; hooks later | Open |
| OD-06 | ic-* + recipe coexistence | Strict mutual exclusion | Open |
| OD-07 | Bitbucket/GitLab | Deferred post-v1 | Deferred |
| OD-08 | pgvector learnings | Optional bridge | Open |
| OD-09 | PR comment cadence | Wave + phase milestones | Open |
| OD-10 | Tier-2 DAG auto agents | Parked until Tier-1 stable | Parked |
