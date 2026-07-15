#!/usr/bin/env bash
# recipe-plan-phase installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern (same approach already used
# by install-recipe-prd-intake.sh / install-recipe-planning-policy.sh /
# install-recipe-run-phase.sh), independent of the full TASK-010 install.sh
# (though also composed into it — see install.sh's
# RECIPE_PLAN_PHASE_INSTALLER wiring).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as install-recipe-run-phase.sh, NOT the plain top-level skills/ path
# install-recipe-planning-policy.sh uses for GSD's own agent_skills injection
# mechanism).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-plan-phase.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-plan-phase.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-run-phase.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-plan-phase" for clean removal.
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
  echo "recipe-plan-phase installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-plan-phase/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-plan-phase-SKILL.md"
COMPONENT="recipe-plan-phase"

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
    read -r -p "Install recipe-plan-phase skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-plan-phase installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-plan-phase/SKILL.md"

  echo "recipe-plan-phase installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-plan-phase N' by name to gate-and-plan a single phase:"
  echo "determines first-plan vs re-plan, resolves the tracker issue key, calls"
  echo "native gsd-plan-phase N directly, then post-hoc verifies the resulting"
  echo "PLAN.md (soft warn-and-confirm) and syncs plan_complete/plan_revised"
  echo "via gsd-jira-sync (if a tracker issue is linked)."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-plan-phase installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/recipe-plan-phase" 2>/dev/null || true

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
  echo "recipe-plan-phase installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
