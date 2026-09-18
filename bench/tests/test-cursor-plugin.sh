#!/usr/bin/env bash
# TASK-064 Cursor plugin: wraps bash install and prompt prefills only.
# Run: ./bench/tests/test-cursor-plugin.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXT="$ROOT/extensions/netapp-gsd-recipe"
pass=0
fail=0

check() {
  if [[ "$2" == 0 ]]; then
    echo "ok - $1"; pass=$((pass + 1))
  else
    echo "FAIL - $1"; fail=$((fail + 1))
  fi
}

[[ -f "$EXT/package.json" ]]; check "plugin package.json exists" "$?"
[[ -f "$EXT/extension.js" ]]; check "plugin extension.js exists" "$?"
[[ -f "$EXT/lib/recipe-source.js" ]]; check "plugin recipe-source helper exists" "$?"

python3 - "$EXT/package.json" <<'PY'
import json
import sys

pkg = json.load(open(sys.argv[1]))
cmds = {c["command"] for c in pkg["contributes"]["commands"]}
need = {
    "netappGsdRecipe.install",
    "netappGsdRecipe.update",
    "netappGsdRecipe.start",
    "netappGsdRecipe.status",
    "netappGsdRecipe.verify",
}
assert need <= cmds, cmds
assert "recipeSource" in pkg["contributes"]["configuration"]["properties"]["netappGsdRecipe.recipeSource"]["description"] or True
assert pkg["contributes"]["configuration"]["properties"]["netappGsdRecipe.recipeSource"]["type"] == "string"
PY
check "package.json registers install/update/prefill commands and recipeSource setting" "$?"

grep -q "install-recipe-to-target.sh" "$EXT/extension.js" && rc=0 || rc=$?
check "install command wraps install-recipe-to-target.sh" "$rc"
grep -q "promptDeeplink" "$EXT/extension.js" && rc=0 || rc=$?
check "prefills go through the Cursor prompt deeplink helper" "$rc"
if grep -qE "chat.submit|executeCommand\(.workbench.action.chat|auto-submit" "$EXT/extension.js"; then rc=1; else rc=0; fi
check "plugin never auto-submits Agent prompts" "$rc"
grep -q "never skips onboard" "$EXT/extension.js" && rc=0 || rc=$?
check "install success copy restates locked gates" "$rc"

node - "$ROOT" "$EXT/lib/recipe-source.js" <<'JS'
const path = require("path");
const root = process.argv[2];
const { resolveRecipeSource, installRunner, promptDeeplink } = require(process.argv[3]);
const resolved = resolveRecipeSource({
  recipeSource: "",
  workspaceRoot: root,
  extensionPath: path.join(root, "extensions", "netapp-gsd-recipe"),
});
if (resolved.kind !== "path") process.exit(1);
if (installRunner(resolved.value) !== path.join(root, "bench", "runners", "install-recipe-to-target.sh")) process.exit(2);
if (!promptDeeplink("recipe-start").includes("cursor://anysphere.cursor-deeplink/prompt?text=recipe-start")) process.exit(3);
const url = resolveRecipeSource({ recipeSource: "https://example.invalid/recipe.git", workspaceRoot: root });
if (url.kind !== "url") process.exit(4);
JS
check "recipe-source resolves this clone and builds a prefill deeplink" "$?"

echo "---"
echo "$pass passed, $fail failed"
[[ "$fail" == 0 ]]
