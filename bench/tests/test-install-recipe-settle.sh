#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-settle.sh (TASK-027).
# Matches the convention of bench/tests/test-install-recipe-validate-tokens.sh
# — single-file staging shape, ledger tracking, fail-closed non-git target,
# idempotent re-install, uninstall cleanup, self-install collision safety,
# staged-content assertions for the skill's documented gates/behaviors — plus
# this task's own --check-ci mode, exercised against fake gh stubs (never the
# real gh CLI's actual auth/CI state — the integration report's manual
# verification section covers real gh separately) covering PASS/FAIL/WARN
# branches and confirming no credential value ever leaks into the output.
#
# Deliberately does NOT assert install.sh composition (RECIPE_SETTLE_INSTALLER
# wiring) — install.sh is not edited by this task (parallel sibling tasks are
# editing it concurrently); see this task's integration report for the
# copy-paste-ready snippet a follow-up integration pass should apply.
#
# Run: ./bench/tests/test-install-recipe-settle.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-settle.sh"

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

# Builds a scratch PATH from every real PATH binary, excluding whichever
# names are listed in $1 (space separated) — same technique as
# test-install.sh's/test-install-recipe-validate-tokens.sh's
# make_scratch_path_excluding, so a test can drop in its own fake stub for
# those names without a real binary shadowing it.
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

# 2. Fresh install stages the skill at .cursor/skills/recipe-settle/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-settle/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-settle/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-settle']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the documented gates/behaviors the skill requires are
# actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-settle/SKILL.md"

grep -q "gh pr checks" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real gh pr checks probe" "$rc"
grep -q -- "--check-ci" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking the script's --check-ci mode" "$rc"
grep -q "check-runs" "$STAGED" && rc=0 || rc=$?
check "staged skill references the gh api check-runs fallback" "$rc"
grep -q "CI: PASS" "$STAGED" && grep -q "CI: FAIL" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the CI: PASS/FAIL/WARN summary format" "$rc"
grep -qi "PO-accept\|PO accept" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the PO-accept gate" "$rc"
grep -qi "y/n" "$STAGED" && rc=0 || rc=$?
check "staged skill documents an explicit y/n confirmation question" "$rc"
grep -qi "never skippable\|not skippable\|no skip\|no flag" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims any flag/skip mechanism for the PO-accept gate" "$rc"
grep -qi "genuine human gate\|genuine, real-time human" "$STAGED" && rc=0 || rc=$?
check "staged skill has a 'genuine human gate, not skippable' section" "$rc"
grep -qi "no settled event should be posted\|no .settled. event" "$STAGED" && rc=0 || rc=$?
check "staged skill quotes FAILURE-MATRIX.md's 'no settled event should be posted' rule" "$rc"
grep -qi "do not call .gsd-jira-sync. at all when CI is not\|never call \`gsd-jira-sync\`" "$STAGED" && rc=0 || rc=$?
check "staged skill states it never calls gsd-jira-sync when CI is not green" "$rc"
grep -q "gsd-jira-sync" "$STAGED" && rc=0 || rc=$?
check "staged skill invokes gsd-jira-sync by name (Option B skill-to-skill)" "$rc"
grep -q "Why Option B" "$STAGED" && rc=0 || rc=$?
check "staged skill has a 'Why Option B' section for the gsd-jira-sync invocation" "$rc"
grep -q "sync-ledger.sh" "$STAGED" && rc=0 || rc=$?
check "staged skill uses sync-ledger.sh for settled idempotency" "$rc"
grep -q "resolve-issue settled\|resolve-issue .settled." "$STAGED" && rc=0 || rc=$?
check "staged skill resolves the settled event via parse-state.sh resolve-issue settled" "$rc"
grep -q "resolve-issue settled --phase N" "$STAGED" && rc=0 || rc=$?
check "staged skill resolves settled against phase N" "$rc"
grep -qi "phase-routed" "$STAGED" && rc=0 || rc=$?
check "staged skill documents settled as a phase-routed event" "$rc"
grep -qi "every.*phase task.*Done\|all.*phase tasks.*Done" "$STAGED" && rc=0 || rc=$?
check "staged skill closes the Epic only after all phase tasks are Done" "$rc"
grep -qi "fail-open" "$STAGED" && rc=0 || rc=$?
check "staged skill documents fail-open behavior on a missing phase task" "$rc"
grep -qi "never fabricat" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fabricating a CI result" "$rc"
grep -qi "out of scope\|parked" "$STAGED" && grep -qi "grader" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the project-specific grader hook as parked/out of scope" "$rc"
grep -q "read -p" "$STAGED" && rc=0 || rc=$?
check "staged skill explicitly disclaims a bash read -p implementation for the PO gate" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-settle']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-settle/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-settle' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-settle" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-settle.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-settle.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-settle-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
rm -rf "$COPY"

# --- --check-ci mode: real script logic, fake gh stubs (never the real gh
# CLI's actual CI state -- the integration report's manual verification
# covers real gh separately, against a real public GitHub PR).

# 8. gh completely absent from PATH -> FAIL, exit 0 (never fails closed)
FAKEBIN_ABSENT="$(make_scratch_path_excluding "gh")"
OUT8="$(PATH="$FAKEBIN_ABSENT" "$INSTALLER" --check-ci some/repo somebranch)" && rc=0 || rc=$?
check "--check-ci exits 0 even when gh is completely absent" "$rc"
printf '%s' "$OUT8" | grep -q "CI: FAIL" && rc=0 || rc=$?
check "--check-ci reports FAIL when gh is absent from PATH" "$rc"
printf '%s' "$OUT8" | grep -qi "gh auth login" && rc=0 || rc=$?
check "--check-ci's absent-gh FAIL case suggests 'gh auth login' remediation (warn detail)" "$rc"
rm -rf "$FAKEBIN_ABSENT"

# 9. All checks green -> PASS, exit 0, check names surfaced
FAKEBIN_PASS="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_PASS/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo '[{"bucket":"pass","name":"build","state":"SUCCESS"},{"bucket":"pass","name":"unit-tests","state":"SUCCESS"}]'
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN_PASS/gh"
OUT9="$(PATH="$FAKEBIN_PASS" GH_TOKEN="FAKETOKENDONOTLEAK1234567890" "$INSTALLER" --check-ci my-org/my-repo 42)" && rc=0 || rc=$?
check "--check-ci exits 0 for the all-green case" "$rc"
printf '%s' "$OUT9" | grep -q "CI: PASS" && rc=0 || rc=$?
check "--check-ci reports PASS when all checks are green" "$rc"
printf '%s' "$OUT9" | grep -q "pass: build" && printf '%s' "$OUT9" | grep -q "pass: unit-tests" && rc=0 || rc=$?
check "--check-ci's PASS case surfaces each check's real name" "$rc"
printf '%s' "$OUT9" | grep -q "FAKETOKENDONOTLEAK" && rc=1 || rc=0
check "--check-ci never leaks a credential/token value into its output (PASS case)" "$rc"
rm -rf "$FAKEBIN_PASS"

# 10. Some checks failing -> FAIL, exit 0
FAKEBIN_FAILING="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_FAILING/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo '[{"bucket":"pass","name":"build","state":"SUCCESS"},{"bucket":"fail","name":"unit-tests","state":"FAILURE"}]'
  exit 1
fi
exit 1
EOF
chmod +x "$FAKEBIN_FAILING/gh"
OUT10="$(PATH="$FAKEBIN_FAILING" "$INSTALLER" --check-ci my-org/my-repo 42)" && rc=0 || rc=$?
check "--check-ci exits 0 when one or more checks are genuinely failing" "$rc"
printf '%s' "$OUT10" | grep -q "CI: FAIL" && rc=0 || rc=$?
check "--check-ci reports FAIL when checks are failing" "$rc"
rm -rf "$FAKEBIN_FAILING"

# 11. Some checks still pending (gh pr checks exit code 8) -> FAIL, exit 0
# (pending is never treated as green -- the settle gate requires PASS only)
FAKEBIN_PENDING="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_PENDING/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo '[{"bucket":"pass","name":"build","state":"SUCCESS"},{"bucket":"pending","name":"unit-tests","state":"PENDING"}]'
  exit 8
fi
exit 1
EOF
chmod +x "$FAKEBIN_PENDING/gh"
OUT11="$(PATH="$FAKEBIN_PENDING" "$INSTALLER" --check-ci my-org/my-repo 42)" && rc=0 || rc=$?
check "--check-ci exits 0 when checks are still pending" "$rc"
printf '%s' "$OUT11" | grep -q "CI: FAIL" && rc=0 || rc=$?
check "--check-ci reports FAIL (never PASS) when checks are pending, not yet green" "$rc"
printf '%s' "$OUT11" | grep -qi "pending" && rc=0 || rc=$?
check "--check-ci's pending case mentions 'pending' in its detail" "$rc"
rm -rf "$FAKEBIN_PENDING"

# 12. gh authenticated, no PR for this ref, but the check-runs API fallback
# succeeds and is all-green -> PASS via the fallback path
FAKEBIN_FALLBACK_PASS="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_FALLBACK_PASS/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo 'no pull requests found for branch "some-sha"' >&2
  exit 1
fi
if [ "$1" = "api" ]; then
  echo '{"total_count":2,"check_runs":[{"name":"build","status":"completed","conclusion":"success"},{"name":"test","status":"completed","conclusion":"success"}]}'
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN_FALLBACK_PASS/gh"
OUT12="$(PATH="$FAKEBIN_FALLBACK_PASS" "$INSTALLER" --check-ci my-org/my-repo deadbeef)" && rc=0 || rc=$?
check "--check-ci exits 0 for the no-PR check-runs-API-fallback PASS case" "$rc"
printf '%s' "$OUT12" | grep -q "CI: PASS" && rc=0 || rc=$?
check "--check-ci falls back to the check-runs API and reports PASS when no PR exists for the ref" "$rc"
rm -rf "$FAKEBIN_FALLBACK_PASS"

# 13. gh authenticated, no PR for this ref, and the check-runs API fallback
# also fails outright -> WARN (inconclusive, never treated as green)
FAKEBIN_WARN="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_WARN/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "checks" ]; then
  echo 'no pull requests found for branch "some-sha"' >&2
  exit 1
fi
if [ "$1" = "api" ]; then
  echo 'gh: Not Found (HTTP 404)' >&2
  exit 1
fi
exit 1
EOF
chmod +x "$FAKEBIN_WARN/gh"
OUT13="$(PATH="$FAKEBIN_WARN" "$INSTALLER" --check-ci my-org/my-repo deadbeef)" && rc=0 || rc=$?
check "--check-ci exits 0 for the no-PR-and-API-fails WARN case" "$rc"
printf '%s' "$OUT13" | grep -q "CI: WARN" && rc=0 || rc=$?
check "--check-ci reports WARN (never PASS) when no PR exists and the check-runs API also fails" "$rc"
rm -rf "$FAKEBIN_WARN"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
