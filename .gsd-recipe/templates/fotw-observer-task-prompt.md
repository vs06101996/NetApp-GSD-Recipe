# FOTW observer — subagent task prompt (shared, runtime-agnostic)

**Single source of truth for what the spawned observer subagent actually does.**
Both trigger paths — the reactive hook
([.gsd-recipe/templates/fotw-observer-nudge.sh](fotw-observer-nudge.sh)) and the
pluggable skill (`.cursor/skills/fotw-observer-bootstrap/SKILL.md`) — must
point here instead of inlining instructions, so behavior stays identical
regardless of which trigger fired.

**Scope note:** this design assumes at most one *active* observer per repo at
a time (matching the existing anti-double-spawn marker, which stores a single
`session_id`). It is not built for multiple concurrent observer sessions
against the same `.learnings/observer/` tree — the tick lock prevents
corrupted writes if that ever happens, but the target descriptor
(`.gsd-recipe/.observer-target.json`) is a single global file that a second
concurrent spawn would overwrite. Out of scope to fix here; noted so it isn't
mistaken for an oversight later.

## Inputs (read once at spawn time)

1. `.gsd-recipe/.observer-target.json` — `session_id`, `transcript_path` (the
   absolute path to *this* session's live transcript JSONL — read directly
   from here, not from `config.paths.live_transcript_file`, which is reserved
   for a future adapter that mirrors/copies transcripts instead of reading
   them in place).
2. `.gsd-recipe/observer-config.json` — `tick_interval_seconds`,
   `rollup_threshold_signal_lines`,
   `inactivity_consecutive_empty_ticks_threshold`,
   `end_trigger_finalize_margin_ticks`, `paths.*`, `classification_rubric`,
   `session_end_triggers`.

## Loop (repeat until an end-trigger fires)

Keep an in-memory `consecutive_empty_ticks` counter across loop iterations
(this is one continuous subagent turn, not separate invocations — no need to
persist the counter to disk).

1. **Explicit stop check.** If `paths.stop_sentinel_file` exists → finalize
   immediately (`explicit_stop`), skip straight to Finalize.
2. **Acquire tick lock.** `.gsd-recipe/lib/observer-lib.sh lock <paths.lockfile>`
   (deployed copy staged by the installer; canonical source is
   `bench/lib/observer-lib.sh` in this implementation repo).
   If not acquired (another tick in progress — only possible if something
   else is concurrently ticking against the same files), sleep a short
   backoff and retry; do not skip the tick silently.
3. **Read new lines.** `.gsd-recipe/lib/observer-lib.sh read-new <transcript_path> <paths.offset_file>`
   — prints `<line_no>\t<json_line>` for everything since the committed
   offset. Does not advance the offset yet.
4. **Zero new lines?** Increment `consecutive_empty_ticks`. If it reaches
   `inactivity_consecutive_empty_ticks_threshold` → release the lock,
   finalize as `inactivity`. Otherwise release the lock, sleep
   `tick_interval_seconds`, go to step 1.
5. **New lines exist.** Reset `consecutive_empty_ticks` to 0. For each new
   line, classify using `classification_rubric`:
   - `signal` — on-topic AND conclusive (decision, fact, requirement,
     confirmed answer).
   - `noise_irrelevant` — off-topic.
   - `noise_hedge` — on-topic but non-conclusive (hedges, TBDs, assumptions).

   While classifying, also watch for a turn that declares all tracked
   requirements/PRD items satisfied — if found, remember to finalize as
   `prd_complete` right after this tick's writes land (do not cut the tick
   short; finish writing everything read in this batch first).
6. **Write results.**
   - Append every `signal` line to `paths.ticks_file` via `append-jsonl`
     (one JSON object per line: `{"line": N, "label": "signal", "note": "<short judgment>"}`).
   - Append every `noise_irrelevant` / `noise_hedge` line to
     `paths.noise_log_file` via `append-jsonl` (same shape, label reflects
     the category).
   - Only after all appends for this batch succeed: `commit-offset
     <paths.offset_file> <highest line_no read this batch>`.
7. **Release the tick lock.** `.gsd-recipe/lib/observer-lib.sh unlock <paths.lockfile>`.
8. If step 5 flagged `prd_complete` → finalize now (`prd_complete`), skip the
   sleep. Otherwise sleep `tick_interval_seconds`, then go to step 1.

## Finalize (any end-trigger)

1. Wait `end_trigger_finalize_margin_ticks` extra tick-intervals before
   closing the book, running steps 2–7 of the loop once more each time, in
   case a trailing burst of lines lands right at the boundary.
2. **Read existing knowledge before writing anything new.** List and read
   every file already under `paths.kb_sessions_dir` and
   `paths.kb_playbooks_dir` (there may be none, on a fresh repo — that's
   fine, skip to step 3). This is the entire "conflict check": no separate
   tool or algorithm, just reading prior structured summaries before adding
   a new one, the same way a human reviewer would.
3. Summarize the session's accumulated `ticks.jsonl` entries (signal lines
   only) into an OKF-shaped session summary file under
   `paths.kb_sessions_dir`, named by `session_id` and date. While writing
   it, compare each signal item against (a) earlier ticks *in this same
   session* and (b) the existing files read in step 2. A session can
   contradict itself just as easily as it can contradict prior knowledge —
   check both.
   - If nothing conflicts: write the summary with plain frontmatter
     (`type: session_summary`, `status: unverified`, `rollup_id`,
     `covers_ticks`, `covers_lines`, `generated`) — see
     `.learnings/kb/sessions/run1-rollup-02.md` for the reference shape.
   - If something conflicts (a fact, decision, or requirement changed
     value/shape from an earlier point in this session or from an existing
     playbook/session file): still write the summary, but call out the
     conflict inline in the body (what changed, from what, to what, which
     earlier tick/line or file it reverses) — again, see
     `run1-rollup-02.md`'s "Retry cap revised from 5 to 3 — reverses the
     value set earlier in this same session" line for the reference
     phrasing.
4. If total signal-line count for this session exceeds
   `rollup_threshold_signal_lines`, additionally propose a playbook entry
   under `paths.kb_playbooks_dir` — this is a **proposal for human review**,
   never an automatic promotion into `.knowledge/` (that promotion gate is
   `gsd-extract-learnings`, per `OBSERVER-LLD.md`). If this session's signal
   conflicts with an *existing* playbook file (found in step 2), do not
   silently overwrite it — instead:
   - Set `status: contradictory` and `needs_verification: true` in that
     existing playbook's frontmatter (edit in place, do not delete it —
     conflicting knowledge is still knowledge, and deletion would destroy
     the human reviewer's ability to see both sides).
   - Add/extend a `contradicts:` array field listing the session-summary
     file(s) that conflict with it.
   - Add a `contradiction_note:` field in plain language: what specifically
     differs and where each side comes from.
   - Reference exact schema and worked example:
     `.learnings/kb/playbooks/notification-retry-policy.md`.
5. Remove `.gsd-recipe/.observer-active.json` (this session is no longer
   active — a future PRD-intake signal in a new session should be able to
   spawn a fresh observer without being blocked by a stale marker).
6. Return a short completion summary from the subagent: end-trigger reason,
   signal/noise counts, the session-summary file path written, and — if
   applicable — which existing playbook(s) got flagged `contradictory` and
   why.
