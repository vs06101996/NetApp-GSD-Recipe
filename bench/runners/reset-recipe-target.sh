#!/usr/bin/env bash
# reset-recipe-target.sh — remove recipe + GSD artifacts from a target repo so
# onboarding can run again from a clean slate.
#
# Uninstalls ledger-tracked recipe skills, then scrapes planning memory, installed
# scaffold copies, and typical application paths created during a prior recipe run.
# Preserves operator-owned files such as README.md, BRIEF.md, .gitignore, and
# vanilla GSD .cursor/ state.
#
# Usage (from inside the target repo — no --target needed):
#   /path/to/gsd-benchmark/bench/runners/reset-recipe-target.sh --yes
#   /path/to/gsd-benchmark/bench/runners/reset-recipe-target.sh --verify
#
# Optional override:
#   reset-recipe-target.sh --target /other/repo --yes
#
# --verify          Print absent/keep checks (no changes).
# --dry-run         Print removals only.
# --yes             Skip confirmation prompt.
# --skip-uninstall  Do not run install.sh --uninstall against the target first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/recipe-target-root.sh
. "$SCRIPT_DIR/../lib/recipe-target-root.sh"
TARGET=""
MODE="reset"
DRY_RUN=0
YES=0
SKIP_UNINSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --verify) MODE="verify"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes|-y) YES=1; shift ;;
    --skip-uninstall) SKIP_UNINSTALL=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if ! TARGET="$(recipe_target_root "$TARGET")"; then
  echo "reset-recipe-target.sh: run inside a git repo (or pass --target <repo_root>)." >&2
  exit 2
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "reset-recipe-target.sh: $TARGET is not a git repo root. Refusing (fail closed)." >&2
  exit 1
fi

INSTALL_SH="$BENCHMARK_ROOT/.gsd-recipe/scripts/install.sh"

SCRAPE_PATHS=(
  ".planning"
  "docs"
  "docs/PRD.md"
  ".templates"
  ".knowledge"
  "code_base_details"
  ".learnings"
  ".gsd-codebase"
  ".gsd-recipe"
  "go.mod"
  "go.sum"
  "store"
  "task"
  "cmd"
  "web"
  "api"
  "internal"
)

KEEP_PATHS=(
  ".git"
  ".gitignore"
  "BRIEF.md"
  "README.md"
  ".cursor"
)

remove_path() {
  local rel="$1"
  local abs="$TARGET/$rel"
  if [ ! -e "$abs" ]; then
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ] || [ "$MODE" = "verify" ]; then
    echo "  would remove: $rel"
    return 0
  fi
  rm -rf "$abs"
  echo "  removed: $rel"
}

verify_keepers() {
  local ok=1
  for rel in "${KEEP_PATHS[@]}"; do
    if [ -e "$TARGET/$rel" ]; then
      echo "  OK  keep: $rel"
    else
      echo "  FAIL missing keeper: $rel"
      ok=0
    fi
  done
  return "$ok"
}

verify_absent() {
  local ok=1
  for rel in "${SCRAPE_PATHS[@]}"; do
    if [ -e "$TARGET/$rel" ]; then
      echo "  STILL PRESENT: $rel"
      ok=0
    else
      echo "  OK  absent: $rel"
    fi
  done
  if ls "$TARGET/.cursor/skills"/recipe-* >/dev/null 2>&1; then
    echo "  STILL PRESENT: .cursor/skills/recipe-*"
    ok=0
  else
    echo "  OK  absent: .cursor/skills/recipe-*"
  fi
  return "$ok"
}

if [ "$MODE" = "verify" ]; then
  echo "=== reset-recipe-target verify: $TARGET ==="
  echo "--- keepers (must exist) ---"
  verify_keepers || true
  echo "--- scrape targets (should be absent after reset) ---"
  verify_absent || true
  exit 0
fi

echo "=== reset-recipe-target: $TARGET ==="
echo "Keep (operator + vanilla GSD): ${KEEP_PATHS[*]}"
echo "Scrape (removed so recipe onboarding can recreate):"
printf '  %s\n' "${SCRAPE_PATHS[@]}"
echo "Also: recipe uninstall removes .cursor/skills/recipe-* if previously installed"

if [ "$DRY_RUN" -eq 0 ] && [ "$YES" -eq 0 ]; then
  read -r -p "Reset $TARGET for fresh recipe onboarding? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

if [ "$DRY_RUN" -eq 0 ] && [ "$SKIP_UNINSTALL" -eq 0 ] && [ -x "$INSTALL_SH" ]; then
  echo "--- recipe uninstall from recipe source (ledger-tracked skills on target) ---"
  "$INSTALL_SH" --uninstall --yes --target "$TARGET" 2>/dev/null || true
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "--- skip uninstall (dry-run) ---"
else
  echo "--- skip uninstall (--skip-uninstall or install.sh missing) ---"
fi

echo "--- scrape GSD memory, prior application code, recipe copies ---"
for rel in "${SCRAPE_PATHS[@]}"; do
  remove_path "$rel"
done

echo "--- post-reset checks ---"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run with --yes to apply."
  exit 0
fi

verify_keepers
verify_absent && echo "PASS: reset-recipe-target complete — ready for install-recipe-to-target" || {
  echo "WARN: some scrape targets still present (see above)"
  exit 1
}
