# Roadmap: GSD-dialect fixture (heading-mismatch regression)

Mirrors the actual output shape of `gsd-new-project`/`gsd-plan-phase`
(get-shit-done/templates/roadmap.md's "## Phase Details" section): phase
headings are H3 with a colon separator (`### Phase N: Title`), nested under a
`## Phase Details` H2, and the goal line is `**Goal**:` (colon *outside* the
bold), not this repo's own `## Phase N — Title` / `**Goal:**` dialect.

## Phases

- [ ] **Phase 1: Foundation** - Core types and store
- [ ] **Phase 2: HTTP API** - JSON endpoints

## Phase Details

### Phase 1: Foundation

**Goal**: A `Task` type and in-memory store exist and are proven correct by unit tests
**Depends on**: Nothing (first phase)

### Phase 2: HTTP API

**Goal**: Clients can read and create tasks over HTTP using JSON
**Depends on**: Phase 1

## Progress

| Phase | Status |
|-------|--------|
| 1. Foundation | Complete |
| 2. HTTP API | Complete |
