#!/usr/bin/env bash
# gsd-jira-sync installer (TASK-028) — closes the staging gap flagged in
# tracker-sync-SKILL.md and every recipe-* skill that invokes gsd-jira-sync
# "by name" (recipe-plan-phase, recipe-run-phase, recipe-verify-feature,
# recipe-review-ship, recipe-settle, tracker-sync itself): the skill has only
# ever existed as documentation at
# docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md — nothing staged
# it into .cursor/skills/gsd-jira-sync/SKILL.md on a fresh install, so every
# "invoke gsd-jira-sync by name" instruction would silently fail to resolve
# on a brand-new target repo. Standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern, mirroring
# install-tracker-sync.sh's structure/functions as closely as possible.
#
# Usage:
#   ./.gsd-recipe/scripts/install-gsd-jira-sync.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-gsd-jira-sync.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-tracker-sync.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "gsd-jira-sync" for clean removal.
#   - Never touches .gsd-recipe/config.json's "tracker" field (that's
#     install-tracker-sync.sh's own job, already built) and never touches
#     .planning/config.json — this installer's only job is staging one file.
#     It also never touches .planning/STATE.md or
#     .gsd-recipe/sync-ledger.jsonl itself — issue resolution and idempotent
#     posting are the staged skill's own runtime job (see SKILL.md § C),
#     not the installer's.
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
  echo "gsd-jira-sync installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/gsd-jira-sync/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/gsd-jira-sync-SKILL.md"
COMPONENT="gsd-jira-sync"

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
    read -r -p "Install gsd-jira-sync skill into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "gsd-jira-sync installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/gsd-jira-sync/SKILL.md"

  echo "gsd-jira-sync installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'gsd-jira-sync' by name to post a GSD lifecycle milestone as a"
  echo "Jira comment (single-event mode) or drain a queued backlog (--drain)."
  echo "tracker-sync and every recipe-* skill that syncs a lifecycle event"
  echo "(recipe-plan-phase, recipe-run-phase, recipe-verify-feature,"
  echo "recipe-review-ship, recipe-settle) delegate to this skill by name —"
  echo "this installer is what makes that resolve on a fresh target."
  echo "This installer never touches .gsd-recipe/config.json's 'tracker' field"
  echo "(install-tracker-sync.sh's own job) or .planning/config.json."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "gsd-jira-sync installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/gsd-jira-sync" 2>/dev/null || true

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
  echo "gsd-jira-sync installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
