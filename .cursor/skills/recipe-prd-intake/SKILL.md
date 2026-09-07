---
name: recipe-prd-intake
description: "Recipe: PRD intake for the NetApp GSD recipe (TASK-016). Accepts a Jira issue key or browse URL (fetched via Atlassian MCP), Jira/Confluence PRD exports, canonical PRD files, pasted text, or freeform description; maps input to .templates/PRD.template.md; writes docs/PRD.md; invokes fotw-observer-bootstrap as its final step."
---

<cursor_skill_adapter>
## A. Skill Invocation

Invoke by name (`recipe-prd-intake`) with one of:
- a **Jira issue key or browse URL** (e.g. `KAN-53` or
  `https://netapp.atlassian.net/browse/KAN-53`) — fetched via Atlassian MCP,
- a path to an existing PRD file to ingest (Jira/Confluence export, canonical PRD, or
  a draft following `.templates/JIRA-PRD.input.template.md`),
- PRD text pasted directly into the conversation, or
- a freeform description of the feature/project to turn into a PRD.

No arguments are required to invoke it, but at least one of the inputs
above must be available by the time step 2 of Tool Usage runs, or the skill
falls back to the "no PRD" path (see Do NOT).
If the argument is an existing file path, treat it as a file even if the name
looks like a Jira key. Otherwise, if it matches a Jira key or issue URL,
fetch it (do not treat the URL string as the PRD body).

## B. Prerequisites

- `.templates/PRD.template.md` exists (staged by
  `.gsd-recipe/scripts/install-recipe-prd-intake.sh`). If missing, tell the
  operator to run that installer first, then stop — do not fabricate a
  template inline.
- `.templates/JIRA-PRD.input.template.md` and
  `.templates/JIRA-PRD.input.MAPPING.md` (Jira/Confluence **input** shapes —
  staged by the same installer). If missing, still run intake using
  `PRD.template.md` only; mention the Jira input templates are optional.
- `docs/` directory may or may not exist yet — create it if needed.
- Atlassian MCP enabled and authenticated — required only when the input is a
  Jira issue key or browse URL.

## C. Tool Usage

1. `Read`: load `.templates/PRD.template.md` to get the required **output**
   section list (Problem, Goals, Non-Goals, Requirements, Out of Scope; Open
   Questions is optional).
2. `Read`: load `.templates/JIRA-PRD.input.MAPPING.md` when present — it defines
   how NetApp Jira/Confluence PRD exports map into the canonical sections.
3. Resolve the input source (first match wins):
   - Argument is an existing file path → `Read` it.
   - Argument is a Jira issue key (`[A-Z][A-Z0-9]+-\\d+`) or a Jira issue URL
     (`/browse/KEY`, `/issues/KEY`, or `selectedIssue=KEY`) → **fetch, do not
     paste the URL as the PRD.** Resolve `bench/lib/parse-jira-issue-ref.sh`
     via `.gsd-recipe/scripts/recipe-paths.sh resolve` when that helper exists;
     otherwise apply the same parse rules. Then:
     1. Discover MCP tools (`GetDynamicTools` / `GetMcpTools`) for the
        Atlassian Jira namespace.
     2. `getAccessibleAtlassianResources` if `cloudId` is not already known;
        use the site hostname from the browse URL when present
        (e.g. `netapp.atlassian.net`).
     3. `getJiraIssue` with `issueIdOrKey` = the parsed key,
        `responseContentFormat` = `markdown`, fields at least
        `summary`, `description`, `issuetype`, `status`.
     4. Build intake text: title from `summary`, body from `description`
        (markdown). If description is empty, use summary only and ask
        clarifying questions for required PRD sections.
     5. Fetch failure (no MCP, 404, auth) → **stop**. Do not invent a PRD
        from the key/URL string. Tell the operator to paste the description
        or authenticate Atlassian MCP.
   - PRD text pasted inline → use it directly.
   - Freeform description only → draft a first-pass PRD against the
     template sections from that description.
   - Nothing at all → do not proceed to step 4; see Do NOT.
4. Classify the input shape:
   - **Jira/Confluence PRD** — headings like `# 1. Objective`, `# 5. Product
     Feature Requirements`, or `Product Non-Requirements` (see MAPPING.md).
     Map sections into the canonical `PRD.template.md` structure using
     `.templates/JIRA-PRD.input.MAPPING.md`. Do **not** copy all 15 sections
     into `docs/PRD.md`.
   - **Already canonical** — input already matches `PRD.template.md` section
     names → normalize lightly (remove HTML comments, fix heading levels).
   - **Freeform / partial** → draft directly against `PRD.template.md`.
5. For any **required** canonical section that ends up empty or clearly
   underspecified after mapping, ask the operator a clarifying question before writing the
   file (human gate, per `RUNTIME-LLD.md` §1.a "Human gates: Operator
   confirms scope when template was incomplete and agent asked clarifying
   questions"). Do not guess and silently fill required sections.
6. `Read` (check first): if `docs/PRD.md` already exists, do not overwrite
   it silently — show the operator a diff/summary of what would change and
   get explicit confirmation before proceeding.
7. `Write`: `docs/PRD.md`, conforming to `.templates/PRD.template.md`'s
   section structure only, with the template's leading HTML comment block
   removed. Never write the 15-section Jira/Confluence form to `docs/PRD.md`.
8. Final step, always, once `docs/PRD.md` is written: invoke the
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
- Do not skip step 8 (invoking `fotw-observer-bootstrap`) even if you're
  unsure whether the observer is installed — that skill's own guard handles
  the "not installed" case safely and silently.
- Do not overwrite an existing `docs/PRD.md` without operator confirmation.
- Do not write Jira/Confluence 15-section PRD structure to `docs/PRD.md` —
  that input shape is for intake only; output is always canonical
  `PRD.template.md`.
- Do not invent a PRD from a Jira key or browse URL string. Fetch via
  `getJiraIssue` or stop. Do not treat a URL as file contents unless that
  path exists on disk.
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

1. Get a PRD from the operator (Jira issue key or browse URL via Atlassian MCP,
   Jira/Confluence export, file, pasted text, or freeform description).
2. If input matches the NetApp Jira/Confluence PRD shape, map it using
   `.templates/JIRA-PRD.input.MAPPING.md`; otherwise fill
   `.templates/PRD.template.md`'s sections directly.
3. Ask clarifying questions for anything required and missing.
4. Write `docs/PRD.md` in **canonical** form only (never overwrite without asking).
5. Invoke `fotw-observer-bootstrap` — the one-line integration point that
   skill's own docs describe as its intended caller.

## Jira / Confluence input (not output)

NetApp teams often start from the official Confluence PRD template (15 numbered
sections). That shape is staged as **input only**:

- `.templates/JIRA-PRD.input.template.md` — skeleton for exports/pastes
- `.templates/JIRA-PRD.input.MAPPING.md` — how sections become Problem, Goals,
  Requirements, etc.

`recipe-create-epic` still reads **canonical** `docs/PRD.md` when drafting the
Epic body — same as today.

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
