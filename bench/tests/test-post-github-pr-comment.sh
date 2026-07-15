#!/usr/bin/env bash
# Regression test for bench/runners/post-github-pr-comment.sh (TASK-030).
# Matches the convention of bench/tests/test-install-recipe-settle.sh's
# --check-ci coverage — exercises the real script logic (draft ->
# idempotency-check -> post -> ledger) against fake `gh` stubs on a scratch
# PATH (never the real gh CLI, never a real external GitHub PR), covering:
# unknown event_id fail-closed, --dry-run never calling gh/never touching the
# ledger, duplicate_skipped never calling gh, a successful stubbed post
# appending exactly one ledger row, a failing stubbed post never appending a
# row, and confirming the drafted body genuinely comes from
# draft-github-pr-comment.sh's own real output (diffed against a direct call
# with the same args, not reimplemented/duplicated templating logic).
# Run: ./bench/tests/test-post-github-pr-comment.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$REPO_ROOT/bench/runners/post-github-pr-comment.sh"
DRAFT_SCRIPT="$REPO_ROOT/bench/runners/draft-github-pr-comment.sh"
SYNC_LEDGER="$REPO_ROOT/bench/lib/sync-ledger.sh"

pass=0
fail=0

check() {
  local desc="$1"; local result="$2"
  if [ "$result" = "0" ]; then
    echo "ok - $desc"
    pass=$((pass + 1))
  else
    echo "FAIL - $desc"
    fail=$((fail + 1))
  fi
}

new_repo() {
  local dir
  dir="$(mktemp -d)"
  (cd "$dir" && git init -q && git commit --allow-empty -qm init)
  echo "$dir"
}

# Builds a scratch PATH from every real PATH binary, excluding whichever
# names are listed in $1 (space separated) — same technique as
# test-install-recipe-settle.sh's make_scratch_path_excluding, so a test can
# drop in its own fake stub for those names without a real binary shadowing
# it (this repo has a known pre-existing broken `gh` symlink on the default
# PATH — never rely on it here).
make_scratch_path_excluding() {
  local exclude=" $1 "
  local fakebin dir f b
  fakebin="$(mktemp -d)"
  for dir in $(echo "$PATH" | tr ':' '\n'); do
    [ -d "$dir" ] || continue
    for f in "$dir"/*; do
      [ -f "$f" ] || continue
      b="$(basename "$f")"
      case "$exclude" in *" $b "*) continue ;; esac
      [ -e "$fakebin/$b" ] || ln -s "$f" "$fakebin/$b" 2>/dev/null || true
    done
  done
  echo "$fakebin"
}

REPO="$(new_repo)"

# 1. Unknown event_id fails closed — propagates draft-github-pr-comment.sh's
# own exit code unchanged, never re-validating the event list itself.
OUT1="$(REPO_ROOT="$REPO" "$RUNNER" bogus_event --pr 1 --phase 1 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ]
check "unknown event_id fails closed (non-zero exit)" "$?"
printf '%s' "$OUT1" | grep -qi "unknown event_id" && rc=0 || rc=$?
check "unknown event_id error message propagates draft-github-pr-comment.sh's own error" "$rc"

# 2. --dry-run never calls gh, never touches the ledger, and reports the
# drafted body + idempotency key + not-yet-posted status.
LEDGER2="$(mktemp -u)"
GHLOG2="$(mktemp)"
FAKEBIN2="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN2/gh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$GHLOG2"
exit 0
EOF
chmod +x "$FAKEBIN2/gh"
OUT2="$(PATH="$FAKEBIN2" REPO_ROOT="$REPO" "$RUNNER" execute_wave --pr 42 --phase 3 --wave 2 --repo my-org/my-repo --ledger "$LEDGER2" --dry-run)" && rc=0 || rc=$?
check "--dry-run exits 0" "$rc"
printf '%s' "$OUT2" | grep -q "DRY RUN" && rc=0 || rc=$?
check "--dry-run output announces dry-run mode" "$rc"
printf '%s' "$OUT2" | grep -q "Idempotency key: gsd-recipe:execute_wave:phase=3:wave=2:issue=pr-42" && rc=0 || rc=$?
check "--dry-run reports the computed idempotency key using the synthetic pr-<PR_NUMBER> issue key" "$rc"
printf '%s' "$OUT2" | grep -q "Already posted: no" && rc=0 || rc=$?
check "--dry-run reports not-yet-posted status" "$rc"
[ ! -s "$GHLOG2" ]
check "--dry-run never calls gh at all" "$?"
[ ! -f "$LEDGER2" ]
check "--dry-run never creates/touches the ledger file" "$?"
rm -rf "$FAKEBIN2"

# 3. Already-posted key reports duplicate_skipped and never calls gh.
LEDGER3="$(mktemp)"
KEY3="$("$SYNC_LEDGER" key execute_wave pr-42 --phase 3 --wave 2)"
"$SYNC_LEDGER" append "$KEY3" github --result posted --ledger "$LEDGER3" >/dev/null
GHLOG3="$(mktemp)"
FAKEBIN3="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN3/gh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$GHLOG3"
exit 0
EOF
chmod +x "$FAKEBIN3/gh"
OUT3="$(PATH="$FAKEBIN3" REPO_ROOT="$REPO" "$RUNNER" execute_wave --pr 42 --phase 3 --wave 2 --repo my-org/my-repo --ledger "$LEDGER3")" && rc=0 || rc=$?
check "duplicate key: runner exits 0" "$rc"
printf '%s' "$OUT3" | grep -q "duplicate_skipped" && rc=0 || rc=$?
check "duplicate key: reports duplicate_skipped" "$rc"
[ ! -s "$GHLOG3" ]
check "duplicate key: never calls gh" "$?"
LINES3_AFTER="$(wc -l < "$LEDGER3" | tr -d ' ')"
[ "$LINES3_AFTER" = "1" ]
check "duplicate key: ledger still has exactly 1 row (no duplicate row appended)" "$?"
rm -rf "$FAKEBIN3"

# 4. Successful stubbed post appends exactly one ledger row with
# target: github, result: posted, and the real gh-provided external_id.
LEDGER4="$(mktemp -u)"
GHLOG4="$(mktemp)"
FAKEBIN4="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN4/gh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$GHLOG4"
if [ "\$1" = "pr" ] && [ "\$2" = "comment" ]; then
  echo "https://github.com/my-org/my-repo/pull/42#issuecomment-1234567"
  exit 0
fi
exit 1
EOF
chmod +x "$FAKEBIN4/gh"
OUT4="$(PATH="$FAKEBIN4" REPO_ROOT="$REPO" "$RUNNER" execute_wave --pr 42 --phase 3 --wave 2 --repo my-org/my-repo --ledger "$LEDGER4")" && rc=0 || rc=$?
check "successful stubbed post: runner exits 0" "$rc"
printf '%s' "$OUT4" | grep -q "posted" && rc=0 || rc=$?
check "successful stubbed post: reports posted" "$rc"
printf '%s' "$OUT4" | grep -q "issuecomment-1234567" && rc=0 || rc=$?
check "successful stubbed post: reports the real gh-provided comment URL as the external ID" "$rc"
python3 -c "
import json
with open('$LEDGER4') as f:
    lines = [json.loads(l) for l in f if l.strip()]
assert len(lines) == 1, lines
rec = lines[0]
assert rec['target'] == 'github', rec
assert rec['result'] == 'posted', rec
assert rec['external_id'] == 'https://github.com/my-org/my-repo/pull/42#issuecomment-1234567', rec
"
check "successful stubbed post: exactly 1 ledger row with target=github, result=posted, real external_id" "$?"
grep -qF "42 --repo my-org/my-repo --body-file" "$GHLOG4" && rc=0 || rc=$?
check "gh pr comment invoked with the expected PR number, --repo, and --body-file args" "$rc"
rm -rf "$FAKEBIN4"

# 5. Failing stubbed post never appends a ledger row and reports the
# failure clearly.
LEDGER5="$(mktemp -u)"
GHLOG5="$(mktemp)"
FAKEBIN5="$(make_scratch_path_excluding "gh")"
cat > "$FAKEBIN5/gh" <<EOF
#!/usr/bin/env bash
echo "\$@" >> "$GHLOG5"
if [ "\$1" = "pr" ] && [ "\$2" = "comment" ]; then
  echo "gh: HTTP 404 (Not Found)" >&2
  exit 1
fi
exit 1
EOF
chmod +x "$FAKEBIN5/gh"
OUT5="$(PATH="$FAKEBIN5" REPO_ROOT="$REPO" "$RUNNER" execute_wave --pr 99 --phase 3 --wave 2 --repo my-org/my-repo --ledger "$LEDGER5" 2>&1)" && rc=0 || rc=$?
[ "$rc" != "0" ]
check "failing stubbed post: runner exits non-zero" "$?"
printf '%s' "$OUT5" | grep -qi "FAILED to post" && rc=0 || rc=$?
check "failing stubbed post: reports the failure clearly" "$rc"
printf '%s' "$OUT5" | grep -q "404" && rc=0 || rc=$?
check "failing stubbed post: surfaces gh's real error detail" "$rc"
[ ! -f "$LEDGER5" ]
check "failing stubbed post: never creates/appends to the ledger file" "$?"
rm -rf "$FAKEBIN5"

# 6. The drafted body genuinely comes from draft-github-pr-comment.sh's own
# real output — diff a --dry-run's drafted-body section against a direct
# call to draft-github-pr-comment.sh with the same args.
DIRECT_BODY="$(REPO_ROOT="$REPO" "$DRAFT_SCRIPT" execute_wave --pr 42 --phase 3 --wave 2 --arm recipe --run run-01)"
LEDGER6="$(mktemp -u)"
DRYRUN_OUT="$(REPO_ROOT="$REPO" "$RUNNER" execute_wave --pr 42 --phase 3 --wave 2 --repo my-org/my-repo --ledger "$LEDGER6" --dry-run)"
DRYRUN_BODY="$(printf '%s\n' "$DRYRUN_OUT" | sed -n '/--- Drafted body/,$p' | tail -n +2)"
[ "$DIRECT_BODY" = "$DRYRUN_BODY" ]
check "the runner's drafted body is byte-identical to a direct draft-github-pr-comment.sh call (never reimplemented)" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
