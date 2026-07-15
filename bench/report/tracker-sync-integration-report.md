# tracker-sync generalization (TASK-014)

**Picked next per user selection**, following TASK-005 (`sync-drain-queue.sh`).
`BACKLOG.md` lists TASK-014 as depending on TASK-005 (built) with size `S` —
the smallest unblocked item left in the traceability wave, and a natural
follow-on to the just-completed Jira-only drain loop: the recipe's own docs
already talk about tracker choice as a first-class install-time decision
(`INSTALL-LLD.md` Step 4, `{TRACKER}` placeholder), but nothing actually
implements that choice yet — every script hardcodes `"jira"` as a literal
string.

## Key design decision: install-time dispatch, not runtime rewrite

`INSTALL-LLD.md`'s Step 4 spec ("tracker-sync skill registration") and its
`{TRACKER}` placeholder table (`jira`, `github_issues`, `linear`) read as a
mandate for a fully tracker-parameterized runtime: every script that talks to
Jira today (`sync-reconcile.sh`, `sync-drain-queue.sh`, `sync-ledger.sh`,
`draft-jira-comment.sh`) rewritten to branch on an adapter. Taken literally,
that's a much larger task than the `S`-sized backlog estimate implies, and it
collides with `DECISIONS.md`'s own **Locked (v1)** table, which limits
platforms to **Jira + GitHub** — `linear` is explicitly out of scope for v1,
so the placeholder's third option is illustrative future-proofing, not a v1
requirement. GitHub tracker-sync itself is also still blocked on TASK-006
(not yet built), so a runtime GitHub adapter would have nothing to delegate
to today anyway.

Scope was narrowed and confirmed with the user before building:

| Layer | Status | Scope |
|---|---|---|
| Install-time registration | **This task** | A `tracker` key in `.gsd-recipe/config.json` (default `jira`), plus a thin `tracker-sync` skill that reads that key and dispatches — `INSTALL-LLD.md`'s literal "tracker-sync skill registered" output. |
| Runtime tracker adapters | **Deferred** | `sync-reconcile.sh`/`sync-drain-queue.sh`/`sync-ledger.sh`/`draft-jira-comment.sh` stay Jira-literal, unchanged. Rewriting them to branch on `{TRACKER}` has no second implementation to branch to yet (GitHub sync is TASK-006), so it would be speculative generality with no real second caller to validate it against. |

This mirrors the same reconcile/drain narrowing precedent from TASK-003: ship
the piece of the spec that has a concrete consumer today, name the deferred
piece explicitly so it isn't mistaken for an oversight, and let the next
tracker (GitHub, via TASK-006) be the actual trigger for generalizing the
runtime scripts — retrofitting an abstraction for a single real
implementation (Jira) tends to guess wrong about the shape a second
implementation needs.

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Tracker config library | `bench/lib/tracker-sync-config.sh` | `get-tracker`/`set-tracker` against `.gsd-recipe/config.json`'s `tracker` field. Validation is hardcoded to the two locked v1 platforms (`jira`, `github`) — rejects `linear` on purpose (see design decision above), not relying on an environment variable an operator could accidentally widen. |
| Tracker-sync skill | `.gsd-recipe/templates/tracker-sync-SKILL.md` | Thin dispatcher: reads the configured tracker, delegates to `gsd-jira-sync` for `tracker: jira`, reports "not implemented, needs TASK-006" for `tracker: github`. |
| Installer | `.gsd-recipe/scripts/install-tracker-sync.sh` | Standalone installer (mirrors `install-recipe-prd-intake.sh`/`install-observer.sh`), ahead of TASK-010's `install.sh`. Stages the skill, initializes `config.json`'s `tracker` to `jira` **only if the key is absent** (never overwrites an operator's own choice), `--uninstall` removes the staged skill but always leaves `config.json` untouched. |
| Tests | `bench/tests/test-tracker-sync-config.sh` (10 assertions), `bench/tests/test-install-tracker-sync.sh` (16 assertions) | Config library behavior (defaulting, validation, JSON correctness) and installer behavior (fresh install, idempotency, operator-config preservation, uninstall, self-install) respectively. |

### Why `config.json` is never ledger-tracked for deletion

Every other installer in this recipe (`install-observer.sh`,
`install-recipe-prd-intake.sh`) ledgers every file it creates so
`--uninstall` can cleanly remove exactly what it staged. `config.json` is
different: it's a single shared file that other, unrelated recipe settings
may also live in (today just `tracker`, but nothing prevents future
components from adding their own keys to the same file). Ledgering it would
mean `--uninstall` deletes the whole file — destroying any co-located
settings this installer doesn't own. So `install-tracker-sync.sh` writes to
`config.json` via `tracker-sync-config.sh` but never records it in the
ledger; `--uninstall` only ever removes the skill file it did stage. Verified
directly in the test suite (assertion: "uninstall preserves unrelated
pre-existing config.json keys").

## Validation performed

Manual smoke test against real scratch git repos first (fresh install,
idempotent re-run, uninstall, operator-github-preserved, self-install), then
formalized into the checked-in regression suite:

| # | Check | Result |
|---|---|---|
| 1 | Config library: `tracker` key defaults to unset until explicitly set | PASS |
| 2 | Config library: `set-tracker` rejects `linear` (not a locked v1 platform) | PASS |
| 3 | Config library: `set-tracker` requires a value argument | PASS |
| 4 | Config library: `get-tracker`/`set-tracker` round-trip through valid JSON | PASS |
| 5 | Installer refuses to install outside a git repo (fail closed) | PASS |
| 6 | Fresh install stages `.cursor/skills/tracker-sync/SKILL.md` | PASS |
| 7 | Fresh install initializes `config.json`'s `tracker` to `jira` (default) | PASS |
| 8 | Fresh install records exactly 1 ledger row (the skill file only) | PASS |
| 9 | Staged skill references `gsd-jira-sync` (delegates, doesn't reimplement) | PASS |
| 10 | Re-running install does not duplicate ledger rows | PASS |
| 11 | Re-running install leaves an already-set tracker value unchanged | PASS |
| 12 | Install never overwrites an operator's pre-existing tracker choice (`github` stays `github`) | PASS |
| 13 | Uninstall removes the staged skill, preserves `config.json` and its `tracker` value | PASS |
| 14 | Uninstall preserves unrelated pre-existing `config.json` keys | PASS |
| 15 | Uninstall clears the component's ledger entry | PASS |
| 16 | Self-install into a copy of this repo does not error and preserves the canonical skill template source | PASS |

Full `bench/tests/` suite after this addition: 10 (nudge) + 17
(install-observer) + 17 (install-recipe-prd-intake) + 16
(install-tracker-sync, this task) + 12 (observer-lib) + 6
(observer-tick-loop) + 20 (parse-state) + 18 (sync-drain-queue) + 9
(sync-ledger) + 14 (sync-reconcile) + 10 (tracker-sync-config, this task) =
**149 assertions across all 11 test files, all passing, zero regressions.**

## Explicitly deferred (do not mistake for oversights)

| Deferred | Why |
|---|---|
| Runtime GitHub tracker-sync | Blocked on TASK-006 (not yet built) — the skill reports this explicitly rather than silently no-op'ing. |
| Rewriting `sync-reconcile.sh`/`sync-drain-queue.sh`/`sync-ledger.sh`/`draft-jira-comment.sh` to branch on `{TRACKER}` | No second real implementation to validate the abstraction against yet; deferred until TASK-006 lands. |
| Wiring into `install.sh` (TASK-010) | Not yet built — this installer is standalone, same precedent as `recipe-prd-intake`/FOTW observer bypassing TASK-010. |
| `linear` as a tracker option | `INSTALL-LLD.md`'s `{TRACKER}` placeholder lists it as an example, but `DECISIONS.md`'s Locked (v1) table limits v1 to Jira + GitHub — config library rejects it on purpose. |

## Files

- `bench/lib/tracker-sync-config.sh`
- `.gsd-recipe/templates/tracker-sync-SKILL.md`
- `.gsd-recipe/scripts/install-tracker-sync.sh`
- `bench/tests/test-tracker-sync-config.sh`
- `bench/tests/test-install-tracker-sync.sh`

## Live dispatch smoke test

**Gap closed:** TASK-014's own test suite (16 assertions above) only exercised
the installer/config logic against scratch local git repos — no MCP calls at
all. Whether invoking `tracker-sync` by name actually hands off to
`gsd-jira-sync` and results in a real posted comment was never exercised.
This section closes that gap with a real call against `netapp.atlassian.net`.

**Setup:** ran `./.gsd-recipe/scripts/install-tracker-sync.sh --yes` against
this repo for the first time — staged `.cursor/skills/tracker-sync/SKILL.md`
and initialized `.gsd-recipe/config.json` with `"tracker": "jira"`. Read the
now-staged skill and literally followed its dispatch instructions:
`bench/lib/tracker-sync-config.sh get-tracker` reported `jira`, so per the
skill's § C branch ("`jira` — invoke the `gsd-jira-sync` skill... follow *its*
`SKILL.md` for everything from here"), execution continued into
`gsd-jira-sync`'s documented workflow (`docs/netapp-recipe/reference/skills/gsd-jira-sync/SKILL.md`),
run via its constituent `bench/` primitives — same precedent as
[gsd-jira-sync-live-test-report.md](gsd-jira-sync-live-test-report.md), since
`gsd-jira-sync` isn't itself installed as a live `.cursor/skills/` folder yet.

**Event chosen:** `execute_started` targeting `KAN-40` (phase 1, phase-routed).
Not a duplicate — `.gsd-recipe/sync-ledger.jsonl` only had `discuss_complete`
(epic `KAN-39`) and `plan_complete` (phase 1, `KAN-40`) from the prior live
test; `execute_started` on the same issue is a genuinely new key.

| # | Step | Mechanism | Result |
|---|---|---|---|
| 1 | Dispatch check | `bench/lib/tracker-sync-config.sh get-tracker` | `jira` → delegates to `gsd-jira-sync` per staged skill |
| 2 | Resolve issue | `parse-state.sh resolve-issue execute_started --phase 1` | → `KAN-40` |
| 3 | Draft comment | `draft-jira-comment.sh execute_started KAN-40 --phase 1` | rendered from `_comment.template.md` |
| 4 | Compute key | `sync-ledger.sh key execute_started KAN-40 --phase 1` | `gsd-recipe:execute_started:phase=1:issue=KAN-40` |
| 5 | Pre-post duplicate check | `sync-ledger.sh has "$KEY"` | absent (exit 1) — correct, first run |
| 6 | Post comment for real | `addCommentToJiraIssue` (cloudId `netapp.atlassian.net`, `issueIdOrKey` `KAN-40`) | Jira comment id **`10002`** |
| 7 | Append to ledger | `sync-ledger.sh append "$KEY" jira --external-id jira-comment-10002 --result posted` | 1 line appended to `.gsd-recipe/sync-ledger.jsonl` |
| 8 | Read-back verification | `getJiraIssue` (`fields: ["comment"]`) on `KAN-40` | comment `10002` body matches byte-for-byte what was drafted/posted |
| 9 | Idempotency re-check | `sync-ledger.sh has "$KEY"` again | now reports **already posted** (exit 0) — the exact signal that prevents a real duplicate repost |

No MCP auth prompt was hit this session (the Atlassian MCP was already
authenticated from the prior live-test session), so the `mcp_auth` fallback
path wasn't exercised here.

**Result: PASS.** The full `tracker-sync → gsd-jira-sync` handoff works as
designed: the dispatcher correctly reads `tracker: jira` from a freshly
installed config, routes to `gsd-jira-sync`'s documented flow, and that flow's
primitives (`parse-state.sh`, `draft-jira-comment.sh`, the real Atlassian MCP,
`sync-ledger.sh`) post a genuine new comment, verify it landed, and correctly
flip to "already posted" on the idempotency check. `KAN-39`/`KAN-40` remain
disposable test fixtures per the prior live-test report's precedent.
