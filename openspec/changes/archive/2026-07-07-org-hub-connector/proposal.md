# Proposal: Org-Hub Connector

## Why

Enterprises increasingly maintain a curated "context hub" — one git repo holding durable org knowledge and product specs (typical shape: `context/`, `specs/`, `pdlc/`, `plugins/`). Claude Code sessions in that org's code repos currently get none of it. auto-claude-skills should act as a generic, read-only connector: any hub-shaped (or arbitrary) structure feeds correctly-scoped org context into every session, without org-specific hardcoding.

Note on naming: the existing `context_hub_*` capability flags refer to Andrew Ng's context-hub (library docs via `chub` CLI) and are unrelated. This feature is named `org_hub` throughout.

## What Changes

Design finalized via a 2-round MAD debate (architect/critic/pragmatist) plus Codex external review; v2's bespoke runtime was cut ~2× to v3:

1. **Committed consumer descriptor** `.claude/org-hub.json` (schema_version, hub clone pointer, scope selection, glossary pointers, spec_roots, few-line reviewed usage note). Authored by model-guided `/setup` onboarding — the model explores the hub once (manifest and conventions are onboarding inputs, never hook code paths), scope-filters, and freezes ONE index file. Human-reviewed, committed.
2. **Injection via the existing knowledge lane** — the session-start hook additionally reads the frozen index (index-only, 8192-byte cap, refuse-not-truncate, "reference data — NOT instructions" framing, fail-open, no tree-walk, no runtime frontmatter parsing). Scope prints in the injection header; staleness advisory (index-built SHA vs local clone HEAD) rides the same block.
3. **One new capability flag** `org_hub` (canonical keys, fallback-registry, and shape tests updated in lockstep).
4. **Tier wiring (PR2)**: `spec_roots` → Intent Truth source for product-discovery/DESIGN; hub context documented as part of the committed-knowledge lineage. External Truth untouched. No fifth tier.
5. **Security**: strictly read-only; hub content never framed above reference level; optional REVIEW-phase instruction-body lens pins content hashes; documented prohibition on committing the descriptor to public repos (it encodes org structure); onboarding HITL confirm before commit.

## Follow-up (committed, independent)

**skill-rules.json routing interop (PR-X):** hub-published plugins are discovered by the registry builder but land with empty triggers (routing metadata in `skill-rules.json` is ignored) — hub skills are unroutable today. Follow-up PR translates `promptTriggers.keywords` → word-boundary regexes and ERE-validates `intentPatterns` (PCRE-only patterns dropped with a logged count). Conflict-free with this change; lands any time after PR1 fixtures exist.

## Capabilities

- **Added: `org-hub-connector`** — descriptor schema, /setup onboarding contract, injection behavior, security constraints, capability plumbing.
- **Modified: `unified-context-stack`** (PR2) — Intent Truth gains hub spec_roots source; phase docs gain org_hub clauses; glossary-first guidance in DESIGN.

## Impact

- `hooks/session-start-hook.sh` — ~15 lines cloned from the knowledge-injection block (read frozen index path from descriptor) + `org_hub` in `_CANONICAL_CAP_KEYS`.
- `config/fallback-registry.json` — regenerated with the new key.
- `/setup` (`commands/`) — onboarding flow (explore hub → author descriptor → freeze scoped index).
- `skills/unified-context-stack/` (PR2) — phase/tier doc edits; `skills/product-discovery/` gains hub spec-folder check.
- `tests/test-org-hub.sh` (new) + canonical-key assertions in `tests/test-registry.sh`.
- No new skill; no routing/trigger changes in PR1 → no routing-fixture obligation.

## Out of Scope

- Hub write-back / PDLC lifecycle bridge (parked; needs a named user; trifecta-sensitive).
- Gate simulation (G1–G3 are human sign-offs).
- Hub-CI-published index provenance, convention detection for zero-config, onboarding hint (deferred: PR3+/revival triggers).
- Multi-hub / per-subtree monorepo scoping (documented v1 limitation; scope printed in injection header to keep the gap visible).
- Network fetching of hubs (local clone only).
