#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-install-verify.sh
# (TASK-023). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh / test-install-recipe-plan-phase.sh —
# single-skill staging shape (plus this task's second staged file,
# bench/lib/install-verify-report.sh), ledger tracking, fail-closed non-git
# target, idempotent re-install, uninstall cleanup, self-install collision
# safety, staged-content assertions for the skill's documented gates/
# behaviors, and a standalone functional check of the report-writer library
# itself (bench/lib/install-verify-report.sh's record/summary subcommands
# and its 1-7-blocking / 8-10-warn-only install_verified computation).
# Run: ./bench/tests/test-install-recipe-install-verify.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-install-verify.sh"
REPORT_LIB="$REPO_ROOT/bench/lib/install-verify-report.sh"

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

# 2. Fresh install stages the skill at .cursor/skills/recipe-install-verify/SKILL.md
# (invoke-by-name Cursor skill, same shape as recipe-run-phase/recipe-plan-phase).
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-install-verify/SKILL.md" "$?"

# 3. Also stages its runtime dependency, bench/lib/install-verify-report.sh
[ -f "$TARGET1/bench/lib/install-verify-report.sh" ]
check "fresh install stages bench/lib/install-verify-report.sh" "$?"
[ -x "$TARGET1/bench/lib/install-verify-report.sh" ]
check "staged install-verify-report.sh is executable" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-install-verify']))")"
[ "$LEDGER_COUNT1" = "2" ]
check "fresh install records exactly 2 ledger rows (skill + lib)" "$?"

# 4. Never touches .gsd-recipe/config.json, .gsd-recipe/install-report.json, or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.gsd-recipe/install-report.json" ]
check "install never creates .gsd-recipe/install-report.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 5. Staged content: the workflow steps and documented gates/behaviors the
# plan requires are actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-install-verify/SKILL.md"

grep -q "install.sh --verify" "$STAGED" && rc=0 || rc=$?
check "staged skill references calling install.sh --verify as the bash foundation" "$rc"
grep -q "/gsd-health" "$STAGED" && rc=0 || rc=$?
check "staged skill references native /gsd-health (item 1)" "$rc"
grep -q -- "--context" "$STAGED" && rc=0 || rc=$?
check "staged skill references /gsd-health --context (item 2)" "$rc"
grep -qi "gsd-surface status" "$STAGED" && rc=0 || rc=$?
check "staged skill references /gsd-surface status (item 3)" "$rc"
grep -q "recipe-validate-tokens" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the recipe-validate-tokens delegation (item 4)" "$rc"
grep -q "gh auth status" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the minimal gh auth status fallback (item 4)" "$rc"
grep -qi "MCP" "$STAGED" && rc=0 || rc=$?
check "staged skill references MCP tool listing (item 8)" "$rc"
grep -q "getAccessibleAtlassianResources" "$STAGED" && rc=0 || rc=$?
check "staged skill requires a live read-only Atlassian probe before Jira pass" "$rc"
grep -q -- '\$INSTALL_SH --record-jira-check pass --target <target>' "$STAGED" && rc=0 || rc=$?
check "staged skill records a live Jira pass through the script escape hatch" "$rc"
python3 - "$STAGED" <<'PY'
import sys
text = open(sys.argv[1]).read()
record = text.index("$INSTALL_SH --record-jira-check pass --target <target>")
rerun = text.index("$INSTALL_SH --verify --target <target>", record)
assert record < rerun
PY
check "staged skill reruns --verify after recording Jira pass in the same turn" "$?"
grep -q "INSTALL-VERIFIED.json.*one Agent turn\|one Agent turn.*INSTALL-VERIFIED.json" "$STAGED" && rc=0 || rc=$?
check "staged skill documents one-turn INSTALL-VERIFIED completion" "$rc"
grep -q "observer-config.json" "$STAGED" && rc=0 || rc=$?
check "staged skill references observer-config.json (item 9)" "$rc"
grep -q "bare_metal.template.md" "$STAGED" && rc=0 || rc=$?
check "staged skill references bare_metal.template.md (item 10)" "$rc"
grep -qi "never fabricate\|never invent" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fabricating repo-specific bootstrap commands" "$rc"
grep -q "install_verified" "$STAGED" && rc=0 || rc=$?
check "staged skill references the install_verified marker" "$rc"
grep -qi "never hard-block\|never hard block\|never blocks the operator" "$STAGED" && rc=0 || rc=$?
check "staged skill documents that it never hard-blocks the operator" "$rc"
grep -q "Option B" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the Option B precedent for native command calls" "$rc"
grep -q "install-verify-report.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill references bench/lib/install-verify-report.sh" "$rc"
grep -qi "does not duplicate\|never duplicat" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims duplicating install.sh --verify / recipe-validate-tokens" "$rc"

# 6. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-install-verify']))")"
[ "$LEDGER_COUNT2" = "2" ]
check "re-running install does not duplicate ledger rows" "$?"

# 7. Uninstall removes both staged files and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-install-verify/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/bench/lib/install-verify-report.sh" ]
check "uninstall removes the staged report-writer lib" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-install-verify' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-install-verify" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 8. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && rm -f .git && git init -q && git add -A && git commit -qm init)
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-install-verify.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-install-verify.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-install-verify-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
[ -f "$COPY/bench/lib/install-verify-report.sh" ]
check "self-uninstall preserves the canonical report-writer lib source" "$?"

# 9. Functional check of bench/lib/install-verify-report.sh itself: record +
# summary + the 1-7-blocking / 8-10-warn-only install_verified computation.
SCRATCH_REPORT="$(mktemp -d)/install-report.json"

# Record items 1-7 as pass, item 8 as warn, item 9 as warn, item 10 as fail —
# per the checklist's own failure-handling rule, install_verified should be
# true (8-10 never gate the marker, even when one of them is a fail).
"$REPORT_LIB" record 1 "GSD integrity" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 2 "Context headroom" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 3 "Capability surface" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 4 "Token still valid" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 5 "Templates present" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 6 "OKF index" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 7 "Gitignore" pass --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 8 "MCP reachable" warn --detail "not configured" --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 9 "Observer loop scheduled" warn --detail "absent, expected for v1" --report "$SCRATCH_REPORT" >/dev/null
"$REPORT_LIB" record 10 "Bare metal Gate A" fail --detail "smoke command exited 1" --report "$SCRATCH_REPORT" >/dev/null

INSTALL_VERIFIED="$(python3 -c "import json; print(json.load(open('$SCRATCH_REPORT'))['install_verified'])")"
[ "$INSTALL_VERIFIED" = "True" ]
check "install_verified is true when items 1-7 all pass, regardless of 8-10" "$?"

RIV_VERIFIED="$(python3 -c "import json; print(json.load(open('$SCRATCH_REPORT'))['recipe_install_verify']['install_verified'])")"
[ "$RIV_VERIFIED" = "True" ]
check "recipe_install_verify.install_verified mirrors the top-level marker" "$?"

ITEM10_STATUS="$(python3 -c "import json; print(json.load(open('$SCRATCH_REPORT'))['recipe_install_verify']['items']['10']['status'])")"
[ "$ITEM10_STATUS" = "fail" ]
check "item 10's individual fail status is preserved even though it doesn't block the marker" "$?"

# 10. Now fail one of the 1-7 blocking items and confirm install_verified flips false.
"$REPORT_LIB" record 3 "Capability surface" fail --detail "gsd-surface errored" --report "$SCRATCH_REPORT" >/dev/null
INSTALL_VERIFIED_2="$(python3 -c "import json; print(json.load(open('$SCRATCH_REPORT'))['install_verified'])")"
[ "$INSTALL_VERIFIED_2" = "False" ]
check "install_verified flips to false when any of items 1-7 fails" "$?"

# 11. install-verify-report.sh rejects an invalid status value
"$REPORT_LIB" record 1 "GSD integrity" bogus --report "$SCRATCH_REPORT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install-verify-report.sh rejects an invalid status value" "$?"

# 12. install-verify-report.sh rejects an out-of-range item number
"$REPORT_LIB" record 11 "Out of range" pass --report "$SCRATCH_REPORT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install-verify-report.sh rejects an item number outside 1-10" "$?"

# 13. summary subcommand runs cleanly against a populated report
"$REPORT_LIB" summary --report "$SCRATCH_REPORT" >/dev/null 2>&1 && rc=0 || rc=$?
check "install-verify-report.sh summary runs cleanly against a populated report" "$rc"

# 14. summary subcommand fails gracefully against a missing report
"$REPORT_LIB" summary --report "$(mktemp -u)" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "install-verify-report.sh summary fails (non-zero) when the report doesn't exist yet" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
