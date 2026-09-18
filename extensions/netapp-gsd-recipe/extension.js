"use strict";

const vscode = require("vscode");
const { spawn } = require("child_process");
const { resolveRecipeSource, installRunner, promptDeeplink } = require("./lib/recipe-source");

function workspaceRoot() {
  const folder = vscode.workspace.workspaceFolders && vscode.workspace.workspaceFolders[0];
  return folder ? folder.uri.fsPath : undefined;
}

function sourceResolution() {
  const cfg = vscode.workspace.getConfiguration("netappGsdRecipe");
  return resolveRecipeSource({
    recipeSource: cfg.get("recipeSource") || "",
    workspaceRoot: workspaceRoot(),
    extensionPath: vscode.extensions.getExtension("netapp.netapp-gsd-recipe")
      ? vscode.extensions.getExtension("netapp.netapp-gsd-recipe").extensionPath
      : __dirname,
  });
}

async function prefillPrompt(text) {
  const uri = vscode.Uri.parse(promptDeeplink(text));
  await vscode.env.openExternal(uri);
  vscode.window.showInformationMessage(
    `Cursor opened with '${text}' pre-filled. Review it, then press Enter. This plugin never submits Agent prompts and never skips onboard, Jira MCP OAuth, or PO accept.`
  );
}

function runRunner(sourceRoot, target, extraArgs) {
  return new Promise((resolve, reject) => {
    const runner = installRunner(sourceRoot);
    const child = spawn(runner, ["--target", target, "--yes", "--no-open-start", ...extraArgs], {
      stdio: "inherit",
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`${runner} exited ${code}`));
    });
  });
}

async function installIntoWorkspace() {
  const target = workspaceRoot();
  if (!target) {
    vscode.window.showErrorMessage("Open a product git repo as the workspace folder first.");
    return;
  }
  const source = sourceResolution();
  if (source.kind === "url") {
    vscode.window.showErrorMessage(
      "Set netappGsdRecipe.recipeSource to a local clone path. This plugin wraps install-recipe-to-target.sh; it does not clone from a URL."
    );
    return;
  }
  if (source.kind !== "path") {
    vscode.window.showErrorMessage(source.value);
    return;
  }
  try {
    await runRunner(source.value, target, []);
    await prefillPrompt("recipe-start");
  } catch (err) {
    vscode.window.showErrorMessage(String(err.message || err));
  }
}

function activate(context) {
  context.subscriptions.push(
    vscode.commands.registerCommand("netappGsdRecipe.install", installIntoWorkspace),
    vscode.commands.registerCommand("netappGsdRecipe.update", () => prefillPrompt("recipe-update")),
    vscode.commands.registerCommand("netappGsdRecipe.start", () => prefillPrompt("recipe-start")),
    vscode.commands.registerCommand("netappGsdRecipe.onboard", () => prefillPrompt("recipe-onboard")),
    vscode.commands.registerCommand("netappGsdRecipe.status", () => prefillPrompt("recipe-status")),
    vscode.commands.registerCommand("netappGsdRecipe.verify", () => prefillPrompt("recipe-install-verify"))
  );
}

function deactivate() {}

module.exports = { activate, deactivate };
