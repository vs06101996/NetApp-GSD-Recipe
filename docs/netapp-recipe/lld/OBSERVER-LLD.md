# Observer LLD (p2) — deferred stub

**Status:** Post-pilot. Do not implement for v1 pilot.

FLY ON THE WALL (FOTW) would capture session friction into `.learnings/observer/ticks.jsonl`, roll up to playbooks, and promote to `.knowledge/` after human review via `gsd-extract-learnings`.

| Piece | Target path |
|-------|-------------|
| Live ticks | `.learnings/observer/ticks.jsonl` |
| Session rollup | `.learnings/kb/sessions/` |
| Playbooks | `.learnings/kb/playbooks/` |
| Promotion | `.knowledge/` (human gate) |

**Pilot today:** use `gsd-capture --note` and `gsd-extract-learnings` manually if needed ([RUNTIME-LLD.md](RUNTIME-LLD.md)).

Full design when prioritized: TASK-013 in [BACKLOG.md](../BACKLOG.md).
