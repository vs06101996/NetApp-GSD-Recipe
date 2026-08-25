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
printf '%s\n' '{"status":"ready"}' > "$DIR/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
mkdir -p "$DIR/.planning/codebase" "$DIR/.planning/graphs"
printf '# Stack\n\nLanguages and runtime for the repo under test.\n' > "$DIR/.planning/codebase/STACK.md"
printf '# Architecture\n\nLayered layout for the repo under test.\n' > "$DIR/.planning/codebase/ARCHITECTURE.md"
printf '{"nodes":[],"edges":[]}\n' > "$DIR/.planning/graphs/graph.json"
printf '# plan\n' > "$DIR/.planning/phases/01-alpha/01-PLAN.md"
printf '{"jira_check":"pass"}\n' > "$DIR/.gsd-recipe/install-report.json"
printf '{"status":"queued"}\n' > "$DIR/.gsd-recipe/sync-queue.jsonl"
printf '{"event_id":"execute_complete","target":"jira","result":"posted","ts":"2026-01-01T00:00:00Z"}\n' > "$DIR/.gsd-recipe/sync-ledger.jsonl"

OUT="$("$HELPER" --target "$DIR")"
echo "$OUT" | grep -q "=== Recipe status ===" && rc=0 || rc=$?
check "prints status banner" "$rc"
echo "$OUT" | grep -q "PRD:             yes" && rc=0 || rc=$?
check "detects PRD" "$rc"
echo "$OUT" | grep -q "Knowledge:       yes" && rc=0 || rc=$?
check "knowledge marker reports ready" "$rc"

MARKER="$(mktemp -d)"
(cd "$MARKER" && git init -q && git commit --allow-empty -qm init)
mkdir -p "$MARKER/.gsd-recipe"
printf '%s\n' '{"status":"ready"}' > "$MARKER/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
MARKER_OUT="$("$HELPER" --target "$MARKER")"
echo "$MARKER_OUT" | grep -q "Knowledge:       no" && rc=0 || rc=$?
check "marker without map/graph artifacts is not ready" "$rc"
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

STUB="$(mktemp -d)"
(cd "$STUB" && git init -q && git commit --allow-empty -qm init)
mkdir -p "$STUB/docs" "$STUB/.planning" "$STUB/.knowledge" "$STUB/.gsd-recipe"
printf '# PRD\n' > "$STUB/docs/PRD.md"
printf '# ROADMAP\n\n## Phase 1 Alpha\n' > "$STUB/.planning/ROADMAP.md"
printf -- '- tracker: none\n' > "$STUB/.planning/STATE.md"
printf '%s\n' '{"onboard":{"skip_tracker":true}}' > "$STUB/.gsd-recipe/config.json"
cat > "$STUB/.knowledge/index.md" <<'EOF'
# Knowledge Index
not by install.sh itself.
EOF
STUB_OUT="$("$HELPER" --target "$STUB")"
echo "$STUB_OUT" | grep -q "Epic:            (skipped)" && rc=0 || rc=$?
check "skip_tracker with no epic key prints Epic (skipped)" "$rc"
echo "$STUB_OUT" | grep -q "Knowledge:       no" && rc=0 || rc=$?
check "install stub knowledge index is not yes" "$rc"

find "$DIR" -name '*.bak' | grep -q . && extra=1 || extra=0
[ "$extra" = "0" ]
check "does not leave extra bak files" "$?"

GSD="$(mktemp -d)"
(cd "$GSD" && git init -q && git commit --allow-empty -qm init)
mkdir -p "$GSD/docs" "$GSD/.planning" "$GSD/.knowledge" "$GSD/.gsd-recipe"
printf '# PRD\n' > "$GSD/docs/PRD.md"
cp "$REPO_ROOT/bench/tests/fixtures/roadmap-gsd-dialect-sample.md" "$GSD/.planning/ROADMAP.md"
printf -- '- epic: ABCD-1\n' > "$GSD/.planning/STATE.md"
printf '# index\n' > "$GSD/.knowledge/index.md"
GSD_OUT="$("$HELPER" --target "$GSD")"
echo "$GSD_OUT" | grep -q "Current phase:    1" && rc=0 || rc=$?
check "GSD-dialect ### Phase N headings are numbered" "$rc"
echo "$GSD_OUT" | grep -q "  2: PLAN=" && rc=0 || rc=$?
check "GSD-dialect ROADMAP lists phase 2" "$rc"

cmp -s "$REPO_ROOT/bench/lib/recipe-status.sh" "$REPO_ROOT/.gsd-recipe/scripts/recipe-status.sh"
check "bench/lib and .gsd-recipe/scripts recipe-status.sh stay identical" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
