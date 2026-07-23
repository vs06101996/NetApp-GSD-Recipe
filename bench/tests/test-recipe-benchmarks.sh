#!/usr/bin/env bash
# Smoke test for field benchmark JSON + generate-recipe-benchmarks.sh.
# Run: ./bench/tests/test-recipe-benchmarks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GENERATOR="$REPO_ROOT/bench/lib/generate-recipe-benchmarks.sh"
JSON="$REPO_ROOT/docs/netapp-recipe/benchmarks/kb-evaluations-agentstudio-2026-07.json"
DOC="$REPO_ROOT/docs/netapp-recipe/BENCHMARKS.md"

check() {
  local label="$1" rc="$2"
  if [ "$rc" -eq 0 ]; then echo "PASS: $label"; else echo "FAIL: $label"; exit 1; fi
}

[ -x "$GENERATOR" ] || chmod +x "$GENERATOR"
[ -f "$JSON" ]
check "kb-evaluations benchmark JSON exists" "$?"

python3 - "$JSON" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r["id"] == "kb-evaluations-agentstudio-2026-07"
assert r["tracker"]["issue_key"] == "KAN-53"
assert r["ship_artifact"]["number"] == 465
assert len(r["arms"]) >= 2
PY
check "benchmark JSON validates required fields" "$?"

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
"$GENERATOR" --out "$TMP"
grep -q "kb-evaluations-agentstudio-2026-07" "$TMP"
check "generator emits benchmark id" "$?"
grep -q "KAN-53" "$TMP"
check "generator emits Jira link" "$?"
grep -q "AgentStudio" "$TMP"
check "generator emits target repo" "$?"
grep -q "Field benchmarks" "$TMP"
check "generator emits field benchmarks section" "$?"
grep -q "3" "$TMP"
check "generator emits recipe wall-clock" "$?"

"$GENERATOR" >/dev/null
grep -q "Field benchmark summary" "$DOC"
check "committed BENCHMARKS.md exists" "$?"

echo "All recipe-benchmarks checks passed."
