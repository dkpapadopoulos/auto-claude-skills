# Proposal: Gating milestones require invocation evidence (no walker back-fill)

## Why

The activation-hook composition walker back-fills all predecessor steps of the
current chain anchor into `.completed` on a mere prompt trigger match
(`hooks/skill-activation-hook.sh` `_progress_idx = _current_idx - 1`, chain
prefix written wholesale). The push gate accepts `.completed` as evidence for
its two gating milestones. Consequence, verified in an enforcement audit
(2026-07-14, confirmed independently by a Codex sparring pass): an everyday
prompt like "ship it" anchors at `verification-before-completion` (step 5,
broad triggers `ship|merge|push|finish|lgtm|finalize|...`) and fabricates the
`requesting-code-review` milestone; an `openspec`/"as-built" prompt anchors at
`openspec-ship` (step 6) and fabricates BOTH milestones. The next `git push`
then passes the fail-closed gate without review or verification ever running.
Untrusted text (teammate/agent messages) also flows through UserPromptSubmit
and can do the anchoring — demonstrated live during the audit.

The back-fill itself is load-bearing: it was added deliberately so a prior
prompt's non-chain skill does not reset progress and false-block chore pushes.
The fix must remove the fabrication without regressing that.

## What Changes

The walker's COMPUTED done-prefix excludes the two gating milestone names
`requesting-code-review` and `verification-before-completion`, regardless of
which signal produced the prefix (anchor-index or last-invoked-index). Those
names enter `.completed` only via (i) the PostToolUse completion hook on an
actual successful Skill return, or (ii) preservation of existing on-disk
entries through the monotonic union (which is not weakened). All non-gating
steps continue to be back-filled exactly as today (chore false-block guard
preserved). No change to the push gate's read side, the branch ledger, or the
verdict artifact.

## Capabilities

- **Modified: pdlc-safety** — composition-state writer contract: gating
  milestones require invocation evidence.
- Touched subsystems: `hooks/skill-activation-hook.sh` (walker state write),
  `tests/test-routing.sh` (walker regression tests),
  `tests/test-push-gate-failclosed.sh` or sibling (end-to-end deny regression).

## Impact

- Closes the only known deterministic bypass of the fail-closed push gate
  (audit finding F1, ranked critical by both auditors).
- No false-block regression expected: if review/verify genuinely ran, the
  completion hook wrote `.completed` (same session, write-lag fallback intact)
  and the durable branch ledger (cross-session evidence). If they never ran,
  denying is correct.
- Residual accepted: a review performed in a prior session that produced NO
  ledger record (e.g. jq missing at the time) can no longer be resurrected by
  back-fill; the ledger is the intended durable evidence for that case.
- This change touches `hooks/` in a routing repo: pushing it is itself subject
  to the routing-governance gate (clean verdict at HEAD) — dogfooding.
