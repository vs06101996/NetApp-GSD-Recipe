#!/usr/bin/env bash
# recipe-status installer (TASK-060) — stages recipe-status skill + recipe-status.sh
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-status.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-status.sh --uninstall [--target <repo_root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="install"
YES=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --yes|-y) YES=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$SELF_ROOT"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-status installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-status/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-status-SKILL.md"
if [ -f "$SCRIPT_DIR/recipe-status.sh" ]; then
  STATUS_SRC="$SCRIPT_DIR/recipe-status.sh"
else
  STATUS_SRC="$SELF_ROOT/bench/lib/recipe-status.sh"
fi
STATUS_DEST="$GSD_RECIPE_DIR/scripts/recipe-status.sh"
COMPONENT="recipe-status"

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

is_canonical_source() {
  local candidate="$1"
  [ -e "$candidate" ] || return 1
  [ -e "$SKILL_SRC" ] || return 1
  [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$SKILL_SRC")" && pwd)/$(basename "$SKILL_SRC")" ]
}

is_canonical_status() {
  local candidate="$1"
  [ -e "$candidate" ] || return 1
  [ -e "$STATUS_SRC" ] || return 1
  [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$STATUS_SRC")" && pwd)/$(basename "$STATUS_SRC")" ]
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-status skill into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-status installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  if [ ! -f "$STATUS_SRC" ]; then
    echo "recipe-status installer: missing $STATUS_SRC" >&2
    exit 1
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-status/SKILL.md"
  mkdir -p "$(dirname "$STATUS_DEST")"
  safe_copy "$STATUS_SRC" "$STATUS_DEST"
  chmod +x "$STATUS_DEST"
  ledger_record ".gsd-recipe/scripts/recipe-status.sh"

  echo "recipe-status installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "In Cursor Agent type:  recipe-status"
  echo "Terminal helper:       $STATUS_DEST --target $TARGET"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-status installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    if is_canonical_source "$TARGET/$rel" || is_canonical_status "$TARGET/$rel"; then
      echo "  keeping $rel (canonical source — self-install)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)
  rmdir "$TARGET/.cursor/skills/recipe-status" 2>/dev/null || true
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
  echo "recipe-status installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
