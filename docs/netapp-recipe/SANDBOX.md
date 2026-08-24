# Recipe sandbox (dummy test target)

External throwaway git repo for pickup + **unbiased tester** runs. Not AgentStudio. Not this source repo.

**Default path:** `~/Projects/recipe-sandbox`

TASK-040 / TASK-044 are Built. Unbiased testers still use **two directories**, never one working tree ([PARALLEL-PICKUP.md](PARALLEL-PICKUP.md)):

```bash
./bench/runners/setup-recipe-sandbox.sh --dir "$HOME/Projects/recipe-sandbox-040" --reset
./bench/runners/setup-recipe-sandbox.sh --dir "$HOME/Projects/recipe-sandbox-044" --reset
```

```bash
# Recreate (default path)
./bench/runners/setup-recipe-sandbox.sh --reset

# Install recipe into it (idempotent restage)
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox" --yes
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox" --verify
```

Then in Cursor Agent type **`recipe-start`** (or **`recipe-help --next`**). Clone/reinstall: [CLONE.md](CLONE.md).

## Branches

| Branch | What is there |
|--------|----------------|
| `main` | Dummy `src/app.py`; **no** `docs/PRD.md` |
| `feat/ui-prd` | Dummy UI `docs/PRD.md` |
| `feat/backend-prd` | Dummy backend `docs/PRD.md` |
| `feat/gitignore-reset` | Product `.gitignore` **without** recipe installer lines |

## Rules

- Jira: skip or use a sandbox project — do not file real KAN epics from this repo unless testing tracker on purpose.
- After install, recipe scaffold is gitignored (external-target policy).
- Unbiased tester `--target` **must** be this sandbox (or a `--dir` copy), not AgentStudio.
