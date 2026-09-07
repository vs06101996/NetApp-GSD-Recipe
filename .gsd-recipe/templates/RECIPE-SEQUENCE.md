# Recipe command sequence (local)

Staged by recipe install. **Gitignored** (`docs/RECIPE-SEQUENCE.md`) — do not commit this file with product work.

Type commands in Cursor Agent **by name** (not `/slash`). Pick one option in the current segment.

## 1. Onboard

**Jira (default)**

```text
recipe-onboard
```

**No Jira**

```text
recipe-onboard --skip-tracker
```

Optional inputs:

```text
recipe-onboard @path/to/jira-or-confluence-prd.md
recipe-onboard docs/PRD.md
recipe-onboard docs/PRD.md --branch gsd/my-initiative
recipe-onboard docs/PRD.md --no-branch
recipe-onboard --project KEY
```

An explicit source (`KAN-53`, URL, file, paste, or description) starts a **fresh**
onboarding cycle on a new `gsd/<slug>` branch: the previous initiative's planning,
tracker queue/ledger, and readiness state are snapshotted before intake. `--branch NAME`
overrides the name; `--no-branch` archives in place. `recipe-onboard` with no source
resumes the active cycle. Branch checkout swaps context automatically (`recipe-workspace status`).

For a NetApp 15-section Jira/Confluence PRD, start from
`.templates/JIRA-PRD.input.template.md`. It is **input only**; intake maps it via
`.templates/JIRA-PRD.input.MAPPING.md` and writes canonical `docs/PRD.md`.

Artifacts: `docs/PRD.md`, `.planning/ROADMAP.md`, and verified knowledge. Skip-tracker sets
`onboard.skip_tracker` (no Epic) but does not skip knowledge. Onboard also invokes
`fotw-observer-bootstrap` once a PRD exists, including when intake is skipped.

## 2. Plan then run (per phase N)

```text
recipe-plan-phase N
recipe-run-phase N
```

Or a range: `recipe-run-phases`.

## 3. Verify, review, settle

```text
recipe-verify-feature N
recipe-review-ship N
recipe-settle N
```

---

Coach: `recipe-start` · snapshot: `recipe-status` · catalog: `recipe-help`
