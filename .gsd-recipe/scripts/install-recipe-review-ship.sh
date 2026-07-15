#!/usr/bin/env bash
# recipe-review-ship installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern (same approach already used
# by install-recipe-prd-intake.sh / install-recipe-planning-policy.sh /
# install-recipe-run-phase.sh / install-recipe-plan-phase.sh), independent of
# the full TASK-010 install.sh. Composition into install.sh is deferred to a
# later integration pass (see bench/report/recipe-review-ship-integration-report.md
# — three sibling tasks are being built concurrently against install.sh).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as install-recipe-run-phase.sh/install-recipe-plan-phase.sh, NOT the
# plain top-level skills/ path install-recipe-planning-policy.sh uses for
# GSD's own agent_skills injection mechanism).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-review-ship.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-review-ship.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-run-phase.sh/install-recipe-plan-phase.sh's
# structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-review-ship" for clean removal.
#   - Never touches .gsd-recipe/config.json or .planning/config.json — this
#     installer's only job is staging one file.
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
  echo "recipe-review-ship installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-review-ship/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-review-ship-SKILL.md"
COMPONENT="recipe-review-ship"

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
    read -r -p "Install recipe-review-ship skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-review-ship installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-review-ship/SKILL.md"

  echo "recipe-review-ship installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-review-ship N [--draft]' by name to review-and-ship a"
  echo "single phase: calls native gsd-code-review N directly, syncs"
  echo "review_complete via gsd-jira-sync (if a tracker issue is linked,"
  echo "with the optional 'In Review' transition), calls native gsd-ship N"
  echo "[--draft] directly, and surfaces the resulting PR link. Prints"
  echo "gsd-review/gsd-ui-review N as informational-only suggestions —"
  echo "never auto-invokes either."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-review-ship installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/recipe-review-ship" 2>/dev/null || true

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
  echo "recipe-review-ship installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
