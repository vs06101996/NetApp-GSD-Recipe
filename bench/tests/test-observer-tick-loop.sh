#!/usr/bin/env bash
# Proves the observer can run a real *repeated* tick loop against a moving
# offset (not the one-shot single-window classification the hook-trigger
# spike left as an open gap — see bench/report/fotw-hook-trigger-spike-report.md
# "remaining unknowns" #2). Drives bench/runners/simulate-session.sh to grow
# a live file in the background, and runs a small stand-in tick loop in the
# foreground using the exact primitives from bench/lib/observer-lib.sh that
# .gsd-recipe/templates/fotw-observer-task-prompt.md specifies. The stand-in
# classifier is a trivial substring rule (real classification is agent
# judgment, not scriptable) — this test is about the mechanical loop
# machinery (offset advancing across ticks, incremental appends, end-trigger
# detection), not classification quality.
# Run: ./bench/tests/test-observer-tick-loop.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/bench/lib/observer-lib.sh"
SIMULATE="$REPO_ROOT/bench/runners/simulate-session.sh"

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

# One tick: read-new, classify trivially, append, commit-offset. Prints the
# number of lines processed this tick (0 if caught up).
run_one_tick() {
  local live="$1" offset="$2" ticks="$3" noise="$4"
  local batch max_line count=0
  batch="$("$LIB" read-new "$live" "$offset")"
  [ -z "$batch" ] && { echo 0; return 0; }
  max_line=""
  while IFS=$'\t' read -r line_no json_line; do
    [ -z "$line_no" ] && continue
    count=$((count + 1))
    max_line="$line_no"
    case "$json_line" in
      *NOISE*) "$LIB" append-jsonl "$noise" "{\"line\":$line_no,\"label\":\"noise_irrelevant\"}" ;;
      *)       "$LIB" append-jsonl "$ticks" "{\"line\":$line_no,\"label\":\"signal\"}" ;;
    esac
  done <<< "$batch"
  "$LIB" commit-offset "$offset" "$((max_line + 1))"
  echo "$count"
}

# --- Scenario A: multi-tick loop with a growing transcript, offset advances
#     more than once, ticks.jsonl grows incrementally across ticks. ---

WORK_A="$(mktemp -d)"
SOURCE_A="$WORK_A/fixture.jsonl"
for i in $(seq 1 12); do
  if [ $((i % 4)) -eq 0 ]; then
    echo "{\"turn\":$i,\"text\":\"NOISE off-topic aside\"}" >> "$SOURCE_A"
  else
    echo "{\"turn\":$i,\"text\":\"on-topic decision number $i\"}" >> "$SOURCE_A"
  fi
done
LIVE_A="$WORK_A/live.jsonl"
OFFSET_A="$WORK_A/.offset"
TICKS_A="$WORK_A/ticks.jsonl"
NOISE_A="$WORK_A/noise-log.jsonl"

"$SIMULATE" "$SOURCE_A" "$LIVE_A" --batch-size 3 --delay 1 >/dev/null 2>&1 &
SIM_PID=$!

offsets_seen=()
ticks_after_each_tick=()
for _ in $(seq 1 6); do
  n="$(run_one_tick "$LIVE_A" "$OFFSET_A" "$TICKS_A" "$NOISE_A")"
  offsets_seen+=("$(cat "$OFFSET_A" 2>/dev/null || echo 0)")
  ticks_after_each_tick+=("$("$LIB" count-lines "$TICKS_A")")
  sleep 1
done
wait "$SIM_PID" 2>/dev/null || true
# One final tick to catch anything appended after our last sleep.
run_one_tick "$LIVE_A" "$OFFSET_A" "$TICKS_A" "$NOISE_A" >/dev/null

DISTINCT_OFFSETS="$(printf '%s\n' "${offsets_seen[@]}" | sort -u | wc -l | tr -d ' ')"
[ "$DISTINCT_OFFSETS" -ge 3 ]
check "offset advances across multiple ticks (saw $DISTINCT_OFFSETS distinct values, not just one-shot)" "$?"

FINAL_TICKS="$("$LIB" count-lines "$TICKS_A")"
FIRST_NONZERO_TICKS="${ticks_after_each_tick[1]:-0}"
[ "$FINAL_TICKS" -gt "$FIRST_NONZERO_TICKS" ]
check "ticks.jsonl keeps growing across later ticks, not frozen after the first" "$?"

TOTAL_SIGNAL="$("$LIB" count-lines "$TICKS_A")"
TOTAL_NOISE="$("$LIB" count-lines "$NOISE_A")"
[ "$((TOTAL_SIGNAL + TOTAL_NOISE))" = "12" ]
check "every one of the 12 fixture lines was eventually classified (signal + noise = 12)" "$?"
[ "$TOTAL_NOISE" = "3" ]
check "the 3 NOISE-marked lines landed in noise-log.jsonl" "$?"

# --- Scenario B: explicit stop sentinel halts the loop before it would
#     otherwise keep ticking. ---

WORK_B="$(mktemp -d)"
LIVE_B="$WORK_B/live.jsonl"
OFFSET_B="$WORK_B/.offset"
TICKS_B="$WORK_B/ticks.jsonl"
NOISE_B="$WORK_B/noise-log.jsonl"
STOP_B="$WORK_B/.stop"

printf '{"turn":1,"text":"first decision"}\n{"turn":2,"text":"second decision"}\n' > "$LIVE_B"
run_one_tick "$LIVE_B" "$OFFSET_B" "$TICKS_B" "$NOISE_B" >/dev/null

# More lines land, but a stop sentinel appears before the next tick checks it.
printf '{"turn":3,"text":"third decision, should never be processed"}\n' >> "$LIVE_B"
touch "$STOP_B"

should_finalize() { [ -f "$STOP_B" ]; }
if should_finalize; then
  FINALIZED=1
else
  run_one_tick "$LIVE_B" "$OFFSET_B" "$TICKS_B" "$NOISE_B" >/dev/null
  FINALIZED=0
fi
[ "$FINALIZED" = "1" ]
check "explicit stop_sentinel_file is detected before the next tick would run" "$?"

LINES_PROCESSED_B="$("$LIB" count-lines "$TICKS_B")"
[ "$LINES_PROCESSED_B" = "2" ]
check "the line written after the stop sentinel was correctly never processed" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
