**[GSD Recipe] Phase {{PHASE_ID}} task**

- **Epic:** {{EPIC_KEY}} · **Phase:** {{PHASE_ID}} · **Arm:** {{ARM}} · **Run:** {{RUN_ID}}

### Phase
**{{PHASE_TITLE}}**

{{PHASE_GOAL}}

### Tracker linkage
This task tracks GSD phase {{PHASE_ID}} under epic {{EPIC_KEY}} (source: `ROADMAP.md`).
Created by `create-phase-tasks.sh` (TASK-007) — not yet posted to Jira. Once an agent turn
creates this issue (`createJiraIssue`) and verifies its native Parent field (or an explicitly
reported legacy Epic Link compatibility fallback), record the resulting key with:

```
bench/lib/parse-state.sh add-phase-task {{PHASE_ID}} <ISSUE_KEY> --state .planning/STATE.md
```

### Next
`recipe-plan-phase {{PHASE_ID}}` → sync `plan_complete` via `gsd-jira-sync` once planning
completes for this phase.
