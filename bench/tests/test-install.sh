#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install.sh (TASK-010).
# Matches the convention of bench/tests/test-install-tracker-sync.sh.
# Run: ./bench/tests/test-install.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install.sh"

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

new_repo() {
  local dir
  dir="$(mktemp -d)"
  (cd "$dir" && git init -q && git commit --allow-empty -qm init)
  echo "$dir"
}

# Never let general installer cases touch the developer's real Cursor GSD.
# Purpose-built prerequisite cases below override this signal again.
TEST_GSD_ROOT="$(mktemp -d)/.cursor"
export GSD_SIGNAL_PATH="$TEST_GSD_ROOT/skills/gsd-help/SKILL.md"
mkdir -p \
  "$TEST_GSD_ROOT/skills/gsd-help" \
  "$TEST_GSD_ROOT/skills/gsd-new-project" \
  "$TEST_GSD_ROOT/skills/gsd-map-codebase" \
  "$TEST_GSD_ROOT/skills/gsd-graphify" \
  "$TEST_GSD_ROOT/skills/gsd-ingest-docs" \
  "$TEST_GSD_ROOT/agents"
touch \
  "$GSD_SIGNAL_PATH" \
  "$TEST_GSD_ROOT/skills/gsd-new-project/SKILL.md" \
  "$TEST_GSD_ROOT/skills/gsd-map-codebase/SKILL.md" \
  "$TEST_GSD_ROOT/skills/gsd-graphify/SKILL.md" \
  "$TEST_GSD_ROOT/skills/gsd-ingest-docs/SKILL.md" \
  "$TEST_GSD_ROOT/agents/gsd-roadmapper.md"

# A PATH containing everything the installer/test harness needs (python3,
# git, coreutils, bash, sed, etc.) except a binary named "gh" — simulates
# an environment where the GitHub CLI is not installed, per the plan's
# requirement to test the warn-only (not fail-closed) behavior without
# depending on real GitHub credentials being present or absent.
make_path_without_gh() {
  local fakebin dir f b
  fakebin="$(mktemp -d)"
  for dir in $(echo "$PATH" | tr ':' '\n'); do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"
      [ "$b" = "gh" ] && continue
      [ -e "$fakebin/$b" ] || ln -s "$f" "$fakebin/$b" 2>/dev/null || true
    done
  done
  echo "$fakebin"
}

# Generalized version of make_path_without_gh: builds a scratch PATH from
# every real PATH binary, excluding whichever names are listed in $1 (space
# separated), so a test can drop in its own fake stub for those names
# without a real binary shadowing it. Used both by the prerequisite-bootstrap
# cases below and by the self-install case (#11) to robustly exclude
# graphify/uv regardless of this dev machine's actual state.
make_scratch_path_excluding() {
  local exclude=" $1 "
  local fakebin dir f b
  fakebin="$(mktemp -d)"
  for dir in $(echo "$PATH" | tr ':' '\n'); do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"
      case "$exclude" in *" $b "*) continue ;; esac
      [ -e "$fakebin/$b" ] || ln -s "$f" "$fakebin/$b" 2>/dev/null || true
    done
  done
  echo "$fakebin"
}

# 1. Refuses to install outside a git repo (fail closed)
NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"

# 2. Fresh install stages the full directory tree
TARGET1="$(new_repo)"
INSTALL_OUT1="$("$INSTALLER" --yes --target "$TARGET1")"

for f in PRD.template.md JIRA-PRD.input.template.md JIRA-PRD.input.MAPPING.md SPEC.template.md TDD.template.md bare_metal.template.md jira-comment.template.md github-pr-comment.template.md; do
  [ -f "$TARGET1/.templates/$f" ]
  check "fresh install stages .templates/$f" "$?"
done

[ -f "$TARGET1/.knowledge/index.md" ] && [ -f "$TARGET1/.knowledge/log.md" ]
check "fresh install stages .knowledge/index.md and log.md" "$?"

for d in architecture dependency-graph hot-files risk-register dag; do
  [ -d "$TARGET1/.knowledge/$d" ] || { check "fresh install stages empty .knowledge/$d" "1"; break; }
done
[ -d "$TARGET1/.knowledge/dag" ]
check "fresh install stages the 5 empty .knowledge/ subdirs" "$?"

[ -f "$TARGET1/code_base_details/README.md" ]
check "fresh install stages code_base_details/README.md" "$?"

rc=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  grep -qxF "$line" "$TARGET1/.gitignore" || { rc=1; break; }
done <<'EOF'
/bin/
/dist/
*.exe
.idea/
.vscode/
.env
.env.*
.learnings/
.gsd-codebase/
.gsd-recipe/
.knowledge/
.templates/
.planning/
code_base_details/
skills/
docs/RECIPE-COMMANDS.md
docs/RECIPE-BENCHMARKS.md
docs/RECIPE-SEQUENCE.md
bench/
.cursor/get-shit-done/
.cursor/gsd-install-state.json
.cursor/gsd-file-manifest.json
.cursor/.gsd-profile
EOF
check "fresh install writes standard .gitignore entries" "$rc"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/config.json'))
assert d['traceability'] == {'enabled': True, 'reason': ''}, d
assert d['observer'] == {'enabled': False, 'interval_minutes': 10}, d
assert d['tracker'] == 'jira', d
"
check "fresh install merges traceability/observer defaults into config.json alongside tracker" "$?"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/install-report.json'))
assert d['github_check'] in ('pass', 'fail', 'skipped'), d
assert d['jira_check'] == 'pending', d
"
check "fresh install writes install-report.json with jira_check: pending" "$?"

# Printed paste snippets must name only staged paths and include enough
# operator guidance to make the print-only setup verifiable after restart.
printf '%s' "$INSTALL_OUT1" | grep -q '"gsd-planner": \["skills/recipe-planning-policy"\]' && rc=0 || rc=$?
check "agent_skills snippet contains the real staged recipe-planning-policy path" "$rc"
if printf '%s' "$INSTALL_OUT1" | grep -qE 'skills/recipe-repo-conventions|skills/recipe-acceptance-criteria'; then rc=1; else rc=0; fi
check "agent_skills snippet contains no phantom skill paths" "$rc"
printf '%s' "$INSTALL_OUT1" | grep -q "Paste checklist:" && \
  printf '%s' "$INSTALL_OUT1" | grep -q "restart the Cursor Agent" && \
  printf '%s' "$INSTALL_OUT1" | grep -q "list MCP tools" && rc=0 || rc=$?
check "MCP paste snippet says where to paste, restart Agent, and confirm listed tools" "$rc"
printf '%s' "$INSTALL_OUT1" | grep -q "Run gsd-surface status" && rc=0 || rc=$?
check "agent_skills paste snippet explains how to confirm the injected skill" "$rc"

# recipe_source / recipe-paths.sh — permanent fix for "script missing on
# external --target" (see bench/tests/test-recipe-paths.sh for the fuller
# resolver behavior suite; these are just the install.sh-side assertions).
python3 -c "
import json, os
d = json.load(open('$TARGET1/.gsd-recipe/config.json'))
assert os.path.realpath(d.get('recipe_source', '')) == os.path.realpath('$REPO_ROOT'), d
"
check "fresh external --target install writes recipe_source pointing at the recipe source repo" "$?"

[ -x "$TARGET1/.gsd-recipe/scripts/recipe-paths.sh" ]
check "fresh install stages recipe-paths.sh, executable" "$?"

[ -x "$TARGET1/.gsd-recipe/scripts/recipe-verify-knowledge.sh" ]
check "fresh install stages recipe-verify-knowledge.sh guardrail" "$?"
[ -x "$TARGET1/.gsd-recipe/scripts/recipe-verify-planning.sh" ]
check "fresh install stages recipe-verify-planning.sh guardrail" "$?"
[ -f "$TARGET1/.gsd-recipe/scripts/recipe_knowledge.py" ]
check "fresh install stages recipe_knowledge.py guardrail lib" "$?"
[ -f "$TARGET1/.gsd-recipe/scripts/recipe_verify_planning.py" ]
check "fresh install stages recipe_verify_planning.py guardrail lib" "$?"
[ -x "$TARGET1/.gsd-recipe/scripts/graphify-probe.sh" ]
check "fresh install stages graphify-probe.sh guardrail lib" "$?"

# 3. Cascading composition: install-observer.sh / install-tracker-sync.sh /
# install-recipe-planning-policy.sh / install-recipe-run-phase.sh actually ran
[ -f "$TARGET1/.cursor/skills/fotw-observer-bootstrap/SKILL.md" ]
check "install.sh composes install-observer.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/tracker-sync/SKILL.md" ]
check "install.sh composes install-tracker-sync.sh (skill staged)" "$?"
[ -f "$TARGET1/skills/recipe-planning-policy/SKILL.md" ]
check "install.sh composes install-recipe-planning-policy.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-run-phase/SKILL.md" ]
check "install.sh composes install-recipe-run-phase.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "install.sh composes install-recipe-plan-phase.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-validate-tokens/SKILL.md" ]
check "install.sh composes install-recipe-validate-tokens.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "install.sh composes install-recipe-bootstrap-knowledge.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "install.sh composes install-recipe-install-verify.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "install.sh composes install-recipe-run-phases.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "install.sh composes install-recipe-verify-feature.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "install.sh composes install-recipe-review-ship.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-settle/SKILL.md" ]
check "install.sh composes install-recipe-settle.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/gsd-jira-sync/SKILL.md" ]
check "install.sh composes install-gsd-jira-sync.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-sync/SKILL.md" ]
check "install.sh composes install-recipe-sync.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-pr-comment/SKILL.md" ] && [ -f "$TARGET1/bench/runners/post-github-pr-comment.sh" ]
check "install.sh composes install-recipe-pr-comment.sh (skill + runner staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-install/SKILL.md" ]
check "install.sh composes install-recipe-install.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-observe/SKILL.md" ]
check "install.sh composes install-recipe-observe.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-create-epic/SKILL.md" ] && [ -f "$TARGET1/bench/runners/draft-jira-epic.sh" ]
check "install.sh composes install-recipe-create-epic.sh (skill + runner staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-create-phase-tasks/SKILL.md" ]
check "install.sh composes install-recipe-create-phase-tasks.sh (skill staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-help/SKILL.md" ] && [ -f "$TARGET1/docs/RECIPE-COMMANDS.md" ] && [ -f "$TARGET1/docs/RECIPE-BENCHMARKS.md" ]
check "install.sh composes install-recipe-help.sh (skill + docs staged)" "$?"
[ -f "$TARGET1/.cursor/skills/recipe-prd-intake/SKILL.md" ]
check "install.sh composes install-recipe-prd-intake.sh (skill staged)" "$?"
if [ -f "$TARGET1/.cursor/skills/recipe-new-project/SKILL.md" ]; then
  check "install.sh composes install-recipe-new-project.sh (skill staged)" "0"
fi
if [ -f "$TARGET1/.cursor/skills/recipe-onboard/SKILL.md" ]; then
  check "install.sh composes install-recipe-onboard.sh (skill staged)" "0"
fi
if [ -f "$TARGET1/.cursor/skills/recipe-start/SKILL.md" ]; then
  check "install.sh composes install-recipe-start.sh (skill staged)" "0"
fi
if [ -f "$TARGET1/.cursor/skills/recipe-status/SKILL.md" ]; then
  check "install.sh composes install-recipe-status.sh (skill staged)" "0"
fi
if [ -f "$TARGET1/.cursor/skills/recipe-workspace/SKILL.md" ] &&
   [ -f "$TARGET1/.gsd-recipe/lib/workspace-swap.sh" ] &&
   [ -f "$TARGET1/.gsd-recipe/lib/initiative-branch.sh" ]; then
  check "install.sh composes install-recipe-workspace.sh (skill + workspace/initiative libs staged)" "0"
fi
if [ -f "$TARGET1/.cursor/skills/recipe-update/SKILL.md" ] && [ -f "$TARGET1/.gsd-recipe/lib/recipe-update.sh" ] && [ -f "$TARGET1/.gsd-recipe/lib/recipe-update-nudge.sh" ]; then
  check "install.sh composes install-recipe-update.sh (skill + lib + nudge staged)" "0"
fi
[ -f "$TARGET1/.cursor/rules/recipe-command-surface.mdc" ]
check "install.sh composes install-recipe-command-surface.sh (always-applied rule staged)" "$?"
[ -f "$TARGET1/.gsd-recipe/scripts/recipe-next.sh" ]
check "install.sh stages recipe-next.sh with recipe-start" "$?"
[ -f "$TARGET1/.gsd-recipe/scripts/recipe-status.sh" ]
check "install.sh stages recipe-status.sh with recipe-status" "$?"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/ledger.json'))
assert 'fotw-observer' in d and d['fotw-observer'], d
assert 'tracker-sync' in d and d['tracker-sync'], d
assert 'recipe-planning-policy' in d and d['recipe-planning-policy'], d
assert 'recipe-run-phase' in d and d['recipe-run-phase'], d
assert 'recipe-plan-phase' in d and d['recipe-plan-phase'], d
assert 'recipe-validate-tokens' in d and d['recipe-validate-tokens'], d
assert 'recipe-bootstrap-knowledge' in d and d['recipe-bootstrap-knowledge'], d
assert 'recipe-install-verify' in d and d['recipe-install-verify'], d
assert 'recipe-run-phases' in d and d['recipe-run-phases'], d
assert 'recipe-verify-feature' in d and d['recipe-verify-feature'], d
assert 'recipe-review-ship' in d and d['recipe-review-ship'], d
assert 'recipe-settle' in d and d['recipe-settle'], d
assert 'gsd-jira-sync' in d and d['gsd-jira-sync'], d
assert 'recipe-sync' in d and d['recipe-sync'], d
assert 'recipe-pr-comment' in d and d['recipe-pr-comment'], d
assert 'recipe-install' in d and d['recipe-install'], d
assert 'recipe-observe' in d and d['recipe-observe'], d
assert 'recipe-create-epic' in d and d['recipe-create-epic'], d
assert 'recipe-create-phase-tasks' in d and d['recipe-create-phase-tasks'], d
assert 'recipe-help' in d and d['recipe-help'], d
assert 'recipe-prd-intake' in d and d['recipe-prd-intake'], d
assert 'install-core' in d and d['install-core'], d
if 'recipe-new-project' in d:
    assert d['recipe-new-project'], d
if 'recipe-onboard' in d:
    assert d['recipe-onboard'], d
if 'recipe-start' in d:
    assert d['recipe-start'], d
if 'recipe-status' in d:
    assert d['recipe-status'], d
if 'recipe-workspace' in d:
    assert d['recipe-workspace'], d
if 'recipe-update' in d:
    assert d['recipe-update'], d
assert 'recipe-command-surface' in d and d['recipe-command-surface'], d
# install.sh must not re-ledger files the sub-installers already track under
# their own component names.
assert set(d['install-core']).isdisjoint(set(d['fotw-observer'])), d
assert set(d['install-core']).isdisjoint(set(d['tracker-sync'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-planning-policy'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-run-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-plan-phase'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-validate-tokens'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-bootstrap-knowledge'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-install-verify'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-run-phases'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-verify-feature'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-review-ship'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-settle'])), d
assert set(d['install-core']).isdisjoint(set(d['gsd-jira-sync'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-sync'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-pr-comment'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-install'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-observe'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-create-epic'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-create-phase-tasks'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-help'])), d
assert set(d['install-core']).isdisjoint(set(d['recipe-prd-intake'])), d
for _opt in ('recipe-new-project', 'recipe-onboard', 'recipe-start', 'recipe-status', 'recipe-workspace', 'recipe-update', 'recipe-command-surface'):
    if _opt in d:
        assert set(d['install-core']).isdisjoint(set(d[_opt])), d
"
check "ledger separates install-core from composed recipe components including recipe-workspace" "$?"

# capability.json is generated once install() has composed every sub-installer,
# and validates against the new capability.schema.json (TASK-011).
"$REPO_ROOT/bench/lib/capability-schema.sh" validate-capability --capability "$TARGET1/.gsd-recipe/capability.json" --schema "$REPO_ROOT/.gsd-recipe/capability.schema.json" >/dev/null 2>&1
check "install.sh generates a capability.json that validates against capability.schema.json" "$?"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/capability.json'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['install-core']['staged'] is True
"
check "install.sh's own capability.json reports install-core as staged" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['install-core']))")"

# 4. Idempotent re-run: no duplicate ledger rows, config.json unchanged
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['install-core']))")"
[ "$LEDGER_COUNT1" = "$LEDGER_COUNT2" ]
check "re-running install does not duplicate install-core ledger rows" "$?"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/config.json'))
assert d['tracker'] == 'jira', d
"
check "re-running install leaves config.json's tracker value unchanged" "$?"

# 5. config.json merge preserves a pre-existing tracker choice AND unrelated keys
TARGET2="$(new_repo)"
mkdir -p "$TARGET2/.gsd-recipe"
cat > "$TARGET2/.gsd-recipe/config.json" <<'EOF'
{"tracker": "github", "some_other_key": "keep-me"}
EOF
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
python3 -c "
import json
d = json.load(open('$TARGET2/.gsd-recipe/config.json'))
assert d.get('tracker') == 'github', d
assert d.get('some_other_key') == 'keep-me', d
assert d.get('traceability', {}).get('enabled') is True, d
assert d.get('observer', {}).get('enabled') is False, d
"
check "config.json merge preserves pre-existing tracker + unrelated keys while adding traceability/observer" "$?"

# A reinstall from another recipe clone must repair a stale recipe_source.
# This uses a complete scratch copy because every composed installer resolves
# its canonical templates relative to the clone that is actually running.
ALT_SOURCE="$(mktemp -d)/gsd-benchmark-alt-source"
cp -R "$REPO_ROOT" "$ALT_SOURCE"
"$ALT_SOURCE/.gsd-recipe/scripts/install.sh" --yes --target "$TARGET2" >/dev/null
python3 -c "
import json, os
d = json.load(open('$TARGET2/.gsd-recipe/config.json'))
assert os.path.realpath(d.get('recipe_source', '')) == os.path.realpath('$ALT_SOURCE'), d
"
check "reinstall from a different recipe clone refreshes recipe_source" "$?"
python3 -c "
import json
d = json.load(open('$TARGET2/.gsd-recipe/config.json'))
assert d.get('tracker') == 'github', d
assert d.get('some_other_key') == 'keep-me', d
"
check "recipe_source refresh preserves unrelated config keys" "$?"
rm -rf "$(dirname "$ALT_SOURCE")"

# 6. --verify blocks INSTALL-VERIFIED.json while jira_check is pending
"$INSTALLER" --verify --target "$TARGET1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--verify exits non-zero while jira_check is pending" "$?"
[ ! -f "$TARGET1/.gsd-recipe/INSTALL-VERIFIED.json" ]
check "--verify does not write INSTALL-VERIFIED.json while jira_check is pending" "$?"

# 7. --record-jira-check unblocks --verify on a subsequent run
"$INSTALLER" --record-jira-check pass --target "$TARGET1" >/dev/null
python3 -c "
import json
assert json.load(open('$TARGET1/.gsd-recipe/install-report.json'))['jira_check'] == 'pass'
"
check "--record-jira-check pass updates install-report.json's jira_check" "$?"

VERIFY_OUT1="$("$INSTALLER" --verify --target "$TARGET1")"
check "--verify now exits 0 once jira_check is no longer pending" "$?"
[ -f "$TARGET1/.gsd-recipe/INSTALL-VERIFIED.json" ]
check "--verify writes INSTALL-VERIFIED.json once unblocked" "$?"

echo "$VERIFY_OUT1" | grep -q "Observer loop composed — pass" && rc=0 || rc=$?
check "--verify output mentions observer composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "tracker-sync composed — pass" && rc=0 || rc=$?
check "--verify output mentions tracker-sync composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-planning-policy composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-planning-policy composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-run-phase composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-run-phase composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-plan-phase composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-plan-phase composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-validate-tokens composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-validate-tokens composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-bootstrap-knowledge composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-bootstrap-knowledge composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-install-verify composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-install-verify composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-run-phases composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-run-phases composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-verify-feature composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-verify-feature composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-review-ship composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-review-ship composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-settle composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-settle composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "gsd-jira-sync composed — pass" && rc=0 || rc=$?
check "--verify output mentions gsd-jira-sync composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-sync composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-sync composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-pr-comment composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-pr-comment composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-install composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-install composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-observe composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-observe composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-create-epic composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-create-epic composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-create-phase-tasks composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-create-phase-tasks composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-help composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-help composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-prd-intake composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-prd-intake composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-onboard composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-onboard composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-start composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-start composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-status composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-status composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-workspace composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-workspace composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-update composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-update composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "recipe-command-surface composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-command-surface composition" "$rc"
echo "$VERIFY_OUT1" | grep -q "config.schema.json — strict schema validation — pass" && rc=0 || rc=$?
check "--verify output mentions config.schema.json strict validation" "$rc"

python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/INSTALL-VERIFIED.json'))
for k in ('verified_at', 'gsd_version', 'tracker', 'vcs'):
    assert k in d, (k, d)
assert d['tracker'] == 'jira', d
assert d['vcs'] == 'github', d
"
check "INSTALL-VERIFIED.json matches DATA-CONTRACTS.md schema (verified_at/gsd_version/tracker/vcs)" "$?"

# 8. --record-jira-check rejects an invalid value (fail closed)
"$INSTALLER" --record-jira-check maybe --target "$TARGET1" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--record-jira-check rejects a value other than pass|fail" "$?"

# 9. --uninstall cascades to sub-installers and preserves human/shared data
TARGET3="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET3" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET3" >/dev/null

[ ! -f "$TARGET3/.templates/SPEC.template.md" ]
check "uninstall removes install-core-staged templates" "$?"
[ ! -f "$TARGET3/.cursor/skills/fotw-observer-bootstrap/SKILL.md" ]
check "uninstall cascades to install-observer.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/tracker-sync/SKILL.md" ]
check "uninstall cascades to install-tracker-sync.sh --uninstall" "$?"
[ ! -f "$TARGET3/skills/recipe-planning-policy/SKILL.md" ]
check "uninstall cascades to install-recipe-planning-policy.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-run-phase/SKILL.md" ]
check "uninstall cascades to install-recipe-run-phase.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-plan-phase/SKILL.md" ]
check "uninstall cascades to install-recipe-plan-phase.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-validate-tokens/SKILL.md" ]
check "uninstall cascades to install-recipe-validate-tokens.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "uninstall cascades to install-recipe-bootstrap-knowledge.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "uninstall cascades to install-recipe-install-verify.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-run-phases/SKILL.md" ]
check "uninstall cascades to install-recipe-run-phases.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "uninstall cascades to install-recipe-verify-feature.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "uninstall cascades to install-recipe-review-ship.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-settle/SKILL.md" ]
check "uninstall cascades to install-recipe-settle.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/gsd-jira-sync/SKILL.md" ]
check "uninstall cascades to install-gsd-jira-sync.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-sync/SKILL.md" ]
check "uninstall cascades to install-recipe-sync.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-pr-comment/SKILL.md" ] && [ ! -f "$TARGET3/bench/runners/post-github-pr-comment.sh" ]
check "uninstall cascades to install-recipe-pr-comment.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-install/SKILL.md" ]
check "uninstall cascades to install-recipe-install.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-observe/SKILL.md" ]
check "uninstall cascades to install-recipe-observe.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-create-epic/SKILL.md" ] && [ ! -f "$TARGET3/bench/runners/draft-jira-epic.sh" ]
check "uninstall cascades to install-recipe-create-epic.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-create-phase-tasks/SKILL.md" ]
check "uninstall cascades to install-recipe-create-phase-tasks.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-help/SKILL.md" ] && [ ! -f "$TARGET3/docs/RECIPE-COMMANDS.md" ] && [ ! -f "$TARGET3/docs/RECIPE-BENCHMARKS.md" ]
check "uninstall cascades to install-recipe-help.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-prd-intake/SKILL.md" ]
check "uninstall cascades to install-recipe-prd-intake.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-workspace/SKILL.md" ] &&
  [ ! -f "$TARGET3/.gsd-recipe/lib/workspace-swap.sh" ] &&
  [ ! -f "$TARGET3/.gsd-recipe/lib/initiative-branch.sh" ]
check "uninstall cascades to install-recipe-workspace.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/skills/recipe-update/SKILL.md" ] && [ ! -f "$TARGET3/.gsd-recipe/lib/recipe-update.sh" ] && [ ! -f "$TARGET3/.gsd-recipe/lib/recipe-update-nudge.sh" ]
check "uninstall cascades to install-recipe-update.sh --uninstall" "$?"
[ ! -f "$TARGET3/.cursor/rules/recipe-command-surface.mdc" ]
check "uninstall cascades to install-recipe-command-surface.sh --uninstall" "$?"

[ -d "$TARGET3/code_base_details" ] && [ -f "$TARGET3/code_base_details/README.md" ]
check "uninstall preserves code_base_details/" "$?"
[ -f "$TARGET3/.knowledge/index.md" ] && [ -f "$TARGET3/.knowledge/log.md" ]
check "uninstall preserves .knowledge/" "$?"
[ -f "$TARGET3/.gsd-recipe/config.json" ]
check "uninstall preserves config.json (the file itself is never deleted by any installer)" "$?"

python3 -c "
import json
d = json.load(open('$TARGET3/.gsd-recipe/config.json'))
assert d.get('tracker') == 'jira', d
"
check "uninstall leaves config.json's tracker value intact" "$?"

python3 -c "
import json
d = json.load(open('$TARGET3/.gsd-recipe/ledger.json'))
assert 'install-core' not in d, d
"
check "uninstall clears the install-core ledger entry" "$?"

# 10. GitHub check is resilient to gh being unavailable — install still succeeds
FAKEBIN="$(make_path_without_gh)"
TARGET4="$(new_repo)"
(cd "$TARGET4" && PATH="$FAKEBIN" "$INSTALLER" --yes --target "$TARGET4" >/dev/null 2>&1) && rc=0 || rc=$?
check "install succeeds even when gh is not on PATH" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET4/.gsd-recipe/install-report.json'))
assert d['github_check'] == 'skipped', d
"
check "github_check is recorded as 'skipped' (not a hard failure) when gh is unavailable" "$?"
rm -rf "$FAKEBIN"

# 11. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical template sources on uninstall.
#
# Safety: this copy's install.sh runs with TEMPLATES_SRC_DIR ==
# TEMPLATES_DEST_DIR's parent (self-install case) — an explicit scratch PATH
# excluding "graphify" and "uv" is used here (not relying on them simply
# being absent from this dev machine today) so PREREQ_GRAPHIFY always
# resolves to "fail" and graphify_config_enable() never fires for real, per
# this task's safety requirement. graphify/uv are just as unlikely to be
# genuinely absent on this exact dev machine as any other unconstrained
# PATH state — this makes the exclusion robust, not an accident of it.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && rm -rf .git && git init -q && git add -A && git commit -qm init)
FAKEBIN11="$(make_scratch_path_excluding "graphify uv")"
(cd "$COPY" && PATH="$FAKEBIN11" ./.gsd-recipe/scripts/install.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && PATH="$FAKEBIN11" ./.gsd-recipe/scripts/install.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/SPEC.template.md" ] && [ -f "$COPY/.gsd-recipe/templates/TDD.template.md" ] && [ -f "$COPY/.gsd-recipe/templates/bare_metal.template.md" ]
check "self-uninstall preserves the canonical template sources" "$?"
rm -rf "$FAKEBIN11"

# --- Prerequisite bootstrap (preflight/ensure_prereq) ---
# Every case below runs with a scratch PATH built from real binaries minus
# the ones under test (same technique as make_path_without_gh above) and/or
# a scratch GSD_SIGNAL_PATH — never the real ~/.cursor/skills/gsd-help/SKILL.md
# and never a real npx/brew invocation. See the safety constraints in
# bench/report/install-scaffold-integration-report.md's "Prerequisite
# bootstrap" section.

# A scratch, never-real GSD-presence signal path, matching the shape of the
# real ~/.cursor/skills/gsd-help/SKILL.md but rooted under a fresh tmpdir.
fake_gsd_signal_path() {
  echo "$(mktemp -d)/.cursor/skills/gsd-help/SKILL.md"
}

seed_fake_gsd() {
  local help_signal="$1" cursor_root
  cursor_root="$(dirname "$(dirname "$(dirname "$help_signal")")")"
  mkdir -p \
    "$(dirname "$help_signal")" \
    "$cursor_root/skills/gsd-new-project" \
    "$cursor_root/skills/gsd-map-codebase" \
    "$cursor_root/skills/gsd-graphify" \
    "$cursor_root/skills/gsd-ingest-docs" \
    "$cursor_root/agents"
  touch \
    "$help_signal" \
    "$cursor_root/skills/gsd-new-project/SKILL.md" \
    "$cursor_root/skills/gsd-map-codebase/SKILL.md" \
    "$cursor_root/skills/gsd-graphify/SKILL.md" \
    "$cursor_root/skills/gsd-ingest-docs/SKILL.md" \
    "$cursor_root/agents/gsd-roadmapper.md"
}

# Polls $2 (a log file) for literal substring $1 for up to $3 seconds.
# Used to synchronize an interactive test's scripted input against the
# installer's actual prompt output instead of guessing timing with sleep —
# a fixed sleep duration would be a flaky race against process-startup
# overhead (observed in practice under load).
wait_for_log() {
  local needle="$1" log="$2" timeout_secs="$3" i=0
  while ! grep -qF "$needle" "$log" 2>/dev/null; do
    i=$((i + 1))
    [ "$i" -gt $((timeout_secs * 10)) ] && return 1
    sleep 0.1
  done
  return 0
}

# Runs $2.. in the background and kills it if it outlives $1 seconds —
# a defensive belt-and-suspenders check on top of the production --yes
# short-circuit, so a regression in ensure_prereq's prompt loop fails this
# test suite fast instead of hanging it.
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local cmd_pid=$!
  ( sleep "$secs"; kill -9 "$cmd_pid" 2>/dev/null ) &
  local watchdog_pid=$!
  local rc
  wait "$cmd_pid" 2>/dev/null; rc=$?
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  return "$rc"
}

# --- graphify prerequisite + .planning/config.json auto-enable helpers ---
# Every graphify-specific case below runs against a fresh mktemp -d scratch
# repo with its own scratch .planning/config.json fixture and fake
# graphify/uv/gsd-tools shims (logging invocations, no real network/installs
# — same technique as the gh/brew/npx stubs above). GSD_TOOLS_CJS_PATH is
# always pointed at a scratch fake script, never the real
# ~/.claude/get-shit-done/bin/gsd-tools.cjs.

# Writes a scratch $1/.planning/config.json fixture with a pre-existing
# unrelated key + nested object, so tests can assert the fake config-set
# stub only adds "graphify.enabled" and leaves everything else untouched.
write_scratch_planning_config() {
  local target="$1"
  mkdir -p "$target/.planning"
  cat > "$target/.planning/config.json" <<'EOF'
{
  "some_other_key": "keep-me",
  "workflow": {
    "research": true
  }
}
EOF
}

# Writes a fake `graphify` binary at $1 that passes graphify_functional when
# bench/lib/graphify-probe.sh is sourced — used for preflight pass cases.
write_fake_graphify_functional() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "graphify — knowledge graph CLI (test stub)"
  exit 0
fi
exit 0
EOF
  chmod +x "$1"
}

# Writes a no-op stub that graphify_functional rejects.
write_fake_graphify_stub() {
  cat > "$1" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$1"
}

# Back-compat alias for tests that expect a working graphify on PATH.
write_fake_graphify_present() {
  write_fake_graphify_functional "$1"
}

# Writes a fake `uv` binary at $1 that, when invoked as `uv tool install ...` or
# `uv pip install ...`, logs the call to $2 and simulates a successful `graphifyy`
# install by creating a working `graphify` stub. Prefers $UV_TOOL_BIN_DIR (what
# install-graphify.sh exports) so tests catch a parent PATH that does not include
# $HOME/bin; otherwise writes to $3.
write_fake_uv_installs_graphify() {
  local uv_path="$1" log_file="$2" fakebin_dir="$3"
  cat > "$uv_path" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$log_file"
dest="\${UV_TOOL_BIN_DIR:-$fakebin_dir}"
mkdir -p "\$dest"
if [ "\$1" = "tool" ] && [ "\$2" = "install" ]; then
  cat > "\$dest/graphify" <<'INNER'
#!/usr/bin/env bash
if [ "\$1" = "--help" ] || [ "\$1" = "-h" ]; then
  echo "graphify — knowledge graph CLI (test stub)"
  exit 0
fi
exit 0
INNER
  chmod +x "\$dest/graphify"
elif [ "\$1" = "pip" ] && [ "\$2" = "install" ]; then
  cat > "\$dest/graphify" <<'INNER'
#!/usr/bin/env bash
if [ "\$1" = "--help" ] || [ "\$1" = "-h" ]; then
  echo "graphify — knowledge graph CLI (test stub)"
  exit 0
fi
exit 0
INNER
  chmod +x "\$dest/graphify"
fi
exit 0
EOF
  chmod +x "$uv_path"
}

# Writes a fake `gsd-tools` shell shim at $1 that mimics the real
# `gsd-tools config-set <key> <value> --cwd <dir>`'s effect: it sets the
# given dot-path key in <dir>/.planning/config.json (converting the
# literal strings "true"/"false" to real JSON booleans, matching the real
# tool's behavior), preserving every other pre-existing key. Logs its raw
# argv to $2 for assertions. Used for the "gsd-tools resolvable via PATH"
# branch.
write_fake_gsd_tools_shell() {
  local stub_path="$1" log_file="$2"
  cat > "$stub_path" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$log_file"
if [ "\$1" = "config-set" ]; then
  key="\$2"; value="\$3"; shift 3
  cwd="\$PWD"
  while [ \$# -gt 0 ]; do
    case "\$1" in
      --cwd) cwd="\$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  python3 - "\$cwd/.planning/config.json" "\$key" "\$value" <<'PY'
import json, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
parts = key.split(".")
node = data
for p in parts[:-1]:
    node = node.setdefault(p, {})
if value == "true":
    v = True
elif value == "false":
    v = False
else:
    v = value
node[parts[-1]] = v
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
fi
EOF
  chmod +x "$stub_path"
}

# Writes a fake gsd-tools.cjs at $1 — a node script with the same
# config-set-mimicking behavior as write_fake_gsd_tools_shell, for exercising
# the GSD_TOOLS_CJS_PATH (`node <path>`) resolution branch specifically, when
# gsd-tools itself isn't on PATH. Logs its raw argv to $2. Never the real
# ~/.claude/get-shit-done/bin/gsd-tools.cjs.
write_fake_gsd_tools_cjs() {
  local stub_path="$1" log_file="$2"
  cat > "$stub_path" <<EOF
#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const args = process.argv.slice(2);
fs.appendFileSync('$log_file', args.join(' ') + '\n');
if (args[0] === 'config-set') {
  const key = args[1];
  const value = args[2];
  let cwd = process.cwd();
  for (let i = 3; i < args.length; i++) {
    if (args[i] === '--cwd') { cwd = args[i + 1]; i++; }
  }
  const configPath = path.join(cwd, '.planning', 'config.json');
  const data = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const parts = key.split('.');
  let node = data;
  for (let i = 0; i < parts.length - 1; i++) {
    node[parts[i]] = node[parts[i]] || {};
    node = node[parts[i]];
  }
  let v = value;
  if (value === 'true') v = true;
  else if (value === 'false') v = false;
  node[parts[parts.length - 1]] = v;
  fs.writeFileSync(configPath, JSON.stringify(data, null, 2) + '\n');
}
EOF
  chmod +x "$stub_path"
}

# 12. GSD-absent case: fake npx creates the signal file when asked to install
# GSD — reverify then finds it and records gsd_core: auto_installed.
FAKEBIN12="$(make_scratch_path_excluding "npx")"
SIGNAL12="$(fake_gsd_signal_path)"
cat > "$FAKEBIN12/npx" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$FAKE_GSD_NPX_LOG"
cursor_root="$(dirname "$(dirname "$(dirname "$FAKE_GSD_SIGNAL")")")"
mkdir -p "$(dirname "$FAKE_GSD_SIGNAL")" \
  "$cursor_root/skills/gsd-new-project" "$cursor_root/skills/gsd-map-codebase" \
  "$cursor_root/skills/gsd-graphify" "$cursor_root/skills/gsd-ingest-docs" \
  "$cursor_root/agents"
touch "$FAKE_GSD_SIGNAL" \
  "$cursor_root/skills/gsd-new-project/SKILL.md" \
  "$cursor_root/skills/gsd-map-codebase/SKILL.md" \
  "$cursor_root/skills/gsd-graphify/SKILL.md" \
  "$cursor_root/skills/gsd-ingest-docs/SKILL.md" \
  "$cursor_root/agents/gsd-roadmapper.md"
EOF
chmod +x "$FAKEBIN12/npx"
TARGET12="$(new_repo)"
NPX_LOG12="$(mktemp)"
(cd "$TARGET12" && PATH="$FAKEBIN12" GSD_SIGNAL_PATH="$SIGNAL12" FAKE_GSD_SIGNAL="$SIGNAL12" \
  FAKE_GSD_NPX_LOG="$NPX_LOG12" GSD_PREFER_NPX=1 \
  "$INSTALLER" --yes --target "$TARGET12" >/dev/null 2>&1) && rc=0 || rc=$?
check "install succeeds when GSD is absent and the fake npx auto-fix creates the signal" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET12/.gsd-recipe/install-report.json'))
assert d['prereqs']['gsd_core'] == 'auto_installed', d['prereqs']
"
check "gsd_core recorded as auto_installed once the fake npx creates the signal file" "$?"
[ -f "$SIGNAL12" ]
check "fake npx auto-fix actually created the GSD signal file" "$?"
grep -q -- 'gsd-core --cursor --global --profile=full' "$NPX_LOG12"
check "GSD auto-install uses Cursor full profile (not Claude)" "$?"
grep -q 'registry.npmjs.org/@opengsd/gsd-core/latest' "$INSTALLER" &&
  ! grep -q 'strict.ssl=false\|strict_ssl=false' "$INSTALLER"
check "GSD installer has TLS-verified package fallback without disabling certificate checks" "$?"
rm -rf "$FAKEBIN12" "$(dirname "$(dirname "$SIGNAL12")")"

# 13. GSD-absent-and-npx-doesn't-fix-it case: onboarding cannot work without
# native Cursor GSD, so install fails closed instead of producing a broken repo.
FAKEBIN13="$(make_scratch_path_excluding "npx")"
SIGNAL13="$(fake_gsd_signal_path)"
cat > "$FAKEBIN13/npx" <<'EOF'
#!/usr/bin/env bash
# Deliberately a no-op — simulates an auto-fix attempt that doesn't resolve
# the prerequisite, so the fallback path is exercised.
exit 0
EOF
chmod +x "$FAKEBIN13/npx"
TARGET13="$(new_repo)"
(cd "$TARGET13" && PATH="$FAKEBIN13" GSD_SIGNAL_PATH="$SIGNAL13" GSD_PREFER_NPX=1 run_with_timeout 20 \
  "$INSTALLER" --yes --target "$TARGET13" </dev/null >/dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install fails closed when Cursor GSD auto-install does not resolve it" "$?"
[ ! -f "$TARGET13/.gsd-recipe/install-report.json" ]
check "failed Cursor GSD prerequisite aborts before writing install-report.json" "$?"
rm -rf "$FAKEBIN13" "$(dirname "$(dirname "$SIGNAL13")")"

# 14. python3 hard-fail case: absent, no brew fallback -> install.sh exits
# non-zero before touching any file (fail closed, per "checked first,
# before anything else").
FAKEBIN14="$(make_scratch_path_excluding "python3 brew")"
TARGET14="$(new_repo)"
(cd "$TARGET14" && PATH="$FAKEBIN14" run_with_timeout 20 "$INSTALLER" --yes --target "$TARGET14" >/dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install.sh exits non-zero when python3 is missing and no brew fallback exists (hard fail)" "$?"
[ ! -f "$TARGET14/.gsd-recipe/config.json" ] && [ ! -f "$TARGET14/.gsd-recipe/install-report.json" ]
check "python3 hard-fail aborts before writing config.json/install-report.json" "$?"
rm -rf "$FAKEBIN14"

# 15. git hard-fail case: absent, no brew fallback -> same fail-closed
# behavior (install.sh itself shells out to git-repo checks/ledgering).
FAKEBIN15="$(make_scratch_path_excluding "git brew")"
TARGET15="$(new_repo)"
(cd "$TARGET15" && PATH="$FAKEBIN15" run_with_timeout 20 "$INSTALLER" --yes --target "$TARGET15" >/dev/null 2>&1) && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install.sh exits non-zero when git is missing and no brew fallback exists (hard fail)" "$?"
[ ! -f "$TARGET15/.gsd-recipe/config.json" ] && [ ! -f "$TARGET15/.gsd-recipe/install-report.json" ]
check "git hard-fail aborts before writing config.json/install-report.json" "$?"
rm -rf "$FAKEBIN15"

# 16. gh auto-fix-via-fake-brew case: gh absent, brew present (records what
# it was asked to install) -> assert the fake brew was invoked with "gh".
FAKEBIN16="$(make_scratch_path_excluding "gh brew")"
BREW_LOG16="$(mktemp)"
cat > "$FAKEBIN16/brew" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$BREW_LOG16"
EOF
chmod +x "$FAKEBIN16/brew"
SIGNAL16="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL16"
TARGET16="$(new_repo)"
(cd "$TARGET16" && PATH="$FAKEBIN16" GSD_SIGNAL_PATH="$SIGNAL16" \
  "$INSTALLER" --yes --target "$TARGET16" >/dev/null 2>&1) && rc=0 || rc=$?
check "install succeeds when gh is missing but a fake brew is present (warn-only)" "$rc"
grep -qxF "install gh" "$BREW_LOG16"
check "ensure_prereq invokes the fake brew with 'install gh' when gh is absent" "$?"
python3 -c "
import json
d = json.load(open('$TARGET16/.gsd-recipe/install-report.json'))
assert d['prereqs']['gh'] == 'fail', d['prereqs']  # fake brew doesn't actually create a working gh
"
check "gh recorded as fail (warn-only) since the fake brew doesn't actually install a working gh" "$?"
rm -rf "$FAKEBIN16" "$(dirname "$(dirname "$SIGNAL16")")"

# 17. Interactive prompt-and-reverify loop: scripted stdin "fixes" the fake
# missing tool (by creating the stub) after one prompt cycle, assert install
# proceeds (not --yes, so the real interactive loop runs). Synchronized on
# the installer's actual prompt text (via a FIFO + log file) rather than a
# fixed sleep, since a wall-clock guess raced against process-startup
# overhead and was observed to flake.
FAKEBIN17="$(make_scratch_path_excluding "gh brew")"
# Pre-resolve graphify (a stub that's simply present, same as SIGNAL17 below
# for gsd_core) so preflight() doesn't open a second, unscripted interactive
# prompt for it — this test's FIFO choreography is deliberately scripted
# only for the gh prompt cycle.
write_fake_graphify_present "$FAKEBIN17/graphify"
SIGNAL17="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL17"
TARGET17="$(new_repo)"
LOG17="$(mktemp)"
FIFO17="$(mktemp -u)"
mkfifo "$FIFO17"
(cd "$TARGET17" && PATH="$FAKEBIN17" GSD_SIGNAL_PATH="$SIGNAL17" \
  "$INSTALLER" --target "$TARGET17" <"$FIFO17" >"$LOG17" 2>&1) &
INSTALL_PID17=$!
exec 9>"$FIFO17"

# Sync on the plain echo'd messages (not the read -p prompt text itself —
# bash never writes a -p prompt when stdin isn't a tty, confirmed by a
# throwaway check, so it can't be used as a sync point here).
test17_ok=1
wait_for_log "gh is missing" "$LOG17" 15 || test17_ok=0
echo "" >&9                              # 1st Enter: gh still missing at this point
wait_for_log "gh still not found" "$LOG17" 15 || test17_ok=0
printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN17/gh"
chmod +x "$FAKEBIN17/gh"                 # "fixes" the fake missing tool
echo "" >&9                              # 2nd Enter: reverify now finds it
echo "y" >&9                             # answers the "Install ...? [y/N]" consent prompt
exec 9>&-
for _ in $(seq 1 200); do kill -0 "$INSTALL_PID17" 2>/dev/null || break; sleep 0.1; done
wait "$INSTALL_PID17" 2>/dev/null; rc=$?
rm -f "$FIFO17"

[ "$test17_ok" = "1" ]
check "interactive prompt-and-reverify loop actually prompts for gh before/after the fix" "$?"
check "interactive prompt-and-reverify loop proceeds once piped stdin 'fixes' the missing tool" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET17/.gsd-recipe/install-report.json'))
assert d['prereqs']['gh'] == 'pass', d['prereqs']
"
check "gh recorded as pass after the interactive reverify loop finds the newly-created stub" "$?"
rm -rf "$FAKEBIN17" "$(dirname "$(dirname "$SIGNAL17")")" "$LOG17"

# 18. (a) graphify pre-existing + gsd-tools resolvable via PATH + target has
# a .planning/config.json -> prereqs.graphify=pass, graphify_config_enabled
# is the JSON boolean true, scratch config.json shows graphify.enabled:
# true, and the pre-existing unrelated keys survive untouched.
FAKEBIN18="$(make_scratch_path_excluding "graphify uv gsd-tools")"
write_fake_graphify_present "$FAKEBIN18/graphify"
LOG18="$(mktemp)"
write_fake_gsd_tools_shell "$FAKEBIN18/gsd-tools" "$LOG18"
SIGNAL18="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL18"
TARGET18="$(new_repo)"
write_scratch_planning_config "$TARGET18"
(cd "$TARGET18" && PATH="$FAKEBIN18" GSD_SIGNAL_PATH="$SIGNAL18" \
  "$INSTALLER" --yes --target "$TARGET18" >/dev/null 2>&1) && rc=0 || rc=$?
check "(a) install succeeds with graphify pre-existing + gsd-tools on PATH + .planning/config.json present" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET18/.gsd-recipe/install-report.json'))
assert d['prereqs']['graphify'] == 'pass', d['prereqs']
assert d['graphify_config_enabled'] is True, d['graphify_config_enabled']
"
check "(a) prereqs.graphify=pass and graphify_config_enabled=true recorded in install-report.json" "$?"
grep -qF "config-set graphify.enabled true --cwd $TARGET18" "$LOG18"
check "(a) fake gsd-tools invoked with the exact expected config-set arguments" "$?"
python3 -c "
import json
d = json.load(open('$TARGET18/.planning/config.json'))
assert d['graphify']['enabled'] is True, d
assert d['some_other_key'] == 'keep-me', d
assert d['workflow'] == {'research': True}, d
"
check "(a) scratch .planning/config.json has graphify.enabled=true, pre-existing keys untouched" "$?"
rm -rf "$FAKEBIN18" "$(dirname "$(dirname "$SIGNAL18")")" "$LOG18"

# 18b. Same as (a) but exercising the GSD_TOOLS_CJS_PATH (`node <path>`)
# fallback branch specifically — gsd-tools is NOT on PATH here, only a fake
# gsd-tools.cjs reachable via the override env var.
FAKEBIN18B="$(make_scratch_path_excluding "graphify uv gsd-tools")"
write_fake_graphify_present "$FAKEBIN18B/graphify"
LOG18B="$(mktemp)"
CJS18B="$(mktemp -d)/fake-gsd-tools.cjs"
write_fake_gsd_tools_cjs "$CJS18B" "$LOG18B"
SIGNAL18B="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL18B"
TARGET18B="$(new_repo)"
write_scratch_planning_config "$TARGET18B"
(cd "$TARGET18B" && PATH="$FAKEBIN18B" GSD_SIGNAL_PATH="$SIGNAL18B" GSD_TOOLS_CJS_PATH="$CJS18B" \
  "$INSTALLER" --yes --target "$TARGET18B" >/dev/null 2>&1) && rc=0 || rc=$?
check "(a2) install succeeds via the GSD_TOOLS_CJS_PATH node fallback (gsd-tools not on PATH)" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET18B/.gsd-recipe/install-report.json'))
assert d['graphify_config_enabled'] is True, d['graphify_config_enabled']
"
check "(a2) graphify_config_enabled=true via the node/GSD_TOOLS_CJS_PATH resolution branch" "$?"
grep -qF "config-set graphify.enabled true --cwd $TARGET18B" "$LOG18B"
check "(a2) fake gsd-tools.cjs (invoked via node) received the exact expected arguments" "$?"
python3 -c "
import json
d = json.load(open('$TARGET18B/.planning/config.json'))
assert d['graphify']['enabled'] is True, d
assert d['some_other_key'] == 'keep-me', d
"
check "(a2) scratch .planning/config.json updated via the node fallback, unrelated keys untouched" "$?"
rm -rf "$FAKEBIN18B" "$(dirname "$(dirname "$SIGNAL18B")")" "$(dirname "$CJS18B")" "$LOG18B"

# 19. (b) graphify absent + uv stubbed to succeed -> auto_installed +
# graphify_config_enabled=true.
FAKEBIN19="$(make_scratch_path_excluding "graphify uv gsd-tools")"
UVLOG19="$(mktemp)"
write_fake_uv_installs_graphify "$FAKEBIN19/uv" "$UVLOG19" "$FAKEBIN19"
LOG19="$(mktemp)"
write_fake_gsd_tools_shell "$FAKEBIN19/gsd-tools" "$LOG19"
SIGNAL19="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL19"
TARGET19="$(new_repo)"
write_scratch_planning_config "$TARGET19"
# HOME is scoped to a scratch dir here because install-graphify.sh (the
# uv_fix_cmd() target) resolves its own TOOL_BIN/cache dirs off $HOME by
# default — a real, already-populated ~/bin/graphify on the dev machine
# would otherwise leak through and short-circuit this test's fake uv.
HOME19="$(mktemp -d)"
(cd "$TARGET19" && PATH="$FAKEBIN19" GSD_SIGNAL_PATH="$SIGNAL19" HOME="$HOME19" \
  "$INSTALLER" --yes --target "$TARGET19" >/dev/null 2>&1) && rc=0 || rc=$?
check "(b) install succeeds when graphify is absent and the fake uv auto-fix installs it" "$rc"
grep -qE 'tool install .*graphifyy|pip install graphifyy' "$UVLOG19"
check "(b) ensure_prereq invokes the fake uv to install graphifyy" "$?"
grep -q -- '--quiet' "$UVLOG19"
check "(b) uv tool install was invoked with --quiet" "$?"
python3 -c "
import json
d = json.load(open('$TARGET19/.gsd-recipe/install-report.json'))
assert d['prereqs']['graphify'] == 'auto_installed', d['prereqs']
assert d['graphify_config_enabled'] is True, d['graphify_config_enabled']
"
check "(b) graphify recorded auto_installed and graphify_config_enabled=true" "$?"
[ -x "$HOME19/bin/graphify" ]
check "(b) graphify landed in HOME/bin (not only on the scratch PATH)" "$?"
rm -rf "$FAKEBIN19" "$(dirname "$(dirname "$SIGNAL19")")" "$UVLOG19" "$LOG19" "$HOME19"

# 20. (c) graphify absent + no uv on scratch PATH -> fail, warn-only, install
# still exits 0, and graphify_config_enable() never even attempts to run
# (no gsd-tools invocation at all, .planning/config.json untouched).
FAKEBIN20="$(make_scratch_path_excluding "graphify uv gsd-tools")"
LOG20="$(mktemp)"
write_fake_gsd_tools_shell "$FAKEBIN20/gsd-tools" "$LOG20"
SIGNAL20="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL20"
TARGET20="$(new_repo)"
write_scratch_planning_config "$TARGET20"
(cd "$TARGET20" && PATH="$FAKEBIN20" GSD_SIGNAL_PATH="$SIGNAL20" \
  "$INSTALLER" --yes --target "$TARGET20" >/dev/null 2>&1) && rc=0 || rc=$?
check "(c) install still exits 0 when graphify is absent and no uv fallback exists" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET20/.gsd-recipe/install-report.json'))
assert d['prereqs']['graphify'] == 'fail', d['prereqs']
assert d['graphify_config_enabled'] == 'skipped_graphify_absent', d['graphify_config_enabled']
"
check "(c) graphify recorded fail (warn-only) and graphify_config_enabled='skipped_graphify_absent'" "$?"
[ ! -s "$LOG20" ]
check "(c) graphify_config_enable() never even attempted (fake gsd-tools log file is empty)" "$?"
python3 -c "
import json
d = json.load(open('$TARGET20/.planning/config.json'))
assert 'graphify' not in d, d
assert d['some_other_key'] == 'keep-me', d
"
check "(c) .planning/config.json left completely untouched" "$?"
rm -rf "$FAKEBIN20" "$(dirname "$(dirname "$SIGNAL20")")" "$LOG20"

# 21. (d) graphify present but target has no .planning/config.json ->
# graphify_config_enabled='skipped_no_planning_config', install still exits
# 0, and no .planning/config.json is ever created.
FAKEBIN21="$(make_scratch_path_excluding "graphify uv gsd-tools")"
write_fake_graphify_present "$FAKEBIN21/graphify"
LOG21="$(mktemp)"
write_fake_gsd_tools_shell "$FAKEBIN21/gsd-tools" "$LOG21"
SIGNAL21="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL21"
TARGET21="$(new_repo)"
(cd "$TARGET21" && PATH="$FAKEBIN21" GSD_SIGNAL_PATH="$SIGNAL21" \
  "$INSTALLER" --yes --target "$TARGET21" >/dev/null 2>&1) && rc=0 || rc=$?
check "(d) install still exits 0 when graphify is present but no .planning/config.json exists yet" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET21/.gsd-recipe/install-report.json'))
assert d['prereqs']['graphify'] == 'pass', d['prereqs']
assert d['graphify_config_enabled'] == 'skipped_no_planning_config', d['graphify_config_enabled']
"
check "(d) graphify_config_enabled='skipped_no_planning_config' recorded" "$?"
[ ! -f "$TARGET21/.planning/config.json" ]
check "(d) .planning/config.json was never created by install.sh" "$?"
[ ! -s "$LOG21" ]
check "(d) fake gsd-tools was never invoked (nothing safe to enable)" "$?"
rm -rf "$FAKEBIN21" "$(dirname "$(dirname "$SIGNAL21")")" "$LOG21"

# 22. (e) graphify present, .planning/config.json present, but gsd-tools is
# absent from PATH AND GSD_TOOLS_CJS_PATH points at a nonexistent file ->
# falls back to the print-only snippet, graphify_config_enabled=false,
# install still exits 0, no crash, config.json left untouched.
FAKEBIN22="$(make_scratch_path_excluding "graphify uv gsd-tools")"
write_fake_graphify_present "$FAKEBIN22/graphify"
SIGNAL22="$(fake_gsd_signal_path)"; seed_fake_gsd "$SIGNAL22"
NONEXISTENT_CJS22="$(mktemp -u)/does-not-exist-gsd-tools.cjs"
TARGET22="$(new_repo)"
write_scratch_planning_config "$TARGET22"
CONFIG_BEFORE22="$(cat "$TARGET22/.planning/config.json")"
(cd "$TARGET22" && PATH="$FAKEBIN22" GSD_SIGNAL_PATH="$SIGNAL22" GSD_TOOLS_CJS_PATH="$NONEXISTENT_CJS22" \
  "$INSTALLER" --yes --target "$TARGET22" >/dev/null 2>&1) && rc=0 || rc=$?
check "(e) install still exits 0 when both gsd-tools and GSD_TOOLS_CJS_PATH are unavailable" "$rc"
python3 -c "
import json
d = json.load(open('$TARGET22/.gsd-recipe/install-report.json'))
assert d['prereqs']['graphify'] == 'pass', d['prereqs']
assert d['graphify_config_enabled'] is False, d['graphify_config_enabled']
"
check "(e) graphify_config_enabled=false (attempted, but gsd-tools unavailable)" "$?"
CONFIG_AFTER22="$(cat "$TARGET22/.planning/config.json")"
[ "$CONFIG_BEFORE22" = "$CONFIG_AFTER22" ]
check "(e) .planning/config.json is byte-for-byte unchanged (never a hand-rolled JSON edit)" "$?"
rm -rf "$FAKEBIN22" "$(dirname "$(dirname "$SIGNAL22")")"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
