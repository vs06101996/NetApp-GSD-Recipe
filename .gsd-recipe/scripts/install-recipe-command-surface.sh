#!/usr/bin/env bash
# recipe-command-surface installer — stages the always-applied Cursor rule that
# translates native GSD next-step suggestions into recipe commands.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-command-surface.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-command-surface.sh --uninstall [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-command-surface.sh --verify [--target <repo_root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MODE="install"
YES=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --verify)    MODE="verify";    shift ;;
    --yes|-y)    YES=1;            shift ;;
    --target)    TARGET="$2"; shift 2   ;;
    *) echo "recipe-command-surface installer: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$SELF_ROOT"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-command-surface installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
COMPONENT="recipe-command-surface"

RULE_DEST="$TARGET/.cursor/rules/recipe-command-surface.mdc"
RULE_SRC="$SCRIPT_DIR/../templates/recipe-command-surface.mdc"

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

ledger_clear() {
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
}

safe_copy() {
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ -e "$src" ]; then
    local src_real dest_real
    src_real="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
    dest_real="$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")"
    if [ "$src_real" = "$dest_real" ]; then
      return 0
    fi
  fi
  cp "$src" "$dest"
}

is_self_install() {
  [ "$(cd "$TARGET" && pwd)" = "$SELF_ROOT" ]
}

install() {
  if [ ! -f "$RULE_SRC" ]; then
    echo "recipe-command-surface installer: missing $RULE_SRC" >&2
    exit 1
  fi

  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-command-surface Cursor rule into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-command-surface installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$RULE_SRC" "$RULE_DEST"
  ledger_record ".cursor/rules/recipe-command-surface.mdc"

  echo "recipe-command-surface installer: staged always-applied Cursor rule."
  echo "  rule: .cursor/rules/recipe-command-surface.mdc"
  ledger_files | sed 's/^/  - /'
}

verify() {
  local ok=1
  if [ ! -f "$RULE_DEST" ]; then
    echo "recipe-command-surface installer --verify: missing $RULE_DEST"
    ok=0
  elif ! grep -q "alwaysApply: true" "$RULE_DEST"; then
    echo "recipe-command-surface installer --verify: $RULE_DEST is not alwaysApply"
    ok=0
  elif ! grep -q 'Never recommend a `gsd-\*' "$RULE_DEST"; then
    echo "recipe-command-surface installer --verify: $RULE_DEST missing next-action translation contract"
    ok=0
  else
    echo "recipe-command-surface installer --verify: $RULE_DEST — pass"
  fi
  if [ "$ok" -eq 1 ]; then
    echo "recipe-command-surface installer --verify: pass"
    return 0
  fi
  echo "recipe-command-surface installer --verify: FAIL"
  return 1
}

uninstall() {
  echo "recipe-command-surface installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    if is_self_install && [ "$rel" = ".cursor/rules/recipe-command-surface.mdc" ]; then
      echo "  keeping $rel (canonical live rule, self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  rmdir "$TARGET/.cursor/rules" 2>/dev/null || true

  ledger_clear
  echo "recipe-command-surface installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  verify) verify ;;
  uninstall) uninstall ;;
esac
