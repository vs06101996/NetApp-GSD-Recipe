# `recipe-sync` skill (TASK-029)

**Built per direct task assignment**, closing a real gap identified after the `gsd-jira-sync`
installer (TASK-028) landed: `sync-reconcile.sh` (TASK-003, detect+draft+queue) and
`sync-drain-queue.sh`/`gsd-jira-sync --drain` (TASK-005, drain+post) are both fully built, but an
operator had to invoke them as two separate manual steps. `docs/netapp-recipe/DECISIONS.md`'s
**OD-05** ("`recipe-sync` trigger: Loop-first; hooks later") names this exact skill and locks the
"loop-first" half of its scope up front: a single one-shot "run one sync pass now" primitive, with
recurring triggering left as a separate, still-open concern this task does not resolve.

## Locked design decisions (implemented exactly, not re-derived)

1. **`recipe-sync [--dry-run]`** — a thin, invoke-by-name orchestration skill, mirroring
   `tracker-sync-SKILL.md`'s own "delegate entirely, never reimplement" precedent.
2. **Step 1 — detect + queue, real shell call, not agent-mediated.** Runs
   `bench/runners/sync-reconcile.sh` directly via `Shell`, passing `--dry-run` through unchanged.
   Same category as `recipe-install-verify` calling `install.sh --verify` directly — a real,
   scriptable, testable script invocation.
3. **`--dry-run` stops after step 1, full stop.** Never proceeds to drain — "show me what would
   happen" never posts anything.
4. **Step 2 — drain, skill-to-skill, Option B.** Invokes `gsd-jira-sync --drain` by name.
   `recipe-sync` never calls `sync-drain-queue.sh list`/`mark-done`/`mark-failed` itself, and never
   calls `addCommentToJiraIssue` itself — it delegates the entire drain step, exactly like
   `tracker-sync` delegates entirely to `gsd-jira-sync` for single-event mode.
5. **Step 3 — combined summary** of step 1's queued/duplicate_skipped/errors plus step 2's
   posted/failed/skipped_duplicate counts.
6. **No internal loop/scheduler/hooks — the single most important scope boundary.** No
   `--interval`/`--watch` flag, no `while` loop, no cron, no background daemon, no
   `.cursor/hooks.json` entry. Recurrence is the operator's job (invoke it again) or Cursor's own
   generic `/loop` automation, composed externally — `recipe-sync` does not need to know about or
   integrate with `/loop` in any way.
7. **Never fabricates a result.** A failed/partial drain surfaces as a real failure via
   `gsd-jira-sync --drain`'s own `mark-failed` path, never silently treated as success.
8. **`target: github` rows are surfaced, never worked around.** Same limitation
   `gsd-jira-sync --drain`'s own `list` step already documents (TASK-006 only built the draft
   script, no posting path) — `recipe-sync` reports these plainly, never substitutes `gh pr comment`.

## Explicitly out of scope (do not mistake for oversights)

| Out of scope | Why |
|---|---|
| Any internal loop, `--interval`/`--watch` flag, cron registration, or background daemon | Locked decision #6 — OD-05's "loop-first" framing places recurrence outside this skill; building one here would mean maintaining a competing scheduler alongside Cursor's own `/loop` primitive. |
| Hooks-based auto-triggering (reacting to GSD lifecycle events without an explicit invocation) | OD-05's own "hooks later" half — still open, deliberately not pre-empted by this task. No `.cursor/hooks.json` entry, no file watcher, no event listener. |
| Reimplementing `sync-reconcile.sh`'s detect/draft/queue logic | Always delegates to the real script (step 1). |
| Reimplementing `sync-drain-queue.sh`'s `list`/`mark-done`/`mark-failed`, or the `addCommentToJiraIssue` MCP call itself | Always delegates to `gsd-jira-sync --drain` (step 2) — same precedent `tracker-sync` already established for single-event mode. |
| A GitHub posting workaround for `target: github` rows | TASK-006 only built `draft-github-pr-comment.sh`, not a posting path — no GitHub drain exists to delegate to yet. |
| `recipe-pr-comment` | Separate, unbuilt, out-of-scope future task — not touched by this one. |

## What was built

| Piece | Path | Purpose |
|---|---|---|
| Skill content | `.gsd-recipe/templates/recipe-sync-SKILL.md` | Canonical source. Full `<cursor_skill_adapter>` A/B/C/D block implementing the 3-step workflow (detect+queue → drain-unless-dry-run → combined summary), with a dedicated "Why this doesn't loop itself (OD-05)" section, a "Combined summary shape" section, a "GitHub tracker limitation" section, a "Never fabricates a result" section, and a "Relationship to sync-reconcile.sh / sync-drain-queue.sh / gsd-jira-sync" ownership table. |
| Installer | `.gsd-recipe/scripts/install-recipe-sync.sh` | Standalone installer mirroring `install-gsd-jira-sync.sh`'s structure/functions (ledger tracking, `--yes`/`--target`/`--uninstall`, fail-closed on non-git target, `is_canonical_source` self-install guard), staging to `.cursor/skills/recipe-sync/SKILL.md`. Ledger component `"recipe-sync"`. Never touches `.gsd-recipe/config.json`, `.planning/config.json`, `.gsd-recipe/sync-queue.jsonl`, or `.gsd-recipe/sync-ledger.jsonl` — those are the staged skill's own runtime concern whenever it's actually invoked, not the installer's. |
| Tests | `bench/tests/test-install-recipe-sync.sh` (30 assertions) | Fail-closed non-git target, fresh install staging, exactly-1 ledger row, never touching config/queue/ledger files, 14 staged-content assertions covering every documented workflow step and scope boundary above, idempotent re-install, uninstall + ledger-clear + directory cleanup, self-install collision safety, self-uninstall canonical-source preservation. |
| Composed into `install.sh` | 14th sub-installer, appended after the existing 13 (`observer`, `tracker-sync`, `recipe-planning-policy`, `recipe-run-phase`, `recipe-plan-phase`, `recipe-validate-tokens`, `recipe-bootstrap-knowledge`, `recipe-install-verify`, `recipe-run-phases`, `recipe-verify-feature`, `recipe-review-ship`, `recipe-settle`, `gsd-jira-sync`) — path var, `install()`/`uninstall()`/`verify()` wiring, consent-prompt string, header comment. | |
| Capability catalog | `bench/lib/capability-schema.sh` — 16th `CATALOG` entry (`id: "recipe-sync"`, `task_id: "TASK-029"`). | |
| Docs | `docs/netapp-recipe/BACKLOG.md` (new TASK-029 row) and `docs/netapp-recipe/README.md` (Built-vs-spec row, Commands→Built row; `recipe-sync` removed from both Spec-table mentions since it's no longer spec-only). | |

## Validation performed

### Automated

`bench/tests/test-install-recipe-sync.sh`: **30 assertions, 0 failed**, run standalone.

Full `bench/tests/*.sh` suite (27 files, run after this task's composition edits landed):
**all 27 files exit 0, zero regressions.**

### Manual (real-environment)

Exercised the installer against disposable `/tmp` scratch git repos (fresh install, idempotent
re-install, uninstall + ledger-clear + directory cleanup, self-install-into-a-copy collision
safety) — the same shape every prior single-file-staging installer's report documents. Confirmed
`sync-reconcile.sh --dry-run` runs cleanly standalone (real script call, no queue writes) against
a repo with no `.planning/STATE.md` present, correctly reporting zero detected events rather than
erroring — consistent with `recipe-sync`'s own step-1 "capture and report whatever it detects"
contract. The `gsd-jira-sync --drain` step itself (step 2) was not invoked for real during
verification — same standing constraint every prior report in this recipe applies to native
GSD/MCP calls, since draining requires a real, authenticated Atlassian MCP session and a real
queued backlog; the skill's own documented delegation to `gsd-jira-sync --drain`'s already-verified
Drain-mode contract (see `bench/report/gsd-jira-sync-installer-integration-report.md`) was
inspected instead.

### Self-install into the real repo

```bash
./.gsd-recipe/scripts/install-recipe-sync.sh --yes --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh generate-capability --target /Users/vs72964/Projects/gsd-benchmark
./bench/lib/capability-schema.sh validate-capability \
  --capability .gsd-recipe/capability.json --schema .gsd-recipe/capability.schema.json
```

Staged `.cursor/skills/recipe-sync/SKILL.md`, recorded exactly 1 ledger row, regenerated
`.gsd-recipe/capability.json` (**16 capabilities, 13 staged**, `recipe-sync` reporting
`staged: true`), and it validates cleanly against `capability.schema.json`.

## Files

- `.gsd-recipe/templates/recipe-sync-SKILL.md` (new)
- `.gsd-recipe/scripts/install-recipe-sync.sh` (new)
- `bench/tests/test-install-recipe-sync.sh` (new, 30 assertions)
- `bench/report/recipe-sync-integration-report.md` (new, this file)
- `.cursor/skills/recipe-sync/SKILL.md` (self-install side effect, real repo)
- `.gsd-recipe/ledger.json` / `.gsd-recipe/capability.json` (self-install side effects, real repo — additive only)

**Modified (composed directly — no concurrent siblings were running this session):**
`.gsd-recipe/scripts/install.sh`, `bench/lib/capability-schema.sh`, `bench/tests/test-install.sh`,
`bench/tests/test-capability-schema.sh`, `docs/netapp-recipe/BACKLOG.md`,
`docs/netapp-recipe/README.md`.

## Deviations from the plan

None in scope or design. One process note: the build session's connection stalled during a final
cleanup step (removing `/tmp` scratch directories) after all functional work, tests, and shared-file
composition were already complete and passing — the self-install, `capability.json` regeneration,
and this report were finished in a short follow-up pass rather than by the original session.
