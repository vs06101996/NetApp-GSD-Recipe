#!/usr/bin/env bash
# recipe-paths.sh — single canonical path resolver for every recipe-*
# skill/script that needs to locate harness code (a `.gsd-recipe/scripts/*`
# installer, a `bench/runners/*` runner, or a `bench/lib/*` library) at
# runtime, on ANY target repo — not just the recipe's own source repo
# (gsd-benchmark).
#
# Why this file exists (the permanent fix for the "missing script on
# external target" class of bug — see recipe-validate-tokens's own
# --check-github failure on a fresh `install.sh --target <external-repo>`
# for the original symptom): install.sh --target <repo> stages Cursor
# skills (and a handful of runners individual sub-installers happen to
# copy) into <repo>, but most of bench/runners/ and bench/lib/ — and
# .gsd-recipe/scripts/ itself — are NOT duplicated into every target by
# design (duplicating the entire harness into every installed repo would
# mean N drifting copies of the same code instead of one source of truth).
# Any skill whose instructions shell out to a hardcoded relative path like
# `.gsd-recipe/scripts/install-recipe-settle.sh` or
# `bench/runners/create-phase-tasks.sh` breaks the moment that path isn't
# also staged locally.
#
# The fix: install.sh records where the recipe's own source tree lives (the
# repo `install.sh` itself was invoked from) as `recipe_source` in the
# target's own `.gsd-recipe/config.json`, and stages *this one small
# resolver script* — never the rest of the harness — into every target at
# `.gsd-recipe/scripts/recipe-paths.sh`. Every skill/installer that needs a
# harness path resolves it through this script instead of hardcoding a
# relative path or self-copying itself into the target (the ad hoc pattern
# recipe-validate-tokens used before this file existed):
#
#   RESOLVED="$("$TARGET/.gsd-recipe/scripts/recipe-paths.sh" resolve \
#     .gsd-recipe/scripts/install-recipe-settle.sh --target "$TARGET")"
#   "$RESOLVED" --check-ci owner/repo 42
#
# Resolution order for a given relative path (e.g. "bench/runners/foo.sh"):
#   1. "$TARGET/<relative_path>"                       — staged locally
#   2. "$recipe_source/<relative_path>"                 — from config.json
#   3. two levels up from this script's own location    — this script is
#      itself running from a canonical .gsd-recipe/scripts/ tree, i.e. the
#      self-install case (TARGET is the recipe's own source repo, so
#      config.json never got a recipe_source written for it — see
#      install.sh's config_json_merge()).
# Fails closed (non-zero, actionable message on stderr) only if none of the
# three resolve to a real file — never silently returns a guessed path.
#
# Usage:
#   recipe-paths.sh resolve <relative_path> [--target <repo_root>]
#   recipe-paths.sh source [--target <repo_root>]   # prints recipe_source
#                                                     # (or the target itself
#                                                     # when unset/self-install)
#
# Examples:
#   recipe-paths.sh resolve .gsd-recipe/scripts/install.sh --target /tmp/sandbox
#   recipe-paths.sh resolve bench/runners/create-phase-tasks.sh --target /tmp/sandbox
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD=""
REL_PATH=""
TARGET=""

usage() {
  cat >&2 <<'EOF'
Usage:
  recipe-paths.sh resolve <relative_path> [--target <repo_root>]
  recipe-paths.sh source [--target <repo_root>]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  resolve)
    [ $# -ge 1 ] || usage
    REL_PATH="$1"; shift
    ;;
  source) : ;;
  *) usage ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    *) echo "recipe-paths.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# This script's own location is always .gsd-recipe/scripts/recipe-paths.sh
# once staged (or bench/lib/recipe-paths.sh when run straight from the
# recipe's own source tree, e.g. via bench/tests/) — either way, two levels
# up is a repo root. Used only as the last-resort fallback below.
SELF_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

get_recipe_source() {
  local config="$TARGET/.gsd-recipe/config.json"
  [ -f "$config" ] || return 1
  python3 -c "
import json
try:
    with open('$config') as f:
        data = json.load(f)
except Exception:
    raise SystemExit(1)
src = data.get('recipe_source')
if not src:
    raise SystemExit(1)
print(src)
" 2>/dev/null
}

resolve() {
  local rel="$1"

  if [ -e "$TARGET/$rel" ]; then
    echo "$TARGET/$rel"
    return 0
  fi

  local recipe_source
  if recipe_source="$(get_recipe_source)" && [ -n "$recipe_source" ] && [ -e "$recipe_source/$rel" ]; then
    echo "$recipe_source/$rel"
    return 0
  fi

  if [ -e "$SELF_REPO_ROOT/$rel" ]; then
    echo "$SELF_REPO_ROOT/$rel"
    return 0
  fi

  echo "recipe-paths.sh: could not resolve '$rel' — not staged at '$TARGET/$rel', no usable 'recipe_source' in $TARGET/.gsd-recipe/config.json, and not found relative to this script's own location ($SELF_REPO_ROOT). Re-run install.sh from the recipe's source repo against this target, or set 'recipe_source' in .gsd-recipe/config.json by hand." >&2
  return 1
}

print_source() {
  local recipe_source
  if recipe_source="$(get_recipe_source)" && [ -n "$recipe_source" ]; then
    echo "$recipe_source"
    return 0
  fi
  # Unset recipe_source means either self-install (TARGET is already the
  # canonical source) or a config.json predating this mechanism — the
  # target itself is the best available answer in both cases.
  echo "$TARGET"
}

case "$CMD" in
  resolve) resolve "$REL_PATH" ;;
  source) print_source ;;
esac
