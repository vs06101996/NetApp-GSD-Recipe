#!/usr/bin/env bash
# tracker-sync installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 4 ("Tracker-sync registration [C]"), independent of
# the full TASK-010 install.sh (size L, not yet built), same precedent as
# install-observer.sh / install-recipe-prd-intake.sh.
#
# NOTE: TASK-014 (BACKLOG.md) is scoped narrowly here — install-time skill
# registration + a thin tracker-config dispatch layer only. It does NOT
# rewrite sync-reconcile.sh/sync-drain-queue.sh/sync-ledger.sh/
# draft-jira-comment.sh, which stay Jira-literal. See
# bench/report/tracker-sync-integration-report.md for the full scope
# decision. It is opt-in, idempotent, and fully removable via --uninstall.
#
# Usage:
#   ./.gsd-recipe/scripts/install-tracker-sync.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-tracker-sync.sh --uninstall [--target <repo_root>]
#
# Design (per INSTALL-LLD Step 4):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data —
#     in particular, never overwrite an already-configured `tracker` value
#     in .gsd-recipe/config.json (an operator may have deliberately set
#     "github"), and never delete config.json on uninstall (it may hold
#     other, unrelated settings this installer doesn't own).
#   - Ledger-tracked: every file this script creates is recorded in
#     .gsd-recipe/ledger.json under component "tracker-sync" for clean
#     removal. config.json is intentionally NOT ledger-tracked for deletion —
#     only the skill file is.
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
  echo "tracker-sync installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
CONFIG="$GSD_RECIPE_DIR/config.json"
SKILL_DEST="$TARGET/.cursor/skills/tracker-sync/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/tracker-sync-SKILL.md"
CONFIG_LIB="$SCRIPT_DIR/../../bench/lib/tracker-sync-config.sh"
COMPONENT="tracker-sync"

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
    read -r -p "Install tracker-sync skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "tracker-sync installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/tracker-sync/SKILL.md"

  # Only set a default tracker if the config doesn't already have one —
  # never clobber an operator's existing choice (e.g. a deliberate "github").
  EXISTING_TRACKER=""
  if [ -f "$CONFIG" ]; then
    EXISTING_TRACKER="$(python3 -c "
import json
try:
    d = json.load(open('$CONFIG'))
    print(d.get('tracker', ''))
except Exception:
    print('')
" 2>/dev/null || true)"
  fi
  if [ -z "$EXISTING_TRACKER" ]; then
    REPO_ROOT="$TARGET" "$CONFIG_LIB" set-tracker jira --config "$CONFIG" >/dev/null
    echo "tracker-sync installer: initialized $CONFIG with tracker: jira (default — the only fully-built path today)."
  else
    echo "tracker-sync installer: $CONFIG already has tracker: $EXISTING_TRACKER, leaving it untouched."
  fi

  echo "tracker-sync installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'tracker-sync' by name to dispatch on the configured tracker —"
  echo "today this always delegates to 'gsd-jira-sync' for tracker: jira."
  echo "GitHub tracker sync is not yet implemented (needs TASK-006)."
  echo "Switch trackers: bench/lib/tracker-sync-config.sh set-tracker <jira|github>"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "tracker-sync installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/tracker-sync" 2>/dev/null || true

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
  echo "tracker-sync installer: uninstall complete. $CONFIG (and its 'tracker' setting) is left in place — it may hold other, unrelated settings this installer doesn't own."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
