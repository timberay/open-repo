# Essential Follow-up — 2026-06-08

## Current Findings

1. V2 pagination `Link` headers did not URL-encode cursor values.
   - Catalog cursors can contain `/` because repository names support namespaces such as `team/app`.
   - Tag cursors can contain `:` because tag names support colon-like reference strings in this codebase.
   - Impact: clients following `Link` could parse the cursor incorrectly or produce ambiguous URLs.
   - Status: fixed in this change.

2. The 2026-06-07 full audit document is stale for several previously critical findings.
   - OAuth re-verification, upload UUID scoping, Content-Range validation, referenced blob delete protection, and README OCI/anonymous-pull alignment are already fixed in current code.
   - Impact: operationally low, but the document can mislead prioritization.
   - Status: documented here; no production-code change needed.

3. PullEvent audit rows are intentionally collected for retention/analysis but are not exposed in the Web UI.
   - README already says they are "not currently shown in the UI".
   - Impact: not a contradiction, but still a product gap if operators need per-pull browsing.
   - Status: not implemented in this pass because the README scopes it as retained analysis data, not a shipped UI feature.

## Goal Prompt Used

Improve the highest-confidence essential gap discovered during the 2026-06-08 project review: make Docker Registry V2 pagination `Link` headers safe and spec-friendly by URL-encoding cursor query values and preserving valid repository path segments. Add focused controller tests for catalog namespace cursors and tag cursors containing reserved characters. Keep the change small, avoid unrelated refactors, run targeted Rails tests and the available CI checks, then commit and push to `main`.
