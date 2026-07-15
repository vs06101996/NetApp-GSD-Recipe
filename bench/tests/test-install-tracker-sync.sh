#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-tracker-sync.sh (TASK-014).
# Matches the convention of bench/tests/test-install-recipe-prd-intake.sh.
# Run: ./bench/tests/test-install-tracker-sync.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-tracker-sync.sh"
CONFIG_LIB="$REPO_ROOT/bench/lib/tracker-sync-config.sh"

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

# 2. Fresh install stages the skill and defaults config.json's tracker to jira
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/skills/tracker-sync/SKILL.md" ]
check "fresh install stages .cursor/skills/tracker-sync/SKILL.md" "$?"

OUT1="$(REPO_ROOT="$TARGET1" "$CONFIG_LIB" get-tracker --config "$TARGET1/.gsd-recipe/config.json")"
[ "$OUT1" = "jira" ]
check "fresh install initializes config.json's tracker to jira (default)" "$?"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['tracker-sync']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row (the skill file)" "$?"

# 3. The staged skill references gsd-jira-sync (delegation, not reimplementation)
grep -q "gsd-jira-sync" "$TARGET1/.cursor/skills/tracker-sync/SKILL.md" && rc=0 || rc=$?
check "staged skill references gsd-jira-sync (delegates, doesn't reimplement)" "$rc"

# 4. Idempotent re-run: no duplicate ledger rows, tracker value unchanged
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['tracker-sync']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

OUT2="$(REPO_ROOT="$TARGET1" "$CONFIG_LIB" get-tracker --config "$TARGET1/.gsd-recipe/config.json")"
[ "$OUT2" = "jira" ]
check "re-running install leaves tracker value unchanged" "$?"

# 5. Never overwrites an operator's already-configured tracker value
TARGET2="$(new_repo)"
mkdir -p "$TARGET2/.gsd-recipe"
"$CONFIG_LIB" set-tracker github --config "$TARGET2/.gsd-recipe/config.json" >/dev/null
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
OUT3="$(REPO_ROOT="$TARGET2" "$CONFIG_LIB" get-tracker --config "$TARGET2/.gsd-recipe/config.json")"
[ "$OUT3" = "github" ]
check "install never overwrites an operator's pre-existing tracker choice (github stays github)" "$?"

# 6. Uninstall removes the skill, preserves config.json (and its tracker value)
TARGET3="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET3" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET3" >/dev/null

[ ! -f "$TARGET3/.cursor/skills/tracker-sync/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ -f "$TARGET3/.gsd-recipe/config.json" ]
check "uninstall preserves config.json (not tracked for deletion — may hold unrelated settings)" "$?"
OUT4="$(REPO_ROOT="$TARGET3" "$CONFIG_LIB" get-tracker --config "$TARGET3/.gsd-recipe/config.json")"
[ "$OUT4" = "jira" ]
check "uninstall leaves the tracker value intact" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET3/.gsd-recipe/ledger.json')); print('tracker-sync' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"

# 7. Uninstall preserves other unrelated keys already in config.json
TARGET4="$(new_repo)"
mkdir -p "$TARGET4/.gsd-recipe"
cat > "$TARGET4/.gsd-recipe/config.json" <<'EOF'
{"some_other_setting": "keep-me"}
EOF
"$INSTALLER" --yes --target "$TARGET4" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET4" >/dev/null
python3 -c "
import json
d = json.load(open('$TARGET4/.gsd-recipe/config.json'))
assert d.get('some_other_setting') == 'keep-me', d
assert d.get('tracker') == 'jira', d
"
check "uninstall preserves unrelated pre-existing config.json keys" "$?"

# 8. Self-install case (installing into a copy of this repo) does not error and preserves canonical source on uninstall
COPY="$(mktemp -d)/gsd-benchmark-copy"
cp -R "$REPO_ROOT" "$COPY"
(cd "$COPY" && ./.gsd-recipe/scripts/install-tracker-sync.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error (src==dest collision handled)" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-tracker-sync.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/tracker-sync-SKILL.md" ]
check "self-uninstall preserves the canonical skill template source" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
