#!/usr/bin/env bash
# Regression tests for the sudo-free graphify installer.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-graphify.sh"

pass=0
fail=0

check() {
  local desc="$1" result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $desc"
    pass=$((pass + 1))
  else
    echo "FAIL - $desc"
    fail=$((fail + 1))
  fi
}

HOME_DIR="$(mktemp -d)"
FAKEBIN="$(mktemp -d)"
UV_LOG="$HOME_DIR/uv.log"

cat > "$FAKEBIN/uv" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$UV_LOG"
if [ "$1" = "tool" ] && [ "$2" = "install" ] && [ "$3" = "--force" ]; then
  mkdir -p "$UV_TOOL_BIN_DIR"
  cat > "$UV_TOOL_BIN_DIR/graphify" <<'INNER'
#!/usr/bin/env bash
case "${1:-}" in
  --help|-h) echo "graphify knowledge graph CLI" ;;
  install) : ;;
  *) : ;;
esac
INNER
  chmod +x "$UV_TOOL_BIN_DIR/graphify"
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN/uv"

HOME="$HOME_DIR" UV_LOG="$UV_LOG" PATH="$FAKEBIN:/usr/bin:/bin" \
  "$INSTALLER" >/dev/null 2>&1 && rc=0 || rc=$?
check "installer repairs registered graphifyy with missing command" "$rc"

grep -q '^tool install --force graphifyy$' "$UV_LOG" && rc=0 || rc=$?
check "installer forces uv to recreate missing entry-point links" "$rc"

HOME="$HOME_DIR" PATH="$HOME_DIR/bin:/usr/bin:/bin" \
  "$HOME_DIR/bin/graphify" --help >/dev/null 2>&1 && rc=0 || rc=$?
check "repaired graphify command is available from HOME/bin" "$rc"

FASTBIN="$(mktemp -d)"
cat > "$FASTBIN/graphify" <<'EOF'
#!/usr/bin/env python3
from graphify.__main__ import main
raise RuntimeError("probe must not execute this launcher")
EOF
chmod +x "$FASTBIN/graphify"
# shellcheck source=/dev/null
source "$REPO_ROOT/bench/lib/graphify-probe.sh"
PATH="$FASTBIN:/usr/bin:/bin" graphify_functional && rc=0 || rc=$?
check "probe recognizes genuine Python entry-point shape without executing it" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
