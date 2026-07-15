# FOTW Hook-Trigger Validation Spike — Report

Date: 2026-07-06
Scope: a narrow follow-up spike to the main FOTW feasibility spike
(`bench/report/fotw-spike-report.md`). That spike proved the tick/classify/
rollup/end-trigger *logic* works; this spike tests the piece that logic was
missing — **can the observer be triggered automatically and run without
touching the primary conversation**, using only mechanisms native to the
runtime (no raw LLM API calls).

## TL;DR

**All 6 validation targets passed.** The hook → nudge → background-subagent
chain works in Cursor end to end, tested live against this actual
conversation, not simulated. Specifically:

- A real `postToolUse` hook fired immediately on save, with **no Cursor
  restart needed** (contrary to the worry raised before starting this spike).
- The hook payload directly hands us the current session's live transcript
  path (`transcript_path`) and `session_id` — no path-guessing heuristic
  needed at all (a mtime-recency fallback was tested and works, but turned
  out to be unnecessary).
- `additional_context` returned by the hook is actually surfaced to the
  agent as a `<system_reminder>` immediately after the triggering tool call.
- Conditional matching (only nudge for phase-start-shaped writes) and
  anti-double-spawn (marker file keyed by `session_id`) both work as designed.
- A background `Task` subagent, spawned with exactly one tool call, read the
  *real* live transcript file directly off disk by the path the hook
  provided, and produced real classification output (32 signal / 4 hedge /
  4 mechanical-marker lines out of the last 40) — while the file was
  actively growing underneath it, which is about as strong a proof of
  "genuinely live, zero-simulation" as this spike could produce.

**Net effect on your primary conversation for this entire chain:** one
`Write` (the trigger), one `<system_reminder>` nudge, one `Task` spawn call,
and one completion notification. No per-tick cost, no polling, nothing else.

## What was tested, and results

| # | Target | Method | Result |
|---|--------|--------|--------|
| 1 | Self-discovery of the live transcript path | mtime-recency heuristic against `agent-transcripts/`, cross-checked against the hook's own `transcript_path` field | PASS — both methods agree; the hook field makes the heuristic unnecessary in practice |
| 2 | Hook fires on a real Write, no restart needed | Created `.cursor/hooks.json` + `.cursor/hooks/fotw-observer-nudge.sh` (`postToolUse`, matcher `Write`), then performed a real `Write` tool call | PASS — fired on the very next tool call after creating the hook |
| 3 | `additional_context` actually reaches the agent | Hook returned a distinctive marker string | PASS — appeared as a `<system_reminder>` immediately after the `Write` tool result |
| 4 | Conditional matching (only relevant writes nudge) | Wrote to an unrelated file first (should stay silent), then to the phase-start marker file (should nudge) | PASS — silent for the unrelated file, nudged for the marker file |
| 5 | Anti-double-spawn | Marked `.gsd-recipe/.observer-active.json` for the current `session_id`, repeated the same phase-start write | PASS — hook detected the existing marker and stayed silent about spawning again, confirmed via a distinct "already active" message |
| 6 | Background subagent reads the *real* transcript and does real classification work | Spawned `Task(subagent_type=generalPurpose, run_in_background=true)` with the target descriptor the hook wrote (`session_id` + `transcript_path`), instructed to read the last 40 lines and classify them | PASS — read the live file directly by absolute path (`.gsd-recipe/.observer-target.json` → `transcript_path`), no special access. Classified 40 lines: 32 signal, 4 noise_hedge, 4 noise_irrelevant (mechanical `turn_ended` markers, not real off-topic content). The file visibly grew (209 → 236 lines) *while the subagent was reading it*, and its own tail captured the very `Task` call that spawned it — unambiguous proof this was a live read, not a stale snapshot. |

## Real hook payload schema (confirmed empirically)

```json
{
  "conversation_id": "...",
  "generation_id": "...",
  "model": "claude-sonnet-5",
  "tool_name": "Write",
  "tool_input": { "file_path": "...", "content": "..." },
  "tool_output": "...",
  "duration": 17.404,
  "tool_use_id": "toolu_...",
  "session_id": "...",
  "hook_event_name": "postToolUse",
  "cursor_version": "3.9.16",
  "workspace_roots": ["..."],
  "user_email": "...",
  "transcript_path": "/Users/.../agent-transcripts/<uuid>/<uuid>.jsonl"
}
```

This is more than the `create-hook` skill's documentation spells out —
worth carrying into the real `TASK-013` design doc verbatim, since
`transcript_path` and `session_id` are exactly the two things the
bootstrap step needs and neither was guaranteed to exist before this test.

## Artifacts produced

- `.cursor/hooks.json`, `.cursor/hooks/fotw-observer-nudge.sh` — the actual
  working hook (spike-quality: matcher target is a stand-in test file, not
  real `.planning/STATE.md` phase-start detection yet)
- `.gsd-recipe/.observer-target.json` — descriptor the hook writes for a
  consumer (primary agent or subagent) to pick up
- `.gsd-recipe/.observer-active.json` — anti-double-spawn marker
- `.learnings/observer/.hook-debug.jsonl` — every raw hook invocation, for
  schema inspection
- `.learnings/observer/hook-spike-live-tick.jsonl` +
  `hook-spike-live-tick-summary.md` — the background subagent's real
  classification output against this actual conversation's transcript

## Portability: Cursor vs. Claude Code CLI vs. GitHub Copilot (future scope)

Only Cursor was tested live. The other two are informed by current public
docs, not empirical testing — treat these as a reading of the terrain, not
validated facts.

| | Cursor (tested) | Claude Code CLI (docs only) | GitHub Copilot (docs only) |
|---|---|---|---|
| Config location | `.cursor/hooks.json` (project) / `~/.cursor/hooks.json` (user) | `.claude/settings.json` (project) / `~/.claude/settings.json` (user) / `.claude/settings.local.json` (personal, gitignored) | `.github/hooks/*.json` (repo-wide, both CLI + cloud agent) / `~/.copilot/hooks/*.json` (CLI-only, personal) |
| Relevant event | `postToolUse` | `PostToolUse` (same concept, different casing) | `postToolUse` |
| Reload behavior | Confirmed live in this spike: no restart needed | Docs claim hooks/permissions reload live, no restart | Not documented either way |
| Handler types | `command`, `type: "prompt"` | `command`, `http`, `mcp_tool`, `prompt` (30s), **`agent`** (60s) | `command`/`bash` only, per docs read |
| Can a hook itself spawn a subagent? | No — hook can only return `additional_context`; the *agent* has to act on the nudge and make its own `Task` call (confirmed: this indirection works, see result #3 above) | Possibly more direct — the `agent` handler type (60s timeout) suggests the hook itself can spawn a subagent, not just nudge one. **Unverified, worth checking first** since it could remove a layer of indirection entirely. | Unclear from docs; likely same nudge-based indirection as Cursor |
| Known gaps | None found in this spike | None found (not tested) | **Documented bug** (github/copilot-cli#3013): `preToolUse`/`sessionStart` hooks do not reliably fire for background/task sub-agents — doesn't block our design (we don't need hooks *inside* the spawned observer), but worth knowing before assuming full symmetry with Cursor |
| Background-process viability | Confirmed via this spike and the earlier FOTW feasibility spike | Presumed similar to Cursor (local CLI process) — unverified | **Materially different for Copilot cloud agent**: hooks run inside an ephemeral, non-interactive, network-constrained sandbox that's destroyed when the job ends — a long-lived background daemon would not survive there. Copilot CLI (local, not cloud) is likely closer to Cursor/Claude Code, but unverified. |

**Recommendation:** the config/lib pieces (`.gsd-recipe/observer-config.json`,
`.gsd-recipe/lib/observer-lib.sh`) are already runtime-agnostic — they're
just files and shell primitives. Only the hook *definition* and the
bootstrap-nudge mechanism are runtime-specific and would need a parallel
implementation per runtime (three small adapter files, not a redesign).
Copilot cloud agent is the one surface where the whole "long-lived
background process" premise may not hold at all and deserves its own check
before assuming parity.

## Remaining unknowns after this spike

All 6 validation targets passed; nothing about the *mechanism* is left
unverified. What's left is scope, not risk:

1. **This spike's matcher target was a stand-in test file**, not real
   `.planning/STATE.md` phase-start detection — wiring it to the actual GSD
   phase-start signal is straightforward but not yet done.
2. **The subagent classified a fixed 40-line window once**, not a real
   ticking loop against a moving offset — re-arming it repeatedly (or
   re-spawning at the next phase boundary) with the offset-tracking
   primitives from the main FOTW spike (`bench/lib/observer-lib.sh`) is the
   next integration step, not a new unknown.
3. **Installer wiring** (staging the hook + config files at recipe-install
   time, merging into an existing `.cursor/hooks.json` without clobbering
   unrelated hooks) has been designed but not built.
4. Claude Code's `agent` hook handler type could remove the nudge-indirection
   step entirely (hook spawns the subagent directly, no reliance on the
   primary model acting on `additional_context`) — worth checking before
   porting, since it may be a strictly better mechanism than what Cursor
   supports today.
5. Copilot cloud agent's ephemeral sandbox is a real, documented constraint
   on the background-daemon premise — not something to assume works without
   checking.
