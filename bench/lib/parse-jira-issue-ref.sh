#!/usr/bin/env bash
# Parse a Jira issue key or browse URL into KEY + optional browse URL.
# Used by recipe-prd-intake / recipe-onboard (Jira-ticket PRD source).
#
# Usage: parse-jira-issue-ref.sh <ref>
# Prints:
#   key=PROJ-123
#   url=https://host/browse/PROJ-123   (empty if only a key was given)
# Exits 1 if ref is not a Jira key or Jira issue URL.
set -euo pipefail

REF="${1:-}"
if [ -z "$REF" ]; then
  echo "parse-jira-issue-ref.sh: missing ref" >&2
  exit 2
fi

python3 - "$REF" <<'PY'
import re, sys, urllib.parse

raw = sys.argv[1].strip()
key_re = re.compile(r"\b([A-Z][A-Z0-9]+-\d+)\b")

def emit(key, url=""):
    print(f"key={key}")
    print(f"url={url}")

if re.fullmatch(r"[A-Z][A-Z0-9]+-\d+", raw):
    emit(raw)
    raise SystemExit(0)

try:
    parsed = urllib.parse.urlparse(raw)
except Exception:
    parsed = None

if parsed and parsed.scheme in ("http", "https") and parsed.netloc:
    qs = urllib.parse.parse_qs(parsed.query)
    selected = (qs.get("selectedIssue") or qs.get("issueKey") or [None])[0]
    m = key_re.search(parsed.path or "")
    if not m and selected:
        m = key_re.search(selected)
    if m:
        key = m.group(1)
        url = f"{parsed.scheme}://{parsed.netloc}/browse/{key}"
        emit(key, url)
        raise SystemExit(0)

print("parse-jira-issue-ref.sh: not a Jira issue key or browse URL", file=sys.stderr)
raise SystemExit(1)
PY
