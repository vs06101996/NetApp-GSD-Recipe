#!/usr/bin/env bash
set -euo pipefail

readonly REPOSITORY="vs06101996/NetApp-GSD-Recipe"
readonly ALLOWED_LABELS="bug enhancement question"
readonly INSTALLED_RECIPE_REVISION="__RECIPE_REVISION__"

usage() {
  cat <<'EOF'
Usage: report-recipe-issue.sh --description TEXT [--title TITLE]
       [--expected TEXT] [--command TEXT] [--context TEXT]
       [--label bug|enhancement|question] [--dry-run] [--confirmed]
       [--allow-duplicate]

   or: report-recipe-issue.sh --title TITLE --body-file PATH
       [--label bug|enhancement|question] [--dry-run] [--confirmed]
       [--allow-duplicate]
EOF
}

title=""
body_file=""
description=""
expected="unknown"
invoked_command="unknown"
context="none"
label="bug"
dry_run=false
confirmed=false
allow_duplicate=false

while (($#)); do
  case "$1" in
    --title) title="${2:-}"; shift 2 ;;
    --body-file) body_file="${2:-}"; shift 2 ;;
    --description) description="${2:-}"; shift 2 ;;
    --expected) expected="${2:-}"; shift 2 ;;
    --command) invoked_command="${2:-}"; shift 2 ;;
    --context) context="${2:-}"; shift 2 ;;
    --label) label="${2:-}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --confirmed) confirmed=true; shift ;;
    --allow-duplicate) allow_duplicate=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -n "$body_file" && -n "$description" ]]; then
  echo "error: use either --body-file or --description, not both" >&2
  exit 2
fi
if [[ -n "$body_file" ]]; then
  [[ -f "$body_file" ]] || { echo "error: --body-file must name a readable file" >&2; exit 2; }
else
  [[ -n "$description" ]] || {
    echo "error: --description is required when --body-file is absent" >&2
    exit 2
  }
fi
case " $ALLOWED_LABELS " in
  *" $label "*) ;;
  *) echo "error: --label must be bug, enhancement, or question" >&2; exit 2 ;;
esac

draft_body="$(mktemp)"
sanitized_body="$(mktemp)"
trap 'rm -f "$draft_body" "$sanitized_body"' EXIT

if [[ -n "$body_file" ]]; then
  cp "$body_file" "$draft_body"
else
  if [[ -z "$title" ]]; then
    title="$(python3 - "$description" <<'PY'
import re
import sys

print(re.sub(r"\s+", " ", sys.argv[1]).strip()[:120].rstrip())
PY
)"
  fi
  repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  template="$repo_root/.gsd-recipe/templates/recipe-issue-body.template.md"
  [[ -f "$template" ]] || { echo "error: report body template is missing: $template" >&2; exit 1; }
  if [[ "$INSTALLED_RECIPE_REVISION" != "__RECIPE_REVISION__" ]]; then
    recipe_revision="$INSTALLED_RECIPE_REVISION"
  else
    recipe_revision="$(git -C "$repo_root" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
  fi
  platform="$(uname -srm 2>/dev/null || printf 'unknown')"
  python3 - "$template" "$draft_body" "$description" "$expected" "$recipe_revision" "$platform" "$invoked_command" "$context" <<'PY'
import sys

template_path, destination, actual, expected, revision, platform, command, context = sys.argv[1:]
body = open(template_path, encoding="utf-8").read()
values = {
    "ACTUAL": actual,
    "EXPECTED": expected,
    "REPRODUCTION": "1. Invoke the command shown in Safe diagnostics.\n2. Observe the behavior above.",
    "RECIPE_REVISION": revision,
    "PLATFORM": platform,
    "COMMAND": command,
    "CONTEXT": context,
}
for name, value in values.items():
    body = body.replace("{{" + name + "}}", value)
open(destination, "w", encoding="utf-8").write(body)
PY
fi

[[ -n "$title" ]] || { echo "error: --title is required for --body-file reports" >&2; exit 2; }

title="$(python3 - "$draft_body" "$sanitized_body" "$title" <<'PY'
import os
import re
import sys

source, destination, title = sys.argv[1:]
text = open(source, encoding="utf-8").read()

patterns = [
    (r"(?i)(authorization\s*:\s*(?:bearer|basic)\s+)\S+", r"\1[REDACTED]"),
    (r"(?i)((?:password|passwd|token|api[_-]?key|secret)\s*[=:]\s*)\S+", r"\1[REDACTED]"),
    (r"\b(?:ghp_[A-Za-z0-9_]{16,}|github_pat_[A-Za-z0-9_]{16,}|glpat-[A-Za-z0-9_-]{16,})\b", "[REDACTED]"),
    (r"\bAKIA[0-9A-Z]{16}\b", "[REDACTED]"),
]

def sanitize(value):
    home = os.path.expanduser("~")
    if home and home != "/":
        value = value.replace(home, "~")
    for pattern, replacement in patterns:
        value = re.sub(pattern, replacement, value)
    value = re.sub(r"(?<![A-Za-z0-9:])/(?:Users|home)/[^/\s]+/", "~/", value)
    value = re.sub(
        r"(?<![A-Za-z0-9:])/(?:private/tmp|tmp|var/folders|Volumes)/\S+",
        "[LOCAL_PATH]",
        value,
    )
    value = re.sub(r"(?i)\b[A-Z]:\\Users\\[^\\\s]+\\\S+", "[LOCAL_PATH]", value)
    return value

open(destination, "w", encoding="utf-8").write(sanitize(text))
print(sanitize(title))
PY
)"

printf 'Repository: %s\nLabel: %s\nTitle: %s\n\n' "$REPOSITORY" "$label" "$title"
cat "$sanitized_body"
printf '\n'

if "$dry_run"; then
  printf '\nDry run: no GitHub API calls were made.\n'
  exit 0
fi

"$confirmed" || {
  echo "error: refusing to create an issue without --confirmed after operator preview" >&2
  exit 2
}

command -v gh >/dev/null 2>&1 || {
  echo "error: GitHub CLI (gh) is required" >&2
  exit 1
}
gh auth status >/dev/null

duplicates="$(
  gh issue list \
    --repo "$REPOSITORY" \
    --state all \
    --search "$title in:title" \
    --limit 10 \
    --json number,title,url,state
)"

if ! "$allow_duplicate"; then
  exact_duplicate="$(
    python3 - "$title" "$duplicates" <<'PY'
import json
import sys

needle = " ".join(sys.argv[1].casefold().split())
for issue in json.loads(sys.argv[2]):
    candidate = " ".join(issue.get("title", "").casefold().split())
    if candidate == needle:
        print(issue.get("url", ""))
        break
PY
  )"
  if [[ -n "$exact_duplicate" ]]; then
    echo "error: an issue with the same normalized title already exists: $exact_duplicate" >&2
    echo "review it first, or rerun with --allow-duplicate after explicit confirmation" >&2
    exit 3
  fi
fi

gh issue create \
  --repo "$REPOSITORY" \
  --title "$title" \
  --body-file "$sanitized_body" \
  --label "$label"
