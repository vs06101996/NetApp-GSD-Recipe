#!/usr/bin/env bash
# recipe-observe installer (TASK-032) — stages the operator-facing FOTW
# observer lifecycle front-door skill described in
# .gsd-recipe/templates/recipe-observe-SKILL.md. Standalone fallback path
# per lld/INSTALL-LLD.md Step 3's documented pattern, mirroring
# install-tracker-sync.sh's / install-recipe-sync.sh's structure/functions
# as closely as possible (single-file staging, no config side effects).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-observe.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-observe.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-tracker-sync.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-observe" for clean removal.
#   - Stages ONLY the skill file (.cursor/skills/recipe-observe/SKILL.md).
#     Deliberately never stages, copies, or touches
#     .gsd-recipe/lib/observer-lib.sh, .gsd-recipe/observer-config.json,
#     .gsd-recipe/scripts/install-observer.sh, or any other FOTW file —
#     those remain exclusively install-observer.sh's job. The staged
#     skill's own runtime instructions document this as a dependency
#     (checked at invocation time, per fotw-observer-bootstrap/SKILL.md's
#     own § B precedent) — this installer never enforces or checks for it
#     at install time, same "installer stages, skill's own prerequisites
#     section documents" split gsd-jira-sync's installer already
#     established relative to tracker-sync.
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
  echo "recipe-observe installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-observe/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-observe-SKILL.md"
COMPONENT="recipe-observe"

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
    read -r -p "Install recipe-observe skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-observe installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-observe/SKILL.md"

  echo "recipe-observe installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-observe <status|start|stop|enable|disable>' by name."
  echo "This is a thin front door only — 'start' delegates to"
  echo "'fotw-observer-bootstrap', and status/stop/enable/disable delegate to"
  echo "bench/lib/observer-lib.sh's own subcommands. 'stop' only sets a"
  echo "graceful-finalize sentinel the tick loop checks at its next tick —"
  echo "it cannot forcibly kill an already-running observer subagent."
  echo "Runtime dependency (not staged by this installer, staged separately"
  echo "by install-observer.sh): .gsd-recipe/observer-config.json,"
  echo ".gsd-recipe/lib/observer-lib.sh. If those are missing, every"
  echo "subcommand except 'status' fails closed with a clear message."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-observe installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/recipe-observe" 2>/dev/null || true

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
  echo "recipe-observe installer: uninstall complete. .gsd-recipe/observer-config.json,"
  echo ".gsd-recipe/lib/observer-lib.sh, and .gsd-recipe/scripts/install-observer.sh"
  echo "(if present) are left in place — this installer never staged them and"
  echo "does not own their removal (install-observer.sh --uninstall's job)."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
