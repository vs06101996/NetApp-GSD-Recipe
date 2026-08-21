# Team clone / reinstall playbook (TASK-041)

Recipe scaffold is **gitignored** on external product repos so feature PRs stay clean. That means **every clone and often every branch that resets `.gitignore` is recipe-less** until you restage.

## Which path?

| Situation | What to run |
|-----------|-------------|
| New laptop / `git clone` of the product, with no recipe skills | Run the first-install runner below |
| Switched git branch and recipe skills still exist | Invoke `recipe-install` in Cursor to restage |
| Switched branch or clone and recipe skills are missing | Run the first-install runner below again (idempotent; does not wipe `.planning/`). If `git switch` refuses because install dirtied `.gitignore`, stash or keep that file, switch, then restage. |
| Recipe is installed and you only need a health check | Invoke `recipe-install-verify` in Cursor |
| Recipe is installed and should be removed | Invoke `recipe-install --uninstall` in Cursor |
| Want ROADMAP/PRD shared with the team | Optional chore PR that **tracks** `.planning/` / `docs/PRD.md` — default is still local-only |

## Install / restage (copy-paste)

From the **recipe source** repo (`gsd-benchmark` / NetApp-GSD-Recipe):

```bash
./bench/runners/install-recipe-to-target.sh --target /path/to/product-repo --yes
```

This is the only first-install command. The runner already calls `install.sh`;
do not choose `install.sh` as another front door. `bin/recipe install` is kept
only as a thin compatibility alias of this runner.

Dummy test target:

```bash
./bench/runners/install-recipe-to-target.sh --target "$HOME/Projects/recipe-sandbox" --yes
```

On an interactive terminal, a successful install opens Cursor with this prompt
already filled in:

```text
recipe-start
```

Review it and press **Enter**. Cursor's prompt deeplink never submits the prompt
automatically. It uses the focused Cursor window and does not guarantee a
separate new Agent chat. For headless/non-interactive installs, open Cursor and
type `recipe-start`; use `--open-start` to force the deeplink or
`--no-open-start` to suppress it.

`recipe-start` prints the next command in plain language (usually
`recipe-onboard`). Restage also restores gitignored skills, not only
`.gitignore` lines.

## Do not

- Expect `recipe-install` to work **before** skills exist (chicken-and-egg). First time = bash runner above.
- `git push` `.gsd-recipe/` or `.planning/` unless the team explicitly chooses option B.

See [SANDBOX.md](SANDBOX.md) · [INSTALL-LLD](lld/INSTALL-LLD.md) § gitignore.
