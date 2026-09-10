#!/usr/bin/env bash
# derive-initiative-branch.sh — default initiative branch name for recipe-onboard.
# Pattern: feat|fix/<feature-title>[-<Ticket>]
#
# Usage:
#   derive-initiative-branch.sh [--kind feat|fix] [--title TEXT] [--file PATH] [--ticket KEY]
# Prints one branch name to stdout. Exits 1 if kind or resulting name is invalid.
set -euo pipefail

KIND="feat"
TITLE=""
FILE=""
TICKET=""

while [ $# -gt 0 ]; do
  case "$1" in
    --kind) KIND="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    --ticket) TICKET="$2"; shift 2 ;;
    *) echo "derive-initiative-branch.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$KIND" in
  feat|fix) ;;
  *)
    echo "derive-initiative-branch.sh: --kind must be feat or fix" >&2
    exit 1
    ;;
esac

if [ -z "$TITLE" ] && [ -n "$FILE" ]; then
  TITLE="$(basename "$FILE")"
  TITLE="${TITLE%.*}"
fi

slugify() {
  LC_ALL=C printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g' |
    cut -c1-48
}

TITLE_SLUG="$(slugify "$TITLE")"
TICKET="$(printf '%s' "$TICKET" | tr -d '[:space:]')"

if [ -z "$TITLE_SLUG" ] && [ -z "$TICKET" ]; then
  echo "derive-initiative-branch.sh: need --title, --file, or --ticket" >&2
  exit 1
fi

if [ -n "$TICKET" ]; then
  TICKET_SLUG="$(slugify "$TICKET")"
  if [ -n "$TITLE_SLUG" ] && [ "$TITLE_SLUG" != "$TICKET_SLUG" ]; then
    BRANCH="${KIND}/${TITLE_SLUG}-${TICKET}"
  else
    BRANCH="${KIND}/${TICKET}"
  fi
else
  BRANCH="${KIND}/${TITLE_SLUG}"
fi

if ! git check-ref-format --branch "$BRANCH" >/dev/null 2>&1; then
  echo "derive-initiative-branch.sh: invalid branch name '$BRANCH'" >&2
  exit 1
fi

printf '%s\n' "$BRANCH"
