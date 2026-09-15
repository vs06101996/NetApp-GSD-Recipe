#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER="$ROOT/bench/runners/report-recipe-issue.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
pass=0
fail=0

check() {
  if [[ "$2" == 0 ]]; then
    echo "ok - $1"; pass=$((pass + 1))
  else
    echo "FAIL - $1"; fail=$((fail + 1))
  fi
}

cat > "$scratch/body.md" <<EOF
Actual: Authorization: Bearer private-token-value
password=supersecret
GitHub: ghp_1234567890abcdefghijkl
Path: $HOME/Projects/private-product/log.txt
Temporary path: /tmp/private-product/debug.log
EOF

fakebin="$scratch/bin"
mkdir -p "$fakebin"
cat > "$fakebin/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$GH_CALLS"
case "$1 $2" in
  "auth status") exit 0 ;;
  "issue list")
    if [[ "${GH_DUPLICATE:-0}" == 1 ]]; then
      printf '[{"number":7,"title":"Sync fails","url":"https://example.test/issues/7","state":"OPEN"}]\n'
    else
      printf '[]\n'
    fi
    ;;
  "issue create")
    while (($#)); do
      if [[ "$1" == --body-file ]]; then cp "$2" "$GH_CREATED_BODY"; fi
      shift
    done
    [[ "${GH_CREATE_FAIL:-0}" != 1 ]] || exit 42
    printf 'https://github.com/vs06101996/NetApp-GSD-Recipe/issues/99\n'
    ;;
esac
EOF
chmod +x "$fakebin/gh"
export GH_CALLS="$scratch/calls"
export GH_CREATED_BODY="$scratch/created-body"

output="$(PATH="$fakebin:$PATH" "$RUNNER" --title "Sync fails" --body-file "$scratch/body.md" --label enhancement --dry-run)"
grep -q "Dry run: no GitHub API calls were made" <<<"$output" &&
  grep -q "Label: enhancement" <<<"$output" &&
  grep -q "\[REDACTED\]" <<<"$output" &&
  grep -q "~/Projects/private-product/log.txt" <<<"$output" &&
  grep -q "Temporary path: \[LOCAL_PATH\]" <<<"$output" &&
  ! grep -q "private-token-value\|supersecret\|ghp_1234567890abcdefghijkl" <<<"$output" &&
  [[ ! -e "$GH_CALLS" ]]
check "dry-run redacts secrets and home path without calling GitHub" "$?"

description_output="$(
  PATH="$fakebin:$PATH" "$RUNNER" \
    --description "Hierarchy sync failed" \
    --expected "Epic should enter In Progress" \
    --command "recipe-sync" \
    --label bug \
    --dry-run
)"
grep -q "Title: Hierarchy sync failed" <<<"$description_output" &&
  grep -q "## What happened" <<<"$description_output" &&
  grep -q "## Expected behavior" <<<"$description_output" &&
  grep -q "## Safe diagnostics" <<<"$description_output" &&
  grep -q "Recipe revision:" <<<"$description_output" &&
  grep -q "Platform:" <<<"$description_output" &&
  grep -q 'Command: `recipe-sync`' <<<"$description_output"
check "description mode drafts a structured report with safe diagnostics" "$?"

PATH="$fakebin:$PATH" "$RUNNER" --title "Sync fails" --body-file "$scratch/body.md" >/dev/null 2>&1 && rc=0 || rc=$?
[[ "$rc" -ne 0 ]]; check "real post requires explicit confirmation" "$?"

: > "$GH_CALLS"
result="$(PATH="$fakebin:$PATH" "$RUNNER" --title "Sync fails" --body-file "$scratch/body.md" --label question --confirmed)"
grep -q "issues/99" <<<"$result" &&
  grep -q -- "--repo vs06101996/NetApp-GSD-Recipe" "$GH_CALLS" &&
  grep -q -- "--label question" "$GH_CALLS" &&
  ! grep -q "supersecret\|private-token-value" "$GH_CREATED_BODY"
check "confirmed post uses fixed repository, selected label, and sanitized body" "$?"

: > "$GH_CALLS"
GH_DUPLICATE=1 PATH="$fakebin:$PATH" "$RUNNER" --title "  SYNC   fails " --body-file "$scratch/body.md" --confirmed >/dev/null 2>"$scratch/duplicate.err" && rc=0 || rc=$?
[[ "$rc" == 3 ]] &&
  grep -q "https://example.test/issues/7" "$scratch/duplicate.err" &&
  ! grep -q "issue create" "$GH_CALLS"
check "exact normalized duplicate blocks creation and returns its URL" "$?"

GH_CREATE_FAIL=1 PATH="$fakebin:$PATH" "$RUNNER" --title "Different failure" --body-file "$scratch/body.md" --confirmed >/dev/null 2>&1 && rc=0 || rc=$?
[[ "$rc" == 42 ]]; check "GitHub create failure propagates without claiming success" "$?"

PATH="$fakebin:$PATH" "$RUNNER" --title "Title" --body-file "$scratch/body.md" --label incident --dry-run >/dev/null 2>&1 && rc=0 || rc=$?
[[ "$rc" -ne 0 ]]; check "unsupported labels fail closed" "$?"

echo "---"
echo "$pass passed, $fail failed"
[[ "$fail" == 0 ]]
