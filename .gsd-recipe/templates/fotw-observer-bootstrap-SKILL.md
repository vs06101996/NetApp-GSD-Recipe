---
name: fotw-observer-bootstrap
description: "Recipe: spawn the FLY ON THE WALL (FOTW) observer background subagent. Pluggable trigger — invoke by name directly, or reference as one step from any PRD-intake command (e.g. a future recipe-prd-intake)."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke directly (`fotw-observer-bootstrap`), or — this is the intended
integration point — have another command's own workflow reference this
skill as one of its steps right after it finishes PRD intake / project
bootstrap (writing `docs/PRD.md`, `.planning/intake/PRD.md`, or
`.planning/STATE.md`). A future `recipe-prd-intake` (`BACKLOG.md` TASK-016,
not yet built at time of writing) is the expected caller, but this skill
does not depend on that command existing — it only needs the current
`session_id` and `transcript_path`, which any GSD/Cursor session already
has available.

No arguments required. Optional: pass a `session_id` / `transcript_path`
pair explicitly if the caller has them (e.g. from its own context); otherwise
this skill resolves them from the current session the same way the hook
does.

## B. Prerequisites

- `.gsd-recipe/observer-config.json` exists and `"enabled": true` (staged by
  `.gsd-recipe/scripts/install-observer.sh`) — if missing or disabled, this
  skill is a no-op by design (fail closed, matches `INSTALL-LLD.md` Step 1).
- `.gsd-recipe/lib/observer-lib.sh` present (staged by the same installer).

## C. Tool Usage

1. `Shell`: run the shared guard —
   `.gsd-recipe/lib/observer-lib.sh can-spawn .gsd-recipe/observer-config.json .gsd-recipe/.observer-active.json <session_id>`.
   Exit 0 = proceed; exit 1 = stop here, no spawn (print the reason from
   stdout for visibility, do not treat it as an error).
2. Write `.gsd-recipe/.observer-target.json`:
   ```json
   { "session_id": "<session_id>", "transcript_path": "<transcript_path>", "discovered_at": "<utc timestamp>", "matched_signal_path": "<caller-provided, or 'skill-invoked' if none>" }
   ```
3. `Task`: spawn `subagent_type=generalPurpose`, `run_in_background=true`,
   with a prompt that follows
   `.gsd-recipe/templates/fotw-observer-task-prompt.md` verbatim (do not
   improvise different instructions here — that file is the single source
   of truth shared with the hook-triggered path).
4. `Write`: mark `.gsd-recipe/.observer-active.json` with the current
   `session_id`, so neither this skill nor the reactive hook nudges again
   for the same session.

## D. Do NOT

- Do not spawn a second observer for a session that is already marked
  active — always check `can-spawn` first, never spawn unconditionally.
- Do not inline the subagent's instructions here or anywhere else — always
  point at `fotw-observer-task-prompt.md` so the hook path and this skill
  path can never drift apart.
- Do not treat a `can-spawn` block (disabled / not installed / already
  active) as an error — it is expected, silent, correct behavior.
- Do not assume `recipe-prd-intake` or any specific caller command exists —
  this skill must work standalone, invoked by name, with no caller at all.
</cursor_skill_adapter>

# fotw-observer-bootstrap — FOTW observer pluggable trigger

The **deterministic** half of the FOTW trigger design (the reactive
`postToolUse` hook in `.cursor/hooks/fotw-observer-nudge.sh` is the
**catch-all** half — see `bench/report/fotw-observer-install-integration-report.md`
for the full architecture). Where the hook depends on the primary agent
noticing and acting on an injected `additional_context` reminder after the
fact, this skill is meant to be called as an explicit, first-class step in
a command's own workflow — much more reliable, because it is "part of doing
the command correctly," not an interruption to it.

**Spec:** `docs/netapp-recipe/lld/OBSERVER-LLD.md` ·
`docs/netapp-recipe/lld/INSTALL-LLD.md` Step 3 ·
`docs/netapp-recipe/lld/RUNTIME-LLD.md` §1.a–1.b (PRD intake / bootstrap).

## Workflow

1. Resolve `session_id` and `transcript_path` for the current session (from
   the caller's context if it has them; otherwise from the runtime's own
   session metadata).
2. Run the shared guard: `.gsd-recipe/lib/observer-lib.sh can-spawn
   .gsd-recipe/observer-config.json .gsd-recipe/.observer-active.json
   <session_id>`.
3. If blocked — stop silently (or log the printed reason if useful for
   debugging); this is normal, not an error.
4. If allowed — write the target descriptor, spawn the background `Task`
   per `fotw-observer-task-prompt.md`, and mark the active-session file.

## How a future PRD-intake command should wire this in

Once a real entry point exists (e.g. `recipe-prd-intake`, `BACKLOG.md`
TASK-016), its own `SKILL.md` should add one line at the end of its PRD
intake / bootstrap step:

> "After PRD intake completes, invoke the `fotw-observer-bootstrap` skill."

That is the entire integration surface — no shared code to duplicate, no
knowledge of the observer's internals required by the caller.

## Relationship to the hook

Both trigger paths call the exact same guard and the exact same subagent
instructions. Keep both: the hook catches PRD-intake writes that happen
through *any* path (including raw native GSD commands with no recipe
wrapper at all), while this skill gives whichever command wires it in a
reliable, non-reactive spawn. Neither path is authoritative over the other —
`can-spawn`'s anti-double-spawn check is what keeps them from ever double
firing for the same session.
