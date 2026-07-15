#!/usr/bin/env bash
# recipe-settle installer — standalone fallback path per
# lld/TRACEABILITY-LLD.md rule 4 ("Settled = PO + CI green"),
# lld/RUNTIME-LLD.md § 4.c Ship ("PO accept + CI green before settled"), and
# lld/FAILURE-MATRIX.md's "CI red at settle gate" row, formalized into its
# own re-invokable Cursor skill (TASK-027). Same standalone-installer shape
# as install-recipe-validate-tokens.sh / install-recipe-run-phase.sh,
# independent of the full TASK-010 install.sh (intended to also be composed
# into it as a ninth sub-installer — see the copy-paste snippet in this
# task's integration report; not wired in by this script itself, to avoid a
# concurrent edit collision with sibling in-flight tasks on install.sh).
#
# Stages an invoke-by-name Cursor skill (single file, .cursor/skills/ — same
# shape as recipe-run-phase/recipe-plan-phase/recipe-validate-tokens).
#
# Also ships this script's own --check-ci mode: a real, standalone, testable
# GitHub CI status probe (gh pr checks, falling back to gh api .../check-runs
# when no PR is found for the given ref) — the direct CI-check analog of
# recipe-validate-tokens's own --check-github mode. It does NOT implement
# the PO-accept human gate — that gate has no local scriptable oracle (only
# the live agent<->operator conversation can reach a real human), so it is
# entirely a skill-instruction concern, never a script mode. See this
# script's own header note under check_ci() and the skill's own "Why this is
# a genuine human gate, not skippable" section for the full rationale.
#
# Usage:
#   ./.gsd-recipe/scripts/install-recipe-settle.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-settle.sh --uninstall [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-recipe-settle.sh --check-ci <owner/repo> <ref>
#
# Design (mirrors install-recipe-validate-tokens.sh's structure/functions for
# install/uninstall; --check-ci is net-new for this skill):
#   - Human gate: operator approves before anything is staged (--yes skips
#     the interactive prompt for scripted/CI installs). This --yes flag only
#     ever affects this *install-time* scaffolding prompt — it has no
#     bearing on, and cannot skip, the separate runtime PO-accept gate the
#     skill itself asks the operator at settle time (that gate has no flag
#     at all, by design — see the skill's own "Why this is a genuine human
#     gate, not skippable" section).
#   - Fail closed on install/uninstall: never partially stage; never
#     overwrite operator data; refuses a non-git --target.
#   - --check-ci needs no git repo / --target at all — it's a pure,
#     read-only local CI-status probe, unrelated to any scaffolding. Never
#     fails closed: a missing/unauthenticated gh, a failed API probe, or
#     failing/pending checks are all reported as FAIL/WARN, but the script
#     itself always exits 0 (this is a reporting tool, not a gate — the
#     invoking skill decides what to do with the result, same precedent as
#     recipe-validate-tokens's own --check-github).
#   - Never prints token/credential values — gh's own commands are never
#     asked to reveal one, and no output is echoed that could contain one.
#   - Ledger-tracked: the staged file is recorded in .gsd-recipe/ledger.json
#     under component "recipe-settle" for clean removal.
#   - Never touches .gsd-recipe/config.json or .planning/config.json — this
#     installer's only job is staging one file (and --check-ci never writes
#     anything at all, anywhere).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODE="install"
YES=0
TARGET=""
CHECK_CI_OWNER_REPO=""
CHECK_CI_REF=""

while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --check-ci)
      MODE="check-ci"
      CHECK_CI_OWNER_REPO="${2:?--check-ci requires <owner/repo> <ref>}"
      CHECK_CI_REF="${3:?--check-ci requires <owner/repo> <ref>}"
      shift 3
      ;;
    --yes|-y) YES=1; shift ;;
    --target) TARGET="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

# render_checks_json()/check_ci_via_api() (both defined below) read their
# python helper from $RENDER_CHECKS_PY/$CHECK_RUNS_API_PY — real mktemp'd
# files, written just below, only when MODE=check-ci actually needs them.
# Deliberately NOT an inline `python3 -c "$(cat <<'PY' ... )"` heredoc: bash
# 3.2 (still macOS's /bin/bash) has a documented quirk where a heredoc read
# inside a command substitution that itself lives inside a shell *function
# being used as the receiving end of a pipe* (exactly this script's
# `printf ... | render_checks_json ""` call shape) can desync from the
# enclosing pipe's stdin and corrupt the substituted text. A plain temp file
# sidesteps that class of bug entirely — every *other* heredoc in this
# script (ledger_record, etc.) is safe because none of those are ever the
# receiving end of a pipe themselves.
RENDER_CHECKS_PY=""
CHECK_RUNS_API_PY=""

write_check_ci_helpers() {
  RENDER_CHECKS_PY="$(mktemp)"
  CHECK_RUNS_API_PY="$(mktemp)"
  trap 'rm -f "$RENDER_CHECKS_PY" "$CHECK_RUNS_API_PY"' EXIT

  cat > "$RENDER_CHECKS_PY" <<'PY'
import json, os, sys

filter_bucket = os.environ.get("FILTER_BUCKET", "")
try:
    checks = json.load(sys.stdin)
except ValueError:
    sys.exit(0)

for c in checks:
    bucket = c.get("bucket", "unknown")
    if filter_bucket and bucket != filter_bucket:
        continue
    print(f"  {bucket}: {c.get('name', 'unknown')}")
PY

  cat > "$CHECK_RUNS_API_PY" <<'PY'
import json, sys

try:
    data = json.load(sys.stdin)
except ValueError:
    print("CI: WARN (check-runs API returned unparseable output)")
    sys.exit(0)

runs = data.get("check_runs", [])
if not runs:
    print("CI: WARN (no check runs found for this ref -- CI may not be configured, or has not run yet)")
    sys.exit(0)

pending = [r for r in runs if r.get("status") != "completed"]
failing = [
    r for r in runs
    if r.get("status") == "completed" and r.get("conclusion") not in ("success", "neutral", "skipped")
]

if pending:
    print(f"CI: FAIL ({len(pending)} of {len(runs)} check run(s) still pending)")
    for r in pending:
        print(f"  pending: {r.get('name', 'unknown')}")
    sys.exit(0)

if failing:
    print(f"CI: FAIL ({len(failing)} of {len(runs)} check run(s) failing)")
    for r in failing:
        print(f"  failing: {r.get('name', 'unknown')} (conclusion: {r.get('conclusion', 'unknown')})")
    sys.exit(0)

print(f"CI: PASS (all {len(runs)} check run(s) green via check-runs API)")
for r in runs:
    print(f"  pass: {r.get('name', 'unknown')}")
PY
}

# Renders a gh pr checks --json (name,state,bucket,link) array into
# "  <bucket>: <name>" detail lines, one per element optionally filtered to
# $1 = a bucket to keep (empty = keep all). Reads the JSON from stdin. Silent
# no-op (never errors the caller) if the input isn't parseable JSON — the
# raw gh output has already been shown to the operator by the caller in that
# case, this is purely an enrichment pass.
render_checks_json() {
  local filter_bucket="${1:-}"
  FILTER_BUCKET="$filter_bucket" python3 "$RENDER_CHECKS_PY" 2>/dev/null || true
}

check_ci_via_api() {
  # Fallback used by check_ci() when gh pr checks reports "no pull requests
  # found" for the given ref (e.g. settling directly against a branch/SHA
  # with no open PR). Queries the commit's check-runs directly. Always
  # returns 0 — reports PASS/FAIL/WARN, never fails the caller closed.
  local owner_repo="$1" ref="$2"
  local api_output api_rc
  api_output="$(gh api "repos/$owner_repo/commits/$ref/check-runs" 2>&1)" && api_rc=0 || api_rc=$?

  if [ "$api_rc" -ne 0 ]; then
    echo "CI: WARN (no PR found for '$ref', and the check-runs API probe also failed)"
    echo "  Detail: gh api repos/$owner_repo/commits/$ref/check-runs failed — $(printf '%s' "$api_output" | head -n1)"
    return 0
  fi

  # Uses the pre-created $CHECK_RUNS_API_PY temp file — see the comment
  # above render_checks_json() for why this must not be an inline heredoc.
  printf '%s' "$api_output" | python3 "$CHECK_RUNS_API_PY"
}

check_ci() {
  # Mirrors recipe-validate-tokens's own check_github() shape: a real,
  # standalone, testable probe reported as exactly one of PASS/FAIL/WARN.
  # $1 = owner/repo, $2 = ref (PR number, branch name, or SHA). Always
  # returns 0 — this function reports, it never fails the caller closed
  # (the invoking skill's own CI gate, not this script, decides what to do
  # with a non-PASS result).
  local owner_repo="$1" ref="$2"

  if ! command -v gh >/dev/null 2>&1; then
    echo "CI: FAIL (gh CLI not found on PATH)"
    echo "  Remediation: install the gh CLI (e.g. 'brew install gh'), then run 'gh auth login'."
    return 0
  fi

  local pr_output pr_rc
  pr_output="$(gh pr checks "$ref" -R "$owner_repo" --json name,state,bucket,link 2>&1)" && pr_rc=0 || pr_rc=$?

  case "$pr_rc" in
    0)
      echo "CI: PASS (all checks green for $owner_repo @ $ref)"
      printf '%s' "$pr_output" | render_checks_json ""
      return 0
      ;;
    8)
      echo "CI: FAIL (one or more checks still pending -- not yet green -- for $owner_repo @ $ref)"
      printf '%s' "$pr_output" | render_checks_json "pending"
      return 0
      ;;
    4)
      echo "CI: FAIL (gh CLI found but not authenticated)"
      echo "  Remediation: run 'gh auth login'."
      return 0
      ;;
  esac

  # rc not in {0,8,4}: either genuine failing checks, or gh pr checks
  # couldn't resolve a PR for this ref at all (common when settling
  # directly against a branch/SHA with no open PR) -- check the message to
  # decide whether to report FAIL directly or fall back to the check-runs
  # API for that same ref.
  if printf '%s' "$pr_output" | grep -qi "no pull requests found\|could not resolve\|no default remote"; then
    check_ci_via_api "$owner_repo" "$ref"
    return 0
  fi

  echo "CI: FAIL (one or more checks failing for $owner_repo @ $ref)"
  local rendered
  rendered="$(printf '%s' "$pr_output" | render_checks_json "")"
  if [ -n "$rendered" ]; then
    printf '%s\n' "$rendered"
  else
    printf '%s\n' "$pr_output" | sed 's/^/  /'
  fi
}

if [ "$MODE" = "check-ci" ]; then
  write_check_ci_helpers
  check_ci "$CHECK_CI_OWNER_REPO" "$CHECK_CI_REF"
  exit 0
fi

if [ -z "$TARGET" ]; then
  TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

if [ ! -d "$TARGET/.git" ]; then
  echo "recipe-settle installer: $TARGET is not a git repo root. Refusing to scaffold (fail closed)." >&2
  exit 1
fi

GSD_RECIPE_DIR="$TARGET/.gsd-recipe"
LEDGER="$GSD_RECIPE_DIR/ledger.json"
SKILL_DEST="$TARGET/.cursor/skills/recipe-settle/SKILL.md"
SKILL_SRC="$SCRIPT_DIR/../templates/recipe-settle-SKILL.md"
COMPONENT="recipe-settle"

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
    read -r -p "Install recipe-settle skill (standalone, ahead of TASK-010) into $TARGET? [y/N] " reply
    case "$reply" in
      [yY]|[yY][eE][sS]) : ;;
      *) echo "recipe-settle installer: aborted, no consent given."; exit 0 ;;
    esac
  fi

  safe_copy "$SKILL_SRC" "$SKILL_DEST"
  ledger_record ".cursor/skills/recipe-settle/SKILL.md"

  echo "recipe-settle installer: staged. Files tracked in $LEDGER:"
  ledger_files | sed 's/^/  - /'
  echo
  echo "Invoke 'recipe-settle N' by name to run the real, scriptable CI check"
  echo "(gh pr checks / gh api .../check-runs, never fabricated) and then ask"
  echo "an explicit, non-skippable PO-accept y/n question in this conversation."
  echo "Only when both pass does it sync the 'settled' event via gsd-jira-sync —"
  echo "if CI is not green, no settled event is ever posted."
  echo "Run the CI check standalone any time: $0 --check-ci <owner/repo> <ref>"
  echo "Remove entirely: $0 --uninstall --target $TARGET"
}

uninstall() {
  echo "recipe-settle installer: removing tracked files for component '$COMPONENT'..."
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
  rmdir "$TARGET/.cursor/skills/recipe-settle" 2>/dev/null || true

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
  echo "recipe-settle installer: uninstall complete."
}

case "$MODE" in
  install) install ;;
  uninstall) uninstall ;;
esac
