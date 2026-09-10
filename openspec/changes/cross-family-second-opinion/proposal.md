# Proposal: Cross-Family Second Opinion

## Why

Adopted from Patric Fornasier's "Getting Out of the Loop" (patforna/writing) and its companion repos, after two independent analyses (Claude + Codex) of what ACS should take from them converged on this as the top adoptable slice. Upstream evidence: independent single-round generation by models from *different families* (Claude + Codex), merged by a synthesis that preserves disagreements, gave the largest quality gain at the planning stage; a cross-family adversarial review pass "most reliably caught real bugs"; same-family panels still help but materially less. ACS has the Codex plumbing installed (codex plugin) but no routed skill exposes it, and `agent-team-review`'s Cross-Model Offer is limited to external-fact claims.

## What Changes

1. New skill `panel` — dispatches N fresh-context panelists (default: strongest Claude + Codex) on one prompt, single round, no cross-talk; delivers verbatim attributed responses. When no second family is available: announced, consent-gated degradation to same-family for the default roster; an explicitly requested panelist is never silently substituted.
2. New skill `synthesize` — composition-only; merges N perspectives without forcing consensus (agreement → take; unique → re-examine; contradiction → decide on evidence, never vote; gap → flag). Surviving disagreements go to the caller.
3. `agent-team-review` §6 widened — the Cross-Model Offer covers a full cross-family adversarial pass over the diff (not just external-fact claims), read-only/sandboxed, findings flowing through the existing severity floor and §4a adjudication.
4. `agent-team-review` autofix lane — optional per-finding `Autofix:` line (suggestion severity only, four-condition eligibility, independently validated by the lead — the token never self-certifies), applied only after per-item human approval and a byte-exact application check, before verification and verdict recording.

## Capabilities

### Added
- `cross-family-panel` — panel + synthesize skills, routing entries, degradation contract.

### Modified
- `review-cross-family-pass` — agent-team-review §6 Cross-Model Offer scope.
- `review-autofix-lane` — agent-team-review finding contract + lead synthesis.

## Impact

- `skills/panel/SKILL.md`, `skills/synthesize/SKILL.md` (new, adapted from patforna/core-skills, MIT, attributed)
- `skills/agent-team-review/SKILL.md` (§6, finding contract, §4 lead synthesis)
- `config/default-triggers.json`, `config/fallback-registry.json` (registry entries)
- `tests/fixtures/routing/panel.txt`, content-assertion tests, anatomy compliance
- No hook changes; no gate behavior changes; no review default changes (cross-family stays opt-in pending A/B evidence)
