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

seed_knowledge_artifacts() {
  local dir="$1"
  mkdir -p "$dir/.planning/codebase" "$dir/.planning/graphs"
  printf '# Stack\n\nLanguages and runtime for the repo under test.\n' > "$dir/.planning/codebase/STACK.md"
  printf '# Architecture\n\nLayered layout for the repo under test.\n' > "$dir/.planning/codebase/ARCHITECTURE.md"
  printf '{"nodes":[],"edges":[]}\n' > "$dir/.planning/graphs/graph.json"
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
echo "$OUT" | grep -q "recipe-onboard --skip-tracker" && rc=0 || rc=$?
check "ONBOARD how-text mentions --skip-tracker" "$rc"
echo "$OUT" | grep -q "docs/RECIPE-SEQUENCE.md" && rc=0 || rc=$?
check "ONBOARD how-text points at RECIPE-SEQUENCE.md" "$rc"
echo "$OUT" | grep -q "JIRA-PRD.input.template.md" && rc=0 || rc=$?
check "ONBOARD how-text exposes Jira/Confluence PRD input template" "$rc"
echo "$OUT" | grep -E "^Command: recipe-onboard$" && rc=0 || rc=$?
check "ONBOARD Command line stays recipe-onboard without flag" "$rc"

mkdir -p "$EMPTY/docs"
echo "# PRD" > "$EMPTY/docs/PRD.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "ONBOARD" ]
check "PRD without ROADMAP → ONBOARD" "$?"
OUT="$("$NEXT" --target "$EMPTY")"
echo "$OUT" | grep -q "JIRA-PRD.input.template.md" && rc=1 || rc=0
check "existing PRD suppresses Jira input instructions" "$rc"

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
printf '%s\n' '{"status":"ready"}' > "$EMPTY/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
seed_knowledge_artifacts "$EMPTY"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "PLAN" ]
check "knowledge marker + phase without PLAN.md → PLAN" "$?"

MARKER_ONLY="$(new_repo)"
mkdir -p "$MARKER_ONLY/.cursor/skills/recipe-onboard" "$MARKER_ONLY/.gsd-recipe" "$MARKER_ONLY/docs" "$MARKER_ONLY/.planning" "$MARKER_ONLY/.knowledge"
touch "$MARKER_ONLY/.cursor/skills/recipe-onboard/SKILL.md"
printf '{}\n' > "$MARKER_ONLY/.gsd-recipe/config.json"
echo "# PRD" > "$MARKER_ONLY/docs/PRD.md"
cat > "$MARKER_ONLY/.planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Demo
EOF
cat > "$MARKER_ONLY/.planning/STATE.md" <<'EOF'
## Tracker
- epic: DEMO-1
EOF
echo "# idx" > "$MARKER_ONLY/.knowledge/index.md"
printf '%s\n' '{"status":"ready"}' > "$MARKER_ONLY/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
ID="$("$NEXT" --id --target "$MARKER_ONLY")"
[ "$ID" = "BOOTSTRAP" ]
check "marker alone without map/graph artifacts → BOOTSTRAP" "$?"

mkdir -p "$EMPTY/.planning/phases/01-demo"
echo "# plan" > "$EMPTY/.planning/phases/01-demo/PLAN.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "RUN" ]
check "PLAN without SUMMARY → RUN" "$?"

echo "# done" > "$EMPTY/.planning/phases/01-demo/01-SUMMARY.md"
ID="$("$NEXT" --id --target "$EMPTY")"
[ "$ID" = "VERIFY" ]
check "SUMMARY present → VERIFY" "$?"

SKIP="$(new_repo)"
mkdir -p "$SKIP/.cursor/skills/recipe-onboard" "$SKIP/.gsd-recipe" "$SKIP/docs" "$SKIP/.planning"
touch "$SKIP/.cursor/skills/recipe-onboard/SKILL.md"
printf '{}\n' > "$SKIP/.gsd-recipe/config.json"
echo "# PRD" > "$SKIP/docs/PRD.md"
cat > "$SKIP/.planning/ROADMAP.md" <<'EOF'
# Roadmap
## Phase 1: Demo
EOF
ID="$("$NEXT" --id --target "$SKIP")"
[ "$ID" = "ONBOARD" ]
check "PRD+ROADMAP without Epic and without skip_tracker → ONBOARD" "$?"

printf '%s\n' '{"onboard":{"skip_tracker":true}}' > "$SKIP/.gsd-recipe/config.json"
ID="$("$NEXT" --id --target "$SKIP")"
[ "$ID" = "BOOTSTRAP" ]
check "skip_tracker with PRD+ROADMAP and no Epic → BOOTSTRAP" "$?"

mkdir -p "$SKIP/.knowledge"
cat > "$SKIP/.knowledge/index.md" <<'EOF'
# Knowledge Index
not by install.sh itself.
EOF
ID="$("$NEXT" --id --target "$SKIP")"
[ "$ID" = "BOOTSTRAP" ]
check "install stub .knowledge/index.md does not count as bootstrapped" "$?"

echo "# real" > "$SKIP/.knowledge/index.md"
printf '%s\n' '{"status":"ready"}' > "$SKIP/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
seed_knowledge_artifacts "$SKIP"
ID="$("$NEXT" --id --target "$SKIP")"
[ "$ID" = "PLAN" ]
check "knowledge readiness marker with skip_tracker → PLAN" "$?"

GSD="$(new_repo)"
mkdir -p "$GSD/.cursor/skills/recipe-onboard" "$GSD/.gsd-recipe" "$GSD/docs" "$GSD/.planning" "$GSD/.knowledge"
touch "$GSD/.cursor/skills/recipe-onboard/SKILL.md"
printf '%s\n' '{"onboard":{"skip_tracker":true}}' > "$GSD/.gsd-recipe/config.json"
echo "# PRD" > "$GSD/docs/PRD.md"
cp "$REPO_ROOT/bench/tests/fixtures/roadmap-gsd-dialect-sample.md" "$GSD/.planning/ROADMAP.md"
echo "# real" > "$GSD/.knowledge/index.md"
printf '%s\n' '{"status":"ready"}' > "$GSD/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
seed_knowledge_artifacts "$GSD"
ID="$("$NEXT" --id --target "$GSD")"
[ "$ID" = "PLAN" ]
check "GSD-dialect ### Phase headings still resolve to PLAN" "$?"

cmp -s "$REPO_ROOT/bench/lib/recipe-next.sh" "$REPO_ROOT/.gsd-recipe/scripts/recipe-next.sh"
check "bench/lib and .gsd-recipe/scripts recipe-next.sh stay identical" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
