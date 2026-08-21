#!/usr/bin/env bash
# generate-recipe-help.sh — emit docs/RECIPE-COMMANDS.md from capability.json
# catalog, bench/runners headers, and a curated native GSD summary table.
#
# Usage:
#   bench/lib/generate-recipe-help.sh [--out PATH]
#
# Default output: docs/RECIPE-COMMANDS.md under repo root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
OUT="$REPO_ROOT/docs/RECIPE-COMMANDS.md"

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 [--out PATH]" >&2
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

TMP_CAP="$(mktemp)"
trap 'rm -f "$TMP_CAP"' EXIT

"$REPO_ROOT/bench/lib/capability-schema.sh" generate-capability \
  --target "$REPO_ROOT" --out "$TMP_CAP" >/dev/null

REPO_ROOT="$REPO_ROOT" OUT="$OUT" CAP="$TMP_CAP" python3 <<'PY'
import json, os, re, glob
from datetime import datetime, timezone

repo = os.environ["REPO_ROOT"]
out_path = os.environ["OUT"]
cap_path = os.environ["CAP"]

with open(cap_path) as f:
    caps = {c["id"]: c for c in json.load(f)["capabilities"]}

def cap_by_invoke(name):
    for c in caps.values():
        if c.get("invoke_name") == name:
            return c
    return None

def _rel(inst):
    # Installer paths in the catalog are already repo-root-relative (e.g.
    # ".gsd-recipe/scripts/install-foo.sh") — do NOT call str.lstrip("./")
    # here, it strips a *character set*, not a prefix, and silently mangles
    # the leading "." into "gsd-recipe/..." (a path that never exists).
    return inst[2:] if inst.startswith("./") else inst

def installer_exists(entry):
    inst = entry.get("installer")
    if not inst:
        return True
    return os.path.isfile(os.path.join(repo, _rel(inst)))

def status_for(entry):
    if entry.get("invoke_name") in ("recipe-new-project", "recipe-onboard", "recipe-start", "recipe-status"):
        if not installer_exists(entry):
            return "planned"
    inst = entry.get("installer")
    if inst and not os.path.isfile(os.path.join(repo, _rel(inst))):
        return "planned"
    return "built"

WORKFLOW_GROUPS = [
    ("Install and verify", [
        "recipe-start", "recipe-status", "recipe-install", "recipe-validate-tokens", "recipe-install-verify",
    ]),
    ("Onboard", [
        "recipe-onboard", "recipe-prd-intake", "recipe-new-project",
        "recipe-create-epic", "recipe-create-phase-tasks",
    ]),
    ("Knowledge bootstrap", ["recipe-bootstrap-knowledge"]),
    ("Plan and run", [
        "recipe-plan-phase", "recipe-run-phase", "recipe-run-phases",
    ]),
    ("Verify and ship", [
        "recipe-verify-feature", "recipe-review-ship", "recipe-settle",
    ]),
    ("Sync and tracker", [
        "tracker-sync", "gsd-jira-sync", "recipe-sync", "recipe-pr-comment",
    ]),
    ("Observer", ["recipe-observe", "fotw-observer-bootstrap"]),
    ("Help", ["recipe-help"]),
]

INJECTED = [
    ("recipe-planning-policy", "Injected into gsd-planner via agent_skills (not invoke-by-name)"),
]

GSD_COMMANDS = [
    ("gsd-new-project", "Initialize project: PROJECT.md, ROADMAP.md, STATE.md"),
    ("gsd-import", "Import external plans with conflict detection"),
    ("gsd-plan-phase N", "Create phase PLAN.md with verification loop"),
    ("gsd-execute-phase N [--wave W]", "Execute phase plans in waves"),
    ("gsd-verify-work N", "Conversational UAT for phase N"),
    ("gsd-audit-milestone", "Gap analysis vs ROADMAP DoD (informational)"),
    ("gsd-audit-uat", "Cross-phase UAT audit (warn-and-skip if N/A)"),
    ("gsd-code-review N", "Cross-AI code review for phase N"),
    ("gsd-ship N [--draft]", "Open PR for phase N"),
    ("/gsd-map-codebase [--fast]", "Generate .planning/codebase/ documents"),
    ("/gsd-graphify build", "Build knowledge graph in .planning/graphs/"),
    ("/gsd-graphify query <term>", "Query project knowledge graph"),
    ("/gsd-ingest-docs", "Ingest docs per ingest-manifest.yaml"),
    ("gsd-help", "Full native GSD command reference (use for deep detail)"),
    ("gsd-progress", "Check workflow progress and next step"),
    ("gsd-health", "Health check (install-verify item)"),
    ("gsd-surface status", "List surfaced GSD skills"),
]

RUNNER_GROUPS = {
    "Install and reset": [
        "install-recipe-to-target.sh", "reset-recipe-target.sh",
        "reset-recipe-scaffold.sh",
    ],
    "Sync": [
        "sync-reconcile.sh", "sync-drain-queue.sh",
    ],
    "Jira and GitHub draft/post": [
        "draft-jira-epic.sh", "draft-jira-comment.sh",
        "draft-github-pr-comment.sh", "post-github-pr-comment.sh",
        "create-phase-tasks.sh",
    ],
    "Benchmark-only (optional)": [
        "run-benchmark.sh", "run-baseline.sh", "run-all-baseline.sh",
        "run-gsd.sh", "prepare-run.sh", "finalize-run.sh",
        "validate-pipeline.sh", "init-all-runs.sh", "log-phase-metrics.sh",
        "simulate-session.sh", "smoke-test.sh", "emit-stamp.sh",
        "check-auth.sh", "check-sbt.sh",
    ],
}

def runner_blurb(path):
    text = open(path).read().splitlines()[:25]
    usage = []
    for line in text:
        if line.strip().startswith("#") and ("Usage" in line or line.strip().startswith("#   ")):
            usage.append(line.lstrip("# ").rstrip())
    desc = ""
    for line in text:
        if line.startswith("# ") and "Usage" not in line and not line.startswith("#!"):
            if "—" in line or " - " in line:
                desc = line.lstrip("# ").strip()
                break
    return desc, usage[:6]

lines = []
lines.append("<!-- generated by bench/lib/generate-recipe-help.sh; do not edit by hand -->")
lines.append("")
lines.append("# NetApp GSD Recipe — command reference")
lines.append("")
lines.append(f"_Generated: {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')}_")
lines.append("")
lines.append("In Cursor, invoke **`recipe-help`** for a guided tour. For native GSD depth, use **`gsd-help`**.")
lines.append("")
lines.append("## Quick start (delivery workflow)")
lines.append("")
lines.append("```text")
lines.append("After bash install:  recipe-start     (or recipe-status / recipe-help --next)")
lines.append("recipe-onboard (or step-by-step intake/epic/tasks)")
lines.append("  → recipe-bootstrap-knowledge")
lines.append("  → recipe-plan-phase N → recipe-run-phase N  (or recipe-run-phases)")
lines.append("  → recipe-verify-feature N → recipe-review-ship N → recipe-settle")
lines.append("  → recipe-sync / tracker-sync as needed")
lines.append("```")
lines.append("")
lines.append("Enable planning policy: add `\"agent_skills\": {\"gsd-planner\": [\"skills/recipe-planning-policy\"]}` to `.planning/config.json` (print-only during install).")
lines.append("")
lines.append("## Jira tickets (assign + status)")
lines.append("")
lines.append("Creating an Epic or phase tasks **assigns a person** and moves the new issue to **To Do** (or Backlog / Open / New).")
lines.append("")
lines.append("- Pass `--assignee \"Display Name or email\"` on `recipe-onboard`, `recipe-create-epic`, or `recipe-create-phase-tasks`.")
lines.append("- Or set `\"assignee\": \"...\"` in `.gsd-recipe/config.json`.")
lines.append("- Else the skill uses `git config user.name`, then asks.")
lines.append("")
lines.append("`gsd-jira-sync` posts a **comment and a status change** when `jira-events.json` names one (not comment-only): plan/execute → **In Progress**; verify/review → **In Review**; settle → **Done**. If the board has no matching transition, it warns and still posts the comment. Override with `--transition \"Name\"`.")
lines.append("")

# Field benchmarks (from docs/netapp-recipe/benchmarks/*.json)
bench_dir = os.path.join(repo, "docs/netapp-recipe/benchmarks")
bench_records = []
for path in sorted(glob.glob(os.path.join(bench_dir, "*.json"))):
    if os.path.basename(path) == "schema.json":
        continue
    with open(path) as f:
        bench_records.append(json.load(f))

lines.append("## Field benchmarks (recipe vs ad-hoc)")
lines.append("")
lines.append("Directional pilots on real repos — not the controlled harness grader. Full detail: **`docs/RECIPE-BENCHMARKS.md`** (staged on install) or [docs/netapp-recipe/BENCHMARKS.md](../netapp-recipe/BENCHMARKS.md) in the recipe source repo.")
lines.append("")
if not bench_records:
    lines.append("_No field benchmarks recorded yet._")
else:
    lines.append("| Feature | Target | Recipe | Ad-hoc | Speedup | Jira | PR |")
    lines.append("|---------|--------|--------|--------|---------|------|-----|")
    for r in bench_records:
        arms = {a["id"]: a for a in r.get("arms", [])}
        recipe = arms.get("recipe", {}).get("wall_clock_hours", {})
        adhoc = arms.get("ad-hoc-baseline", {}).get("wall_clock_hours", {})
        def _hrs(h):
            if not h: return "—"
            lo, hi = h.get("min"), h.get("max")
            if lo == hi and lo is not None: return f"{lo:g} h"
            if lo is not None and hi is not None: return f"{lo:g}–{hi:g} h"
            return h.get("note") or "—"
        oc = r.get("outcome", {})
        sp = f"{oc.get('speedup_ratio_min', 0):.1f}–{oc.get('speedup_ratio_max', 0):.1f}×" if oc.get("speedup_ratio_min") else "—"
        j = r.get("tracker", {})
        jira = f"[{j.get('issue_key','—')}]({j['url']})" if j.get("url") else "—"
        s = r.get("ship_artifact", {})
        pr = f"[#{s['number']}]({s['url']})" if s.get("url") and s.get("number") else "—"
        lines.append(f"| {r.get('feature','—')} | {r.get('target_repo',{}).get('name','—')} | {_hrs(recipe)} | {_hrs(adhoc)} | {sp} | {jira} | {pr} |")
lines.append("")
lines.append("Regenerate: `bench/lib/generate-recipe-benchmarks.sh`")
lines.append("")

for group, names in WORKFLOW_GROUPS:
    lines.append(f"## Recipe skills — {group}")
    lines.append("")
    lines.append("| Command | Status | Purpose |")
    lines.append("|---------|--------|---------|")
    for name in names:
        entry = cap_by_invoke(name)
        if not entry:
            lines.append(f"| `{name}` | — | _(not in catalog)_ |")
            continue
        st = status_for(entry)
        desc = entry["description"].replace("|", "\\|")
        if len(desc) > 120:
            desc = desc[:117] + "..."
        lines.append(f"| `{name}` | {st} | {desc} |")
    lines.append("")

lines.append("## Injected planner context (not invoke-by-name)")
lines.append("")
lines.append("| Skill path | Notes |")
lines.append("|------------|-------|")
for skill_id, note in INJECTED:
    entry = caps.get(skill_id, {})
    st = status_for(entry) if entry else "—"
    lines.append(f"| `skills/{skill_id}/SKILL.md` | {st} — {note} |")
lines.append("")

lines.append("## Native GSD commands (summary)")
lines.append("")
lines.append("Recipe skills delegate to these. Run **`gsd-help`** or **`gsd-help --full`** for the complete GSD catalog.")
lines.append("")
lines.append("| Command | Purpose |")
lines.append("|---------|---------|")
for cmd, purpose in GSD_COMMANDS:
    lines.append(f"| `{cmd}` | {purpose} |")
lines.append("")

lines.append("## Harness CLI")
lines.append("")
lines.append("| Command | Purpose |")
lines.append("|---------|---------|")
lines.append("| `bin/recipe install [--verify] [--target REPO]` | Install recipe into target repo |")
lines.append("| `bin/recipe reset [--yes] [--verify] [--target REPO]` | Reset recipe scaffold on target |")
lines.append("| `.gsd-recipe/scripts/install.sh --verify` | Post-install checklist (bash items) |")
lines.append("| `.gsd-recipe/scripts/install.sh --record-jira-check pass\\|fail` | Record Jira token check result |")
lines.append("| `.gsd-recipe/scripts/install.sh --uninstall` | Remove staged recipe files |")
lines.append("| `.gsd-recipe/scripts/install-graphify.sh` | Sudo-free graphify install (requires `uv`) |")
lines.append("| `bench/lib/generate-recipe-help.sh` | Regenerate this document |")
lines.append("")

lines.append("## Bench runners")
lines.append("")
for group, names in RUNNER_GROUPS.items():
    lines.append(f"### {group}")
    lines.append("")
    lines.append("| Runner | Purpose |")
    lines.append("|--------|---------|")
    for name in names:
        path = os.path.join(repo, "bench/runners", name)
        if not os.path.isfile(path):
            continue
        desc, usage = runner_blurb(path)
        if not desc:
            desc = usage[0] if usage else "See script header"
        desc = desc.replace("|", "\\|")
        if len(desc) > 100:
            desc = desc[:97] + "..."
        lines.append(f"| `bench/runners/{name}` | {desc} |")
    lines.append("")

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as f:
    f.write("\n".join(lines))
    f.write("\n")

print(f"generate-recipe-help: wrote {out_path}")
PY
