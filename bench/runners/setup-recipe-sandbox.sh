#!/usr/bin/env bash
# setup-recipe-sandbox.sh — create/reset the dummy *external* git repo used to
# test the NetApp GSD recipe (unbiased tester target). Not AgentStudio.
#
# Default location: $HOME/Projects/recipe-sandbox
# Override: --dir <path>  or  RECIPE_SANDBOX_DIR
#
# Usage:
#   ./bench/runners/setup-recipe-sandbox.sh
#   ./bench/runners/setup-recipe-sandbox.sh --dir /tmp/recipe-sandbox
#   ./bench/runners/setup-recipe-sandbox.sh --reset   # wipe and recreate
#
# Then install the recipe into it from this harness:
#   ./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox" --yes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BENCHMARK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

DIR="${RECIPE_SANDBOX_DIR:-$HOME/Projects/recipe-sandbox}"
RESET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)
      DIR="$2"
      shift 2
      ;;
    --reset)
      RESET=1
      shift
      ;;
    -h|--help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "setup-recipe-sandbox.sh: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# Product-shaped gitignore *without* recipe installer lines (repro of
# "switched branch, missing ignore names").
write_product_gitignore() {
  cat > "$1" <<'EOF'
# recipe-sandbox — product ignores only (recipe installer adds more later)
__pycache__/
*.pyc
.venv/
.env
.DS_Store
EOF
}

write_readme() {
  cat > "$1" <<EOF
# recipe-sandbox

Throwaway **external** target for testing the NetApp GSD Recipe.

- Not AgentStudio. Not the recipe source repo (\`gsd-benchmark\`).
- Recreate: \`$BENCHMARK_ROOT/bench/runners/setup-recipe-sandbox.sh --reset\`
- Install recipe:

\`\`\`bash
$BENCHMARK_ROOT/bench/runners/install-recipe-to-target.sh --target $DIR --yes
\`\`\`

## Branches

| Branch | Purpose |
|--------|---------|
| \`main\` | Empty product; no PRD |
| \`feat/ui-prd\` | UI-shaped \`docs/PRD.md\` |
| \`feat/backend-prd\` | Backend-shaped \`docs/PRD.md\` |
| \`feat/gitignore-reset\` | Same product \`.gitignore\` (no recipe lines) — switch-away repro |

Do not commit recipe scaffold here on purpose: after install it should be gitignored.
EOF
}

write_app() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
"""Tiny dummy app so knowledge-map / graphify has something to chew on."""


def greet(name: str) -> str:
    return f"hello, {name}"


if __name__ == "__main__":
    print(greet("sandbox"))
EOF
}

write_prd_ui() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
# PRD: Sandbox UI match (dummy)

## Problem

Operators see a mismatched greeting label in the dummy UI.

## Goals

- Match the signed-off "hello" copy on the home screen.

## Non-Goals

- Real AgentStudio work.

## Requirements

- Change the greeting string in `src/app.py` to the approved copy.

## Out of Scope

- Backend metrics, Jira production projects.
EOF
}

write_prd_backend() {
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
# PRD: Sandbox backend metrics (dummy)

## Problem

The dummy UI has nowhere to read a metric payload from.

## Goals

- Add a `metrics()` helper that returns a small dict.

## Non-Goals

- UI layout.

## Requirements

- `src/app.py` exposes `metrics() -> dict`.

## Out of Scope

- Production AgentStudio eval worker.
EOF
}

if [ "$RESET" -eq 1 ] && [ -d "$DIR" ]; then
  echo "setup-recipe-sandbox.sh: --reset removing $DIR"
  rm -rf "$DIR"
fi

if [ -d "$DIR/.git" ] && [ "$RESET" -eq 0 ]; then
  echo "setup-recipe-sandbox.sh: already exists at $DIR"
  echo "  Recreate: $0 --dir $DIR --reset"
  echo "  Install:  $BENCHMARK_ROOT/bench/runners/install-recipe-to-target.sh --target $DIR --yes"
  git -C "$DIR" branch -a
  exit 0
fi

mkdir -p "$DIR"
cd "$DIR"
git init -b main -q
git config user.email "recipe-sandbox@local.test"
git config user.name "recipe-sandbox"

write_product_gitignore "$DIR/.gitignore"
write_readme "$DIR/README.md"
write_app "$DIR/src/app.py"
mkdir -p "$DIR/docs"
: > "$DIR/docs/.gitkeep"

git add -A
git commit -qm "main: dummy product (no PRD, product gitignore only)"

git switch -c feat/ui-prd -q
write_prd_ui "$DIR/docs/PRD.md"
git add docs/PRD.md
git commit -qm "feat/ui-prd: dummy UI PRD"

git switch main -q
git switch -c feat/backend-prd -q
write_prd_backend "$DIR/docs/PRD.md"
git add docs/PRD.md
git commit -qm "feat/backend-prd: dummy backend PRD"

git switch main -q
git switch -c feat/gitignore-reset -q
# Same incomplete ignore set as main, plus a marker comment so the branch
# is a real checkout (repro: installer lines vanish after switch).
write_product_gitignore "$DIR/.gitignore"
printf '\n# marker: incomplete gitignore branch (recipe lines not here)\n' >> "$DIR/.gitignore"
git add .gitignore
git commit -qm "feat/gitignore-reset: product gitignore without recipe lines"

git switch main -q

echo "setup-recipe-sandbox.sh: ready at $DIR"
echo "Branches:"
git -C "$DIR" branch
echo
echo "Install recipe (external target):"
echo "  $BENCHMARK_ROOT/bench/runners/install-recipe-to-target.sh --target $DIR --yes"
echo "  $BENCHMARK_ROOT/bench/runners/install-recipe-to-target.sh --target $DIR --verify"
echo
echo "Open that folder in a second Cursor window for unbiased tester runs."
