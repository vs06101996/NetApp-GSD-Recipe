#!/usr/bin/env bash
# graphify-probe.sh — detect no-op graphify stubs vs a usable CLI.
# Sourced by install.sh, install-graphify.sh, and regression tests.
#
# Usage (when sourced):
#   graphify_is_noop_stub [path]   # exit 0 if path (or `command -v graphify`) is a stub
#   graphify_functional            # exit 0 when graphify on PATH is not a stub and --help works

graphify_is_noop_stub() {
  local gpath="${1:-}"
  if [ -z "$gpath" ]; then
    command -v graphify >/dev/null 2>&1 || return 1
    gpath="$(command -v graphify)"
  fi
  [ -n "$gpath" ] && [ -f "$gpath" ] || return 1

  if ! head -n 1 "$gpath" 2>/dev/null | grep -qE '^#!.*(bash|sh)'; then
    return 1
  fi

  local lines size
  lines="$(wc -l < "$gpath" | tr -d ' ')"
  size="$(wc -c < "$gpath" | tr -d ' ')"
  [ "$lines" -le 8 ] && [ "$size" -lt 384 ] || return 1
  grep -qE '^exit 0' "$gpath" || return 1
  grep -qiE 'graphify|graphifyy|python|uv tool' "$gpath" && return 1
  return 0
}

graphify_functional() {
  local gpath out
  command -v graphify >/dev/null 2>&1 || return 1
  gpath="$(command -v graphify)"
  if graphify_is_noop_stub "$gpath"; then
    return 1
  fi

  # uv/pip console entry points are deterministic Python launchers. Checking
  # their import target avoids importing graphify's full parser stack merely
  # to answer --help (which can take minutes on a cold machine), while still
  # rejecting the short `exit 0` shell stubs this guard was introduced for.
  if head -n 1 "$gpath" 2>/dev/null | grep -qE '^#!.*python' &&
     grep -qE '^from graphify(\.__main__)? import |^from graphify\.__main__ import ' "$gpath"; then
    [ -x "$gpath" ]
    return $?
  fi

  out="$(graphify --help 2>&1)" || return 1
  [ -n "${out//[[:space:]]/}" ] || return 1
  return 0
}
