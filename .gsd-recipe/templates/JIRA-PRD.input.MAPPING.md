# Jira / Confluence PRD input → canonical `docs/PRD.md`

**Input formats** accepted by `recipe-prd-intake`:

| Source | Example |
|--------|---------|
| File following `.templates/JIRA-PRD.input.template.md` | `docs/input/my-feature-prd.md` |
| Confluence PRD export (markdown or pasted) | NetApp 15-section PRD pages |
| Jira Epic body that uses the same headings | Paste from Epic description |
| Already-canonical PRD | Matches `.templates/PRD.template.md` |
| Freeform | Short feature description in chat |

**Output:** always `.templates/PRD.template.md` shape at `docs/PRD.md` — never write the
15-section Jira/Confluence form to `docs/PRD.md`.

## Section mapping

| Jira / Confluence input | Canonical `docs/PRD.md` section | Notes |
|-------------------------|----------------------------------|-------|
| Epic summary or first line under `# 1. Objective` | `# PRD: {Feature / Project Name}` | Prefer Epic summary when provided |
| `# 1. Objective`, `## 1.1. Value Proposition` | `## Problem` | Combine into one narrative |
| `# 1. Objective` success outcomes, `## 1.4. Implementation Phases` (in-scope phases) | `## Goals` | Bulleted, checkable outcomes |
| `# 7. Product Non-Requirements`, explicit "will not" items | `## Non-Goals` | What we are not doing |
| `# 5. Product Feature Requirements` (especially `## 5.1. Functional Requirements`) | `## Requirements` | Numbered MUST/SHOULD items; preserve phase tags inline |
| `# 1.4` future phases, `# 7`, deferred `# 5.x` marked future | `## Out of Scope` | Adjacent work deferred |
| `# 12. Open Issues` (unresolved rows) | `## Open Questions` (optional) | Skip resolved rows |

Sections **not copied verbatim** into canonical PRD (use only as intake context):

- `# 2. Related Documents`, `# 3. Terminology`
- `# 6. Feature Interaction Requirements` (matrix → summarize conflicts in Requirements or Open Questions)
- `# 8`–`# 11` (UI, API, RAS, Security) → distill into Requirements bullets where testable
- `# 13`–`# 15` (Revision History, Approvals, Reviewers)

## Detection hints

Treat input as Jira/Confluence PRD when **two or more** match:

- Headings like `# 1. Objective` or `# 5. Product Feature Requirements`
- `Product Non-Requirements` or `Functional Requirements` under section 5
- Numbered top-level sections 1–15 from the NetApp Confluence template

When ambiguous, ask the operator whether the source is a Jira/Confluence PRD export.

## Human gate

Required canonical sections still missing after mapping → ask clarifying questions before
writing `docs/PRD.md` (same gate as any other intake path).
