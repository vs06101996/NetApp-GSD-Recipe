#!/usr/bin/env bash
# recipe-workspace installer (TASK-059) — per-branch workspace swap.
# Stages workspace-swap.sh lib, recipe-workspace skill, git post-checkout hook,
# and Cursor postToolUse/Bash fallback hook.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-workspace.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-workspace.sh --uninstall [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-workspace.sh --verify   [--target <repo_root>]
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
    *) echo "recipe-workspace installer: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$SELF_ROOT"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-workspace installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
COMPONENT="recipe-workspace"

SKILL_DEST="$TARGET/.cursor/skills/recipe-workspace/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-workspace-SKILL.md"

LIB_SRC="$SELF_ROOT/bench/lib/workspace-swap.sh"
LIB_DEST="$GSD_RECIPE_DIR/lib/workspace-swap.sh"

HOOK_SRC="$SCRIPT_DIR/../hooks/post-checkout"
HOOK_DEST="$TARGET/.git/hooks/post-checkout"

CURSOR_FALLBACK_SRC="$SCRIPT_DIR/../hooks/workspace-swap-cursor-fallback.sh"
CURSOR_FALLBACK_DEST="$TARGET/.cursor/hooks/workspace-swap-cursor-fallback.sh"
CURSOR_FALLBACK_COMMAND=".cursor/hooks/workspace-swap-cursor-fallback.sh"

HOOKS_JSON="$TARGET/.cursor/hooks.json"

mkdir -p "$GSD_RECIPE_DIR"

# ── ledger helpers ────────────────────────────────────────────────────────────

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

# ── safe_copy (skip when src == dest, i.e. self-install) ─────────────────────

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

# ── hooks.json merge/remove ───────────────────────────────────────────────────

hooks_json_merge() {
  mkdir -p "$(dirname "$HOOKS_JSON")"
  python3 - "$HOOKS_JSON" "$CURSOR_FALLBACK_COMMAND" <<'PY'
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
    post.append({"command": command, "matcher": "Bash"})
with open(hooks_path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

hooks_json_remove_entry() {
  [ -f "$HOOKS_JSON" ] || return 0
  python3 - "$HOOKS_JSON" "$CURSOR_FALLBACK_COMMAND" <<'PY'
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

# ── install ───────────────────────────────────────────────────────────────────

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-workspace (per-branch swap hook) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-workspace installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  for src_file in "$SKILL_SRC" "$LIB_SRC" "$HOOK_SRC" "$CURSOR_FALLBACK_SRC"; do
    if [ ! -f "$src_file" ]; then
      echo "recipe-workspace installer: missing source file: $src_file" >&2
      exit 1
    fi
  done

  # Skill
  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-workspace/SKILL.md"

  # Core lib
  mkdir -p "$(dirname "$LIB_DEST")"
  safe_copy "$LIB_SRC" "$LIB_DEST"
  chmod +x "$LIB_DEST"
  ledger_record ".gsd-recipe/lib/workspace-swap.sh"

  # git post-checkout hook (NOT ledger-tracked — .git/ is outside the tracked tree)
  safe_copy "$HOOK_SRC" "$HOOK_DEST"
  chmod +x "$HOOK_DEST"

  # Cursor postToolUse/Bash fallback
  safe_copy "$CURSOR_FALLBACK_SRC" "$CURSOR_FALLBACK_DEST"
  chmod +x "$CURSOR_FALLBACK_DEST"
  ledger_record ".cursor/hooks/workspace-swap-cursor-fallback.sh"

  # hooks.json merge
  hooks_json_merge
  ledger_record ".cursor/hooks.json"

  # workspaces scaffold
  mkdir -p "$GSD_RECIPE_DIR/workspaces"
  touch "$GSD_RECIPE_DIR/workspaces/.gitkeep"
  ledger_record ".gsd-recipe/workspaces/.gitkeep"

  echo "recipe-workspace installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "git hook: $HOOK_DEST (active — fires on git checkout/switch)"
  echo "Cursor fallback: $CURSOR_FALLBACK_COMMAND (postToolUse/Bash — fires after Bash tool calls)"
  echo "Note: git hook is not ledger-tracked. Remove manually if desired: rm $HOOK_DEST"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

# ── uninstall ─────────────────────────────────────────────────────────────────

uninstall() {
  echo "recipe-workspace installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local abs="$TARGET/$rel"
    # Skip when src == dest (self-install canonical source files)
    if [ -f "$abs" ]; then
      # Check if this is a canonical source we must not delete
      local skip=0
      for canon in "$SKILL_SRC" "$LIB_SRC" "$CURSOR_FALLBACK_SRC"; do
        if [ -e "$canon" ] && [ -e "$abs" ]; then
          local canon_real abs_real
          canon_real="$(cd "$(dirname "$canon")" && pwd)/$(basename "$canon")"
          abs_real="$(cd "$(dirname "$abs")" && pwd)/$(basename "$abs")"
          if [ "$canon_real" = "$abs_real" ]; then
            echo "  keeping $rel (canonical source — self-install)"
            skip=1
            break
          fi
        fi
      done
      if [ "$skip" -eq 0 ]; then
        rm -f "$abs"
        echo "  removed $rel"
      fi
    fi
  done < <(ledger_files)

  # Remove hooks.json entry
  hooks_json_remove_entry

  # Remove skill dir if empty
  rmdir "$TARGET/.cursor/skills/recipe-workspace" 2>/dev/null || true

  # Remove workspaces/ only if empty (preserve snapshots)
  local wdir="$GSD_RECIPE_DIR/workspaces"
  if [ -d "$wdir" ]; then
    # Count non-.gitkeep files
    local count
    count="$(find "$wdir" -not -name ".gitkeep" -not -path "$wdir" | wc -l | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
      rm -rf "$wdir"
      echo "  removed .gsd-recipe/workspaces/ (empty)"
    else
      echo "  keeping .gsd-recipe/workspaces/ (contains snapshots — remove manually)"
    fi
  fi

  echo "Note: git hook at $HOOK_DEST is NOT removed automatically."
  echo "  Remove manually if desired: rm $HOOK_DEST"

  ledger_clear
  echo "recipe-workspace installer: uninstall complete."
}

# ── verify ────────────────────────────────────────────────────────────────────

verify() {
  local missing=()

  while IFS= read -r rel; do
    [ -f "$TARGET/$rel" ] || missing+=("$rel")
  done < <(ledger_files 2>/dev/null || true)

  # git hook (not in ledger)
  if [ ! -x "$HOOK_DEST" ]; then
    missing+=(".git/hooks/post-checkout (not executable or missing)")
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    echo "recipe-workspace installer: verify PASS — all files present"
    exit 0
  else
    echo "recipe-workspace installer: verify FAIL — missing:"
    for m in "${missing[@]}"; do
      echo "  - $m"
    done
    exit 1
  fi
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$MODE" in
  install)   install   ;;
  uninstall) uninstall ;;
  verify)    verify    ;;
esac
