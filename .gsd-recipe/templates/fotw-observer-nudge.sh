#!/usr/bin/env bash
# FOTW observer trigger — postToolUse hook, matched on Write.
#
# Staged into <target_repo>/.cursor/hooks/fotw-observer-nudge.sh by
# .gsd-recipe/scripts/install-observer.sh. Do not hand-edit the staged copy;
# edit this template and re-run the installer instead.
#
# This is the *reactive, catch-all* trigger path — it fires on any matching
# Write regardless of which command produced it. The *deterministic* trigger
# path is the pluggable `.cursor/skills/fotw-observer-bootstrap/SKILL.md`
# skill, meant to be invoked as an explicit step from a future PRD-intake
# command (e.g. `recipe-prd-intake`, once it exists). Both paths share the
# same guard (`bench/lib/observer-lib.sh can-spawn`) and the same subagent
# instructions (`.gsd-recipe/templates/fotw-observer-task-prompt.md`), so
# behavior is identical no matter which one fires.
#
# Trigger condition (per lld/RUNTIME-LLD.md §1.a "PRD intake" and §1.b
# "Project bootstrap"): fires on the first Write to one of the concrete
# PRD-ingestion artifacts GSD/the recipe produce when an operator gives
# netapp-gsd a PRD to consume — there is no single "netapp-gsd command";
# PRD intake is a config layer over gsd-new-project / gsd-import /
# gsd-discuss-phase / gsd-ingest-docs, and these are the files it writes:
#   - docs/PRD.md                  (PRD intake artifact)
#   - .planning/intake/PRD.md      (PRD intake artifact, alt location)
#   - .planning/STATE.md           (project bootstrap, immediately follows intake)
#
# Behavior:
#   1. Log every invocation (debug instrumentation, cheap, unconditional —
#      useful for seeing hook fires even while the observer is disabled).
#   2. Only act on the PRD-intake signal paths above; silent otherwise.
#   3. Delegate the fail-closed + anti-double-spawn decision to the shared
#      `observer-lib.sh can-spawn` guard (single source of truth, also used
#      by the bootstrap skill and the test suite).
#   4. If allowed, write a target descriptor and nudge the primary agent via
#      additional_context to spawn a background Task subagent following the
#      shared task-prompt template.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="$REPO_ROOT/.gsd-recipe/lib/observer-lib.sh"
CONFIG="$REPO_ROOT/.gsd-recipe/observer-config.json"
LOG="$REPO_ROOT/.learnings/observer/.hook-debug.jsonl"
ACTIVE_MARKER="$REPO_ROOT/.gsd-recipe/.observer-active.json"
TARGET_FILE="$REPO_ROOT/.gsd-recipe/.observer-target.json"
TASK_PROMPT="$REPO_ROOT/.gsd-recipe/templates/fotw-observer-task-prompt.md"

mkdir -p "$(dirname "$LOG")" "$(dirname "$ACTIVE_MARKER")"

INPUT="$(cat)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
printf '{"ts":"%s","raw_stdin":%s}\n' "$TS" "$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')" >> "$LOG"

FILE_PATH="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))')"

case "$FILE_PATH" in
  */docs/PRD.md|*/.planning/intake/PRD.md|*/.planning/STATE.md) : ;;  # real PRD-intake / bootstrap signal
  *) echo '{}'; exit 0 ;;                                              # not intake-relevant, stay silent
esac

SESSION_ID="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("session_id",""))')"
TRANSCRIPT_PATH="$(printf '%s' "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("transcript_path",""))')"

if ! REASON="$("$LIB" can-spawn "$CONFIG" "$ACTIVE_MARKER" "$SESSION_ID")"; then
  case "$REASON" in
    "blocked: session $SESSION_ID"*)
      echo '{"additional_context":"FOTW_HOOK: observer already marked active for this session, no nudge (anti-double-spawn working)."}'
      ;;
    *)
      echo '{}'  # disabled or not installed — fail closed, stay silent
      ;;
  esac
  exit 0
fi

python3 - "$SESSION_ID" "$TRANSCRIPT_PATH" "$TS" "$FILE_PATH" <<'PY' > "$TARGET_FILE"
import json, sys
session_id, transcript_path, ts, matched_path = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
print(json.dumps({
    "session_id": session_id,
    "transcript_path": transcript_path,
    "discovered_at": ts,
    "matched_signal_path": matched_path
}, indent=2))
PY

echo '{"additional_context":"FOTW_HOOK_NUDGE: PRD-intake signal detected ('"$FILE_PATH"'). No FOTW observer is marked active for this session. Spawn the observer now via Task(subagent_type=generalPurpose, run_in_background=true), following the instructions in '"$TASK_PROMPT"' with target descriptor .gsd-recipe/.observer-target.json, then mark .gsd-recipe/.observer-active.json for this session_id."}'
exit 0
