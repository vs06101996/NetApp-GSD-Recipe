#!/usr/bin/env bash
# Near-RT reconciler (TASK-003): scans .planning/ + git log for new GSD lifecycle
# artifacts, infers which jira-events.json event fired, resolves the Jira issue via
# parse-state.sh, skips anything already posted (sync-ledger.sh), drafts the comment
# body (draft-jira-comment.sh), and enqueues a `queued` row to .gsd-recipe/sync-queue.jsonl.
#
# Does NOT post to Jira — a bash script has no MCP tool-calling access. The `queued`
# rows it writes are meant to be drained by an agent turn (gsd-jira-sync skill) that
# calls addCommentToJiraIssue, then appends `posted` to sync-ledger.jsonl and runs
# emit-stamp.sh. TASK-005 builds a dedicated drain script for this; until then, drain
# manually via the skill, using the queue rows this script writes as the work list.
#
# Signal -> event_id inference (TRACEABILITY-LLD only says "watches .planning/ mtimes
# + git log, infers event_id" — the concrete rules below are this implementation's own
# design, grounded in RUNTIME-LLD.md's documented per-phase artifact paths, and are
# carried in-code same as sync-ledger.sh's key format / parse-state.sh's routing table):
#
#   .planning/STATE.md newly exists                       -> intake_started    (epic)
#   .planning/phases/NN-*/*CONTEXT.md new                 -> discuss_complete  (epic)
#   .planning/phases/NN-*/*PLAN.md new                    -> plan_complete     (phase N)
#   .planning/phases/NN-*/*PLAN.md modified again          -> plan_revised      (phase N, commit-keyed)
#     (only once plan_complete is already ledgered)
#   .planning/phases/NN-*/*SUMMARY.md new                  -> execute_complete  (phase N)
#   .planning/phases/NN-*/*REVIEW.md new                   -> review_complete   (phase N)
#   .planning/phases/NN-*/*VERIFICATION.md or *UAT.md new  -> verify_complete   (phase N)
#   new commit touching PLAN.md frontmatter `touches:` globs,
#     after plan_complete ledgered, before SUMMARY.md exists -> execute_started (phase N)
#   learning_stored, execute_wave, settled, reopened: NOT auto-inferred.
#     - execute_wave / settled / reopened: no reliable filesystem signal (wave
#       boundaries are plan-internal; settled/reopened are human+CI decisions).
#     - learning_stored: DATA-CONTRACTS.md rule 7 lists it as *phase-routed*,
#       but its filesystem signal (new file under .sdlc/patterns/repo/) has no
#       structural link back to a phase_id — there's no naming convention tying
#       a pattern file to the phase that produced it. Rather than guess (e.g.
#       "most recent phase"), this is deferred to manual gsd-jira-sync same as
#       the others above, flagged here so it isn't mistaken for an oversight.
#   All of the above stay manual-only via the existing gsd-jira-sync skill.
#
# Idempotency: ledger (sync-ledger.sh) is the source of truth for "already posted" —
# the checkpoint file is only a local performance/plan_revised-detection aid and is
# always re-verified against the ledger before anything is queued.
#
# Usage:
#   sync-reconcile.sh [--dry-run] [--state PATH] [--checkpoint PATH] [--queue PATH]
#                      [--ledger PATH] [--arm recipe] [--run RUN_ID]
#
# Examples:
#   bench/runners/sync-reconcile.sh --dry-run           # CI-safe: detect + draft only, no writes
#   bench/runners/sync-reconcile.sh --run pilot-01       # writes queue rows for new events
set -euo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

DRY_RUN=0
STATE_FILE="$REPO_ROOT/.planning/STATE.md"
CHECKPOINT_FILE="$REPO_ROOT/.gsd-recipe/reconcile-state.json"
QUEUE_FILE="$REPO_ROOT/.gsd-recipe/sync-queue.jsonl"
LEDGER_FILE="$REPO_ROOT/.gsd-recipe/sync-ledger.jsonl"
ARM="recipe"
RUN_ID="run-01"

usage() {
  cat >&2 <<'EOF'
Usage:
  sync-reconcile.sh [--dry-run] [--state PATH] [--checkpoint PATH] [--queue PATH]
                     [--ledger PATH] [--arm recipe] [--run RUN_ID]
EOF
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --state) STATE_FILE="${2:?--state requires a value}"; shift 2 ;;
    --checkpoint) CHECKPOINT_FILE="${2:?--checkpoint requires a value}"; shift 2 ;;
    --queue) QUEUE_FILE="${2:?--queue requires a value}"; shift 2 ;;
    --ledger) LEDGER_FILE="${2:?--ledger requires a value}"; shift 2 ;;
    --arm) ARM="${2:?--arm requires a value}"; shift 2 ;;
    --run) RUN_ID="${2:?--run requires a value}"; shift 2 ;;
    *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
  esac
done

REPO_ROOT="$REPO_ROOT" BENCH_ROOT="$BENCH_ROOT" DRY_RUN="$DRY_RUN" STATE_FILE="$STATE_FILE" \
CHECKPOINT_FILE="$CHECKPOINT_FILE" QUEUE_FILE="$QUEUE_FILE" LEDGER_FILE="$LEDGER_FILE" \
ARM="$ARM" RUN_ID="$RUN_ID" python3 - <<'PY'
import fnmatch
import json
import os
import pathlib
import re
import subprocess
import sys
from datetime import datetime, timezone

REPO_ROOT = os.environ["REPO_ROOT"]
BENCH_ROOT = pathlib.Path(os.environ["BENCH_ROOT"])
DRY_RUN = os.environ["DRY_RUN"] == "1"
STATE_FILE = os.environ["STATE_FILE"]
CHECKPOINT_FILE = pathlib.Path(os.environ["CHECKPOINT_FILE"])
QUEUE_FILE = pathlib.Path(os.environ["QUEUE_FILE"])
LEDGER_FILE = os.environ["LEDGER_FILE"]
ARM = os.environ["ARM"]
RUN_ID = os.environ["RUN_ID"]

PARSE_STATE = BENCH_ROOT / "lib" / "parse-state.sh"
SYNC_LEDGER = BENCH_ROOT / "lib" / "sync-ledger.sh"
DRAFT = BENCH_ROOT / "runners" / "draft-jira-comment.sh"


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def resolve_issue(event_id, phase_id=None):
    cmd = [str(PARSE_STATE), "resolve-issue", event_id, "--state", STATE_FILE]
    if phase_id is not None:
        cmd += ["--phase", str(phase_id)]
    r = sh(cmd)
    if r.returncode != 0:
        return None, r.stderr.strip()
    return r.stdout.strip(), None


def ledger_key(event_id, issue_key, phase_id=None, commit=None):
    cmd = [str(SYNC_LEDGER), "key", event_id, issue_key]
    if phase_id is not None:
        cmd += ["--phase", str(phase_id)]
    if commit:
        cmd += ["--commit", commit]
    r = sh(cmd)
    if r.returncode != 0:
        raise RuntimeError(f"sync-ledger.sh key failed: {r.stderr}")
    return r.stdout.strip()


def ledger_has(key):
    cmd = [str(SYNC_LEDGER), "has", key, "--ledger", LEDGER_FILE]
    r = sh(cmd)
    return r.returncode == 0


def draft_comment(event_id, issue_key, phase_id=None):
    cmd = [str(DRAFT), event_id, issue_key]
    if phase_id is not None:
        cmd += ["--phase", str(phase_id)]
    cmd += ["--arm", ARM, "--run", RUN_ID]
    r = sh(cmd)
    if r.returncode != 0:
        raise RuntimeError(f"draft-jira-comment.sh failed for {event_id}/{issue_key}: {r.stderr}")
    return r.stdout


def last_commit_sha(rel_path):
    r = sh(["git", "-C", REPO_ROOT, "log", "-1", "--format=%h", "--", rel_path])
    out = r.stdout.strip()
    return out or None


def commits_touching_since(globs, since_iso):
    if not globs or not since_iso:
        return False
    r = sh(["git", "-C", REPO_ROOT, "log", f"--since={since_iso}", "--name-only", "--pretty=format:"])
    changed = [ln.strip() for ln in r.stdout.splitlines() if ln.strip()]
    for f in changed:
        for pat in globs:
            if fnmatch.fnmatch(f, pat):
                return True
    return False


def parse_touches(plan_path):
    """Hand-rolled parse of the PLAN.md frontmatter `touches:` glob list
    (RUNTIME-LLD.md § PLAN.md frontmatter schema). No YAML dependency needed —
    the documented shape is a fixed `key:` / `  - glob` block."""
    text = plan_path.read_text(errors="replace")
    if not text.startswith("---"):
        return []
    end = text.find("\n---", 3)
    if end == -1:
        return []
    front = text[3:end]
    touches = []
    in_touches = False
    for line in front.splitlines():
        if re.match(r"^touches\s*:", line):
            in_touches = True
            continue
        if in_touches and line.startswith((" ", "\t")) and line.strip().startswith("-"):
            glob_val = line.strip().lstrip("-").strip().split("#")[0].strip()
            if glob_val:
                touches.append(glob_val)
            continue
        in_touches = False
    return touches


def ledger_ts(key):
    if not os.path.isfile(LEDGER_FILE):
        return None
    latest = None
    with open(LEDGER_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            if rec.get("key") == key:
                latest = rec.get("ts")
    return latest


def load_checkpoint():
    if CHECKPOINT_FILE.is_file():
        try:
            return json.loads(CHECKPOINT_FILE.read_text())
        except json.JSONDecodeError:
            pass
    return {"files": {}}


def save_checkpoint(cp):
    if DRY_RUN:
        return
    CHECKPOINT_FILE.parent.mkdir(parents=True, exist_ok=True)
    CHECKPOINT_FILE.write_text(json.dumps(cp, indent=2))


def rel(p):
    return str(pathlib.Path(p).resolve().relative_to(pathlib.Path(REPO_ROOT).resolve()))


checkpoint = load_checkpoint()
seen_files = checkpoint.setdefault("files", {})

candidates = []  # dicts: event_id, phase_id, file, commit(optional), since_ts(optional, for execute_started)

state_path = pathlib.Path(STATE_FILE)
if state_path.is_file():
    key_id = rel(state_path)
    if key_id not in seen_files:
        candidates.append({"event_id": "intake_started", "phase_id": None, "file": key_id})

phases_dir = pathlib.Path(REPO_ROOT) / ".planning" / "phases"
PHASE_DIR_RE = re.compile(r"^(\d+)-")

if phases_dir.is_dir():
    for d in sorted(phases_dir.iterdir()):
        if not d.is_dir():
            continue
        m = PHASE_DIR_RE.match(d.name)
        if not m:
            continue
        phase_id = str(int(m.group(1)))

        def find_suffix(*suffixes):
            for f in sorted(d.iterdir()):
                if f.is_file() and any(f.name.endswith(suf) for suf in suffixes):
                    return f
            return None

        context_f = find_suffix("CONTEXT.md")
        plan_f = find_suffix("PLAN.md")
        summary_f = find_suffix("SUMMARY.md")
        review_f = find_suffix("REVIEW.md")
        verify_f = find_suffix("VERIFICATION.md", "UAT.md")

        def check_new(f, event_id, phase_for_key):
            if f is None:
                return
            key_id = rel(f)
            if key_id not in seen_files:
                candidates.append({"event_id": event_id, "phase_id": phase_for_key, "file": key_id})

        check_new(context_f, "discuss_complete", None)
        check_new(summary_f, "execute_complete", phase_id)
        check_new(review_f, "review_complete", phase_id)
        check_new(verify_f, "verify_complete", phase_id)

        if plan_f is not None:
            key_id = rel(plan_f)
            mtime = plan_f.stat().st_mtime
            prev = seen_files.get(key_id)
            if prev is None:
                candidates.append({"event_id": "plan_complete", "phase_id": phase_id, "file": key_id})
            elif mtime > prev:
                candidates.append({
                    "event_id": "plan_revised", "phase_id": phase_id, "file": key_id,
                    "commit": last_commit_sha(key_id),
                })

        if plan_f is not None and summary_f is None:
            pc_issue, _ = resolve_issue("plan_complete", phase_id)
            if pc_issue:
                pc_key = ledger_key("plan_complete", pc_issue, phase_id)
                if ledger_has(pc_key):
                    es_issue, _ = resolve_issue("execute_started", phase_id)
                    if es_issue:
                        es_key = ledger_key("execute_started", es_issue, phase_id)
                        if not ledger_has(es_key):
                            touches = parse_touches(plan_f)
                            since = ledger_ts(pc_key)
                            if commits_touching_since(touches, since):
                                candidates.append({
                                    "event_id": "execute_started", "phase_id": phase_id,
                                    "file": rel(plan_f) + " (touches: " + ",".join(touches) + ")",
                                })

results = {"queued": [], "duplicate_skipped": [], "errors": []}
queued_lines = []
seen_keys_this_run = set()

for c in candidates:
    event_id = c["event_id"]
    phase_id = c["phase_id"]
    commit = c.get("commit")

    issue_key, err = resolve_issue(event_id, phase_id)
    if err:
        results["errors"].append({"event_id": event_id, "phase_id": phase_id, "file": c["file"], "error": err})
        continue

    key = ledger_key(event_id, issue_key, phase_id, commit)
    if key in seen_keys_this_run:
        continue
    seen_keys_this_run.add(key)

    if ledger_has(key):
        results["duplicate_skipped"].append({"event_id": event_id, "issue_key": issue_key, "key": key})
        if "file" in c:
            f = pathlib.Path(REPO_ROOT) / c["file"].split(" (")[0]
            if f.is_file():
                seen_files[c["file"].split(" (")[0]] = f.stat().st_mtime
        continue

    try:
        body = draft_comment(event_id, issue_key, phase_id)
    except RuntimeError as e:
        results["errors"].append({"event_id": event_id, "phase_id": phase_id, "issue_key": issue_key, "error": str(e)})
        continue

    entry = {
        "queued_at": datetime.now(timezone.utc).isoformat(),
        "event_id": event_id,
        "issue_key": issue_key,
        "target": "jira",
        "template": "_comment.template.md",
        "key": key,
        "status": "queued",
    }
    if phase_id is not None:
        entry["phase_id"] = phase_id

    results["queued"].append({**entry, "body_preview": body.splitlines()[0] if body else ""})
    queued_lines.append(json.dumps(entry))

    plain_file = c["file"].split(" (")[0]
    f = pathlib.Path(REPO_ROOT) / plain_file
    if f.is_file():
        seen_files[plain_file] = f.stat().st_mtime

if not DRY_RUN and queued_lines:
    QUEUE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(QUEUE_FILE, "a") as f:
        for line in queued_lines:
            f.write(line + "\n")

save_checkpoint(checkpoint)

print(json.dumps({"dry_run": DRY_RUN, **results}, indent=2))

if results["errors"]:
    sys.exit(1)
PY
