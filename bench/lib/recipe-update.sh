#!/usr/bin/env bash
# recipe-update core logic (TASK-058 / OD-21).
# Pulls the recipe source clone and restages skills/scripts/templates into TARGET.
# Never wipes .planning/, .knowledge/, docs/PRD.md, or customized .templates/.
#
# Usage:
#   bench/lib/recipe-update.sh --target <repo_root> [--dry-run] [--check] [--yes]
set -euo pipefail

TARGET=""
DRY_RUN=0
YES=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --dry-run|--check) DRY_RUN=1; shift ;;
    --yes|-y) YES=1; shift ;;
    *) echo "recipe-update: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "recipe-update: --target not specified and not inside a git repo." >&2; exit 1
  }
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-update: $TARGET is not a git repo root." >&2; exit 1
fi

read_recipe_source() {
  python3 - "$TARGET/.gsd-recipe/config.json" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as f:
        print(json.load(f).get("recipe_source", ""))
except Exception:
    print("")
PY
}

RECIPE_SOURCE="$(read_recipe_source)"

if [ -z "$RECIPE_SOURCE" ]; then
  echo "recipe-update: recipe_source not set in .gsd-recipe/config.json — re-run install-recipe-to-target.sh from the recipe source clone." >&2
  exit 1
fi

if [ ! -d "$RECIPE_SOURCE" ]; then
  echo "recipe-update: recipe_source path '$RECIPE_SOURCE' does not exist. Re-run install-recipe-to-target.sh --target $TARGET from a fresh clone." >&2
  exit 1
fi

if ! git -C "$RECIPE_SOURCE" rev-parse --git-dir >/dev/null 2>&1; then
  echo "recipe-update: recipe_source '$RECIPE_SOURCE' is not a git repo. Re-run install-recipe-to-target.sh --target $TARGET from a git clone." >&2
  exit 1
fi

if [ -n "$(git -C "$RECIPE_SOURCE" status --porcelain 2>/dev/null)" ]; then
  echo "recipe-update: recipe source at $RECIPE_SOURCE has uncommitted changes — commit or stash them first." >&2
  exit 1
fi

git -C "$RECIPE_SOURCE" fetch --quiet 2>/dev/null || {
  echo "recipe-update: fetch failed (no remote or network error). Check remote config in $RECIPE_SOURCE." >&2
  exit 1
}

PREVIEW="$(git -C "$RECIPE_SOURCE" log --oneline HEAD..@{u} 2>/dev/null || true)"

if [ -z "$PREVIEW" ]; then
  echo "recipe-update: recipe source already up to date."
  exit 0
fi

echo "recipe-update: recipe source — incoming changes from origin:"
while IFS= read -r line; do
  echo "  $line"
done <<< "$PREVIEW"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "recipe-update: dry-run — no changes made."
  exit 0
fi

if [ "$YES" -ne 1 ]; then
  printf 'Proceed with recipe update? [y/N] '
  read -r reply
  case "$reply" in
    [yY]|[yY][eE][sS]) : ;;
    *) echo "recipe-update: aborted."; exit 0 ;;
  esac
fi

git -C "$RECIPE_SOURCE" pull --ff-only 2>/dev/null || {
  echo "recipe-update: pull failed — not a fast-forward. Resolve manually in $RECIPE_SOURCE." >&2
  exit 1
}

"$RECIPE_SOURCE/.gsd-recipe/scripts/install.sh" --yes --target "$TARGET"

NEW_VERSION="$(git -C "$RECIPE_SOURCE" rev-parse --short HEAD 2>/dev/null || echo "unknown")"

python3 - "$TARGET/.gsd-recipe/install-report.json" "$NEW_VERSION" <<'PY'
import json, sys, os
path, version = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data["recipe_version"] = version
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

echo "recipe-update: done. Recipe restaged from $RECIPE_SOURCE@$NEW_VERSION."
