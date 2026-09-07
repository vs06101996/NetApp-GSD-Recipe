#!/usr/bin/env bash
# workspace-swap.sh — per-branch snapshot/restore of gitignored recipe files.
# Part of TASK-059 (OD-22): post-checkout hook swaps .planning/ + docs/PRD.md
# between branches so each branch carries its own independent planning context.
#
# Subcommands:
#   snapshot <branch> [--target <root>]  — save current working-tree state for branch
#   restore  <branch> [--target <root>]  — restore snapshot for branch (no-op if none)
#   archive  <branch> [--target <root>] [--preserve <path>]
#                                      — archive + clear active onboarding context
#   status          [--target <root>]    — list snapshots + current branch
#   sanitize <branch>                    — print sanitized dir name (no --target needed)
#   list            [--target <root>]    — print snapshot dir names
#
# RECIPE_WORKSPACE_SWAP=0  disables snapshot/restore (status always works).
set -euo pipefail

SUBCOMMAND="${1:-}"
shift || true

TARGET=""
BRANCH_ARG=""
CLEAR=0
PRESERVE=""
POSITIONAL=()

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --clear)  CLEAR=1; shift ;;
    --preserve) PRESERVE="$2"; shift 2 ;;
    -*) echo "workspace-swap.sh: unknown flag: $1" >&2; exit 2 ;;
    *) POSITIONAL+=("$1"); shift ;;
  esac
done

# ── helpers ──────────────────────────────────────────────────────────────────

resolve_target() {
  if [ -z "$TARGET" ]; then
    TARGET="$(git rev-parse --show-toplevel 2>/dev/null)" || {
      echo "workspace-swap.sh: not inside a git repo and no --target given" >&2
      exit 1
    }
  fi
  if [ ! -d "$TARGET/.git" ]; then
    echo "workspace-swap.sh: $TARGET is not a git repo root" >&2
    exit 1
  fi
}

sanitize_branch() {
  local b="$1"
  # Replace / with __ first, then replace remaining non-[a-zA-Z0-9._-] with -
  printf '%s' "$b" | sed 's|/|__|g; s|[^a-zA-Z0-9._-]|-|g'
}

workspaces_dir() {
  printf '%s' "$TARGET/.gsd-recipe/workspaces"
}

snapshot_dir() {
  local branch="$1"
  printf '%s/%s' "$(workspaces_dir)" "$(sanitize_branch "$branch")"
}

archive_dir() {
  local branch="$1" archive_id="$2"
  printf '%s/.gsd-recipe/workspace-archives/%s/%s' \
    "$TARGET" "$(sanitize_branch "$branch")" "$archive_id"
}

is_preserved() {
  local candidate="$1"
  [ -n "$PRESERVE" ] && [ "$candidate" = "$PRESERVE" ]
}

# ── subcommands ───────────────────────────────────────────────────────────────

cmd_sanitize() {
  [ "${#POSITIONAL[@]}" -ge 1 ] || { echo "workspace-swap.sh: sanitize requires <branch>" >&2; exit 2; }
  sanitize_branch "${POSITIONAL[0]}"
}

cmd_snapshot() {
  [ "${#POSITIONAL[@]}" -ge 1 ] || { echo "workspace-swap.sh: snapshot requires <branch>" >&2; exit 2; }
  local branch="${POSITIONAL[0]}"
  resolve_target

  if [ "${RECIPE_WORKSPACE_SWAP:-1}" = "0" ]; then
    echo "workspace-swap.sh: swap disabled (RECIPE_WORKSPACE_SWAP=0) — skipping snapshot for '$branch'"
    exit 0
  fi

  local has_planning=0 has_prd=0
  [ -d "$TARGET/.planning" ] && has_planning=1

  # Include docs/PRD.md only if it is untracked/gitignored (not committed)
  if [ -f "$TARGET/docs/PRD.md" ]; then
    if ! git -C "$TARGET" ls-files --error-unmatch "docs/PRD.md" >/dev/null 2>&1; then
      has_prd=1
    fi
  fi

  if [ "$has_planning" -eq 0 ] && [ "$has_prd" -eq 0 ]; then
    echo "workspace-swap.sh: nothing to snapshot for '$branch' (no .planning/ or untracked docs/PRD.md)"
    exit 0
  fi

  local sdir
  sdir="$(snapshot_dir "$branch")"
  local tmp_dir
  tmp_dir="${sdir}-tmp-$$"
  mkdir -p "$tmp_dir"

  # Copy .planning/
  if [ "$has_planning" -eq 1 ]; then
    cp -r "$TARGET/.planning" "$tmp_dir/.planning"
  fi

  # Copy docs/PRD.md
  if [ "$has_prd" -eq 1 ]; then
    mkdir -p "$tmp_dir/docs"
    cp "$TARGET/docs/PRD.md" "$tmp_dir/docs/PRD.md"
  fi

  # Copy untracked docs/PRD-*.md
  if [ -d "$TARGET/docs" ]; then
    while IFS= read -r rel_path; do
      local basename
      basename="$(basename "$rel_path")"
      case "$basename" in
        PRD-*.md)
          mkdir -p "$tmp_dir/docs"
          cp "$TARGET/$rel_path" "$tmp_dir/docs/$basename"
          ;;
      esac
    done < <(git -C "$TARGET" ls-files --others --exclude-standard -- "docs/" 2>/dev/null || true)
  fi

  # Record original branch name
  printf '%s\n' "$branch" > "$tmp_dir/.branch-name"

  # Atomic swap
  rm -rf "$sdir"
  mv "$tmp_dir" "$sdir"

  echo "workspace-swap.sh: snapshot saved for '$branch' → $(workspaces_dir)/$(sanitize_branch "$branch")"
}

cmd_restore() {
  [ "${#POSITIONAL[@]}" -ge 1 ] || { echo "workspace-swap.sh: restore requires <branch>" >&2; exit 2; }
  local branch="${POSITIONAL[0]}"
  resolve_target

  if [ "${RECIPE_WORKSPACE_SWAP:-1}" = "0" ]; then
    echo "workspace-swap.sh: swap disabled (RECIPE_WORKSPACE_SWAP=0) — skipping restore for '$branch'"
    exit 0
  fi

  local sdir
  sdir="$(snapshot_dir "$branch")"

  # --clear: unconditionally wipe working-tree recipe files before restoring.
  # The post-checkout hook always passes --clear so the old branch's planning
  # never leaks into a branch that has no snapshot yet (AC-2 fix).
  # Manual `recipe-workspace restore` does NOT pass --clear for safety.
  if [ "$CLEAR" -eq 1 ]; then
    rm -rf "$TARGET/.planning"
    # Remove untracked docs/PRD*.md (never touch committed files)
    if [ -d "$TARGET/docs" ]; then
      for prd in "$TARGET/docs/PRD.md" "$TARGET/docs"/PRD-*.md; do
        [ -f "$prd" ] || continue
        if ! git -C "$TARGET" ls-files --error-unmatch "docs/$(basename "$prd")" >/dev/null 2>&1; then
          rm -f "$prd"
        fi
      done
    fi
  fi

  if [ ! -d "$sdir" ]; then
    echo "workspace-swap.sh: no snapshot for '$branch' — working tree cleared"
    exit 0
  fi

  # Restore .planning/
  if [ -d "$sdir/.planning" ]; then
    rm -rf "$TARGET/.planning"
    cp -r "$sdir/.planning" "$TARGET/.planning"
  fi

  # Restore docs/PRD*.md
  if [ -d "$sdir/docs" ]; then
    mkdir -p "$TARGET/docs"
    for f in "$sdir/docs"/PRD.md "$sdir/docs"/PRD-*.md; do
      [ -f "$f" ] || continue
      cp "$f" "$TARGET/docs/$(basename "$f")"
    done
  fi

  echo "workspace-swap.sh: restored snapshot for '$branch' from $(workspaces_dir)/$(sanitize_branch "$branch")"
}

cmd_archive() {
  [ "${#POSITIONAL[@]}" -ge 1 ] || { echo "workspace-swap.sh: archive requires <branch>" >&2; exit 2; }
  local branch="${POSITIONAL[0]}"
  resolve_target

  if [ "${RECIPE_WORKSPACE_SWAP:-1}" = "0" ]; then
    echo "workspace-swap.sh: swap disabled (RECIPE_WORKSPACE_SWAP=0) — refusing to archive active onboarding context" >&2
    exit 1
  fi

  if [ -n "$PRESERVE" ] && [ "${PRESERVE#/}" = "$PRESERVE" ]; then
    PRESERVE="$TARGET/$PRESERVE"
  fi

  if [ -f "$TARGET/.gsd-recipe/config.json" ] &&
     ! python3 -m json.tool "$TARGET/.gsd-recipe/config.json" >/dev/null 2>&1; then
    echo "workspace-swap.sh: invalid .gsd-recipe/config.json — refusing to archive or clear" >&2
    exit 1
  fi

  local archive_id
  archive_id="${RECIPE_WORKSPACE_ARCHIVE_ID:-$(date -u +%Y%m%dT%H%M%SZ)-$$}"
  local adir tmp_dir
  adir="$(archive_dir "$branch" "$archive_id")"
  tmp_dir="${adir}-tmp-$$"
  mkdir -p "$tmp_dir"

  local found=0
  if [ -d "$TARGET/.planning" ]; then
    cp -r "$TARGET/.planning" "$tmp_dir/.planning"
    found=1
  fi

  if [ -d "$TARGET/docs" ]; then
    local prd rel
    for prd in "$TARGET/docs/PRD.md" "$TARGET/docs"/PRD-*.md; do
      [ -f "$prd" ] || continue
      is_preserved "$prd" && continue
      rel="docs/$(basename "$prd")"
      if ! git -C "$TARGET" ls-files --error-unmatch "$rel" >/dev/null 2>&1; then
        mkdir -p "$tmp_dir/docs"
        cp "$prd" "$tmp_dir/$rel"
        found=1
      fi
    done
  fi

  if [ -f "$TARGET/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ]; then
    mkdir -p "$tmp_dir/.gsd-recipe"
    cp "$TARGET/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" \
      "$tmp_dir/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
    found=1
  fi

  if [ -f "$TARGET/.gsd-recipe/config.json" ]; then
    if python3 - "$TARGET/.gsd-recipe/config.json" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
raise SystemExit(0 if (data.get("onboard") or {}).get("skip_tracker") is True else 1)
PY
    then
      mkdir -p "$tmp_dir/.gsd-recipe"
      printf '%s\n' '{"skip_tracker":true}' > "$tmp_dir/.gsd-recipe/onboard-state.json"
      found=1
    fi
  fi

  if [ "$found" -eq 0 ]; then
    rm -rf "$tmp_dir"
    echo "workspace-swap.sh: nothing to archive for '$branch'"
    exit 0
  fi

  printf '%s\n' "$branch" > "$tmp_dir/.branch-name"
  mkdir -p "$(dirname "$adir")"
  mv "$tmp_dir" "$adir"

  rm -rf "$TARGET/.planning"
  if [ -d "$TARGET/docs" ]; then
    local active_prd active_rel
    for active_prd in "$TARGET/docs/PRD.md" "$TARGET/docs"/PRD-*.md; do
      [ -f "$active_prd" ] || continue
      is_preserved "$active_prd" && continue
      active_rel="docs/$(basename "$active_prd")"
      if ! git -C "$TARGET" ls-files --error-unmatch "$active_rel" >/dev/null 2>&1; then
        rm -f "$active_prd"
      fi
    done
  fi
  rm -f "$TARGET/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"

  if [ -f "$TARGET/.gsd-recipe/config.json" ]; then
    python3 - "$TARGET/.gsd-recipe/config.json" <<'PY'
import json, os, sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    data = json.load(f)
onboard = data.get("onboard")
if isinstance(onboard, dict):
    onboard.pop("skip_tracker", None)
    if not onboard:
        data.pop("onboard", None)
tmp = f"{path}.tmp-{os.getpid()}"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, path)
PY
  fi

  echo "workspace-swap.sh: archived active onboarding context for '$branch' → $adir; working tree cleared"
}

cmd_status() {
  resolve_target

  local current
  current="$(git -C "$TARGET" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "(unknown)")"
  echo "current branch: $current"

  local wdir
  wdir="$(workspaces_dir)"
  if [ ! -d "$wdir" ] || [ -z "$(ls -A "$wdir" 2>/dev/null)" ]; then
    echo "snapshots: (none)"
    return 0
  fi

  echo "snapshots:"
  for sdir in "$wdir"/*/; do
    [ -d "$sdir" ] || continue
    local dname
    dname="$(basename "$sdir")"
    local display="$dname"
    if [ -f "$sdir/.branch-name" ]; then
      display="$(cat "$sdir/.branch-name") (dir: $dname)"
    fi
    local contents
    contents="$(ls -A "$sdir" 2>/dev/null | grep -v '^\.' | tr '\n' ' ' || true)"
    echo "  $display"
    [ -n "$contents" ] && echo "    contents: $contents" || true
  done
}

cmd_list() {
  resolve_target
  local wdir
  wdir="$(workspaces_dir)"
  [ -d "$wdir" ] || exit 0
  for sdir in "$wdir"/*/; do
    [ -d "$sdir" ] || continue
    basename "$sdir"
  done
}

# ── dispatch ──────────────────────────────────────────────────────────────────

case "$SUBCOMMAND" in
  snapshot) cmd_snapshot ;;
  restore)  cmd_restore  ;;
  archive)  cmd_archive  ;;
  status)   cmd_status   ;;
  sanitize) cmd_sanitize ;;
  list)     cmd_list     ;;
  "")
    echo "workspace-swap.sh: subcommand required (snapshot|restore|archive|status|sanitize|list)" >&2
    exit 2
    ;;
  *)
    echo "workspace-swap.sh: unknown subcommand: $SUBCOMMAND" >&2
    exit 2
    ;;
esac
