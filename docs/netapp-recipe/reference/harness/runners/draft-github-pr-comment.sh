#!/usr/bin/env bash
# Draft a GitHub PR comment body for a GSD recipe lifecycle event.
# Does NOT post to GitHub — use `gh pr comment` after reviewing output.
#
# Usage:
#   draft-github-pr-comment.sh <event_id> --pr <number> --phase <N> [--wave <W>] [--issue <KEY>] [--arm recipe] [--run run-01]
set -euo pipefail

EVENT="${1:-}"
if [[ -z "${EVENT}" ]]; then
  echo "event_id required (see bench/recipe/trackers/github-events.json)" >&2
  exit 2
fi
shift || true

PR_NUMBER=""
PHASE=""
WAVE=""
ISSUE_KEY=""
ARM="recipe"
RUN_ID="run-01"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr) PR_NUMBER="${2:-}"; shift 2 ;;
    --phase) PHASE="${2:-}"; shift 2 ;;
    --wave) WAVE="${2:-}"; shift 2 ;;
    --issue) ISSUE_KEY="${2:-}"; shift 2 ;;
    --arm) ARM="${2:-}"; shift 2 ;;
    --run) RUN_ID="${2:-}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "${PR_NUMBER}" || -z "${PHASE}" ]]; then
  echo "--pr and --phase are required" >&2
  exit 2
fi

HARNESS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EVENTS="$HARNESS_ROOT/recipe/trackers/github-events.json"
TEMPLATE_DIR="$HARNESS_ROOT/recipe/templates/github-pr-comments"

python3 - "$EVENT" "$PR_NUMBER" "$PHASE" "$WAVE" "$ISSUE_KEY" "$ARM" "$RUN_ID" "$EVENTS" "$TEMPLATE_DIR" "$REPO_ROOT" <<'PY'
import json, pathlib, subprocess, sys

event_id, pr_number, phase, wave, issue_key, arm, run_id, events_path, tpl_dir, repo_root = sys.argv[1:11]
events = json.loads(pathlib.Path(events_path).read_text())
match = next((e for e in events["events"] if e["id"] == event_id), None)
if not match:
    print(f"Unknown event_id: {event_id}", file=sys.stderr)
    sys.exit(1)

tpl_name = match.get("template") or "_comment.template.md"
tpl_path = pathlib.Path(tpl_dir) / tpl_name
if not tpl_path.exists():
    tpl_path = pathlib.Path(tpl_dir) / "_comment.template.md"
if not tpl_path.exists():
    print(f"Template missing: {tpl_path}", file=sys.stderr)
    sys.exit(1)

def git_log():
    try:
        return subprocess.check_output(["git", "-C", repo_root, "log", "--oneline", "-5"], text=True).strip()
    except Exception:
        return "n/a"

issue = issue_key or "TBD-ISSUE"
short_sha = "HEAD"
idem = f"gsd-recipe:{event_id}:phase={phase}"
if wave:
    idem += f":wave={wave}"
idem += f":commit={short_sha}:issue={issue}"

replacements = {
    "{{EVENT}}": event_id,
    "{{PR_NUMBER}}": pr_number,
    "{{PHASE}}": phase,
    "{{WAVE}}": wave or "—",
    "{{ISSUE_KEY}}": issue,
    "{{ARM}}": arm,
    "{{RUN_ID}}": run_id,
    "{{WAVE_SUMMARY}}": "(fill wave summary)",
    "{{DELIVERY_SUMMARY}}": "(fill delivery summary from SUMMARY.md)",
    "{{REVIEW_SUMMARY}}": "(fill review summary from REVIEW.md)",
    "{{REVIEW_PATH}}": f".planning/phases/*/*-{phase}-*-REVIEW.md",
    "{{SUMMARY_PATHS}}": f".planning/phases/*/*-{phase}-*-SUMMARY.md",
    "{{CI_STATUS}}": "(fill CI status)",
    "{{COMMIT_SHAS}}": git_log(),
    "{{IDEMPOTENCY_KEY}}": idem,
}

body = tpl_path.read_text()
for key, value in replacements.items():
    body = body.replace(key, value)

print(body)
PY
