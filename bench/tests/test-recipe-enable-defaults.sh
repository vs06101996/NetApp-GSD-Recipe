#!/usr/bin/env bash
# Guardrail tests for recipe-enable-defaults.sh (TDD + graphify circuit breaker).
# Run: ./bench/tests/test-recipe-enable-defaults.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENABLE="$REPO_ROOT/bench/lib/recipe-enable-defaults.sh"

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

NOPLAN="$(new_repo)"
("$ENABLE" --target "$NOPLAN") && rc=0 || rc=$?
check "missing .planning/config.json still exits 0" "$rc"

FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/gsd-tools" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "${GSD_TOOLS_LOG:?}"
if [ "$1" = "config-set" ]; then
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN/gsd-tools"

HASCFG="$(new_repo)"
mkdir -p "$HASCFG/.planning"
printf '%s\n' '{"schema_version":1}' > "$HASCFG/.planning/config.json"
export GSD_TOOLS_LOG="$HASCFG/gsd-tools.log"
PATH="$FAKEBIN:$PATH" "$ENABLE" --target "$HASCFG" && rc=0 || rc=$?
check "config-set path exits 0" "$rc"
grep -q "config-set workflow.tdd_mode true --cwd $HASCFG" "$GSD_TOOLS_LOG" && rc=0 || rc=$?
check "tries workflow.tdd_mode true" "$rc"
grep -q "config-set graphify.enabled true --cwd $HASCFG" "$GSD_TOOLS_LOG" && rc=0 || rc=$?
check "tries graphify.enabled true" "$rc"

FAILBIN="$(mktemp -d)"
cat > "$FAILBIN/gsd-tools" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAILBIN/gsd-tools"
FAILCFG="$(new_repo)"
mkdir -p "$FAILCFG/.planning"
printf '%s\n' '{"schema_version":1}' > "$FAILCFG/.planning/config.json"
PATH="$FAILBIN:$PATH" "$ENABLE" --target "$FAILCFG" && rc=0 || rc=$?
check "failed config-set still exits 0" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
