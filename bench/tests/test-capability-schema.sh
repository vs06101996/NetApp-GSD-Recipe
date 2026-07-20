#!/usr/bin/env bash
# Regression test for bench/lib/capability-schema.sh (TASK-011).
# Run: ./bench/tests/test-capability-schema.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/capability-schema.sh"
FIX="$REPO_ROOT/bench/tests/fixtures"

CONFIG_SCHEMA="$REPO_ROOT/.gsd-recipe/config.schema.json"
CAPABILITY_SCHEMA="$REPO_ROOT/.gsd-recipe/capability.schema.json"

pass=0
fail=0

check() {
  local desc="$1"; local result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $desc"
    pass=$((pass + 1))
  else
    echo "FAIL - $desc"
    fail=$((fail + 1))
  fi
}

SCRATCH="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# --- config.schema.json: valid instances -----------------------------------

# 1. Full real shape (tracker + traceability + observer) validates
"$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-valid.json" >/dev/null 2>&1
check "config schema: real install.sh shape (tracker+traceability+observer) validates" "$?"

# 2. Minimal shape (no tracker key) still validates — tracker is optional
"$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-valid-minimal.json" >/dev/null 2>&1
check "config schema: minimal shape without 'tracker' key validates (tracker is optional)" "$?"

# 3. Unknown top-level/nested keys are tolerated (additionalProperties: true)
"$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-valid-extra-keys.json" >/dev/null 2>&1
check "config schema: unrecognized extra keys do not fail validation" "$?"

# 4. traceability.enabled=false WITH a non-empty reason validates
"$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-traceability-disabled-with-reason.json" >/dev/null 2>&1
check "config schema: traceability disabled + reason present validates" "$?"

# --- config.schema.json: invalid instances (fail closed with actionable errors) --

# 5. Missing required top-level 'observer' object fails
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-missing-observer.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required property 'observer'"
check "config schema: missing required 'observer' object fails with actionable error" "$?"

# 6. Wrong type (interval_minutes as a string) fails
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-wrong-type.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "expected type"
check "config schema: wrong type (interval_minutes as string) fails" "$?"

# 7. tracker enum violation ('trello') fails
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-invalid-tracker.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "not in enum"
check "config schema: unsupported tracker value fails enum check" "$?"

# 8. observer.enabled=true without interval_minutes fails the conditional (if/then)
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-observer-enabled-no-interval.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required property 'interval_minutes'"
check "config schema: observer.enabled=true without interval_minutes fails conditional requirement" "$?"

# 9. traceability.enabled=false without a reason fails the conditional (if/then)
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-traceability-disabled-no-reason.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required property 'reason'"
check "config schema: traceability.enabled=false without reason fails conditional requirement" "$?"

# 10. A top-level array (not an object) fails the base type check
OUT="$("$LIB" validate "$CONFIG_SCHEMA" "$FIX/gsd-recipe-config-not-an-object.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "expected type object"
check "config schema: top-level array instead of object fails type check" "$?"

# 11. validate-config subcommand defaults --config/--schema to the real repo paths
"$LIB" validate-config --config "$FIX/gsd-recipe-config-valid.json" --schema "$CONFIG_SCHEMA" >/dev/null 2>&1
check "validate-config subcommand runs against an explicit --config/--schema pair" "$?"

# --- capability.schema.json: valid/invalid instances ------------------------

# 12. A well-formed capability.json instance validates
"$LIB" validate "$CAPABILITY_SCHEMA" "$FIX/capability-valid.json" >/dev/null 2>&1
check "capability schema: well-formed manifest validates" "$?"

# 13. A capability entry missing required fields (id, staged_path, etc.) fails
OUT="$("$LIB" validate "$CAPABILITY_SCHEMA" "$FIX/capability-missing-field.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required property 'id'"
check "capability schema: entry missing required 'id' fails" "$?"

# 14. Wrong type at the top level (schema_version as a string) fails
OUT="$("$LIB" validate "$CAPABILITY_SCHEMA" "$FIX/capability-wrong-type.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "expected type integer"
check "capability schema: schema_version as string fails type check" "$?"

# 15. kind outside the enum (installer|cursor-skill|agent-skill) fails
OUT="$("$LIB" validate "$CAPABILITY_SCHEMA" "$FIX/capability-invalid-kind-enum.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "not in enum"
check "capability schema: unrecognized 'kind' value fails enum check" "$?"

# 16. Missing required top-level field (schema_version) fails
OUT="$("$LIB" validate "$CAPABILITY_SCHEMA" "$FIX/capability-missing-top-level.json" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ] && echo "$OUT" | grep -q "missing required property 'schema_version'"
check "capability schema: missing top-level 'schema_version' fails" "$?"

# 17. validate-capability subcommand works with explicit flags
"$LIB" validate-capability --capability "$FIX/capability-valid.json" --schema "$CAPABILITY_SCHEMA" >/dev/null 2>&1
check "validate-capability subcommand runs against an explicit --capability/--schema pair" "$?"

# --- generate-capability: introspection against a scratch target -----------

new_scratch_target() {
  local dir="$SCRATCH/target-$1"
  mkdir -p "$dir/.gsd-recipe" "$dir/.cursor/skills/tracker-sync" "$dir/.cursor/skills/recipe-run-phase" "$dir/skills/recipe-planning-policy"
  echo "# stub" > "$dir/.cursor/skills/tracker-sync/SKILL.md"
  echo "# stub" > "$dir/.cursor/skills/recipe-run-phase/SKILL.md"
  echo "# stub" > "$dir/skills/recipe-planning-policy/SKILL.md"
  cat > "$dir/.gsd-recipe/ledger.json" <<'EOF'
{
  "install-core": [".templates/PRD.template.md"],
  "tracker-sync": [".cursor/skills/tracker-sync/SKILL.md"],
  "recipe-run-phase": [".cursor/skills/recipe-run-phase/SKILL.md"],
  "recipe-planning-policy": ["skills/recipe-planning-policy/SKILL.md"]
}
EOF
  echo "$dir"
}

TARGET1="$(new_scratch_target 1)"
"$LIB" generate-capability --target "$TARGET1" >/dev/null
GEN_OUT="$TARGET1/.gsd-recipe/capability.json"

# 18. generate-capability writes a manifest that itself validates against capability.schema.json
"$LIB" validate "$CAPABILITY_SCHEMA" "$GEN_OUT" >/dev/null 2>&1
check "generate-capability output validates against capability.schema.json" "$?"

# 19. Staged capabilities (tracker-sync, recipe-run-phase, recipe-planning-policy, install-core) report staged=true
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['tracker-sync']['staged'] is True, 'tracker-sync should be staged'
assert by_id['recipe-run-phase']['staged'] is True, 'recipe-run-phase should be staged'
assert by_id['recipe-planning-policy']['staged'] is True, 'recipe-planning-policy should be staged'
assert by_id['install-core']['staged'] is True, 'install-core should be staged (ledger-only component)'
"
check "generate-capability correctly reports staged=true for present skills/ledger components" "$?"

# 20. Non-staged capabilities (recipe-prd-intake, recipe-plan-phase, fotw-observer,
# recipe-validate-tokens, recipe-bootstrap-knowledge, recipe-install-verify,
# recipe-run-phases, recipe-verify-feature, recipe-review-ship, recipe-settle,
# gsd-jira-sync, recipe-sync, recipe-pr-comment, recipe-install, recipe-observe) report staged=false
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
for cid in ('recipe-prd-intake', 'recipe-plan-phase', 'fotw-observer', 'recipe-validate-tokens', 'recipe-bootstrap-knowledge', 'recipe-install-verify', 'recipe-run-phases', 'recipe-verify-feature', 'recipe-review-ship', 'recipe-settle', 'gsd-jira-sync', 'recipe-sync', 'recipe-pr-comment', 'recipe-install', 'recipe-observe', 'recipe-create-epic', 'recipe-create-phase-tasks', 'recipe-new-project', 'recipe-onboard'):
    assert by_id[cid]['staged'] is False, f'{cid} should NOT be staged in this scratch target'
"
check "generate-capability correctly reports staged=false for absent capabilities" "$?"

# 21. Every catalog entry is present exactly once (no invented/duplicated ids)
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
ids = [c['id'] for c in d['capabilities']]
assert len(ids) == len(set(ids)), 'duplicate capability ids'
assert len(ids) == 23, f'expected 23 catalog entries, got {len(ids)}'
"
check "generate-capability emits exactly 23 catalog entries with unique ids" "$?"

# 22. task_id values match BACKLOG.md's task table
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['install-core']['task_id'] == 'TASK-010'
assert by_id['recipe-planning-policy']['task_id'] == 'TASK-012'
assert by_id['fotw-observer']['task_id'] == 'TASK-013'
assert by_id['tracker-sync']['task_id'] == 'TASK-014'
assert by_id['recipe-prd-intake']['task_id'] == 'TASK-016'
assert by_id['recipe-plan-phase']['task_id'] == 'TASK-017'
assert by_id['recipe-run-phases']['task_id'] == 'TASK-018'
assert by_id['recipe-validate-tokens']['task_id'] == 'TASK-021'
assert by_id['recipe-bootstrap-knowledge']['task_id'] == 'TASK-022'
assert by_id['recipe-install-verify']['task_id'] == 'TASK-023'
assert by_id['recipe-run-phase']['task_id'] == 'TASK-024'
assert by_id['recipe-verify-feature']['task_id'] == 'TASK-025'
assert by_id['recipe-review-ship']['task_id'] == 'TASK-026'
assert by_id['recipe-settle']['task_id'] == 'TASK-027'
assert by_id['gsd-jira-sync']['task_id'] == 'TASK-028'
assert by_id['recipe-sync']['task_id'] == 'TASK-029'
assert by_id['recipe-pr-comment']['task_id'] == 'TASK-030'
assert by_id['recipe-install']['task_id'] == 'TASK-031'
assert by_id['recipe-observe']['task_id'] == 'TASK-032'
assert by_id['recipe-create-epic']['task_id'] == 'TASK-033'
assert by_id['recipe-create-phase-tasks']['task_id'] == 'TASK-034'
assert by_id['recipe-new-project']['task_id'] == 'TASK-036'
assert by_id['recipe-onboard']['task_id'] == 'TASK-037'
"
check "generate-capability's task_id values match BACKLOG.md's task table" "$?"

# 22b. recipe-install-verify has no single staged_path (stages 2 files), same
# no-canonical-path shape as install-core, and is ledger_tracked when staged.
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['recipe-install-verify']['staged_path'] is None
"
check "generate-capability: recipe-install-verify has no single staged_path (stages skill + lib)" "$?"

# 22c. recipe-pr-comment has no single staged_path (stages 2 files: skill +
# bench/runners/post-github-pr-comment.sh runtime dependency), same shape.
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['recipe-pr-comment']['staged_path'] is None
"
check "generate-capability: recipe-pr-comment has no single staged_path (stages skill + runner)" "$?"

# 22d. recipe-create-epic has no single staged_path (stages 2 files: skill +
# bench/runners/draft-jira-epic.sh runtime dependency), same shape.
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['recipe-create-epic']['staged_path'] is None
"
check "generate-capability: recipe-create-epic has no single staged_path (stages skill + runner)" "$?"

# 23. install-core reports ledger_tracked=true and staged_path=null (no single canonical file)
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['install-core']['staged_path'] is None
assert by_id['install-core']['ledger_tracked'] is True
"
check "generate-capability: install-core has no single staged_path, is ledger_tracked" "$?"

# 24. Idempotent regeneration: running generate-capability twice on the same
#     unchanged target produces byte-identical capabilities (only generated_at differs)
"$LIB" generate-capability --target "$TARGET1" >/dev/null
python3 -c "
import json
d = json.load(open('$GEN_OUT'))
d.pop('generated_at')
d2 = json.load(open('$GEN_OUT'))
d2.pop('generated_at')
assert d == d2, 'regeneration on an unchanged target should be stable'
"
check "generate-capability is idempotent on an unchanged target (identical besides timestamp)" "$?"

# 25. A second scratch target with nothing staged reports all 7 capabilities as staged=false
TARGET2="$SCRATCH/target-2-empty"
mkdir -p "$TARGET2"
"$LIB" generate-capability --target "$TARGET2" >/dev/null
python3 -c "
import json
d = json.load(open('$TARGET2/.gsd-recipe/capability.json'))
assert all(c['staged'] is False for c in d['capabilities']), 'nothing should be staged in an empty target'
assert all(c['ledger_tracked'] is False for c in d['capabilities'])
"
check "generate-capability against a totally empty target reports all capabilities unstaged" "$?"

# 26. --out lets the caller redirect output without touching .gsd-recipe/capability.json
CUSTOM_OUT="$SCRATCH/custom-capability-output.json"
"$LIB" generate-capability --target "$TARGET1" --out "$CUSTOM_OUT" >/dev/null
[ -f "$CUSTOM_OUT" ]
check "generate-capability --out writes to a custom path" "$?"

# 27. validate rejects a schema/instance pair where the schema file itself is missing
"$LIB" validate "$SCRATCH/does-not-exist-schema.json" "$FIX/gsd-recipe-config-valid.json" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate fails closed when the schema file is missing" "$?"

# 28. validate rejects a schema/instance pair where the instance file is not valid JSON
BAD_JSON="$SCRATCH/not-valid.json"
printf '{ this is not json' > "$BAD_JSON"
"$LIB" validate "$CONFIG_SCHEMA" "$BAD_JSON" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "validate fails closed on malformed JSON instance" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
