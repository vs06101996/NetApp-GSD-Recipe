#!/usr/bin/env bash
# Regression test for install-recipe-to-target.sh prompt deeplink behavior.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$REPO_ROOT/bench/runners/install-recipe-to-target.sh"
TMP="$(mktemp -d)"
TARGET="$TMP/target"
FAKEBIN="$TMP/bin"
INSTALL_LOG="$TMP/install.log"
OPEN_LOG="$TMP/open.log"
mkdir -p "$TARGET" "$FAKEBIN"
(cd "$TARGET" && git init -q)

pass=0
fail=0
check() {
  local description="$1" result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $description"
    pass=$((pass + 1))
  else
    echo "FAIL - $description"
    fail=$((fail + 1))
  fi
}

cat > "$TMP/fake-install.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$INSTALL_LOG"
SH
chmod +x "$TMP/fake-install.sh"

cat > "$FAKEBIN/open" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$1" > "$OPEN_LOG"
SH
chmod +x "$FAKEBIN/open"

PATH="$FAKEBIN:$PATH" INSTALL_LOG="$INSTALL_LOG" OPEN_LOG="$OPEN_LOG" \
  RECIPE_INSTALL_SH="$TMP/fake-install.sh" \
  "$RUNNER" --target "$TARGET" --yes --open-start >/dev/null

grep -q -- "--yes --target $TARGET" "$INSTALL_LOG"
check "forwards install arguments and target" "$?"
grep -q '^cursor://anysphere.cursor-deeplink/prompt?text=recipe-start$' "$OPEN_LOG"
check "opens the documented Cursor prompt deeplink" "$?"

rm -f "$OPEN_LOG"
PATH="$FAKEBIN:$PATH" INSTALL_LOG="$INSTALL_LOG" OPEN_LOG="$OPEN_LOG" \
  RECIPE_INSTALL_SH="$TMP/fake-install.sh" \
  "$RUNNER" --target "$TARGET" --yes --no-open-start >/dev/null
[ ! -e "$OPEN_LOG" ]
check "--no-open-start suppresses Cursor" "$?"

PATH="$FAKEBIN:$PATH" INSTALL_LOG="$INSTALL_LOG" OPEN_LOG="$OPEN_LOG" \
  RECIPE_INSTALL_SH="$TMP/fake-install.sh" \
  "$RUNNER" --target "$TARGET" --verify --open-start >/dev/null
[ ! -e "$OPEN_LOG" ]
check "verify mode never opens a prompt" "$?"
grep -q -- "--verify --target $TARGET" "$INSTALL_LOG"
check "verify mode still forwards correctly" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
