#!/usr/bin/env bash
# reset-recipe-scaffold.sh — remove installed recipe scaffold from a repo while
# keeping the recipe source tree (scripts, templates, harness).
#
# Use on the recipe source repo or any target where install.sh should visibly
# recreate .templates/, .knowledge/, code_base_details/, and recipe skills without
# deleting installer sources under .gsd-recipe/scripts and bench/.
#
# Usage:
#   ./bench/runners/reset-recipe-scaffold.sh [--target <repo_root>] [--dry-run] [--yes]
#   ./bench/runners/reset-recipe-scaffold.sh --verify [--target <repo_root>]
#
# When --target is omitted, defaults to this harness repo root.
#
# --verify          Print what would be removed / what must still exist (no changes).
# --dry-run         Print removals only (no uninstall, no deletes).
# --yes             Skip the confirmation prompt.
# --skip-uninstall  Only scrape files; do not run install.sh --uninstall first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
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

if [ -z "$TARGET" ]; then
  TARGET="$BENCHMARK_ROOT"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "reset-recipe-scaffold.sh: $TARGET is not a git repo root. Refusing (fail closed)." >&2
  exit 1
fi

INSTALL_SH="$TARGET/.gsd-recipe/scripts/install.sh"
if [ ! -x "$INSTALL_SH" ]; then
  INSTALL_SH="$BENCHMARK_ROOT/.gsd-recipe/scripts/install.sh"
fi

SCRAPE_PATHS=(
  ".planning"
  "docs/PRD.md"
  ".templates"
  ".knowledge"
  "code_base_details"
  ".learnings"
  ".gsd-recipe/sync-ledger.jsonl"
  ".gsd-recipe/sync-queue.jsonl"
  ".gsd-recipe/phase-tasks-queue.jsonl"
  ".gsd-recipe/install-report.json"
  ".gsd-recipe/INSTALL-VERIFIED.json"
  ".gsd-recipe/capability.json"
)

KEEP_PATHS=(
  ".gsd-recipe/scripts"
  ".gsd-recipe/templates"
  ".gsd-recipe/lib"
  "bench"
  "docs/netapp-recipe"
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
  echo "=== reset-recipe-scaffold verify: $TARGET ==="
  echo "--- keepers (must exist) ---"
  verify_keepers || true
  echo "--- scrape targets (should be absent after reset) ---"
  verify_absent || true
  exit 0
fi

echo "=== reset-recipe-scaffold: $TARGET ==="
echo "Keep (recipe source + harness): ${KEEP_PATHS[*]}"
echo "Scrape (removed so install recreates scaffold):"
printf '  %s\n' "${SCRAPE_PATHS[@]}"
echo "Also: recipe uninstall removes .cursor/skills/recipe-* (and other ledgered skills)"

if [ "$DRY_RUN" -eq 0 ] && [ "$YES" -eq 0 ]; then
  read -r -p "Reset recipe scaffold in $TARGET? This deletes .planning/, docs/PRD.md, .templates/, etc. [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

if [ "$DRY_RUN" -eq 0 ] && [ "$SKIP_UNINSTALL" -eq 0 ] && [ -x "$INSTALL_SH" ]; then
  echo "--- recipe uninstall (ledger-tracked skills) ---"
  "$INSTALL_SH" --uninstall --yes --target "$TARGET"
elif [ "$DRY_RUN" -eq 1 ]; then
  echo "--- skip uninstall (dry-run) ---"
elif [ "$SKIP_UNINSTALL" -eq 1 ]; then
  echo "--- skip uninstall (--skip-uninstall) ---"
else
  echo "--- skip uninstall (install.sh not executable at $INSTALL_SH) ---"
fi

echo "--- scrape GSD + operator + installed scaffold copies ---"
for rel in "${SCRAPE_PATHS[@]}"; do
  remove_path "$rel"
done

if [ -f "$TARGET/.gsd-recipe/config.json" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "  would reset: .gsd-recipe/config.json -> {\"tracker\": \"jira\"}"
  else
    printf '%s\n' '{"tracker": "jira"}' > "$TARGET/.gsd-recipe/config.json"
    echo "  reset: .gsd-recipe/config.json"
  fi
fi

echo "--- post-reset checks ---"
if [ "$DRY_RUN" -eq 1 ]; then
  echo "Dry run complete. Re-run without --dry-run to apply."
  exit 0
fi

verify_keepers
verify_absent && echo "PASS: reset-recipe-scaffold complete — ready for recipe-install" || {
  echo "WARN: some scrape targets still present (see above)"
  exit 1
}
