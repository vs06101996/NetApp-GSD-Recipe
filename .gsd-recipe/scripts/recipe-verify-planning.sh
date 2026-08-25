#!/usr/bin/env bash
# recipe-verify-planning.sh — fail-closed planning artifact guardrail.
#
# Usage: recipe-verify-planning.sh [--target DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help) echo "Usage: $0 [--target DIR]"; exit 0 ;;
    *) echo "$0: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(pwd)"
fi
TARGET="$(cd "$TARGET" && pwd)"

PLANNING_PY="$SCRIPT_DIR/recipe_verify_planning.py"
if [ ! -f "$PLANNING_PY" ]; then
  PLANNING_PY="$TARGET/.gsd-recipe/scripts/recipe_verify_planning.py"
fi
if [ ! -f "$PLANNING_PY" ]; then
  echo "recipe-verify-planning.sh: recipe_verify_planning.py not found" >&2
  exit 2
fi

python3 "$PLANNING_PY" --target "$TARGET"
