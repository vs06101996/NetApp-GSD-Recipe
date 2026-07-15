# `recipe-observe` skill (TASK-032)

Built per direct task assignment — the **true last remaining unbuilt named `recipe-*` skill**.
`recipe-install` (TASK-031) was believed to be the last one when it landed, but its own report's
"All other `recipe-*` wrappers (`recipe-observe`)" Spec-table row still named one more; this task
closes that row. Once this task landed, **every** named `recipe-*` skill in
`docs/netapp-recipe/README.md`'s Built-vs-spec table and `docs/netapp-recipe/BACKLOG.md`'s task
table is Built.

`recipe-observe` is a thin, invoke-by-name **front door** for the FOTW observer's (TASK-013)
operator-facing lifecycle — `status`/`start`/`stop`/`enable`/`disable` — dispatching entirely to
pieces this task adds to already-existing infrastructure, per the locked scope:

- **`status`** — new `bench/lib/observer-lib.sh status` subcommand. Read-only, always exits 0 (even
  when the observer isn't installed at all), prints a fixed `key: value` report.
- **`start`** — a pure pass-through to the already-built `fotw-observer-bootstrap` skill (Option B,
  skill-to-skill dispatch). Zero new spawn logic.
- **`stop`** — new `bench/lib/observer-lib.sh request-stop` subcommand. Idempotently creates the
  graceful-finalize stop-sentinel file the tick loop's own prompt already watches for
  (`session_end_triggers.explicit_stop`) — previously only human-`touch`-able.
- **`enable`/`disable`** — new `bench/lib/observer-lib.sh enable`/`disable` subcommands. Atomic
  `"enabled"` JSON toggle (mktemp+mv), fails closed on a missing config.

## Locked design decisions (implemented exactly, not re-derived)

1. **Thin dispatch, zero engine reimplementation.** Every subcommand maps directly onto a primitive
   that either already existed (`fotw-observer-bootstrap`'s spawn logic, `observer-config.json`'s
   `"enabled"` key, the tick loop's `session_end_triggers.explicit_stop` check) or is a pure,
   mechanical read/write primitive added to `observer-lib.sh` in this task — never a rewrite of the
   observer engine itself. Same "thin dispatch, not a runtime rewrite" philosophy
   `tracker-sync-SKILL.md`'s own § Scope established.
2. **`status` has no prerequisite and never fails closed.** Unlike the other four subcommands, it
   must work even when `.gsd-recipe/observer-config.json` is missing entirely — reporting
   `installed: false` rather than erroring, so an operator can always ask "what's the state of the
   observer here?" without first knowing whether it's even installed.
3. **`start`/`stop`/`enable`/`disable` fail closed on a missing config**, with a clear "not
   installed" message pointing at the `fotw-observer` installer / `install.sh` — this skill never
   creates `observer-config.json` itself; that remains exclusively `install-observer.sh`'s job.
4. **`stop` is a graceful-finalize signal only, documented as such every single time it's
   invoked** — never presented as, or allowed to be mistaken for, a forced kill. See the dedicated
   section below for the full reasoning and exact wording.
5. **Installer stages exactly one file** (`.cursor/skills/recipe-observe/SKILL.md`) and never
   touches `.gsd-recipe/observer-config.json`, `.gsd-recipe/lib/observer-lib.sh`, or
   `.gsd-recipe/scripts/install-observer.sh` — those three remain exclusively `install-observer.sh`'s
   job, mirroring the "installer stages, skill's own prerequisites section documents" split
   `gsd-jira-sync`'s installer already established relative to `tracker-sync`.
6. **Do not invent a 5th subcommand.** No `restart`/hard-`kill` exists in `observer-lib.sh`, and none
   is improvised in the skill — an operator asking for a forced kill is told plainly that no such
   mechanism exists anywhere in this recipe or in Cursor's own `Task` tool.

## Why `stop` is documented as a graceful signal, not a kill switch

`recipe-observe stop` creates `.learnings/observer/.stop` (or whichever path
`observer-config.json`'s `paths.stop_sentinel_file` names) and nothing else. The **only** thing that
ever acts on that file is the next iteration of an *already-running* background `Task` subagent's
own tick loop, per `fotw-observer-task-prompt.md` step 1 ("Explicit stop check. If
`paths.stop_sentinel_file` exists → finalize immediately"). Concretely, this means:

- If the observer subagent is genuinely running and ticking, `stop` works — the next tick sees the
  sentinel and finalizes gracefully.
- If the observer subagent has already crashed, was never actually spawned (the exact non-guaranteed
  gap `fotw-observer-install-integration-report.md`'s own "Step 5 doesn't happen" caveat documents),
  or has already finished — `stop` still "succeeds" (the file gets created, exit 0), but **nothing is
  listening**, so nothing observable happens.
- **There is no mechanism anywhere in this recipe — not in this skill, not in `observer-lib.sh`, not
  in Cursor's own `Task` tool — to forcibly terminate an already-spawned background subagent.** This
  is a hard platform limitation, not a scope choice this task narrowed away.

The skill's own § C therefore surfaces this caveat **verbatim, every single time `stop` is invoked**
(not just the first), and § D explicitly forbids letting an operator walk away believing it is a
forceful kill switch. The exact wording shipped in `recipe-observe-SKILL.md`:

> This only creates the graceful-finalize sentinel file the tick loop's own prompt
> (`fotw-observer-task-prompt.md`'s `session_end_triggers.explicit_stop`) already checks at the top
> of every tick. It does **not** and **cannot** forcibly kill an already-running background `Task`
> subagent — no such capability exists. If the observer has already crashed, finished, or was never
> actually spawned, this sentinel has no effect until (and unless) a tick loop runs again and checks
> for it. Use `recipe-observe status` afterward to see whether the observer is still `active`.

## `status` output format (a judgment call — no prior precedent enforced a shape)

`observer-lib.sh status` prints a fixed, stable, `key: value` report, one fact per line, always in
this order:

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

This shape directly answers the five questions an operator asking "what is the observer doing right
now?" actually has: is it installed at all, is it turned on, is a session currently active, how much
has it produced so far, and has anyone already asked it to stop. It deliberately does **not** attempt
to report whether the underlying background `Task` subagent process is *actually alive* right now —
Cursor exposes no such introspection primitive, so `active`/`tick_count` (does the marker exist, is
data still growing) are the closest proxies available — the same limitation the `stop` section above
documents for the opposite direction (no forced-kill capability either).

## Ownership table — which piece owns which primitive

| Subcommand | Owned by | This skill's role |
|---|---|---|
| `status` | `observer-lib.sh status` (new this task, pure read) | Resolves the 4 well-known paths, shells out, relays the report verbatim |
| `start` | `fotw-observer-bootstrap` (unchanged) | Invokes it by name; adds zero spawn logic |
| `stop` | `observer-lib.sh request-stop` (new this task) + the tick loop's pre-existing `session_end_triggers.explicit_stop` check (unchanged) | Shells out to create the sentinel; surfaces the graceful-only caveat verbatim every time |
| `enable`/`disable` | `observer-lib.sh enable`/`disable` (new this task) | Shells out; trusts the subcommand's own exit code and stderr message |

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| A forced-kill / hard-stop mechanism | No such platform primitive exists (Cursor's `Task` tool offers no "kill this background agent" call) — not a scope choice, a hard limitation, documented explicitly rather than silently absent. |
| A `restart` subcommand | Not requested by the locked scope; `stop` then `start` already composes to the same effect using existing primitives. |
| Creating/modifying `.gsd-recipe/observer-config.json` from this skill or its installer | Exclusively `install-observer.sh`'s job — this task only ever reads or atomically toggles one existing key inside it. |
| Staging or touching `.gsd-recipe/lib/observer-lib.sh` / `.gsd-recipe/scripts/install-observer.sh` from `install-recipe-observe.sh` | Same ownership split as above — this installer stages exactly the one skill file. |
| Reimplementing `can-spawn`, the target-descriptor write, or the `Task` spawn call | Always delegated to `fotw-observer-bootstrap` by name for `start`. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| `observer-lib.sh` extensions | `bench/lib/observer-lib.sh` | 4 new subcommands: `status` (read-only, always exit 0, fixed `key: value` report), `enable`/`disable` (atomic `"enabled"` JSON toggle via mktemp+mv, preserves unrelated keys, fails closed on missing config), `request-stop` (idempotent sentinel-file creation, creates parent dir). |
| Skill content | `.gsd-recipe/templates/recipe-observe-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block dispatching all 5 subcommands, a dedicated "The `stop` subcommand's real limitation" section, a `status` output-format section, and a "Relationship to `fotw-observer-bootstrap`" section. |
| Installer | `.gsd-recipe/scripts/install-recipe-observe.sh` | Standalone installer mirroring `install-tracker-sync.sh`'s structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard), staging to `.cursor/skills/recipe-observe/SKILL.md`. Ledger component `"recipe-observe"`. Never touches `observer-config.json`, `observer-lib.sh`, or `install-observer.sh`. |
| Tests (lib) | `bench/tests/test-observer-lib.sh` | Extended with 7 new test cases (35 total assertions) covering `status`'s full field set and fail-open-on-missing-config behavior, `enable`/`disable`'s atomicity and unrelated-key preservation, `request-stop`'s idempotency and directory creation, and tick-count accuracy. |
| Tests (installer) | `bench/tests/test-install-recipe-observe.sh` (new, 35 assertions) | Fail-closed non-git target, fresh install staging exactly the skill file, exactly-1 ledger row, never touching `observer-config.json`/`observer-lib.sh`/`install-observer.sh`/`.observer-active.json`/`fotw-observer-bootstrap`'s skill file, 13 staged-content assertions covering every documented workflow step/caveat/scope-boundary above, idempotent re-install, uninstall + ledger-clear + directory cleanup (with the same never-touch assertions repeated on the removal path), self-install collision safety, self-uninstall canonical-source preservation. |
| Composed into `install.sh` | 17th sub-installer, appended after the existing 16 — path var, `install()`/`uninstall()`/`verify()` wiring, consent-prompt string, "composing sub-installers..." echo line, header comment. | |
| Capability catalog | `bench/lib/capability-schema.sh` — 19th `CATALOG` entry (`id: "recipe-observe"`, `task_id: "TASK-032"`). | |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-032 row, `Depends: 013`) and `docs/netapp-recipe/README.md` (Built-vs-spec dedicated row replacing the "All other `recipe-*` wrappers (`recipe-observe`)" row; Commands→Built row; dedicated Spec-table row removed; shipped-percentage header recomputed `~97%` → `100%`). | |

## Shipped-percentage recomputation

The prior `~97%` figure resolves to 30 Built / 31 (Built + Spec) rows in the Built-vs-spec table (the
`dag-build.sh` **Parked** row excluded from the denominator, same as every prior addition's
recomputation) = 96.8%, rounded to 97%. `recipe-observe` moving from Spec (the "All other `recipe-*`
wrappers" row) to its own dedicated Built row makes it 31 Built / 31 = **100%** — every named
`recipe-*` skill in the spec is now Built.

## Validation performed

### Automated

`bench/tests/test-observer-lib.sh` (extended, run standalone):

```
$ ./bench/tests/test-observer-lib.sh
...
35 passed, 0 failed
```

`bench/tests/test-install-recipe-observe.sh` (new, run standalone):

```
$ ./bench/tests/test-install-recipe-observe.sh
...
35 passed, 0 failed
```

`bench/tests/test-capability-schema.sh` (extended for the 19th catalog entry):

```
$ ./bench/tests/test-capability-schema.sh
...
30 passed, 0 failed
```

`bench/tests/test-install.sh` (extended with 4 new recipe-observe composition/verify/uninstall
assertions):

```
$ ./bench/tests/test-install.sh
...
126 passed, 0 failed
```

Full `bench/tests/*.sh` suite, run **twice** after all composition edits landed:

- **Run 1:** all 32 files exit 0, zero failures.
- **Run 2 (immediate re-run):** all 32 files exit 0, zero failures — identical result, confirming no
  flakiness or ordering dependency across the suite.

Every shell file touched or created was syntax-checked with `bash -n`: `bench/lib/observer-lib.sh`,
`.gsd-recipe/scripts/install-recipe-observe.sh`, `.gsd-recipe/scripts/install.sh`,
`bench/tests/test-observer-lib.sh`, `bench/tests/test-install-recipe-observe.sh`,
`bench/tests/test-install.sh`, `bench/lib/capability-schema.sh`,
`bench/tests/test-capability-schema.sh` — all clean.

### Self-install into the real repo

```bash
./.gsd-recipe/scripts/install-recipe-observe.sh --yes --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh generate-capability --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh validate-capability \
  --capability .gsd-recipe/capability.json --schema .gsd-recipe/capability.schema.json
```

Staged `.cursor/skills/recipe-observe/SKILL.md`, recorded exactly 1 new ledger row, regenerated
`.gsd-recipe/capability.json` (**19 capabilities**, `recipe-observe` reporting `staged: true`), and it
validates cleanly against `capability.schema.json`.

`git status --porcelain` after the self-install/regeneration confirms only the expected paths
changed: this task's new files (`recipe-observe-SKILL.md`, `install-recipe-observe.sh`,
`test-install-recipe-observe.sh`, this report), this task's edits to the six shared composition files
(`observer-lib.sh`, `test-observer-lib.sh`, `install.sh`, `test-install.sh`, `capability-schema.sh`,
`test-capability-schema.sh`, `BACKLOG.md`, `README.md`), and the self-install's own side effects
(`.cursor/skills/recipe-observe/SKILL.md`, `.gsd-recipe/ledger.json`, `.gsd-recipe/capability.json`)
— no other files were touched.

### Real, read-only `status` check against this repo's actual runtime files

Per the explicit safety constraint, `observer-lib.sh status` was run for real against this repo's
own `.gsd-recipe/observer-config.json` and `.gsd-recipe/.observer-active.json` — a pure read, no
mutation:

```
$ ./bench/lib/observer-lib.sh status .gsd-recipe/observer-config.json \
    .gsd-recipe/.observer-active.json .learnings/observer/ticks.jsonl \
    .learnings/observer/.stop
```

`enable`, `disable`, and `request-stop` were **never** invoked against this repo's real files — every
exercise of those three subcommands happened exclusively against disposable `mktemp -d` scratch
repos/configs, both in `test-observer-lib.sh` and `test-install-recipe-observe.sh`.

### What was NOT invoked conversationally (by design)

Per this task's explicit instruction, `recipe-observe` itself was **not** invoked conversationally —
doing so would dispatch `start` to `fotw-observer-bootstrap` and spawn a real background `Task`
subagent. The skill's *content* was instead validated by careful reading/review (this report, plus
the 13 staged-content `grep` assertions in the test file asserting every documented workflow step,
caveat, and scope boundary is actually present in the shipped `SKILL.md`) — the installer that stages
it and the `observer-lib.sh` primitives it dispatches to (the only genuinely scriptable parts of this
task) were exercised for real, repeatedly, against disposable scratch repos/configs and this real
repo's own self-install/read-only status check.

## Files

- `.gsd-recipe/templates/recipe-observe-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-observe.sh` (new)
- `bench/tests/test-install-recipe-observe.sh` (new, 35 assertions)
- `bench/report/recipe-observe-integration-report.md` (new, this file)
- `.cursor/skills/recipe-observe/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` / `.gsd-recipe/capability.json` (self-install side effects, real repo — additive only)

**Modified (composed directly — no concurrent siblings running this session):**
`bench/lib/observer-lib.sh`, `bench/tests/test-observer-lib.sh`, `.gsd-recipe/scripts/install.sh`,
`bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`.

## Deviations / judgment calls

None in scope or design — all locked decisions were implemented exactly as specified. Two judgment
calls worth flagging explicitly:

1. **`status`'s exact field order and shape** — no prior precedent enforced a specific report shape
   for a new introspection subcommand; the 10-line `key: value` shape above was chosen to directly
   answer the five natural operator questions (installed? enabled? active? how much produced? stop
   already requested?) in a single fixed-order, stable, machine-parseable block.
2. **Shipped-percentage recomputation method** — same reverse-engineering method every prior task in
   this series has used: testing which built-vs-spec-row ratio reproduces the prior documented
   figure (30/31 = 96.8% ≈ 97%, excluding the `Parked` `dag-build.sh` row from the denominator) rather
   than assuming a documented formula existed — the resulting **100%** (31/31) follows the same
   method, and is now an exact, not rounded, figure.
