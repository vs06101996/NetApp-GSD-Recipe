#!/usr/bin/env bash
# Draft a Jira Epic body (summary + description) from docs/PRD.md, for the
# recipe-create-epic skill (TASK-033). Does NOT call createJiraIssue — only
# an agent turn has Atlassian MCP tool-calling access, same split every other
# draft-*.sh script in this repo already uses (draft-jira-comment.sh,
# draft-github-pr-comment.sh).
#
# Usage:
#   draft-jira-epic.sh [--prd PATH] [--project KEY]
#
# Output: a single JSON object on stdout -- {"summary": "...", "description": "..."}
#   summary     : the PRD's first '# ' (H1) heading, trimmed, truncated to
#                 Jira's 255-char summary limit with a trailing '…' marker if
#                 longer. Falls back to "Untitled PRD" (+ a stderr warning)
#                 if no H1 is found -- never hard-fails on that account.
#   description : every real '## '-level section from the PRD (Problem /
#                 Goals / Non-Goals / Requirements / Out of Scope / Open
#                 Questions -- see .templates/PRD.template.md), concatenated
#                 in file order as plain markdown (no ADF), same simple-text
#                 approach draft-jira-comment.sh already uses.
#
# --project is accepted (forwarded by the recipe-create-epic skill once it
# has resolved a project key) but does not change the drafted body -- an
# Epic's summary/description has no per-project shape difference here, only
# the createJiraIssue call itself (agent-mediated, not this script's job)
# needs the project key.
#
# Fails non-zero (actionable stderr message) only when the PRD file itself
# doesn't exist -- there is nothing to draft from. Every other condition
# (missing H1, missing/empty sections) degrades gracefully and still exits 0
# with a usable body.
#
# Examples:
#   bench/runners/draft-jira-epic.sh
#   bench/runners/draft-jira-epic.sh --prd docs/PRD.md --project PROJ
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PRD_PATH="$REPO_ROOT/docs/PRD.md"
PROJECT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --prd) PRD_PATH="${2:?--prd requires a value}"; shift 2 ;;
    --project) PROJECT="${2:?--project requires a value}"; shift 2 ;;
    *) echo "ERROR: unknown flag '$1'" >&2; exit 2 ;;
  esac
done

if [ ! -f "$PRD_PATH" ]; then
  echo "ERROR: PRD file not found at $PRD_PATH -- run 'recipe-prd-intake' first to create it (nothing to draft an Epic from)." >&2
  exit 1
fi

PRD_PATH="$PRD_PATH" PROJECT="$PROJECT" python3 - <<'PY'
import json
import os
import re
import sys

PRD_PATH = os.environ["PRD_PATH"]

text = open(PRD_PATH, errors="replace").read()
lines = text.splitlines()

H1 = re.compile(r"^#\s+(.+?)\s*$")
H2 = re.compile(r"^##\s+(.+?)\s*$")
MAX_SUMMARY_LEN = 255

summary = None
for ln in lines:
    m = H1.match(ln)
    if m:
        summary = m.group(1).strip()
        break

if not summary:
    print(f"WARNING: no top-level '# ' heading found in {PRD_PATH} -- using placeholder summary", file=sys.stderr)
    summary = "Untitled PRD"
elif len(summary) > MAX_SUMMARY_LEN:
    summary = summary[: MAX_SUMMARY_LEN - 1].rstrip() + "\u2026"

sections = []
current_heading = None
current_lines = []
for ln in lines:
    m = H2.match(ln)
    if m:
        if current_heading is not None:
            sections.append((current_heading, "\n".join(current_lines).strip()))
        current_heading = m.group(1).strip()
        current_lines = []
    elif current_heading is not None:
        current_lines.append(ln)
if current_heading is not None:
    sections.append((current_heading, "\n".join(current_lines).strip()))

if sections:
    description = "\n\n".join(f"## {heading}\n\n{body}".rstrip() for heading, body in sections)
else:
    print(f"WARNING: no '## ' sections found in {PRD_PATH} -- description will be a placeholder", file=sys.stderr)
    description = "(no '## ' sections found in PRD)"

print(json.dumps({"summary": summary, "description": description}))
PY
