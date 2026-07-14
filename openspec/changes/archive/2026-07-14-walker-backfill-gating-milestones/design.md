# Design: walker-backfill-gating-milestones

## Architecture

Single-writer-contract change, confined to the walker's state-write block in
`hooks/skill-activation-hook.sh` (~lines 1060–1119):

1. `_comp_completed` (the computed chain prefix, built from
   `_progress_idx = max(_current_idx - 1, _last_skill_chain_idx)`) is filtered
   to drop `requesting-code-review` and `verification-before-completion`
   before any further use. The filter applies to the PREFIX COMPUTATION only —
   both signals, anchor-index and last-invoked-index, flow through the same
   `_comp_completed` value, so one filter covers both.
2. The monotonic union with on-disk `.completed` is unchanged: entries the
   completion hook wrote (including gating names) survive re-anchors exactly
   as today. The union's chain-ordered select already preserves them; the
   filter must sit on the computed-prefix input, never on the union output.
3. The PostToolUse completion hook (`hooks/skill-completion-hook.sh`) remains
   the sole writer that can introduce a gating name into `.completed`, and the
   branch ledger remains the durable cross-session evidence.

Resulting evidence contract for the push gate (read side untouched):

| Evidence | requesting-code-review / verification-before-completion |
|---|---|
| branch ledger | actual Skill completion (durable) |
| `.completed` | actual Skill completion this session (write-lag fallback) |
| clean verdict @ HEAD | VERIFY only, unchanged |
| walker back-fill | **never** (this change) |

Implementation constraints: Bash 3.2, fail-open (filter failure degrades to
prefix-only write, never aborts the hook), no additional jq forks — the filter
folds into the existing `jq -s` that builds the prefix array.

## Trade-offs

- **(a) walker-side exclusion (chosen)** vs **(b) gate-side distrust of
  `.completed`**: (b) breaks the legitimate same-session write-lag fallback
  (ledger write can lag the Skill return; `.completed` bridges it) and
  re-introduces the false-block class this repo has repeatedly paid for. (a)
  removes fabrication at the source while leaving every legitimate evidence
  path intact.
- **Chore false-block guard**: preserved by scoping the filter to the two
  gating names; all other steps back-fill as before. If review/verify actually
  ran, the completion hook has already credited them, so (a) forfeits nothing.
- **Cross-session resurrection**: a prior-session review with no ledger record
  is no longer back-fillable. Accepted — the ledger exists precisely to carry
  that evidence across sessions, and back-fill was never reliable evidence.

## Dissenting views

- **Codex sparring pass (2026-07-14)** additionally recommended a provenance
  marker (`completed_by_tool` field or sidecar) so the gate could distrust
  non-provenanced gating entries — defense-in-depth toward (c). REJECTED for
  this change: after (a), the only remaining writers of gating names into
  `.completed` are the completion hook (trusted, same plugin version as the
  walker) and direct file forgery, which is outside the gate's threat model
  (drift guardrail, not a security boundary against a malicious local agent —
  see CLAUDE.md verdict-token note). Revival criterion: any NEW writer of
  composition state appears, or the threat model is extended to adversarial
  local writes.
- Gate-side hardening (b) as a second layer was likewise rejected: redundant
  once (a) holds, carries real false-block risk.

## Decisions

1. Filter location: computed prefix only, inside the existing jq pipeline
   (one program, no new forks; hot path stays within budget).
2. Gating-name list is hardcoded in the walker next to the existing hardcoded
   gate invariants (mirrors the `max_iterations` role-allowlist precedent) —
   NOT config-driven, so a config edit cannot silently re-enable fabrication.
3. Red-first TDD: fabrication regressions land as failing tests before the
   walker change; the full suite plus a push-gate end-to-end deny test gate
   completion.
4. Trifecta note: this change REDUCES the untrusted_input → outbound_action
   coupling (prompt text can no longer arm the push gate); no new legs added,
   no agent-safety-review required.

## Implementation Notes (synced at ship time)

- Built as designed; no architectural deviations. Two ship-time additions from
  review: the e2e test additionally asserts the walker-written `.completed`
  itself carries no gating name (robust against future chain reordering), and
  a CLAUDE.md gotcha documents that a prior-session review without a ledger
  record is deliberately not resurrectable (correct deny, not a false block).
- Review record: code review "Ready to merge: Yes" (no critical/important);
  adversarial governance APPROVE-WITH-NOTES — residual trivial-return
  crediting is pre-existing and tracked via the provenance-marker revival
  criterion above.
