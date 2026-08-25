# E2E new-hire onboard — required knowledge + GSD install (2026-08-24)

**Agent:** [Fresh new-hire deep verification](0d851d2d-7c91-4265-b1a9-362ee06344dd)  
**Target:** `~/Projects/recipe-sandbox-e2e-required-knowledge`  
**Route:** `recipe-onboard --skip-tracker` · Hello Widget CLI dummy feature

## Verdict

| Layer | Result |
|-------|--------|
| Subagent onboard chain | **PARTIAL** — artifacts present, marker written, next step correct |
| Recipe contract (post-fix) | **Would FAIL closed** — marker-only readiness no longer counts |

## What the subagent proved (good)

- Five-step preview gate worked (`--skip-tracker` skipped Jira only).
- Core artifacts created: `docs/PRD.md`, `.planning/*`, `onboard.skip_tracker`.
- `recipe-next` → `recipe-plan-phase 1` (correct after onboard).
- Cursor GSD full profile available globally (`agents_installed: true` after installer fix).

## Gaps found (addressed in follow-up)

1. **No-op `graphify` stub** at `~/bin/graphify` (`exit 0` only) passed install preflight but produced no graph files.
2. **Marker-only readiness** — agent wrote `KNOWLEDGE-BOOTSTRAPPED` without verified graph output; status showed `Knowledge: yes`.
3. **Inline planning/map** — native `gsd-new-project` / `gsd-map-codebase` not invoked end-to-end (agent shortcut).
4. **`fotw-observer-bootstrap`** skipped after PRD intake (existing skill gap, not blocking planning).

## Follow-up shipped

| Change | Effect |
|--------|--------|
| `bench/lib/graphify-probe.sh` | Detect no-op stubs; require `graphify --help` output |
| `install.sh` | Cursor GSD hard prereq + TLS-verified npm tarball fallback; graphify uses functional probe |
| `install-graphify.sh` | Removes stub, installs real `graphifyy` via `uv` |
| `recipe-bootstrap-knowledge` | Must verify `.planning/codebase/*.md` **and** graph artifacts before marker |
| `recipe-next` / `recipe-status` | `knowledge_ready()` requires marker + map + graph files |
| **`recipe_knowledge.py`** | Single source of truth for readiness checks |
| **`recipe-verify-knowledge.sh`** | Fail-closed CLI; `--write-marker` is the only supported marker write path |
| **`recipe-verify-planning.sh`** | Fail-closed planning artifact checks after `recipe-new-project` |
| DATA-CONTRACTS | Documents three-part readiness contract + guardrail scripts |

## Regression

- `test-install.sh`: **157 passed**
- Focused guardrail suite (`test-recipe-verify-knowledge.sh`): **8 passed**
- Focused suites (onboard, bootstrap, next, status, new-project): **136 passed**

## Remaining friction (not fixed this pass)

- Agents may still shortcut native GSD skills unless enforced at runtime (skill compliance, not script-enforced).
- `fotw-observer-bootstrap` optional chain after PRD intake.
- Jira check still `pending` until `recipe-install-verify` (expected for no-Jira sandbox).

## Recommended re-test

In a clean sandbox after `install-recipe-to-target.sh`:

```text
recipe-onboard --skip-tracker
recipe-status
```

Expect `Knowledge: yes` only when `.planning/codebase/*.md` (≥2 substantive docs) **and**
`.planning/graphs/` (or `graphify-out/`) contain files **and** `graphify` is not a stub.

Use `.gsd-recipe/scripts/recipe-verify-knowledge.sh --target .` to audit readiness.
Never hand-write `KNOWLEDGE-BOOTSTRAPPED`; use `--write-marker` only after native map + graphify.
