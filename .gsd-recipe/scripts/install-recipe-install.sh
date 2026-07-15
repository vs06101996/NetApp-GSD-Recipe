#!/usr/bin/env bash
# recipe-install installer (TASK-031) — stages the end-to-end install
# orchestrator skill described in .gsd-recipe/templates/recipe-install-SKILL.md.
# Standalone fallback path per lld/INSTALL-LLD.md's documented pattern,
# mirroring install-recipe-sync.sh's / install-recipe-run-phases.sh's
# structure/functions as closely as possible (single-file staging, no config
# side effects).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-install.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-install.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-sync.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs). This is this
#     installer's own, ordinary, single-file scaffolding-consent prompt —
#     unrelated to the staged skill's own, much stricter, live-conversation
#     Step B/uninstall gate, which only exists once the skill itself is
#     invoked conversationally (never inside this script).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-install" for clean removal.
#   - Never touches .gsd-recipe/config.json, .planning/config.json, or
#     .gsd-recipe/ledger.json beyond its own component's row — and, uniquely
#     for this installer, never touches .gsd-recipe/scripts/install.sh
#     itself either (that file is a sibling this skill's own runtime
#     instructions invoke via Shell, not something this installer stages,
#     copies, or removes).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
  TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-install installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-install/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-install-SKILL.md"
COMPONENT="recipe-install"

mkdir -p "$GSD_RECIPE_DIR"

ledger_init() {
  [ -f "$LEDGER" ] || printf '{}\n' > "$LEDGER"
}

ledger_record() {
  # $1 = path relative to $TARGET
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
  # $1 = src, $2 = dest. Skips the copy (not an error) when src and dest
  # already resolve to the same file — happens when installing into the
  # implementation repo itself (gsd-benchmark is both source and target).
  local src="$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] && [ "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" = "$(cd "$(dirname "$dest")" && pwd)/$(basename "$dest")" ]; then
    return 0
  fi
  cp "$src" "$dest"
}

is_canonical_source() {
  # $1 = absolute path being considered for removal. Returns 0 (skip removal)
  # if it resolves to our own template source — true whenever TARGET is this
  # implementation repo itself (self-install case).
  local candidate="$1"
  [ -e "$candidate" ] || return 1
  [ -e "$SKILL_SRC" ] || return 1
  [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$SKILL_SRC")" && pwd)/$(basename "$SKILL_SRC")" ]
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-install skill (end-to-end install orchestrator) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-install installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-install/SKILL.md"

  echo "recipe-install installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-install [--target <path>] [--uninstall]' by name to run the"
  echo "full end-to-end install flow: recipe-validate-tokens (informational) ->"
  echo "a live consent gate asked in your own conversation -> the real"
  echo "install.sh --yes --target <path> -> recipe-install-verify's Step-5"
  echo "checklist -> one combined summary. '--uninstall' delegates to"
  echo "install.sh --uninstall --yes, behind its own equally-explicit"
  echo "live-conversation confirm gate. This installer never touches"
  echo "install.sh itself, .gsd-recipe/config.json, or .planning/config.json —"
  echo "it only stages the skill file."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-install installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    if is_canonical_source "$TARGET/$rel"; then
      echo "  keeping $rel (this is the canonical skill template source, not an installed copy — self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  # Clean up now-empty directories left behind (rmdir is a silent no-op if not empty).
  rmdir "$TARGET/.cursor/skills/recipe-install" 2>/dev/null || true

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
  echo "recipe-install installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
