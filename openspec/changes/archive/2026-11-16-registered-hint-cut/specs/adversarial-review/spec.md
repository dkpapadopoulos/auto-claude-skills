# adversarial-review delta: registered hint cut

## REMOVED Requirements

### Requirement: Always-On Adversarial Checklist

**Reason**: Registered hint cut (`tests/probes/compliance-census/README.md`, read 2026-11-15). The checklist was delivered as a REVIEW-phase composition hint, and all shipped phase hints are removed. This is a cost decision under a pre-registered rule; the census did not measure whether this checklist changed any review. See `design.md`, Decision 4: it is the one removal the owner was asked to confirm separately.

**Migration**: The governance lens is no longer delivered to every code review. It remains in the adversarial-reviewer specialist ("Adversarial-Reviewer Specialist"), which `agent-team-review` spawns for changes of 5 or more files or changes to sensitive paths, and in the governance regression tests ("Governance Regression Tests"). An ordinary `requesting-code-review` dispatch receives no adversarial checklist unless the reviewer brief supplies one.
