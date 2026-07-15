---
name: recipe-observe
description: "Recipe: front door for the FOTW observer's operator-facing lifecycle (TASK-032). status/start/stop/enable/disable — dispatches entirely to already-built pieces (observer-lib.sh, fotw-observer-bootstrap); never duplicates their logic."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke as `recipe-observe <status|start|stop|enable|disable>`. Exactly one
subcommand is required.

Arguments: `{{GSD_ARGS}}` — the first token is the subcommand; nothing else
is expected or parsed.

## B. Prerequisites

- `status` has **no** prerequisite — it must work even when
  `.gsd-recipe/observer-config.json` is missing entirely, reporting
  "not installed" rather than erroring (see § Scope below).
- Every other subcommand (`start`, `stop`, `enable`, `disable`) requires
  `.gsd-recipe/observer-config.json` to exist (staged by
  `.gsd-recipe/scripts/install-observer.sh`). If it's missing, stop and tell
  the operator plainly: "FOTW observer is not installed in this repo — run
  the `fotw-observer` installer (or `install.sh`) first, or ask `recipe-observe
  status` for a read-only report." Do not attempt to create the config
  yourself — that is exclusively `install-observer.sh`'s job.
- `.gsd-recipe/lib/observer-lib.sh` present (staged by the same installer,
  same prerequisite `fotw-observer-bootstrap` already documents). This
  skill's own installer (`install-recipe-observe.sh`) does **not** stage or
  check for this file at install time — it is a pure runtime dependency,
  checked here, at invocation time, exactly like
  `fotw-observer-bootstrap/SKILL.md`'s own § B already does.

## C. Tool Usage

Resolve the 4 well-known paths before doing anything else, for every
subcommand (including `status`):

1. `config` = `.gsd-recipe/observer-config.json`.
2. If `config` exists, read its `paths` object for `ticks_file` and
   `stop_sentinel_file`; if `config` is missing, fall back to the documented
   defaults (`.learnings/observer/ticks.jsonl`,
   `.learnings/observer/.stop`) so `status` can still report something
   meaningful.
3. `active_marker` = `.gsd-recipe/.observer-active.json` (fixed path, not
   configurable — same path `fotw-observer-bootstrap`/the hook already use).

Then, per subcommand:

- **`status`** — `Shell`:
  `.gsd-recipe/lib/observer-lib.sh status <config> <active_marker> <ticks_file> <stop_sentinel_file>`.
  Always succeeds (exit 0) even when `config` is missing — present the
  `key: value` report readably (see `observer-lib.sh`'s own header comment
  for the exact line order/shape). Never treat "not installed" or
  "disabled" as an error here; just relay the facts.
- **`start`** — invoke the `fotw-observer-bootstrap` skill by name
  (Option B, skill-to-skill dispatch). Do **not** resolve `session_id` /
  `transcript_path` yourself, and do **not** call `can-spawn` or `Task`
  directly here — `fotw-observer-bootstrap` owns every one of those steps
  end to end (its own guard, its own target-descriptor write, its own
  subagent spawn, its own active-marker write). This skill's only job for
  `start` is the single act of invoking that skill by name and relaying
  whatever it reports (including a blocked/no-op outcome, which is normal,
  not an error).
- **`stop`** — `Shell`:
  `.gsd-recipe/lib/observer-lib.sh request-stop <stop_sentinel_file>`. Then
  **explicitly tell the operator, every time, prominently** — this is not a
  footnote:
  > This only creates the graceful-finalize sentinel file the tick loop's
  > own prompt (`fotw-observer-task-prompt.md`'s `session_end_triggers.explicit_stop`)
  > already checks at the top of every tick. It does **not** and **cannot**
  > forcibly kill an already-running background `Task` subagent — no such
  > capability exists. If the observer has already crashed, finished, or
  > was never actually spawned, this sentinel has no effect until (and
  > unless) a tick loop runs again and checks for it. Use `recipe-observe
  > status` afterward to see whether the observer is still `active`.
- **`enable`** — `Shell`: `.gsd-recipe/lib/observer-lib.sh enable <config>`.
  Trust the subcommand's own exit code (fails closed with a clear stderr
  message if `config` is missing — relay that verbatim rather than
  re-deriving your own missing-config message). On success, tell the
  operator plainly: "Observer enabled in `.gsd-recipe/observer-config.json`
  — the next `start` (by name or via the reactive hook) will be allowed to
  spawn."
- **`disable`** — `Shell`: `.gsd-recipe/lib/observer-lib.sh disable <config>`.
  Same trust-the-exit-code contract as `enable`. On success: "Observer
  disabled — both trigger paths (`fotw-observer-bootstrap` and the reactive
  hook) will refuse to spawn a new observer until re-enabled. This does
  **not** stop an already-running observer" (that's `stop`'s job, with its
  own documented limitation above) "— it only blocks future spawns."

## D. Do NOT

- Do not reimplement `can-spawn`, the target-descriptor write, or the `Task`
  spawn here — always delegate `start` entirely to `fotw-observer-bootstrap`
  by name. This skill's `start` subcommand exists purely so an operator can
  say "observer, start" without knowing that skill's name — it adds zero new
  spawn logic.
- Do not treat `stop` as a forceful kill switch, and do not let an operator
  walk away believing it is one — always surface the graceful-signal-only
  caveat verbatim, every single time `stop` is invoked, not just the first.
- Do not silently succeed on `start`/`stop`/`enable`/`disable` when
  `.gsd-recipe/observer-config.json` is missing — fail closed with a clear
  "not installed" message for those four subcommands specifically (`status`
  is the sole exception, per § B/C above).
- Do not invent a 5th subcommand (e.g. a `restart` or a hard `kill`) — none
  exists in `observer-lib.sh` and none should be improvised here; if an
  operator asks for a forced kill, tell them plainly that no such mechanism
  exists in this recipe (see § Scope below).
</cursor_skill_adapter>

# recipe-observe — GSD recipe: FOTW observer operator front door (TASK-032)

## Scope (read this before extending)

This skill is deliberately narrow, following the exact same "thin dispatch,
not a runtime rewrite" philosophy `tracker-sync-SKILL.md`'s own § Scope
established. It adds **zero** new observer engine logic. Every one of its
five subcommands maps directly onto a primitive that already existed before
this task:

| Subcommand | Delegates to |
|---|---|
| `status` | `observer-lib.sh status` (new in this task, but a pure read — no engine change) |
| `start` | `fotw-observer-bootstrap` skill, unchanged |
| `stop` | `observer-lib.sh request-stop` (new in this task) — the sentinel it creates was **already** a documented, watched trigger (`observer-config.json`'s `session_end_triggers.explicit_stop`, `fotw-observer-task-prompt.md` step 1) before this task; the only real gap this closes is the *operator-facing way to create that file* — previously only a human manually running `touch .learnings/observer/.stop` could do it |
| `enable` / `disable` | `observer-lib.sh enable`/`disable` (new in this task) — toggles the exact `"enabled"` flag `can-spawn` already gates on |

Before this task, `bench/lib/observer-lib.sh` had no `status`, `enable`/
`disable`, or `stop` subcommand at all — an operator who wanted any of these
five things had to either read `.gsd-recipe/observer-config.json`/
`.gsd-recipe/.observer-active.json` by hand, hand-edit the config's
`"enabled"` key, or manually `touch` the stop sentinel. `recipe-observe`
does not change what any of those files mean or how the tick loop
interprets them — it only gives an operator a single, consistent,
invoke-by-name surface over facts and toggles that already existed.

## The `stop` subcommand's real limitation — read this before using it

**`recipe-observe stop` is a request, not a kill switch.** It creates
`.learnings/observer/.stop` (or whichever path `observer-config.json`'s
`paths.stop_sentinel_file` names) and nothing else. The **only** thing that
ever acts on that file is the next iteration of an *already-running*
background `Task` subagent's own tick loop, per
`fotw-observer-task-prompt.md` step 1 ("Explicit stop check. If
`paths.stop_sentinel_file` exists → finalize immediately"). That means:

- If the observer subagent is genuinely running and ticking, `stop` works —
  the very next tick (at most `tick_interval_seconds` later) sees the
  sentinel and finalizes gracefully (writes its session summary, removes
  the active marker, per the task prompt's own Finalize section).
- If the observer subagent has already crashed, was never actually spawned
  (e.g. the primary agent ignored a hook nudge — the exact non-guaranteed
  gap `fotw-observer-install-integration-report.md`'s own "Step 5 doesn't
  happen" caveat documents), or has already finished and cleared its own
  active marker — `stop` still "succeeds" (the file gets created, exit 0),
  but **nothing is listening**, so nothing observable happens. The sentinel
  just sits there until some future tick loop (if one ever starts again)
  happens to check for it.
- There is **no mechanism anywhere in this recipe** — not in this skill, not
  in `observer-lib.sh`, not in Cursor's own `Task` tool — to forcibly
  terminate an already-spawned background subagent. Cursor's `Task` tool
  offers no "kill this background agent" primitive this skill (or any
  skill) can call. This is a hard platform limitation, not a scope choice
  this task narrowed away.
- Use `recipe-observe status` after calling `stop` to check whether
  `active: true` eventually flips to `false` (or whether `tick_count` stops
  growing) — that is the only way to *observe* whether the stop actually
  took effect, since there is no synchronous confirmation.

## `status` output format

`observer-lib.sh status` prints a fixed, stable, `key: value` report, one
fact per line, always in this order (see the script's own header comment
for the authoritative contract):

```
config_file: <path>
installed: true|false
enabled: true|false
active_marker_file: <path>
active: true|false
session_id: <id>|none
ticks_file: <path>
tick_count: <n>
stop_sentinel_file: <path>
stop_requested: true|false
```

This shape was chosen (a judgment call — no prior precedent enforced a
specific report shape for a new introspection subcommand) to directly answer
the five questions an operator asking "what is the observer doing right
now?" actually has: is it installed at all, is it turned on, is a session
currently active, how much has it produced so far, and has anyone already
asked it to stop. It intentionally does **not** attempt to report whether
the underlying background `Task` subagent process is *actually alive* right
now — Cursor exposes no such introspection primitive, so `active`/
`tick_count` (does the marker exist, is data still growing) are the closest
proxies available, same limitation the `stop` section above documents for
the opposite direction (no forced-kill capability either).

## Relationship to `fotw-observer-bootstrap`

`recipe-observe start` is a pure pass-through to `fotw-observer-bootstrap`
— it exists only so an operator doesn't need to know that skill's name.
Nothing about `fotw-observer-bootstrap`'s own guard (`can-spawn`), target
descriptor, subagent spawn, or active-marker write changes because of this
skill; invoking `fotw-observer-bootstrap` directly by name continues to work
exactly as before and is equally correct. The reactive `postToolUse` hook
(`.cursor/hooks/fotw-observer-nudge.sh`) is likewise completely untouched by
this task — `recipe-observe` adds a third, deliberately manual entry point
alongside the two existing trigger paths, never replacing either.
