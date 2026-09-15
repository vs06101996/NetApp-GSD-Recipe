#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-recipe-validate-tokens.sh
# (TASK-021). Matches the convention of
# bench/tests/test-install-recipe-run-phase.sh /
# bench/tests/test-install-recipe-plan-phase.sh — single-file staging shape,
# ledger tracking, fail-closed non-git target, idempotent re-install,
# uninstall cleanup, self-install collision safety, staged-content
# assertions for the skill's documented gates/behaviors — plus this task's
# own --check-github mode, exercised against fake gh stubs (never the real
# gh CLI's auth state) covering the FAIL/WARN/PASS paths and confirming no
# token value ever leaks into the output.
#
# Deliberately does NOT assert install.sh composition (RECIPE_VALIDATE_TOKENS_INSTALLER
# wiring) — install.sh is not edited by this task (parallel sibling tasks are
# editing it concurrently); see this task's integration report for the
# copy-paste-ready snippet a follow-up integration pass should apply.
#
# Run: ./bench/tests/test-install-recipe-validate-tokens.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-validate-tokens.sh"

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
# test-install.sh's make_scratch_path_excluding, so a test can drop in its
# own fake stub for those names without a real binary shadowing it.
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

# 2. Fresh install stages the skill at .cursor/skills/recipe-validate-tokens/SKILL.md
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/recipe-validate-tokens/SKILL.md" ]
check "fresh install stages .cursor/skills/recipe-validate-tokens/SKILL.md" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-validate-tokens']))")"
[ "$LEDGER_COUNT1" = "2" ]
check "fresh install records exactly 2 ledger rows (skill + --check-github script)" "$?"

[ -f "$TARGET1/.gsd-recipe/scripts/install-recipe-validate-tokens.sh" ]
check "fresh install stages .gsd-recipe/scripts/install-recipe-validate-tokens.sh on external target" "$?"
[ -x "$TARGET1/.gsd-recipe/scripts/install-recipe-validate-tokens.sh" ]
check "staged --check-github script is executable" "$?"

# 3. Never touches .gsd-recipe/config.json or .planning/config.json
[ ! -f "$TARGET1/.gsd-recipe/config.json" ]
check "install never creates .gsd-recipe/config.json" "$?"
[ ! -f "$TARGET1/.planning/config.json" ]
check "install never creates .planning/config.json" "$?"

# 4. Staged content: the documented gates/behaviors the skill requires are
# actually present in the shipped skill file.
STAGED="$TARGET1/.cursor/skills/recipe-validate-tokens/SKILL.md"

grep -q "gh auth status" "$STAGED" && rc=0 || rc=$?
check "staged skill references the real gh auth status probe" "$rc"
grep -q -- "--check-github" "$STAGED" && rc=0 || rc=$?
check "staged skill references invoking the script's --check-github mode" "$rc"
grep -q "CallMcpTool" "$STAGED" && rc=0 || rc=$?
check "staged skill references CallMcpTool for the Jira/Atlassian probe" "$rc"
grep -q "getAccessibleAtlassianResources" "$STAGED" && rc=0 || rc=$?
check "staged skill references getAccessibleAtlassianResources as the lightweight probe" "$rc"
grep -qi "entry is.*inconclusive" "$STAGED" &&
  grep -qi "wake/probe invocation" "$STAGED" && rc=0 || rc=$?
check "staged skill treats missing discovery as inconclusive and invokes the live probe" "$rc"
grep -q "mcp_auth" "$STAGED" && rc=0 || rc=$?
check "staged skill references mcp_auth as a remediation suggestion" "$rc"
grep -qi "no MCP tool-calling access" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the bash-has-no-MCP-access architectural split" "$rc"
grep -q "PASS" "$STAGED" && grep -q "WARN" "$STAGED" && grep -q "FAIL" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the PASS/WARN/FAIL summary format" "$rc"
grep -qi "never print\|never surfaces\|never prints" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims printing/logging actual token values" "$rc"
grep -qi "never fix\|do not attempt to fix\|never fixes" "$STAGED" && rc=0 || rc=$?
check "staged skill disclaims fixing/authenticating anything itself" "$rc"
grep -q "JIRA_NGAGE_TOKEN\|Bearer PAT" "$STAGED" && rc=0 || rc=$?
check "staged skill documents the OAuth-vs-Bearer-PAT distinction" "$rc"
grep -q "never touch\|Do not touch" "$STAGED" && grep -q ".gsd-recipe/config.json" "$STAGED" && rc=0 || rc=$?
check "staged skill documents never touching .gsd-recipe/config.json" "$rc"
grep -q ".planning/config.json" "$STAGED" && rc=0 || rc=$?
check "staged skill documents never touching .planning/config.json" "$rc"
grep -qi "never block\|does not block\|never abort\|non-blocking" "$STAGED" && rc=0 || rc=$?
check "staged skill documents non-blocking behavior" "$rc"

# 5. Idempotent re-run: no duplicate ledger rows
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-validate-tokens']))")"
[ "$LEDGER_COUNT2" = "2" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes the skill and clears the ledger entry
TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null

[ ! -f "$TARGET2/.cursor/skills/recipe-validate-tokens/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET2/.gsd-recipe/scripts/install-recipe-validate-tokens.sh" ]
check "uninstall removes the staged --check-github script" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET2/.gsd-recipe/ledger.json')); print('recipe-validate-tokens' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"
[ ! -d "$TARGET2/.cursor/skills/recipe-validate-tokens" ]
check "uninstall cleans up the now-empty skill directory" "$?"

# 7. Self-install case (installing into a copy of this repo) does not error
# and preserves canonical source on uninstall.
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-validate-tokens.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-validate-tokens.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-validate-tokens-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"
rm -rf "$COPY"

# --- --check-github mode: real script logic, fake gh stubs (never the real
# gh CLI's actual auth state — the manual verification report covers that
# separately, against real gh, per the task's real-environment requirement).

# 8. gh completely absent from PATH -> FAIL, exit 0 (never fails closed)
FAKEBIN_ABSENT="$(make_scratch_path_excluding "gh")"
OUT8="$(PATH="$FAKEBIN_ABSENT" "$INSTALLER" --check-github)" && rc=0 || rc=$?
check "--check-github exits 0 even when gh is completely absent" "$rc"
printf '%s' "$OUT8" | grep -q "GitHub: FAIL" && rc=0 || rc=$?
check "--check-github reports FAIL when gh is absent from PATH" "$rc"
printf '%s' "$OUT8" | grep -qi "gh auth login" && rc=0 || rc=$?
check "--check-github's FAIL case suggests 'gh auth login' remediation" "$rc"
rm -rf "$FAKEBIN_ABSENT"

# 9. gh present but not authenticated -> WARN, exit 0
FAKEBIN_UNAUTH="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_UNAUTH/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "You are not logged into any GitHub hosts." >&2
  exit 1
fi
exit 1
EOF
chmod +x "$FAKEBIN_UNAUTH/gh"
OUT9="$(PATH="$FAKEBIN_UNAUTH" "$INSTALLER" --check-github)" && rc=0 || rc=$?
check "--check-github exits 0 when gh is present but unauthenticated" "$rc"
printf '%s' "$OUT9" | grep -q "GitHub: WARN" && rc=0 || rc=$?
check "--check-github reports WARN when gh is present but unauthenticated" "$rc"
rm -rf "$FAKEBIN_UNAUTH"

# 10. gh authenticated, but the "gh api user" probe fails -> WARN, exit 0
FAKEBIN_APIFAIL="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_APIFAIL/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "github.com"
  echo "  Logged in to github.com account faketestuser (keyring)"
  echo "  Token scopes: 'repo', 'workflow'"
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  exit 1
fi
exit 1
EOF
chmod +x "$FAKEBIN_APIFAIL/gh"
OUT10="$(PATH="$FAKEBIN_APIFAIL" "$INSTALLER" --check-github)" && rc=0 || rc=$?
check "--check-github exits 0 when the api probe fails after a successful auth status" "$rc"
printf '%s' "$OUT10" | grep -q "GitHub: WARN" && rc=0 || rc=$?
check "--check-github reports WARN when 'gh api user' fails despite auth status success" "$rc"
rm -rf "$FAKEBIN_APIFAIL"

# 11. gh fully authenticated -> PASS, exit 0, scopes surfaced, and the fake
# token value never leaks into the script's output.
FAKEBIN_PASS="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN_PASS/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "status" ]; then
  echo "github.com"
  echo "  Logged in to github.com account faketestuser (keyring)"
  echo "  Active account: true"
  echo "  Token: gho_FAKETOKENDONOTLEAK1234567890"
  echo "  Token scopes: 'gist', 'read:org', 'repo', 'workflow'"
  exit 0
fi
if [ "$1" = "api" ] && [ "$2" = "user" ]; then
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN_PASS/gh"
OUT11="$(PATH="$FAKEBIN_PASS" "$INSTALLER" --check-github)" && rc=0 || rc=$?
check "--check-github exits 0 for the fully-authenticated case" "$rc"
printf '%s' "$OUT11" | grep -q "GitHub: PASS" && rc=0 || rc=$?
check "--check-github reports PASS when gh is authenticated and the api probe succeeds" "$rc"
printf '%s' "$OUT11" | grep -q "Token scopes: 'gist', 'read:org', 'repo', 'workflow'" && rc=0 || rc=$?
check "--check-github's PASS case surfaces real scopes parsed from gh auth status" "$rc"
printf '%s' "$OUT11" | grep -q "faketestuser" && rc=0 || rc=$?
check "--check-github's PASS case surfaces the logged-in username" "$rc"
printf '%s' "$OUT11" | grep -q "FAKETOKENDONOTLEAK" && rc=1 || rc=0
check "--check-github never leaks the raw token value into its output" "$rc"
rm -rf "$FAKEBIN_PASS"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
