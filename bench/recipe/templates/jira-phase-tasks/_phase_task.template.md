**[GSD Recipe] Phase {{PHASE_ID}} task**

- **Epic:** {{EPIC_KEY}} · **Phase:** {{PHASE_ID}} · **Arm:** {{ARM}} · **Run:** {{RUN_ID}}

### Phase
**{{PHASE_TITLE}}**

{{PHASE_GOAL}}

### Tracker linkage
This sub-task tracks GSD phase {{PHASE_ID}} under epic {{EPIC_KEY}} (source: `ROADMAP.md`).
Created by `create-phase-tasks.sh` (TASK-007) — not yet posted to Jira. Once an agent turn
creates this issue (`createJiraIssue`) and links it to the epic (`createIssueLink` or a
parent field), record the resulting key with:

```
bench/lib/parse-state.sh add-phase-task {{PHASE_ID}} <ISSUE_KEY> --state .planning/STATE.md
```

### Next
`gsd-plan-phase {{PHASE_ID}}` → sync `plan_complete` via `gsd-jira-sync` once planning
completes for this phase.
