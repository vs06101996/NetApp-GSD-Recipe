#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-observer.sh.
# Formalizes the ad hoc temp-repo validation performed during development
# (fresh install, merge into existing hooks.json, idempotent re-run, and
# surgical uninstall) into a checked-in, repeatable test.
# Run: ./bench/tests/test-install-observer.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-observer.sh"

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

# 2. Fresh install stages every expected file
TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
EXPECTED_FILES=(
  ".learnings/observer/.gitkeep"
  ".learnings/kb/sessions/.gitkeep"
  ".learnings/kb/playbooks/.gitkeep"
  ".gsd-recipe/lib/observer-lib.sh"
  ".cursor/hooks/fotw-observer-nudge.sh"
  ".cursor/hooks.json"
  ".gsd-recipe/templates/fotw-observer-task-prompt.md"
  ".cursor/skills/fotw-observer-bootstrap/SKILL.md"
  ".gsd-recipe/observer-config.json"
)
ok=0
for f in "${EXPECTED_FILES[@]}"; do
  [ -f "$TARGET1/$f" ] || ok=1
done
check "fresh install stages all expected files" "$ok"

ENABLED="$(python3 -c "import json; print(json.load(open('$TARGET1/.gsd-recipe/observer-config.json'))['enabled'])")"
[ "$ENABLED" = "True" ]
check "fresh install's observer-config.json defaults to enabled" "$?"

# 3. Merges into a pre-existing hooks.json without disturbing unrelated hooks
TARGET2="$(new_repo)"
mkdir -p "$TARGET2/.cursor"
cat > "$TARGET2/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": { "postToolUse": [ { "command": ".cursor/hooks/some-other-guard.sh", "matcher": "Write" } ] }
}
EOF
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
COUNT="$(python3 -c "import json; print(len(json.load(open('$TARGET2/.cursor/hooks.json'))['hooks']['postToolUse']))")"
[ "$COUNT" = "2" ]
check "merges into existing hooks.json, keeping unrelated hook + adding ours" "$?"
HAS_OTHER="$(python3 -c "import json; d=json.load(open('$TARGET2/.cursor/hooks.json')); print(any(e['command']=='.cursor/hooks/some-other-guard.sh' for e in d['hooks']['postToolUse']))")"
[ "$HAS_OTHER" = "True" ]
check "unrelated pre-existing hook entry survives the merge" "$?"

# 4. Never overwrites a pre-existing observer-config.json
TARGET3="$(new_repo)"
mkdir -p "$TARGET3/.gsd-recipe"
echo '{"enabled": true, "_marker": "operator-customized"}' > "$TARGET3/.gsd-recipe/observer-config.json"
"$INSTALLER" --yes --target "$TARGET3" >/dev/null
MARKER="$(python3 -c "import json; print(json.load(open('$TARGET3/.gsd-recipe/observer-config.json')).get('_marker'))")"
[ "$MARKER" = "operator-customized" ]
check "never overwrites a pre-existing observer-config.json" "$?"

# 5. Idempotent re-run: no duplicate hook entries, no duplicate ledger rows
TARGET4="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET4" >/dev/null
"$INSTALLER" --yes --target "$TARGET4" >/dev/null
COUNT4="$(python3 -c "import json; print(len(json.load(open('$TARGET4/.cursor/hooks.json'))['hooks']['postToolUse']))")"
[ "$COUNT4" = "1" ]
check "re-running install does not duplicate the hooks.json entry" "$?"
LEDGER_COUNT="$(python3 -c "import json; print(len(json.load(open('$TARGET4/.gsd-recipe/ledger.json'))['fotw-observer']))")"
[ "$LEDGER_COUNT" = "9" ]
check "re-running install does not duplicate ledger rows" "$?"

# 6. Uninstall removes exactly what we staged, preserves operator data + unrelated hooks
TARGET5="$(new_repo)"
mkdir -p "$TARGET5/.cursor"
cat > "$TARGET5/.cursor/hooks.json" <<'EOF'
{
  "version": 1,
  "hooks": { "postToolUse": [ { "command": ".cursor/hooks/some-other-guard.sh", "matcher": "Write" } ] }
}
EOF
"$INSTALLER" --yes --target "$TARGET5" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET5" >/dev/null

[ ! -f "$TARGET5/.cursor/hooks/fotw-observer-nudge.sh" ]
check "uninstall removes the staged hook script" "$?"
[ ! -f "$TARGET5/.gsd-recipe/lib/observer-lib.sh" ]
check "uninstall removes the staged lib copy" "$?"
[ ! -f "$TARGET5/.cursor/skills/fotw-observer-bootstrap/SKILL.md" ]
check "uninstall removes the staged skill" "$?"
[ ! -f "$TARGET5/.gsd-recipe/templates/fotw-observer-task-prompt.md" ]
check "uninstall removes the staged task-prompt template" "$?"
[ -f "$TARGET5/.gsd-recipe/observer-config.json" ]
check "uninstall preserves operator's observer-config.json" "$?"
[ -d "$TARGET5/.learnings" ]
check "uninstall preserves .learnings/ data" "$?"
POST_COUNT="$(python3 -c "import json; print(len(json.load(open('$TARGET5/.cursor/hooks.json'))['hooks']['postToolUse']))")"
[ "$POST_COUNT" = "1" ]
check "uninstall removes only our hooks.json entry" "$?"
HAS_OTHER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET5/.cursor/hooks.json')); print(any(e['command']=='.cursor/hooks/some-other-guard.sh' for e in d['hooks']['postToolUse']))")"
[ "$HAS_OTHER_AFTER" = "True" ]
check "unrelated hook entry survives uninstall" "$?"
LEDGER_AFTER="$(python3 -c "import json; d=json.load(open('$TARGET5/.gsd-recipe/ledger.json')); print('fotw-observer' in d)")"
[ "$LEDGER_AFTER" = "False" ]
check "uninstall clears the component's ledger entry" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
