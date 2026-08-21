#!/usr/bin/env bash
# install-recipe-to-target.sh — install the NetApp GSD recipe into a target git repo.
#
# Runs install.sh from this harness repo (recipe source) against the target.
# When --target is omitted, uses the current git repo (cwd or any subdirectory).
#
# Usage (from inside the target repo — no --target needed):
#   /path/to/gsd-benchmark/bench/runners/install-recipe-to-target.sh
#   /path/to/gsd-benchmark/bench/runners/install-recipe-to-target.sh --record-jira-check pass
#   /path/to/gsd-benchmark/bench/runners/install-recipe-to-target.sh --verify
#
# Optional override:
#   install-recipe-to-target.sh --target /other/repo
#   install-recipe-to-target.sh --open-start       # force Cursor prompt deeplink
#   install-recipe-to-target.sh --no-open-start    # never open Cursor
#
# Successful interactive installs open Cursor with `recipe-start` pre-filled.
# Cursor still requires the operator to press Enter; deeplinks never execute.
# Non-interactive runs skip this unless --open-start is explicit.
#
# Forwards install.sh flags; adds --yes when no other flags are given.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INSTALL_SH="${RECIPE_INSTALL_SH:-$BENCHMARK_ROOT/.gsd-recipe/scripts/install.sh}"
# shellcheck source=../lib/recipe-target-root.sh
. "$SCRIPT_DIR/../lib/recipe-target-root.sh"

TARGET=""
FORWARD=()
OPEN_START="auto"
INSTALL_MODE=1

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      TARGET="$2"
      shift 2
      ;;
    --open-start)
      OPEN_START="yes"
      shift
      ;;
    --no-open-start)
      OPEN_START="no"
      shift
      ;;
    --verify|--uninstall)
      INSTALL_MODE=0
      FORWARD+=("$1")
      shift
      ;;
    --record-jira-check)
      INSTALL_MODE=0
      FORWARD+=("$1" "${2:?--record-jira-check requires pass or fail}")
      shift 2
      ;;
    *)
      FORWARD+=("$1")
      shift
      ;;
  esac
done

if ! TARGET="$(recipe_target_root "$TARGET")"; then
  echo "install-recipe-to-target.sh: run inside a git repo (or pass --target <repo_root>)." >&2
  exit 2
fi

if [ ! -x "$INSTALL_SH" ]; then
  echo "install-recipe-to-target.sh: missing installer: $INSTALL_SH" >&2
  exit 1
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "install-recipe-to-target.sh: $TARGET is not a git repo root. Refusing (fail closed)." >&2
  exit 1
fi

if [ ${#FORWARD[@]} -eq 0 ]; then
  FORWARD=(--yes)
fi

"$INSTALL_SH" "${FORWARD[@]}" --target "$TARGET"

if [ "$INSTALL_MODE" -eq 1 ] && { [ "$OPEN_START" = "yes" ] || { [ "$OPEN_START" = "auto" ] && [ -t 1 ]; }; }; then
  START_URL="cursor://anysphere.cursor-deeplink/prompt?text=recipe-start"
  if command -v open >/dev/null 2>&1; then
    open "$START_URL" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$START_URL" >/dev/null 2>&1 || true
  elif command -v cmd.exe >/dev/null 2>&1; then
    cmd.exe /c start "" "$START_URL" >/dev/null 2>&1 || true
  else
    echo "Cursor prompt: $START_URL"
  fi
  echo "Cursor opened with 'recipe-start' pre-filled. Review it, then press Enter."
fi
