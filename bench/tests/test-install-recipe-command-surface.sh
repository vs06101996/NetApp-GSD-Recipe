#!/usr/bin/env bash
# Regression test for install-recipe-command-surface.sh and the always-applied
# Cursor rule that translates native GSD next-step suggestions into recipe
# commands.
# Run: ./bench/tests/test-install-recipe-command-surface.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO_ROOT/.gsd-recipe/scripts/install-recipe-command-surface.sh"
TEMPLATE="$REPO_ROOT/.gsd-recipe/templates/recipe-command-surface.mdc"
LIVE_RULE="$REPO_ROOT/.cursor/rules/recipe-command-surface.mdc"

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

assert_mapping_contract() {
  local file="$1"
  python3 - "$file" <<'PY'
import re, sys
path = sys.argv[1]
text = open(path, encoding="utf-8").read()
if "alwaysApply: true" not in text.split("---", 2)[1]:
    raise SystemExit("missing alwaysApply: true in frontmatter")
if "Never recommend a `gsd-*" not in text:
    raise SystemExit("missing never-recommend contract")
required = [
    ("gsd-new-project", "recipe-onboard"),
    ("gsd-import", "recipe-onboard"),
    ("gsd-map-codebase", "recipe-bootstrap-knowledge"),
    ("gsd-graphify build", "recipe-bootstrap-knowledge"),
    ("gsd-ingest-docs", "recipe-bootstrap-knowledge"),
    ("gsd-plan-phase", "recipe-plan-phase"),
    ("gsd-execute-phase", "recipe-run-phase"),
    ("gsd-verify-work", "recipe-verify-feature"),
    ("gsd-audit-milestone", "recipe-verify-feature"),
    ("gsd-audit-uat", "recipe-verify-feature"),
    ("gsd-code-review", "recipe-review-ship"),
    ("gsd-ship", "recipe-review-ship"),
    ("gsd-progress", "recipe-status"),
    ("gsd-next", "recipe-status"),
    ("gsd-health", "recipe-status"),
]
for native, recipe in required:
    if native not in text:
        raise SystemExit(f"missing native token {native}")
    if recipe not in text:
        raise SystemExit(f"missing recipe token {recipe}")
    # Same table row: native appears before recipe on a pipe-delimited line.
    row = None
    for line in text.splitlines():
        if native in line and line.strip().startswith("|"):
            row = line
            break
    if row is None:
        raise SystemExit(f"native {native} not on a table row")
    if recipe not in row:
        raise SystemExit(f"{native} row does not recommend {recipe}: {row}")
if "When `gsd-*` is still correct" not in text:
    raise SystemExit("missing exception section")
for needle in ("gsd-help", "explicitly asked", "delegates", "recipe-next.sh"):
    if needle not in text:
        raise SystemExit(f"missing exception/fallback needle {needle}")
# Must not claim every gsd mention is forbidden.
if re.search(r"never say gsd", text, re.I):
    raise SystemExit("over-broad never-say-gsd wording")
PY
}

# ── source-tree contract ──────────────────────────────────────────────────────

[ -f "$TEMPLATE" ]
check "canonical template exists" "$?"
[ -f "$LIVE_RULE" ]
check "live always-applied rule exists in this repo" "$?"
cmp -s "$TEMPLATE" "$LIVE_RULE"
check "live rule matches canonical template (no drift)" "$?"

assert_mapping_contract "$TEMPLATE" && rc=0 || rc=$?
check "template mapping contract (native → recipe + exceptions)" "$rc"
assert_mapping_contract "$LIVE_RULE" && rc=0 || rc=$?
check "live rule mapping contract (native → recipe + exceptions)" "$rc"

head -n 20 "$LIVE_RULE" | grep -q "alwaysApply: true"
check "live rule frontmatter sets alwaysApply: true" "$?"

# ── installer fail-closed ─────────────────────────────────────────────────────

chmod +x "$INSTALLER"

NOTGIT="$(mktemp -d)"
"$INSTALLER" --yes --target "$NOTGIT" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "refuses to install into a non-git directory" "$?"

"$INSTALLER" --yes --bogus >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" = "2" ]
check "unknown argument exits 2" "$?"

# ── fresh target install ──────────────────────────────────────────────────────

TARGET1="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET1" >/dev/null
[ -f "$TARGET1/.cursor/rules/recipe-command-surface.mdc" ]
check "fresh install stages .cursor/rules/recipe-command-surface.mdc" "$?"

cmp -s "$TEMPLATE" "$TARGET1/.cursor/rules/recipe-command-surface.mdc"
check "staged rule is a byte-identical copy of the template" "$?"

assert_mapping_contract "$TARGET1/.cursor/rules/recipe-command-surface.mdc" && rc=0 || rc=$?
check "staged rule satisfies mapping contract" "$rc"

LEDGER_COUNT1="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-command-surface']))")"
[ "$LEDGER_COUNT1" = "1" ]
check "fresh install records exactly 1 ledger row" "$?"

"$INSTALLER" --verify --target "$TARGET1" >/dev/null && rc=0 || rc=$?
check "--verify passes after install" "$rc"

"$INSTALLER" --yes --target "$TARGET1" >/dev/null
LEDGER_COUNT2="$(python3 -c "import json; print(len(json.load(open('$TARGET1/.gsd-recipe/ledger.json'))['recipe-command-surface']))")"
[ "$LEDGER_COUNT2" = "1" ]
check "re-running install does not duplicate ledger rows" "$?"

# ── uninstall from an external target ─────────────────────────────────────────

TARGET2="$(new_repo)"
"$INSTALLER" --yes --target "$TARGET2" >/dev/null
"$INSTALLER" --uninstall --target "$TARGET2" >/dev/null
[ ! -f "$TARGET2/.cursor/rules/recipe-command-surface.mdc" ]
check "uninstall removes the staged rule from an external target" "$?"
python3 -c "
import json
d = json.load(open('$TARGET2/.gsd-recipe/ledger.json'))
assert 'recipe-command-surface' not in d, d
"
check "uninstall clears the recipe-command-surface ledger entry" "$?"

"$INSTALLER" --verify --target "$TARGET2" >/dev/null 2>&1 && rc=0 || rc=$?
[ "$rc" != "0" ]
check "--verify fails after uninstall on an external target" "$?"

# ── self-install / self-uninstall preserves the live rule ─────────────────────

COPY="$(mktemp -d)/gsd-benchmark-copy"
# Copy only the recipe bits the installer needs — avoid dragging .claude worktrees.
mkdir -p "$COPY/.gsd-recipe/scripts" "$COPY/.gsd-recipe/templates" "$COPY/.cursor/rules"
cp "$INSTALLER" "$COPY/.gsd-recipe/scripts/install-recipe-command-surface.sh"
cp "$TEMPLATE" "$COPY/.gsd-recipe/templates/recipe-command-surface.mdc"
cp "$LIVE_RULE" "$COPY/.cursor/rules/recipe-command-surface.mdc"
(cd "$COPY" && git init -q && git add -A && git commit -qm init)

(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-command-surface.sh --yes >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install into a copy of this repo does not error" "$rc"
(cd "$COPY" && ./.gsd-recipe/scripts/install-recipe-command-surface.sh --uninstall >/dev/null 2>&1) && rc=0 || rc=$?
check "self-install uninstall does not error" "$rc"
[ -f "$COPY/.gsd-recipe/templates/recipe-command-surface.mdc" ]
check "self-uninstall preserves the canonical template source" "$?"
[ -f "$COPY/.cursor/rules/recipe-command-surface.mdc" ]
check "self-uninstall preserves the live always-applied rule" "$?"

echo "---"
echo "$pass passed, $fail failed"
[ "$fail" = "0" ]
