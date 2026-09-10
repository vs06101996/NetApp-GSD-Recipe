#!/usr/bin/env bash
# recipe-gitignore.sh — additive recipe .gitignore lines (INSTALL-LLD).
# Used by install.sh and recipe-onboard so a new initiative cut from trunk
# still ignores recipe artifacts when the previous PR's .gitignore never merged.
#
# Usage:
#   recipe-gitignore.sh ensure --target <repo_root> [--self-install]
#   recipe-gitignore.sh missing --target <repo_root> [--self-install]
set -euo pipefail

SUBCOMMAND="${1:-}"
shift || true

TARGET=""
SELF_INSTALL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --self-install) SELF_INSTALL=1; shift ;;
    -*) echo "recipe-gitignore.sh: unknown flag: $1" >&2; exit 2 ;;
    *) echo "recipe-gitignore.sh: unexpected argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  echo "recipe-gitignore.sh: --target is required" >&2
  exit 2
fi
if [ ! -d "$TARGET" ]; then
  echo "recipe-gitignore.sh: target does not exist: $TARGET" >&2
  exit 1
fi

if [ "$SELF_INSTALL" -eq 0 ] &&
   [ -f "$TARGET/bench/lib/recipe-gitignore.sh" ] &&
   [ -d "$TARGET/.gsd-recipe/templates" ]; then
  SELF_INSTALL=1
fi

recipe_gitignore_lines() {
  cat <<'EOF'
/bin/
/dist/
*.exe
.idea/
.vscode/
.env
.env.*
.learnings/
.gsd/
.gsd-codebase/
.gsd-recipe/
.knowledge/
.templates/
.planning/
code_base_details/
skills/
docs/RECIPE-COMMANDS.md
docs/RECIPE-BENCHMARKS.md
docs/RECIPE-SEQUENCE.md
bench/
.cursor/get-shit-done/
.cursor/gsd-install-state.json
.cursor/gsd-file-manifest.json
.cursor/.gsd-profile
graphify-out/
EOF
}

should_skip() {
  [ "$SELF_INSTALL" -eq 1 ] && [ "$1" = ".gsd-recipe/" ]
}

GITIGNORE="$TARGET/.gitignore"

cmd_ensure() {
  mkdir -p "$(dirname "$GITIGNORE")"
  touch "$GITIGNORE"
  local line added=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    should_skip "$line" && continue
    if ! grep -qxF "$line" "$GITIGNORE"; then
      printf '%s\n' "$line" >> "$GITIGNORE"
      added=$((added + 1))
    fi
  done < <(recipe_gitignore_lines)
  if [ "$added" -eq 0 ]; then
    echo "recipe-gitignore.sh: .gitignore already has recipe entries"
  else
    echo "recipe-gitignore.sh: added $added recipe ignore line(s) to $GITIGNORE"
  fi
}

cmd_missing() {
  local line missing=0
  touch "$GITIGNORE" 2>/dev/null || true
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    should_skip "$line" && continue
    if [ ! -f "$GITIGNORE" ] || ! grep -qxF "$line" "$GITIGNORE"; then
      printf '%s\n' "$line"
      missing=1
    fi
  done < <(recipe_gitignore_lines)
  [ "$missing" -eq 0 ]
}

case "$SUBCOMMAND" in
  ensure) cmd_ensure ;;
  missing) cmd_missing ;;
  *)
    echo "recipe-gitignore.sh: unknown subcommand '$SUBCOMMAND' (use ensure|missing)" >&2
    exit 2
    ;;
esac
