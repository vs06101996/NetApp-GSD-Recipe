#!/usr/bin/env bash
# recipe-verify-knowledge.sh — fail-closed knowledge readiness guardrail.
#
# Usage:
#   recipe-verify-knowledge.sh [--target DIR]              # exit 0 when ready
#   recipe-verify-knowledge.sh --write-marker [--target DIR]
#   recipe-verify-knowledge.sh --json [--target DIR]
#   recipe-verify-knowledge.sh --check-graphify [--target DIR]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET=""
MODE="check"
WRITE_MARKER=0
JSON=0
CHECK_GRAPHIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --write-marker) WRITE_MARKER=1; shift ;;
    --json) JSON=1; shift ;;
    --check-graphify) CHECK_GRAPHIFY=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--write-marker] [--json] [--check-graphify] [--target DIR]"
      exit 0
      ;;
    *) echo "$0: unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$TARGET" ]; then
  if [ -d "$SCRIPT_DIR/../../.git" ] && [ -f "$SCRIPT_DIR/../../bench/lib/recipe-verify-knowledge.sh" ]; then
    TARGET="$(cd "$SCRIPT_DIR/../.." && pwd)"
  else
    TARGET="$(pwd)"
  fi
fi
TARGET="$(cd "$TARGET" && pwd)"

KNOWLEDGE_PY="$SCRIPT_DIR/recipe_knowledge.py"
if [ ! -f "$KNOWLEDGE_PY" ]; then
  KNOWLEDGE_PY="$TARGET/.gsd-recipe/scripts/recipe_knowledge.py"
fi
if [ ! -f "$KNOWLEDGE_PY" ]; then
  echo "recipe-verify-knowledge.sh: recipe_knowledge.py not found" >&2
  exit 2
fi

PROBE="$SCRIPT_DIR/graphify-probe.sh"
if [ ! -f "$PROBE" ]; then
  PROBE="$TARGET/.gsd-recipe/scripts/graphify-probe.sh"
fi

graphify_guard() {
  if [ ! -f "$PROBE" ]; then
    echo "graphify: probe script missing — cannot verify CLI" >&2
    return 1
  fi
  # shellcheck source=/dev/null
  source "$PROBE"
  if graphify_functional; then
    return 0
  fi
  echo "graphify: missing or no-op stub on PATH — run .gsd-recipe/scripts/install-graphify.sh" >&2
  return 1
}

if [ "$CHECK_GRAPHIFY" = "1" ]; then
  graphify_guard
  exit $?
fi

if [ "$JSON" = "1" ]; then
  python3 "$KNOWLEDGE_PY" json --target "$TARGET"
  exit $?
fi

if [ "$WRITE_MARKER" = "1" ]; then
  graphify_guard || exit 1
  python3 "$KNOWLEDGE_PY" write-marker --target "$TARGET"
  exit $?
fi

graphify_guard || exit 1
python3 "$KNOWLEDGE_PY" check --target "$TARGET"
