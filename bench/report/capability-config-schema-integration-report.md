# `capability.json` + config schema (TASK-011)

Implemented per the task brief, running in parallel with four sibling tasks (TASK-007, TASK-021,
TASK-022, TASK-023). Per the shared-file-avoidance constraint, `.gsd-recipe/scripts/install.sh`,
`bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`, and `docs/netapp-recipe/README.md`
were **not edited** — see "Snippets for a follow-up integration pass" at the bottom for exactly
what a later pass should add to each.

## Scope decisions (this task had no prior example to mirror for `capability.json`)

| Decision | Rationale |
|---|---|
| `config.schema.json` is **draft-07**, not 2020-12 | Both drafts support `if`/`then`/`else` (needed for `traceability.reason`/`observer.interval_minutes`'s conditional-required fields), but draft-07 is the more universally recognized/tooling-supported draft. Declared explicitly via each file's own `"$schema"` key. |
| No `jsonschema` pip package | Confirmed absent from this environment (`python3 -c "import jsonschema"` → `ModuleNotFoundError`) and not used anywhere else in this repo (`rg jsonschema` → no matches). Mirrors this repo's existing convention (`parse-state.sh`, `install.sh --verify`'s own hand-rolled `python3 -c "assert ..."` checks) of never adding a new external dependency when python3's stdlib already covers the need. `bench/lib/capability-schema.sh` implements a hand-rolled **subset** of draft-07 (see "Validator scope" below) rather than a full spec-compliant engine — sufficient for both schemas this task actually ships. |
| `config.json`'s real shape was **introspected, not guessed** | Read `install.sh`, `install-tracker-sync.sh`, and every other `install-*.sh` script's `CONFIG=`/`config.json` references (confirmed only two scripts ever touch it), then **ran the real, unmodified `install.sh` against a fresh scratch git repo** (`/tmp/task-011-manual-01`) and inspected its real output. Real shape: `{"traceability": {"enabled": bool, "reason": str}, "observer": {"enabled": bool, "interval_minutes": int}, "tracker": "jira"\|"github"}` — matches `DATA-CONTRACTS.md`'s existing `traceability`/`observer` table exactly, plus the `tracker` field `DATA-CONTRACTS.md` hadn't schema-documented yet. |
| `tracker` is **optional** in the schema | `bench/lib/tracker-sync-config.sh get-tracker` treats an absent `tracker` key as `"jira"` rather than erroring, and `config.json` can validly exist without ever having run `install-tracker-sync.sh` (e.g. a hand-authored file, or a partial install). Marking it required would reject files the recipe's own code already treats as valid. |
| `additionalProperties: true` at every level | `install.sh`'s own `config_json_merge()` comment says "Additive only — never touches `tracker` or any other pre-existing key", and `install-tracker-sync.sh` documents `config.json` as a file that "may hold other keys". A schema that rejected unknown keys would break forward-compatibility with components not yet built (e.g. a future `graphify` or `recipe-*` key). |
| `capability.json`'s schema is **new design, no prior example** | The task explicitly calls this out — "no prior example exists in this repo". Designed as: a static per-repo-run **snapshot** (`schema_version`, `generated_at`, `recipe`, `capabilities[]`), where each `capabilities[]` entry documents one recipe capability from a **fixed catalog** (id, task_id, kind, description, invoke_name, staged_path, installer, composed_by_install_sh, ledger_component) plus two **introspected** fields (`staged`, `ledger_tracked`) computed against a real target repo. Explicitly **not** a duplicate of `ledger.json`: the ledger is an append/remove-on-uninstall *event* log per file; `capability.json` is a point-in-time *description* of what's staged right now, and never itself drives install/uninstall. |
| Capability `version` is a **documented placeholder** (`"1.0.0"` for everything) | This recipe has no per-component version-tracking mechanism yet — no `VERSION` file, no git-tag-per-skill convention. Rather than inventing a fake versioning scheme, every capability reports the same static string and both `capability.schema.json`'s own field description and this report call this out explicitly as a known limitation, not real semantic versioning. |
| `capability.json`'s catalog is **static and fixed** (7 entries) | `generate-capability` never invents entries from what it finds on disk — it always reports all 7 known capabilities (`install-core` TASK-010, `fotw-observer` TASK-013, `tracker-sync` TASK-014, `recipe-planning-policy` TASK-012, `recipe-prd-intake` TASK-016, `recipe-run-phase` TASK-024, `recipe-plan-phase` TASK-017, task ids confirmed against `BACKLOG.md`'s task table), each with `staged: true/false`. This keeps the manifest schema-stable across runs (always exactly 7 entries) rather than varying in shape depending on what happens to be staged. |
| `recipe-prd-intake`'s `composed_by_install_sh: false` | Confirmed by reading `install.sh`: it declares `OBSERVER_INSTALLER`/`TRACKER_SYNC_INSTALLER`/`RECIPE_PLANNING_POLICY_INSTALLER`/`RECIPE_RUN_PHASE_INSTALLER`/`RECIPE_PLAN_PHASE_INSTALLER` variables and invokes all five in `install()`/`uninstall()`, but has no `RECIPE_PRD_INTAKE_INSTALLER` variable at all — `install-recipe-prd-intake.sh`'s own header comment confirms it's "standalone (ahead of TASK-010)" and never composed. |
| `staged` detection rule | When a capability has a single canonical `staged_path` (every `cursor-skill`/`agent-skill` entry), `staged` = that file exists on disk (ground truth — corroborated by, but not solely dependent on, the ledger). When it has no single canonical path (`install-core`, which stages ~15 files across `.templates/`, `.knowledge/`, etc.), `staged` falls back to "is the ledger component present and non-empty". `ledger_tracked` is reported as a separate boolean alongside `staged` specifically so a caller can distinguish "file present but never ledgered" (e.g. hand-copied) from "ledgered but file missing" (e.g. manually deleted) — collapsing them into one boolean would hide that distinction. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Config schema | `.gsd-recipe/config.schema.json` | JSON Schema (draft-07) for `.gsd-recipe/config.json`'s real shape. |
| Capability schema | `.gsd-recipe/capability.schema.json` | JSON Schema (draft-07) for the new `.gsd-recipe/capability.json` manifest shape (see design table above). |
| Validation/generation library | `bench/lib/capability-schema.sh` | `validate <schema> <instance>` (generic), `validate-config`, `validate-capability`, `generate-capability` — CLI-subcommand style mirroring `bench/lib/parse-state.sh`/`bench/lib/sync-ledger.sh`. Contains a hand-rolled draft-07-subset validator (see "Validator scope" below) and the static 7-entry capability catalog. |
| Generated manifest (this repo, self-install artifact) | `.gsd-recipe/capability.json` | Real output of `generate-capability --target /Users/vs72964/Projects/gsd-benchmark`, same "self-install side effect" precedent every prior installer task has left behind (e.g. `.cursor/skills/tracker-sync/SKILL.md`). Reports 5 of 7 capabilities staged in this repo today (`install-core` and `recipe-planning-policy` are not staged here — see "A real finding" below). |
| Tests | `bench/tests/test-capability-schema.sh` (28 assertions) | Schema validation (valid/invalid cases for both schemas, covering type/enum/required/conditional-if-then violations), `generate-capability` introspection against scratch targets (staged/unstaged detection, idempotency, catalog stability, `--out` override), and fail-closed behavior on a missing schema file / malformed instance JSON. |
| Fixtures | `bench/tests/fixtures/gsd-recipe-config-*.json` (9 files), `bench/tests/fixtures/capability-*.json` (5 files) | New — no `.gsd-recipe/config.json` or `capability.json` fixtures existed before this task. |
| Doc updates | `docs/netapp-recipe/contracts/DATA-CONTRACTS.md`, `docs/netapp-recipe/lld/INSTALL-LLD.md` | Registered both new schema files in the Contract Index table; added a full `## .gsd-recipe/capability.json` normative section to `DATA-CONTRACTS.md` (shape table + example); annotated `INSTALL-LLD.md`'s directory tree with `[X] TASK-011` tags and a status note. Neither file is in the 4-file shared-avoidance list. |

## Validator scope (hand-rolled draft-07 subset)

| Supported | Not supported (schemas in this task don't need it) |
|---|---|
| `type` (incl. arrays of types, e.g. `["string","null"]`) | `$ref` / schema composition beyond `if`/`then`/`else` |
| `enum`, `const` | `patternProperties`, `propertyNames` |
| `required`, `properties`, `additionalProperties` (bool or schema) | `oneOf`/`anyOf`/`allOf` |
| `items` (single schema, list-form arrays) | `pattern` (regex), `format` |
| `minLength`, `minimum`, `maximum`, `minItems` | `maxLength`, `maxItems`, `uniqueItems`, `multipleOf` |
| `if`/`then`/`else` (evaluated over properties present in the instance) | Full draft-07 `if` semantics for absent properties — see the documented simplification below |

**Documented simplification:** `if: {"properties": {"enabled": {"const": false}}}` is evaluated by
checking `"enabled"` only when it's actually present in the instance being validated; if `"enabled"`
is missing entirely, the `if` vacuously "passes" (no violation found), which means `then` gets
applied even though the real draft-07 semantics would also depend on how `required` composes with
`if`. In practice this never produces a wrong verdict for either schema in this task: `traceability`/
`observer` both separately mark `enabled` as unconditionally `required`, so an instance missing
`enabled` already fails on that independent check regardless of what `if`/`then` additionally
reports — confirmed by test #8/#9 in `test-capability-schema.sh`, which check for the *presence* of
an error, not an exact single-error-only count.

## Test results

`bench/tests/test-capability-schema.sh` run standalone (per the task's explicit instruction not to
run the full `bench/tests/` suite while sibling tasks are mid-edit):

```
$ ./bench/tests/test-capability-schema.sh
ok - config schema: real install.sh shape (tracker+traceability+observer) validates
ok - config schema: minimal shape without 'tracker' key validates (tracker is optional)
ok - config schema: unrecognized extra keys do not fail validation
ok - config schema: traceability disabled + reason present validates
ok - config schema: missing required 'observer' object fails with actionable error
ok - config schema: wrong type (interval_minutes as string) fails
ok - config schema: unsupported tracker value fails enum check
ok - config schema: observer.enabled=true without interval_minutes fails conditional requirement
ok - config schema: traceability.enabled=false without reason fails conditional requirement
ok - config schema: top-level array instead of object fails type check
ok - validate-config subcommand runs against an explicit --config/--schema pair
ok - capability schema: well-formed manifest validates
ok - capability schema: entry missing required 'id' fails
ok - capability schema: schema_version as string fails type check
ok - capability schema: unrecognized 'kind' value fails enum check
ok - capability schema: missing top-level 'schema_version' fails
ok - validate-capability subcommand runs against an explicit --capability/--schema pair
ok - generate-capability output validates against capability.schema.json
ok - generate-capability correctly reports staged=true for present skills/ledger components
ok - generate-capability correctly reports staged=false for absent capabilities
ok - generate-capability emits exactly 7 catalog entries with unique ids
ok - generate-capability's task_id values match BACKLOG.md's task table
ok - generate-capability: install-core has no single staged_path, is ledger_tracked
ok - generate-capability is idempotent on an unchanged target (identical besides timestamp)
ok - generate-capability against a totally empty target reports all capabilities unstaged
ok - generate-capability --out writes to a custom path
ok - validate fails closed when the schema file is missing
ok - validate fails closed on malformed JSON instance
---
28 passed, 0 failed
```

**28/28 assertions passing, 0 failures.** Not run: the full `bench/tests/` suite (per the task's
explicit instruction — sibling agents are editing shared files concurrently right now, so a
full-suite run could show spurious unrelated failures).

## Manual verification (real scratch repo, real `install.sh`, real schema validation)

Per the safety constraint, every command below is a **single self-contained absolute-path shell
invocation** — no `cd` or exported variable was relied on to survive across separate tool calls.

1. **Created a fresh scratch git repo:** `/tmp/task-011-manual-01` (`git init` + an empty initial
   commit).
2. **Ran the real, unmodified installer** against it:
   `/Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/scripts/install.sh --yes --target /tmp/task-011-manual-01`
   → exit 0. This is the actual TASK-010 script, not a stub — it staged real templates, a real
   `.knowledge/` bundle, composed all 5 of its real sub-installers, and wrote a real
   `.gsd-recipe/config.json`.
3. **Inspected the real resulting `config.json`:**
   ```json
   {
     "traceability": { "enabled": true, "reason": "" },
     "observer": { "enabled": false, "interval_minutes": 10 },
     "tracker": "jira"
   }
   ```
4. **Validated that real file against the new schema for real:**
   `bench/lib/capability-schema.sh validate-config --config /tmp/task-011-manual-01/.gsd-recipe/config.json --schema /Users/vs72964/Projects/gsd-benchmark/.gsd-recipe/config.schema.json`
   → `OK`, exit 0.
5. **Negative-case proof against the same real file:** copied it, mutated `observer.enabled` to
   `true` and deleted `interval_minutes` (a realistic operator typo), re-validated →
   `ERROR: $.observer: missing required property 'interval_minutes'`, exit 1 — confirming the
   schema genuinely rejects a real, not-fixture-only invalid config, then restored the original file
   from the backup copy.
6. **Generated + validated a real `capability.json`** for the same scratch install:
   `bench/lib/capability-schema.sh generate-capability --target /tmp/task-011-manual-01` → wrote
   `.gsd-recipe/capability.json` reporting **6 of 7** capabilities staged (`recipe-prd-intake` is the
   one genuinely absent — correct, since `install.sh` never composes it). Re-validated that output
   against `capability.schema.json` → `OK`, exit 0.
7. **Exercised the rest of `install.sh`'s own flow** against the same scratch repo for completeness:
   `--record-jira-check pass` then `--verify` → both real invocations, `--verify` printed
   `config.json — parses and has required traceability/observer fields — pass` (its own
   independent hand-rolled check, now corroborated by the new schema) and wrote a real
   `INSTALL-VERIFIED.json`.
8. **Cleaned up:** `rm -rf /tmp/task-011-manual-01` (and its install log). Confirmed via
   `git status --porcelain` on the real repo (below) that nothing leaked outside the scratch
   directory.

### A real finding surfaced by this task's own manual verification

Running `bench/lib/capability-schema.sh validate-config` (no flags, i.e. against *this real repo's
own* `.gsd-recipe/config.json`) fails:

```
$ bench/lib/capability-schema.sh validate-config
ERROR: $: missing required property 'traceability'
ERROR: $: missing required property 'observer'
```

This is **not a schema bug** — it's the schema correctly detecting that this repo's own
self-hosted `.gsd-recipe/config.json` (`{"tracker": "jira"}` only) predates a full `install.sh` run:
prior tasks only ever ran `install-tracker-sync.sh` standalone here (which writes `tracker` only),
never the full umbrella `install.sh` (which is what adds `traceability`/`observer`). Confirmed real
and expected by the successful full-`install.sh` scratch-repo run in step 2–4 above, which produces
a config that *does* validate cleanly. This task deliberately did **not** hand-edit this repo's
`config.json` to force it to pass — doing so would be data massaging a file it doesn't own
(TASK-010's artifact), not a genuine fix, and `.gsd-recipe/scripts/install.sh` itself is off-limits
per the shared-file-avoidance constraint. `.gsd-recipe/capability.json` (this task's own new
artifact) *does* validate cleanly against `capability.schema.json` — confirmed separately.

### Real repo git status after all work (scratch-only side effects, nothing leaked)

```
$ git status --porcelain
```

See the "Deliverable" section of the final response for the full, current output. All of this
task's new files are additions under `.gsd-recipe/`, `bench/lib/`, `bench/tests/`, and
`bench/report/`, plus two non-forbidden doc edits (`DATA-CONTRACTS.md`, `INSTALL-LLD.md`). None of
the 4 forbidden files (`install.sh`, `test-install.sh`, `BACKLOG.md`, `README.md`) show as modified
by this task — confirmed both via `git status --porcelain` (all four show `??`, i.e. untracked from
before this session started, not `M`) and via `md5` checksums taken before vs. after this task's
work.

## Explicitly deferred / not built (do not mistake for oversights)

| Deferred | Why |
|---|---|
| Wiring `generate-capability`/`validate-config` into `install.sh`'s own flow | `install.sh` is one of the 4 forbidden shared files for this task's run — see the exact copy-paste snippet below for a follow-up pass. |
| A `capability.json`/`config.json` check inside `install.sh --verify`'s checklist | Same reason — `install.sh` is off-limits. The checklist item's exact text is included in the snippet below. |
| Real per-component semantic versioning for `capability.json`'s `version` field | No versioning mechanism (VERSION file, git tags per skill) exists anywhere in this recipe yet — inventing one was out of this task's scope (`capability.json`'s *shape*, not a new versioning system). Documented as a placeholder in both the schema and this report. |
| `gsd capability list --json` / `/gsd-surface status` cross-check (`INSTALL-LLD.md` Step 5 item 3) | Native GSD command, Cursor-slash-command-mediated, not shell-invokable — same category of deferral every prior `install.sh`-adjacent task has already documented for checks 1–3/8–10 of that checklist. `capability.json`'s shape is designed to be a plausible *future* input to such a check (hence documenting `kind`/`invoke_name`/`staged` per entry), but actually wiring a native GSD command to read it is out of scope here. |
| Full `bench/tests/` suite run | Explicitly instructed not to, since 4 sibling tasks are editing shared files concurrently right now. |
| Adding sibling tasks' newly-created capabilities (`recipe-bootstrap-knowledge` TASK-022, `recipe-install-verify` TASK-023) to the static catalog | `.gsd-recipe/ledger.json` gained both components' entries *while this task was in progress* (confirmed via a real repo `Read` mid-task, timestamped after this task's own `capability.json` generation) — genuine evidence of the parallel-sibling execution this task was told to expect. Chasing a moving target mid-flight would risk describing a shape those sibling tasks haven't finalized yet; the 7-entry catalog here reflects `BACKLOG.md`'s task table as it stood when this task started. Extending the catalog to include newly-landed sibling capabilities is a natural, low-risk follow-up once all 4 siblings have merged. |

## Files

- `.gsd-recipe/config.schema.json` (new)
- `.gsd-recipe/capability.schema.json` (new)
- `.gsd-recipe/capability.json` (new — self-install side effect, real repo, generated for real)
- `bench/lib/capability-schema.sh` (new)
- `bench/tests/test-capability-schema.sh` (new, 28 assertions)
- `bench/tests/fixtures/gsd-recipe-config-valid.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-valid-minimal.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-valid-extra-keys.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-missing-observer.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-wrong-type.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-invalid-tracker.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-observer-enabled-no-interval.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-traceability-disabled-no-reason.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-traceability-disabled-with-reason.json` (new)
- `bench/tests/fixtures/gsd-recipe-config-not-an-object.json` (new)
- `bench/tests/fixtures/capability-valid.json` (new)
- `bench/tests/fixtures/capability-missing-field.json` (new)
- `bench/tests/fixtures/capability-wrong-type.json` (new)
- `bench/tests/fixtures/capability-invalid-kind-enum.json` (new)
- `bench/tests/fixtures/capability-missing-top-level.json` (new)
- `docs/netapp-recipe/contracts/DATA-CONTRACTS.md` (edited — new Contract Index rows + full `capability.json` normative section)
- `docs/netapp-recipe/lld/INSTALL-LLD.md` (edited — directory tree `[X] TASK-011` annotations + status note)

## Snippets for a follow-up integration pass

Not applied here — all 4 target files are off-limits for this task's run. Copy-paste-ready for
whoever runs the next integration pass.

### `install.sh`

Add near the top-of-file header comment, replacing the "deferred to TASK-011" line (currently line
~17):

```bash
#   - `capability.json` / `config.schema.json`: built in TASK-011
#     (bench/lib/capability-schema.sh). install.sh itself does not yet call
#     generate-capability or validate-config — see
#     bench/report/capability-config-schema-integration-report.md's
#     "Snippets for a follow-up integration pass" for the exact call sites
#     below.
```

Add a call to `generate-capability` at the end of `install()`, right after `install_report_write`/
`ledger_record` for `install-report.json` (so the manifest reflects the fully-composed state,
after all 5 sub-installers have run) and before `print_mcp_snippet`:

```bash
  "$SCRIPT_DIR/../../bench/lib/capability-schema.sh" generate-capability --target "$TARGET" >/dev/null
  ledger_record ".gsd-recipe/capability.json"
```

Add a `config.json` schema-validation check inside `verify()`, immediately after the existing
hand-rolled `config.json` assert block (right before the `echo "[E] 8. MCP reachable..."` line), so
`--verify` also confirms strict schema compliance, not just the two hand-picked fields it already
checks:

```bash
  if REPO_ROOT="$SCRIPT_DIR/../.." "$SCRIPT_DIR/../../bench/lib/capability-schema.sh" validate-config --config "$CONFIG" --schema "$SCRIPT_DIR/../config.schema.json" >/dev/null 2>&1; then
    echo "[C] config.schema.json — strict schema validation — pass"
  else
    echo "[C] config.schema.json — strict schema validation — FAIL"
    ok=0
  fi
```

### `test-install.sh`

Add assertions (after the existing `config.json` merge/preservation checks) confirming the composed
flow's `capability.json` output — mirrors this task's own `test-capability-schema.sh` #18-19 style:

```bash
# N. Fresh install generates a capability.json that validates against the new schema
"$REPO_ROOT/bench/lib/capability-schema.sh" validate-capability --capability "$TARGET1/.gsd-recipe/capability.json" --schema "$REPO_ROOT/.gsd-recipe/capability.schema.json" >/dev/null 2>&1
check "install.sh generates a capability.json that validates against capability.schema.json" "$?"

# N+1. install-core reports staged=true once install.sh has fully composed
python3 -c "
import json
d = json.load(open('$TARGET1/.gsd-recipe/capability.json'))
by_id = {c['id']: c for c in d['capabilities']}
assert by_id['install-core']['staged'] is True
"
check "install.sh's own capability.json reports install-core as staged" "$?"
```

### `BACKLOG.md`

Replace the current TASK-011 row (line ~74):

```markdown
| TASK-011 | `capability.json` + config schema | S | 010 | [INSTALL-LLD](lld/INSTALL-LLD.md) — **Built**: `.gsd-recipe/config.schema.json` (validates the real `install.sh`-written `config.json` shape: `tracker`/`traceability`/`observer`) and a new `.gsd-recipe/capability.json` + `.gsd-recipe/capability.schema.json` (static per-repo capability manifest, generated by introspecting `.cursor/skills/`/`skills/`/`ledger.json`), plus `bench/lib/capability-schema.sh` (hand-rolled draft-07-subset validator + `generate-capability`). Not yet wired into `install.sh`'s own flow — see [capability-config-schema-integration-report.md](../../bench/report/capability-config-schema-integration-report.md)'s follow-up snippets. |
```

### `README.md`

Add a row to the "Built vs spec" table (exact section header/format may differ slightly by the time
this is applied — insert alongside the other TASK-0xx "Built" rows):

```markdown
| `capability.json` / `config.schema.json` (TASK-011) | Built | `.gsd-recipe/config.schema.json`, `.gsd-recipe/capability.json`, `.gsd-recipe/capability.schema.json`, `bench/lib/capability-schema.sh` (`validate-config`/`validate-capability`/`generate-capability`). Not yet called from `install.sh` itself. |
```
