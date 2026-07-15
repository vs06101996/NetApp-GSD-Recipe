#!/usr/bin/env bash
# post-github-pr-comment.sh (TASK-030) — the real, scriptable draft -> idempotency-check
# -> post -> ledger pipeline for GitHub PR lifecycle comments that
# draft-github-pr-comment.sh (TASK-006) deliberately stopped short of ("Does NOT
# post to GitHub — use `gh pr comment` after reviewing output.").
#
# Unlike Jira posting (addCommentToJiraIssue is an MCP tool call, only reachable
# from a live agent turn -- see gsd-jira-sync-SKILL.md), `gh pr comment` is a
# plain, real, local CLI call. So this entire pipeline -- draft, compute the
# idempotency key, check the ledger, post for real, record the outcome -- is a
# single standalone, testable script, the same category as install.sh's own
# `gh auth status`/`gh api user` GitHub check and recipe-settle's `--check-ci`
# `gh pr checks` probe.
#
# Synthetic issue-key convention (a genuine scope decision, not an oversight):
# GitHub PRs have no Jira issue key. The idempotency-ledger key still needs an
# <issue_key>-shaped segment (sync-ledger.sh's `key` subcommand signature), so:
#   - if --issue KEY was passed (e.g. this PR is cross-linked to a Jira issue),
#     that real key is used, matching the Jira-side convention exactly;
#   - otherwise, a synthetic `pr-<PR_NUMBER>` value is used instead.
# This keeps GitHub-only PRs (no linked tracker issue) idempotent on their own
# terms without inventing a fake Jira-shaped key. The ledger key deliberately
# does NOT include a :commit= segment (unlike draft-github-pr-comment.sh's own
# *displayed* idempotency key, which does) -- comments are milestone-scoped
# (once per phase/wave/event), not per-commit, matching every other recipe-*
# skill's own `sync-ledger.sh key <event> <issue> --phase N [--wave W]` call
# shape (e.g. recipe-settle's `sync-ledger.sh key settled <issue_key>`).
#
# Why no stamp emission (locked decision, not a silent omission): the 4 GitHub
# events in bench/recipe/trackers/github-events.json have no "stamp" field at
# all -- unlike jira-events.json's entries, which each carry a "stamp": {...}
# or "stamp": null. There is nothing to key a stamp emission off for the
# GitHub side, and when a PR's phase is also linked to a Jira issue, the Jira
# side already owns the canonical KPI stamp for that same milestone (emitted
# via sync-drain-queue.sh mark-done / gsd-jira-sync's own single-event flow).
# GitHub PR comments are a secondary/parallel visibility channel per
# docs/netapp-recipe/lld/TRACEABILITY-LLD.md's "GitHub PR events" section, not
# a second source of KPI truth. So this script never calls emit-stamp.sh.
#
# Usage:
#   post-github-pr-comment.sh <event_id> --pr <number> --phase <N> [--wave <W>]
#     [--issue <KEY>] [--repo <owner/repo>] [--arm recipe] [--run run-01]
#     [--ledger <path>] [--dry-run]
#
# Examples:
#   post-github-pr-comment.sh execute_complete --pr 42 --phase 3 --issue PROJ-101
#   post-github-pr-comment.sh execute_wave --pr 42 --phase 3 --wave 2 --dry-run
#
# Event ids: see bench/recipe/trackers/github-events.json (validated by
# draft-github-pr-comment.sh itself -- this script never re-implements that
# check, it just propagates the draft script's own failure).
set -euo pipefail

EVENT="${1:-}"
if [ -z "$EVENT" ]; then
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
REPO_OVERRIDE=""
LEDGER_OVERRIDE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --pr) PR_NUMBER="${2:?--pr requires a value}"; shift 2 ;;
    --phase) PHASE="${2:?--phase requires a value}"; shift 2 ;;
    --wave) WAVE="${2:?--wave requires a value}"; shift 2 ;;
    --issue) ISSUE_KEY="${2:?--issue requires a value}"; shift 2 ;;
    --repo) REPO_OVERRIDE="${2:?--repo requires a value}"; shift 2 ;;
    --arm) ARM="${2:?--arm requires a value}"; shift 2 ;;
    --run) RUN_ID="${2:?--run requires a value}"; shift 2 ;;
    --ledger) LEDGER_OVERRIDE="${2:?--ledger requires a value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$PR_NUMBER" ] || [ -z "$PHASE" ]; then
  echo "--pr and --phase are required" >&2
  exit 2
fi

BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${REPO_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
DRAFT_SCRIPT="$BENCH_ROOT/runners/draft-github-pr-comment.sh"
SYNC_LEDGER="$BENCH_ROOT/lib/sync-ledger.sh"
LEDGER_PATH="${LEDGER_OVERRIDE:-$REPO_ROOT/.gsd-recipe/sync-ledger.jsonl}"

# --- Step 1: draft the body by calling draft-github-pr-comment.sh directly ---
# (never duplicate its templating/git-log/short_sha logic here). Unknown
# event_id fails here too -- draft-github-pr-comment.sh already prints
# "Unknown event_id: <id>" to stderr and exits 1; we just add context and
# propagate its exit code unchanged, never re-validating ourselves.
DRAFT_ARGS=("$EVENT" --pr "$PR_NUMBER" --phase "$PHASE" --arm "$ARM" --run "$RUN_ID")
[ -n "$WAVE" ] && DRAFT_ARGS+=(--wave "$WAVE")
[ -n "$ISSUE_KEY" ] && DRAFT_ARGS+=(--issue "$ISSUE_KEY")

set +e
BODY="$("$DRAFT_SCRIPT" "${DRAFT_ARGS[@]}")"
DRAFT_RC=$?
set -e
if [ "$DRAFT_RC" -ne 0 ]; then
  echo "post-github-pr-comment.sh: draft-github-pr-comment.sh failed (see error above) — aborting before any ledger check or gh call." >&2
  exit "$DRAFT_RC"
fi

# --- Step 2 (deferred): --repo is only resolved later, right before an actual
# gh call -- dry-run and duplicate_skipped paths never need a real GitHub
# remote to exist, so failing to resolve one must never block those paths.

# --- Step 3: compute the idempotency key ---
# issue_key_for_ledger: the real --issue value if passed, else a synthetic
# pr-<PR_NUMBER> placeholder (see header comment for the full rationale).
if [ -n "$ISSUE_KEY" ]; then
  ISSUE_KEY_FOR_LEDGER="$ISSUE_KEY"
else
  ISSUE_KEY_FOR_LEDGER="pr-$PR_NUMBER"
fi

KEY_ARGS=("$EVENT" "$ISSUE_KEY_FOR_LEDGER" --phase "$PHASE")
[ -n "$WAVE" ] && KEY_ARGS+=(--wave "$WAVE")
KEY="$("$SYNC_LEDGER" key "${KEY_ARGS[@]}")"

# --- Step 4: check the ledger ---
ALREADY_POSTED=0
if "$SYNC_LEDGER" has "$KEY" --ledger "$LEDGER_PATH" >/dev/null 2>&1; then
  ALREADY_POSTED=1
fi

# --- Step 5: --dry-run -- report, never call gh ---
if [ "$DRY_RUN" -eq 1 ]; then
  echo "=== post-github-pr-comment.sh: DRY RUN (gh pr comment is never called) ==="
  echo "Event: $EVENT   PR: #$PR_NUMBER   Phase: $PHASE   Wave: ${WAVE:-—}"
  echo "Idempotency key: $KEY"
  if [ "$ALREADY_POSTED" -eq 1 ]; then
    echo "Already posted: yes (a real run would report duplicate_skipped and skip gh entirely)"
  else
    echo "Already posted: no (a real run would proceed to gh pr comment)"
  fi
  echo "--- Drafted body (from draft-github-pr-comment.sh) ---"
  printf '%s\n' "$BODY"
  exit 0
fi

# --- Duplicate check (real run) ---
if [ "$ALREADY_POSTED" -eq 1 ]; then
  echo "post-github-pr-comment.sh: duplicate_skipped — key already present in $LEDGER_PATH, gh pr comment was never called."
  echo "Idempotency key: $KEY"
  exit 0
fi

# --- Step 2 (for real): resolve --repo now that we're actually about to post ---
resolve_owner_repo() {
  local url
  url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" || return 1
  url="${url%.git}"
  case "$url" in
    git@github.com:*) printf '%s\n' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf '%s\n' "${url#ssh://git@github.com/}" ;;
    https://github.com/*) printf '%s\n' "${url#https://github.com/}" ;;
    http://github.com/*) printf '%s\n' "${url#http://github.com/}" ;;
    *) return 1 ;;
  esac
}

OWNER_REPO="$REPO_OVERRIDE"
if [ -z "$OWNER_REPO" ]; then
  if ! OWNER_REPO="$(resolve_owner_repo)"; then
    echo "post-github-pr-comment.sh: could not resolve owner/repo from 'git remote get-url origin' in $REPO_ROOT — pass --repo <owner/repo> explicitly. Never guessing." >&2
    exit 1
  fi
fi

# --- Step 6: post for real ---
if ! command -v gh >/dev/null 2>&1; then
  echo "post-github-pr-comment.sh: gh CLI not found on PATH — cannot post. Install it (e.g. 'brew install gh') and run 'gh auth login'." >&2
  echo "Idempotency key: $KEY (not appended to the ledger — nothing was posted)" >&2
  exit 1
fi

BODY_FILE="$(mktemp)"
GH_ERR_FILE="$(mktemp)"
trap 'rm -f "$BODY_FILE" "$GH_ERR_FILE"' EXIT
printf '%s\n' "$BODY" > "$BODY_FILE"

set +e
GH_OUT="$(gh pr comment "$PR_NUMBER" --repo "$OWNER_REPO" --body-file "$BODY_FILE" 2>"$GH_ERR_FILE")"
GH_RC=$?
set -e
GH_ERR="$(cat "$GH_ERR_FILE")"

if [ "$GH_RC" -ne 0 ]; then
  echo "post-github-pr-comment.sh: FAILED to post (gh pr comment exited $GH_RC) — no ledger row appended." >&2
  echo "gh error: $GH_ERR" >&2
  [ -n "$GH_OUT" ] && echo "gh stdout: $GH_OUT" >&2
  echo "Idempotency key: $KEY" >&2
  exit 1
fi

# On success, `gh pr comment` prints exactly the new comment's URL to stdout
# (verified live against cli/cli's own pkg/cmd/pr/shared/commentable.go
# createComment(): `fmt.Fprintln(opts.IO.Out, url)`) — nothing else, on success.
EXTERNAL_ID="$(printf '%s' "$GH_OUT" | tr -d '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

# --- Step 7: on success, append to the ledger (never before this point) ---
if [ -n "$EXTERNAL_ID" ]; then
  "$SYNC_LEDGER" append "$KEY" github --external-id "$EXTERNAL_ID" --result posted --ledger "$LEDGER_PATH" >/dev/null
else
  "$SYNC_LEDGER" append "$KEY" github --result posted --ledger "$LEDGER_PATH" >/dev/null
fi

echo "post-github-pr-comment.sh: posted"
echo "Idempotency key: $KEY"
echo "PR: $OWNER_REPO#$PR_NUMBER"
if [ -n "$EXTERNAL_ID" ]; then
  echo "External ID (comment URL): $EXTERNAL_ID"
else
  echo "External ID: (gh printed no output — none captured)"
fi
