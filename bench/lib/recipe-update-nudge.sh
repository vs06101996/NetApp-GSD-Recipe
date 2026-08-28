#!/usr/bin/env bash
# Fail-open recipe-source check for recipe-start (never restages).
# Prints a nudge only when recipe-update --check reports incoming commits.
# Skip: RECIPE_UPDATE_CHECK=0, missing lib, errors, or already up to date.
set -euo pipefail

if [ "${RECIPE_UPDATE_CHECK:-1}" = "0" ]; then
  exit 0
fi

TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$TARGET/.gsd-recipe/lib/recipe-update.sh"
if [ ! -f "$LIB" ]; then
  LIB="$SCRIPT_DIR/recipe-update.sh"
fi
if [ ! -f "$LIB" ]; then
  exit 0
fi

OUT="$(bash "$LIB" --target "$TARGET" --check 2>&1)" || true
echo "$OUT" | grep -q "incoming changes" || exit 0
echo "$OUT"
echo "Type recipe-update to restage. recipe-start will not restage."
exit 0
