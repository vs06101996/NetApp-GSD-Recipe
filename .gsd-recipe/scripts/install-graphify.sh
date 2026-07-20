#!/usr/bin/env bash
# install-graphify.sh — sudo-free graphify bootstrap for recipe targets.
#
# Uses user-owned cache/tool directories so machines without sudo (and repos
# where ~/.cache or ~/.local are root-owned) still work. Never invokes sudo.
#
# Usage: .gsd-recipe/scripts/install-graphify.sh
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.uv-cache}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.xdg-data}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.xdg-cache}"

TOOL_BIN="$HOME/bin"
mkdir -p "$UV_CACHE_DIR" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$TOOL_BIN"
export PATH="$TOOL_BIN:$PATH"

if ! command -v uv >/dev/null 2>&1; then
  echo "install-graphify.sh: uv not found (sudo not required)." >&2
  echo "  macOS:  brew install uv" >&2
  echo "  other:  curl -LsSf https://astral.sh/uv/install.sh | sh" >&2
  exit 1
fi

if ! command -v graphify >/dev/null 2>&1; then
  uv tool install graphifyy
fi

graphify install

echo "install-graphify.sh: graphify ready. Add to your shell profile if needed:" >&2
echo "  export PATH=\"\$HOME/bin:\$PATH\"" >&2
echo "  export UV_CACHE_DIR=\"\$HOME/.uv-cache\"" >&2
echo "  export XDG_DATA_HOME=\"\$HOME/.xdg-data\"" >&2
