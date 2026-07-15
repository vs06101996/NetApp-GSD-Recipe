#!/usr/bin/env bash
# recipe-pr-comment installer (TASK-030) — stages the invoke-by-name skill
# described in .gsd-recipe/templates/recipe-pr-comment-SKILL.md, plus its
# runtime dependency bench/runners/post-github-pr-comment.sh (the real
# draft->idempotency-check->post->ledger script the staged skill's own
# instructions shell out to). Standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern, mirroring
# install-recipe-install-verify.sh's two-file-staging structure/functions
# (same "no single canonical staged_path" shape, since this component also
# stages more than one file under one ledger component) as closely as
# possible, independent of the full TASK-010 install.sh (though also
# composed into it, as its 15th sub-installer).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-pr-comment.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-pr-comment.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-install-verify.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: both staged files are recorded in
#     .gsd-recipe/ledger.json under component "recipe-pr-comment" for clean
#     removal.
#   - Never touches .gsd-recipe/config.json, .planning/config.json, or
#     .gsd-recipe/sync-ledger.jsonl — those are the staged skill's own
#     runtime concern (via post-github-pr-comment.sh / sync-ledger.sh)
#     whenever it's actually invoked, not this installer's job. This
#     installer's only job is staging two files.
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
  echo "recipe-pr-comment installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-pr-comment/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-pr-comment-SKILL.md"
RUNNER_DEST="$TARGET/bench/runners/post-github-pr-comment.sh"
RUNNER_SRC="$SCRIPT_DIR/../../bench/runners/post-github-pr-comment.sh"
COMPONENT="recipe-pr-comment"

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
    read -r -p "Install recipe-pr-comment skill + post-github-pr-comment.sh runner (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-pr-comment installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-pr-comment/SKILL.md"

  safe_copy "$RUNNER_SRC" "$RUNNER_DEST"
  chmod +x "$RUNNER_DEST" 2>/dev/null || true
  ledger_record "bench/runners/post-github-pr-comment.sh"

  echo "recipe-pr-comment installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-pr-comment <event_id> <pr_number> --phase N [...]' by name"
  echo "to draft (draft-github-pr-comment.sh) + idempotency-check (sync-ledger.sh)"
  echo "+ post (real 'gh pr comment') + ledger-record a GitHub PR lifecycle"
  echo "comment. Unlike Jira posting, this is a real, scriptable, testable"
  echo "pipeline end-to-end — no MCP call anywhere. No stamp is ever emitted"
  echo "(github-events.json has no 'stamp' field at all)."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-pr-comment installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local canonical_src=""
    case "$rel" in
      .cursor/skills/recipe-pr-comment/SKILL.md) canonical_src="$SKILL_SRC" ;;
      bench/runners/post-github-pr-comment.sh) canonical_src="$RUNNER_SRC" ;;
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
  rmdir "$TARGET/.cursor/skills/recipe-pr-comment" 2>/dev/null || true

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
  echo "recipe-pr-comment installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
