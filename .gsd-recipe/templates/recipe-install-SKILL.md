---
name: recipe-install
description: "Recipe: thin, invoke-by-name end-to-end install orchestrator for the NetApp GSD recipe (TASK-031), the last remaining unbuilt named recipe-* skill. Chains three already-separately-invokable pieces into one command: Step A invokes recipe-validate-tokens by name (informational, never blocks); Step B asks a genuine, non-skippable, live human consent question in the operator's own conversation previewing what will be staged (distinct from install.sh's own --yes-skippable prompt, since this is the one place in the recipe that writes new scaffolding into a possibly-unfamiliar target repo for the first time); Step C runs .gsd-recipe/scripts/install.sh --yes --target <repo> directly (INSTALL-LLD.md Steps 2-4, already composing every sub-installer this repo has built); Step D invokes recipe-install-verify by name (Step 5's checklist); Step E reports one combined summary, never fabricating any sub-result. --uninstall delegates to install.sh --uninstall --yes --target <repo>, behind its own equally-explicit live-conversation confirm gate. Never calls install.sh --record-jira-check, and never re-implements any check recipe-validate-tokens/install.sh --verify/recipe-install-verify already own."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-install`) with:
- `--target <path>` — optional. The repo root to install into. Default: the current repo root
  (same convention as every `install-recipe-*.sh` installer and `recipe-install-verify`'s own
  `--target` argument).
- `--uninstall` — optional. Switches this skill from "run the full install flow" to "delegate to
  `install.sh --uninstall`" (see § C step "Uninstall mode" below). Mutually exclusive with running
  Steps A-E; when passed, none of Steps A/C/D run at all.

Examples:
- `recipe-install` — full end-to-end install into the current repo root.
- `recipe-install --target /path/to/other-repo` — full end-to-end install into a different repo.
- `recipe-install --uninstall` — delegate to `install.sh --uninstall` for the current repo root.
- `recipe-install --uninstall --target /path/to/other-repo`

## B. Prerequisites

- None strictly required before invocation — `install.sh` itself already handles its own
  prerequisite bootstrap (`preflight()`/`ensure_prereq()` for `python3`/`git`/`node`/`gh`/
  `gsd_core`/`graphify`), and `recipe-validate-tokens`/`recipe-install-verify` are each
  self-contained, standalone-invokable skills with no prerequisites of their own.
- `<target>` must be a git repo root (`install.sh` itself fails closed on this — this skill does
  not duplicate that check, it surfaces whatever `install.sh` reports).
- `recipe-validate-tokens` and `recipe-install-verify` may or may not already be staged at
  `.cursor/skills/recipe-validate-tokens/SKILL.md` / `.cursor/skills/recipe-install-verify/SKILL.md`
  in `<target>` before this skill runs. Both scenarios are fine: `install.sh` (Step C) stages both
  of them itself as part of its own composed sub-installer list if they aren't already present, so
  Step D's invocation of `recipe-install-verify` will find it staged regardless of whether it was
  there before this skill started.

## C. Tool Usage

Run steps A-E below, in order, **unless `--uninstall` was passed** — in that case, skip straight to
"Uninstall mode" at the end of this section and do not run Steps A-E at all.

1. **Step A — `recipe-validate-tokens`, by name, informational only (never blocks).** Invoke the
   `recipe-validate-tokens` skill directly, in this same turn (skill-to-skill, same shape as
   `recipe-install-verify`'s own item-4 delegation). Read and follow its own documented workflow
   exactly as it documents for itself — do not re-derive or shortcut its GitHub/Jira checks here.
   Capture its `PASS`/`WARN`/`FAIL` line per credential for the combined summary in Step E.
   - This is a **layered, additional** check on top of `install.sh`'s own internal `preflight()`
     (which is separately hard-fail-closed for `python3`/`git`, warn-only for `node`/`gh`/
     `gsd_core`/`graphify`) — not a duplicate of it, and not a gate for anything that follows.
     Whatever `recipe-validate-tokens` reports, **continue to Step B regardless** — a `FAIL` on
     either credential here does not stop this skill; it is surfaced informationally in the
     combined summary so the operator knows about it going in, exactly as
     `recipe-validate-tokens`'s own § D already documents ("this skill only reports... never
     aborts a workflow").

2. **Step B — genuine, live, non-skippable human consent gate, asked directly in this
   conversation.** Before touching anything on disk, tell the operator plainly what is about to
   happen and ask them to confirm. Preview, concretely:
   - The resolved `<target>` path (absolute).
   - That `install.sh --yes --target <target>` is about to run, which will scaffold `.templates/`,
     `.knowledge/`, `code_base_details/README.md`, `.gitignore` entries, `.gsd-recipe/config.json`
     defaults, and stage all 16 composed sub-installers' skill files (observer, tracker-sync, and
     every `recipe-*`/`gsd-jira-sync` skill this repo has built) into `<target>` — the same
     directory-tree preview `INSTALL-LLD.md`'s own "Directory tree (created or updated)" section
     documents.
   - That this is the first time this recipe would be writing scaffolding into `<target>` (or, if
     some of it already exists, that `install.sh` is idempotent and will leave existing
     operator-customized files untouched — same "never overwrite operator data" guarantee
     `install.sh`'s own header comment documents).
   - Ask something equivalent to: "Ready to install the NetApp GSD recipe into `<target>`? [y/n]" —
     then **stop and wait for the operator's actual next message.** Never answer on their behalf,
     never assume "yes" because `recipe-validate-tokens` reported all-`PASS`, never proceed without
     an explicit affirmative reply appearing in the conversation. See "Why Step B is a genuine human
     gate, distinct from `install.sh`'s own `--yes`" below for the full rationale.
   - **Affirmative (y/yes)** → continue to Step C.
   - **Negative (n/no) or the operator otherwise declines** → stop here entirely. Report "operator
     declined — install not run" in the final summary. Do not run Step C or Step D.

3. **Step C — run `install.sh` directly (real script call, INSTALL-LLD.md Steps 2-4).** `Shell`:
   run `<target>/.gsd-recipe/scripts/install.sh --yes --target <target>` (absolute paths; the
   canonical source is `.gsd-recipe/scripts/install.sh` in this recipe's own source tree if `<target>`
   hasn't had this recipe installed into it before — same bundled-source precedence every other
   skill in this recipe follows). This is the same category of direct shell call `recipe-sync`'s own
   step 1 makes to `sync-reconcile.sh`, and `recipe-install-verify`'s own step 1 makes to
   `install.sh --verify` — a real, scriptable, testable script invocation, never
   Option-B/native-GSD-call territory (there is no native GSD command being wrapped here at all).
   - Pass `--yes` unconditionally — Step B is this skill's own, stricter, higher-level human gate;
     passing `--yes` here does **not** skip Step B (which already happened), it only skips
     `install.sh`'s own *nested* scaffolding-consent prompt, which would otherwise ask essentially
     the same question a second time. See "Why `--yes` here doesn't re-introduce the nested-prompt
     noise `install.sh`'s own header comment warns about" below.
   - **Never** pass `--record-jira-check` — out of scope for this skill per the locked design
     (unrelated feature; the Jira/Atlassian check this skill's own Step A already surfaces is a
     different, standalone, re-invokable check, not `install.sh`'s own `jira_check: pending`
     record-and-unblock mechanism).
   - Capture `install.sh`'s own real stdout — specifically, the "staged" file count, which
     sub-installers it composed, and (if `gh`/prerequisite issues surfaced) its warn-only prereq
     lines — for the combined summary in Step E. Never fabricate or infer any of this; relay
     exactly what the script actually printed.
   - If `install.sh` itself exits non-zero (e.g. `<target>` turned out not to be a git repo, or a
     hard prerequisite like `python3`/`git` is genuinely missing with no fallback), **stop here**:
     report the script's own failure output verbatim in the final summary, and do not run Step D
     (there is nothing meaningful to verify if the install itself never completed).

4. **Step D — `recipe-install-verify`, by name (Step 5's checklist).** Invoke the
   `recipe-install-verify` skill directly, in this same turn (skill-to-skill), passing through
   `--target <target>` if it differs from the current repo root. Follow its own documented
   10-item-checklist workflow exactly as it documents for itself — do not re-derive or shortcut any
   of its items. Capture its final pass/warn/fail table and its `install_verified: true|false`
   closing line for the combined summary in Step E.

5. **Step E — one combined summary, never fabricated.** Report, in one block to the operator:
   - Step A: `recipe-validate-tokens`'s own reported `PASS`/`WARN`/`FAIL` line per credential
     (GitHub, Jira/Atlassian), relayed verbatim.
   - Step B: `accepted` or `declined` (and, if declined, that Steps C/D never ran).
   - Step C: `install.sh`'s own reported staged/skipped file counts and which sub-installers it
     composed, relayed verbatim from its real stdout (or its failure output, if it exited non-zero).
   - Step D: `recipe-install-verify`'s own reported pass/warn/fail table per checklist item, and its
     `install_verified: true|false` closing line, relayed verbatim.
   Every one of these four sub-results must be the real thing each invoked step/script actually
   reported — never invent, round up, or assume a result for any of them, even when a prior step's
   outcome makes a particular result "likely."

### Uninstall mode (`--uninstall`)

When `--uninstall` is passed, skip Steps A/C/D above entirely and do this instead:

1. **Live, non-skippable human consent gate — same rigor as Step B, arguably more so.** Tell the
   operator plainly that `install.sh --uninstall --yes --target <target>` is about to run, which
   will cascade `--uninstall` to every composed sub-installer (removing every staged `recipe-*`/
   `gsd-jira-sync`/observer/tracker-sync skill file from `<target>`, per `install.sh`'s own
   `uninstall()` — see its own closing line: "`code_base_details/`, `.knowledge/`, `config.json`, and
   `.gitignore` are left in place"). Ask something equivalent to: "Ready to uninstall the NetApp GSD
   recipe from `<target>`? This removes every staged skill file (observer, tracker-sync, every
   `recipe-*`/`gsd-jira-sync` skill) but preserves `.knowledge/`, `code_base_details/`, `config.json`,
   and `.gitignore`. [y/n]" — then **stop and wait for the operator's actual next message**, same
   rules as Step B (never fabricated, never auto-answered, never skippable via any flag). See "Why
   the uninstall gate mirrors Step B's reasoning" below.
   - Affirmative → continue to step 2.
   - Negative/declines → stop here. Report "operator declined — uninstall not run" in the final
     summary.
2. **Delegate to `install.sh --uninstall` directly (real script call).** `Shell`: run
   `<target>/.gsd-recipe/scripts/install.sh --uninstall --yes --target <target>`. Never re-implement
   any of `install.sh`'s own uninstall cascade here — it already knows how to walk every ledgered
   component and cascade to every composed sub-installer's own `--uninstall`.
3. **Report.** Relay `install.sh --uninstall`'s own real stdout (which files/components it removed,
   which it preserved) verbatim as the final summary. Never fabricate a "removed" result for
   anything the script didn't actually report removing.

## D. Do NOT

- Do not skip Step B (the live consent gate) under any circumstance, including when
  `recipe-validate-tokens` reported all-`PASS` in Step A — a clean token check is not a substitute
  for operator consent to write new scaffolding into their repo. There is no flag, environment
  variable, or non-interactive mode that answers Step B (or the uninstall gate) on the operator's
  behalf — passing `--yes` to `install.sh` itself in Step C only ever skips *that script's own*
  nested scaffolding-consent prompt, never this skill's own Step B, which has already happened by
  the time Step C runs.
- Do not implement Step B (or the uninstall gate) as a bash `read -p` prompt, a script argument, or
  any other non-conversational mechanism. Same "only a live agent turn can reach the real human
  operator" principle `recipe-settle-SKILL.md`'s own "Why this is a genuine human gate, not
  skippable" section documents for its PO-accept gate — a bash process spawned by a tool call has no
  real human typing at its stdin, so a `read -p` there would only ever be answered by the invoking
  agent itself, defeating the entire point.
- Do not call `install.sh --record-jira-check` — unrelated feature, explicitly out of scope for this
  skill per the locked design decision. `install.sh`'s own `jira_check: pending`/
  `--record-jira-check` mechanism is a separate, narrower install-time record this skill does not
  touch; `recipe-validate-tokens`'s own Jira/Atlassian check (Step A) is a different, standalone,
  re-invokable check with no relationship to that flag.
- Do not re-implement, shortcut, or second-guess any check `recipe-validate-tokens` (Step A),
  `install.sh` itself (Step C's own internal `preflight()`/template-scaffolding/sub-installer
  composition), or `recipe-install-verify` (Step D) already own. This skill's entire job is
  invoking each of the three in the right order with the right gate in between, and combining their
  real reports — never re-deriving any individual check's logic inline.
- Do not proceed to Step C when Step B was declined, and do not proceed to Step D when Step C never
  completed (either because Step B was declined, or because `install.sh` itself exited non-zero).
- Do not proceed to the delegated `install.sh --uninstall` call when the uninstall gate was
  declined.
- Do not fabricate any of the four sub-results in the Step E combined summary (or the single
  uninstall-mode result). Every reported outcome must be the real thing the invoked
  skill/script actually printed — a `FAIL` from `recipe-validate-tokens`, a non-zero exit from
  `install.sh`, or an `install_verified: false` from `recipe-install-verify` are all reported
  plainly, never rounded up to a cleaner-sounding result.
- Do not accept a `--target` that doesn't resolve to a git repo root as a reason to short-circuit or
  guess — that fail-closed check belongs to `install.sh` itself (Step C); this skill surfaces
  whatever `install.sh` reports rather than duplicating the check beforehand.

## Why Step B is a genuine human gate, distinct from `install.sh`'s own `--yes`

`install.sh`'s own header comment is explicit about *its* nested-prompt policy: "Sub-installers are
invoked with `--yes` too — the umbrella prompt already covers consent, a second nested prompt would
just be noise." That policy is correct **for `install.sh`'s own relationship to the 16 sub-installers
it composes** — one umbrella consent prompt covering 16 mechanically-identical "stage this one skill
file" operations really would make 16 nested prompts pure noise.

`recipe-install`'s Step B is a **different, higher-level gate**, not a violation of that policy or a
redundant re-ask of it:

- It sits **above** `install.sh`'s own umbrella prompt, not beside or inside it — Step B happens in
  the operator's live conversation with this skill, before `install.sh` (and its own `--yes`-skipped
  prompt) is ever invoked at all.
- `recipe-install` is, per this task's own framing, **the one place in the whole recipe that
  actually writes new scaffolding into a possibly-unfamiliar target repo for the first time.** Every
  other `recipe-*` skill in this repo either (a) has its own standalone installer that stages
  exactly one skill file with its own single consent prompt (`recipe-sync`, `recipe-settle`, etc. —
  narrow, single-purpose, low-stakes), or (b) does no installing at all (`recipe-run-phase`,
  `recipe-plan-phase`, etc. — pure runtime orchestration over an already-installed recipe).
  `recipe-install` is unique in being the **umbrella, first-time, whole-tree** install path,
  wrapped in a conversational skill an operator might invoke against a repo they've never run this
  recipe against before, possibly without having read `INSTALL-LLD.md`'s own directory-tree preview
  first. A single, explicit, human-readable preview-then-confirm exchange in the operator's own
  conversation — not a scripted `--yes` flag they may have passed without fully registering what it
  authorizes — is the appropriate level of ceremony for that specific moment, mirroring exactly the
  rigor `recipe-settle-SKILL.md`'s own PO-accept gate applies to its own "this is the one
  consequential, non-mechanical decision point in this skill" moment.
- Passing `--yes` to `install.sh` in Step C therefore does not defeat or duplicate Step B — it
  simply prevents `install.sh` from asking its *own*, lower-level, "stage these 16 mechanically
  composed files?" question a second time, immediately after the operator already answered the
  higher-level "should this whole install run at all?" question in Step B. Skipping that second,
  narrower question is exactly what avoids becoming the "second nested prompt [that] would just be
  noise" `install.sh`'s own header comment already warns against — Step B is the one prompt that
  matters here; a second one asking essentially the same thing moments later would be the noise, not
  Step B itself.

## Why the uninstall gate mirrors Step B's reasoning

Removing every staged skill file this recipe has installed is at least as consequential as
installing them in the first place — per the locked design decision, uninstalling deserves the same
explicit, live-conversation gate as installing, not a lighter one. The same architectural
distinction applies: `install.sh --uninstall`'s own cascade to 16 sub-installers' `--uninstall`
modes is intentionally silent/non-interactive at that layer (mirroring its own install-time "nested
prompts are noise" policy), while this skill's own uninstall gate sits one level above, asked once,
live, in the operator's conversation, before that cascade is ever triggered.

## Ownership: which piece owns which `INSTALL-LLD.md` step

| `INSTALL-LLD.md` step | Owned by | This skill's role |
|---|---|---|
| Step −1 (Source) | Operator, before invoking this skill at all | Not touched — this skill assumes `<target>` already exists as a git working copy |
| Step 0-1 (Token validation) | `recipe-validate-tokens` (TASK-021) | Step A invokes it by name, relays its report verbatim, never blocks on it |
| Step 2 (Capability install / fallback installer) | `install.sh` itself | Step C runs it directly via `Shell` |
| Step 3 (FLY ON THE WALL install) | `install.sh` itself, via its composed `install-observer.sh` sub-installer | Step C runs it directly via `Shell` (composed inside `install.sh`, not invoked separately) |
| Step 4 (Tracker-sync registration) | `install.sh` itself, via its composed `install-tracker-sync.sh` sub-installer | Step C runs it directly via `Shell` (composed inside `install.sh`, not invoked separately) |
| Step 5 (Verification checklist) | `recipe-install-verify` (TASK-023) | Step D invokes it by name, relays its report verbatim |
| The live "may I write to your repo?" gate | This skill, uniquely (Step B / the uninstall gate) | Never delegated — see "Why Step B is a genuine human gate" above |

## What this does NOT do

- **No re-implementation of `recipe-validate-tokens`'s, `install.sh`'s, or
  `recipe-install-verify`'s own logic.** This skill's entire job is invoking each of the three, in
  order, with exactly one gate of its own (Step B) in between Step A and Step C, and combining their
  real reports.
- **No `--record-jira-check` call.** Unrelated feature, out of scope per the locked design decision.
- **No flag, environment variable, or non-interactive mode that skips or auto-answers Step B or the
  uninstall gate.** Both are genuine, live, conversational human gates — see the dedicated sections
  above for the full rationale.
- **No fabricated sub-results.** Every reported outcome in the Step E combined summary (or the
  uninstall-mode result) is the real thing the invoked skill/script actually printed.
- **No proceeding past a declined gate, or past a failed `install.sh` run**, to a later step that
  depends on it having succeeded.
</cursor_skill_adapter>

# recipe-install — end-to-end install orchestrator (TASK-031)

Formalizes `docs/netapp-recipe/lld/INSTALL-LLD.md`'s full install flow (Steps 0 through 5) into its
own invoke-by-name Cursor skill, so an operator can run the entire install sequence — token
validation, a genuine human consent gate, the real fallback installer, and the post-install
verification checklist — as a single command, instead of invoking `recipe-validate-tokens`,
`install.sh`, and `recipe-install-verify` as three separate manual steps. This is the last remaining
unbuilt named `recipe-*` skill in the spec; once built, every named `recipe-*` skill is Built.

**Spec:** `docs/netapp-recipe/lld/INSTALL-LLD.md` (all steps) · `docs/netapp-recipe/BACKLOG.md`
TASK-031.

**Built standalone**, the same pattern already used by `recipe-sync` (TASK-029) and
`recipe-run-phases` (TASK-018) for a thin, multi-step orchestrator chaining other already-built
pieces by name/by real script call — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-install.sh`, composed into `install.sh` (TASK-010) as its 16th
sub-installer.

## Workflow

1. Invoke `recipe-validate-tokens` by name (Step A) — informational, never blocks.
2. Ask the operator a genuine, live, non-skippable consent question previewing what will be staged
   (Step B). Decline → stop, nothing else runs.
3. Run `install.sh --yes --target <target>` directly via `Shell` (Step C) — the real fallback
   installer, already composing every sub-installer this repo has built.
4. Invoke `recipe-install-verify` by name (Step D) — the real Step-5 verification checklist.
5. Report one combined summary of all four sub-results, never fabricated (Step E).

`--uninstall` skips straight to its own live consent gate, then delegates to
`install.sh --uninstall --yes --target <target>` directly.

## Why this is a thin orchestrator, not a reimplementation

Every actual piece of work — token validation, directory scaffolding, sub-installer composition,
verification — is already built and already independently invokable:
`recipe-validate-tokens` (TASK-021), `install.sh` (TASK-010, already composing 15 other
sub-installers before this task adds a 16th), and `recipe-install-verify` (TASK-023). This skill
adds exactly one net-new thing that didn't exist before: a genuine, live, human consent gate sitting
above all three, plus the glue that invokes each in order and combines their reports. Same
"delegate entirely, never reimplement" precedent `recipe-sync-SKILL.md` and
`recipe-run-phases-SKILL.md` already established for their own multi-step orchestrations.

## Relationship to `install.sh`'s own `--yes`

`install.sh --yes` (passed in Step C) skips only `install.sh`'s *own* nested scaffolding-consent
prompt — the "Install NetApp GSD recipe scaffold (...) into `<target>`? [y/N]" question its own
`install()` function would otherwise ask. It does **not** skip, replace, or stand in for Step B,
which is a separate, higher-level gate this skill asks in its own conversational turn, before
`install.sh` is ever invoked. See the skill's own "Why Step B is a genuine human gate, distinct from
`install.sh`'s own `--yes`" section for the full reasoning — the short version: `install.sh`'s
"nested prompts are noise" policy is correct for its relationship to the 16 sub-installers it
composes, not a reason to skip the one, higher-level "should this whole install run at all?"
question a first-time (or first-time-into-this-repo) operator deserves to be asked, live, in their
own conversation.

## What this does NOT do

- **Does not implement any check itself.** Every credential check, every scaffolding step, every
  verification item is owned by one of the three invoked pieces (`recipe-validate-tokens`,
  `install.sh`, `recipe-install-verify`) — this skill only orchestrates the order and the one gate
  in between.
- **Does not call `install.sh --record-jira-check`.** Explicitly out of scope, unrelated feature.
- **Does not skip or auto-answer its own Step B or uninstall gate**, ever, under any flag or
  environment variable — see the dedicated rationale sections above.
- **Does not fabricate any sub-result.** The combined summary (Step E) and the uninstall-mode
  report always relay exactly what each invoked skill/script actually reported.
