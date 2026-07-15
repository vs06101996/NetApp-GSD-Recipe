#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-verify-feature.sh
# (TASK-025). Matches the convention of
# bench/tests/test-install-recipe-bootstrap-knowledge.sh /
# test-install-recipe-run-phase.sh — single-file staging shape, ledger
# tracking, fail-closed non-git target, idempotent re-install, uninstall
# cleanup, self-install collision safety, plus staged-content assertions for
# the skill's documented steps/gates/behaviors/decisions.
#
# Deliberately does NOT assert install.sh composition (unlike
# test-install-recipe-run-phase.sh's § 8) — TASK-025 was built in parallel
# with sibling tasks (TASK-018/026/027) concurrently editing install.sh/
# test-install.sh/BACKLOG.md/README.md, so composition is deferred to a
# follow-up integration pass (see
# bench/report/recipe-verify-feature-integration-report.md for the exact
# snippets to apply then). This file only ever tests this installer
# standalone.
#
# Run: ./bench/tests/test-install-recipe-verify-feature.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-verify-feature.sh"

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
# .cursor/skills/recipe-verify-feature/SKILL.md (invoke-by-name Cursor
# skill, NOT the plain top-level skills/ path used by
# recipe-planning-policy's agent_skills injection mechanism).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-verify-feature/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-verify-feature']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json, .planning/config.json,
# .planning/STATE.md, or .gsd-recipe/sync-ledger.jsonl — tracker resolution
# and idempotent sync are the staged skill's own runtime job, not the
# installer's.
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"
[ ! -f "$TARGET1/.planning/STATE.md" ]
check "install never creates .planning/STATE.md" "$?"
[ ! -f "$TARGET1/.gsd-recipe/sync-ledger.jsonl" ]
check "install never creates .gsd-recipe/sync-ledger.jsonl itself (that's the staged skill's runtime job)" "$?"

# 4. Staged content: the workflow steps and documented gates/behaviors/
# decisions the task brief requires are actually present in the shipped
# skill file.
STAGED="$TARGET1/.cursor/skills/recipe-verify-feature/SKILL.md"

grep -q "gsd-audit-milestone" "$STAGED" && rc=0 || rc=$?
check "staged skill references native gsd-audit-milestone" "$rc"
grep -q "gsd-audit-uat" "$STAGED" && rc=0 || rc=$?
check "staged skill references native gsd-audit-uat" "$rc"
grep -q "gsd-verify-work" "$STAGED" && rc=0 || rc=$?
check "staged skill references native gsd-verify-work" "$rc"
grep -qi "conversational\|interactive" "$STAGED" && rc=0 || rc=$?
check "staged skill documents gsd-verify-work as conversational/interactive" "$rc"
grep -qi "not.*script\|never script\|do not.*script" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims scripting/automating gsd-verify-work's conversation" "$rc"
grep -q "verify_complete" "$STAGED" && rc=0 || rc=$?
check "staged skill references the verify_complete tracker event" "$rc"
grep -q "gsd-jira-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes the gsd-jira-sync skill (not inlined Jira logic)" "$rc"
grep -q "sync-ledger.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references sync-ledger.sh idempotency" "$rc"
grep -q "resolve-issue" "$STAGED" && rc=0 || rc=$?
check "staged skill resolves the tracker issue key via parse-state.sh resolve-issue" "$rc"
grep -qi "fail-open\|warn and continue\|never block\|does not block" "$STAGED" && rc=0 || rc=$?
check "staged skill documents fail-open behavior when no tracker issue is linked" "$rc"
grep -q "manual GSD trigger\|manual.*trigger" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the Option-B same-turn-call reasoning" "$rc"
grep -qi "never fabricate\|never invent" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fabricating audit/verification results" "$rc"
grep -qi "warn-and-skip\|warn and skip" "$STAGED" && rc=0 || rc=$?
check "staged skill documents graceful warn-and-skip for gsd-audit-milestone/gsd-audit-uat" "$rc"
grep -qi "bootstrap gate" "$STAGED" && rc=0 || rc=$?
check "staged skill documents Bootstrap Gate A/B as explicitly out of scope" "$rc"
grep -qi "gsd-debug" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the gsd-debug recovery loop as explicitly out of scope" "$rc"
grep -qi "grader" "$STAGED" && rc=0 || rc=$?
check "staged skill documents any benchmark/project-specific grader hook as explicitly out of scope" "$rc"
grep -q "gsd-audit-fix" "$STAGED" && rc=0 || rc=$?
check "staged skill documents gsd-audit-fix as explicitly out of scope (separate operator follow-up)" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-verify-feature']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-verify-feature/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-verify-feature' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-verify-feature" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-verify-feature.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-verify-feature.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-verify-feature-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
