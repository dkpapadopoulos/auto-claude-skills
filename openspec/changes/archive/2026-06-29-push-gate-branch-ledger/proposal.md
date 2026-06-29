# Push-Gate Branch Milestone Ledger (chain-reanchor false-block fix)

## Why

The REVIEW→VERIFY push gate (`hooks/openspec-guard.sh`) false-blocks legitimate pushes. Observed
and reproduced repeatedly this session: after `requesting-code-review` and
`verification-before-completion` genuinely complete, a later prompt whose detected phase differs
(e.g. text mentioning "outcome-review"/"LEARN") makes the activation hook **re-anchor the
composition chain and reset `.completed`** (`hooks/skill-activation-hook.sh:1088-1106` —
`.completed` is unioned only when `$p.chain == $chain`, else reset to the fresh prefix). The push
gate then denies `git push` because `.completed` no longer lists the gating milestones — even
though the work was reviewed and verified.

Root cause: `.completed` is **transient composition state** (per-chain, two writers, documented
"monotonic within the same chain"), but the push gate uses it as **durable branch/work readiness**.
The superpowers backbone *deliberately* recomputes the chain every prompt (forward progression,
backward re-entry, DEBUG/LEARN detours), so tying gate readiness to the transient chain is the bug.

Token-rotation (#51) is already mitigated (gate resolves token from transcript). This change fixes
the remaining same-session chain-reanchor reset.

## What Changes

Decouple the gate's source of truth from `.completed`, **additively** (backward-compatible):

- **`skill-completion-hook.sh`**: when a *gating* milestone (`requesting-code-review`,
  `verification-before-completion`) completes, also record it to a **per-(repo+branch) milestone
  ledger** (HEAD sha + timestamp). Append-only / per-milestone marker writes (no read-modify-write
  JSON) to avoid concurrent-session write contention.
- **`openspec-guard.sh` push gate**: allow when **(ledger has the gating milestone for this
  repo+branch) OR (current `.completed` has it)**; deny only when the active chain contains a gate
  and **neither** source satisfies it. Emit a **soft staleness warning** (not a block) when the
  recorded HEAD sha differs from current HEAD.
- **Keying**: repo+branch hash via the existing `consol-marker.sh` remote-URL→path→`shasum`
  pattern; detached HEAD → `detached-<sha>` boundary.
- **`.completed` is unchanged** — it stays the display/walker's per-chain state; no new writer, no
  invariant change (avoids the sticky-emission "non-chain-member = malformed" break at
  `skill-activation-hook.sh:390-399`).

## Capabilities

- **Modified:** `skill-routing` — push-gate readiness keyed to a durable per-branch milestone
  ledger (`OR` the transient `.completed`), surviving composition chain re-anchors.

## Impact

- `hooks/skill-completion-hook.sh` (ledger writer)
- `hooks/openspec-guard.sh` (gate reads ledger OR `.completed`; soft staleness warning)
- new `hooks/lib/branch-ledger.sh` (repo+branch key + ledger read/write helpers; reuses
  `consol-marker.sh` keying pattern)
- `tests/test-routing.sh` (regression fixtures)

## Out of Scope

- **Hard HEAD-invalidation** (re-blocking every post-review commit) — conflicts with the SHIP
  happy-path (commit workflow runs after verification) and the REVIEW fix→re-review loop; soft
  warning only. Tree-hash staleness comparison is a possible future tightening.
- Changing `.completed` semantics, the chain-derivation, or phase detection.
- Removing the `.completed` gate path (kept as the OR-fallback for in-flight sessions and as the
  deny baseline).
- The `agent-team-review` inter-lens disagreement and detector coverage-delta items (separate,
  already deferred).
