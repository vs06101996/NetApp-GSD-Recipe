#!/usr/bin/env bash
# Regression test for bench/lib/tracker-sync-config.sh (TASK-014).
# Run: ./bench/tests/test-tracker-sync-config.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CFG_LIB="$REPO_ROOT/bench/lib/tracker-sync-config.sh"

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

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
CONFIG="$SCRATCH/config.json"

# --- 1. get-tracker defaults to jira when the config file doesn't exist -----
rm -f "$CONFIG"
OUT1="$("$CFG_LIB" get-tracker --config "$CONFIG")"
[ "$OUT1" = "jira" ]
check "get-tracker defaults to jira when config file is missing" "$?"
[ ! -e "$CONFIG" ]
check "get-tracker never creates the config file as a side effect" "$?"

# --- 2. set-tracker jira, then get-tracker round-trips -----------------------
"$CFG_LIB" set-tracker jira --config "$CONFIG" >/dev/null
OUT2="$("$CFG_LIB" get-tracker --config "$CONFIG")"
[ "$OUT2" = "jira" ]
check "set-tracker jira then get-tracker round-trips to jira" "$?"

# --- 3. set-tracker github, then get-tracker round-trips ---------------------
"$CFG_LIB" set-tracker github --config "$CONFIG" >/dev/null
OUT3="$("$CFG_LIB" get-tracker --config "$CONFIG")"
[ "$OUT3" = "github" ]
check "set-tracker github then get-tracker round-trips to github" "$?"

# --- 4. set-tracker rejects an unsupported value (linear is NOT locked v1) ---
if "$CFG_LIB" set-tracker linear --config "$CONFIG" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "set-tracker rejects 'linear' (illustrative {TRACKER} example, not a locked v1 platform)" "$rc"

OUT4="$("$CFG_LIB" get-tracker --config "$CONFIG")"
[ "$OUT4" = "github" ]
check "a rejected set-tracker call leaves the existing config value untouched" "$?"

# --- 5. set-tracker preserves other keys already in the config file ---------
cat > "$CONFIG" <<'EOF'
{
  "some_other_setting": "keep-me",
  "tracker": "jira"
}
EOF
"$CFG_LIB" set-tracker github --config "$CONFIG" >/dev/null
python3 -c "
import json
d = json.load(open('$CONFIG'))
assert d['tracker'] == 'github', d
assert d['some_other_setting'] == 'keep-me', d
"
check "set-tracker merges into existing config, preserving unrelated keys" "$?"

# --- 6. get-tracker fails closed on an unsupported value already in the file ---
cat > "$CONFIG" <<'EOF'
{"tracker": "linear"}
EOF
if "$CFG_LIB" get-tracker --config "$CONFIG" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "get-tracker fails closed when the config file already has an unsupported tracker value" "$rc"

# --- 7. get-tracker fails on invalid JSON, doesn't silently default ---------
echo "not valid json {" > "$CONFIG"
if "$CFG_LIB" get-tracker --config "$CONFIG" >/dev/null 2>&1; then rc=1; else rc=0; fi
check "get-tracker fails on invalid JSON instead of silently defaulting" "$rc"

# --- 8. set-tracker rejects a missing value argument ------------------------
if "$CFG_LIB" set-tracker >/dev/null 2>&1; then rc=1; else rc=0; fi
check "set-tracker with no value argument fails" "$rc"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
