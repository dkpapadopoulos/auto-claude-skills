# Proposal: split the push gate's REVIEW leg into status and verdict

## Why

The push gate's REVIEW leg records **invocation**, never **work**. `Skill(superpowers:requesting-code-review)` returning successfully credits the milestone and opens the gate, whether or not any review happened.

This is structural, not a bug in the crediting code. `Skill(...)` returns the *instruction body*, so `PostToolUse ^Skill$` fires at instruction-load time — **before** any reviewer dispatch is even attempted. No enrichment of that payload can witness review work, because at the moment the hook runs the work has not happened.

VERIFY does not have this problem: it carries a `~/.claude/.skill-project-verified-<token>` artifact bound to a commit SHA, so the gate can ask *did it pass* separately from *did it run*. REVIEW has no such split.

The consequence is that the project's central claim — denial conditioned on durable evidence the work actually happened — is true for one of the two gating milestones and false for the other. This session demonstrated it: the REVIEW gate could have been made green at any point by one `Skill()` call with no reviewer in existence.

`finding_count_estimate` compounds it. It is `wc -l` over the **outer Skill** `tool_response` — the skill body, not the reviewer's output — so every `requesting-code-review` record reads `1`. Nothing in the system can currently distinguish a real review from a no-op.

## What Changes

- A new **review verdict artifact**, `~/.claude/.skill-review-verdict-<token>`, versioned, recording reviewed base+head SHA, a changed-file digest, provider provenance, unresolved-blocking count, and a terminal verdict.
- A new **Bash 3.2 reader lib**, `hooks/lib/review-verdict.sh`, shaped like `hooks/lib/verdict.sh`: artifact path, subject binding, `review_verdict_is_clean`, cross-token resolution. Fail-open throughout.
- **Two providers** write the artifact through one writer, `scripts/record-review-verdict.sh`: a local agent/human review, and a GitHub import that reads real PR reviews.
- A **warn-only REVIEW-verdict leg** in `hooks/openspec-guard.sh`, sitting alongside the existing status leg and never replacing it. It appends to `_STALE_MSG` and sets no `permissionDecision`.
- A **forward shadow corpus** (`~/.claude/.push-review-shadow.jsonl`) with a pre-registered, episode-based exact Clopper–Pearson decision rule, mirroring the IMPLEMENT leg's discipline.
- `finding_count_estimate` is **fixed to stop claiming what it cannot measure**, and the review-verdict artifact carries the real count.

## Capabilities

**Modified**

- `pdlc-safety` — the push gate gains a REVIEW verdict layer parallel to the existing VERIFY verdict layer. The REVIEW *status* leg is unchanged; the verdict leg is additive and advisory.

## Impact

- **Enforcement is unchanged by this proposal.** The new leg cannot deny. Every existing deny path keeps its current behaviour, byte-identical on a healthy run.
- **`hooks/lib/review-verdict.sh` is NOT added to `_GATE_ENFORCE_LIBS`** while the leg is advisory — same posture as `implement-shadow.sh` and `pr-diff.sh`. It joins the canary only if and when the deny-flip ships.
- **No REVIEW attestation.** `phase_attest` rejects `requesting-code-review` at both writer and reader, and CLAUDE.md names the IMPLEMENT-vs-REVIEW/VERIFY auditable-escape asymmetry as deliberate. This change does not reverse it.
- **The local gate is not the trust boundary.** Every local evidence store is in-band; a model with filesystem access can write one. GitHub branch protection is the out-of-band control, and `main` is currently unprotected. This artifact is an early-warning and telemetry layer, and is designed knowing that.
