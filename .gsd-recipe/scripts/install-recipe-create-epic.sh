#!/usr/bin/env bash
# recipe-create-epic installer (TASK-033) — stages the invoke-by-name skill
# described in .gsd-recipe/templates/recipe-create-epic-SKILL.md, plus its
# runtime dependency bench/runners/draft-jira-epic.sh (the real
# PRD-to-{summary,description} draft script the staged skill's own
# instructions shell out to). Standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern, mirroring
# install-recipe-pr-comment.sh's two-file-staging structure/functions
# exactly (same "no single canonical staged_path" shape, since this
# component also stages more than one file under one ledger component),
# independent of the full TASK-010 install.sh (though also intended to be
# composed into it — see the integration report's copy-paste-ready
# install.sh snippet; that edit is NOT applied by this script or by this
# task, per the parallel-work shared-file constraint it was built under).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-create-epic.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-create-epic.sh --verify [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-create-epic.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-pr-comment.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: both staged files are recorded in
#     .gsd-recipe/ledger.json under component "recipe-create-epic" for clean
#     removal.
#   - Never touches .gsd-recipe/config.json, .planning/STATE.md, or
#     .planning/config.json — those are the staged skill's own runtime
#     concern (via parse-state.sh init-tracker / createJiraIssue) whenever
#     it's actually invoked, not this installer's job. This installer's
#     only job is staging two files.
#   - --verify (additive to install-recipe-pr-comment.sh's own shape, per
#     this task's own validation checklist): a light, read-only check that
#     both staged files exist at their ledgered paths and the ledger
#     component is present -- never writes anything, never required for a
#     successful install/uninstall cycle on its own.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install"
YES=0
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --verify) MODE="verify"; shift ;;
    --yes|-y) YES=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-create-epic installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-create-epic/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-create-epic-SKILL.md"
RUNNER_DEST="$TARGET/bench/runners/draft-jira-epic.sh"
RUNNER_SRC="$SCRIPT_DIR/../../bench/runners/draft-jira-epic.sh"
COMPONENT="recipe-create-epic"

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

ledger_has_component() {
  ledger_init
  python3 - "$LEDGER" "$COMPONENT" <<'PY'
import json, sys
ledger_path, component = sys.argv[1], sys.argv[2]
with open(ledger_path) as f:
    data = json.load(f)
sys.exit(0 if data.get(component) else 1)
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
    read -r -p "Install recipe-create-epic skill + draft-jira-epic.sh runner (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-create-epic installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-create-epic/SKILL.md"

  safe_copy "$RUNNER_SRC" "$RUNNER_DEST"
  chmod +x "$RUNNER_DEST" 2>/dev/null || true
  ledger_record "bench/runners/draft-jira-epic.sh"

  echo "recipe-create-epic installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-create-epic [--project KEY] [--issue-type NAME] [--force]'"
  echo "by name to draft (draft-jira-epic.sh) + confirm + create (createJiraIssue"
  echo "via the Atlassian MCP) a Jira Epic from docs/PRD.md, then link it into"
  echo ".planning/STATE.md's '## Tracker' section (parse-state.sh init-tracker)"
  echo "and sync intake_started via the gsd-jira-sync skill."
  echo "Verify staged files: $0 --verify --target $TARGET"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

verify() {
  local ok=1

  echo "recipe-create-epic installer --verify: checking staged files for component '$COMPONENT'"

  if ledger_has_component; then
    echo "  [pass] ledger component '$COMPONENT' present in $LEDGER"
  else
    echo "  [FAIL] ledger component '$COMPONENT' absent from $LEDGER"
    ok=0
  fi

  if [ -f "$SKILL_DEST" ]; then
    echo "  [pass] $SKILL_DEST exists"
  else
    echo "  [FAIL] $SKILL_DEST missing"
    ok=0
  fi

  if [ -f "$RUNNER_DEST" ]; then
    echo "  [pass] $RUNNER_DEST exists"
  else
    echo "  [FAIL] $RUNNER_DEST missing"
    ok=0
  fi

  if [ -x "$RUNNER_DEST" ]; then
    echo "  [pass] $RUNNER_DEST is executable"
  else
    echo "  [FAIL] $RUNNER_DEST is not executable"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    echo "recipe-create-epic installer --verify: OK"
    return 0
  else
    echo "recipe-create-epic installer --verify: one or more checks failed"
    return 1
  fi
}

uninstall() {
  echo "recipe-create-epic installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    local canonical_src=""
    case "$rel" in
      .cursor/skills/recipe-create-epic/SKILL.md) canonical_src="$SKILL_SRC" ;;
      bench/runners/draft-jira-epic.sh) canonical_src="$RUNNER_SRC" ;;
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
  rmdir "$TARGET/.cursor/skills/recipe-create-epic" 2>/dev/null || true

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
  echo "recipe-create-epic installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  verify) verify ;;
  uninstall) uninstall ;;
esac
