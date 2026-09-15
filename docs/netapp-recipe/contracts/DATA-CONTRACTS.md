# NetApp GSD Recipe — Data Contracts

**Purpose:** single normative reference for all machine-readable recipe artifacts used by operators, scripts, and Cursor agents.  
**Scope:** contract-first docs for v1 (`jira` + `github`) with recipe metadata under `.gsd-recipe/`.  
**Related:** [README.md](../README.md) · [TRACEABILITY-LLD.md](../lld/TRACEABILITY-LLD.md) · [INSTALL-LLD.md](../lld/INSTALL-LLD.md) · [BACKLOG.md](../BACKLOG.md)

---

## Contract Index (fixed paths)

| Purpose | Path | Contract type |
|---------|------|---------------|
| Tracker linkage + routing source | `.planning/STATE.md` | Markdown schema + rules |
| Recipe runtime configuration | `.gsd-recipe/config.json` | JSON object |
| Recipe runtime configuration schema | `.gsd-recipe/config.schema.json` | JSON Schema (draft-07) |
| Capability manifest | `.gsd-recipe/capability.json` | JSON object |
| Capability manifest schema | `.gsd-recipe/capability.schema.json` | JSON Schema (draft-07) |
| Doc ingest manifest | `.gsd-recipe/ingest-manifest.yaml` | YAML object |
| Sync idempotency ledger | `.gsd-recipe/sync-ledger.jsonl` | JSON Lines (append-only) |
| Sync backlog queue | `.gsd-recipe/sync-queue.jsonl` | JSON Lines (append-only) |
| Install verification marker | `.gsd-recipe/INSTALL-VERIFIED.json` | JSON object |
| Knowledge readiness marker | `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED` | JSON object |
| PRD structure baseline | `.templates/PRD.template.md` | Markdown skeleton (canonical output) |
| Jira/Confluence PRD input skeleton | `.templates/JIRA-PRD.input.template.md` | Markdown skeleton (intake only) |
| Jira/Confluence → canonical PRD mapping | `.templates/JIRA-PRD.input.MAPPING.md` | Markdown guide |
| DAG graph output | `.knowledge/dag/graph.json` | JSON object (runtime output) |
| bare_metal command template | `.templates/bare_metal.template.md` | Markdown template (runtime gate input) |
| Jira event vocabulary | [reference/harness/recipe/trackers/jira-events.json](../reference/harness/recipe/trackers/jira-events.json) (`bench/recipe/trackers/` after copy to gsd-benchmark) | JSON catalog |
| GitHub PR event vocabulary | [reference/harness/recipe/trackers/github-events.json](../reference/harness/recipe/trackers/github-events.json) (`bench/recipe/trackers/` after copy) | JSON catalog |

---

<a id="state-md"></a>
## `.planning/STATE.md`

### Normative schema

Required section order:

1. `## Tracker`
2. `## Phase tasks`

Required fields in `## Tracker`:

- `epic`
- `system`
- `run_id`
- `arm`
- `url`

Optional field:

- `issue` (legacy convenience pointer; not used for event routing)

`## Phase tasks` table schema:

| column | type | required | notes |
|--------|------|----------|-------|
| `phase_id` | integer-like string | yes | unique per row |
| `issue_key` | string | yes | tracker issue for phase comments |

### Copy-paste example

```markdown
## Tracker
- epic: PROJ-100
- issue: PROJ-100
- system: jira
- url: https://your-org.atlassian.net/browse/PROJ-100
- run_id: pilot-01
- arm: recipe

## Phase tasks
| phase_id | issue_key |
|----------|-----------|
| 1 | PROJ-101 |
| 2 | PROJ-102 |
| 3 | PROJ-103 |
```

### Validation rules

1. `## Tracker` must exist exactly once and include all required fields above.
2. `system` must be a supported tracker string for the recipe run (`jira` in v1 for tracker tasks; GitHub remains VCS comment target).
3. `arm` must be set and non-empty (`recipe`, `gsd`, or `baseline` by benchmark convention).
4. `## Phase tasks` table must exist for p1/p3 phase-level events.
5. `phase_id` values must be unique and map to planned phases; duplicates fail validation.
6. `issue_key` must be non-empty for each phase row.
7. Event routing:
   - Epic-routed events: `intake_started`, `discuss_complete`
   - Phase-routed events: `plan_complete`, `plan_revised`, `execute_started`, `execute_wave`, `execute_complete`, `verify_complete`, `review_complete`, `learning_stored`, `settled`, `reopened`
   - Phase-event status roll-up is status-only: active children move a To Do Epic to In Progress;
     `settled` moves its phase task to Done, and the Epic reaches Done only when every phase task
     recorded in this table has Jira status category `done`.
8. Parser behavior for unresolved phase-routed event key: fail non-zero with actionable error.

Validation implementation target: TASK-008 in [BACKLOG.md](../BACKLOG.md) · [INSTALL-LLD.md](../lld/INSTALL-LLD.md).

---

<a id="config-json"></a>
## `.gsd-recipe/config.json`

### Normative fields (v1)

| field | type | required | meaning |
|-------|------|----------|---------|
| `traceability.enabled` | boolean | yes | master switch for sync/reconcile behavior |
| `traceability.reason` | string | yes when disabled | operator reason for disabling traceability |
| `observer.enabled` | boolean | yes | enable/disable p2 observer flow |
| `observer.interval_minutes` | integer | yes when observer enabled | loop interval recommendation |
| `assignee` | string | no | default Jira display name or email for new Epics and phase tasks (`lookupJiraAccountId`) |
| `onboard.skip_tracker` | boolean | no | set by `recipe-onboard --skip-tracker` after PRD + planning succeed without creating Jira issues. `recipe-next` / `recipe-status` treat a missing Epic as intentional, not an incomplete onboard. Do not invent an Epic key in `STATE.md`. |

### Example

```json
{
  "traceability": {
    "enabled": true,
    "reason": ""
  },
  "observer": {
    "enabled": false,
    "interval_minutes": 10
  }
}
```

Strict validation source: `.gsd-recipe/config.schema.json` (TASK-011 in [BACKLOG.md](../BACKLOG.md) · [INSTALL-LLD.md](../lld/INSTALL-LLD.md)) — validates the exact shape above, plus the `tracker` field (optional; defaults to `jira` when absent per `bench/lib/tracker-sync-config.sh`). Validate with `bench/lib/capability-schema.sh validate-config`. Confirmed against a real scratch-repo `install.sh` run — see [capability-config-schema-integration-report.md](../../../bench/report/capability-config-schema-integration-report.md).

---

<a id="capability-json"></a>
## `.gsd-recipe/capability.json`

### Purpose

Static manifest describing which recipe capabilities/skills are installed in *this* target repo — generated by introspecting `.cursor/skills/`, `skills/`, and `.gsd-recipe/ledger.json`. Distinct from `.gsd-recipe/ledger.json`: the ledger tracks install/uninstall *events* per file; `capability.json` is a point-in-time *description* of what's staged right now. Never itself drives install/uninstall.

### Shape

| field | type | required | meaning |
|-------|------|----------|---------|
| `schema_version` | integer | yes | version of this manifest's own shape |
| `generated_at` | RFC3339 string | yes | when `generate-capability` produced this file |
| `recipe` | string | yes | fixed recipe identifier |
| `capabilities[].id` | string | yes | stable capability id (matches its ledger component name where one exists) |
| `capabilities[].task_id` | string | yes | `BACKLOG.md` task id that built this capability |
| `capabilities[].kind` | enum | yes | `installer` \| `cursor-skill` \| `agent-skill` |
| `capabilities[].staged` | boolean | yes | whether it's actually staged in the introspected target right now |
| `capabilities[].version` | string | yes | placeholder — no per-component version-tracking mechanism exists yet (see full schema for caveat) |

Full normative schema: `.gsd-recipe/capability.schema.json` (TASK-011). Generate/validate with `bench/lib/capability-schema.sh generate-capability` / `validate-capability`. Full design rationale: [capability-config-schema-integration-report.md](../../../bench/report/capability-config-schema-integration-report.md).

### Example

```json
{
  "schema_version": 1,
  "generated_at": "2026-07-13T12:14:22Z",
  "recipe": "netapp-gsd-recipe",
  "capabilities": [
    {
      "id": "tracker-sync",
      "task_id": "TASK-014",
      "kind": "cursor-skill",
      "invoke_name": "tracker-sync",
      "staged_path": ".cursor/skills/tracker-sync/SKILL.md",
      "staged": true,
      "ledger_tracked": true,
      "version": "1.0.0"
    }
  ]
}
```

---

<a id="ingest-manifest-yaml"></a>
## `.gsd-recipe/ingest-manifest.yaml`

### Rule

Recipe commands **always** use this fixed manifest path. Operators and wrappers must not pass ad-hoc ingest paths.

### Example manifest

```yaml
version: 1
sources:
  - path: docs/PRD.md
    kind: prd
    format_hint: markdown
    required: false
  - path: .planning/intake/PRD.md
    kind: prd
    format_hint: markdown
    required: false
  - path: code_base_details/
    kind: repo_context
    format_hint: markdown_or_text
    required: false
  - path: docs/
    kind: product_docs
    format_hint: markdown
    required: false
options:
  include_globs:
    - "**/*.md"
  exclude_globs:
    - "**/node_modules/**"
    - "**/.git/**"
```

`gsd-ingest-docs` wrappers should call:

```text
gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml
```

---

<a id="sync-ledger-jsonl"></a>
## `.gsd-recipe/sync-ledger.jsonl`

### Format

One JSON object per line (append-only):

| field | type | required | notes |
|-------|------|----------|-------|
| `key` | string | yes | idempotency key |
| `ts` | RFC3339 string | yes | write timestamp |
| `target` | enum | yes | `jira` or `github` |
| `external_id` | string | no | posted comment id if available |
| `result` | enum | no | `posted` or `duplicate_skipped` |
| `detail` | string | no | optional diagnostics |

Idempotency key canonical shape:

```text
gsd-recipe:{event_id}:phase={N}:wave={W}:commit={SHORT_SHA}:issue={ISSUE_KEY}
```

Omit `wave` and/or `commit` when not applicable.

### Example lines

```json
{"key":"gsd-recipe:plan_complete:phase=1:issue=PROJ-101","ts":"2026-07-04T08:15:22Z","target":"jira","external_id":"jira-comment-88421","result":"posted"}
{"key":"gsd-recipe:execute_wave:phase=1:wave=2:commit=7af12cd:issue=PROJ-101","ts":"2026-07-04T10:41:03Z","target":"github","external_id":"gh-pr-comment-4509","result":"posted"}
{"key":"gsd-recipe:execute_wave:phase=1:wave=2:commit=7af12cd:issue=PROJ-101","ts":"2026-07-04T10:46:03Z","target":"github","result":"duplicate_skipped","detail":"already present in ledger"}
```

---

<a id="sync-queue-jsonl"></a>
## `.gsd-recipe/sync-queue.jsonl`

### Format

One queued event request per line:

| field | type | required | notes |
|-------|------|----------|-------|
| `queued_at` | RFC3339 string | yes | enqueue time |
| `event_id` | string | yes | must exist in `jira-events.json` (or tracker equivalent) |
| `phase_id` | integer/string | no | required for phase-routed events |
| `issue_key` | string | yes | resolved from `STATE.md` |
| `target` | enum | yes | `jira` or `github` |
| `template` | string | yes | template file id/path |
| `key` | string | yes | idempotency key |
| `status` | enum | yes | `queued`, `done`, `failed` |
| `error` | string | no | last failure detail |

### Example line

```json
{"queued_at":"2026-07-04T11:02:10Z","event_id":"execute_complete","phase_id":1,"issue_key":"PROJ-101","target":"jira","template":"execute_complete.md","key":"gsd-recipe:execute_complete:phase=1:issue=PROJ-101","status":"queued"}
```

---

<a id="install-verified-json"></a>
## `.gsd-recipe/INSTALL-VERIFIED.json`

### Format

| field | type | required | notes |
|-------|------|----------|-------|
| `verified_at` | RFC3339 string | yes | install verification time |
| `gsd_version` | string | yes | pinned/observed version |
| `tracker` | string | yes | v1 expected `jira` |
| `vcs` | string | yes | v1 expected `github` |
| `run_id` | string | no | optional pilot run reference |

### Example

```json
{
  "verified_at": "2026-07-04T12:00:00Z",
  "gsd_version": "1.2.0",
  "tracker": "jira",
  "vcs": "github",
  "run_id": "pilot-01"
}
```

---

## `.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED`

Written only by `recipe-bootstrap-knowledge` after native map output and graphify both verify.
Install-time `.knowledge/` placeholders never create this marker.

Readiness requires **all** of:
- this file with `"status": "ready"` (written only by `recipe-verify-knowledge.sh --write-marker`)
- at least two substantive `.planning/codebase/*.md` files from native map-codebase
- at least one non-empty graph file under `.planning/graphs/` or `graphify-out/`
- functional `graphify` on PATH (no-op stubs rejected)

Guardrail scripts (staged under `.gsd-recipe/scripts/`):
- `recipe-verify-knowledge.sh` — check / `--write-marker`
- `recipe-verify-planning.sh` — after `recipe-new-project`
- `graphify-probe.sh` — stub detection (sourced by verify-knowledge)

`recipe-status` / `recipe-next` use the same rules via `recipe_knowledge.py`.

```json
{"status":"ready","completed_at":"2026-08-24T08:00:00Z"}
```

Required fields: `status` (must equal `"ready"`) and `completed_at` (RFC3339 UTC).

---

<a id="prd-template-md"></a>
## `.templates/PRD.template.md`

**Canonical output** for `recipe-prd-intake` → `docs/PRD.md`. Required sections:

```markdown
# PRD: {Feature / Project Name}

## Problem

## Goals

## Non-Goals

## Requirements

## Out of Scope

## Open Questions (optional)
```

---

<a id="jira-prd-input-template-md"></a>
## `.templates/JIRA-PRD.input.template.md`

**Input only** — matches the NetApp Confluence/Jira PRD shape (15 numbered sections).
Operators paste exports or fill this locally; `recipe-prd-intake` maps it to
`.templates/PRD.template.md` using `.templates/JIRA-PRD.input.MAPPING.md`.

Official source: [NetApp Confluence PRD Template](https://netapp.atlassian.net/wiki/spaces/CLOUDVOL/pages/108168914/PRD+Template).

Never write this 15-section form to `docs/PRD.md`.

---

<a id="jira-prd-input-mapping-md"></a>
## `.templates/JIRA-PRD.input.MAPPING.md`

Normative section map from Jira/Confluence input → canonical PRD sections (Problem,
Goals, Non-Goals, Requirements, Out of Scope, Open Questions). Consumed by
`recipe-prd-intake` at intake time.

---

## Additional fixed-path contracts

<a id="dag-graph-json"></a>
### `.knowledge/dag/graph.json` (runtime output)

Minimum shape expected by wrappers:

```json
{
  "version": 1,
  "nodes": [
    { "phase_id": 1, "name": "Phase 1", "depends_on": [] },
    { "phase_id": 2, "name": "Phase 2", "depends_on": [1] }
  ]
}
```

Produced by `dag-build.sh` (TASK-009); consumed by `recipe-run-phases`.

<a id="bare-metal-template-md"></a>
### `.templates/bare_metal.template.md`

Template contract:

```markdown
## Bootstrap commands (repo-specific — human-authored)
- install_deps: <command>
- build: <command>
- unit_tests: <command>
- smoke: <command>
- dev_server: <command> (optional)

## Success criteria
- All commands exit 0
- smoke output contains: <substring> (optional)
```

---

<a id="event-vocabulary-source"></a>
## Event vocabulary source

Canonical Jira event IDs and routing vocabulary:

- [reference/harness/recipe/trackers/jira-events.json](../reference/harness/recipe/trackers/jira-events.json) (bundled copy; `bench/recipe/trackers/jira-events.json` in gsd-benchmark)

Any parser/reconciler implementation for v1 must treat this file as authoritative for valid Jira `event_id` values.

<a id="github-event-vocabulary"></a>
### GitHub PR event vocabulary

Canonical GitHub PR comment events (wave + phase boundaries):

- [reference/harness/recipe/trackers/github-events.json](../reference/harness/recipe/trackers/github-events.json) (bundled copy; `bench/recipe/trackers/github-events.json` in gsd-benchmark)

Each event object requires: `id`, `gsd_trigger`, `template`, `target` (`github`), `cadence`.  
Templates resolve under [reference/harness/recipe/templates/github-pr-comments/](../reference/harness/recipe/templates/github-pr-comments).  
Full posting contract: [TRACEABILITY-LLD.md § GitHub PR events](../lld/TRACEABILITY-LLD.md#github-pr-events).
