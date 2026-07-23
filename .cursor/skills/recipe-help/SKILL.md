---
name: recipe-help
description: "Recipe: command reference for the NetApp GSD recipe (TASK-038). Read-only help — lists recipe skills, native GSD commands the recipe wraps, harness CLI, and bench runners. Invoke by name with optional --brief, --full, --gsd, --runners, or --brief <topic>."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-help`) with optional arguments (same spirit as `gsd-help`):

| Args | Behavior |
|------|----------|
| _(none)_ | Default tour: delivery workflow + top recipe commands |
| `--brief` | One-line summary per command (recipe + harness CLI) |
| `--full` | Display full `docs/RECIPE-COMMANDS.md` |
| `--brief <topic>` | Lookup one command (e.g. `recipe-plan-phase`, `install`, `gsd-plan-phase`) |
| `--gsd` | Native GSD summary table only — defer deep detail to `gsd-help` |
| `--runners` | Bench runner appendix only |
| `--benchmarks` | Field benchmark summary (recipe vs ad-hoc pilots) |

Examples:
- `recipe-help`
- `recipe-help --brief`
- `recipe-help --full`
- `recipe-help --benchmarks`
- `recipe-help --brief recipe-run-phases`
- `recipe-help --gsd`

## B. Prerequisites

- None. Read-only reference skill — never invokes other recipe skills or mutates the repo.
- Prefer reading `docs/RECIPE-COMMANDS.md` in the project root when present (staged by `install-recipe-help.sh`). If missing, read from the recipe source repo via `.gsd-recipe/scripts/recipe-paths.sh resolve docs/RECIPE-COMMANDS.md` when `recipe_source` is set.
- Field benchmarks: read `docs/RECIPE-BENCHMARKS.md` when present, else resolve `docs/netapp-recipe/BENCHMARKS.md` via `recipe-paths.sh`.

## C. Tool Usage

1. **Resolve the reference doc.** Read `docs/RECIPE-COMMANDS.md` at the project root if it exists. Otherwise resolve via `recipe-paths.sh` from the harness source, or synthesize a minimal answer from this skill's built-in summary below.

2. **Apply the requested mode** from § A:
   - **Default:** Print the Quick start workflow from the doc, then a numbered list of the most-used commands: `recipe-install`, `recipe-onboard`, `recipe-bootstrap-knowledge`, `recipe-plan-phase`, `recipe-run-phase`, `recipe-run-phases`, `recipe-verify-feature`, `recipe-review-ship`, `recipe-settle`, `recipe-sync`, `recipe-help`.
   - **`--brief`:** Extract the recipe-skills tables; one line per row (`command — purpose`).
   - **`--full`:** Output the entire markdown file verbatim (no commentary).
   - **`--brief <topic>`:** Find the matching row or section; print that entry only. If not found, say so and suggest `recipe-help --brief`.
   - **`--gsd`:** Print only the "Native GSD commands" section; add one line: "For full GSD reference, invoke `gsd-help`."
   - **`--runners`:** Print only the "Bench runners" section.
   - **`--benchmarks`:** Print the "Field benchmarks" section from `docs/RECIPE-BENCHMARKS.md` or `docs/netapp-recipe/BENCHMARKS.md`. Include the KB-Evaluations summary (KAN-53, AgentStudio PR #465) when present.

3. **Output ONLY the reference content** for the chosen mode. Do NOT add project-specific analysis, git status, or unsolicited next-step suggestions.

## D. Do NOT

- Invoke or chain other recipe skills (`recipe-install`, `recipe-plan-phase`, etc.) — this is help only.
- Auto-run installs, resets, or sync passes.
- Replace `gsd-help` for native GSD deep reference — point operators there when they need the full GSD catalog.
</cursor_skill_adapter>

# recipe-help — command reference (TASK-038)

Read-only catalog of NetApp GSD Recipe commands. Full generated reference: [docs/RECIPE-COMMANDS.md](../../docs/RECIPE-COMMANDS.md) · Benchmarks: [docs/netapp-recipe/BENCHMARKS.md](../../docs/netapp-recipe/BENCHMARKS.md)

**Delivery workflow (summary):**

```text
recipe-install → recipe-onboard → recipe-bootstrap-knowledge
→ recipe-plan-phase / recipe-run-phase (or recipe-run-phases)
→ recipe-verify-feature → recipe-review-ship → recipe-settle
```

**Harness CLI:** `bin/recipe install|reset` · `.gsd-recipe/scripts/install.sh --verify`

**Native GSD:** use `gsd-help` for the complete list; recipe skills commonly call `gsd-plan-phase`, `gsd-execute-phase`, `gsd-verify-work`, `gsd-code-review`, `gsd-ship`, `/gsd-map-codebase`, `/gsd-graphify build`.

Regenerate the doc after catalog changes: `bench/lib/generate-recipe-help.sh`
