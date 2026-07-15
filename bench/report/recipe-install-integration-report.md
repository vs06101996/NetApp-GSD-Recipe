# `recipe-install` skill (TASK-031)

Built per direct task assignment — the **last remaining unbuilt named `recipe-*` skill** in
`docs/netapp-recipe/README.md`'s Built-vs-spec table and `docs/netapp-recipe/BACKLOG.md`'s Wave 1b
table. Once this task landed, every named `recipe-*` skill in the spec is Built; only `recipe-observe`
(p2, explicitly post-pilot per `docs/netapp-recipe/lld/OBSERVER-LLD.md`) remains genuinely unbuilt
among named `recipe-*` items.

`recipe-install` is a thin, invoke-by-name **orchestrator** chaining three already-separately-built
and already-separately-invokable pieces into one end-to-end command — it reimplements none of
their logic, per the locked scope:

- **Step A** — `recipe-validate-tokens` (TASK-021), by name, informational, never blocks.
- **Step B** — a genuine, live, non-skippable human consent gate asked directly in the operator's
  own conversation, previewing what will be staged.
- **Step C** — `.gsd-recipe/scripts/install.sh --yes --target <repo>` (TASK-010), by real `Shell`
  call — `INSTALL-LLD.md` Steps 2-4, already composing every sub-installer this repo has built.
- **Step D** — `recipe-install-verify` (TASK-023), by name — `INSTALL-LLD.md` Step 5's checklist.
- **Step E** — one combined summary of all four sub-results, never fabricated.
- `--uninstall` delegates directly to `install.sh --uninstall --yes --target <repo>`, behind its own
  equally-explicit live-conversation confirm gate.

## Locked design decisions (implemented exactly, not re-derived)

1. **Thin orchestrator, zero reimplementation.** Every actual unit of work — token validation,
   directory scaffolding, sub-installer composition, verification — is owned by one of the three
   invoked pieces. This skill adds exactly one net-new thing: a genuine, live human consent gate
   sitting above all three (Step B / the uninstall gate), plus the glue that invokes each in order
   and combines their reports.
2. **Step A never blocks.** `recipe-validate-tokens`'s own `PASS`/`WARN`/`FAIL` per credential is
   relayed informationally; Step B always follows regardless of Step A's outcome, matching
   `recipe-validate-tokens`'s own documented "never aborts a workflow" contract.
3. **Step B is a genuine, live, non-skippable human gate — distinct from `install.sh`'s own
   `--yes`.** See the dedicated section below for the full architectural reasoning.
4. **Step C passes `--yes` unconditionally, but never `--record-jira-check`.** `--yes` here only
   ever skips `install.sh`'s own *nested* scaffolding-consent prompt (already superseded by Step
   B's higher-level question) — it does not, and cannot, retroactively skip Step B, which already
   happened by the time Step C runs. `--record-jira-check` is an unrelated, explicitly out-of-scope
   feature this skill never touches.
5. **Step D delegates the entire Step-5 checklist to `recipe-install-verify`**, relaying its
   pass/warn/fail table and `install_verified` marker verbatim — never re-derived.
6. **Step E never fabricates.** Every one of the four sub-results (Step A's credential lines, Step
   B's accept/decline, Step C's real `install.sh` stdout, Step D's real checklist table) is relayed
   exactly as the invoked skill/script reported it.
7. **`--uninstall` delegates directly to `install.sh --uninstall --yes`**, behind its own gate
   mirroring Step B's reasoning — removing every staged skill is at least as consequential as
   installing them.
8. **Installer never touches `install.sh` itself.** Unlike the skill's own *runtime* instructions
   (which invoke `install.sh` via `Shell`), `install-recipe-install.sh` (the installer that stages
   the skill file) stages exactly one file and never copies, modifies, or removes
   `.gsd-recipe/scripts/install.sh` — the two are cleanly separated: one script installs the
   orchestrator skill, a different script (invoked only when that skill is later run
   conversationally) is the thing it orchestrates.

## Why Step B is a genuine human gate, distinct from `install.sh`'s own `--yes`

`install.sh`'s own header comment states its policy plainly: "Sub-installers are invoked with
`--yes` too — the umbrella prompt already covers consent, a second nested prompt would just be
noise." That policy is correct for `install.sh`'s relationship to the 16 sub-installers it composes
— one umbrella prompt covering 16 mechanically-identical "stage this one skill file" operations
really would make 16 nested prompts pure noise.

`recipe-install`'s Step B is a **different, higher-level gate**, not a violation of or a redundant
re-ask of that policy:

- It sits **above** `install.sh`'s own umbrella prompt entirely — Step B happens in the live
  conversation between the operator and this skill, before `install.sh` (and its own
  `--yes`-skipped prompt) is ever invoked at all.
- `recipe-install` is, per the task's own framing, **the one place in the whole recipe that
  actually writes new scaffolding into a possibly-unfamiliar target repo for the first time.** Every
  other `recipe-*` skill either has its own narrow, single-purpose installer with its own single
  low-stakes consent prompt (`recipe-sync`, `recipe-settle`, etc.), or does no installing at all
  (`recipe-run-phase`, `recipe-plan-phase`, etc. — pure runtime orchestration over an
  already-installed recipe). `recipe-install` is unique in being the umbrella, first-time,
  whole-tree install path, wrapped in a conversational skill an operator might invoke against a
  repo they've never run this recipe against before — possibly without having read
  `INSTALL-LLD.md`'s own directory-tree preview first.
- A single, explicit, human-readable preview-then-confirm exchange in the operator's own
  conversation is the appropriate level of ceremony for that specific moment — mirroring exactly the
  rigor `recipe-settle-SKILL.md`'s own PO-accept gate applies to *its* "one consequential,
  non-mechanical decision point" moment. Just as `recipe-settle`'s report explicitly distinguishes
  its PO-accept gate from `install.sh --yes` ("deliberately stricter than `install.sh`'s own
  `--yes` convention... Accepting a feature as done is neither mechanical nor reversible in the same
  way"), Step B is deliberately a stricter, higher-ceremony gate than a flag an operator might pass
  without fully registering what it authorizes.
- Passing `--yes` to `install.sh` in Step C does not defeat or duplicate Step B — it simply prevents
  `install.sh` from asking its own, lower-level, "stage these 16 mechanically composed files?"
  question a second time, moments after the operator already answered the higher-level "should this
  whole install run at all?" question in Step B. Skipping that second, narrower question is exactly
  what avoids becoming the "second nested prompt [that] would just be noise" `install.sh`'s own
  header comment warns against — **Step B is the one prompt that matters here; a second one asking
  essentially the same thing moments later would be the noise, not Step B itself.**

The same reasoning applies to the `--uninstall` gate: removing every staged skill file is at least
as consequential as installing them, so it gets the same live, explicit, non-skippable treatment —
sitting one level above `install.sh --uninstall`'s own silent cascade to 16 sub-installers'
`--uninstall` modes, exactly as Step B sits above `install()`'s own silent composition.

Neither gate is implemented as a bash `read -p` prompt, a script argument, or any other
non-conversational mechanism — same "only a live agent turn can reach the real human operator"
architectural principle `recipe-settle-SKILL.md`'s own "Why this is a genuine human gate, not
skippable" section documents: a bash process spawned by a tool call has no real human typing at its
stdin, so a `read -p` there would only ever be answered by the invoking agent itself, silently
defeating the entire point of a human gate.

## Ownership table — which piece owns which `INSTALL-LLD.md` step

| `INSTALL-LLD.md` step | Owned by | This skill's role |
|---|---|---|
| Step −1 (Source) | Operator, before invoking this skill at all | Not touched — assumes `<target>` already exists as a git working copy |
| Step 0-1 (Token validation) | `recipe-validate-tokens` (TASK-021) | Step A invokes it by name, relays its report verbatim, never blocks on it |
| Step 2 (Capability install / fallback installer) | `install.sh` itself (TASK-010) | Step C runs it directly via `Shell` |
| Step 3 (FLY ON THE WALL install) | `install.sh` itself, via its composed `install-observer.sh` sub-installer | Step C runs it directly via `Shell` (composed inside `install.sh`, not invoked separately) |
| Step 4 (Tracker-sync registration) | `install.sh` itself, via its composed `install-tracker-sync.sh` sub-installer | Step C runs it directly via `Shell` (composed inside `install.sh`, not invoked separately) |
| Step 5 (Verification checklist) | `recipe-install-verify` (TASK-023) | Step D invokes it by name, relays its report verbatim |
| The live "may I write to your repo?" gate | This skill, uniquely (Step B / the uninstall gate) | Never delegated — the one net-new thing this skill adds |

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| `install.sh --record-jira-check` | Unrelated feature per the locked design decision — a separate, narrower install-time record `install.sh` itself owns; `recipe-validate-tokens`'s Jira/Atlassian check (Step A) is a different, standalone, re-invokable check with no relationship to that flag. |
| Reimplementing any check `recipe-validate-tokens`, `install.sh`, or `recipe-install-verify` already own | This skill's entire job is invoking each of the three in order with exactly one gate (Step B) in between Step A and Step C, and combining their real reports. |
| Any flag/env var/non-interactive mode that skips or auto-answers Step B or the uninstall gate | Both are genuine, live, conversational human gates — see "Why Step B is a genuine human gate" above. |
| Implementing Step B or the uninstall gate as a bash `read -p` prompt | A spawned bash process has no real human at its stdin — same principle `recipe-settle-SKILL.md` documents. |
| Touching `install.sh` itself from the installer (`install-recipe-install.sh`) | The installer stages exactly one file (the skill); `install.sh` is a sibling script the *staged skill's runtime instructions* invoke via `Shell`, never something the installer copies/modifies/removes. |
| MCP fragment / `agent_skills` injection print-only snippets | Already owned by `install.sh` itself (`print_mcp_snippet`/`print_agent_skills_snippet`); this skill's Step C relays whatever `install.sh` prints, never re-prints or re-derives those snippets separately. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-install-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block implementing Steps A-E plus the `--uninstall` delegation, with a dedicated "Why Step B is a genuine human gate, distinct from `install.sh`'s own `--yes`" section, a "Why the uninstall gate mirrors Step B's reasoning" section, and an ownership table mapping every `INSTALL-LLD.md` step to the piece that owns it. |
| Installer | `.gsd-recipe/scripts/install-recipe-install.sh` | Standalone installer mirroring `install-recipe-sync.sh`'s structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard), staging to `.cursor/skills/recipe-install/SKILL.md`. Ledger component `"recipe-install"`. Never touches `.gsd-recipe/config.json`, `.planning/config.json`, `.gsd-recipe/ledger.json` beyond its own component's row, or — uniquely for this installer — `.gsd-recipe/scripts/install.sh` itself. |
| Tests | `bench/tests/test-install-recipe-install.sh` (36 assertions) | Fail-closed non-git target, fresh install staging, exactly-1 ledger row, never touching config/install.sh, 20 staged-content assertions covering every documented workflow step/gate/scope-boundary above, idempotent re-install, uninstall + ledger-clear + directory cleanup, self-install collision safety (including a byte-for-byte "install.sh unchanged" assertion), self-uninstall canonical-source preservation (including "install.sh never removed"). |
| Composed into `install.sh` | 16th sub-installer, appended after the existing 15 (`observer`, `tracker-sync`, `recipe-planning-policy`, `recipe-run-phase`, `recipe-plan-phase`, `recipe-validate-tokens`, `recipe-bootstrap-knowledge`, `recipe-install-verify`, `recipe-run-phases`, `recipe-verify-feature`, `recipe-review-ship`, `recipe-settle`, `gsd-jira-sync`, `recipe-sync`, `recipe-pr-comment`) — path var, `install()`/`uninstall()`/`verify()` wiring, consent-prompt string, "composing sub-installers..." echo line, header comment. | |
| Capability catalog | `bench/lib/capability-schema.sh` — 18th `CATALOG` entry (`id: "recipe-install"`, `task_id: "TASK-031"`). | |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-031 row, `Depends: 021, 010, 023`) and `docs/netapp-recipe/README.md` (Built-vs-spec dedicated row; `recipe-install` removed from the "All other `recipe-*` wrappers" row's parenthetical, leaving just `recipe-observe`; Commands→Built row; dedicated Spec-table row removed; shipped-percentage header recomputed `~94%` → `~97%`). | |

## Shipped-percentage recomputation

The prior `~94%` figure resolves to 29 Built / 31 (Built + Spec) rows in the Built-vs-spec table
(the `dag-build.sh` **Parked** row is excluded from the denominator, same as every prior addition's
recomputation) = 93.5%, rounded to 94%. `recipe-install` moving from Spec to Built makes it
30 Built / 31 = 96.8%, rounded to **97%**.

## Validation performed

### Automated

`bench/tests/test-install-recipe-install.sh`: **36 assertions, 0 failed**, run standalone:

```
$ ./bench/tests/test-install-recipe-install.sh
...
36 passed, 0 failed
```

Full `bench/tests/*.sh` suite (30 files, run after this task's composition edits landed):
**all 30 files exit 0, zero regressions** (2,204+ total assertions across the suite; `test-install.sh`
alone grew from its pre-existing count to **123 passed, 0 failed** with this task's 4 new
composition/staging/verify/uninstall assertions added).

Every shell file touched or created was syntax-checked with `bash -n`:
`.gsd-recipe/scripts/install-recipe-install.sh`, `.gsd-recipe/scripts/install.sh`,
`bench/tests/test-install-recipe-install.sh`, `bench/tests/test-install.sh`,
`bench/lib/capability-schema.sh`, `bench/tests/test-capability-schema.sh` — all clean.

### Self-install into the real repo

```bash
./.gsd-recipe/scripts/install-recipe-install.sh --yes --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh generate-capability --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh validate-capability \
  --capability .gsd-recipe/capability.json --schema .gsd-recipe/capability.schema.json
```

Staged `.cursor/skills/recipe-install/SKILL.md`, recorded exactly 1 ledger row, regenerated
`.gsd-recipe/capability.json` (**18 capabilities, 15 staged**, `recipe-install` reporting
`staged: true`), and it validates cleanly (`OK`) against `capability.schema.json`.

`git status --porcelain` after the self-install/regeneration confirms only the expected paths
changed: this task's new files (`recipe-install-SKILL.md`, `install-recipe-install.sh`,
`test-install-recipe-install.sh`, this report), this task's edits to the five shared composition
files (`install.sh`, `test-install.sh`, `capability-schema.sh`, `test-capability-schema.sh`,
`BACKLOG.md`, `README.md`), and the self-install's own side effects
(`.cursor/skills/recipe-install/SKILL.md`, `.gsd-recipe/ledger.json`,
`.gsd-recipe/capability.json`) — no other files were touched. (This entire repo tree is untracked
pre-existing WIP as of this task's start — `git ls-files` confirms `.gsd-recipe/scripts/install.sh`
itself was never committed — so every one of these paths shows as `??`, not `M`; the scoping check
is "did only the intended set of paths change", which it did.)

### What was NOT invoked conversationally (by design)

Per this task's explicit instruction, `recipe-install` itself was **not** invoked conversationally
against the real repo — doing so would re-run the real `install.sh` end-to-end and ask a live
human-gate question (Step B) that cannot be meaningfully answered by a non-interactive script. The
skill's *content* was instead validated by careful reading/review (this report, plus the 20
staged-content `grep` assertions in the test file asserting every documented workflow step, gate,
and scope boundary is actually present in the shipped `SKILL.md`) — the installer that stages it
(the only genuinely scriptable half of this task) was exercised for real, repeatedly, against
disposable scratch repos and this real repo's own self-install.

## Files

- `.gsd-recipe/templates/recipe-install-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-install.sh` (new)
- `bench/tests/test-install-recipe-install.sh` (new, 36 assertions)
- `bench/report/recipe-install-integration-report.md` (new, this file)
- `.cursor/skills/recipe-install/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` / `.gsd-recipe/capability.json` (self-install side effects, real repo — additive only)

**Modified (composed directly — no concurrent siblings running this session):**
`.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`.

## Deviations / judgment calls

None in scope or design — all locked decisions were implemented exactly as specified. Two judgment
calls worth flagging explicitly:

1. **The uninstall gate's exact wording is this skill's own composition, not lifted verbatim from
   any prior skill.** No existing `recipe-*` skill has a comparable "uninstall this much scaffolding"
   moment (`recipe-sync`'s/`recipe-settle`'s own installers each stage/remove exactly one skill
   file, a much lower-stakes operation) — the uninstall gate's wording was written to mirror Step
   B's own rigor and cite the same "consequential, non-mechanical decision point" framing
   `recipe-settle-SKILL.md` established, applied to a removal instead of an addition.
2. **Shipped-percentage recomputation method.** Reverse-engineered from the prior `~94%` figure by
   testing which built-vs-spec-row ratio reproduces it (29/31 = 93.5% ≈ 94%, excluding the `Parked`
   `dag-build.sh` row from the denominator, consistent with every prior task's own recomputation
   never needing to touch that row) rather than assuming a documented formula existed — the
   resulting `~97%` (30/31) follows the same method.
