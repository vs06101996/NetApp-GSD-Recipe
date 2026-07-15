#!/usr/bin/env bash
# Mechanical primitives for the FOTW observer feasibility spike (offset tracking,
# tick locking, append-only writes). Deliberately dumb and testable — the
# actual classification/summarization judgment lives in the agent tick prompt,
# not in this script.
#
# Contract (carried in-code):
#   lock <lockdir>                         mkdir-based atomic lock. exit 0 = acquired, 1 = already held.
#   unlock <lockdir>                       release a lock acquired above (idempotent).
#   read-new <live_file> <offset_file>     print "<line_no>\t<json_line>" for every line strictly
#                                           after the committed offset. Does NOT advance the offset.
#                                           Missing offset file == offset 0. Missing live_file == no output.
#   commit-offset <offset_file> <n>        atomically set the committed offset (write-then-rename).
#                                           Caller must only call this AFTER a read-new batch has been
#                                           fully classified and appended, never before.
#   append-jsonl <target_file> <json>      append one JSON line atomically (single buffered write).
#   count-lines <file>                     print line count, 0 if file missing.
#   size-bytes <file>                      print byte size, 0 if file missing.
#   can-spawn <config_file> <active_marker_file> <session_id>
#                                           shared spawn guard, used by every trigger path (hook,
#                                           skill, tests) so the rule lives in exactly one place.
#                                           exit 0 = spawn allowed, exit 1 = blocked. Reason on
#                                           stdout either way (machine-parseable, single line).
#                                           Blocked when: config_file missing (recipe not
#                                           installed -> fail closed); config's "enabled" is not
#                                           true; or active_marker_file already records this
#                                           exact session_id (anti-double-spawn).
#   status <config_file> <active_marker_file> <ticks_file> <stop_sentinel_file>
#                                           read-only, machine-parseable report for the
#                                           recipe-observe skill's `status` subcommand (TASK-032).
#                                           Prints one "key: value" line per fact, in this fixed
#                                           order:
#                                             config_file: <path>
#                                             installed: true|false        (config_file exists)
#                                             enabled: true|false          (config's "enabled";
#                                                                           missing/unparseable/
#                                                                           not-installed -> false)
#                                             active_marker_file: <path>
#                                             active: true|false           (active_marker_file exists)
#                                             session_id: <id>|none
#                                             ticks_file: <path>
#                                             tick_count: <n>              (same logic as count-lines)
#                                             stop_sentinel_file: <path>
#                                             stop_requested: true|false   (stop_sentinel_file exists)
#                                           Always exits 0 — this is a report, not a gate. Every
#                                           input file may be missing (not-installed/never-run is
#                                           a normal, reportable state, not an error).
#   enable <config_file>                   atomically sets "enabled": true in config_file's JSON,
#                                           preserving every other key (mktemp+mv, same atomicity
#                                           precedent as commit-offset). Fails closed (exit 1) with
#                                           a stderr message if config_file does not exist — this
#                                           command never creates one (that is install-observer.sh's
#                                           job).
#   disable <config_file>                  same as enable, sets "enabled": false. Same fail-closed
#                                           missing-file behavior.
#   request-stop <stop_sentinel_file>      creates stop_sentinel_file (mkdir -p its parent dir
#                                           first; empty file is fine — only existence is checked by
#                                           fotw-observer-task-prompt.md's own "explicit stop" step).
#                                           Idempotent: exit 0 whether the file already existed or
#                                           not. This only sets the graceful-finalize signal an
#                                           already-running tick loop checks at the top of its next
#                                           tick — it cannot forcibly stop a subagent that has
#                                           crashed or was never spawned; see
#                                           recipe-observe-SKILL.md's "stop" subcommand for the full
#                                           caveat.
#
# Usage:
#   bench/lib/observer-lib.sh lock .learnings/observer/.tick.lock
#   bench/lib/observer-lib.sh read-new .learnings/observer/live-transcript.jsonl .learnings/observer/.offset
#   bench/lib/observer-lib.sh commit-offset .learnings/observer/.offset 6
#   bench/lib/observer-lib.sh append-jsonl .learnings/observer/ticks.jsonl '{"line":1,"label":"signal"}'
#   bench/lib/observer-lib.sh can-spawn .gsd-recipe/observer-config.json .gsd-recipe/.observer-active.json abc-123
#   bench/lib/observer-lib.sh status .gsd-recipe/observer-config.json .gsd-recipe/.observer-active.json .learnings/observer/ticks.jsonl .learnings/observer/.stop
#   bench/lib/observer-lib.sh enable .gsd-recipe/observer-config.json
#   bench/lib/observer-lib.sh disable .gsd-recipe/observer-config.json
#   bench/lib/observer-lib.sh request-stop .learnings/observer/.stop
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage:
  observer-lib.sh lock <lockdir>
  observer-lib.sh unlock <lockdir>
  observer-lib.sh read-new <live_file> <offset_file>
  observer-lib.sh commit-offset <offset_file> <n>
  observer-lib.sh append-jsonl <target_file> <json>
  observer-lib.sh count-lines <file>
  observer-lib.sh size-bytes <file>
  observer-lib.sh can-spawn <config_file> <active_marker_file> <session_id>
  observer-lib.sh status <config_file> <active_marker_file> <ticks_file> <stop_sentinel_file>
  observer-lib.sh enable <config_file>
  observer-lib.sh disable <config_file>
  observer-lib.sh request-stop <stop_sentinel_file>
EOF
  exit 2
}

[ $# -ge 1 ] || usage
CMD="$1"; shift

case "$CMD" in
  lock)
    [ $# -eq 1 ] || usage
    LOCKDIR="$1"
    mkdir -p "$(dirname "$LOCKDIR")"
    if mkdir "$LOCKDIR" 2>/dev/null; then
      echo "$$" > "$LOCKDIR/pid"
      exit 0
    else
      exit 1
    fi
    ;;

  unlock)
    [ $# -eq 1 ] || usage
    LOCKDIR="$1"
    rm -rf "$LOCKDIR"
    ;;

  read-new)
    [ $# -eq 2 ] || usage
    LIVE_FILE="$1"; OFFSET_FILE="$2"
    OFFSET=0
    [ -f "$OFFSET_FILE" ] && OFFSET="$(tr -d ' \n' < "$OFFSET_FILE")"
    [ -z "$OFFSET" ] && OFFSET=0
    if [ ! -f "$LIVE_FILE" ]; then
      exit 0
    fi
    TOTAL="$(wc -l < "$LIVE_FILE" | tr -d ' ')"
    if [ "$OFFSET" -ge "$TOTAL" ]; then
      exit 0
    fi
    START=$((OFFSET + 1))
    awk -v start="$START" 'NR>=start {print (NR-1)"\t"$0}' "$LIVE_FILE"
    ;;

  commit-offset)
    [ $# -eq 2 ] || usage
    OFFSET_FILE="$1"; NEWVAL="$2"
    case "$NEWVAL" in
      ''|*[!0-9]*) echo "ERROR: offset must be a non-negative integer, got '$NEWVAL'" >&2; exit 2 ;;
    esac
    mkdir -p "$(dirname "$OFFSET_FILE")"
    TMP="${OFFSET_FILE}.tmp.$$"
    echo -n "$NEWVAL" > "$TMP"
    mv "$TMP" "$OFFSET_FILE"
    ;;

  append-jsonl)
    [ $# -eq 2 ] || usage
    TARGET="$1"; JSON="$2"
    mkdir -p "$(dirname "$TARGET")"
    printf '%s\n' "$JSON" >> "$TARGET"
    ;;

  count-lines)
    [ $# -eq 1 ] || usage
    F="$1"
    if [ -f "$F" ]; then wc -l < "$F" | tr -d ' '; else echo 0; fi
    ;;

  size-bytes)
    [ $# -eq 1 ] || usage
    F="$1"
    if [ -f "$F" ]; then wc -c < "$F" | tr -d ' '; else echo 0; fi
    ;;

  can-spawn)
    [ $# -eq 3 ] || usage
    CONFIG_FILE="$1"; ACTIVE_MARKER_FILE="$2"; SESSION_ID="$3"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "blocked: config_file missing ($CONFIG_FILE) - recipe not installed, fail closed"
      exit 1
    fi
    ENABLED="$(python3 -c 'import json; print(json.load(open("'"$CONFIG_FILE"'")).get("enabled", False))' 2>/dev/null || echo "False")"
    if [ "$ENABLED" != "True" ]; then
      echo "blocked: enabled is not true in $CONFIG_FILE"
      exit 1
    fi
    if [ -f "$ACTIVE_MARKER_FILE" ]; then
      ACTIVE_SESSION="$(python3 -c 'import json; print(json.load(open("'"$ACTIVE_MARKER_FILE"'")).get("session_id",""))' 2>/dev/null || echo "")"
      if [ "$ACTIVE_SESSION" = "$SESSION_ID" ]; then
        echo "blocked: session $SESSION_ID already marked active in $ACTIVE_MARKER_FILE"
        exit 1
      fi
    fi
    echo "allowed: enabled and no active marker for session $SESSION_ID"
    ;;

  status)
    [ $# -eq 4 ] || usage
    CONFIG_FILE="$1"; ACTIVE_MARKER_FILE="$2"; TICKS_FILE="$3"; STOP_SENTINEL_FILE="$4"

    INSTALLED="false"
    ENABLED="false"
    if [ -f "$CONFIG_FILE" ]; then
      INSTALLED="true"
      ENABLED_RAW="$(python3 -c 'import json; print(json.load(open("'"$CONFIG_FILE"'")).get("enabled", False))' 2>/dev/null || echo "False")"
      [ "$ENABLED_RAW" = "True" ] && ENABLED="true"
    fi

    ACTIVE="false"
    SESSION_ID="none"
    if [ -f "$ACTIVE_MARKER_FILE" ]; then
      ACTIVE="true"
      SESSION_ID="$(python3 -c 'import json; print(json.load(open("'"$ACTIVE_MARKER_FILE"'")).get("session_id","none"))' 2>/dev/null || echo "none")"
      [ -z "$SESSION_ID" ] && SESSION_ID="none"
    fi

    if [ -f "$TICKS_FILE" ]; then
      TICK_COUNT="$(wc -l < "$TICKS_FILE" | tr -d ' ')"
    else
      TICK_COUNT=0
    fi

    STOP_REQUESTED="false"
    [ -f "$STOP_SENTINEL_FILE" ] && STOP_REQUESTED="true"

    echo "config_file: $CONFIG_FILE"
    echo "installed: $INSTALLED"
    echo "enabled: $ENABLED"
    echo "active_marker_file: $ACTIVE_MARKER_FILE"
    echo "active: $ACTIVE"
    echo "session_id: $SESSION_ID"
    echo "ticks_file: $TICKS_FILE"
    echo "tick_count: $TICK_COUNT"
    echo "stop_sentinel_file: $STOP_SENTINEL_FILE"
    echo "stop_requested: $STOP_REQUESTED"
    exit 0
    ;;

  enable)
    [ $# -eq 1 ] || usage
    CONFIG_FILE="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "ERROR: config_file missing ($CONFIG_FILE) - recipe not installed, fail closed. enable never creates config.json itself (that is install-observer.sh's job)." >&2
      exit 1
    fi
    TMP="${CONFIG_FILE}.tmp.$$"
    python3 -c '
import json
path = "'"$CONFIG_FILE"'"
tmp = "'"$TMP"'"
with open(path) as f:
    data = json.load(f)
data["enabled"] = True
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
'
    mv "$TMP" "$CONFIG_FILE"
    echo "enabled: true in $CONFIG_FILE"
    ;;

  disable)
    [ $# -eq 1 ] || usage
    CONFIG_FILE="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
      echo "ERROR: config_file missing ($CONFIG_FILE) - recipe not installed, fail closed. disable never creates config.json itself (that is install-observer.sh's job)." >&2
      exit 1
    fi
    TMP="${CONFIG_FILE}.tmp.$$"
    python3 -c '
import json
path = "'"$CONFIG_FILE"'"
tmp = "'"$TMP"'"
with open(path) as f:
    data = json.load(f)
data["enabled"] = False
with open(tmp, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
'
    mv "$TMP" "$CONFIG_FILE"
    echo "enabled: false in $CONFIG_FILE"
    ;;

  request-stop)
    [ $# -eq 1 ] || usage
    STOP_SENTINEL_FILE="$1"
    mkdir -p "$(dirname "$STOP_SENTINEL_FILE")"
    touch "$STOP_SENTINEL_FILE"
    echo "stop requested: $STOP_SENTINEL_FILE"
    ;;

  *)
    usage
    ;;
esac
