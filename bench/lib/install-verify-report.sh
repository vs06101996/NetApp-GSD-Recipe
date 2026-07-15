#!/usr/bin/env bash
# Report writer for the recipe-install-verify skill (TASK-023).
#
# Per docs/netapp-recipe/lld/INSTALL-LLD.md Step 5's own table ("Outputs |
# `INSTALL-VERIFIED` marker in `.gsd-recipe/install-report.json` or operator
# sign-off"), the marker lives INSIDE the same install-report.json that
# .gsd-recipe/scripts/install.sh already writes (github_check, jira_check,
# prereqs, graphify_config_enabled, installed_at, last_install_at) — this
# script only ever ADDS keys to that file, additive-only, never touching or
# overwriting install.sh's own fields. (install.sh's own --verify separately
# writes a sibling file, .gsd-recipe/INSTALL-VERIFIED.json, when its narrower
# bash-checkable subset passes — that file is install.sh's own artifact and
# is never read or written by this script either. Two markers, two owners,
# no collision: this one is the full 10-item checklist's marker, scoped
# exactly to the wording in the LLD's own Step 5 table.)
#
# Contract (carried in-code — no separate spec doc):
#   Report file : .gsd-recipe/install-report.json (same file install.sh owns)
#   New keys    : "install_verified" (bool, top-level — literal LLD wording)
#                 "recipe_install_verify": {
#                   "last_run_at": ISO8601,
#                   "items": {
#                     "<1-10>": {"name": str, "status": "pass"|"warn"|"fail",
#                                "detail": str, "checked_at": ISO8601}
#                   },
#                   "install_verified": bool  (mirrors the top-level key)
#                 }
#   Blocking rule (INSTALL-LLD.md Step 5 "Failure handling": "Block p1 usage
#   until checks 1-7 pass; 8-10 may warn-only") : install_verified is true
#   iff items "1".."7" are ALL recorded with status "pass". Items 8-10 never
#   affect the marker either way — they can be pass/warn/fail and
#   install_verified is computed purely from 1-7. Unrecorded items 1-7 count
#   as not-pass (never assume success for a check that hasn't run yet).
#
# Usage:
#   install-verify-report.sh record <item_number> <item_name> <pass|warn|fail> [--detail TEXT] [--report PATH]
#   install-verify-report.sh summary [--report PATH]
#
# Examples:
#   bench/lib/install-verify-report.sh record 5 "Templates present" pass --detail "all 6 templates found"
#   bench/lib/install-verify-report.sh summary --report /tmp/scratch/.gsd-recipe/install-report.json
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DEFAULT_REPORT="$REPO_ROOT/.gsd-recipe/install-report.json"

usage() {
  cat >&2 <<'EOF'
Usage:
  install-verify-report.sh record <item_number> <item_name> <pass|warn|fail> [--detail TEXT] [--report PATH]
  install-verify-report.sh summary [--report PATH]
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  record)
    [ $# -ge 3 ] || usage
    ITEM_NUMBER="$1"; ITEM_NAME="$2"; STATUS="$3"; shift 3
    DETAIL=""; REPORT="$DEFAULT_REPORT"
    while [ $# -gt 0 ]; do
      case "$1" in
        --detail) DETAIL="${2:?--detail requires a value}"; shift 2 ;;
        --report) REPORT="${2:?--report requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    case "$ITEM_NUMBER" in
      1|2|3|4|5|6|7|8|9|10) ;;
      *) echo "ERROR: item_number must be 1-10, got '$ITEM_NUMBER'" >&2; exit 2 ;;
    esac
    case "$STATUS" in
      pass|warn|fail) ;;
      *) echo "ERROR: status must be 'pass', 'warn', or 'fail', got '$STATUS'" >&2; exit 2 ;;
    esac
    mkdir -p "$(dirname "$REPORT")"
    ITEM_NUMBER="$ITEM_NUMBER" ITEM_NAME="$ITEM_NAME" STATUS="$STATUS" DETAIL="$DETAIL" \
    REPORT="$REPORT" python3 - <<'PY'
import json, os, sys, datetime

path = os.environ["REPORT"]
item_number = os.environ["ITEM_NUMBER"]
item_name = os.environ["ITEM_NAME"]
status = os.environ["STATUS"]
detail = os.environ["DETAIL"]
now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

data = {}
if os.path.exists(path):
    with open(path) as f:
        content = f.read().strip()
        if content:
            data = json.loads(content)

riv = data.setdefault("recipe_install_verify", {})
items = riv.setdefault("items", {})
items[item_number] = {
    "name": item_name,
    "status": status,
    "detail": detail,
    "checked_at": now,
}
riv["last_run_at"] = now

blocking = [str(n) for n in range(1, 8)]  # items 1-7 per Step 5's failure-handling rule
install_verified = all(items.get(n, {}).get("status") == "pass" for n in blocking)
riv["install_verified"] = install_verified
data["install_verified"] = install_verified

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")

print(f"recorded item {item_number} ({item_name}) = {status}; install_verified now {install_verified}")
PY
    ;;

  summary)
    REPORT="$DEFAULT_REPORT"
    while [ $# -gt 0 ]; do
      case "$1" in
        --report) REPORT="${2:?--report requires a value}"; shift 2 ;;
        *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
      esac
    done
    if [ ! -f "$REPORT" ]; then
      echo "(no report recorded yet at $REPORT)"
      exit 1
    fi
    REPORT="$REPORT" python3 - <<'PY'
import json, os

path = os.environ["REPORT"]
with open(path) as f:
    data = json.load(f)
riv = data.get("recipe_install_verify", {})
items = riv.get("items", {})
for n in [str(x) for x in range(1, 11)]:
    entry = items.get(n)
    if entry:
        print(f"  {n}. {entry['name']}: {entry['status']} ({entry.get('detail', '')})")
    else:
        print(f"  {n}. (not checked)")
print(f"install_verified: {riv.get('install_verified', False)}")
PY
    ;;

  *)
    usage
    ;;
esac
