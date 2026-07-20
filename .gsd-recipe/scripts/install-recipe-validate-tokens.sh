#!/usr/bin/env bash
# recipe-validate-tokens installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 1's "Token validation [X]" and Step 5 checklist
# item 4 ("Token still valid — Re-run step 1 probes"), formalized into its
# own re-invokable Cursor skill (TASK-021). Same standalone-installer shape
# as install-recipe-run-phase.sh / install-recipe-plan-phase.sh, independent
# of the full TASK-010 install.sh (intended to also be composed into it as a
# sixth sub-installer — see the copy-paste snippet in this task's integration
# report; not wired in by this script itself, to avoid a concurrent edit
# collision with sibling in-flight tasks on install.sh).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as recipe-run-phase/recipe-plan-phase/recipe-prd-intake, NOT the
# plain top-level skills/ path recipe-planning-policy uses for GSD's own
# agent_skills injection mechanism).
#
# Also ships this script's own --check-github mode: a real, standalone,
# testable GitHub credential/scope probe (gh auth status + gh api user,
# warn-only) that mirrors install.sh's github_check() function. It is a
# mirror, not a `source`, of that function deliberately — install.sh's own
# case-statement dispatch at the bottom of the file runs unconditionally as
# soon as it's loaded (defaulting to MODE="install"), so it has no safe
# sourceable entry point without either editing install.sh (out of scope for
# this task per the shared-file-avoidance constraint) or triggering a live
# install as a side effect of merely wanting one function from it.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-validate-tokens.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-validate-tokens.sh --uninstall [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-validate-tokens.sh --check-github
#
# Design (mirrors install-recipe-run-phase.sh's structure/functions for
# install/uninstall; --check-github is net-new for this skill):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed on install/uninstall: never partially stage; never
#     overwrite operator data; refuses a non-git --target.
#   - --check-github needs no git repo / --target at all — it's a pure,
#     read-only local credential probe, unrelated to any scaffolding.
#     Never fails closed: a missing/unauthenticated gh is reported as
#     FAIL/WARN, but the script itself always exits 0 (this is a reporting
#     tool, not a gate — the invoking skill/operator decides what to do with
#     the result, per docs/netapp-recipe/lld/INSTALL-LLD.md's own Gate A
#     warn-only precedent).
#   - Never prints token values. gh auth status's own masked "Token: gho_..."
#     line is never even read into the summary — only the "Logged in to..."
#     (username) and "Token scopes:" lines are extracted.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-validate-tokens" for clean removal.
#   - Never touches .gsd-recipe/config.json or .planning/config.json — this
#     installer's only job is staging one file (and --check-github never
#     writes anything at all, anywhere).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install"
YES=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --check-github) MODE="check-github"; shift ;;
    --yes|-y) YES=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

check_github() {
  # Mirrors install.sh's github_check() (real gh auth status + gh api user,
  # warn-only), extended to surface OAuth scopes when determinable and to
  # never surface gh auth status's own raw "Token:" line. Always returns 0 —
  # this function reports, it never fails the caller closed.
  if ! command -v gh >/dev/null 2>&1; then
    echo "GitHub: FAIL (gh CLI not found on PATH)"
    echo "  Remediation: install the gh CLI (e.g. 'brew install gh'), then run 'gh auth login'."
    return 0
  fi

  local auth_output auth_rc
  auth_output="$(gh auth status 2>&1)" && auth_rc=0 || auth_rc=$?
  if [ "$auth_rc" -ne 0 ]; then
    echo "GitHub: WARN (gh CLI found but not authenticated)"
    echo "  Remediation: run 'gh auth login'."
    return 0
  fi

  if ! gh api user >/dev/null 2>&1; then
    echo "GitHub: WARN (gh reports logged in, but the API probe 'gh api user' failed)"
    echo "  Remediation: run 'gh auth login' again, or check your network/token."
    return 0
  fi

  local logged_in_line scopes_line
  logged_in_line="$(printf '%s\n' "$auth_output" | grep -i 'Logged in to' | head -n1 | sed -E 's/^[[:space:]]*[^A-Za-z]*//')"
  scopes_line="$(printf '%s\n' "$auth_output" | grep -i 'Token scopes' | head -n1 | sed -E 's/^[[:space:]]*[^A-Za-z]*//')"

  echo "GitHub: PASS (gh CLI authenticated, API probe succeeded)"
  if [ -n "$logged_in_line" ]; then
    echo "  ${logged_in_line}"
  fi
  if [ -n "$scopes_line" ]; then
    echo "  ${scopes_line}"
  else
    echo "  Token scopes: (not determinable from 'gh auth status' output)"
  fi
}

if [ "$MODE" = "check-github" ]; then
  check_github
  exit 0
fi

if [ -z "$TARGET" ]; then
  TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-validate-tokens installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-validate-tokens/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-validate-tokens-SKILL.md"
# This script's own --check-github mode is a single self-contained file with
# no dependency on the rest of bench/ — same category as
# install-recipe-pr-comment.sh's post-github-pr-comment.sh /
# install-recipe-create-epic.sh's draft-jira-epic.sh self-staging precedent
# — so it is staged directly onto the target, not resolved cross-repo via
# recipe-paths.sh (that mechanism is for shared bench/lib/*.sh and
# bench/runners/*.sh files used by many skills, where duplicating into every
# target would mean drifting copies; see bench/lib/recipe-paths.sh's own
# header comment for that side of the story).
SCRIPT_SRC="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
SCRIPT_DEST="$GSD_RECIPE_DIR/scripts/install-recipe-validate-tokens.sh"
COMPONENT="recipe-validate-tokens"

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
    read -r -p "Install recipe-validate-tokens skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-validate-tokens installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-validate-tokens/SKILL.md"

  safe_copy "$SCRIPT_SRC" "$SCRIPT_DEST"
  chmod +x "$SCRIPT_DEST" 2>/dev/null || true
  ledger_record ".gsd-recipe/scripts/install-recipe-validate-tokens.sh"

  echo "recipe-validate-tokens installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-validate-tokens' by name to check GitHub (real, scriptable"
  echo "'gh auth status'/'gh api user' probe) and Jira/Atlassian MCP (agent-mediated"
  echo "probe, since a bash script has no MCP tool-calling access) credentials, and"
  echo "report a PASS/WARN/FAIL summary with soft remediation suggestions — never"
  echo "fixes anything itself, never prints token values."
  echo "Run the GitHub half standalone any time: $0 --check-github"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-validate-tokens installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local canonical_src=""
    case "$rel" in
      .cursor/skills/recipe-validate-tokens/SKILL.md) canonical_src="$SKILL_SRC" ;;
      .gsd-recipe/scripts/install-recipe-validate-tokens.sh) canonical_src="$SCRIPT_SRC" ;;
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
  rmdir "$TARGET/.cursor/skills/recipe-validate-tokens" 2>/dev/null || true

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
  echo "recipe-validate-tokens installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
