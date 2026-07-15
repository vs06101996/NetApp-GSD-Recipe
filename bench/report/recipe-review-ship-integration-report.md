# `recipe-review-ship` skill (TASK-026)

**Design decisions locked by the operator this session** (not re-derived here — implemented
exactly as given), matching the standalone-installer precedent already used by `recipe-prd-intake`
(TASK-016), `recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and
`recipe-plan-phase` (TASK-017) — built ahead of the full `install.sh` (TASK-010). Closest existing
precedent (per the task brief): `recipe-run-phase`'s shape (single native call + Jira sync), here
extended to two native calls (`gsd-code-review` then `gsd-ship`) with the sync sitting between
them.

## Scope decisions (operator-approved this session)

1. **Option B — direct same-turn native calls, both of them.** `recipe-review-ship N [--draft]`
   calls native `gsd-code-review N` directly, then (after the Jira sync) native `gsd-ship N
   [--draft]` directly — both within the same turn. The operator's own act of invoking
   `recipe-review-ship` by name **is** the manual GSD trigger — identical reasoning already
   approved for `recipe-plan-phase`/`recipe-run-phase`, not `recipe-prd-intake`'s deliberate
   *non*-invocation of `gsd-discuss-phase`.
2. **Tracker posting is skill-to-skill, idempotent, fail-open.** `review_complete` is emitted by
   invoking the existing `gsd-jira-sync` skill's documented workflow (never inlining
   `draft-jira-comment.sh`'s draft/post/stamp steps), gated by the same
   `sync-ledger.sh key`/`has`-check idempotency pattern as `recipe-plan-phase`/`recipe-run-phase`,
   and fails open (warns, continues to `gsd-ship`) when no tracker issue is linked for the phase.
   `jira-events.json`'s `review_complete` entry's optional `"In Review"` transition is passed
   through to `gsd-jira-sync` as `--transition "In Review"`, never applied directly by this skill.
3. **No new sync event for the ship/PR-creation step.** The catalog's only relevant later event,
   `settled`, is explicitly triggered by "PO accept + CI green" — a different milestone owned by a
   different task (`recipe-settle`, TASK-027). This skill does not invent a `ship_complete`/
   `pr_opened` event id; it only prints/surfaces the PR link `gsd-ship` itself returns.
4. **`gsd-ship`'s own prerequisite is not re-verified here.** `gsd-ship N`'s documented prerequisite
   ("`gsd-verify-work` passed for phase") is `recipe-verify-feature`'s (TASK-025) job to gate, not
   this skill's — `recipe-review-ship` just calls `gsd-ship N` and surfaces whatever native GSD
   itself reports if the prerequisite isn't met, never silently bypassing or faking a passed state.
5. **Explicitly out of scope, confirmed, not oversights:** bundling
   `bench/runners/draft-github-pr-comment.sh` (TASK-006) into this skill's own flow (stays a
   separate, standalone, operator-run tool); auto-invoking `gsd-review` (optional cross-AI peer
   review) or `gsd-ui-review N` (both print-only informational suggestions in this skill's own
   output, never auto-invoked).

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| A distinct `ship_complete`/`pr_opened` sync event | `jira-events.json`'s only later-lifecycle event is `settled`, explicitly triggered by "PO accept + CI green" (`recipe-settle`, TASK-027) — a different milestone entirely, not the act of opening the PR. Confirmed with the operator this session; do not invent one. |
| Bundling `bench/runners/draft-github-pr-comment.sh` (TASK-006) | Stays a separate, standalone tool an operator can run independently. This skill's own flow never invokes it. |
| Auto-invoking `gsd-review` | Optional cross-AI peer review of plans, per `RUNTIME-LLD.md` §4.a — printed as an informational suggestion only. |
| Auto-invoking `gsd-ui-review N` | Optional FE-paired browser-MCP review, per `RUNTIME-LLD.md` §4.a — printed as an informational suggestion only. |
| Re-verifying `gsd-verify-work`'s pass/fail state before calling `gsd-ship` | `recipe-verify-feature`'s (TASK-025) job, not this skill's. `recipe-review-ship` surfaces whatever native GSD reports if the prerequisite is unmet — it never bypasses or fakes a passed state. |
| Composing this installer into `.gsd-recipe/scripts/install.sh` / `bench/tests/test-install.sh`, or updating `docs/netapp-recipe/BACKLOG.md` / `docs/netapp-recipe/README.md` | Explicit hard constraint for this task — three sibling tasks (TASK-018/025/027) are being built concurrently against those same 4 shared files; a parent integration pass applies all deferred snippets together afterward. See "Deferred snippets" below. |
| `4.b Org review bot [E]` (`{ORG_REVIEW_BOT}` on PR) | Pluggable, explicitly out of recipe core per `RUNTIME-LLD.md` §4.b. Not this skill's concern at all. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-review-ship-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block (mirrors `recipe-run-phase-SKILL.md`'s format) implementing the 7-step workflow: call native `gsd-code-review N` → resolve issue key → emit `review_complete` (skill-to-skill, with optional `"In Review"` transition) → call native `gsd-ship N [--draft]` → surface the resulting PR link → print `gsd-review`/`gsd-ui-review N` as informational-only suggestions → one-line summary. Includes an explicit "Why Option B" section and a "Why there is no `ship_complete`/`pr_opened` sync event" section, both mirroring `recipe-run-phase-SKILL.md`'s own structure. |
| Installer | `.gsd-recipe/scripts/install-recipe-review-ship.sh` | Standalone installer mirroring `install-recipe-run-phase.sh`'s/`install-recipe-plan-phase.sh`'s structure/functions exactly (ledger tracking via `ledger_record`/`ledger_files`, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard), staging to `.cursor/skills/recipe-review-ship/SKILL.md`. Ledger component name `"recipe-review-ship"`. Never touches `.gsd-recipe/config.json` or `.planning/config.json`. Not yet wired into `install.sh` (deferred per hard constraint — see below). |
| Tests | `bench/tests/test-install-recipe-review-ship.sh` (30 assertions) | Standalone installer behavior test, mirroring `test-install-recipe-run-phase.sh`'s assertion style: fail-closed non-git target, fresh install staging, exactly-1 ledger row, never touching either `config.json`, 18 staged-content assertions covering every documented gate/behavior/decision above, idempotent re-install, uninstall + ledger-clear + directory cleanup, self-install collision safety, self-uninstall canonical-source preservation. Deliberately **omits** the composition-assertion section (`test-install-recipe-run-phase.sh`'s §8) since this task does not wire the installer into `install.sh` — those 4 assertions are provided as a deferred snippet instead (see below), to be added by the parent integration pass alongside the other 3 concurrent tasks' own composition wiring. |
| Report | `bench/report/recipe-review-ship-integration-report.md` | This file. |

## Validation performed

### Automated

Ran the new test file standalone (not the full `bench/tests/` suite, per the task's explicit
instruction):

```
$ ./bench/tests/test-install-recipe-review-ship.sh
ok - refuses to install into a non-git directory
ok - fresh install stages .cursor/skills/recipe-review-ship/SKILL.md
ok - fresh install records exactly 1 ledger row (the skill file)
ok - install never creates .gsd-recipe/config.json
ok - install never creates .planning/config.json
ok - staged skill references calling native gsd-code-review directly
ok - staged skill references the review_complete sync event
ok - staged skill references invoking gsd-jira-sync (skill-to-skill, not inline)
ok - staged skill disclaims inlining draft-jira-comment.sh's posting logic
ok - staged skill references the optional 'In Review' transition
ok - staged skill disclaims calling transitionJiraIssue directly itself
ok - staged skill references calling native gsd-ship directly
ok - staged skill forwards --draft to gsd-ship
ok - staged skill references surfacing the resulting PR link
ok - staged skill explains why there is no distinct ship/PR sync event (settled/TASK-027)
ok - staged skill names recipe-settle/TASK-027 as the owner of the settled event
ok - staged skill disclaims bundling draft-github-pr-comment.sh
ok - staged skill disclaims auto-invoking gsd-review/gsd-ui-review
ok - staged skill mentions gsd-review as an informational-only suggestion
ok - staged skill mentions gsd-ui-review N as an informational-only suggestion
ok - staged skill defers gsd-verify-work re-checking to recipe-verify-feature (TASK-025)
ok - staged skill disclaims silently bypassing/faking gsd-ship's passed prerequisite
ok - staged skill documents fail-open behavior on tracker/MCP issues
ok - re-running install does not duplicate ledger rows
ok - uninstall removes the staged skill
ok - uninstall clears the component's ledger entry
ok - uninstall cleans up the now-empty skill directory
ok - self-install into a copy of this repo does not error (src==dest collision handled)
ok - self-install uninstall does not error
ok - self-uninstall preserves the canonical skill template source
---
30 passed, 0 failed
```

**`bench/tests/test-install-recipe-review-ship.sh` total: 30 assertions, 0 failed.** No other test
file was run (per the task's instruction to run only this new test file standalone) — confirmed no
edits were made to any other test file, so no regression risk elsewhere.

### Manual (real-environment, disposable scratch repo)

Ran against a fresh scratch repo at `/tmp/recipe-review-ship-manual-01` (never the real
`gsd-benchmark` repo — every command used an absolute `--target`/`--state`/`REPO_ROOT`/`--ledger`
pointing at the scratch path, self-contained per-call, no `cd`/env persistence relied on across
tool calls). The scratch repo was deleted (`rm -rf`) once verification finished.

1. **Real installer execution.** `git init` the scratch repo, then ran the real
   `.gsd-recipe/scripts/install-recipe-review-ship.sh --yes --target /tmp/recipe-review-ship-manual-01`.
   This genuinely staged `.cursor/skills/recipe-review-ship/SKILL.md` (12,411 bytes) in the scratch
   repo and recorded exactly 1 ledger row (`.cursor/skills/recipe-review-ship/SKILL.md`) — verified
   after the fact by reading both the staged file and `ledger.json` directly.
2. **Real `resolve-issue` trace.** Seeded a scratch `.planning/STATE.md` with `## Tracker` (epic
   `MAN-100`) and a `## Phase tasks` row linking phase `3` → `MAN-103` (phase `4` deliberately left
   unlinked). Ran the real `bench/lib/parse-state.sh resolve-issue review_complete --phase 3` →
   resolved `MAN-103` for real. Ran the same command for `--phase 4` → real exit 1 with the actual
   error message `unresolved phase-routed event: phase_id '4' for event_id 'review_complete' has no
   matching row in '## Phase tasks'` — confirming the skill's own step 2 fail-open routing (warn and
   continue straight to `gsd-ship`) is backed by a real, reproducible failure mode, not a fabricated
   one.
3. **Real idempotency-key trace.** Computed the real key via
   `bench/lib/sync-ledger.sh key review_complete MAN-103 --phase 3` →
   `gsd-recipe:review_complete:phase=3:issue=MAN-103`. Confirmed `sync-ledger.sh has <key>` against
   a scratch (nonexistent) ledger file exits 1 (not found), then appended a real ledger row via
   `sync-ledger.sh append <key> jira --external-id manual-trace-comment-1 --result posted`
   (simulating what `gsd-jira-sync`'s own internal step would do post-comment — not a real MCP
   call), then re-checked `has <key>` → exit 0 (found), confirming a second `recipe-review-ship 3`
   invocation would correctly report `duplicate_skipped` per the skill's step 3.
4. **Real uninstall.** Ran `install-recipe-review-ship.sh --uninstall --target
   /tmp/recipe-review-ship-manual-01` → confirmed the staged `SKILL.md` was genuinely removed, the
   `.cursor/skills/recipe-review-ship/` directory was cleaned up, and the ledger component entry was
   cleared (`{}`).
5. **Cleanup.** `rm -rf /tmp/recipe-review-ship-manual-01` — confirmed gone.

**What was truly executed vs. traced/reasoned through** (per the task's explicit instruction never
to invoke real native GSD or real `gsd-jira-sync`/MCP calls):

- **Truly executed**: the installer itself (staged a real file, wrote a real ledger row, real
  uninstall cleanup); `parse-state.sh resolve-issue` for both the linked (success) and unlinked
  (real failure, real error message) phase cases against a real scratch `STATE.md`;
  `sync-ledger.sh key`/`has`/`append` for the full idempotency lifecycle against a real scratch
  ledger file.
- **Traced/reasoned about, not executed**: `gsd-code-review N` and `gsd-ship N [--draft]`
  themselves (native GSD — would require a real codebase and a real PR-hosting remote to act on,
  neither of which the scratch repo has), and the actual `gsd-jira-sync` skill invocation /
  `addCommentToJiraIssue`/`transitionJiraIssue` MCP calls it would make (would require a real,
  authenticated Atlassian MCP session and a real Jira issue) — per the task's explicit instruction.
  The skill's own documented steps 1, 4, and 5 (the two native calls and the PR-link surfacing) were
  verified by inspection of the staged `SKILL.md` content instead (confirmed present, worded per the
  approved decisions, and consistent with `RUNTIME-LLD.md` §4.a/§4.c's own command shapes).

**Confirmed outcomes for the required scenario checks:**

1. **Installer stages/uninstalls cleanly against a disposable scratch repo, real execution.**
   Confirmed above (steps 1 and 4).
2. **Unresolved issue key → warns and continues, does not block (fail-open).** Confirmed for real
   (phase 4's `resolve-issue` genuinely exits 1 with a real, specific, actionable error; the skill's
   own step 2 instructions route that failure to "warn and continue straight to step 4," never to a
   stop).
3. **Idempotency key computation and duplicate-detection round-trip for `review_complete`.**
   Confirmed for real (step 3 above) — first check `has` misses, real `append`, second check `has`
   hits.
4. **No stray side effects leaked into the real `gsd-benchmark` repo.** `git status --porcelain`
   before and after this task's work shows only the 3 new files this task creates
   (`.gsd-recipe/templates/recipe-review-ship-SKILL.md`,
   `.gsd-recipe/scripts/install-recipe-review-ship.sh`,
   `bench/tests/test-install-recipe-review-ship.sh`) as untracked additions, plus the pre-existing
   untracked/modified tree from prior tasks already present at session start — no stray
   `.cursor/skills/recipe-review-ship/`, no stray git config, no stray `.gsd-recipe/ledger.json`
   changes in this repo (the installer was only ever run with `--target` pointing at `/tmp/...`
   scratch repos or the test file's own `mktemp -d` targets, both cleaned up).

## Deferred snippets (apply in the parent integration pass — not applied by this task)

Per the hard constraint, none of the 4 shared files below were edited. These are copy-paste-ready
for whoever runs the parent integration pass composing this task alongside TASK-018/025/027.

### 1. `.gsd-recipe/scripts/install.sh`

**Declare the installer path** (add after the existing `RECIPE_INSTALL_VERIFY_INSTALLER` line,
~line 133):

```bash
RECIPE_REVIEW_SHIP_INSTALLER="$SCRIPT_DIR/install-recipe-review-ship.sh"
```

**Compose in `install()`** (add after the existing `"$RECIPE_INSTALL_VERIFY_INSTALLER" --yes
--target "$TARGET"` line, ~line 681; also update the preceding `echo "install.sh: composing
sub-installers (...)..."` line to append `, recipe-review-ship`):

```bash
  "$RECIPE_REVIEW_SHIP_INSTALLER" --yes --target "$TARGET"
```

**Cascade in `uninstall()`** (add after the existing `"$RECIPE_INSTALL_VERIFY_INSTALLER"
--uninstall --target "$TARGET"` line, ~line 943):

```bash
  "$RECIPE_REVIEW_SHIP_INSTALLER" --uninstall --target "$TARGET"
```

**Check in `verify()`** (add after the existing `recipe-install-verify composed` block, ~line 849,
mirroring its exact shape):

```bash
  if ledger_has_component "recipe-review-ship"; then
    echo "    recipe-review-ship composed — pass"
  else
    echo "    recipe-review-ship composed — FAIL (recipe-review-ship ledger component absent)"
    ok=0
  fi
```

### 2. `bench/tests/test-install.sh`

**Staging check** (add near the existing `recipe-install-verify` staging assertion, ~line 136):

```bash
[ -f "$TARGET1/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "install.sh composes install-recipe-review-ship.sh (skill staged)" "$?"
```

**Ledger cross-tracking disjointness** — extend the existing Python assertion block (~line 148-160)
by adding one more `assert` line and updating the disjointness check + its `check` description:

```bash
assert 'recipe-review-ship' in d and d['recipe-review-ship'], d
```

```bash
assert set(d['install-core']).isdisjoint(set(d['recipe-review-ship'])), d
```

```bash
check "ledger separates install-core from fotw-observer/tracker-sync/recipe-planning-policy/recipe-run-phase/recipe-plan-phase/recipe-validate-tokens/recipe-bootstrap-knowledge/recipe-install-verify/recipe-review-ship components (no cross-tracking)" "$?"
```

**`--verify` output mention** (add near the existing `recipe-install-verify` verify-output check,
~line 244):

```bash
echo "$VERIFY_OUT1" | grep -q "recipe-review-ship composed — pass" && rc=0 || rc=$?
check "--verify output mentions recipe-review-ship composition" "$rc"
```

**`--uninstall` cascade check** (add near the existing `recipe-install-verify` uninstall-cascade
check, ~line 285):

```bash
[ ! -f "$TARGET3/.cursor/skills/recipe-review-ship/SKILL.md" ]
check "uninstall cascades to install-recipe-review-ship.sh --uninstall" "$?"
```

This is **+5 net new assertions** (1 staging + 1 disjointness-extension [existing assertion body
extended, not duplicated] + 1 verify-output + 1 uninstall-cascade + the ledger-membership `assert`
line folds into the existing block rather than adding a `check`), following the exact `+3`/`+4`
precedent set by the `recipe-run-phase`/`recipe-bootstrap-knowledge` additions.

### 3. `docs/netapp-recipe/BACKLOG.md`

**Replace the existing TASK-026 row** (currently `| TASK-026 | \`recipe-review-ship\` | S | — |
[RUNTIME-LLD](lld/RUNTIME-LLD.md) |`) with:

```markdown
| TASK-026 | `recipe-review-ship` | S | — | [RUNTIME-LLD](lld/RUNTIME-LLD.md) — **Built**: gate-and-invoke wrapper calling native `gsd-code-review N` directly, syncing `review_complete` by invoking the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked, optional `"In Review"` transition), then calling native `gsd-ship N [--draft]` directly and surfacing the resulting PR link. No distinct sync event for the ship/PR-creation step itself — that stays `settled`'s job (`recipe-settle`, TASK-027). Does not re-verify `gsd-ship`'s own "`gsd-verify-work` passed" prerequisite (`recipe-verify-feature`'s, TASK-025, job) and does not bundle `draft-github-pr-comment.sh` (TASK-006) or auto-invoke `gsd-review`/`gsd-ui-review N` (both print-only informational suggestions). See [bench/report/recipe-review-ship-integration-report.md](../../bench/report/recipe-review-ship-integration-report.md). |
```

### 4. `docs/netapp-recipe/README.md`

**"Built vs spec" table** — add a row (mirroring the `recipe-run-phase`/`recipe-plan-phase` row
shape, ~after line 35):

```markdown
| `recipe-review-ship` skill (TASK-026) | **Built** — gate-and-invoke wrapper (`.gsd-recipe/scripts/install-recipe-review-ship.sh`, standalone installer, composed into `install.sh` as a 9th sub-installer); calls native `gsd-code-review N` directly, syncs `review_complete` by invoking the `gsd-jira-sync` skill (idempotent via `sync-ledger.sh`, fail-open when no tracker issue is linked, optional `"In Review"` transition), then calls native `gsd-ship N [--draft]` directly and surfaces the resulting PR link; no distinct sync event for the ship step itself (stays `settled`'s job, TASK-027), no re-verification of `gsd-ship`'s own prerequisite (TASK-025's job), and `draft-github-pr-comment.sh`/`gsd-review`/`gsd-ui-review N` stay explicitly out of scope (informational-only or standalone) — see [bench/report/recipe-review-ship-integration-report.md](../../bench/report/recipe-review-ship-integration-report.md) |
```

**Commands table** — add a row (mirroring the `recipe-run-phase`/`recipe-plan-phase` row shape,
~after line 125):

```markdown
| `recipe-review-ship N [--draft]` (TASK-026) | Gate-and-invoke single-phase review-and-ship wrapper — [.gsd-recipe/templates/recipe-review-ship-SKILL.md](../../.gsd-recipe/templates/recipe-review-ship-SKILL.md) · [report](../../bench/report/recipe-review-ship-integration-report.md) |
```

**Spec table** — remove `recipe-review-ship` if it's listed anywhere in the still-spec-only rows
(it currently is not — `BACKLOG.md`'s TASK-026 row already exists as the only spec reference, and
the Spec table's own rows don't separately enumerate individual `recipe-*` skill names beyond
`recipe-prd-intake`/`recipe-run-phases`/`recipe-verify-feature`, none of which is this skill) — no
removal needed, only the two additions above.

## Files

- `.gsd-recipe/templates/recipe-review-ship-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-review-ship.sh` (new)
- `bench/tests/test-install-recipe-review-ship.sh` (new, 30 assertions)
- `bench/report/recipe-review-ship-integration-report.md` (new, this file)

**Not touched** (per hard constraint — deferred snippets above): `.gsd-recipe/scripts/install.sh`,
`bench/tests/test-install.sh`, `docs/netapp-recipe/BACKLOG.md`, `docs/netapp-recipe/README.md`,
`bench/runners/draft-github-pr-comment.sh`, any other `recipe-*` skill's files,
`.gsd-recipe/capability.json` (capability-catalog registration also deferred to the same parent
integration pass, consistent with not touching `install.sh`, which is what would normally trigger
`generate-capability`).
