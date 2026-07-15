#!/usr/bin/env bash
# Regression test for the staged .cursor/hooks/fotw-observer-nudge.sh hook,
# and indirectly for the shared bench/lib/observer-lib.sh can-spawn guard it
# now delegates to. Formalizes the ad hoc synthetic-stdin scenarios run
# during development into a checked-in, repeatable test.
# Run: ./bench/tests/test-fotw-observer-nudge.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-observer.sh"

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

TARGET="$(mktemp -d)"
(cd "$TARGET" && git init -q && git commit --allow-empty -qm init)
"$INSTALLER" --yes --target "$TARGET" >/dev/null
HOOK="$TARGET/.cursor/hooks/fotw-observer-nudge.sh"
CONFIG="$TARGET/.gsd-recipe/observer-config.json"
ACTIVE="$TARGET/.gsd-recipe/.observer-active.json"

payload() {
  # $1 = file_path, $2 = session_id, $3 = transcript_path
  printf '{"tool_name":"Write","tool_input":{"file_path":"%s"},"session_id":"%s","transcript_path":"%s"}' "$1" "$2" "$3"
}

has_key() {
  # $1 = json string, $2 = key -> exit 0 if key present
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); sys.exit(0 if sys.argv[2] in d else 1)" "$1" "$2"
}

contains() {
  # $1 = haystack, $2 = needle -> exit 0/1, never triggers `set -e` on no-match
  case "$1" in
    *"$2"*) return 0 ;;
    *) return 1 ;;
  esac
}

# 1. Irrelevant Write path stays silent
OUT="$(payload "$TARGET/README.md" s1 /tmp/t1.jsonl | "$HOOK")"
[ "$OUT" = "{}" ]
check "irrelevant Write path returns {} (silent)" "$?"

# 2. Write to .planning/STATE.md nudges
OUT="$(payload "$TARGET/.planning/STATE.md" s1 /tmp/t1.jsonl | "$HOOK")"
has_key "$OUT" additional_context && rc=0 || rc=$?
check "Write to .planning/STATE.md returns additional_context nudge" "$rc"
contains "$OUT" "FOTW_HOOK_NUDGE" && rc=0 || rc=$?
check "nudge text is identifiable as FOTW_HOOK_NUDGE" "$rc"
[ -f "$TARGET/.gsd-recipe/.observer-target.json" ]
check "target descriptor is written on nudge" "$?"

# 3. docs/PRD.md also matches
OUT="$(payload "$TARGET/docs/PRD.md" s2 /tmp/t2.jsonl | "$HOOK")"
contains "$OUT" "FOTW_HOOK_NUDGE" && rc=0 || rc=$?
check "Write to docs/PRD.md also nudges" "$rc"

# 4. .planning/intake/PRD.md also matches
OUT="$(payload "$TARGET/.planning/intake/PRD.md" s3 /tmp/t3.jsonl | "$HOOK")"
contains "$OUT" "FOTW_HOOK_NUDGE" && rc=0 || rc=$?
check "Write to .planning/intake/PRD.md also nudges" "$rc"

# 5. Anti-double-spawn: same session marked active stays silent (distinct message)
echo '{"session_id":"s1"}' > "$ACTIVE"
OUT="$(payload "$TARGET/docs/PRD.md" s1 /tmp/t1.jsonl | "$HOOK")"
contains "$OUT" "already marked active" && rc=0 || rc=$?
check "same session already marked active gets the distinct anti-double-spawn message" "$rc"

# 6. Different session still nudges despite another session's active marker
OUT="$(payload "$TARGET/docs/PRD.md" s4 /tmp/t4.jsonl | "$HOOK")"
contains "$OUT" "FOTW_HOOK_NUDGE" && rc=0 || rc=$?
check "a different session_id still nudges (per-session scoping)" "$rc"

# 7. Disabled config stays silent even on a matching path
python3 -c "
import json
p = '$CONFIG'
d = json.load(open(p)); d['enabled'] = False
json.dump(d, open(p, 'w'))
"
OUT="$(payload "$TARGET/.planning/STATE.md" s5 /tmp/t5.jsonl | "$HOOK")"
[ "$OUT" = "{}" ]
check "disabled config silences a matching path" "$?"

# 8. Missing config entirely stays silent (fail closed)
rm "$CONFIG"
OUT="$(payload "$TARGET/.planning/STATE.md" s6 /tmp/t6.jsonl | "$HOOK")"
[ "$OUT" = "{}" ]
check "missing observer-config.json fails closed (silent)" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
