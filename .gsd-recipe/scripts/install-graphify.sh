#!/usr/bin/env bash
# install-graphify.sh — sudo-free graphify bootstrap for recipe targets.
#
# Uses user-owned cache/tool directories so machines without sudo (and repos
# where ~/.cache or ~/.local are root-owned) still work. Never invokes sudo.
# Replaces no-op graphify stubs (bash scripts that only exit 0).
#
# Usage: .gsd-recipe/scripts/install-graphify.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/graphify-probe.sh" ]; then
  # shellcheck source=graphify-probe.sh
  source "$SCRIPT_DIR/graphify-probe.sh"
elif [ -f "$SCRIPT_DIR/../../bench/lib/graphify-probe.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/../../bench/lib/graphify-probe.sh"
fi

export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.uv-cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.xdg-data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.xdg-cache}"

TOOL_BIN="$HOME/bin"
mkdir -p "$UV_CACHE_DIR" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$TOOL_BIN"
export UV_TOOL_BIN_DIR="${UV_TOOL_BIN_DIR:-$TOOL_BIN}"
export PATH="$TOOL_BIN:$PATH"

if command -v graphify >/dev/null 2>&1; then
  if declare -F graphify_functional >/dev/null 2>&1 && graphify_functional; then
    graphify install
    echo "install-graphify.sh: graphify already functional at $(command -v graphify)" >&2
    exit 0
  fi
  if declare -F graphify_is_noop_stub >/dev/null 2>&1 && graphify_is_noop_stub; then
    gpath="$(command -v graphify)"
    echo "install-graphify.sh: removing no-op graphify stub at $gpath" >&2
    rm -f "$gpath"
  fi
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "install-graphify.sh: uv not found (sudo not required)." >&2
  echo "  macOS:  brew install uv" >&2
  echo "  other:  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

if ! command -v graphify >/dev/null 2>&1; then
  # `uv tool install` is otherwise a no-op when graphifyy is registered but
  # its graphify symlink was removed (for example when replacing a no-op
  # stub). Force recreates both entry-point links in our explicit bin dir.
  uv tool install --force graphifyy
fi

if ! command -v graphify >/dev/null 2>&1; then
  echo "install-graphify.sh: graphifyy installed but graphify is still unavailable in $UV_TOOL_BIN_DIR" >&2
  exit 1
fi

graphify install

echo "install-graphify.sh: graphify ready. Add to your shell profile if needed:" >&2
echo "  export PATH=\"\$HOME/bin:\$PATH\"" >&2
echo "  export UV_CACHE_DIR=\"\$HOME/.uv-cache\"" >&2
echo "  export XDG_DATA_HOME=\"\$HOME/.xdg-data\"" >&2
