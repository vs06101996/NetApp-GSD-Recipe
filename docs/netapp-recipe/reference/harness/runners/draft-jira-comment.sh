#!/usr/bin/env bash
# Draft a Jira comment body for a GSD recipe lifecycle event.
# Does NOT post to Jira — use gsd-jira-sync skill + Atlassian MCP to post.
#
# Usage:
#   draft-jira-comment.sh <event_id> <issue_key> [--phase N] [--arm recipe] [--run run-01]
#
# Examples:
#   draft-jira-comment.sh plan_complete INS-12345 --phase 1
#   draft-jira-comment.sh execute_complete PROJ-456 --phase 2 --arm recipe --run run-01
#
# Event ids: see bench/recipe/trackers/jira-events.json
set -euo pipefail

EVENT="${1:?event_id required — see jira-events.json}"
ISSUE="${2:?issue_key required e.g. INS-12345}"
shift 2 || true

PHASE=""
ARM="recipe"
RUN_ID="run-01"
OPERATOR="${USER:-}"
ACTOR="agent"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase) PHASE="$2"; shift 2 ;;
    --arm) ARM="$2"; shift 2 ;;
    --run) RUN_ID="$2"; shift 2 ;;
    --actor) ACTOR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

HARNESS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
EVENTS="$HARNESS_ROOT/recipe/trackers/jira-events.json"
TEMPLATE_DIR="$HARNESS_ROOT/recipe/templates/jira-comments"

python3 - "$EVENT" "$ISSUE" "$PHASE" "$ARM" "$RUN_ID" "$OPERATOR" "$ACTOR" "$EVENTS" "$TEMPLATE_DIR" "$REPO_ROOT" <<'PY'
import json, pathlib, sys, re

event_id, issue, phase, arm, run_id, operator, actor, events_path, tpl_dir, repo_root = sys.argv[1:11]
events = json.loads(pathlib.Path(events_path).read_text())
match = next((e for e in events["events"] if e["id"] == event_id), None)
if not match:
    sys.exit(f"Unknown event_id: {event_id}")

tpl_name = match.get("template") or "_comment.template.md"
tpl_path = pathlib.Path(tpl_dir) / tpl_name
if not tpl_path.exists():
    tpl_path = pathlib.Path(tpl_dir) / "_comment.template.md"
if not tpl_path.exists():
    sys.exit(f"Template missing: {tpl_path}")

body = tpl_path.read_text()
phase_padded = phase.zfill(2) if phase.isdigit() else phase
phase_dir = f"{phase_padded}-*" if phase else ""

def read_glob(pattern):
    paths = sorted(pathlib.Path(repo_root).glob(pattern))
    if not paths:
        return "(not found)"
    lines = []
    for p in paths[:5]:
        lines.append(f"- `{p.relative_to(repo_root)}`")
    return "\n".join(lines)

def summarize_plan():
    if not phase:
        return "(specify --phase)"
    pattern = f".planning/phases/{phase_padded}-*/*-{phase_padded}-*-PLAN.md"
    paths = list(pathlib.Path(repo_root).glob(pattern))
    if not paths:
        pattern2 = f".planning/phases/*/*-{phase_padded}-*-PLAN.md"
        paths = list(pathlib.Path(repo_root).glob(pattern2))
    if not paths:
        return "(PLAN.md not found yet)"
    out = []
    for p in paths:
        text = p.read_text(errors="replace")
        tasks = re.findall(r"^### Task", text, re.M)
        out.append(f"- `{p.relative_to(repo_root)}` ({len(tasks)} task headers)")
    return "\n".join(out) or "(empty)"

def summarize_context():
    if not phase:
        return "(specify --phase)"
    for pat in [f".planning/phases/{phase_padded}-*/{phase_padded}-CONTEXT.md",
                f".planning/phases/*/{phase_padded}-CONTEXT.md"]:
        paths = list(pathlib.Path(repo_root).glob(pat))
        if paths:
            lines = paths[0].read_text(errors="replace").splitlines()[:12]
            return "\n".join(f"> {l}" for l in lines if l.strip())
    return "(CONTEXT.md not found)"

replacements = {
    "{{EVENT}}": event_id,
    "{{ISSUE_KEY}}": issue,
    "{{PHASE}}": phase or "—",
    "{{PHASE_DIR}}": phase_dir or "—",
    "{{ARM}}": arm,
    "{{RUN_ID}}": run_id,
    "{{OPERATOR}}": operator,
    "{{ACTOR}}": actor,
    "{{PLAN_PATHS}}": summarize_plan(),
    "{{TASK_SUMMARY}}": summarize_plan(),
    "{{CONTEXT_SUMMARY}}": summarize_context(),
    "{{VERIFY_SUMMARY}}": "(fill from PLAN.md must-haves)",
    "{{REVIEW_CONCERNS}}": "(fill from PLAN.md expected review section)",
    "{{REVISION_REASON}}": "(describe revision)",
    "{{WAVE}}": "—",
    "{{WAVE_SUMMARY}}": "(wave tasks completed)",
    "{{COMMIT_SHAS}}": "$(git log --oneline -5 2>/dev/null || echo 'n/a')",
    "{{DELIVERY_SUMMARY}}": "(from SUMMARY.md)",
    "{{VERIFY_OUTCOME}}": "(pass/fail/partial)",
    "{{OPEN_ITEMS}}": "(none)",
    "{{REVIEW_PATH}}": read_glob(f".planning/phases/*/*-{phase_padded}-REVIEW.md") if phase else "(n/a)",
    "{{REVIEW_SUMMARY}}": "(from REVIEW.md)",
    "{{GATES_STATUS}}": "(security/perf if run)",
    "{{LEARNING_SUMMARY}}": "(from extract-learnings)",
    "{{PATTERNS_PATH}}": ".sdlc/patterns/repo/",
    "{{GRADER_RESULT}}": "(from grade.json)",
    "{{PR_LINK}}": "(branch/PR URL)",
    "{{REOPEN_REASON}}": "(why reopened)",
    "{{NEXT_STEPS}}": "(planned rework)",
}

for k, v in replacements.items():
    body = body.replace(k, v)

# Expand shell-style git one-liner placeholder if left
if "{{COMMIT_SHAS}}" in body or "$(git log" in body:
    import subprocess
    try:
        log = subprocess.check_output(
            ["git", "-C", repo_root, "log", "--oneline", "-5"], text=True, stderr=subprocess.DEVNULL
        ).strip()
    except Exception:
        log = "n/a"
    body = body.replace("$(git log --oneline -5 2>/dev/null || echo 'n/a')", log or "n/a")

print(body)
stamp = match.get("stamp")
if stamp:
    print("\n---")
    print(f"# Stamp (after Jira post succeeds):")
    print(f"# Stamp (after Jira post): emit-stamp.sh {arm} {run_id} {stamp['status']} {stamp['step']} {issue} {actor} jira")
PY
