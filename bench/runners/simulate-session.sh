#!/usr/bin/env bash
# Simulates a live, growing conversation by appending lines from a fixture
# transcript into a destination file in small batches, on a delay. Used by
# the FOTW observer feasibility spike to test capture fidelity and end
# triggers without a real chat session.
#
# Usage:
#   simulate-session.sh <source_file> <dest_file> [--batch-size N] [--delay SECONDS]
#                        [--max-lines N] [--start-line N]
#
# Defaults: --batch-size 2 --delay 8 --start-line 0 (0-based, inclusive)
#           --max-lines <all remaining lines in source>
#
# Each append is a single buffered write of the whole batch (one call, one
# flush) so downstream capture-fidelity checks (no torn/partial lines) hold.
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  simulate-session.sh <source_file> <dest_file> [--batch-size N] [--delay SECONDS]
                       [--max-lines N] [--start-line N]
EOF
  exit 2
}

[ $# -ge 2 ] || usage
SOURCE="$1"; DEST="$2"; shift 2
BATCH_SIZE=2
DELAY=8
MAX_LINES=""
START_LINE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --batch-size) BATCH_SIZE="${2:?--batch-size requires a value}"; shift 2 ;;
    --delay) DELAY="${2:?--delay requires a value}"; shift 2 ;;
    --max-lines) MAX_LINES="${2:?--max-lines requires a value}"; shift 2 ;;
    --start-line) START_LINE="${2:?--start-line requires a value}"; shift 2 ;;
    *) echo "ERROR: unknown flag '$1'" >&2; usage ;;
  esac
done

[ -f "$SOURCE" ] || { echo "ERROR: source file not found: $SOURCE" >&2; exit 1; }
mkdir -p "$(dirname "$DEST")"
touch "$DEST"

TOTAL_LINES="$(wc -l < "$SOURCE" | tr -d ' ')"
END_LINE=$((TOTAL_LINES - 1))
if [ -n "$MAX_LINES" ]; then
  CAP=$((START_LINE + MAX_LINES - 1))
  [ "$CAP" -lt "$END_LINE" ] && END_LINE="$CAP"
fi

echo "SIMULATE_SESSION_START source=$SOURCE dest=$DEST lines=${START_LINE}-${END_LINE} batch=${BATCH_SIZE} delay=${DELAY}s"

LINE="$START_LINE"
while [ "$LINE" -le "$END_LINE" ]; do
  BATCH_END=$((LINE + BATCH_SIZE - 1))
  [ "$BATCH_END" -gt "$END_LINE" ] && BATCH_END="$END_LINE"
  # sed is 1-indexed; our line numbers are 0-indexed.
  sed -n "$((LINE + 1)),$((BATCH_END + 1))p" "$SOURCE" >> "$DEST"
  echo "SIMULATE_SESSION_APPENDED lines=${LINE}-${BATCH_END}"
  LINE=$((BATCH_END + 1))
  if [ "$LINE" -le "$END_LINE" ]; then
    sleep "$DELAY"
  fi
done

echo "SIMULATE_SESSION_DONE last_line=${END_LINE}"
