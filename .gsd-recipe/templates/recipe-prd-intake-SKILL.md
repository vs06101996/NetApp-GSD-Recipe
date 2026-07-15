---
name: recipe-prd-intake
description: "Recipe: PRD intake for the NetApp GSD recipe (TASK-016). Takes an operator-supplied PRD file, pasted text, or freeform description, fills in .templates/PRD.template.md, writes docs/PRD.md, and — as its final step — invokes fotw-observer-bootstrap so the FOTW observer starts watching this session."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-prd-intake`) with one of:
- a path to an existing PRD file to ingest,
- PRD text pasted directly into the conversation, or
- a freeform description of the feature/project to turn into a PRD.

No arguments are required to invoke it, but at least one of the three inputs
above must be available by the time step 2 of Tool Usage runs, or the skill
falls back to the "no PRD" path (see Do NOT).

## B. Prerequisites

- `.templates/PRD.template.md` exists (staged by
  `.gsd-recipe/scripts/install-recipe-prd-intake.sh`). If missing, tell the
  operator to run that installer first, then stop — do not fabricate a
  template inline.
- `docs/` directory may or may not exist yet — create it if needed.

## C. Tool Usage

1. `Read`: load `.templates/PRD.template.md` to get the required section
   list (Problem, Goals, Non-Goals, Requirements, Out of Scope; Open
   Questions is optional).
2. Resolve the input source:
   - File path given → `Read` it.
   - PRD text pasted inline → use it directly.
   - Freeform description only → draft a first-pass PRD against the
     template sections from that description.
   - Nothing at all → do not proceed to step 3; see Do NOT.
3. For any **required** template section that ends up empty or clearly
   underspecified, ask the operator a clarifying question before writing the
   file (human gate, per `RUNTIME-LLD.md` §1.a "Human gates: Operator
   confirms scope when template was incomplete and agent asked clarifying
   questions"). Do not guess and silently fill required sections.
4. `Read` (check first): if `docs/PRD.md` already exists, do not overwrite
   it silently — show the operator a diff/summary of what would change and
   get explicit confirmation before proceeding.
5. `Write`: `docs/PRD.md`, conforming to `.templates/PRD.template.md`'s
   section structure, with the template's leading HTML comment block
   removed.
6. Final step, always, once `docs/PRD.md` is written: invoke the
   `fotw-observer-bootstrap` skill. Do not inline its logic here — it owns
   its own guard (`can-spawn`) and its own subagent spec. If the observer
   isn't installed or is disabled, that skill silently no-ops; treat that as
   success for this skill's own purposes, not an error.

## D. Do NOT

- Do not implement `.planning/STATE.md` epic-key stamping ("Stamps:
  `started` @ `intake`" in `RUNTIME-LLD.md`) — that depends on conventions
  TASK-002 (`parse-state`) / TASK-008 (`state-tracker.sh`) haven't defined
  yet. Out of scope for this skill; do not invent an ad hoc STATE.md format.
- Do not implement the `gsd-ingest-docs --manifest` "existing repo docs"
  intake path — if the operator wants that, tell them to run native
  `gsd-ingest-docs` first and bring you the result as pasted text or a file.
- If given no PRD input at all, do not silently invent one and do not call
  `gsd-discuss-phase` on the operator's behalf — tell them to run native
  `gsd-discuss-phase` first, then re-invoke `recipe-prd-intake` with its
  output. GSD stays the orchestrator (`ARCHITECTURE.md` principle); this
  skill is a thin recipe wrapper, not a replacement for native GSD commands.
- Do not skip step 6 (invoking `fotw-observer-bootstrap`) even if you're
  unsure whether the observer is installed — that skill's own guard handles
  the "not installed" case safely and silently.
- Do not overwrite an existing `docs/PRD.md` without operator confirmation.
</cursor_skill_adapter>

# recipe-prd-intake — PRD intake (TASK-016)

Recipe configuration on top of native GSD (`RUNTIME-LLD.md` §1.a, tag
**[C]**) — GSD stays the orchestrator; this skill only adds the
recipe-specific template conformance and the observer trigger on top of it.

**Spec:** `docs/netapp-recipe/lld/RUNTIME-LLD.md` §1.a · `docs/netapp-recipe/BACKLOG.md` TASK-016.

**Built standalone, ahead of TASK-010** (`install.sh`, size L, not yet
built), the same way the FOTW observer was built standalone ahead of its own
formal schedule — see
`bench/report/fotw-observer-install-integration-report.md`. This skill does
not require `install.sh`; it has its own installer,
`.gsd-recipe/scripts/install-recipe-prd-intake.sh`.

## Workflow

1. Get a PRD from the operator (file, pasted text, or freeform description).
2. Fill in `.templates/PRD.template.md`'s sections; ask clarifying questions
   for anything required and missing.
3. Write `docs/PRD.md` (never overwrite an existing one without asking).
4. Invoke `fotw-observer-bootstrap` — the one-line integration point that
   skill's own docs describe as its intended caller.

## Why `docs/PRD.md` and not `.planning/intake/PRD.md`

`RUNTIME-LLD.md` allows either artifact path. `docs/PRD.md` is picked as the
primary target here because it's the first path the FOTW observer's
reactive hook (`.cursor/hooks/fotw-observer-nudge.sh`) already matches on —
keeping this skill's output aligned with what the rest of the stack already
watches for, with no hook changes required.

## What's deferred (see the integration report for the full list)

- `.planning/STATE.md` epic-key stamping (needs TASK-002/TASK-008).
- `gsd-ingest-docs --manifest` routing for existing-repo-docs intake.
- The full TASK-010 `install.sh` (this skill's installer is a narrower,
  standalone fallback per `INSTALL-LLD.md` Step 3's documented pattern).
