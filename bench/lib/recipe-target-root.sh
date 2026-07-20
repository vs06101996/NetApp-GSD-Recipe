#!/usr/bin/env bash
# recipe-target-root.sh — resolve the target git repo root for recipe runners.
#
# Resolution order:
#   1. Explicit path argument (e.g. from --target)
#   2. $RECIPE_TARGET environment variable
#   3. git rev-parse --show-toplevel from cwd
#   4. cwd when cwd/.git exists
#
# Usage (source this file):
#   . "$(recipe-paths.sh resolve bench/lib/recipe-target-root.sh --target "$TARGET")"
#   root="$(recipe_target_root "$maybe_explicit")"
recipe_target_root() {
  local explicit="${1:-}"

  if [ -n "$explicit" ]; then
    printf '%s\n' "$explicit"
    return 0
  fi

  if [ -n "${RECIPE_TARGET:-}" ]; then
    printf '%s\n' "$RECIPE_TARGET"
    return 0
  fi

  local root
  root="$(git -C "$(pwd)" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$root" ] && [ -d "$root/.git" ]; then
    printf '%s\n' "$root"
    return 0
  fi

  if [ -d "$(pwd)/.git" ]; then
    pwd
    return 0
  fi

  return 1
}
