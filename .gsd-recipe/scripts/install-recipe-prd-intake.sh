#!/usr/bin/env bash
# recipe-prd-intake installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern (same approach already used
# by install-observer.sh), independent of the full TASK-010 install.sh
# (size L, not yet built).
#
# NOTE: BACKLOG.md TASK-016 lists this as depending on TASK-010. This script
# exists ahead of that dependency, at explicit operator request, mirroring
# how the FOTW observer (TASK-013, formally post-pilot) was already built
# standalone. It is opt-in, idempotent, and fully removable via --uninstall.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-prd-intake.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-prd-intake.sh --uninstall [--target <repo_root>]
#
# Design (per INSTALL-LLD Step 3):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data
#     (an existing .templates/PRD.template.md, or any docs/PRD.md — this
#     installer never touches docs/PRD.md at all; only the skill writes it,
#     at actual invocation time, with its own overwrite confirmation gate).
#   - Ledger-tracked: every file this script creates is recorded in
#     .gsd-recipe/ledger.json under component "recipe-prd-intake" for clean
#     removal.
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
  echo "recipe-prd-intake installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-prd-intake/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-prd-intake-SKILL.md"
TEMPLATE_DEST="$TARGET/.templates/PRD.template.md"
TEMPLATE_SRC="$SCRIPT_DIR/../templates/PRD.template.md"
COMPONENT="recipe-prd-intake"

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
  # if it resolves to one of our own template sources — true whenever TARGET
  # is this implementation repo itself (self-install case: deployed path and
  # canonical source path coincide). Deleting these would destroy the
  # template, not just an installed copy.
  local candidate="$1" src
  [ -e "$candidate" ] || return 1
  for src in "$SKILL_SRC" "$TEMPLATE_SRC"; do
    [ -e "$src" ] || continue
    if [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" ]; then
      return 0
    fi
  done
  return 1
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-prd-intake skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-prd-intake installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  if [ -f "$TEMPLATE_DEST" ]; then
    echo "recipe-prd-intake installer: $TEMPLATE_DEST already exists, leaving it untouched."
  else
    safe_copy "$TEMPLATE_SRC" "$TEMPLATE_DEST"
    ledger_record ".templates/PRD.template.md"
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-prd-intake/SKILL.md"

  echo "recipe-prd-intake installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-prd-intake' by name with a PRD file, pasted text, or a"
  echo "freeform description. It writes docs/PRD.md and, as its final step,"
  echo "invokes 'fotw-observer-bootstrap' (if that's installed) to start the"
  echo "FOTW observer watching this session."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-prd-intake installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    case "$rel" in
      .templates/PRD.template.md)
        echo "  keeping $rel (operator-customizable scaffold data, same as observer-config.json — remove by hand if desired)"
        continue
        ;;
    esac
    if is_canonical_source "$TARGET/$rel"; then
      echo "  keeping $rel (this is the canonical template source, not an installed copy — self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  # Clean up now-empty directories left behind (rmdir is a silent no-op if not empty).
  rmdir "$TARGET/.cursor/skills/recipe-prd-intake" 2>/dev/null || true

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
  echo "recipe-prd-intake installer: uninstall complete. .templates/PRD.template.md and any docs/PRD.md written during use are left in place."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
