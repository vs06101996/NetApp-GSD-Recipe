<!--
bare_metal template — canonical source staged into target repos at
`.templates/bare_metal.template.md` by `.gsd-recipe/scripts/install.sh`
(TASK-010).

Per docs/netapp-recipe/lld/INSTALL-LLD.md § "`bare_metal.template.md` [X]"
and docs/netapp-recipe/contracts/DATA-CONTRACTS.md#bare-metal-template-md:
a stack-agnostic bootstrap contract. Each target repo fills in its own
repo-specific commands under "Bootstrap commands" — the installer only
provides this skeleton (feasibility caveat: truly zero-touch bootstrap
across all stacks is hard, so per-repo human authorship of the commands
below is expected). Consumed by Step 5's Gate A verification check
(warn-only on failure per INSTALL-LLD's "Open decisions" table).

Delete this comment block when filling in real bootstrap commands.
-->

## Bootstrap commands (repo-specific — human-authored)

- install_deps: `<command>`
- build: `<command>`
- unit_tests: `<command>`
- smoke: `<command>`
- dev_server: `<command>` (optional)

## Success criteria

- All commands exit 0
- smoke output contains: `<substring>` (optional)
