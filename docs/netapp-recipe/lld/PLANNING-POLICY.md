# Planning policy

Mandatory **7 sections** for GSD `PLAN.md` files. Used by TASK-012 (`recipe-planning-policy` skill).

Related: [RUNTIME-LLD](RUNTIME-LLD.md) · [DECISIONS.md](../DECISIONS.md)

**Note:** On Instaclustr `app`, **ic-*** is the production orchestrator — do not run recipe there. This policy applies to GSD-first / recipe pilots.

---

## Mandatory plan sections

1. **Problem restatement** — from Jira, in your own words
2. **Proposed approach** — high-level, reversible where possible
3. **Security considerations** — trust boundaries, auth, data handling
4. **Performance considerations** — latency, scale, resource limits
5. **Expected review concerns** — pre-answer likely pushback
6. **Validation / testing strategy** — CI + project checks (not `gsd-verify-work` alone)
7. **Learning extraction opportunities** — reusable patterns after merge

### GSD mapping

| Section | Artifact |
|---------|----------|
| Problem + approach | `CONTEXT.md`, `PLAN.md` |
| Security | `gsd-plan-phase` threat model; optional `gsd-secure-phase` |
| Validation | Project CI; benchmark grader when registered |
| Learnings | `gsd-extract-learnings` → `.sdlc/patterns/repo/` |

---

## Per-phase prerequisite workflow

Every phase plan must, before its own new-work sections:

1. **Verify** the prior phase's declared deliverables are actually present and passing — not assumed. Re-run the relevant tests/checks; re-read the artifact if no automated check exists.
2. **Close any gap found** — develop the missing/broken prerequisite as part of this phase's own scope, not a silently-deferred TODO.
3. **Update/extend unit tests** to cover the (re-)verified or newly-closed prerequisite, so the next phase inherits a genuinely tested baseline, not just a re-asserted one.
4. **Fill the Prerequisites table** below in the phase's own `PLAN.md` before any new-work sections:

| Prerequisite | Delivered by (phase/task) | Verified? | Gap found | Resolution |
|---|---|---|---|---|
| *(one row per prior-phase deliverable this phase depends on)* | | yes/no | describe, or "none" | how it was closed, or "n/a" |

This table is mandatory even when every prerequisite checks out clean (`Gap found: none`, `Resolution: n/a` rows are still expected, not omitted) — the point is to force the verification step to actually happen, not just to record failures.

---

## Supporting artifacts (SPEC.md / TDD.md)

Net-new work needs a real spec/design record before code, not just a jump straight to implementation:

- If a formal LLD spec **already exists** for the deliverable (true for most backlog tasks today — see each `BACKLOG.md` row's `Spec` column), cite it directly in the plan. No duplicate spec needed.
- If **no LLD spec exists yet**, fill `.templates/SPEC.template.md` (and `.templates/TDD.template.md` for anything with a non-trivial design decision) before finalizing the plan. These templates are staged into every recipe-installed repo by `install.sh` (TASK-010) specifically for this purpose.

---

## Context gathering before planning

Before drafting a plan, check for relevant prior decisions/learnings so the plan doesn't repeat already-settled ground:

1. Read `.knowledge/log.md` and `.knowledge/index.md` for relevant prior entries.
2. If `graphify.enabled` is `true` in `.planning/config.json`, also attempt a `gsd-graphify query <topic>` pass for the phase's subject area.
3. This step is **soft** — if `graphify.enabled` is `false`/absent, or the `graphify` CLI is unavailable, skip step 2 gracefully and proceed with just the `.knowledge/` read. Consistent with graphify's optional/warn-only status established in `install.sh`'s own prerequisite bootstrap — this policy never makes graphify a hard blocker on planning.

---

## Review gates

| Gate | When |
|------|------|
| Plan review | Before `gsd-execute-phase` |
| Security / performance | After implementation; CRITICAL blocks ship |
| Settled | PO + CI green |

Use `actor=human` on stamps when a human gate clears.

---

## Avoid

- Skipping plan sections for speed
- Hyper-specific learnings in org-global patterns
- Treating `gsd-verify-work` as production sign-off
