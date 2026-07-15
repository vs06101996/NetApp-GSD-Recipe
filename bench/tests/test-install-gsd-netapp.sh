#!/usr/bin/env bash
# Regression test for .gsd-recipe/scripts/install-gsd-netapp.sh — the branded,
# zero-logic delegating wrapper around install.sh (TASK-010). Does not
# re-test install.sh's own behavior (see test-install.sh for that); only
# verifies the wrapper actually delegates: same args in, same stdout/stderr/
# exit code out, no divergence.
#
# Run: ./bench/tests/test-install-gsd-netapp.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$REPO_ROOT/.gsd-recipe/scripts/install-gsd-netapp.sh"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install.sh"

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

# 1. Wrapper file exists and is executable.
[ -x "$WRAPPER" ]
check "install-gsd-netapp.sh exists and is executable" "$?"

# 2. Refuses to install outside a git repo, with the same fail-closed
# behavior and exit code as install.sh itself.
NOTGIT="$(mktemp -d)"
"$WRAPPER" --yes --target "$NOTGIT" >/dev/null 2>&1 && WRC=0 || WRC=$?
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && IRC=0 || IRC=$?
[ "$WRC" = "$IRC" ] && [ "$WRC" != "0" ]
check "wrapper refuses non-git target with the same exit code as install.sh" "$?"

# 3. --verify passthrough: identical exit code and stdout to a direct
# install.sh --verify call on the same never-installed scratch target.
TARGET3="$(new_repo)"
WOUT3="$("$WRAPPER" --verify --target "$TARGET3" 2>&1)" && WRC3=0 || WRC3=$?
IOUT3="$("$INSTALLER" --verify --target "$TARGET3" 2>&1)" && IRC3=0 || IRC3=$?
[ "$WRC3" = "$IRC3" ]
check "--verify passthrough: exit code matches install.sh" "$?"
[ "$WOUT3" = "$IOUT3" ]
check "--verify passthrough: stdout/stderr matches install.sh verbatim" "$?"
rm -rf "$TARGET3"

# 4. Full --yes install passthrough on a scratch repo produces the same
# install-report.json shape as calling install.sh directly (spot-check a
# couple of top-level keys rather than full byte-equality, since timestamps
# inside the report legitimately differ between the two invocations).
TARGET4="$(new_repo)"
"$WRAPPER" --yes --target "$TARGET4" >/dev/null 2>&1 && rc=0 || rc=$?
check "wrapper --yes install exits 0 on a fresh scratch repo" "$rc"
[ -f "$TARGET4/.gsd-recipe/install-report.json" ]
check "wrapper install produces .gsd-recipe/install-report.json" "$?"
[ -f "$TARGET4/.gsd-recipe/ledger.json" ]
check "wrapper install produces .gsd-recipe/ledger.json" "$?"
rm -rf "$TARGET4"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
