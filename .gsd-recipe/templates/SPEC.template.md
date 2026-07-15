<!--
SPEC template — canonical source staged into target repos at
`.templates/SPEC.template.md` by `.gsd-recipe/scripts/install.sh` (TASK-010).

Per docs/netapp-recipe/lld/INSTALL-LLD.md's directory tree, this sits
alongside PRD.template.md/TDD.template.md as recipe-committed scaffolding.

NOTE (confirmed via search of RUNTIME-LLD.md at TASK-010 build time): no
runtime consumer (`recipe-plan-phase` or otherwise) references this template
yet — it is authored ahead of its consumer, same precedent as the FOTW
observer/tracker-sync installers landing ahead of TASK-010 itself. Flagged
explicitly in bench/report/install-scaffold-integration-report.md so it isn't
mistaken for an oversight.

Delete this comment block when filling in a real spec.
-->

# SPEC: {Feature / Component Name}

## Problem

What gap does this spec close? Link back to the PRD requirement(s) it serves.

## Scope

What's in scope for this spec, and what's explicitly deferred?

- In scope:
- Deferred:

## Design

The concrete approach: data shapes, interfaces, control flow. Prefer
diagrams/tables over prose where they clarify faster.

## Interfaces

Inputs, outputs, and contracts this spec exposes to callers (CLI flags,
function signatures, file formats).

## Testing

How this spec's implementation will be validated — unit tests, integration
fixtures, manual smoke steps.
