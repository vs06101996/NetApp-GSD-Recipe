#!/usr/bin/env bash
# recipe-status.sh — read-only snapshot + next-step (TASK-060).
# Canonical copy also lives at .gsd-recipe/scripts/recipe-status.sh. Keep in sync.
# Detects generic artifacts only. Never mutates the repo.
#
# Usage:
#   recipe-status.sh [--target <repo_root>]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: recipe-status.sh [--target DIR]"
      exit 0
      ;;
    *) echo "recipe-status.sh: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  if [ -d "$SCRIPT_DIR/../../.git" ] && [ -f "$SCRIPT_DIR/../../bench/lib/recipe-status.sh" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  elif [ -d "$SCRIPT_DIR/../.." ] && [ -d "$(cd "$SCRIPT_DIR/../.." && pwd)/.git" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    TARGET="$(pwd)"
  fi
fi

TARGET="$(cd "$TARGET" && pwd)"

python3 - "$TARGET" <<'PY'
import json, os, re, subprocess, sys

target = sys.argv[1]

def exists(*parts):
    return os.path.exists(os.path.join(target, *parts))

def read(rel):
    p = os.path.join(target, rel)
    try:
        with open(p, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""

def yn(ok):
    return "yes" if ok else "no"

branch = "(unknown)"
try:
    branch = subprocess.check_output(
        ["git", "-C", target, "rev-parse", "--abbrev-ref", "HEAD"],
        stderr=subprocess.DEVNULL, text=True,
    ).strip() or "(unknown)"
except (OSError, subprocess.CalledProcessError):
    pass

state = read(".planning/STATE.md")
epic_m = re.search(r"(?m)^-\s*epic:\s*(\S+)", state)
epic = epic_m.group(1) if epic_m else "(none)"

phase_keys = []
in_table = False
for line in state.splitlines():
    if line.strip().startswith("## Phase tasks"):
        in_table = True
        continue
    if in_table:
        if line.startswith("## "):
            break
        if re.match(r"^\|\s*[-:| ]+\s*$", line) or line.startswith("| phase"):
            continue
        m = re.match(r"^\|\s*(\d+)\s*\|\s*([^|]+)\|", line)
        if m:
            phase_keys.append((m.group(1).strip(), m.group(2).strip()))

rm = read(".planning/ROADMAP.md")
ids = sorted(set(int(x) for x in re.findall(r"(?m)^## Phase (\d+)\b", rm)))

def phase_flag(n, kind):
    phases = os.path.join(target, ".planning", "phases")
    if not os.path.isdir(phases):
        return "no"
    needle = "PLAN" if kind == "plan" else "SUMMARY"
    for root, _dirs, files in os.walk(phases):
        base = os.path.basename(root)
        dir_hit = bool(re.match(rf"0*{n}[-_]", base) or re.match(rf"0*{n}$", base))
        for fn in files:
            if needle not in fn.upper() or not fn.upper().endswith(".MD"):
                continue
            rel = os.path.relpath(os.path.join(root, fn), phases).replace("\\", "/")
            if dir_hit or re.search(rf"(^|/)0*{n}[-_/]", rel) or re.search(rf"phase[-_]?0*{n}\b", rel, re.I):
                return "yes"
    return "no"

jira_check = "(no install-report)"
report = os.path.join(target, ".gsd-recipe", "install-report.json")
if os.path.isfile(report):
    try:
        jira_check = str(json.load(open(report)).get("jira_check", "(unset)"))
    except (OSError, json.JSONDecodeError):
        jira_check = "(unreadable)"

queue_n = 0
qpath = os.path.join(target, ".gsd-recipe", "sync-queue.jsonl")
if os.path.isfile(qpath):
    try:
        with open(qpath, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if row.get("status") in ("queued", "failed"):
                    queue_n += 1
    except OSError:
        pass

ledger_n = 0
last_sync = "(none)"
spath = os.path.join(target, ".gsd-recipe", "sync-ledger.jsonl")
if os.path.isfile(spath):
    last_line = ""
    try:
        with open(spath, encoding="utf-8") as f:
            for line in f:
                if line.strip():
                    last_line = line.strip()
                    ledger_n += 1
        if last_line:
            try:
                row = json.loads(last_line)
                ev = row.get("event_id") or row.get("event") or row.get("kind") or row.get("type")
                if not ev:
                    key_match = re.match(r"^gsd-recipe:([^:]+)", str(row.get("key", "")))
                    ev = key_match.group(1) if key_match else "event"
                target_name = row.get("target", "")
                result = row.get("result", "")
                outcome = "/".join(x for x in (target_name, result) if x)
                ts = row.get("ts") or row.get("at") or row.get("timestamp") or ""
                last_sync = f"{ev}{' -> ' + outcome if outcome else ''}{' at ' + ts if ts else ''}"
            except json.JSONDecodeError:
                last_sync = "(unreadable)"
    except OSError:
        last_sync = "(unreadable)"

print("=== Recipe status ===")
print()
print(f"Branch:          {branch}")
print(f"Recipe skills:   {yn(exists('.cursor', 'skills', 'recipe-onboard', 'SKILL.md'))}")
print(f"PRD:             {yn(exists('docs', 'PRD.md'))}  (docs/PRD.md)")
print(f"ROADMAP:         {yn(exists('.planning', 'ROADMAP.md'))}")
print(f"Knowledge:       {yn(exists('.knowledge', 'index.md'))}")
print(f"Epic:            {epic}")
if phase_keys:
    print("Phase tasks:")
    for pid, key in phase_keys:
        print(f"  phase {pid}: {key}")
else:
    print("Phase tasks:     (none)")
if ids:
    current_phase = next((n for n in ids if phase_flag(n, "summary") == "no"), ids[-1])
    print(f"Current phase:    {current_phase}")
    print("Phases:")
    for n in ids:
        print(f"  {n}: PLAN={phase_flag(n, 'plan')}  SUMMARY={phase_flag(n, 'summary')}")
else:
    print("Phases:          (none numbered in ROADMAP)")
print(f"Install Jira:    {jira_check}")
print(f"Verified:        {yn(exists('.gsd-recipe', 'INSTALL-VERIFIED.json'))}")
print(f"Sync queue:      {queue_n} pending")
print(f"Sync ledger:     {ledger_n} entries")
print(f"Last sync:       {last_sync}")
print()
print("Suggest next: recipe-start   (offers to run it)")
print("Catalog:      recipe-help")
PY

NEXT=""
if [ -x "$SCRIPT_DIR/recipe-next.sh" ]; then
  NEXT="$SCRIPT_DIR/recipe-next.sh"
elif [ -x "$SCRIPT_DIR/../../bench/lib/recipe-next.sh" ]; then
  NEXT="$SCRIPT_DIR/../../bench/lib/recipe-next.sh"
fi
if [ -n "$NEXT" ]; then
  echo
  bash "$NEXT" --target "$TARGET"
fi
