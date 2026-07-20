#!/usr/bin/env bash
# capability-schema.sh — JSON Schema validation for .gsd-recipe/config.json
# and .gsd-recipe/capability.json, plus capability.json generation (TASK-011).
#
# Contract:
#   Schemas   : .gsd-recipe/config.schema.json, .gsd-recipe/capability.json's
#               own schema at .gsd-recipe/capability.schema.json (draft-07 —
#               see the "$schema" key in each file; if/then conditional
#               requirements need at least draft-07, and draft-07 is the
#               most widely-recognized JSON Schema draft, so that's what both
#               files declare).
#   Validator : a hand-rolled subset of draft-07 (type, enum, const,
#               required, properties, additionalProperties, items, minLength,
#               minimum/maximum, if/then/else) implemented inline in python3
#               — no `jsonschema` pip package, matching this repo's existing
#               convention (parse-state.sh, install.sh's own config.json
#               assert-style checks) of never adding a new external
#               dependency when python3's stdlib already covers the need.
#               Known simplification: if/then's "if" is evaluated only over
#               properties actually present in the instance (same as
#               draft-07's real semantics for "properties", but this
#               validator does not implement every possible "if" shape —
#               only {"properties": {...}, "required": [...]}, which is all
#               config.schema.json/capability.schema.json actually use).
#
# Usage:
#   capability-schema.sh validate <schema.json> <instance.json>
#   capability-schema.sh validate-config [--config PATH] [--schema PATH]
#   capability-schema.sh validate-capability [--capability PATH] [--schema PATH]
#   capability-schema.sh generate-capability [--target PATH] [--out PATH]
#
# Examples:
#   bench/lib/capability-schema.sh validate-config --config .gsd-recipe/config.json
#   bench/lib/capability-schema.sh generate-capability --target /tmp/scratch-repo
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DEFAULT_CONFIG_SCHEMA="$REPO_ROOT/.gsd-recipe/config.schema.json"
DEFAULT_CAPABILITY_SCHEMA="$REPO_ROOT/.gsd-recipe/capability.schema.json"
DEFAULT_CONFIG="$REPO_ROOT/.gsd-recipe/config.json"
DEFAULT_CAPABILITY="$REPO_ROOT/.gsd-recipe/capability.json"

usage() {
  cat >&2 <<'EOF'
Usage:
  capability-schema.sh validate <schema.json> <instance.json>
  capability-schema.sh validate-config [--config PATH] [--schema PATH]
  capability-schema.sh validate-capability [--capability PATH] [--schema PATH]
  capability-schema.sh generate-capability [--target PATH] [--out PATH]
EOF
  exit 2
}

# Shared draft-07-subset validator, invoked by every validate* command below.
# $1 = schema path, $2 = instance path. Prints "OK" and exits 0 on success;
# prints one "ERROR: ..." line per violation to stderr and exits 1 otherwise.
run_validate() {
  local schema_path="$1" instance_path="$2"
  SCHEMA_PATH="$schema_path" INSTANCE_PATH="$instance_path" python3 - <<'PY'
import json, os, sys

SCHEMA_PATH = os.environ["SCHEMA_PATH"]
INSTANCE_PATH = os.environ["INSTANCE_PATH"]


def load_json(path, label):
    if not os.path.isfile(path):
        sys.exit(f"ERROR: {label} not found at {path}")
    with open(path) as f:
        content = f.read()
    try:
        return json.loads(content)
    except json.JSONDecodeError as e:
        sys.exit(f"ERROR: {label} at {path} is not valid JSON: {e}")


def type_name(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, int):
        return "integer"
    if isinstance(v, float):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "array"
    if isinstance(v, dict):
        return "object"
    return type(v).__name__


def check_type(v, ty):
    if ty == "object":
        return isinstance(v, dict)
    if ty == "array":
        return isinstance(v, list)
    if ty == "string":
        return isinstance(v, str)
    if ty == "boolean":
        return isinstance(v, bool)
    if ty == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if ty == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    if ty == "null":
        return v is None
    return False


def validate(instance, schema, path="$"):
    errors = []
    if not isinstance(schema, dict):
        return errors

    t = schema.get("type")
    type_ok = True
    if t is not None:
        types = t if isinstance(t, list) else [t]
        type_ok = any(check_type(instance, ty) for ty in types)
        if not type_ok:
            errors.append(f"{path}: expected type {t}, got {type_name(instance)}")

    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path}: value {instance!r} not in enum {schema['enum']}")

    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: value {instance!r} does not equal const {schema['const']!r}")

    if not type_ok:
        # Further structural checks (properties/items/etc.) would be
        # meaningless once the base type itself is wrong.
        return errors

    if isinstance(instance, dict):
        props = schema.get("properties", {})
        for req in schema.get("required", []):
            if req not in instance:
                errors.append(f"{path}: missing required property '{req}'")
        for k, v in instance.items():
            if k in props:
                errors.extend(validate(v, props[k], f"{path}.{k}"))
            else:
                ap = schema.get("additionalProperties", True)
                if ap is False:
                    errors.append(f"{path}: additional property '{k}' is not allowed")
                elif isinstance(ap, dict):
                    errors.extend(validate(v, ap, f"{path}.{k}"))
        if "if" in schema:
            if_schema = schema["if"]
            if_errors = validate(instance, if_schema, path)
            if not if_errors:
                if "then" in schema:
                    errors.extend(validate(instance, schema["then"], path))
            elif "else" in schema:
                errors.extend(validate(instance, schema["else"], path))

    if isinstance(instance, str):
        if "minLength" in schema and len(instance) < schema["minLength"]:
            errors.append(f"{path}: string shorter than minLength {schema['minLength']}")

    if isinstance(instance, (int, float)) and not isinstance(instance, bool):
        if "minimum" in schema and instance < schema["minimum"]:
            errors.append(f"{path}: {instance} is less than minimum {schema['minimum']}")
        if "maximum" in schema and instance > schema["maximum"]:
            errors.append(f"{path}: {instance} is greater than maximum {schema['maximum']}")

    if isinstance(instance, list):
        if "items" in schema:
            for i, item in enumerate(instance):
                errors.extend(validate(item, schema["items"], f"{path}[{i}]"))
        if "minItems" in schema and len(instance) < schema["minItems"]:
            errors.append(f"{path}: array shorter than minItems {schema['minItems']}")

    return errors


schema = load_json(SCHEMA_PATH, "schema")
instance = load_json(INSTANCE_PATH, "instance")

errors = validate(instance, schema)
if errors:
    for e in errors:
        print(f"ERROR: {e}", file=sys.stderr)
    sys.exit(1)
print("OK")
PY
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  validate)
    [ $# -ge 2 ] || usage
    run_validate "$1" "$2"
    ;;

  validate-config)
    CONFIG="$DEFAULT_CONFIG"
    SCHEMA="$DEFAULT_CONFIG_SCHEMA"
    while [ $# -gt 0 ]; do
      case "$1" in
        --config) CONFIG="${2:?--config requires a value}"; shift 2 ;;
        --schema) SCHEMA="${2:?--schema requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    run_validate "$SCHEMA" "$CONFIG"
    ;;

  validate-capability)
    CAPABILITY="$DEFAULT_CAPABILITY"
    SCHEMA="$DEFAULT_CAPABILITY_SCHEMA"
    while [ $# -gt 0 ]; do
      case "$1" in
        --capability) CAPABILITY="${2:?--capability requires a value}"; shift 2 ;;
        --schema) SCHEMA="${2:?--schema requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    run_validate "$SCHEMA" "$CAPABILITY"
    ;;

  generate-capability)
    TARGET="$REPO_ROOT"
    OUT=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --target) TARGET="${2:?--target requires a value}"; shift 2 ;;
        --out) OUT="${2:?--out requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    [ -n "$OUT" ] || OUT="$TARGET/.gsd-recipe/capability.json"
    mkdir -p "$(dirname "$OUT")"
    TARGET="$TARGET" OUT="$OUT" python3 - <<'PY'
import json, os, sys, datetime

TARGET = os.environ["TARGET"]
OUT = os.environ["OUT"]

# Static catalog of every recipe capability this repo knows how to install,
# per docs/netapp-recipe/BACKLOG.md's task table. generate-capability never
# invents entries — it only reports staged/not-staged for this fixed list.
CATALOG = [
    {
        "id": "install-core",
        "task_id": "TASK-010",
        "kind": "installer",
        "description": "Umbrella fallback installer: directory scaffold, .templates/, .knowledge/, code_base_details/README.md, .gitignore entries, .gsd-recipe/config.json traceability/observer defaults, install-report.json.",
        "invoke_name": None,
        "staged_path": None,
        "installer": ".gsd-recipe/scripts/install.sh",
        "composed_by_install_sh": True,
        "ledger_component": "install-core",
    },
    {
        "id": "fotw-observer",
        "task_id": "TASK-013",
        "kind": "cursor-skill",
        "description": "FLY ON THE WALL background observer bootstrap skill + reactive postToolUse hook.",
        "invoke_name": "fotw-observer-bootstrap",
        "staged_path": ".cursor/skills/fotw-observer-bootstrap/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-observer.sh",
        "composed_by_install_sh": True,
        "ledger_component": "fotw-observer",
    },
    {
        "id": "tracker-sync",
        "task_id": "TASK-014",
        "kind": "cursor-skill",
        "description": "Tracker-agnostic front door for GSD lifecycle sync; dispatches to gsd-jira-sync for tracker: jira.",
        "invoke_name": "tracker-sync",
        "staged_path": ".cursor/skills/tracker-sync/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-tracker-sync.sh",
        "composed_by_install_sh": True,
        "ledger_component": "tracker-sync",
    },
    {
        "id": "recipe-planning-policy",
        "task_id": "TASK-012",
        "kind": "agent-skill",
        "description": "GSD agent_skills-injected planning policy (7 mandatory PLAN.md sections + a filled Prerequisites table); not invoke-by-name.",
        "invoke_name": None,
        "staged_path": "skills/recipe-planning-policy/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-planning-policy.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-planning-policy",
    },
    {
        "id": "recipe-prd-intake",
        "task_id": "TASK-016",
        "kind": "cursor-skill",
        "description": "PRD intake wrapper: fills .templates/PRD.template.md, writes docs/PRD.md, invokes fotw-observer-bootstrap as its final step.",
        "invoke_name": "recipe-prd-intake",
        "staged_path": ".cursor/skills/recipe-prd-intake/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-prd-intake.sh",
        "composed_by_install_sh": False,
        "ledger_component": "recipe-prd-intake",
    },
    {
        "id": "recipe-run-phase",
        "task_id": "TASK-024",
        "kind": "cursor-skill",
        "description": "Gated single-phase execute wrapper around native gsd-execute-phase.",
        "invoke_name": "recipe-run-phase",
        "staged_path": ".cursor/skills/recipe-run-phase/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-run-phase.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-run-phase",
    },
    {
        "id": "recipe-plan-phase",
        "task_id": "TASK-017",
        "kind": "cursor-skill",
        "description": "Gated single-phase plan wrapper around native gsd-plan-phase.",
        "invoke_name": "recipe-plan-phase",
        "staged_path": ".cursor/skills/recipe-plan-phase/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-plan-phase.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-plan-phase",
    },
    {
        "id": "recipe-validate-tokens",
        "task_id": "TASK-021",
        "kind": "cursor-skill",
        "description": "Standalone, re-invokable GitHub + Jira/Atlassian credential/scope check (real --check-github probe; agent-mediated Jira/Atlassian MCP check).",
        "invoke_name": "recipe-validate-tokens",
        "staged_path": ".cursor/skills/recipe-validate-tokens/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-validate-tokens.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-validate-tokens",
    },
    {
        "id": "recipe-bootstrap-knowledge",
        "task_id": "TASK-022",
        "kind": "cursor-skill",
        "description": "Idempotent .knowledge/ skeleton scaffold + native gsd-map-codebase/gsd-graphify build/gsd-ingest-docs bootstrap-or-refresh wrapper.",
        "invoke_name": "recipe-bootstrap-knowledge",
        "staged_path": ".cursor/skills/recipe-bootstrap-knowledge/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-bootstrap-knowledge",
    },
    {
        "id": "recipe-install-verify",
        "task_id": "TASK-023",
        "kind": "cursor-skill",
        "description": "Post-install Step-5 verification checklist wrapper (delegates items 5-7 to install.sh --verify, item 4 to recipe-validate-tokens); stages both the skill and its bench/lib/install-verify-report.sh runtime dependency, so no single canonical staged_path exists.",
        "invoke_name": "recipe-install-verify",
        "staged_path": None,
        "installer": ".gsd-recipe/scripts/install-recipe-install-verify.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-install-verify",
    },
    {
        "id": "recipe-run-phases",
        "task_id": "TASK-018",
        "kind": "cursor-skill",
        "description": "Sequential ascending multi-phase loop wrapper around recipe-plan-phase N / recipe-run-phase N (skill-to-skill); stops the whole loop immediately on the first phase whose plan or run step fails. No DAG topo-sort/eligibility gating (parked pending TASK-009).",
        "invoke_name": "recipe-run-phases",
        "staged_path": ".cursor/skills/recipe-run-phases/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-run-phases.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-run-phases",
    },
    {
        "id": "recipe-verify-feature",
        "task_id": "TASK-025",
        "kind": "cursor-skill",
        "description": "Gated single-phase verify wrapper chaining native gsd-audit-milestone -> gsd-audit-uat (each warn-and-skip if inapplicable) -> gsd-verify-work N (genuinely conversational/interactive), then syncs verify_complete via gsd-jira-sync.",
        "invoke_name": "recipe-verify-feature",
        "staged_path": ".cursor/skills/recipe-verify-feature/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-verify-feature.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-verify-feature",
    },
    {
        "id": "recipe-review-ship",
        "task_id": "TASK-026",
        "kind": "cursor-skill",
        "description": "Gate-and-invoke wrapper calling native gsd-code-review N, syncing review_complete via gsd-jira-sync (optional 'In Review' transition), then calling native gsd-ship N [--draft] and surfacing the resulting PR link.",
        "invoke_name": "recipe-review-ship",
        "staged_path": ".cursor/skills/recipe-review-ship/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-review-ship.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-review-ship",
    },
    {
        "id": "recipe-settle",
        "task_id": "TASK-027",
        "kind": "cursor-skill",
        "description": "Quality-floor settle gate formalizing 'Settled = PO + CI green': real --check-ci probe (gh pr checks, falling back to gh api .../check-runs) plus a non-skippable, interactive PO-accept gate, syncing settled via gsd-jira-sync only when both pass.",
        "invoke_name": "recipe-settle",
        "staged_path": ".cursor/skills/recipe-settle/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-settle.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-settle",
    },
    {
        "id": "gsd-jira-sync",
        "task_id": "TASK-028",
        "kind": "cursor-skill",
        "description": "Posts GSD lifecycle milestones as Jira comments (and optional transitions) via Atlassian MCP, emitting matching KPI stamps; single-event mode plus an automated Drain mode (TASK-005 queue backlog). Invoked by name by tracker-sync and every recipe-* skill that syncs a lifecycle event.",
        "invoke_name": "gsd-jira-sync",
        "staged_path": ".cursor/skills/gsd-jira-sync/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-gsd-jira-sync.sh",
        "composed_by_install_sh": True,
        "ledger_component": "gsd-jira-sync",
    },
    {
        "id": "recipe-sync",
        "task_id": "TASK-029",
        "kind": "cursor-skill",
        "description": "One-shot detect->queue->drain sync pass: runs sync-reconcile.sh directly, then (unless --dry-run) invokes gsd-jira-sync --drain by name to post the queued backlog. Never loops, schedules, or hooks itself (DECISIONS.md OD-05) — recurrence is the operator's job or Cursor's own /loop automation.",
        "invoke_name": "recipe-sync",
        "staged_path": ".cursor/skills/recipe-sync/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-sync.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-sync",
    },
    {
        "id": "recipe-pr-comment",
        "task_id": "TASK-030",
        "kind": "cursor-skill",
        "description": "Real, scriptable draft->idempotency-check->post->ledger GitHub PR lifecycle comment poster: calls draft-github-pr-comment.sh for the body, sync-ledger.sh for the idempotency key/dup-check, and the real local gh pr comment CLI directly (no MCP call, unlike Jira posting). Never emits a stamp (github-events.json has no stamp field). Stages both the skill and its bench/runners/post-github-pr-comment.sh runtime dependency, so no single canonical staged_path exists.",
        "invoke_name": "recipe-pr-comment",
        "staged_path": None,
        "installer": ".gsd-recipe/scripts/install-recipe-pr-comment.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-pr-comment",
    },
    {
        "id": "recipe-install",
        "task_id": "TASK-031",
        "kind": "cursor-skill",
        "description": "Thin, invoke-by-name end-to-end install orchestrator: chains recipe-validate-tokens (informational) -> a live, non-skippable human consent gate asked in the operator's own conversation -> the real install.sh --yes --target <repo> -> recipe-install-verify's Step-5 checklist -> one combined summary. --uninstall delegates to install.sh --uninstall --yes, behind its own equally-explicit live-conversation confirm gate. Never calls install.sh --record-jira-check; never reimplements any check the three invoked pieces already own.",
        "invoke_name": "recipe-install",
        "staged_path": ".cursor/skills/recipe-install/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-install.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-install",
    },
    {
        "id": "recipe-observe",
        "task_id": "TASK-032",
        "kind": "cursor-skill",
        "description": "Thin front door for the FOTW observer's operator-facing lifecycle: status/start/stop/enable/disable. status/enable/disable/request-stop delegate to new bench/lib/observer-lib.sh subcommands; start delegates entirely to fotw-observer-bootstrap by name. stop only sets the graceful-finalize sentinel the tick loop already watches for -- it cannot forcibly kill an already-running observer subagent.",
        "invoke_name": "recipe-observe",
        "staged_path": ".cursor/skills/recipe-observe/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-observe.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-observe",
    },
    {
        "id": "recipe-create-epic",
        "task_id": "TASK-033",
        "kind": "cursor-skill",
        "description": "PRD -> Jira Epic bridge: drafts summary/description from docs/PRD.md (bench/runners/draft-jira-epic.sh), resolves the Jira project/issue type (optional flags or live MCP questions via getVisibleJiraProjects/getJiraProjectIssueTypesMetadata), creates the Epic via createJiraIssue, links it into .planning/STATE.md's '## Tracker' section via parse-state.sh's new init-tracker write subcommand, and syncs intake_started via gsd-jira-sync (never posts/transitions Jira issues directly itself). Stages both the skill and its bench/runners/draft-jira-epic.sh runtime dependency, so no single canonical staged_path exists.",
        "invoke_name": "recipe-create-epic",
        "staged_path": None,
        "installer": ".gsd-recipe/scripts/install-recipe-create-epic.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-create-epic",
    },
    {
        "id": "recipe-create-phase-tasks",
        "task_id": "TASK-034",
        "kind": "cursor-skill",
        "description": "Agent-mediated phase-task creation: closes TASK-007's detect+draft+queue-only gap. Runs create-phase-tasks.sh detect then list (self-heals anything already linked out-of-band), resolves one Jira issue type for the whole batch (prefers Task, then Sub-task), shows a soft confirm gate, then creates+links a Jira issue per pending phase task (createJiraIssue + parent field or createIssueLink) and records each outcome via mark-done/mark-failed.",
        "invoke_name": "recipe-create-phase-tasks",
        "staged_path": ".cursor/skills/recipe-create-phase-tasks/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-create-phase-tasks.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-create-phase-tasks",
    },
    {
        "id": "recipe-new-project",
        "task_id": "TASK-036",
        "kind": "cursor-skill",
        "description": "Gated repo-bootstrap wrapper closing the 'make my current repo ready' SDLC coverage gap. Determines first-init vs re-init (soft warn-and-confirm), resolves the bootstrap input (explicit argument, else docs/PRD.md if present, else native input-gathering), calls native gsd-new-project (or gsd-import with --import) directly, then re-verifies .planning/PROJECT.md + ROADMAP.md + STATE.md actually got created. Never syncs intake_started itself — that stays recipe-create-epic's job.",
        "invoke_name": "recipe-new-project",
        "staged_path": ".cursor/skills/recipe-new-project/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-new-project.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-new-project",
    },
    {
        "id": "recipe-onboard",
        "task_id": "TASK-037",
        "kind": "cursor-skill",
        "description": "Single onboarding orchestrator closing the 'no single on-ramp' SDLC coverage gap. Chains, in order, whichever of recipe-prd-intake / recipe-new-project / recipe-create-epic / recipe-create-phase-tasks are actually missing their artifact (docs/PRD.md, .planning/ROADMAP.md, a linked Jira Epic, per-phase Jira sub-tasks), after one soft preview-then-confirm gate. Stops the whole chain on the first step that fails or is declined; never re-implements any invoked skill's own logic or duplicates its Jira sync.",
        "invoke_name": "recipe-onboard",
        "staged_path": ".cursor/skills/recipe-onboard/SKILL.md",
        "installer": ".gsd-recipe/scripts/install-recipe-onboard.sh",
        "composed_by_install_sh": True,
        "ledger_component": "recipe-onboard",
    },
]

ledger_path = os.path.join(TARGET, ".gsd-recipe", "ledger.json")
ledger = {}
if os.path.isfile(ledger_path):
    with open(ledger_path) as f:
        content = f.read().strip()
        if content:
            ledger = json.loads(content)

capabilities = []
for entry in CATALOG:
    lc = entry["ledger_component"]
    ledger_tracked = bool(ledger.get(lc)) if lc else False
    staged_path = entry["staged_path"]
    path_exists = os.path.isfile(os.path.join(TARGET, staged_path)) if staged_path else None

    if staged_path is not None:
        staged = path_exists
    else:
        staged = ledger_tracked

    capabilities.append({
        **entry,
        "staged": bool(staged),
        "ledger_tracked": ledger_tracked,
        # No per-component version-tracking mechanism exists yet in this
        # recipe (no VERSION file, no git-tag-per-skill convention) — see
        # capability.schema.json's own description of this field.
        "version": "1.0.0",
    })

manifest = {
    "schema_version": 1,
    "generated_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "recipe": "netapp-gsd-recipe",
    "capabilities": capabilities,
}

with open(OUT, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")

print(f"generate-capability: wrote {OUT} ({len(capabilities)} capabilities, "
      f"{sum(1 for c in capabilities if c['staged'])} staged)")
PY
    ;;

  *)
    usage
    ;;
esac
