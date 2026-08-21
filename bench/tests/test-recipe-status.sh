#!/usr/bin/env bash
# recipe-status.sh snapshot (TASK-060). Run: ./bench/tests/test-recipe-status.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HELPER="$REPO_ROOT/bench/lib/recipe-status.sh"

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

DIR="$(mktemp -d)"
(cd "$DIR" && git init -q && git commit --allow-empty -qm init)
mkdir -p "$DIR/docs" "$DIR/.planning" "$DIR/.knowledge" "$DIR/.planning/phases/01-alpha" "$DIR/.gsd-recipe"
printf '# PRD\n' > "$DIR/docs/PRD.md"
printf '# ROADMAP\n\n## Phase 1 Alpha\n' > "$DIR/.planning/ROADMAP.md"
printf -- '- epic: ABCD-1\n\n## Phase tasks\n\n| phase | issue |\n| --- | --- |\n| 1 | ABCD-2 |\n' > "$DIR/.planning/STATE.md"
printf '# index\n' > "$DIR/.knowledge/index.md"
printf '# plan\n' > "$DIR/.planning/phases/01-alpha/01-PLAN.md"
printf '{"jira_check":"pass"}\n' > "$DIR/.gsd-recipe/install-report.json"
printf '{"status":"queued"}\n' > "$DIR/.gsd-recipe/sync-queue.jsonl"
printf '{"key":"gsd-recipe:execute_complete:phase=1:issue=ABCD-2","ts":"2026-01-01T00:00:00Z","target":"jira","result":"posted"}\n' > "$DIR/.gsd-recipe/sync-ledger.jsonl"

OUT="$("$HELPER" --target "$DIR")"
echo "$OUT" | grep -q "=== Recipe status ===" && rc=0 || rc=$?
check "prints status banner" "$rc"
echo "$OUT" | grep -q "PRD:             yes" && rc=0 || rc=$?
check "detects PRD" "$rc"
echo "$OUT" | grep -q "Epic:            ABCD-1" && rc=0 || rc=$?
check "reads epic from STATE.md" "$rc"
echo "$OUT" | grep -q "phase 1: ABCD-2" && rc=0 || rc=$?
check "reads phase task key" "$rc"
echo "$OUT" | grep -q "PLAN=yes" && rc=0 || rc=$?
check "detects PLAN.md" "$rc"
echo "$OUT" | grep -q "Current phase:    1" && rc=0 || rc=$?
check "reports the current phase" "$rc"
echo "$OUT" | grep -q "Install Jira:    pass" && rc=0 || rc=$?
check "reads jira_check" "$rc"
echo "$OUT" | grep -q "Sync queue:      1 pending" && rc=0 || rc=$?
check "counts queued sync rows" "$rc"
echo "$OUT" | grep -q "Sync ledger:     1 entries" && rc=0 || rc=$?
check "counts sync ledger rows" "$rc"
echo "$OUT" | grep -q "Last sync:       execute_complete -> jira/posted at 2026-01-01T00:00:00Z" && rc=0 || rc=$?
check "reads last ledger event" "$rc"
echo "$OUT" | grep -q "=== Recipe next step ===" && rc=0 || rc=$?
check "appends recipe-next block" "$rc"

# Helper must not write
find "$DIR" -name '*.bak' | grep -q . && extra=1 || extra=0
[ "$extra" = "0" ]
check "does not leave extra bak files" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
