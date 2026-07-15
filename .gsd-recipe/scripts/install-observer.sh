#!/usr/bin/env bash
# FLY ON THE WALL (FOTW) observer installer — fallback path per
# lld/INSTALL-LLD.md Step 3 ("FLY ON THE WALL install [X]").
#
# NOTE: OBSERVER-LLD.md marks the observer "post-pilot — do not implement
# for v1 pilot" (BACKLOG.md TASK-013, Wave 4, sprint "Post-pilot"). This
# script exists ahead of that schedule, at explicit operator request. It is
# opt-in, idempotent, and fully removable via --uninstall.
#
# Usage:
#   ./.gsd-recipe/scripts/install-observer.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-observer.sh --uninstall [--target <repo_root>]
#
# Design (per INSTALL-LLD Step 3):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs, but does not remove
#     the *conceptual* consent requirement — callers must pass it knowingly).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: every file this script creates is recorded in
#     .gsd-recipe/ledger.json under component "fotw-observer" for clean
#     removal. Pre-existing files (e.g. an operator-edited hooks.json) are
#     merged into, never clobbered.
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
  echo "FOTW installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
CONFIG="$GSD_RECIPE_DIR/observer-config.json"
HOOKS_JSON="$TARGET/.cursor/hooks.json"
HOOK_SCRIPT_DEST="$TARGET/.cursor/hooks/fotw-observer-nudge.sh"
HOOK_SCRIPT_SRC="$SCRIPT_DIR/../templates/fotw-observer-nudge.sh"
HOOK_COMMAND=".cursor/hooks/fotw-observer-nudge.sh"
LIB_DEST="$TARGET/.gsd-recipe/lib/observer-lib.sh"
LIB_SRC="$SCRIPT_DIR/../../bench/lib/observer-lib.sh"
TASK_PROMPT_DEST="$TARGET/.gsd-recipe/templates/fotw-observer-task-prompt.md"
TASK_PROMPT_SRC="$SCRIPT_DIR/../templates/fotw-observer-task-prompt.md"
SKILL_DEST="$TARGET/.cursor/skills/fotw-observer-bootstrap/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/fotw-observer-bootstrap-SKILL.md"
COMPONENT="fotw-observer"

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

hooks_json_merge() {
  mkdir -p "$(dirname "$HOOKS_JSON")"
  python3 - "$HOOKS_JSON" "$HOOK_COMMAND" <<'PY'
import json, os, sys
hooks_path, command = sys.argv[1], sys.argv[2]
if os.path.exists(hooks_path):
    with open(hooks_path) as f:
        data = json.load(f)
else:
    data = {"version": 1, "hooks": {}}
data.setdefault("hooks", {})
post = data["hooks"].setdefault("postToolUse", [])
if not any(e.get("command") == command for e in post):
    post.append({"command": command, "matcher": "Write"})
with open(hooks_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

hooks_json_remove_entry() {
  [ -f "$HOOKS_JSON" ] || return 0
  python3 - "$HOOKS_JSON" "$HOOK_COMMAND" <<'PY'
import json, sys
hooks_path, command = sys.argv[1], sys.argv[2]
with open(hooks_path) as f:
    data = json.load(f)
post = data.get("hooks", {}).get("postToolUse", [])
data["hooks"]["postToolUse"] = [e for e in post if e.get("command") != command]
with open(hooks_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install FLY ON THE WALL observer (background loop, post-pilot feature) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "FOTW installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  for d in \
    ".learnings/observer" \
    ".learnings/kb/sessions" \
    ".learnings/kb/playbooks"
  do
    mkdir -p "$TARGET/$d"
    touch "$TARGET/$d/.gitkeep"
    ledger_record "$d/.gitkeep"
  done

  safe_copy "$LIB_SRC" "$LIB_DEST"
  chmod +x "$LIB_DEST"
  ledger_record ".gsd-recipe/lib/observer-lib.sh"

  safe_copy "$HOOK_SCRIPT_SRC" "$HOOK_SCRIPT_DEST"
  chmod +x "$HOOK_SCRIPT_DEST"
  ledger_record ".cursor/hooks/fotw-observer-nudge.sh"

  hooks_json_merge
  ledger_record ".cursor/hooks.json"

  safe_copy "$TASK_PROMPT_SRC" "$TASK_PROMPT_DEST"
  ledger_record ".gsd-recipe/templates/fotw-observer-task-prompt.md"

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/fotw-observer-bootstrap/SKILL.md"

  if [ ! -f "$CONFIG" ]; then
    python3 - "$CONFIG" <<'PY'
import json, sys, datetime
path = sys.argv[1]
config = {
  "_comment": "FOTW observer config. Post-pilot feature (OBSERVER-LLD.md), installed ahead of schedule at operator request.",
  "enabled": True,
  "installed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "tick_interval_seconds": 300,
  "rollup_threshold_signal_lines": 40,
  "inactivity_consecutive_empty_ticks_threshold": 3,
  "end_trigger_finalize_margin_ticks": 2,
  "paths": {
    "lockfile": ".learnings/observer/.tick.lock",
    "offset_file": ".learnings/observer/.offset",
    "live_transcript_file": ".learnings/observer/live-transcript.jsonl",
    "ticks_file": ".learnings/observer/ticks.jsonl",
    "noise_log_file": ".learnings/observer/noise-log.jsonl",
    "stop_sentinel_file": ".learnings/observer/.stop",
    "kb_sessions_dir": ".learnings/kb/sessions",
    "kb_playbooks_dir": ".learnings/kb/playbooks"
  },
  "classification_rubric": {
    "signal": "on-topic AND conclusive: a stated decision, fact, requirement, or confirmed answer about the PRD/recipe/codebase under discussion",
    "noise_irrelevant": "off-topic content unrelated to the PRD/recipe/codebase being discussed",
    "noise_hedge": "on-topic but non-conclusive: hedges, assumptions, placeholders (e.g. 'maybe', 'TBD', 'not sure', 'let's assume for now')"
  },
  "session_end_triggers": {
    "explicit_stop": "stop_sentinel_file exists at top of tick -> finalize immediately",
    "inactivity": "inactivity_consecutive_empty_ticks_threshold consecutive ticks with zero new lines -> finalize as idle",
    "prd_complete": "tick's own judgment detects a turn declaring all tracked requirements satisfied -> finalize immediately, do not wait for inactivity"
  }
}
with open(path, "w") as f:
    json.dump(config, f, indent=2)
    f.write("\n")
PY
    ledger_record ".gsd-recipe/observer-config.json"
  else
    echo "FOTW installer: $CONFIG already exists, leaving operator config untouched."
  fi

  echo "FOTW installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Two independent trigger paths are now wired, sharing one guard and one"
  echo "subagent spec (.gsd-recipe/lib/observer-lib.sh can-spawn / .gsd-recipe/templates/fotw-observer-task-prompt.md):"
  echo "  1. Reactive hook: fires on any Write to docs/PRD.md, .planning/intake/PRD.md, or .planning/STATE.md."
  echo "  2. Pluggable skill: invoke 'fotw-observer-bootstrap' by name, or reference it as a step"
  echo "     from any future PRD-intake command (e.g. recipe-prd-intake once it exists)."
  echo "Disable without uninstalling: set \"enabled\": false in $CONFIG"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

is_canonical_source() {
  # $1 = absolute path being considered for removal. Returns 0 (skip removal)
  # if it resolves to one of our own template/lib sources — true whenever
  # TARGET is this implementation repo itself (self-install case: deployed
  # path and canonical source path coincide). Deleting these would destroy
  # the template, not just an installed copy.
  local candidate="$1" src
  [ -e "$candidate" ] || return 1
  for src in "$LIB_SRC" "$HOOK_SCRIPT_SRC" "$TASK_PROMPT_SRC" "$SKILL_SRC"; do
    [ -e "$src" ] || continue
    if [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" ]; then
      return 0
    fi
  done
  return 1
}

uninstall() {
  echo "FOTW installer: removing tracked files for component '$COMPONENT'..."
  hooks_json_remove_entry
  while IFS= read -r rel; do
    case "$rel" in
      .gsd-recipe/observer-config.json)
        echo "  keeping $rel (operator data — remove by hand if desired)"
        continue
        ;;
      .cursor/hooks.json)
        continue # handled by hooks_json_remove_entry above
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
  rmdir "$TARGET/.cursor/skills/fotw-observer-bootstrap" 2>/dev/null || true
  rmdir "$TARGET/.cursor/hooks" 2>/dev/null || true
  rmdir "$TARGET/.gsd-recipe/lib" 2>/dev/null || true
  rmdir "$TARGET/.gsd-recipe/templates" 2>/dev/null || true

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
  echo "FOTW installer: uninstall complete. .learnings/ data and observer-config.json left in place."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
