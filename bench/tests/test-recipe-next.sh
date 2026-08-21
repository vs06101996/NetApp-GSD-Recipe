#!/usr/bin/env bash
# Regression test for bench/lib/recipe-next.sh (TASK-056 resolver).
# Run: ./bench/tests/test-recipe-next.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NEXT="$REPO_ROOT/bench/lib/recipe-next.sh"

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

new_repo() {
  local dir
  dir="$(mktemp -d)"
  (cd "$dir" && git init -q && git commit --allow-empty -qm init)
  echo "$dir"
}

EMPTY="$(new_repo)"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "INSTALL" ]
check "empty repo with no recipe → INSTALL" "$?"

mkdir -p "$EMPTY/.cursor/skills/recipe-onboard" "$EMPTY/.gsd-recipe"
touch "$EMPTY/.cursor/skills/recipe-onboard/SKILL.md"
printf '{}\n' > "$EMPTY/.gsd-recipe/config.json"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "ONBOARD" ]
check "skills present, no PRD → ONBOARD" "$?"

OUT="$("$NEXT" --target "$EMPTY")"
echo "$OUT" | grep -q "recipe-onboard"
check "friendly output mentions recipe-onboard" "$?"
echo "$OUT" | grep -q "Type this in Cursor Agent"
check "friendly output has Cursor Agent heading" "$?"
echo "$OUT" | grep -q "recipe-onboard docs/PRD.md" && rc=1 || rc=0
check "no-PRD output does not suggest a missing PRD path" "$rc"

mkdir -p "$EMPTY/docs"
echo "# PRD" > "$EMPTY/docs/PRD.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "ONBOARD" ]
check "PRD without ROADMAP → ONBOARD" "$?"

mkdir -p "$EMPTY/.planning"
cat > "$EMPTY/.planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Demo
EOF
cat > "$EMPTY/.planning/STATE.md" <<'EOF'
## Tracker
- epic: DEMO-1
EOF
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "BOOTSTRAP" ]
check "onboarded without knowledge → BOOTSTRAP" "$?"

mkdir -p "$EMPTY/.knowledge"
echo "# idx" > "$EMPTY/.knowledge/index.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "PLAN" ]
check "knowledge + phase without PLAN.md → PLAN" "$?"

mkdir -p "$EMPTY/.planning/phases/01-demo"
echo "# plan" > "$EMPTY/.planning/phases/01-demo/PLAN.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "RUN" ]
check "PLAN without SUMMARY → RUN" "$?"

echo "# done" > "$EMPTY/.planning/phases/01-demo/01-SUMMARY.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "VERIFY" ]
check "SUMMARY present → VERIFY" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
