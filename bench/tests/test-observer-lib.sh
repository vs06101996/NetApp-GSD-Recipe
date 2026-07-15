#!/usr/bin/env bash
# Regression test for bench/lib/observer-lib.sh (FOTW observer spike primitives).
# Run: ./bench/tests/test-observer-lib.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/observer-lib.sh"
TMPDIR="$(mktemp -d)"
LIVE="$TMPDIR/live.jsonl"
OFFSET="$TMPDIR/.offset"
LOCK="$TMPDIR/.tick.lock"
TARGET="$TMPDIR/ticks.jsonl"

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

# 1. read-new on missing live file / missing offset file returns nothing, exit 0
OUT="$("$LIB" read-new "$LIVE" "$OFFSET")"
[ -z "$OUT" ]
check "read-new on missing files returns nothing" "$?"

# 2. append two lines, read-new with no offset sees both, numbered from 0
printf '{"a":1}\n{"a":2}\n' >> "$LIVE"
OUT="$("$LIB" read-new "$LIVE" "$OFFSET")"
EXPECTED=$'0\t{"a":1}\n1\t{"a":2}'
[ "$OUT" = "$EXPECTED" ]
check "read-new returns all lines with 0-based line numbers when no offset committed" "$?"

# 3. commit-offset then read-new only sees new lines
"$LIB" commit-offset "$OFFSET" 2
printf '{"a":3}\n' >> "$LIVE"
OUT="$("$LIB" read-new "$LIVE" "$OFFSET")"
[ "$OUT" = $'2\t{"a":3}' ]
check "read-new only returns lines after committed offset" "$?"

# 4. read-new does not advance the offset by itself
OFFSET_VAL="$(cat "$OFFSET")"
[ "$OFFSET_VAL" = "2" ]
check "read-new is a pure read, does not mutate offset file" "$?"

# 5. read-new at end of file (offset == total lines) returns nothing
"$LIB" commit-offset "$OFFSET" 3
OUT="$("$LIB" read-new "$LIVE" "$OFFSET")"
[ -z "$OUT" ]
check "read-new returns nothing once caught up" "$?"

# 6. commit-offset rejects non-numeric input
"$LIB" commit-offset "$OFFSET" "abc" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "commit-offset rejects non-integer value" "$?"

# 7. append-jsonl is append-only and creates parent dirs
"$LIB" append-jsonl "$TARGET" '{"tick":1}'
"$LIB" append-jsonl "$TARGET" '{"tick":2}'
LINES="$(wc -l < "$TARGET" | tr -d ' ')"
[ "$LINES" = "2" ]
check "append-jsonl appends without truncating, creates parent dir" "$?"

# 8. lock acquires once, second attempt fails while held
"$LIB" lock "$LOCK" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "lock acquires when free" "$?"
"$LIB" lock "$LOCK" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "1" ]
check "lock fails while already held" "$?"

# 9. unlock releases, lock can be re-acquired
"$LIB" unlock "$LOCK"
"$LIB" lock "$LOCK" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "lock re-acquirable after unlock" "$?"
"$LIB" unlock "$LOCK"

# 10. count-lines / size-bytes match reality, 0 on missing file
CL="$("$LIB" count-lines "$TARGET")"
[ "$CL" = "2" ]
check "count-lines matches actual line count" "$?"
CL_MISSING="$("$LIB" count-lines "$TMPDIR/does-not-exist.jsonl")"
[ "$CL_MISSING" = "0" ]
check "count-lines returns 0 for missing file" "$?"

# --- status / enable / disable / request-stop (TASK-032, recipe-observe) ---

STATUS_CONFIG="$TMPDIR/observer-config.json"
STATUS_ACTIVE="$TMPDIR/.observer-active.json"
STATUS_TICKS="$TMPDIR/status-ticks.jsonl"
STATUS_STOP="$TMPDIR/.stop"

# 11. status on a completely missing config reports not-installed, exit 0
STATUS_OUT="$("$LIB" status "$STATUS_CONFIG" "$STATUS_ACTIVE" "$STATUS_TICKS" "$STATUS_STOP")" && rc=0 || rc=$?
[ "$rc" = "0" ]
check "status exits 0 even when config_file is entirely missing" "$?"
echo "$STATUS_OUT" | grep -qx "installed: false" && rc=0 || rc=$?
check "status reports installed: false on a missing config_file" "$rc"
echo "$STATUS_OUT" | grep -qx "enabled: false" && rc=0 || rc=$?
check "status reports enabled: false when not installed" "$rc"
echo "$STATUS_OUT" | grep -qx "active: false" && rc=0 || rc=$?
check "status reports active: false when active_marker_file is missing" "$rc"
echo "$STATUS_OUT" | grep -qx "session_id: none" && rc=0 || rc=$?
check "status reports session_id: none when active_marker_file is missing" "$rc"
echo "$STATUS_OUT" | grep -qx "tick_count: 0" && rc=0 || rc=$?
check "status reports tick_count: 0 when ticks_file is missing" "$rc"
echo "$STATUS_OUT" | grep -qx "stop_requested: false" && rc=0 || rc=$?
check "status reports stop_requested: false when stop_sentinel_file is missing" "$rc"

# 12. status on a disabled config
printf '{"enabled": false, "other_key": "keep-me"}\n' > "$STATUS_CONFIG"
STATUS_OUT="$("$LIB" status "$STATUS_CONFIG" "$STATUS_ACTIVE" "$STATUS_TICKS" "$STATUS_STOP")"
echo "$STATUS_OUT" | grep -qx "installed: true" && rc=0 || rc=$?
check "status reports installed: true once config_file exists" "$rc"
echo "$STATUS_OUT" | grep -qx "enabled: false" && rc=0 || rc=$?
check "status reports enabled: false for a disabled config" "$rc"

# 13. status on an enabled config with an active marker and tick lines present
printf '{"enabled": true, "other_key": "keep-me"}\n' > "$STATUS_CONFIG"
printf '{"session_id": "abc-123"}\n' > "$STATUS_ACTIVE"
printf '{"line":0,"label":"signal"}\n{"line":1,"label":"noise_hedge"}\n{"line":2,"label":"signal"}\n' > "$STATUS_TICKS"
STATUS_OUT="$("$LIB" status "$STATUS_CONFIG" "$STATUS_ACTIVE" "$STATUS_TICKS" "$STATUS_STOP")"
echo "$STATUS_OUT" | grep -qx "enabled: true" && rc=0 || rc=$?
check "status reports enabled: true for an enabled config" "$rc"
echo "$STATUS_OUT" | grep -qx "active: true" && rc=0 || rc=$?
check "status reports active: true when active_marker_file exists" "$rc"
echo "$STATUS_OUT" | grep -qx "session_id: abc-123" && rc=0 || rc=$?
check "status reports the active marker's session_id" "$rc"
echo "$STATUS_OUT" | grep -qx "tick_count: 3" && rc=0 || rc=$?
check "status reports the real tick_count (same counting logic as count-lines)" "$rc"

# 14. status: stop sentinel present vs absent
echo "$STATUS_OUT" | grep -qx "stop_requested: false" && rc=0 || rc=$?
check "status reports stop_requested: false when the sentinel is absent" "$rc"
: > "$STATUS_STOP"
STATUS_OUT="$("$LIB" status "$STATUS_CONFIG" "$STATUS_ACTIVE" "$STATUS_TICKS" "$STATUS_STOP")"
echo "$STATUS_OUT" | grep -qx "stop_requested: true" && rc=0 || rc=$?
check "status reports stop_requested: true once the sentinel file exists" "$rc"
rm -f "$STATUS_STOP"

# 15. enable/disable round-trip preserves unrelated keys
ENABLE_CONFIG="$TMPDIR/enable-config.json"
printf '{"enabled": false, "tick_interval_seconds": 300, "paths": {"a": "b"}}\n' > "$ENABLE_CONFIG"
"$LIB" enable "$ENABLE_CONFIG" >/dev/null
python3 -c "
import json
d = json.load(open('$ENABLE_CONFIG'))
assert d['enabled'] is True, d
assert d['tick_interval_seconds'] == 300, d
assert d['paths'] == {'a': 'b'}, d
"
check "enable sets enabled:true and preserves unrelated keys" "$?"
"$LIB" disable "$ENABLE_CONFIG" >/dev/null
python3 -c "
import json
d = json.load(open('$ENABLE_CONFIG'))
assert d['enabled'] is False, d
assert d['tick_interval_seconds'] == 300, d
assert d['paths'] == {'a': 'b'}, d
"
check "disable sets enabled:false and preserves unrelated keys" "$?"

# 16. enable/disable fail closed on a missing config file
"$LIB" enable "$TMPDIR/does-not-exist-config.json" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "enable fails closed (non-zero exit) on a missing config_file" "$?"
[ ! -f "$TMPDIR/does-not-exist-config.json" ]
check "enable never creates a config_file from scratch" "$?"
"$LIB" disable "$TMPDIR/does-not-exist-config.json" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "disable fails closed (non-zero exit) on a missing config_file" "$?"

# 17. request-stop creates the file, is idempotent, and creates parent dirs
STOP_SENTINEL="$TMPDIR/nested/stop/.stop"
[ ! -f "$STOP_SENTINEL" ]
"$LIB" request-stop "$STOP_SENTINEL" >/dev/null
[ -f "$STOP_SENTINEL" ]
check "request-stop creates the sentinel file, including parent dirs" "$?"
"$LIB" request-stop "$STOP_SENTINEL" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "0" ]
check "request-stop is idempotent on a second call (still exit 0)" "$?"
[ -f "$STOP_SENTINEL" ]
check "request-stop leaves the sentinel file present after the second call" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
