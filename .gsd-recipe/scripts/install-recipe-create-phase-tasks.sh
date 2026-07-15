#!/usr/bin/env bash
# recipe-create-phase-tasks installer — standalone fallback path per
# lld/INSTALL-LLD.md Step 3's documented pattern (same approach already used
# by install-recipe-run-phase.sh / install-recipe-plan-phase.sh), independent
# of the full TASK-010 install.sh (though also intended to be composed into
# it in a follow-up integration pass — see the integration report for the
# exact install.sh wiring snippet, held back from this task's own diff to
# avoid a merge conflict with sibling tasks editing install.sh concurrently).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as recipe-run-phase/recipe-plan-phase, NOT the plain top-level
# skills/ path recipe-planning-policy's agent_skills injection uses). No new
# runner script is staged here — bench/runners/create-phase-tasks.sh already
# lives in place (extended in-place with a new `list` subcommand by this
# same task, not copied/staged by this installer).
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh --verify [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-create-phase-tasks.sh --uninstall [--target <repo_root>]
#
# Design (mirrors install-recipe-run-phase.sh's structure/functions):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs).
#   - Fail closed: never partially stage; never overwrite operator data.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-create-phase-tasks" for clean removal.
#   - Never touches .gsd-recipe/config.json, .planning/config.json, or
#     .gsd-recipe/phase-tasks-queue.jsonl — this installer's only job is
#     staging one file.
#   - --verify (additive to install-recipe-run-phase.sh's own shape, same
#     precedent install-recipe-create-epic.sh (TASK-033) already set): a
#     light, read-only check that the staged file exists at its ledgered
#     path and the ledger component is present -- never writes anything,
#     never required for a successful install/uninstall cycle on its own.
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
  echo "recipe-create-phase-tasks installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-create-phase-tasks/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-create-phase-tasks-SKILL.md"
COMPONENT="recipe-create-phase-tasks"

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
  # $1 = absolute path being considered for removal. Returns 0 (skip removal)
  # if it resolves to our own template source — true whenever TARGET is this
  # implementation repo itself (self-install case).
  local candidate="$1"
  [ -e "$candidate" ] || return 1
  [ -e "$SKILL_SRC" ] || return 1
  [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$SKILL_SRC")" && pwd)/$(basename "$SKILL_SRC")" ]
}

install() {
  if [ "$YES" -ne 1 ]; then
    read -r -p "Install recipe-create-phase-tasks skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-create-phase-tasks installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-create-phase-tasks/SKILL.md"

  echo "recipe-create-phase-tasks installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-create-phase-tasks' by name to close TASK-007's"
  echo "detect+draft+queue-only gap: runs create-phase-tasks.sh detect then"
  echo "list (self-healing anything already linked out-of-band), resolves one"
  echo "Jira issue type for the whole batch, shows a soft confirm gate, then"
  echo "creates+links a Jira issue per pending phase task via createJiraIssue"
  echo "+ createIssueLink/parent field, recording each outcome via"
  echo "mark-done/mark-failed."
  echo "Verify staged files: $0 --verify --target $TARGET"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

verify() {
  local ok=1

  echo "recipe-create-phase-tasks installer --verify: checking staged files for component '$COMPONENT'"

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

  if [ "$ok" -eq 1 ]; then
    echo "recipe-create-phase-tasks installer --verify: OK"
    return 0
  else
    echo "recipe-create-phase-tasks installer --verify: one or more checks failed"
    return 1
  fi
}

uninstall() {
  echo "recipe-create-phase-tasks installer: removing tracked files for component '$COMPONENT'..."
  while IFS= read -r rel; do
    if is_canonical_source "$TARGET/$rel"; then
      echo "  keeping $rel (this is the canonical skill template source, not an installed copy — self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

  # Clean up now-empty directories left behind (rmdir is a silent no-op if not empty).
  rmdir "$TARGET/.cursor/skills/recipe-create-phase-tasks" 2>/dev/null || true

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
  echo "recipe-create-phase-tasks installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  verify) verify ;;
  uninstall) uninstall ;;
esac
