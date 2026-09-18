# NetApp GSD Recipe Cursor plugin (TASK-064)

Thin Command Palette wrappers around the existing bash installer. This is not a second installer and it does not settle work.

## Commands

| Palette | What it does |
|---|---|
| Install into this workspace | Runs `bench/runners/install-recipe-to-target.sh --target <workspace> --yes --no-open-start`, then prefills `recipe-start` |
| Prefill recipe-update | Opens the Cursor prompt deeplink with `recipe-update` (operator still presses Enter) |
| Prefill recipe-start / onboard / status / install-verify | Same deeplink pattern; never auto-submits |

Set `netappGsdRecipe.recipeSource` to the recipe clone path if the product workspace is not this repo.

## Locked gates (unchanged)

- `recipe-onboard` Yes/No preview
- First-time Atlassian MCP OAuth
- PO accept at settle (Settled = PO + CI green)

Not v1: auto-submit Agent prompts, unattended execute/settle, VS Code Marketplace listing.

Sideload for development: Cursor → Extensions → Install from VSIX (package this folder) or open this folder as an extension host. Marketplace listing is out of scope.
