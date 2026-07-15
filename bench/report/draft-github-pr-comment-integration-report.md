# `draft-github-pr-comment.sh` + templates (TASK-006)

**Picked next per the user's explicit ordering** (TASK-015 → TASK-008 →
TASK-006), after both formalize-only tasks were fully closed out. Unlike
those two, `BACKLOG.md` and the investigation confirm this task is genuinely
unbuilt: only a reference/draft copy existed under
`docs/netapp-recipe/reference/harness/`, and none of it had been copied into
`bench/` yet — the exact same gap TASK-003's report closed for the Jira side
(see that report's "Bundle copy" row), just not yet closed for GitHub.

## Bundle copy

Same precedent as TASK-003's Jira bundle copy, applied to the GitHub side:

| Reference (canonical, share bundle) | `bench/` copy (this task) |
|---|---|
| `docs/netapp-recipe/reference/harness/runners/draft-github-pr-comment.sh` | `bench/runners/draft-github-pr-comment.sh` |
| `docs/netapp-recipe/reference/harness/recipe/trackers/github-events.json` | `bench/recipe/trackers/github-events.json` |
| `docs/netapp-recipe/reference/harness/recipe/templates/github-pr-comments/_comment.template.md` | `bench/recipe/templates/github-pr-comments/_comment.template.md` |

Copied verbatim first, then polished in place (see below) — same order TASK-003
followed for `draft-jira-comment.sh`.

## Polish/review — treated as a real code-review pass, not a blind copy

Read the full script against `draft-jira-comment.sh`'s equivalent logic
(idempotency key format, error handling for unknown `event_id`, missing
required args) and against `TRACEABILITY-LLD.md`'s script-role table, which
is explicit that `draft-github-pr-comment.sh` is **"stdout only; then `gh pr
comment`"** — same draft/post separation as the Jira side. Confirmed the
copied script honors that: it never shells out to `gh`, only prints to
stdout.

### Real bug found and fixed: hardcoded `commit=HEAD` in the idempotency key

The script computes an `{{IDEMPOTENCY_KEY}}` value and renders it into the
comment body's `### Idempotency` section — a feature `draft-jira-comment.sh`
doesn't even attempt (its template has no such placeholder; the real ledger
key is computed separately by `sync-ledger.sh`). The GitHub template does
try to preview the real ledger key, but the reference copy computed it with:

```python
short_sha = "HEAD"
...
idem += f":commit={short_sha}:issue={issue}"
```

`short_sha` was a literal string, never the actual commit — so every drafted
comment's displayed idempotency key silently claimed `commit=HEAD`
regardless of which commit actually triggered the event. If an operator ever
cross-checked this displayed key against what `sync-ledger.sh key <event>
<issue> --phase N --wave W --commit "$(git rev-parse --short HEAD)"` would
really compute, the two would only coincidentally match. This is a real bug,
not a naming mismatch — fixed minimally by resolving the actual short SHA via
`git rev-parse --short HEAD` (reusing the same `repo_root`/subprocess pattern
already used by the script's own `git_log()` helper), falling back to the
literal `"HEAD"` only if `git rev-parse` itself fails (e.g. no commits yet).

No other logic was changed — argument parsing, required-arg validation,
unknown-`event_id` handling, and the wave-conditional key segment were all
reviewed and found already correct (see validation table below).

## Validation performed

Local dry-run/fixture-based testing only — no live `gh pr comment` post, no
real GitHub PR. Per `BACKLOG.md`'s own "Testing" section, live posting is
explicitly "Manual only" and out of scope for CI/regression acceptance; stdout-only
local testing is the correct level of validation here, matching how
`sync-reconcile.sh --dry-run` was validated for the Jira side.

| # | Check | Result |
|---|---|---|
| 1 | `execute_wave` renders without error, body has event/PR/phase/issue/idempotency fields | PASS |
| 2 | `execute_complete` renders without error, same fields | PASS |
| 3 | `review_complete` renders without error, same fields | PASS |
| 4 | `phase_complete` renders without error, same fields | PASS |
| 5 | Missing `--pr` fails non-zero with `--pr and --phase are required` | PASS |
| 6 | Missing `--phase` fails non-zero, same error | PASS |
| 7 | Missing `event_id` entirely fails non-zero with `event_id required` | PASS |
| 8 | Unknown `event_id` fails non-zero with `Unknown event_id: <id>` | PASS |
| 9 | `--wave` present adds a `:wave=N` segment to the idempotency key | PASS |
| 10 | `--wave` absent omits the `:wave=` segment entirely | PASS |
| 11 | `--issue` omitted falls back to the `TBD-ISSUE` placeholder (documents actual behavior) | PASS |
| 12 | Idempotency key's `commit=` segment is the real short SHA, not the literal `HEAD` (regression guard for the fixed bug) | PASS |
| 13 | Rendered body includes the template's `### Changes` section (git log) | PASS |

All 13 assertions in `bench/tests/test-draft-github-pr-comment.sh` pass.

## Explicitly deferred (do not mistake for oversights)

| Deferred | Why |
|---|---|
| Actual `gh pr comment` posting | Out of this task's scope per `TRACEABILITY-LLD.md`'s script-role table (`draft-github-pr-comment.sh` is "stdout only; then `gh pr comment`" — posting is a separate step by design, same draft/post split as `draft-jira-comment.sh`/`gsd-jira-sync`). |
| GitHub-side idempotency drain (append `target: github` rows to `.gsd-recipe/sync-ledger.jsonl` after a real post) | Unlike TASK-003 (whose posting/draining explicitly deferred to TASK-005, which exists and is built), there is **no GitHub-side drain task in `BACKLOG.md` at all yet** — this isn't deferred to a named future task, it's simply outside the scope of any task that exists today. |
| Rewriting `sync-reconcile.sh`/`sync-drain-queue.sh` to detect/drain GitHub events | Those scripts stay Jira-literal per TASK-014's own deferred scope (see `tracker-sync-integration-report.md`) — GitHub tracker-sync was explicitly named there as blocked on this task landing, not the other way around. |

## Files

- `bench/runners/draft-github-pr-comment.sh` (bundle copy + idempotency-key bug fix)
- `bench/recipe/trackers/github-events.json` (bundle copy, unchanged)
- `bench/recipe/templates/github-pr-comments/_comment.template.md` (bundle copy, unchanged)
- `bench/tests/test-draft-github-pr-comment.sh` (new — 13 assertions)
