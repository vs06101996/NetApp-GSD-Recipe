#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh
# (TASK-022). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh / test-install-recipe-plan-phase.sh
# — single-file staging shape, ledger tracking, fail-closed non-git target,
# idempotent re-install, uninstall cleanup, self-install collision safety,
# plus staged-content assertions for the skill's documented steps/behaviors.
#
# Deliberately does NOT assert install.sh composition (unlike
# test-install-recipe-run-phase.sh's § 8) — TASK-022 was built in parallel
# with sibling tasks concurrently editing install.sh/test-install.sh, so
# composition is deferred to a follow-up integration pass (see
# bench/report/recipe-bootstrap-knowledge-integration-report.md for the exact
# install.sh/test-install.sh snippets to apply then). This file only ever
# tests this installer standalone.
#
# Run: ./bench/tests/test-install-recipe-bootstrap-knowledge.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh"

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

# 1. Refuses to install outside a git repo (fail closed)
NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"

# 2. Fresh install stages the skill at
# .cursor/skills/recipe-bootstrap-knowledge/SKILL.md (invoke-by-name Cursor
# skill, NOT the plain top-level skills/ path used by
# recipe-planning-policy's agent_skills injection mechanism).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-bootstrap-knowledge/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-bootstrap-knowledge']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json, .planning/config.json, or
# .knowledge/ / code_base_details/ — those are the staged skill's own
# runtime job, not the installer's.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -d "$TARGET1/.knowledge" ]
check "install never creates .knowledge/ itself (that's the staged skill's runtime job)" "$?"
[ ! -d "$TARGET1/code_base_details" ]
check "install never creates code_base_details/ itself" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors the
# plan requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md"

grep -q "gsd-map-codebase" "$STAGED" && rc=0 || rc=$?
check "staged skill references native /gsd-map-codebase" "$rc"
grep -q "gsd-graphify" "$STAGED" && rc=0 || rc=$?
check "staged skill references native /gsd-graphify build" "$rc"
grep -q "gsd-ingest-docs" "$STAGED" && rc=0 || rc=$?
check "staged skill references native /gsd-ingest-docs" "$rc"
grep -q "ingest-manifest.yaml" "$STAGED" && rc=0 || rc=$?
check "staged skill references .gsd-recipe/ingest-manifest.yaml" "$rc"
grep -qi "skip\|warn" "$STAGED" && rc=0 || rc=$?
check "staged skill documents a graceful skip/warn for a missing ingest manifest" "$rc"
grep -q "hard-fail\|hard block" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims hard-failing when the manifest is missing" "$rc"
grep -q "architecture/" "$STAGED" && grep -q "dependency-graph/" "$STAGED" && grep -q "hot-files/" "$STAGED" && grep -q "risk-register/" "$STAGED" && rc=0 || rc=$?
check "staged skill enumerates all 4 .knowledge/ subdirectories to scaffold" "$rc"
grep -qi "never overwrite\|never touch\|untouched" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims overwriting existing .knowledge/ content (idempotent)" "$rc"
grep -q "code_base_details" "$STAGED" && rc=0 || rc=$?
check "staged skill references preserving human-authored code_base_details/" "$rc"
grep -q "manual GSD trigger" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the Option-B same-turn-call reasoning" "$rc"
grep -q "type: index\|type: log" "$STAGED" && rc=0 || rc=$?
check "staged skill references OKF frontmatter placeholders" "$rc"
grep -q "gsd-extract-learnings\|gsd-capture" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims wrapping gsd-extract-learnings/gsd-capture (out of scope)" "$rc"
grep -q "dag" "$STAGED" && rc=0 || rc=$?
check "staged skill documents .knowledge/dag/ as explicitly out of scope" "$rc"
grep -q "recipe-verify-knowledge.sh --write-marker" "$STAGED" && rc=0 || rc=$?
check "staged skill writes marker only via verify guardrail" "$rc"
grep -q "recipe-verify-knowledge" "$STAGED" && rc=0 || rc=$?
check "staged skill references recipe-verify-knowledge guardrail" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-bootstrap-knowledge']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-bootstrap-knowledge/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-bootstrap-knowledge' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-bootstrap-knowledge" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-bootstrap-knowledge-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
