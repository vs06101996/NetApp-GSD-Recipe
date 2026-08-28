# Internal verify: graphify auto-install PATH + quiet uv (2026-08-28)

**Verifier:** [PATH-fix check](a1c96a8f-4530-4d06-9fc5-f5c47e6679a5) (not the implementer transcript)

## AC

Successful `install.sh` graphify auto-fix must record `prereqs.graphify=auto_installed` when the CLI lands only in `$HOME/bin`. `uv tool install` must be `--quiet` unless `GRAPHIFY_INSTALL_VERBOSE=1`.

## Checks

| Check | Result |
|-------|--------|
| `uv_fix_cmd` exports `PATH=$HOME/bin` in the parent `eval` | PASS |
| `test-install-graphify.sh` | 9 passed, 0 failed |
| Isolated repro (scratch HOME, binary only in `$HOME/bin`) | `prereqs.graphify=auto_installed` |
| Default `uv` argv | `tool install --force --quiet graphifyy` |

## Verdict

**PASS** — original false-fail is gone; uv chatter is suppressed by default.
