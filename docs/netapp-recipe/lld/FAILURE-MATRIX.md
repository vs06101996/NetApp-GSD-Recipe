# NetApp GSD Recipe — Failure Matrix

**Goal:** one-page lookup for cross-cutting failure/recovery behavior across install, runtime, observer, and traceability flows.

---

| Condition | User-visible behavior | GSD continues? | Sync behavior | Recovery action | Stamp/comment? |
|-----------|-----------------------|----------------|---------------|-----------------|----------------|
| Jira MCP down | Sync step reports tracker post failure; work artifacts still created | Yes | Queue event in `.gsd-recipe/sync-queue.jsonl` | Re-auth MCP; run reconcile/drain again | No tracker comment until recovery; no ledger append on failed post |
| GitHub / `gh` auth fail | `recipe-pr-comment`/`gh pr comment` fails with auth error | Yes | Keep pending GitHub event (queue or manual retry) | `gh auth login`/refresh token; re-run draft+comment | No PR comment until retry; no ledger append on failed post |
| Ledger write fails after successful post | Comment appears externally but local dedup uncertain | Yes | Next reconcile may not see posted key | Retry ledger append; run one manual dedup check before replay | Comment posted; stamp may exist; add `duplicate_skipped` once ledger repaired |
| CI red at settle gate | `recipe-settle` blocks completion | Yes (feature remains open) | No `settled` event should be posted | Fix CI, rerun checks, then settle | `settled` stamp/comment blocked until CI green + PO accept |
| DAG cycle detected | Plan/execute blocked with cycle error artifact | No for affected phase flow | No new phase sync events for blocked phase | Fix `depends_on`, rebuild DAG | No phase-complete comment while blocked |
| DAG file conflict (parallel phases) | Warning or block (policy-dependent) on overlapping file ownership | Usually yes after explicit override | Sync allowed only after execution resumes | Adjust phase boundaries or set explicit override | Normal comments resume post-execution |
| ic-* double orchestrator detected | Operator warning about mixed orchestrators | No (recipe flow should pause) | Disable recipe sync while conflict unresolved | Choose one orchestrator; set policy in config/runbook | Avoid duplicate comments/stamps; no settle until resolved |
| GSD `.planning/` corrupt | Planning commands fail; state parsing unavailable | No until repaired | Sync cannot resolve routing safely | Run `/gsd-health --repair`; restore required files | No sync post while STATE/planning unreadable |
| `recipe-sync` queue backlog growth | Pending entries accumulate; delayed external visibility | Yes | Queue grows; near-RT SLA degrades | Restore auth/connectivity; run drain loop in batches | Delayed comments/stamps post once drained |
| bootstrap / `bare_metal` fail | Gate A/B fails; verify/ship blocked per runbook | Yes for investigation; no settle | Verify-related sync may indicate failure/rework only | Run `gsd-debug` loop, fix environment, re-run gate | No final settle comment; optional reopened comment/stamp |

---

## Policy alignment

- **Fail closed on credentials/tokens:** no silent posting when auth is invalid.
- **Continue GSD on sync failure:** development can proceed; sync catches up after recovery.
- **No settle without human + CI gate:** unchanged from runtime/traceability contracts.

For phase-specific details, see:

- [RUNTIME-LLD.md](RUNTIME-LLD.md)
- [TRACEABILITY-LLD.md](TRACEABILITY-LLD.md)
- [OBSERVER-LLD.md](OBSERVER-LLD.md)
