# Proposal: add-scope-conformance-check

## Why

Implementer dispatches (subagent-driven-development, agent-team-execution) have
touched files outside their declared task scope — including an out-of-scope
delete caught only by a manual `git show --stat`. The repo doctrine says
enforceable floors must be OWNED and deterministic; today scope-fencing is
prose discipline only. Adapted from worklease's `conformance` verb
(post-hoc respected/violation/warning partition), triaged 2026-07-17:
reject the Node dependency, adopt the conformance primitive.

## What Changes

- New owned script `scripts/scope-conformance.sh`: deterministic tri-state
  verdict (clean | violation | unverified) comparing branch changes vs the
  plan's declared `**Files:**` scope.
- `implementation-drift-check` gains a deterministic Scope Conformance
  pre-pass before Plan Alignment (covers the common SDD path at REVIEW).
- `agent-team-execution` lead/reviewer prompts run the same script at
  completion/review time (branch-level conformance, honestly labeled).
- PLAN-phase composition hint documents `- Allow:` entries for legitimate
  extras.

## Impact

Advisory REVIEW finding only. No push-gate wiring, no new skill, no new
trigger surface, no superpowers modifications.
