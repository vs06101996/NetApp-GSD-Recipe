#!/usr/bin/env bash
# Guardrail tests for recipe-verify-knowledge.sh and recipe_knowledge.py
# Run: ./bench/tests/test-recipe-verify-knowledge.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$REPO_ROOT/bench/lib/recipe-verify-knowledge.sh"
PLANNING_VERIFY="$REPO_ROOT/bench/lib/recipe-verify-planning.sh"

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

seed_ready() {
  local dir="$1"
  mkdir -p "$dir/.gsd-recipe" "$dir/.planning/codebase" "$dir/.planning/graphs"
  printf '# Stack\n\nLanguages and runtime for the repo under test.\n' > "$dir/.planning/codebase/STACK.md"
  printf '# Architecture\n\nLayered layout for the repo under test.\n' > "$dir/.planning/codebase/ARCHITECTURE.md"
  printf '{"nodes":[],"edges":[]}\n' > "$dir/.planning/graphs/graph.json"
  printf '%s\n' '{"status":"ready"}' > "$dir/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
}

FAKEBIN="$(mktemp -d)"
cat > "$FAKEBIN/graphify" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
  echo "graphify — knowledge graph CLI (test stub)"
  exit 0
fi
exit 0
EOF
chmod +x "$FAKEBIN/graphify"
export PATH="$FAKEBIN:$PATH"

EMPTY="$(new_repo)"
("$VERIFY" --target "$EMPTY") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "empty repo fails knowledge verify" "$?"

MARKER="$(new_repo)"
mkdir -p "$MARKER/.gsd-recipe"
printf '%s\n' '{"status":"ready"}' > "$MARKER/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --target "$MARKER") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "marker-only repo fails verify" "$?"

READY="$(new_repo)"
seed_ready "$READY"
("$VERIFY" --target "$READY") && rc=0 || rc=$?
check "marker + map + graph passes verify" "$rc"

WRITE="$(new_repo)"
seed_ready "$WRITE"
rm -f "$WRITE/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --write-marker --target "$WRITE") && rc=0 || rc=$?
check "write-marker succeeds when artifacts present" "$rc"
[ -f "$WRITE/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED" ]
check "write-marker creates KNOWLEDGE-BOOTSTRAPPED" "$?"

STUBBIN="$(mktemp -d)"
cat > "$STUBBIN/graphify" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$STUBBIN/graphify"
NOWRITE="$(new_repo)"
seed_ready "$NOWRITE"
rm -f "$NOWRITE/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
(PATH="$STUBBIN:$PATH" "$VERIFY" --write-marker --target "$NOWRITE") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "write-marker fails on no-op graphify stub" "$?"

PLAN="$(new_repo)"
mkdir -p "$PLAN/.planning"
printf '# Project\n\nDemo project with enough content for planning guardrails.\n' > "$PLAN/.planning/PROJECT.md"
printf '# Roadmap\n\n## Phase 1 — Demo\n\nFirst delivery phase for the demo feature.\n' > "$PLAN/.planning/ROADMAP.md"
printf '## Tracker\n\n- epic: DEMO-1\n- system: recipe-test\n- run_id: local\n' > "$PLAN/.planning/STATE.md"
("$PLANNING_VERIFY" --target "$PLAN") && rc=0 || rc=$?
check "planning verify passes valid planning trio" "$rc"

BADPLAN="$(new_repo)"
mkdir -p "$BADPLAN/.planning"
printf 'tiny\n' > "$BADPLAN/.planning/ROADMAP.md"
("$PLANNING_VERIFY" --target "$BADPLAN") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "planning verify fails stub roadmap" "$?"

ONEDOC="$(new_repo)"
mkdir -p "$ONEDOC/.gsd-recipe" "$ONEDOC/.planning/codebase" "$ONEDOC/.planning/graphs"
printf '# Stack\n\nLanguages and runtime for the repo under test.\n' > "$ONEDOC/.planning/codebase/STACK.md"
printf '{"nodes":[],"edges":[]}\n' > "$ONEDOC/.planning/graphs/graph.json"
printf '%s\n' '{"status":"ready"}' > "$ONEDOC/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --target "$ONEDOC") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "single codebase doc fails verify" "$?"

TINYDOCS="$(new_repo)"
mkdir -p "$TINYDOCS/.gsd-recipe" "$TINYDOCS/.planning/codebase" "$TINYDOCS/.planning/graphs"
printf 'tiny\n' > "$TINYDOCS/.planning/codebase/A.md"
printf 'tiny\n' > "$TINYDOCS/.planning/codebase/B.md"
printf '{"nodes":[],"edges":[]}\n' > "$TINYDOCS/.planning/graphs/graph.json"
printf '%s\n' '{"status":"ready"}' > "$TINYDOCS/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --target "$TINYDOCS") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "undersized codebase docs fail verify" "$?"

GRAPHOUT="$(new_repo)"
mkdir -p "$GRAPHOUT/.gsd-recipe" "$GRAPHOUT/.planning/codebase" "$GRAPHOUT/graphify-out"
printf '# Stack\n\nLanguages and runtime for the repo under test.\n' > "$GRAPHOUT/.planning/codebase/STACK.md"
printf '# Architecture\n\nLayered layout for the repo under test.\n' > "$GRAPHOUT/.planning/codebase/ARCHITECTURE.md"
printf '{"nodes":[],"edges":[]}\n' > "$GRAPHOUT/graphify-out/graph.json"
printf '%s\n' '{"status":"ready"}' > "$GRAPHOUT/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --target "$GRAPHOUT") && rc=0 || rc=$?
check "graphify-out graph artifact passes verify" "$rc"

BADMARKER="$(new_repo)"
seed_ready "$BADMARKER"
printf 'not-json\n' > "$BADMARKER/.gsd-recipe/KNOWLEDGE-BOOTSTRAPPED"
("$VERIFY" --target "$BADMARKER") && rc=0 || rc=$?
[ "$rc" != "0" ]
check "invalid marker JSON fails verify" "$?"

("$VERIFY" --check-graphify) && rc=0 || rc=$?
check "check-graphify passes with functional graphify stub" "$rc"

(PATH="$STUBBIN:$PATH" "$VERIFY" --check-graphify) && rc=0 || rc=$?
[ "$rc" != "0" ]
check "check-graphify fails on no-op graphify stub" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
