#!/usr/bin/env bash
# recipe-next.sh — repo-agnostic "what should I type next?" (TASK-056).
# Canonical copy also lives at .gsd-recipe/scripts/recipe-next.sh so it is
# copied onto external targets with the recipe tree. Keep the two files in
# sync. Read-only. Detects generic artifacts only. Never mutates the repo.
#
# Usage:
#   recipe-next.sh [--target <repo_root>]
#   recipe-next.sh --id [--target <repo_root>]   # one token: ONBOARD|BOOTSTRAP|PLAN|…
#
# Friendly stdout is for humans and recipe-start / recipe-help --next.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
ID_ONLY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --id) ID_ONLY=1; shift ;;
    -h|--help)
      echo "Usage: recipe-next.sh [--target DIR] [--id]"
      exit 0
      ;;
    *) echo "recipe-next.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  if [ -d "$SCRIPT_DIR/../../.git" ] && [ -f "$SCRIPT_DIR/../../bench/lib/recipe-next.sh" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  elif [ -d "$SCRIPT_DIR/../.." ] && [ -d "$(cd "$SCRIPT_DIR/../.." && pwd)/.git" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    TARGET="$(pwd)"
  fi
fi

TARGET="$(cd "$TARGET" && pwd)"

python3 - "$TARGET" "$ID_ONLY" <<'PY'
import os, re, sys

target = sys.argv[1]
id_only = sys.argv[2] == "1"

def exists(*parts):
    return os.path.exists(os.path.join(target, *parts))

def read(rel):
    p = os.path.join(target, rel)
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""

skill_onboard = exists(".cursor", "skills", "recipe-onboard", "SKILL.md")
prd = exists("docs", "PRD.md")
roadmap = exists(".planning", "ROADMAP.md")
state = read(".planning/STATE.md")
epic = bool(re.search(r"(?m)^-\s*epic:\s*\S+", state))
knowledge = exists(".knowledge", "index.md")

phase_n = None
rm = read(".planning/ROADMAP.md")
ids = [int(x) for x in re.findall(r"(?m)^## Phase (\d+)\b", rm)]
ids = sorted(set(ids))

def phase_has_plan(n):
    phases = os.path.join(target, ".planning", "phases")
    if not os.path.isdir(phases):
        return False
    for root, _dirs, files in os.walk(phases):
        for fn in files:
            if fn.endswith("PLAN.md") or fn == "PLAN.md":
                # match padded or unpadded phase dirs
                if re.search(rf"{n:02d}-|{n}-|phase.?{n}", root + fn, re.I):
                    return True
                if re.match(rf"{n:02d}-.+PLAN\.md$", fn) or re.match(rf"{n}-.+PLAN\.md$", fn):
                    return True
    return False

def phase_has_summary(n):
    phases = os.path.join(target, ".planning", "phases")
    if not os.path.isdir(phases):
        return False
    for root, _dirs, files in os.walk(phases):
        for fn in files:
            if "SUMMARY" in fn.upper() and fn.endswith(".md"):
                if re.search(rf"{n:02d}-|{n}-", root + fn):
                    return True
    return False

step_id = "ONBOARD"
cmd = "recipe-onboard"
why = "No PRD or planning cycle yet."
how = """  recipe-onboard
  (no file yet: Agent will ask you to paste or describe the work)"""

if not skill_onboard and not exists(".gsd-recipe", "config.json"):
    step_id = "INSTALL"
    cmd = "(install from recipe source)"
    why = "Recipe skills are not in this repo yet."
    how = """  From the NetApp GSD Recipe clone (gsd-benchmark):
  ./bench/runners/install-recipe-to-target.sh --target THIS_REPO --yes

  Then in Cursor Agent:
  recipe-start"""
elif not prd:
    step_id = "ONBOARD"
    cmd = "recipe-onboard"
    why = "There is no docs/PRD.md yet."
    how = """  recipe-onboard
  (no file yet: Agent will ask you to paste or describe the work)"""
elif not roadmap:
    step_id = "ONBOARD"
    cmd = "recipe-onboard"
    why = "You have a PRD, but no .planning/ROADMAP.md yet."
    how = "  recipe-onboard"
elif not epic:
    step_id = "ONBOARD"
    cmd = "recipe-onboard"
    why = "Planning exists, but no Jira Epic is linked in .planning/STATE.md yet."
    how = "  recipe-onboard"
elif not knowledge:
    step_id = "BOOTSTRAP"
    cmd = "recipe-bootstrap-knowledge"
    why = "Onboarding looks done; next is repo context for planning."
    how = "  recipe-bootstrap-knowledge"
else:
    # first phase missing PLAN, else first with PLAN but no SUMMARY, else verify
    missing_plan = [n for n in ids if not phase_has_plan(n)]
    missing_run = [n for n in ids if phase_has_plan(n) and not phase_has_summary(n)]
    if missing_plan:
        n = missing_plan[0]
        step_id = "PLAN"
        cmd = f"recipe-plan-phase {n}"
        why = f"Phase {n} has no PLAN.md yet."
        how = f"  recipe-plan-phase {n}"
    elif missing_run:
        n = missing_run[0]
        step_id = "RUN"
        cmd = f"recipe-run-phase {n}"
        why = f"Phase {n} is planned; next is execute."
        how = f"  recipe-run-phase {n}"
    elif ids:
        n = ids[-1]
        step_id = "VERIFY"
        cmd = f"recipe-verify-feature {n}"
        why = "Plans look executed. Next is verify, then review-ship, then settle."
        how = f"""  recipe-verify-feature {n}
  recipe-review-ship {n}
  recipe-settle {n}"""
    else:
        step_id = "PLAN"
        cmd = "recipe-plan-phase 1"
        why = "ROADMAP has no numbered phases yet; start at phase 1 after onboard."
        how = "  recipe-plan-phase 1"

if id_only:
    print(step_id)
    sys.exit(0)

print("=== Recipe next step ===")
print()
print("Why: " + why)
print()
print("Type this in Cursor Agent:")
print()
print(how)
print()
print(f"Command: {cmd}")
print()
print("This is for files on your current git checkout (branch).")
print("recipe-start may offer to run the command after Yes.")
print("recipe-help --next only prints it.")
print("Catalog:  recipe-help")
PY
