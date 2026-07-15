#!/usr/bin/env bash
# recipe-install-verify installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 5's documented pattern (same approach already used
# by install-recipe-run-phase.sh / install-recipe-plan-phase.sh),
# independent of the full TASK-010 install.sh (though intended to also be
# composed into it — see the integration report's copy-paste-ready
# install.sh snippet; that edit is NOT applied by this script or by this
# task, per the parallel-work shared-file constraint it was built under).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as recipe-run-phase/recipe-plan-phase/recipe-prd-intake, NOT the
# plain top-level skills/ path recipe-planning-policy's agent_skills
# injection mechanism uses).
#
# Also stages this skill's runtime dependency, bench/lib/install-verify-report.sh
# (the report writer the staged skill's own instructions shell out to) — a
# second ledgered file, same component.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-install-verify.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-install-verify.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-run-phase.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: every staged file is recorded in
#     .gsd-recipe/ledger.json under component "recipe-install-verify" for
#     clean removal.
#   - Never touches .gsd-recipe/config.json, .gsd-recipe/install-report.json,
#     or .planning/config.json — this installer's only job is staging files;
#     writing into install-report.json is the staged SKILL's own runtime job
#     (via bench/lib/install-verify-report.sh), not this installer's.
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
  echo "recipe-install-verify installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-install-verify/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-install-verify-SKILL.md"
LIB_DEST="$TARGET/bench/lib/install-verify-report.sh"
LIB_SRC="$SCRIPT_DIR/../../bench/lib/install-verify-report.sh"
COMPONENT="recipe-install-verify"

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
  # $1 = candidate absolute path, $2 = canonical source absolute path.
  # Returns 0 (skip removal) if they resolve to the same file — true
  # whenever TARGET is this implementation repo itself (self-install case).
  local candidate="$1" src="$2"
  [ -e "$candidate" ] || return 1
  [ -e "$src" ] || return 1
  [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" ]
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-install-verify skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-install-verify installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-install-verify/SKILL.md"

  safe_copy "$LIB_SRC" "$LIB_DEST"
  chmod +x "$LIB_DEST" 2>/dev/null || true
  ledger_record "bench/lib/install-verify-report.sh"

  echo "recipe-install-verify installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-install-verify [--target <path>]' by name to run the full"
  echo "10-item Step-5 verification checklist: install.sh --verify as the"
  echo "bash-checkable foundation (items 5-7), native /gsd-health,"
  echo "/gsd-health --context, /gsd-surface status (items 1-3), a"
  echo "recipe-validate-tokens delegation or gh-auth-status fallback (item 4),"
  echo "an MCP tool-listing smoke check (item 8), an observer-config.json"
  echo "presence/enabled check (item 9), and a gated bare_metal.template.md"
  echo "Gate A run (item 10) — recording pass/warn/fail per item plus the"
  echo "install_verified marker into .gsd-recipe/install-report.json."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-install-verify installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local canonical_src=""
    case "$rel" in
      .cursor/skills/recipe-install-verify/SKILL.md) canonical_src="$SKILL_SRC" ;;
      bench/lib/install-verify-report.sh) canonical_src="$LIB_SRC" ;;
    esac
    if [ -n "$canonical_src" ] && is_canonical_source "$TARGET/$rel" "$canonical_src"; then
      echo "  keeping $rel (this is the canonical template source, not an installed copy — self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  # Clean up now-empty directories left behind (rmdir is a silent no-op if not empty).
  rmdir "$TARGET/.cursor/skills/recipe-install-verify" 2>/dev/null || true

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
  echo "recipe-install-verify installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
