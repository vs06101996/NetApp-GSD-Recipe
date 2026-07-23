#!/usr/bin/env bash
# recipe-help installer (TASK-038) — stages the invoke-by-name help skill and
# the generated docs/RECIPE-COMMANDS.md reference into the target repo.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-help.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-help.sh --uninstall [--target <repo_root>]
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
  echo "recipe-help installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-help/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-help-SKILL.md"
DOC_DEST="$TARGET/docs/RECIPE-COMMANDS.md"
DOC_SRC="$SELF_ROOT/docs/RECIPE-COMMANDS.md"
BENCH_DEST="$TARGET/docs/RECIPE-BENCHMARKS.md"
BENCH_SRC="$SELF_ROOT/docs/netapp-recipe/BENCHMARKS.md"
COMPONENT="recipe-help"

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
  case "$candidate" in
    "$SKILL_SRC"|"$DOC_SRC"|"$BENCH_SRC") return 0 ;;
  esac
  return 1
}

install() {
  if [ ! -f "$DOC_SRC" ]; then
    echo "recipe-help installer: missing $DOC_SRC — run bench/lib/generate-recipe-help.sh first." >&2
    exit 1
  fi
  if [ ! -f "$BENCH_SRC" ]; then
    echo "recipe-help installer: missing $BENCH_SRC — run bench/lib/generate-recipe-benchmarks.sh first." >&2
    exit 1
  fi

  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-help skill + docs/RECIPE-COMMANDS.md + docs/RECIPE-BENCHMARKS.md into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-help installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-help/SKILL.md"
  safe_copy "$DOC_SRC" "$DOC_DEST"
  ledger_record "docs/RECIPE-COMMANDS.md"
  safe_copy "$BENCH_SRC" "$BENCH_DEST"
  ledger_record "docs/RECIPE-BENCHMARKS.md"

  echo "recipe-help installer: staged. Invoke 'recipe-help' in Cursor for command reference."
  echo "  doc: docs/RECIPE-COMMANDS.md"
  echo "  benchmarks: docs/RECIPE-BENCHMARKS.md"
  ledger_files | sed 's/^/  - /'
}

uninstall() {
  echo "recipe-help installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    if is_canonical_source "$TARGET/$rel"; then
      echo "  keeping $rel (canonical source, self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  rmdir "$TARGET/.cursor/skills/recipe-help" 2>/dev/null || true
  rmdir "$TARGET/docs" 2>/dev/null || true

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
  echo "recipe-help installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
