#!/usr/bin/env bash
# initiative-branch.sh — create a clean branch boundary for fresh onboarding.
# TASK-061 / OD-23. The workspace runtime snapshots the current initiative,
# creates the requested branch, and clears/restores initiative-local state.
#
# Usage:
#   initiative-branch.sh create <branch> [--target <repo_root>] [--base <ref>]
#   initiative-branch.sh validate <branch> [--target <repo_root>] [--base <ref>]
set -euo pipefail

SUBCOMMAND="${1:-}"
shift || true

TARGET=""
BASE=""
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    -*) echo "initiative-branch.sh: unknown flag: $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

resolve_target() {
  if [ -z "$TARGET" ]; then
    TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || {
      echo "initiative-branch.sh: not inside a git repo and no --target given" >&2
      exit 1
    }
  fi
  if [ ! -d "$TARGET/.git" ]; then
    echo "initiative-branch.sh: $TARGET is not a git repo root" >&2
    exit 1
  fi
}

validate_branch() {
  local branch="$1"
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
    echo "initiative-branch.sh: branch name is required" >&2
    return 1
  fi
  if ! git -C "$TARGET" check-ref-format --branch "$branch" >/dev/null 2>&1; then
    echo "initiative-branch.sh: invalid branch name '$branch'" >&2
    return 1
  fi
  if git -C "$TARGET" show-ref --verify --quiet "refs/heads/$branch" ||
     git -C "$TARGET" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    echo "initiative-branch.sh: branch '$branch' already exists; choose a new initiative branch" >&2
    return 1
  fi
}

resolve_base_ref() {
  local current="$1"

  # An explicit base wins over every default. Repos whose integration branch
  # is not origin/HEAD (e.g. a 'dev' trunk) would otherwise silently branch
  # off main and drop the integration-only commits.
  if [ -n "$BASE" ]; then
    if ! git -C "$TARGET" rev-parse --verify --quiet "$BASE^{commit}" >/dev/null; then
      echo "initiative-branch.sh: base ref '$BASE' does not resolve to a commit" >&2
      return 1
    fi
    printf '%s\n' "$BASE"
    return 0
  fi

  case "$current" in
    main|master)
      printf '%s\n' "$current"
      return 0
      ;;
  esac

  local remote_head
  remote_head="$(git -C "$TARGET" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$remote_head" ] && git -C "$TARGET" rev-parse --verify --quiet "$remote_head^{commit}" >/dev/null; then
    printf '%s\n' "$remote_head"
    return 0
  fi

  local candidate
  for candidate in main master; do
    if git -C "$TARGET" rev-parse --verify --quiet "refs/heads/$candidate^{commit}" >/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  echo "initiative-branch.sh: cannot determine a base branch (origin/HEAD, main, or master)" >&2
  return 1
}

# Branches that conventionally carry integration history rather than a single
# initiative. Used only to pick which base to recommend, never to decide.
looks_like_integration_branch() {
  case "$1" in
    dev|develop|development|trunk|integration|staging) return 0 ;;
    *) return 1 ;;
  esac
}

# The default base is origin/HEAD, which is wrong for repos that integrate on a
# non-default branch. Rather than guess, report the fork so the caller's gate can
# ask. Silent when the operator already passed --base or when the current branch
# adds nothing over the default base.
emit_base_note() {
  local current="$1" base="$2"
  [ -z "$BASE" ] || return 0
  [ "$current" != "$base" ] || return 0

  local ahead
  ahead="$(git -C "$TARGET" rev-list --count "$base..$current" 2>/dev/null || printf '0')"
  [ "$ahead" -gt 0 ] 2>/dev/null || return 0

  local recommend detail
  if looks_like_integration_branch "$current"; then
    recommend="$current"
    detail="'$current' looks like an integration branch; basing on '$base' would drop $ahead commit(s) it already carries"
  else
    recommend="$base"
    detail="'$current' looks like a prior initiative branch; basing on it would inherit its $ahead commit(s) into the next PR"
  fi

  printf "initiative-branch.sh: base-ambiguous current='%s' default='%s' ahead=%s recommend='%s'\n" \
    "$current" "$base" "$ahead" "$recommend"
  printf "initiative-branch.sh: %s. Ask the operator, then pass --base <ref>.\n" "$detail"
}

preflight() {
  local branch="$1"
  resolve_target
  validate_branch "$branch" || return 1

  local current
  current="$(git -C "$TARGET" symbolic-ref --quiet --short HEAD 2>/dev/null)" || {
    echo "initiative-branch.sh: detached HEAD is not supported for onboarding" >&2
    exit 1
  }

  local dirty_product_state="" status_line path
  while IFS= read -r status_line; do
    [ -n "$status_line" ] || continue
    path="${status_line:3}"
    if [[ "$status_line" == "?? docs/PRD.md" ||
          "$status_line" == "?? docs/PRD-"*.md ||
          "$status_line" == "?? .gsd/"* ]]; then
      continue
    fi
    # Recipe install always appends ignore lines and stages Cursor
    # hooks/rules. Those are not product work; do not block onboard.
    case "$path" in
      .gitignore|.cursor/hooks.json|.cursor/hooks/workspace-swap-cursor-fallback.sh|.cursor/hooks/fotw-observer-nudge.sh|.cursor/rules/recipe-*)
        continue
        ;;
    esac
    dirty_product_state="${dirty_product_state}${dirty_product_state:+$'\n'}${status_line}"
  done < <(git -C "$TARGET" status --porcelain --untracked-files=all)

  if [ -n "$dirty_product_state" ]; then
    echo "initiative-branch.sh: tracked/untracked product changes are present; commit or stash them before fresh onboarding" >&2
    printf '%s\n' "$dirty_product_state" | sed 's/^/  - /' >&2
    exit 1
  fi

  local tracked_initiative_state
  tracked_initiative_state="$(
    git -C "$TARGET" ls-files -- \
      ".planning/" \
      ".gsd/" \
      "docs/PRD.md" \
      "docs/PRD-*.md" \
      ".gsd-recipe/phase-tasks-queue.jsonl" \
      ".gsd-recipe/sync-ledger.jsonl" \
      ".gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
  )"
  if [ -n "$tracked_initiative_state" ]; then
    echo "initiative-branch.sh: initiative-local files are tracked by git; branch isolation only manages gitignored state:" >&2
    printf '%s\n' "$tracked_initiative_state" | sed 's/^/  - /' >&2
    exit 1
  fi

  local workspace_lib="$TARGET/.gsd-recipe/lib/workspace-swap.sh"
  if [ ! -x "$workspace_lib" ]; then
    echo "initiative-branch.sh: workspace runtime missing or not executable: $workspace_lib" >&2
    exit 1
  fi

  printf '%s\n' "$current"
}

cmd_validate() {
  [ "${#POSITIONAL[@]}" -eq 1 ] || {
    echo "initiative-branch.sh: validate requires exactly one branch" >&2
    exit 2
  }
  local current base
  if ! current="$(preflight "${POSITIONAL[0]}")"; then
    exit 1
  fi
  if ! base="$(resolve_base_ref "$current")"; then
    exit 1
  fi
  echo "initiative-branch.sh: ready to create '${POSITIONAL[0]}' from '$base'"
  emit_base_note "$current" "$base"
}

cmd_create() {
  [ "${#POSITIONAL[@]}" -eq 1 ] || {
    echo "initiative-branch.sh: create requires exactly one branch" >&2
    exit 2
  }

  local branch="${POSITIONAL[0]}"
  local current base workspace_lib
  if ! current="$(preflight "$branch")"; then
    exit 1
  fi
  if ! base="$(resolve_base_ref "$current")"; then
    exit 1
  fi
  workspace_lib="$TARGET/.gsd-recipe/lib/workspace-swap.sh"
  emit_base_note "$current" "$base" >&2

  # Disable the installed post-checkout hook for this switch because this
  # helper performs the same sequence explicitly and can roll it back.
  bash "$workspace_lib" snapshot "$current" --target "$TARGET"
  if ! RECIPE_WORKSPACE_SWAP=0 git -C "$TARGET" switch -q -c "$branch" "$base"; then
    echo "initiative-branch.sh: failed to create '$branch'; current initiative remains on '$current'" >&2
    exit 1
  fi

  if ! bash "$workspace_lib" restore "$branch" --target "$TARGET" --clear; then
    echo "initiative-branch.sh: failed to initialize '$branch'; rolling back to '$current'" >&2
    RECIPE_WORKSPACE_SWAP=0 git -C "$TARGET" switch -q "$current" || true
    bash "$workspace_lib" restore "$current" --target "$TARGET" --clear || true
    git -C "$TARGET" branch -D "$branch" >/dev/null 2>&1 || true
    exit 1
  fi

  echo "initiative-branch.sh: created clean initiative branch '$branch' from '$base' (previous initiative: '$current')"
}

case "$SUBCOMMAND" in
  create) cmd_create ;;
  validate) cmd_validate ;;
  "")
    echo "initiative-branch.sh: subcommand required (create|validate)" >&2
    exit 2
    ;;
  *)
    echo "initiative-branch.sh: unknown subcommand: $SUBCOMMAND" >&2
    exit 2
    ;;
esac
