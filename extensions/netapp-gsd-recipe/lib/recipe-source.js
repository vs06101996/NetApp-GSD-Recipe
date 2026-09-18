"use strict";

const fs = require("fs");
const path = require("path");

function isDir(p) {
  try {
    return fs.statSync(p).isDirectory();
  } catch {
    return false;
  }
}

function looksLikeRecipeSource(root) {
  return (
    isDir(root) &&
    fs.existsSync(path.join(root, "bench", "runners", "install-recipe-to-target.sh"))
  );
}

/**
 * Resolve recipe source without inventing a second installer.
 * Precedence: setting/env, then walk up from workspace and extension for a
 * clone of this repo, then fail.
 */
function resolveRecipeSource({ recipeSource, workspaceRoot, extensionPath, env = process.env }) {
  const configured = (recipeSource || env.RECIPE_SOURCE || "").trim();
  if (configured) {
    if (configured.startsWith("http://") || configured.startsWith("https://") || configured.startsWith("git@")) {
      return { kind: "url", value: configured };
    }
    if (looksLikeRecipeSource(configured)) {
      return { kind: "path", value: path.resolve(configured) };
    }
    return { kind: "error", value: `netappGsdRecipe.recipeSource is set but is not a recipe clone: ${configured}` };
  }

  const startPoints = [workspaceRoot, extensionPath].filter(Boolean);
  for (const start of startPoints) {
    let current = path.resolve(start);
    for (let i = 0; i < 8; i += 1) {
      if (looksLikeRecipeSource(current)) {
        return { kind: "path", value: current };
      }
      const parent = path.dirname(current);
      if (parent === current) break;
      current = parent;
    }
  }

  return {
    kind: "error",
    value: "Set netappGsdRecipe.recipeSource to a clone of the recipe repo (this plugin wraps install-recipe-to-target.sh; it does not reimplement install).",
  };
}

function installRunner(sourceRoot) {
  return path.join(sourceRoot, "bench", "runners", "install-recipe-to-target.sh");
}

function promptDeeplink(text) {
  return `cursor://anysphere.cursor-deeplink/prompt?text=${encodeURIComponent(text)}`;
}

module.exports = {
  resolveRecipeSource,
  installRunner,
  looksLikeRecipeSource,
  promptDeeplink,
};
