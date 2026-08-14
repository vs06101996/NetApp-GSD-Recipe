#!/usr/bin/env bash
# install.sh — TASK-010 umbrella scaffold (fallback installer) per
# lld/INSTALL-LLD.md Step 2's "Fallback path [X]". Composes the already-built
# install-observer.sh / install-tracker-sync.sh / install-recipe-planning-policy.sh
# installers rather than reimplementing them, scaffolds the recipe's
# directory tree, and provides a local verification checklist.
#
# Scope is narrowed per the confirmed decisions in
# bench/report/install-scaffold-integration-report.md (mirrored here):
#   - GitHub check: real (`gh auth status` / `gh api user`), warn-only — a
#     missing/unauthenticated `gh` never fails the install closed.
#   - Jira check: architecturally can't be scripted (only an agent turn can
#     call the Atlassian MCP). Recorded "pending" here; the invoking agent
#     runs the real check and calls `--record-jira-check <pass|fail>`.
#   - MCP `mcpServers` fragment and `.planning/config.json`'s `agent_skills`
#     injection: print-only. Never auto-edits shared Cursor/GSD config.
#   - Target-repo scaffold is local-only: install() adds .gsd-recipe/,
#     .knowledge/, .templates/, .planning/, code_base_details/, skills/, and
#     recipe-owned docs to the target's .gitignore (see INSTALL-LLD).
#     Self-install into this source repo skips ignoring .gsd-recipe/ so the
#     canonical recipe tree stays visible to git.
#
# Prerequisite bootstrap (see bench/report/install-scaffold-integration-report.md
# "Prerequisite bootstrap" section for the full design):
#   - preflight() runs at the very start of install(), before any scaffolding.
#     python3/git are hard prerequisites (install.sh itself shells out to
#     both) — unresolved after the check->auto-fix->reverify->prompt flow
#     below aborts with exit 1. node/gh/gsd_core/graphify are soft —
#     warn-only, recorded in install-report.json's "prereqs" object, install
#     proceeds.
#   - GSD presence is detected via the Cursor-facing signal file at
#     $GSD_SIGNAL_PATH (defaults to ~/.cursor/skills/gsd-help/SKILL.md,
#     overridable via the GSD_SIGNAL_PATH env var — tests must always
#     override this to a scratch path, never the real one).
#   - graphify is a soft/optional prerequisite (standalone CLI, checked via
#     `command -v graphify`; GSD's own wrapper additionally probes
#     `graphify --help`, not `--version`, which graphify doesn't support).
#     Auto-fix only ever attempted when `uv` is already present, via
#     install-graphify.sh (sudo-free, user-owned cache dirs, `uv tool install`
#     — never `uv pip install`, which fails on PEP-668 Homebrew Python and
#     root-owned ~/.cache). Uniquely for
#     this one prerequisite, whenever graphify ends up present (pre-existing
#     or freshly auto-installed), graphify_config_enable() auto-sets
#     graphify.enabled=true in the *target project's* GSD-native
#     $TARGET/.planning/config.json — a deliberate, narrow exception to the
#     "never auto-edit .planning/config.json" policy below, routed
#     exclusively through GSD's own schema-aware `gsd-tools config-set`
#     (never a hand-rolled JSON merge). Resolution order: `gsd-tools` on
#     PATH, else `node $GSD_TOOLS_CJS_PATH` (overridable env var, same
#     override precedent as GSD_SIGNAL_PATH — tests must always override
#     this to a scratch stub), else a print-only manual-instructions
#     fallback. Try/warn-only: never fails install.sh closed, and never
#     creates .planning/config.json itself.
#
# Usage:
#   ./.gsd-recipe/scripts/install.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install.sh --verify [--target <repo_root>]
#   ./.gsd-recipe/scripts/install.sh --record-jira-check <pass|fail> [--target <repo_root>]
#   ./.gsd-recipe/scripts/install.sh --uninstall [--target <repo_root>]
#
# Design:
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs). Sub-installers are
#     invoked with --yes too — the umbrella prompt already covers consent,
#     a second nested prompt would just be noise.
#   - Fail closed on git-repo check and on the hard python3/git
#     prerequisites; warn-only (never fail closed) on the GitHub/node/gsd
#     checks, per the LLD's own Gate A warn-only precedent.
#   - Never overwrite operator data: existing templates, an existing
#     code_base_details/README.md, existing .knowledge/ files, and
#     config.json/.gitignore (shared files this script only ever adds
#     missing keys/lines to, never rewrites wholesale) are all left alone
#     if already present.
#   - Ledger-tracked: every file this script *directly* creates is recorded
#     in .gsd-recipe/ledger.json under component "install-core" — separate
#     from "fotw-observer"/"tracker-sync"/"recipe-prd-intake"/
#     "recipe-planning-policy"/"recipe-run-phase"/"recipe-plan-phase"/
#     "recipe-validate-tokens"/"recipe-bootstrap-knowledge"/
#     "recipe-install-verify"/"recipe-run-phases"/"recipe-verify-feature"/
#     "recipe-review-ship"/"recipe-settle"/"gsd-jira-sync"/"recipe-sync"/
#     "recipe-pr-comment"/"recipe-install"/"recipe-observe"/
#     "recipe-create-epic"/"recipe-create-phase-tasks"/"recipe-help"/
#     "recipe-new-project"/"recipe-onboard", which the sub-installers/skills track under their
#     own component names.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install"
YES=0
TARGET=""
JIRA_CHECK_VALUE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --verify) MODE="verify"; shift ;;
    --record-jira-check)
      MODE="record-jira-check"
      JIRA_CHECK_VALUE="${2:?--record-jira-check requires 'pass' or 'fail'}"
      shift 2
      ;;
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
  echo "install.sh: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

# SELF_ROOT is the recipe's own source tree (where this install.sh lives) —
# used to detect whether TARGET is an external repo (write recipe_source
# into its config.json) or a self-install (TARGET is SELF_ROOT itself, no
# recipe_source needed). See bench/lib/recipe-paths.sh's own header comment
# for the full "why" — this is the permanent fix for any recipe-*
# skill/installer that needs to locate harness code (a
# .gsd-recipe/scripts/*, bench/runners/*, or bench/lib/* file) at runtime on
# a target that doesn't have the whole harness duplicated into it.
SELF_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
RECIPE_PATHS_SRC="$SELF_ROOT/bench/lib/recipe-paths.sh"

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
CONFIG="$GSD_RECIPE_DIR/config.json"
INSTALL_REPORT="$GSD_RECIPE_DIR/install-report.json"
INSTALL_VERIFIED="$GSD_RECIPE_DIR/INSTALL-VERIFIED.json"
GITIGNORE="$TARGET/.gitignore"

TEMPLATES_SRC_DIR="$SCRIPT_DIR/../templates"
TEMPLATES_DEST_DIR="$TARGET/.templates"
JIRA_COMMENT_SRC="$SCRIPT_DIR/../../bench/recipe/templates/jira-comments/_comment.template.md"
GITHUB_PR_COMMENT_SRC="$SCRIPT_DIR/../../bench/recipe/templates/github-pr-comments/_comment.template.md"

KNOWLEDGE_DIR="$TARGET/.knowledge"
CODE_BASE_DETAILS_README="$TARGET/code_base_details/README.md"

OBSERVER_INSTALLER="$SCRIPT_DIR/install-observer.sh"
TRACKER_SYNC_INSTALLER="$SCRIPT_DIR/install-tracker-sync.sh"
RECIPE_PLANNING_POLICY_INSTALLER="$SCRIPT_DIR/install-recipe-planning-policy.sh"
RECIPE_RUN_PHASE_INSTALLER="$SCRIPT_DIR/install-recipe-run-phase.sh"
RECIPE_PLAN_PHASE_INSTALLER="$SCRIPT_DIR/install-recipe-plan-phase.sh"
RECIPE_VALIDATE_TOKENS_INSTALLER="$SCRIPT_DIR/install-recipe-validate-tokens.sh"
RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER="$SCRIPT_DIR/install-recipe-bootstrap-knowledge.sh"
RECIPE_INSTALL_VERIFY_INSTALLER="$SCRIPT_DIR/install-recipe-install-verify.sh"
RECIPE_RUN_PHASES_INSTALLER="$SCRIPT_DIR/install-recipe-run-phases.sh"
RECIPE_VERIFY_FEATURE_INSTALLER="$SCRIPT_DIR/install-recipe-verify-feature.sh"
RECIPE_REVIEW_SHIP_INSTALLER="$SCRIPT_DIR/install-recipe-review-ship.sh"
RECIPE_SETTLE_INSTALLER="$SCRIPT_DIR/install-recipe-settle.sh"
GSD_JIRA_SYNC_INSTALLER="$SCRIPT_DIR/install-gsd-jira-sync.sh"
RECIPE_SYNC_INSTALLER="$SCRIPT_DIR/install-recipe-sync.sh"
RECIPE_PR_COMMENT_INSTALLER="$SCRIPT_DIR/install-recipe-pr-comment.sh"
RECIPE_INSTALL_INSTALLER="$SCRIPT_DIR/install-recipe-install.sh"
RECIPE_OBSERVE_INSTALLER="$SCRIPT_DIR/install-recipe-observe.sh"
RECIPE_CREATE_EPIC_INSTALLER="$SCRIPT_DIR/install-recipe-create-epic.sh"
RECIPE_CREATE_PHASE_TASKS_INSTALLER="$SCRIPT_DIR/install-recipe-create-phase-tasks.sh"
RECIPE_HELP_INSTALLER="$SCRIPT_DIR/install-recipe-help.sh"
RECIPE_NEW_PROJECT_INSTALLER="$SCRIPT_DIR/install-recipe-new-project.sh"
RECIPE_ONBOARD_INSTALLER="$SCRIPT_DIR/install-recipe-onboard.sh"
CAPABILITY_SCHEMA_LIB="$SCRIPT_DIR/../../bench/lib/capability-schema.sh"

# Cursor-facing GSD presence signal (see "Key research finding" in the plan:
# unclear whether the npx installer's --claude --global target is what backs
# this, so it's always re-checked rather than assumed). Override for tests —
# never point this at the real path when testing.
GSD_SIGNAL_PATH="${GSD_SIGNAL_PATH:-$HOME/.cursor/skills/gsd-help/SKILL.md}"

# GSD's own schema-aware config mutator, used exclusively to auto-set
# graphify.enabled in $TARGET/.planning/config.json (see
# graphify_config_enable() below) — never a hand-rolled JSON merge against
# that file. Overridable for tests, same override precedent as
# GSD_SIGNAL_PATH above — tests must always point this at a scratch stub,
# never the real gsd-tools.cjs.
GSD_TOOLS_CJS_PATH="${GSD_TOOLS_CJS_PATH:-$HOME/.claude/get-shit-done/bin/gsd-tools.cjs}"

PREREQ_PYTHON3=""
PREREQ_GIT=""
PREREQ_NODE=""
PREREQ_GH=""
PREREQ_GSD_CORE=""
PREREQ_GRAPHIFY=""

# Tri-state-plus-not-attempted outcome of graphify_config_enable(), written
# into install-report.json as "graphify_config_enabled". Defaults to the
# "never attempted" sentinel — only overwritten when graphify is actually
# present (PREREQ_GRAPHIFY is pass|auto_installed) and the function runs.
# See install_report_write() for the full schema.
GRAPHIFY_CONFIG_ENABLED="skipped_graphify_absent"

COMPONENT="install-core"

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
  # $1 = component name. Exit 0 if that component has a non-empty entry.
  ledger_init
  python3 - "$LEDGER" "$1" <<'PY'
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
  # if it resolves to one of our own template sources — true whenever TARGET
  # is this implementation repo itself (self-install case). Deleting these
  # would destroy the template, not just an installed copy.
  local candidate="$1" src
  [ -e "$candidate" ] || return 1
  for src in "$TEMPLATES_SRC_DIR"/*.template.md; do
    [ -e "$src" ] || continue
    if [ "$(cd "$(dirname "$candidate")" && pwd)/$(basename "$candidate")" = "$(cd "$(dirname "$src")" && pwd)/$(basename "$src")" ]; then
      return 0
    fi
  done
  return 1
}

# Copies $TEMPLATES_SRC_DIR/$1 (or an explicit absolute src via $4) to
# $TEMPLATES_DEST_DIR/$2, ledgered under $3 — but only if the destination
# doesn't already exist. Never overwrites an operator-customized template
# (same precedent as install-recipe-prd-intake.sh's PRD.template.md handling).
stage_template() {
  local src_name="$1" dest_name="$2" rel="$3" src_override="${4:-}"
  local src="${src_override:-$TEMPLATES_SRC_DIR/$src_name}"
  local dest="$TEMPLATES_DEST_DIR/$dest_name"
  if [ -f "$dest" ]; then
    echo "install.sh: $rel already exists, leaving it untouched."
    return 0
  fi
  safe_copy "$src" "$dest"
  ledger_record "$rel"
}

github_check() {
  # Warn-only per the LLD's Gate A precedent: a missing/unauthenticated gh
  # never fails the install closed, it just downgrades the recorded status.
  if ! command -v gh >/dev/null 2>&1; then
    echo "install.sh: gh CLI not found — GitHub check skipped (warn-only, install continues)." >&2
    echo "skipped"
    return 0
  fi
  if gh auth status >/dev/null 2>&1 && gh api user >/dev/null 2>&1; then
    echo "pass"
  else
    echo "install.sh: gh is installed but not authenticated (or API probe failed) — GitHub check failed (warn-only, install continues)." >&2
    echo "fail"
  fi
}

brew_fix_cmd() {
  # $1 = brew formula name. Prints the fix command to run, or nothing if no
  # safe auto-fix exists. Never guesses at apt/yum/dnf — non-macOS or
  # brew-absent always skips straight to the manual-instructions fallback.
  if [ "$(uname -s 2>/dev/null)" != "Darwin" ] || ! command -v brew >/dev/null 2>&1; then
    return 0
  fi
  echo "brew install $1"
}

uv_fix_cmd() {
  # Mirrors brew_fix_cmd()'s pattern for graphify: prints the fix command
  # only when its own precondition (uv itself present) already holds.
  # Never guesses at installing uv — ensure_prereq skips straight to the
  # warn-fallback when uv is absent, same as brew_fix_cmd on non-macOS/
  # brew-absent. Routes through install-graphify.sh (sudo-free).
  if ! command -v uv >/dev/null 2>&1; then
    return 0
  fi
  local graphify_installer="$SCRIPT_DIR/install-graphify.sh"
  if [ ! -x "$graphify_installer" ]; then
    graphify_installer="$GSD_RECIPE_DIR/scripts/install-graphify.sh"
  fi
  if [ -x "$graphify_installer" ]; then
    echo "\"$graphify_installer\""
    return 0
  fi
  echo "UV_CACHE_DIR=\"\$HOME/.uv-cache\" XDG_DATA_HOME=\"\$HOME/.xdg-data\" uv tool install graphifyy && graphify install"
}

# Generic check -> auto-fix-attempt -> verify -> prompt-and-reverify ->
# warn-fallback helper, applied identically to every prerequisite (the
# flowchart in the plan). Sets $PREREQ_RESULT to pass|auto_installed|fail
# for the caller to read (bash 3.2 on macOS has no associative arrays, so
# this is a plain global rather than an out-param).
#
# $1 = name (for messages)      $2 = check command (eval'd, 0 = satisfied)
# $3 = fix command (eval'd; empty = no safe auto-fix exists)
# $4 = hard (1 = exit 1 if still unresolved; 0 = warn-only)
# $5 = manual-instructions text shown in the fallback
ensure_prereq() {
  local name="$1" check_cmd="$2" fix_cmd="$3" hard="$4" instructions="$5"

  if eval "$check_cmd" >/dev/null 2>&1; then
    PREREQ_RESULT="pass"
    return 0
  fi

  if [ -n "$fix_cmd" ]; then
    echo "install.sh: $name missing — attempting automated fix ($fix_cmd)..." >&2
    eval "$fix_cmd" >/dev/null 2>&1 || true
    if eval "$check_cmd" >/dev/null 2>&1; then
      echo "install.sh: $name resolved by automated fix." >&2
      PREREQ_RESULT="auto_installed"
      return 0
    fi
  fi

  echo "install.sh: $name is missing. $instructions" >&2

  if [ "$YES" -eq 1 ]; then
    if [ "$hard" -eq 1 ]; then
      echo "install.sh: $name is required and --yes prevents interactive prompting. Aborting (fail closed)." >&2
      exit 1
    fi
    echo "install.sh: --yes passed — skipping the interactive prompt, $name recorded as failed (warn-only, install continues)." >&2
    PREREQ_RESULT="fail"
    return 0
  fi

  while read -r -p "install.sh: press Enter once $name is installed (Ctrl-C to abort)... " _reply; do
    if eval "$check_cmd" >/dev/null 2>&1; then
      echo "install.sh: $name now resolved." >&2
      PREREQ_RESULT="pass"
      return 0
    fi
    echo "install.sh: $name still not found. $instructions" >&2
  done
  # read failed — stdin closed with no further input (e.g. piped/non-tty
  # invocation that ran out of lines). Fall through to the same
  # hard/soft resolution as the --yes path rather than looping forever.

  if [ "$hard" -eq 1 ]; then
    echo "install.sh: $name is required and could not be resolved. Aborting (fail closed)." >&2
    exit 1
  fi
  echo "install.sh: $name could not be resolved (warn-only, install continues)." >&2
  PREREQ_RESULT="fail"
  return 0
}

preflight() {
  # python3/git first and hard — every script in this repo, including this
  # one, shells out to both internally.
  ensure_prereq "python3" "command -v python3" "$(brew_fix_cmd python3)" 1 \
    "install.sh needs python3 for JSON handling. Install it (e.g. 'brew install python3') and re-run."
  PREREQ_PYTHON3="$PREREQ_RESULT"

  ensure_prereq "git" "command -v git" "$(brew_fix_cmd git)" 1 \
    "install.sh needs the git CLI. Install it (e.g. 'brew install git') and re-run."
  PREREQ_GIT="$PREREQ_RESULT"

  ensure_prereq "node" "command -v npx" "$(brew_fix_cmd node)" 0 \
    "Node/npm/npx not found — the GSD auto-install step will be skipped (install still proceeds). Install Node (e.g. 'brew install node') to enable it."
  PREREQ_NODE="$PREREQ_RESULT"

  ensure_prereq "gh" "command -v gh" "$(brew_fix_cmd gh)" 0 \
    "gh CLI not found — the GitHub check will be skipped (install still proceeds). Install it (e.g. 'brew install gh') and run 'gh auth login'."
  PREREQ_GH="$PREREQ_RESULT"

  # GSD auto-fix only ever fires when completely absent — an already-present
  # GSD is left alone (upgrades stay /gsd-update's job). Also skipped
  # entirely when node is unavailable, since the installer is npx-based.
  local gsd_fix=""
  if [ "$PREREQ_NODE" != "fail" ] && [ ! -f "$GSD_SIGNAL_PATH" ]; then
    gsd_fix="npx -y --package=@opengsd/gsd-core@latest -- gsd-core --claude --global"
  fi
  ensure_prereq "gsd_core" "test -f \"$GSD_SIGNAL_PATH\"" "$gsd_fix" 0 \
    "GSD not detected at $GSD_SIGNAL_PATH. Install it: npx -y --package=@opengsd/gsd-core@latest -- gsd-core --claude --global"
  PREREQ_GSD_CORE="$PREREQ_RESULT"

  # graphify: soft/optional, standalone CLI (not an MCP server) — presence
  # is checked via binary detection (command -v), same pattern as every
  # other prerequisite here; GSD's own wrapper additionally probes
  # `graphify --help` (not `--version`, which graphify doesn't support) at
  # call time, but a simple PATH check is all preflight() needs. Auto-fix
  # only ever attempted when uv is already present (uv_fix_cmd returns
  # empty otherwise), matching brew_fix_cmd's "never guess at installing
  # the installer" precedent.
  ensure_prereq "graphify" "command -v graphify" "$(uv_fix_cmd)" 0 \
    "graphify not found — optional knowledge-graph tooling will be skipped (install still proceeds). Install it (no sudo): .gsd-recipe/scripts/install-graphify.sh (requires uv: brew install uv or https://docs.astral.sh/uv/)."
  PREREQ_GRAPHIFY="$PREREQ_RESULT"
}

config_json_merge() {
  mkdir -p "$(dirname "$CONFIG")"
  python3 - "$CONFIG" "$TARGET" "$SELF_ROOT" <<'PY'
import json, os, sys

path, target, self_root = sys.argv[1:4]
data = {}
if os.path.exists(path):
    with open(path) as f:
        content = f.read().strip()
        if content:
            data = json.loads(content)

# Additive only — never touches "tracker" or any other pre-existing key.
if "traceability" not in data:
    data["traceability"] = {"enabled": True, "reason": ""}
if "observer" not in data:
    data["observer"] = {"enabled": False, "interval_minutes": 10}

# recipe_source: absolute path to the recipe's own source repo, written only
# when TARGET is a *different* repo than the one install.sh itself lives in
# (an external --target install). Every recipe-*/gsd-jira-sync skill and
# recipe-paths.sh (the one small resolver script staged into every target,
# see below) read this to locate harness code that isn't duplicated into
# every target by design. Never written/overwritten for a self-install —
# everything is already local there. Never overwritten once set either
# (re-running install.sh against the same target shouldn't move this).
if os.path.realpath(target) != os.path.realpath(self_root) and "recipe_source" not in data:
    data["recipe_source"] = self_root

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

gitignore_ensure() {
  # $1 = line to ensure is present (as a whole line, not a substring probe).
  mkdir -p "$(dirname "$GITIGNORE")"
  touch "$GITIGNORE"
  if ! grep -qxF "$1" "$GITIGNORE"; then
    printf '%s\n' "$1" >> "$GITIGNORE"
  fi
}

install_report_write() {
  # $1 = github_check result (pass|fail|skipped)
  # $2..$7 = prereqs.{python3,git,node,gh,gsd_core,graphify} (pass|fail|auto_installed)
  # $8 = graphify_config_enabled — true (gsd-tools config-set succeeded),
  #      false (attempted but gsd-tools unavailable or config-set exited
  #      non-zero), "skipped_no_planning_config" (graphify present but no
  #      .planning/config.json in target yet), or "skipped_graphify_absent"
  #      (graphify prereq was "fail", so the auto-enable step was never
  #      even attempted).
  python3 - "$INSTALL_REPORT" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" <<'PY'
import json, os, sys, datetime

path, github_check, p_python3, p_git, p_node, p_gh, p_gsd_core, p_graphify, graphify_config_enabled = sys.argv[1:10]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

data = {}
if os.path.exists(path):
    with open(path) as f:
        content = f.read().strip()
        if content:
            data = json.loads(content)

data["github_check"] = github_check
data.setdefault("jira_check", "pending")  # never reset on re-install — see --record-jira-check
data["prereqs"] = {
    "python3": p_python3,
    "git": p_git,
    "node": p_node,
    "gh": p_gh,
    "gsd_core": p_gsd_core,
    "graphify": p_graphify,
}
# true/false stay JSON booleans; the "skipped_*" sentinels stay strings.
data["graphify_config_enabled"] = {"true": True, "false": False}.get(graphify_config_enabled, graphify_config_enabled)
data.setdefault("installed_at", now)
data["last_install_at"] = now

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

print_mcp_snippet() {
  cat <<'EOF'

--- MCP registration (print-only — paste into your mcp.json by hand) ---
Per docs/netapp-recipe/lld/INSTALL-LLD.md § "MCP extensions [E]":
{
  "mcpServers": {
    "chrome-devtools": {
      "command": "npx",
      "args": ["-y", "chrome-devtools-mcp@latest"]
    }
  }
}
install.sh never auto-edits mcp.json — this is Cursor's own shared config.
Add "gsd-browser" and your {TRACKER}-mcp server (e.g. Atlassian) alongside it
as needed; both are per-repo/per-operator choices, not scripted here.
EOF
}

print_agent_skills_snippet() {
  cat <<'EOF'

--- agent_skills injection (print-only — paste into .planning/config.json by hand) ---
Per docs/netapp-recipe/lld/INSTALL-LLD.md § "agent_skills injection [C]":
{
  "agent_skills": {
    "gsd-planner": ["skills/recipe-planning-policy"],
    "gsd-executor": ["skills/recipe-repo-conventions"],
    "gsd-verifier": ["skills/recipe-acceptance-criteria"]
  }
}
install.sh never auto-edits .planning/config.json — it's GSD's own config
file, and blind-merging JSON into it risks clobbering unrelated settings.
EOF
}

print_graphify_config_snippet() {
  cat <<EOF

--- graphify.enabled (print-only — automated config-set path unavailable) ---
graphify is present, but install.sh could not run the automated
'gsd-tools config-set' step (gsd-tools not on PATH, and \$GSD_TOOLS_CJS_PATH
does not resolve to a real gsd-tools.cjs). Enable it by hand:
  gsd-tools config-set graphify.enabled true --cwd "$TARGET"
install.sh never hand-edits .planning/config.json directly — same policy as
the agent_skills injection above. graphify.enabled is the one sanctioned
exception, and it's routed exclusively through gsd-tools's own schema-aware
config-set, never a hand-rolled JSON merge.
EOF
}

graphify_config_enable() {
  # Auto-enables graphify.enabled=true in the *target project's* GSD-native
  # .planning/config.json — the one sanctioned exception to this script's
  # "never auto-edit .planning/config.json" policy (see
  # print_agent_skills_snippet() above). Only ever called when graphify is
  # genuinely present right now (preflight's PREREQ_GRAPHIFY is pass or
  # auto_installed) — see the call site in install().
  #
  # The exception's mechanism still respects the policy's spirit: this
  # never hand-rolls a python3 json.load/dump merge against
  # .planning/config.json the way config_json_merge() does for
  # .gsd-recipe/config.json (a file this script owns) — instead it shells
  # out to GSD's own sanctioned mutator, `gsd-tools config-set`, which is
  # schema-aware and preserves unrelated keys correctly.
  #
  # Try/warn-only: must never cause install.sh to exit non-zero, no matter
  # what happens (missing .planning/config.json, missing gsd-tools, a
  # failing config-set call — all degrade to a print-only fallback, never a
  # crash). Sets $GRAPHIFY_CONFIG_ENABLED to true|false|
  # "skipped_no_planning_config" for the caller (install_report_write) to
  # read.
  local planning_config="$TARGET/.planning/config.json"

  if [ ! -f "$planning_config" ]; then
    echo "install.sh: $planning_config not found — skipping graphify.enabled auto-set (project isn't GSD-initialized yet, nothing safe to enable)." >&2
    GRAPHIFY_CONFIG_ENABLED="skipped_no_planning_config"
    return 0
  fi

  local gsd_tools_cmd=""
  if command -v gsd-tools >/dev/null 2>&1; then
    gsd_tools_cmd="gsd-tools"
  elif command -v node >/dev/null 2>&1 && [ -f "$GSD_TOOLS_CJS_PATH" ]; then
    gsd_tools_cmd="node \"$GSD_TOOLS_CJS_PATH\""
  fi

  if [ -z "$gsd_tools_cmd" ]; then
    echo "install.sh: gsd-tools not found on PATH and GSD_TOOLS_CJS_PATH ($GSD_TOOLS_CJS_PATH) does not resolve to a real file — cannot auto-set graphify.enabled." >&2
    print_graphify_config_snippet
    GRAPHIFY_CONFIG_ENABLED="false"
    return 0
  fi

  if eval "$gsd_tools_cmd config-set graphify.enabled true --cwd \"$TARGET\"" >/dev/null 2>&1; then
    echo "install.sh: set graphify.enabled=true in $planning_config via gsd-tools config-set." >&2
    GRAPHIFY_CONFIG_ENABLED="true"
  else
    echo "install.sh: gsd-tools config-set graphify.enabled true failed (non-zero exit) — leaving $planning_config untouched." >&2
    print_graphify_config_snippet
    GRAPHIFY_CONFIG_ENABLED="false"
  fi
  return 0
}

install() {
  preflight

  # The one sanctioned exception to "never auto-edit .planning/config.json"
  # — only fires when graphify is genuinely present right now, never on
  # PREREQ_GRAPHIFY=fail (nothing to enable safely). See
  # graphify_config_enable() for the full mechanism.
  if [ "$PREREQ_GRAPHIFY" = "pass" ] || [ "$PREREQ_GRAPHIFY" = "auto_installed" ]; then
    graphify_config_enable
  fi

  if [ "$YES" -ne 1 ]; then
    read -r -p "Install NetApp GSD recipe scaffold (install-core + observer + tracker-sync + recipe-planning-policy + recipe-run-phase + recipe-plan-phase + recipe-validate-tokens + recipe-bootstrap-knowledge + recipe-install-verify + recipe-run-phases + recipe-verify-feature + recipe-review-ship + recipe-settle + gsd-jira-sync + recipe-sync + recipe-pr-comment + recipe-install + recipe-observe + recipe-create-epic + recipe-create-phase-tasks + recipe-help + recipe-new-project + recipe-onboard) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "install.sh: aborted, no consent given."; exit 0 ;;
    esac
  fi

  local gh_result
  gh_result="$(github_check)"
  echo "install.sh: GitHub check: $gh_result"

  mkdir -p "$TEMPLATES_DEST_DIR"
  stage_template "PRD.template.md" "PRD.template.md" ".templates/PRD.template.md"
  stage_template "SPEC.template.md" "SPEC.template.md" ".templates/SPEC.template.md"
  stage_template "TDD.template.md" "TDD.template.md" ".templates/TDD.template.md"
  stage_template "bare_metal.template.md" "bare_metal.template.md" ".templates/bare_metal.template.md"
  stage_template "" "jira-comment.template.md" ".templates/jira-comment.template.md" "$JIRA_COMMENT_SRC"
  stage_template "" "github-pr-comment.template.md" ".templates/github-pr-comment.template.md" "$GITHUB_PR_COMMENT_SRC"

  for d in architecture dependency-graph hot-files risk-register dag; do
    mkdir -p "$KNOWLEDGE_DIR/$d"
    touch "$KNOWLEDGE_DIR/$d/.gitkeep"
    ledger_record ".knowledge/$d/.gitkeep"
  done
  if [ -f "$KNOWLEDGE_DIR/index.md" ]; then
    echo "install.sh: .knowledge/index.md already exists, leaving it untouched."
  else
    cat > "$KNOWLEDGE_DIR/index.md" <<'EOF'
---
type: index
title: Knowledge Index
---

# Knowledge Index

OKF v0.1 bundle root index. Populated by `/gsd-map-codebase`,
`/gsd-graphify build`, `/gsd-ingest-docs` (see
docs/netapp-recipe/lld/INSTALL-LLD.md § "Populate .knowledge/ from GSD") —
not by install.sh itself.
EOF
    ledger_record ".knowledge/index.md"
  fi
  if [ -f "$KNOWLEDGE_DIR/log.md" ]; then
    echo "install.sh: .knowledge/log.md already exists, leaving it untouched."
  else
    cat > "$KNOWLEDGE_DIR/log.md" <<'EOF'
---
type: log
title: Knowledge Log
---

# Knowledge Log

Append-only change log for this OKF bundle.
EOF
    ledger_record ".knowledge/log.md"
  fi

  if [ -f "$CODE_BASE_DETAILS_README" ]; then
    echo "install.sh: code_base_details/README.md already exists, leaving human content untouched."
  else
    mkdir -p "$(dirname "$CODE_BASE_DETAILS_README")"
    cat > "$CODE_BASE_DETAILS_README" <<'EOF'
# Code base details

Human-authored repo context: runbooks, architecture notes, onboarding
quirks — anything an agent should read before working in this repo.

Ingested at runtime via `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml`.
This directory is never overwritten by install.sh once it exists.
EOF
    ledger_record "code_base_details/README.md"
  fi

  # Additive-only entries — must stay in sync with bench/tests/test-install.sh
  # and the --verify gitignore check below.
  #
  # Policy (INSTALL-LLD § .gitignore additions): on *external* targets the
  # recipe scaffold is local-only — not committed with product/feature work.
  # Self-install into this source repo skips `.gsd-recipe/` so we never hide
  # the canonical recipe tree that install.sh itself lives in.
  local self_install=0
  if [ "$(cd "$TARGET" && pwd)" = "$SELF_ROOT" ]; then
    self_install=1
  fi
  local gitignore_line
  while IFS= read -r gitignore_line; do
    [ -n "$gitignore_line" ] || continue
    if [ "$self_install" -eq 1 ] && [ "$gitignore_line" = ".gsd-recipe/" ]; then
      continue
    fi
    gitignore_ensure "$gitignore_line"
  done <<'GITIGNORE_LINES'
/bin/
/dist/
*.exe
.idea/
.vscode/
.env
.env.*
.learnings/
.gsd-codebase/
.gsd-recipe/
.knowledge/
.templates/
.planning/
code_base_details/
skills/
docs/RECIPE-COMMANDS.md
docs/RECIPE-BENCHMARKS.md
bench/
.cursor/get-shit-done/
.cursor/gsd-install-state.json
.cursor/gsd-file-manifest.json
.cursor/.gsd-profile
graphify-out/
GITIGNORE_LINES

  config_json_merge

  # Unconditionally refreshed (never gated on "already exists") — this is
  # pure harness code with no operator customization to protect, the same
  # category as the generated capability.json below, unlike the
  # never-overwritten .templates/ files. Every recipe-*/gsd-jira-sync skill
  # that needs a harness path (a .gsd-recipe/scripts/*, bench/runners/*, or
  # bench/lib/* file not duplicated into every target) resolves it through
  # this one small script instead of hardcoding a relative path.
  mkdir -p "$GSD_RECIPE_DIR/scripts"
  safe_copy "$RECIPE_PATHS_SRC" "$GSD_RECIPE_DIR/scripts/recipe-paths.sh"
  chmod +x "$GSD_RECIPE_DIR/scripts/recipe-paths.sh"
  ledger_record ".gsd-recipe/scripts/recipe-paths.sh"
  safe_copy "$SCRIPT_DIR/install-graphify.sh" "$GSD_RECIPE_DIR/scripts/install-graphify.sh"
  chmod +x "$GSD_RECIPE_DIR/scripts/install-graphify.sh"
  ledger_record ".gsd-recipe/scripts/install-graphify.sh"

  echo "install.sh: composing sub-installers (observer, tracker-sync, recipe-planning-policy, recipe-run-phase, recipe-plan-phase, recipe-validate-tokens, recipe-bootstrap-knowledge, recipe-install-verify, recipe-run-phases, recipe-verify-feature, recipe-review-ship, recipe-settle, gsd-jira-sync, recipe-sync, recipe-pr-comment, recipe-install, recipe-observe, recipe-create-epic, recipe-create-phase-tasks, recipe-help, recipe-new-project, recipe-onboard)..."
  "$OBSERVER_INSTALLER" --yes --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VALIDATE_TOKENS_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_RUN_PHASES_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_VERIFY_FEATURE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_REVIEW_SHIP_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_SETTLE_INSTALLER" --yes --target "$TARGET"
  "$GSD_JIRA_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_SYNC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_PR_COMMENT_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_INSTALL_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_OBSERVE_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_CREATE_EPIC_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_CREATE_PHASE_TASKS_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_HELP_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_NEW_PROJECT_INSTALLER" --yes --target "$TARGET"
  "$RECIPE_ONBOARD_INSTALLER" --yes --target "$TARGET"

  install_report_write "$gh_result" "$PREREQ_PYTHON3" "$PREREQ_GIT" "$PREREQ_NODE" "$PREREQ_GH" "$PREREQ_GSD_CORE" "$PREREQ_GRAPHIFY" "$GRAPHIFY_CONFIG_ENABLED"
  ledger_record ".gsd-recipe/install-report.json"

  "$CAPABILITY_SCHEMA_LIB" generate-capability --target "$TARGET" >/dev/null
  ledger_record ".gsd-recipe/capability.json"

  print_mcp_snippet
  print_agent_skills_snippet

  echo
  echo "install.sh: staged. install-core files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Jira check is recorded as 'pending' in $INSTALL_REPORT — an agent with"
  echo "live Atlassian MCP access must run the real check and then call:"
  echo "  $0 --record-jira-check <pass|fail> --target $TARGET"
  echo "Run '$0 --verify --target $TARGET' once that's done."
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

verify() {
  local ok=1
  local gh_result jira_check

  echo "install.sh --verify: local checklist (docs/netapp-recipe/lld/INSTALL-LLD.md Step 5)"
  echo

  echo "Prerequisite status (from last install run's install-report.json):"
  if [ -f "$INSTALL_REPORT" ]; then
    python3 -c "
import json
d = json.load(open('$INSTALL_REPORT')).get('prereqs', {})
for k in ('python3', 'git', 'node', 'gh', 'gsd_core', 'graphify'):
    print(f'  {k}: {d.get(k, \"unknown\")}')"
  else
    echo "  (none recorded yet — run install.sh first)"
  fi
  echo

  echo "[N] 1. GSD integrity (/gsd-health [--repair]) — run manually"
  echo "[N] 2. Context headroom (/gsd-health --context) — run manually"
  echo "[N] 3. Capability surface (/gsd-surface status) — run manually"

  gh_result="$(github_check)"
  echo "[X] 4a. GitHub token/scope check — $gh_result (warn-only, non-blocking)"

  jira_check="pending"
  if [ -f "$INSTALL_REPORT" ]; then
    jira_check="$(python3 -c "import json; print(json.load(open('$INSTALL_REPORT')).get('jira_check', 'pending'))")"
  fi
  echo "[X] 4b. Jira token/scope check — $jira_check (blocks INSTALL-VERIFIED.json while pending)"
  if [ "$jira_check" = "pending" ]; then
    ok=0
  fi

  local missing_templates=""
  for f in PRD.template.md SPEC.template.md TDD.template.md bare_metal.template.md jira-comment.template.md github-pr-comment.template.md; do
    [ -f "$TEMPLATES_DEST_DIR/$f" ] || missing_templates="$missing_templates $f"
  done
  if [ -z "$missing_templates" ]; then
    echo "[C] 5. Templates present — pass"
  else
    echo "[C] 5. Templates present — FAIL (missing:$missing_templates)"
    ok=0
  fi

  if [ -f "$KNOWLEDGE_DIR/index.md" ]; then
    echo "[C] 6. OKF index (.knowledge/index.md) — pass"
  else
    echo "[C] 6. OKF index (.knowledge/index.md) — FAIL (missing)"
    ok=0
  fi

  local missing_gitignore=""
  local self_install=0
  if [ "$(cd "$TARGET" && pwd)" = "$SELF_ROOT" ]; then
    self_install=1
  fi
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$self_install" -eq 1 ] && [ "$line" = ".gsd-recipe/" ]; then
      continue
    fi
    if [ ! -f "$GITIGNORE" ] || ! grep -qxF "$line" "$GITIGNORE"; then
      missing_gitignore="$missing_gitignore [$line]"
    fi
  done <<'GITIGNORE_VERIFY'
/bin/
/dist/
*.exe
.idea/
.vscode/
.env
.env.*
.learnings/
.gsd-codebase/
.gsd-recipe/
.knowledge/
.templates/
.planning/
code_base_details/
skills/
docs/RECIPE-COMMANDS.md
docs/RECIPE-BENCHMARKS.md
bench/
.cursor/get-shit-done/
.cursor/gsd-install-state.json
.cursor/gsd-file-manifest.json
.cursor/.gsd-profile
GITIGNORE_VERIFY
  if [ -x "$GSD_RECIPE_DIR/scripts/recipe-paths.sh" ]; then
    echo "[C] recipe-paths.sh staged — pass"
  else
    echo "[C] recipe-paths.sh staged — FAIL (missing or not executable at $GSD_RECIPE_DIR/scripts/recipe-paths.sh)"
    ok=0
  fi

  if [ "$(cd "$TARGET" && pwd)" = "$SELF_ROOT" ] || python3 -c "
import json
d = json.load(open('$CONFIG')) if __import__('os').path.exists('$CONFIG') else {}
raise SystemExit(0 if d.get('recipe_source') else 1)
" 2>/dev/null; then
    echo "[C] recipe_source resolvable (self-install or recorded in config.json) — pass"
  else
    echo "[C] recipe_source resolvable — FAIL (external target but config.json has no 'recipe_source')"
    ok=0
  fi

  if [ -z "$missing_gitignore" ]; then
    echo "[C] 7. Gitignore entries — pass"
  else
    echo "[C] 7. Gitignore entries — FAIL (missing:$missing_gitignore)"
    ok=0
  fi

  local config_err_file
  config_err_file="$(mktemp)"
  if [ ! -f "$CONFIG" ]; then
    echo "[C] config.json — FAIL (missing $CONFIG)"
    ok=0
  elif python3 -c "
import json, sys
d = json.load(open('$CONFIG'))
t = d.get('traceability')
o = d.get('observer')
assert isinstance(t, dict) and isinstance(t.get('enabled'), bool), 'traceability.enabled missing/invalid'
if not t['enabled']:
    assert isinstance(t.get('reason'), str) and t['reason'], 'traceability.reason required when disabled'
assert isinstance(o, dict) and isinstance(o.get('enabled'), bool), 'observer.enabled missing/invalid'
if o['enabled']:
    assert isinstance(o.get('interval_minutes'), int), 'observer.interval_minutes required when observer enabled'
" 2>"$config_err_file"; then
    echo "[C] config.json — parses and has required traceability/observer fields — pass"
  else
    echo "[C] config.json — FAIL ($(tail -n1 "$config_err_file"))"
    ok=0
  fi
  rm -f "$config_err_file"

  if "$CAPABILITY_SCHEMA_LIB" validate-config --config "$CONFIG" --schema "$SCRIPT_DIR/../config.schema.json" >/dev/null 2>&1; then
    echo "[C] config.schema.json — strict schema validation — pass"
  else
    echo "[C] config.schema.json — strict schema validation — FAIL"
    ok=0
  fi

  echo "[E] 8. MCP reachable — optional, not automated (print-only snippet at install time)"

  if ledger_has_component "fotw-observer"; then
    echo "[X] 9. Observer loop composed — pass"
  else
    echo "[X] 9. Observer loop composed — FAIL (fotw-observer ledger component absent)"
    ok=0
  fi
  if ledger_has_component "tracker-sync"; then
    echo "    tracker-sync composed — pass"
  else
    echo "    tracker-sync composed — FAIL (tracker-sync ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-planning-policy"; then
    echo "    recipe-planning-policy composed — pass"
  else
    echo "    recipe-planning-policy composed — FAIL (recipe-planning-policy ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-run-phase"; then
    echo "    recipe-run-phase composed — pass"
  else
    echo "    recipe-run-phase composed — FAIL (recipe-run-phase ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-plan-phase"; then
    echo "    recipe-plan-phase composed — pass"
  else
    echo "    recipe-plan-phase composed — FAIL (recipe-plan-phase ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-validate-tokens"; then
    echo "    recipe-validate-tokens composed — pass"
  else
    echo "    recipe-validate-tokens composed — FAIL (recipe-validate-tokens ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-bootstrap-knowledge"; then
    echo "    recipe-bootstrap-knowledge composed — pass"
  else
    echo "    recipe-bootstrap-knowledge composed — FAIL (recipe-bootstrap-knowledge ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-install-verify"; then
    echo "    recipe-install-verify composed — pass"
  else
    echo "    recipe-install-verify composed — FAIL (recipe-install-verify ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-run-phases"; then
    echo "    recipe-run-phases composed — pass"
  else
    echo "    recipe-run-phases composed — FAIL (recipe-run-phases ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-verify-feature"; then
    echo "    recipe-verify-feature composed — pass"
  else
    echo "    recipe-verify-feature composed — FAIL (recipe-verify-feature ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-review-ship"; then
    echo "    recipe-review-ship composed — pass"
  else
    echo "    recipe-review-ship composed — FAIL (recipe-review-ship ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-settle"; then
    echo "    recipe-settle composed — pass"
  else
    echo "    recipe-settle composed — FAIL (recipe-settle ledger component absent)"
    ok=0
  fi
  if ledger_has_component "gsd-jira-sync"; then
    echo "    gsd-jira-sync composed — pass"
  else
    echo "    gsd-jira-sync composed — FAIL (gsd-jira-sync ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-sync"; then
    echo "    recipe-sync composed — pass"
  else
    echo "    recipe-sync composed — FAIL (recipe-sync ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-pr-comment"; then
    echo "    recipe-pr-comment composed — pass"
  else
    echo "    recipe-pr-comment composed — FAIL (recipe-pr-comment ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-install"; then
    echo "    recipe-install composed — pass"
  else
    echo "    recipe-install composed — FAIL (recipe-install ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-observe"; then
    echo "    recipe-observe composed — pass"
  else
    echo "    recipe-observe composed — FAIL (recipe-observe ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-create-epic"; then
    echo "    recipe-create-epic composed — pass"
  else
    echo "    recipe-create-epic composed — FAIL (recipe-create-epic ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-create-phase-tasks"; then
    echo "    recipe-create-phase-tasks composed — pass"
  else
    echo "    recipe-create-phase-tasks composed — FAIL (recipe-create-phase-tasks ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-help"; then
    echo "    recipe-help composed — pass"
  else
    echo "    recipe-help composed — FAIL (recipe-help ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-new-project"; then
    echo "    recipe-new-project composed — pass"
  else
    echo "    recipe-new-project composed — FAIL (recipe-new-project ledger component absent)"
    ok=0
  fi
  if ledger_has_component "recipe-onboard"; then
    echo "    recipe-onboard composed — pass"
  else
    echo "    recipe-onboard composed — FAIL (recipe-onboard ledger component absent)"
    ok=0
  fi

  echo "[X] 10. Bare metal Gate A (.templates/bare_metal.template.md bootstrap run) — run manually"

  echo
  if [ "$ok" -eq 1 ]; then
    local tracker vcs
    tracker="$(python3 -c "import json; print(json.load(open('$CONFIG')).get('tracker', 'jira'))" 2>/dev/null || echo jira)"
    vcs="github"
    python3 - "$INSTALL_VERIFIED" "$tracker" "$vcs" <<'PY'
import json, sys, datetime
path, tracker, vcs = sys.argv[1], sys.argv[2], sys.argv[3]
data = {
    "verified_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "gsd_version": "unknown",  # native GSD version probe is agent-mediated, not scriptable — see checklist items 1-3
    "tracker": tracker,
    "vcs": vcs,
}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
    echo "All local + Jira checks pass — wrote $INSTALL_VERIFIED"
    return 0
  else
    echo "One or more checks failed or are pending — $INSTALL_VERIFIED NOT written."
    return 1
  fi
}

record_jira_check() {
  case "$JIRA_CHECK_VALUE" in
    pass|fail) : ;;
    *) echo "install.sh --record-jira-check: value must be 'pass' or 'fail' (got '$JIRA_CHECK_VALUE')" >&2; exit 2 ;;
  esac
  mkdir -p "$(dirname "$INSTALL_REPORT")"
  python3 - "$INSTALL_REPORT" "$JIRA_CHECK_VALUE" <<'PY'
import json, os, sys, datetime
path, value = sys.argv[1], sys.argv[2]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
data = {}
if os.path.exists(path):
    with open(path) as f:
        content = f.read().strip()
        if content:
            data = json.loads(content)
data.setdefault("github_check", "skipped")
data["jira_check"] = value
data["jira_check_recorded_at"] = now
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
  echo "install.sh: recorded jira_check=$JIRA_CHECK_VALUE in $INSTALL_REPORT"
}

uninstall() {
  echo "install.sh: removing install-core tracked files..."
  while IFS= read -r rel; do
    case "$rel" in
      code_base_details/README.md|.knowledge/index.md|.knowledge/log.md|.knowledge/*/.gitkeep)
        echo "  keeping $rel (human-authored knowledge data — preserved per removal policy, review before delete)"
        continue
        ;;
    esac
    if is_canonical_source "$TARGET/$rel"; then
      echo "  keeping $rel (this is the canonical template source, not an installed copy — self-install case)"
      continue
    fi
    if [ -f "$TARGET/$rel" ]; then
      rm -f "$TARGET/$rel"
      echo "  removed $rel"
    fi
  done < <(ledger_files)

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

  echo "install.sh: cascading to sub-installers' own --uninstall..."
  "$OBSERVER_INSTALLER" --uninstall --target "$TARGET"
  "$TRACKER_SYNC_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_PLANNING_POLICY_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_RUN_PHASE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_PLAN_PHASE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_VALIDATE_TOKENS_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_BOOTSTRAP_KNOWLEDGE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_INSTALL_VERIFY_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_RUN_PHASES_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_VERIFY_FEATURE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_REVIEW_SHIP_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_SETTLE_INSTALLER" --uninstall --target "$TARGET"
  "$GSD_JIRA_SYNC_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_SYNC_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_PR_COMMENT_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_INSTALL_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_OBSERVE_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_CREATE_EPIC_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_CREATE_PHASE_TASKS_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_HELP_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_NEW_PROJECT_INSTALLER" --uninstall --target "$TARGET"
  "$RECIPE_ONBOARD_INSTALLER" --uninstall --target "$TARGET"

  echo "install.sh: uninstall complete. code_base_details/, .knowledge/, config.json, and .gitignore are left in place (shared/human data this installer doesn't own for deletion)."
}

case "$MODE" in
  install) install ;;
  verify) verify ;;
  record-jira-check) record_jira_check ;;
  uninstall) uninstall ;;
esac
