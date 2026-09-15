#!/usr/bin/env bash
# recipe-enable-defaults.sh — circuit-breaker enable of GSD workflow defaults.
#
# Tries to set workflow.tdd_mode=true and graphify.enabled=true through
# gsd-tools config-set (never a hand-rolled JSON merge). Always exits 0:
# missing .planning/config.json, missing gsd-tools, or a failed config-set
# prints a warning and continues.
#
# Usage: recipe-enable-defaults.sh [--target DIR]
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
GSD_TOOLS_CJS_PATH="${GSD_TOOLS_CJS_PATH:-$HOME/.cursor/get-shit-done/bin/gsd-tools.cjs}"

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--target DIR]"
      exit 0
      ;;
    *) echo "$0: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  if [ -d "$SCRIPT_DIR/../../.git" ] && [ -f "$SCRIPT_DIR/../../bench/lib/recipe-enable-defaults.sh" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    TARGET="$(pwd)"
  fi
fi
TARGET="$(cd "$TARGET" && pwd)"

planning_config="$TARGET/.planning/config.json"

resolve_gsd_tools() {
  if command -v gsd-tools >/dev/null 2>&1; then
    echo "gsd-tools"
    return 0
  fi
  if command -v node >/dev/null 2>&1 && [ -f "$GSD_TOOLS_CJS_PATH" ]; then
    echo "node $GSD_TOOLS_CJS_PATH"
    return 0
  fi
  return 1
}

try_set() {
  local key="$1"
  if [ ! -f "$planning_config" ]; then
    echo "recipe-enable-defaults: $key skipped_no_planning_config" >&2
    return 0
  fi
  local gsd_tools_cmd
  if ! gsd_tools_cmd="$(resolve_gsd_tools)"; then
    echo "recipe-enable-defaults: $key skipped_no_gsd_tools" >&2
    return 0
  fi
  # Intentionally unquoted so "node /path/gsd-tools.cjs" stays two argv words.
  # shellcheck disable=SC2086
  if $gsd_tools_cmd config-set "$key" true --cwd "$TARGET" >/dev/null 2>&1; then
    echo "recipe-enable-defaults: $key set" >&2
  else
    echo "recipe-enable-defaults: $key failed — continuing without it" >&2
  fi
  return 0
}

try_set "workflow.tdd_mode"
try_set "graphify.enabled"
exit 0
