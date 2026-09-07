#!/usr/bin/env bash
# Cursor postToolUse/Bash fallback for workspace swap (TASK-059 / OD-22).
# Detects branch changes that bypassed the git post-checkout hook (e.g. Cursor
# UI branch picker via libgit2). Fires after every Bash tool call; is a no-op
# unless the branch actually changed since the last call.
[ "${RECIPE_WORKSPACE_SWAP:-1}" != "0" ] || exit 0

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
LIB="$ROOT/.gsd-recipe/lib/workspace-swap.sh"
[ -f "$LIB" ] || exit 0

SENTINEL="$ROOT/.gsd-recipe/.last-branch"
CURRENT="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[ -n "$CURRENT" ] || exit 0

OLD="$(cat "$SENTINEL" 2>/dev/null || true)"
printf '%s\n' "$CURRENT" > "$SENTINEL"

if [ -n "$OLD" ] && [ "$OLD" != "$CURRENT" ]; then
  bash "$LIB" snapshot "$OLD"     --target "$ROOT"
  bash "$LIB" restore  "$CURRENT" --target "$ROOT"
fi
exit 0
