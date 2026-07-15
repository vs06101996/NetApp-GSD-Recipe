#!/usr/bin/env bash
# demo-reset-target.sh — scrape GSD + operator demo artifacts so recipe-install
# can recreate scaffolding visibly (live demo on gsd-benchmark as target repo).
#
# Keeps the recipe *source* tree (.gsd-recipe/scripts, .gsd-recipe/templates,
# bench/) intact. Removes installed copies, GSD planning memory, and runtime
# queues so the next install/run looks like a first-time setup.
#
# Usage:
#   ./bench/runners/demo-reset-target.sh [--target <repo_root>] [--dry-run] [--yes]
#   ./bench/runners/demo-reset-target.sh --verify [--target <repo_root>]
#
# --verify   Print what would be removed / what must still exist (no changes).
# --dry-run  Print removals only (no uninstall, no deletes).
# --yes      Skip the live confirmation prompt.
# --skip-uninstall  Only scrape files; do not run install.sh --uninstall first.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "demo-reset-target.sh: $TARGET is not a git repo root. Refusing (fail closed)." >&2
  exit 1
fi

INSTALL_SH="$TARGET/.gsd-recipe/scripts/install.sh"

# Paths removed so install.sh / GSD / recipe skills recreate them on the next run.
# Relative to $TARGET.
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

# Never delete — installer source + harness (demo runs from this repo).
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
  # Recipe skills should be gone after a full reset (reinstalled by install.sh).
  if ls "$TARGET/.cursor/skills"/recipe-* >/dev/null 2>&1; then
    echo "  STILL PRESENT: .cursor/skills/recipe-*"
    ok=0
  else
    echo "  OK  absent: .cursor/skills/recipe-*"
  fi
  return "$ok"
}

if [ "$MODE" = "verify" ]; then
  echo "=== demo-reset verify: $TARGET ==="
  echo "--- keepers (must exist) ---"
  verify_keepers || true
  echo "--- scrape targets (should be absent after reset) ---"
  verify_absent || true
  exit 0
fi

echo "=== demo-reset: $TARGET ==="
echo "Keep (never touched): ${KEEP_PATHS[*]}"
echo "Scrape (removed so install/GSD recreate visibly):"
printf '  %s\n' "${SCRAPE_PATHS[@]}"
echo "Also: recipe uninstall removes .cursor/skills/recipe-* (and other ledgered skills)"

if [ "$DRY_RUN" -eq 0 ] && [ "$YES" -eq 0 ]; then
  read -r -p "Reset $TARGET for live demo? This deletes .planning/, docs/PRD.md, .templates/, etc. [y/N] " reply
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

echo "--- scrape GSD + operator + install copies ---"
for rel in "${SCRAPE_PATHS[@]}"; do
  remove_path "$rel"
done

# config.json: reset to minimal tracker default so install can rewrite visibly.
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
verify_absent && echo "PASS: demo-reset complete — ready for recipe-install" || {
  echo "WARN: some scrape targets still present (see above)"
  exit 1
}
