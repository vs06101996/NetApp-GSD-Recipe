---
name: recipe-bootstrap-knowledge
description: "Recipe: invoke-by-name knowledge bootstrap/refresh wrapper for the NetApp GSD recipe (TASK-022). Idempotently scaffolds the OKF-shaped `.knowledge/` skeleton (index.md, log.md, architecture/, dependency-graph/, hot-files/, risk-register/ — minimal frontmatter placeholders only, never overwriting existing files) if any piece is missing, then calls native `/gsd-map-codebase [--fast]`, `/gsd-graphify build`, and `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly in the same turn (Option-B precedent, same reasoning as `recipe-plan-phase`/`recipe-run-phase`), gracefully warning and skipping only the ingest step when that manifest doesn't exist yet — never touching human-authored `code_base_details/` content — and reports what was populated/refreshed."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-bootstrap-knowledge`) with:
- `--fast` — optional, forwarded verbatim to native `/gsd-map-codebase --fast`.

Examples:
- `recipe-bootstrap-knowledge`
- `recipe-bootstrap-knowledge --fast`

## B. Prerequisites

- None strictly required. This skill works whether `.knowledge/` already exists or not, and
  whether `.gsd-recipe/ingest-manifest.yaml` exists or not (see step 4) — both are handled
  idempotently/gracefully, never blocking invocation.
- Run this once per repo after install, and again "on major change" per
  `docs/netapp-recipe/lld/INSTALL-LLD.md` § "Populate `.knowledge/` from GSD" — there is no
  first-time-vs-refresh distinction the operator needs to make up front; the same steps handle
  both safely, every time.

## C. Tool Usage

1. **Check `.knowledge/` and scaffold the OKF-shaped skeleton for any missing piece.** Check for
   `.knowledge/index.md`, `.knowledge/log.md`, and the four subdirectories `architecture/`,
   `dependency-graph/`, `hot-files/`, `risk-register/` individually (not as an all-or-nothing
   check — a partially-scaffolded `.knowledge/` from a prior partial run must still get its
   remaining gaps filled).
   - For each missing piece, create only that piece: `index.md`/`log.md` get minimal OKF
     frontmatter placeholders (`type: index` / `type: log`, plus `title:` — the same minimal
     shape `install.sh`'s own `.knowledge/index.md`/`log.md` placeholders already use, so a repo
     that ran `install.sh` first sees no difference); each subdirectory gets a `.gitkeep` if
     created empty, so git tracks it. This is scaffolding only — minimal placeholder content,
     never full content. The real population is what steps 2-4 below produce.
   - For each piece that already exists, leave it **completely untouched** — never overwrite,
     never append, never regenerate. This step is purely additive/idempotent, safe to run on
     every invocation ("refresh on major change" per the spec) without ever clobbering prior
     output from `/gsd-map-codebase`, `/gsd-graphify`, or `/gsd-ingest-docs`.
   - Never create, touch, or write to `.knowledge/dag/` — that subdirectory is `install.sh`'s own
     scaffolding concern (already created there on install), and DAG population is out of scope
     for this skill (parked pending TASK-009's `dag-build.sh` per `DECISIONS.md`).
   - Never create, edit, or delete anything under `code_base_details/` — that is human-authored
     content (`docs/netapp-recipe/lld/INSTALL-LLD.md`'s "if directory exists, update only —
     installer does not overwrite human files" rule applies here too). `/gsd-ingest-docs` reads
     that directory in step 4; this wrapper never writes to it.

2. **Call native `/gsd-map-codebase [--fast]` directly**, in this same turn. Forward `--fast` only
   if the operator passed it to `recipe-bootstrap-knowledge`. Invoking `recipe-bootstrap-knowledge`
   was itself the operator's deliberate act of choosing to bootstrap/refresh knowledge right now —
   that IS the manual GSD trigger; this is not an unapproved autonomous invocation (same precedent
   as `recipe-plan-phase`'s direct call to `gsd-plan-phase` and `recipe-run-phase`'s direct call to
   `gsd-execute-phase` — see "Why Option B" below for the full reasoning, mirrored verbatim from
   those two skills' own explanatory sections).

3. **Call native `/gsd-graphify build` directly**, in this same turn, same Option-B reasoning as
   step 2. No flags to forward — `/gsd-graphify build` takes none here.

4. **Check for `.gsd-recipe/ingest-manifest.yaml` before calling `/gsd-ingest-docs`.** This is the
   one step of the three native commands that is conditionally skippable — `/gsd-map-codebase` and
   `/gsd-graphify build` have no equivalent missing-input condition, so steps 2-3 always run
   regardless of what this check finds.
   - Exists → call native `/gsd-ingest-docs --manifest .gsd-recipe/ingest-manifest.yaml` directly,
     in this same turn, same Option-B reasoning as steps 2-3.
   - Missing → **do not hard-fail and do not fabricate a manifest.** Print a plain warning, e.g.:
     "No `.gsd-recipe/ingest-manifest.yaml` found — skipping `/gsd-ingest-docs` this run. See
     `docs/netapp-recipe/contracts/DATA-CONTRACTS.md` § ingest-manifest.yaml for the expected
     shape if you want to add one." Then continue straight to step 5 — never block the other two
     native calls or the skeleton scaffolding in step 1 on this file's absence.

5. **Summarize**, in one final report to the operator: whether the `.knowledge/` skeleton was
   freshly created, partially filled in (naming which pieces were added), or already complete
   this run; confirmation that `/gsd-map-codebase [--fast]` and `/gsd-graphify build` were called;
   and the `/gsd-ingest-docs` result (`called` / `skipped-no-manifest`).

## D. Do NOT

- Do not wrap or invoke `gsd-extract-learnings`/`gsd-capture` — those stay `OBSERVER-LLD.md`'s
  pilot-scoped manual fallback ("use `gsd-capture --note` and `gsd-extract-learnings` manually if
  needed"), a different task/skill entirely, out of scope here. This skill wraps exactly the 3
  commands in steps 2-4, no more.
- Do not overwrite any existing file or directory content under `.knowledge/` (`index.md`,
  `log.md`, or anything already populated in `architecture/`, `dependency-graph/`, `hot-files/`,
  `risk-register/`) — scaffolding in step 1 is additive-only, filling gaps, never clobbering
  prior native-command output.
- Do not create, edit, or delete anything under `code_base_details/` — human-authored content this
  skill never touches; `/gsd-ingest-docs` reads it, this wrapper does not write it.
- Do not fabricate `.gsd-recipe/ingest-manifest.yaml` when it's missing — warn and skip that one
  step (step 4), never invent a manifest on the operator's behalf.
- Do not create, touch, or write to `.knowledge/dag/` — owned by `install.sh`'s own scaffolding
  and parked DAG work (TASK-009), not this task.
- Do not gate this skill behind a tracker/Jira sync step — `bench/recipe/trackers/jira-events.json`
  defines no event for a knowledge bootstrap/refresh (it is not a phase/epic milestone), so this
  skill never calls `gsd-jira-sync` and never touches `sync-ledger.sh`.
- Do not hard-block on any missing input anywhere in this workflow — the only conditionally
  skippable step is `/gsd-ingest-docs` (step 4); every other step always proceeds.
</cursor_skill_adapter>

# recipe-bootstrap-knowledge — knowledge bootstrap/refresh wrapper (TASK-022)

Recipe configuration on top of native GSD (`docs/netapp-recipe/lld/INSTALL-LLD.md` § "Populate
`.knowledge/` from GSD", tag **[N]** for the three underlying native calls, **[C]**/**[X]** for
this wrapper's idempotent `.knowledge/` skeleton scaffolding) — GSD stays the orchestrator; this
skill adds an idempotent OKF-shaped directory-skeleton check/fill and a direct, same-turn call to
all three native commands the spec names.

**Spec:** `docs/netapp-recipe/lld/INSTALL-LLD.md` § "Populate `.knowledge/` from GSD" ·
`docs/netapp-recipe/BACKLOG.md` TASK-022.

**Built standalone**, the same pattern already used by `recipe-prd-intake` (TASK-016),
`recipe-planning-policy` (TASK-012), `recipe-run-phase` (TASK-024), and `recipe-plan-phase`
(TASK-017) ahead of/alongside the full `install.sh` (TASK-010) — this skill has its own installer,
`.gsd-recipe/scripts/install-recipe-bootstrap-knowledge.sh`, intended to also be composed into
`install.sh` as a sub-installer in a follow-up integration pass (see the integration report for
the exact `install.sh` wiring snippet, held back from this task's own diff to avoid a merge
conflict with sibling tasks editing `install.sh` concurrently).

## Workflow

1. Check `.knowledge/index.md`, `log.md`, and the four subdirectories individually; scaffold only
   whichever pieces are missing, with minimal OKF-frontmatter placeholders — never overwrite
   anything that already exists. Never touch `.knowledge/dag/` or `code_base_details/`.
2. Call native `/gsd-map-codebase [--fast]` directly, in the same turn (Option B — the operator's
   own invocation of `recipe-bootstrap-knowledge` is the manual GSD trigger).
3. Call native `/gsd-graphify build` directly, in the same turn, same reasoning.
4. Check for `.gsd-recipe/ingest-manifest.yaml`. Present → call native `/gsd-ingest-docs
   --manifest .gsd-recipe/ingest-manifest.yaml` directly, same reasoning. Missing → warn and skip
   only this one step, never hard-fail, never fabricate a manifest.
5. Summarize the skeleton-fill result and all three native-call outcomes in one final report.

## Why Option B (direct same-turn calls), not a background/async trigger

Decision (approved, mirroring `recipe-plan-phase`'s and `recipe-run-phase`'s own precedent): the
operator's own act of invoking `recipe-bootstrap-knowledge` already is the "human decided to
bootstrap/refresh knowledge now" gate that `docs/netapp-recipe/lld/INSTALL-LLD.md` describes for
`/gsd-map-codebase`, `/gsd-graphify build`, and `/gsd-ingest-docs` ("After install, operator or
agent runs (once per repo, refresh on major change)…"). `docs/netapp-recipe/AGENTS.md` line 11's
standing rule — "User runs GSD skills manually — do not invoke `gsd-plan-phase`,
`gsd-execute-phase`, etc. on the user's behalf" — governs *autonomous*, unrequested invocation on
the operator's behalf. It does not forbid a skill the operator explicitly named and ran from
directly calling the native command(s) that skill exists to wrap, in the same turn, as its
documented job. This is the exact same reasoning `recipe-plan-phase-SKILL.md` and
`recipe-run-phase-SKILL.md` already establish for `gsd-plan-phase`/`gsd-execute-phase` — applied
here, unchanged, to `/gsd-map-codebase`, `/gsd-graphify build`, and `/gsd-ingest-docs`. Unlike
`recipe-prd-intake`'s deliberate *non*-invocation of `gsd-discuss-phase` (that skill explicitly
defers to the operator to run discuss themselves — see its own SKILL.md § D), this skill is
explicitly approved to call all three native knowledge commands on the operator's behalf, because
`recipe-bootstrap-knowledge` *is* the operator's request to bootstrap/refresh knowledge right now.

No new precedent is created by this task — it is a direct, narrow application of an
already-approved pattern to a third distinct trio of native commands.

## What this does NOT do (see the integration report for the full rationale)

- **No `gsd-extract-learnings`/`gsd-capture` wrapping.** `OBSERVER-LLD.md` line 14 explicitly
  names these as the pilot's manual fallback, a different task/skill's scope entirely. This skill
  is scoped to exactly the 3 commands `INSTALL-LLD.md`'s "Populate `.knowledge/` from GSD" section
  names, no more.
- **No `.knowledge/` overwriting.** The skeleton check in step 1 is strictly additive — it fills
  gaps in a possibly-partial `.knowledge/` tree, it never regenerates or clobbers anything that's
  already there (whether from a prior run of this skill, `install.sh`, or the native commands
  themselves).
- **No `code_base_details/` writes.** Human-authored content, read-only from this skill's
  perspective; `/gsd-ingest-docs` is the only thing that reads it.
- **No manifest fabrication.** A missing `.gsd-recipe/ingest-manifest.yaml` triggers a warn-and-
  skip of the ingest step only — never an invented manifest, never a block on the other two native
  calls.
- **No `.knowledge/dag/` involvement.** Owned by `install.sh`'s own scaffolding; DAG population
  itself is parked pending TASK-009 per `DECISIONS.md`.
- **No tracker/Jira sync.** There is no `jira-events.json` event for a knowledge bootstrap/refresh
  — it is not a phase/epic milestone, so this skill never calls `gsd-jira-sync`.

## Fail-open behavior

The only condition that changes this skill's behavior mid-run is `.gsd-recipe/ingest-manifest.yaml`
being absent — that skips step 4 alone, with a warning, and every other step (the skeleton fill,
`/gsd-map-codebase`, `/gsd-graphify build`) always runs regardless. There is no scenario in this
skill's documented workflow where it stops before completing all applicable steps.
