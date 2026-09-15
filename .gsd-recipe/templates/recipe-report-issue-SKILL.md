---
name: recipe-report-issue
description: "Safely draft and submit a bug, enhancement, or question to the fixed NetApp GSD Recipe GitHub repository. Use when an operator wants to report a recipe problem or request."
---

# recipe-report-issue

Report an issue only to `vs06101996/NetApp-GSD-Recipe`. Never infer or accept a different
repository.

## Invocation

`recipe-report-issue [bug|enhancement|question] [short description] [--dry-run]`

Default type: `bug`.

## Workflow

1. Resolve the installed runner:
   ```bash
   .gsd-recipe/scripts/recipe-paths.sh resolve .gsd-recipe/scripts/report-recipe-issue.sh
   ```
2. Gather only information needed to reproduce the recipe behavior. Do not collect environment
   dumps, repository contents, credentials, tokens, customer data, or unrelated logs.
3. Draft a concise title and collect actual behavior, expected behavior, invoked command, and
   optional context. The runner accepts these as `--description`, `--expected`, `--command`, and
   `--context` and renders the structure represented by
   `.gsd-recipe/templates/recipe-issue-body.template.md`. Use `unknown` where the operator has not
   supplied an answer; do not invent facts. `--body-file` remains available for a deliberately
   pre-filled template.
4. Invoke the runner with `--dry-run`. It redacts common secret forms and local home paths and
   makes no GitHub calls in this mode.
5. Show that exact sanitized preview. Ask a non-skippable yes/no confirmation before any write.
   If the answer is no, delete the temporary file and stop.
6. After yes, invoke the same runner with `--confirmed`. It verifies `gh` authentication, searches
   open and closed issues for an exact normalized title, and creates the issue with
   `gh issue create`.
   - If an exact duplicate is found, show its URL and stop.
   - Use `--allow-duplicate` only after showing that URL and receiving a second explicit yes.
7. Delete any temporary body file and report the URL returned by `gh`.

## Safety and failure behavior

- Never attach files automatically.
- Never include secret values, authorization headers, full environment output, customer names,
  or absolute local home paths.
- Never pass `--confirmed` before the operator has seen the runner's sanitized dry-run output.
- Authentication, repository, duplicate-search, and create failures are fail-closed: print the
  actionable error and do not claim an issue was created.
- This command reports recipe defects; it does not mutate Jira, project planning state, or source
  files.
