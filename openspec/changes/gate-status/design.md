# Design: gate-status

## Capabilities Affected

- `pdlc-safety` (extended — gate observability; same home as the drift canary)

## Constraints (recorded 2026-07-15, post-audit triage item 2)

(a) Source the guard's OWN evidence libs and mirror `openspec-guard.sh`'s
decision ORDER — never reimplement parsing. Parallel interpretation drifts:
the status tool would say "clear" while the guard denies, which is worse than
no tool. Enforced by construction (`command -v` guards around lib functions,
no jq re-parsing of verdict/ledger artifacts) and by the anti-drift anchors in
`tests/test-gate-status.sh`.

(b) Purely observational — exit 0 always; output never wired into enforcement.
The guard remains the only decider.

(c) `docs/enforcement-map.md` folded into the SAME change; `--help` ≈ map,
pinned by shared-phrase assertions so they cannot drift silently.

(d) Staleness-delta observation line (files/lines since review SHA,
docs-vs-source split) via the shared classifier, to keep collecting live data
for the DEFERRED deny-vs-warn decision. The pre-registered backtest
(`backtest-protocol.md`, sealed at commit 835d19a BEFORE data collection)
found: V1 naive 94%, V2 docs-exempt 83%, V3 size>25 56% would-fire rates and
ZERO defects attributable to post-review deltas across all 108 merged PRs
(fix-PR archaeology, line-level attribution). Advisory stands; deny stays
deferred.

## Decisions

- Token resolution: no stdin payload exists for a user-run script, so the
  session token comes from the shared singleton (caveat printed inline);
  verdict reads go through `verdict_resolve_token` (commit-bound bridge,
  #97) exactly like the guard.
- Gate 1 (compound mutate-then-push) is per-command, not per-state — reported
  as a rule reminder, not replayed.
- Classifier docs-set (`docs/**`, `openspec/**`, `*.md`) is frozen with the
  backtest protocol; changing it requires a re-registered backtest.

## Out-of-Scope

- Any enforcement coupling (exit codes, hook wiring) — constraint (b).
- Hardening REVIEW staleness to deny — explicitly rejected by the backtest
  under the pre-registered decision rule.
- Live-hook introspection for the unexplained-deny investigation.
- JSON output mode (add if a consumer materializes).

## Acceptance Scenarios

Provenance: constraints (a)–(d) from the post-audit triage memory
(2026-07-15); backtest numbers from `backtest-results.md`.

- WHEN `bash scripts/gate-status.sh` runs on a branch with no REVIEW/VERIFY
  records THEN it reports WOULD DENY at the global fail-closed gate, names
  both missing milestones, and exits 0.
- WHEN ledger milestones exist and a clean verdict sits at HEAD in a routing
  repo THEN every replayed gate reports pass and the summary says WOULD ALLOW.
- WHEN the verdict at HEAD reports failing gates and verification is in the
  active chain THEN the replay denies at verify-hardening (gate 4) before
  gates 5/6 — the guard's order.
- WHEN the review ledger SHA is an ancestor of HEAD THEN the staleness line
  prints the shared classifier's `files=… docs_files=… src_files=…` split and
  frames it as observation only.
- WHEN `--help` output and `docs/enforcement-map.md` are compared THEN the
  pinned shared phrases are present in both (drift gate).
