#!/usr/bin/env bash
# install-gsd-netapp.sh — branded entry point for the NetApp GSD recipe installer.
#
# Thin, zero-logic wrapper delegating entirely to install.sh (TASK-010) — never
# duplicates its prerequisite bootstrap, scaffolding, or sub-installer composition.
# Exists purely so operators (e.g. "Alex" in the onboarding story) run a
# recipe-branded command instead of the more generic `install.sh` name. Every
# flag, exit code, and behavior is identical — this file only resolves its own
# directory and `exec`s the real installer with all arguments passed through.
#
# Usage: identical to install.sh — see that script's own header for the full
# flag list ([--yes|-y] [--target <repo_root>], --verify, --record-jira-check
# pass|fail, --uninstall).
#   ./.gsd-recipe/scripts/install-gsd-netapp.sh [--yes] [--target <repo_root>]
#   ./.gsd-recipe/scripts/install-gsd-netapp.sh --verify [--target <repo_root>]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/install.sh" "$@"
