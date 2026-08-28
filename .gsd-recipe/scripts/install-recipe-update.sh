#!/usr/bin/env bash
# recipe-update installer (TASK-058) — stages recipe-update skill + recipe-update.sh lib
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-update.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-update.sh --uninstall [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-update.sh --verify [--target <repo_root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="install"
YES=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --verify) MODE="verify"; shift ;;
    --yes|-y) YES=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$SELF_ROOT"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-update installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-update/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-update-SKILL.md"
if [ -f "$SCRIPT_DIR/recipe-update.sh" ]; then
  LIB_SRC="$SCRIPT_DIR/recipe-update.sh"
else
  LIB_SRC="$SELF_ROOT/bench/lib/recipe-update.sh"
fi
LIB_DEST="$GSD_RECIPE_DIR/lib/recipe-update.sh"
if [ -f "$SCRIPT_DIR/recipe-update-nudge.sh" ]; then
  NUDGE_SRC="$SCRIPT_DIR/recipe-update-nudge.sh"
else
  NUDGE_SRC="$SELF_ROOT/bench/lib/recipe-update-nudge.sh"
fi
NUDGE_DEST="$GSD_RECIPE_DIR/lib/recipe-update-nudge.sh"
COMPONENT="recipe-update"

mkdir -p "$GSD_RECIPE_DIR"

ledger_init() {
  [ -f "$LEDGER" ] || printf '{}\n' > "$LEDGER"
}

ledger_record() {
  ledger_init
  python3 - "$LEDGER" "$COMPONENT" "$1" <<'PY'
import json, sys
ledger_path, component, rel_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(ledger_path) as f:
    data = json.load(f)
files = data.setdefault(component, [])
if rel_path not in files:
    files.append(rel_path)
with open(ledger_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

ledger_files() {
  ledger_init
  python3 - "$LEDGER" "$COMPONENT" <<'PY'
import json, sys
ledger_path, component = sys.argv[1], sys.argv[2]
with open(ledger_path) as f:
    data = json.load(f)
for p in data.get(component, []):
    print(p)
PY
}

safe_copy() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" = "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")" ]; then
    return 0
  fi
  cp "$src" "$dest"
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-update skill into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-update installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  if [ ! -f "$LIB_SRC" ]; then
    echo "recipe-update installer: missing lib at $LIB_SRC" >&2
    exit 1
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-update/SKILL.md"

  mkdir -p "$(dirname "$LIB_DEST")"
  safe_copy "$LIB_SRC" "$LIB_DEST"
  chmod +x "$LIB_DEST"
  ledger_record ".gsd-recipe/lib/recipe-update.sh"

  if [ -f "$NUDGE_SRC" ]; then
    safe_copy "$NUDGE_SRC" "$NUDGE_DEST"
    chmod +x "$NUDGE_DEST"
    ledger_record ".gsd-recipe/lib/recipe-update-nudge.sh"
  fi

  echo "recipe-update installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-update [--dry-run|--check]' by name to pull the latest recipe source"
  echo "and restage skills/scripts without wiping .planning/, .knowledge/, or custom .templates/."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

verify() {
  local missing=0
  for rel in ".cursor/skills/recipe-update/SKILL.md" ".gsd-recipe/lib/recipe-update.sh" ".gsd-recipe/lib/recipe-update-nudge.sh"; do
    if [ ! -f "$TARGET/$rel" ]; then
      echo "recipe-update installer: MISSING $rel" >&2
      missing=1
    fi
  done
  if [ "$missing" -eq 0 ]; then
    echo "recipe-update installer: verify PASS"
  fi
  exit "$missing"
}

uninstall() {
  echo "recipe-update installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local src_abs dest_abs
    if [ -e "$LIB_SRC" ] && [ -e "$TARGET/$rel" ]; then
      src_abs="$(cd "$(dirname "$LIB_SRC")" && pwd)/$(basename "$LIB_SRC")"
      dest_abs="$(cd "$(dirname "$TARGET/$rel")" && pwd)/$(basename "$rel")"
      if [ "$src_abs" = "$dest_abs" ]; then
        echo "  keeping $rel (canonical source — self-install)"
        continue
      fi
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)
  rmdir "$TARGET/.cursor/skills/recipe-update" 2>/dev/null || true
  python3 - "$LEDGER" "$COMPONENT" <<'PY'
import json, sys
ledger_path, component = sys.argv[1], sys.argv[2]
with open(ledger_path) as f:
    data = json.load(f)
data.pop(component, None)
with open(ledger_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  echo "recipe-update installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  verify) verify ;;
  uninstall) uninstall ;;
esac
