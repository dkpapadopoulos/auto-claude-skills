# Adopt addy agent-skills mechanics into the auto-claude-skills PDLC

## Why

A re-evaluation of `addyosmani/agent-skills` (@ `e0d2e43`, 2026-06-23) against our
full stack re-confirmed "their PDLC ⊂ ours" at full breadth. The value is not new
capabilities but a handful of specific mechanics, best captured through the one
mechanism no competitor's flat skill list has: **hook-injected phase directives +
inter-skill context contracts** that wrap dependency skills (superpowers) we cannot
edit and pass context skill→skill. Full debate and dissents in
`docs/plans/2026-06-25-addy-adoption-design.md`.

Taking addy's plugin as a hard dependency is rejected (`using-agent-skills` is a
competing router; ~18/24 skills duplicate ours; 12-day restructure = version-drift
risk). Co-installation remains available to users who want addy's standalone skills.

## What Changes

A ranked, sequenced adoption. In scope for this change:

**PR 1 — content grafts (owned SKILL.md prose; no routing/eval risk):**
- deploy-gate gains staged-rollout/rollback thresholds (canary %, error/latency triggers).
- security-scanner gains a STRIDE threat-model-first pre-pass.
- batch-scripting gains a Rule-of-500 cross-link.
- unified-context-stack External Truth gains CITE/UNVERIFIED + inline-planning/confusion nuggets.

**PR 2 — phase directives (each eval-gated, hard phase-gated):**
- Intent-extraction pre-brainstorming directive writing `confirmed-intent` to session state for brainstorming to consume.
- Scope-manifest IMPLEMENT→REVIEW context contract consumed by agent-team-review / implementation-drift-check.

## Capabilities

### Modified
- **skill-routing** — adds two phase directives and two inter-skill context handoffs (intent→brainstorming, scope-manifest IMPLEMENT→REVIEW); will add routing entries when DO-LATER skills land.

### Content-enriched (no observable contract change to their capability specs)
- **unified-context-stack** — External Truth consumption guidance (citation/planning nuggets).
- **security-scanner** — design-time STRIDE pre-pass.
- deploy-gate skill, batch-scripting skill — prose grafts (no capability spec today).

## Impact

- `config/default-triggers.json` + `config/fallback-registry.json` (PR2 directive entries, mirrored).
- `hooks/skill-activation-hook.sh` reuses the existing `methodology_hints[]` walker — no hook code change expected; PR2 adds entries + `phases[]` gating.
- `tests/test-routing.sh` (PR2 directive fixtures).
- Skill prose: `skills/deploy-gate`, `skills/security-scanner`, `skills/batch-scripting`, `skills/unified-context-stack` (PR1).
- Session state: a new `confirmed-intent` field (PR2, reusing PERSIST-DESIGN plumbing).

## Deferred (out of scope, with revival triggers)
- T3a observability skill (standalone-first; **composition** with deploy-gate/incident-analysis deferred until the manual handoff is hit ≥2×).
- T3b deprecation-and-migration skill (episodic).
- T3c api-and-interface-design skill (needs Kotlin/Spring reframe; gate behind T3b).

## Skipped
using-agent-skills (competing router), performance-optimization (frontend-heavy),
ci-cd scaffolding (low freq), ADR-lifecycle (openspec covers traceability),
frontend AI-aesthetic (frontend-design plugin), T1c/T1d/T1e standalone (collapsed/folded).
