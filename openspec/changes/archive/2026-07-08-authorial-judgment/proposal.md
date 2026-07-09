# Proposal: authorial-judgment skill

## Why

LLM prose is often technically correct, well-structured, and dead — too smooth,
too complete, too linear, too certain. We have a strong editorial playbook for
this failure mode ("Cognitive Texture and Authorial Judgment"), but it lives as a
static document with no way to activate. This change turns it into a routable
domain skill that fires as a **revision lens** on authored persuasive prose, so
the playbook actually applies when someone drafts an essay, blog post, or
"make this not sound like AI" rewrite.

The playbook is a *review/refinement* layer by its own framing ("use after
premise interrogation and before the final style pass") and its value is bounded:
it earns its keep exactly where genericness = failure (persuasive prose where
authorial judgment is the product), and it does damage where completeness,
linearity, and certainty are the point (README, spec, changelog). The skill
therefore fires narrowly and stays silent on reference/procedural/code prompts.

## What Changes

- **Added skill** `skills/authorial-judgment/` (SKILL.md + one merged-taxonomy
  reference). SKILL.md distills the source doc's 14 sections to its ~6
  non-redundant moves plus the load-bearing "real texture or clean prose" gate.
- **Added routing** entry in `config/default-triggers.json` and mirrored in
  `config/fallback-registry.json` (`role: domain`), matching authored-persuasive
  -prose prompts and excluding docs/specs/changelogs/code.
- **Added routing fixture** `tests/fixtures/routing/authorial-judgment.txt`
  (>=1 MATCH, >=1 verbatim-borrowed NO_MATCH decoy) — the CI-blocking done-gate.

## Capabilities

### Added
- `prose-quality` — activation of an editorial revision lens for authored
  persuasive prose, and suppression of it for reference/procedural/code writing.

## Impact

- Routing engine gains one domain skill; subject to the existing 2-domain
  role-cap, so no new gating behavior and no SDLC-phase change.
- No changes to hooks, push-gate, or composition chain.
- Distilled scope avoids the over-firing scars documented in project memory
  (word-boundary fixes, hint-path bypass, over-matching).
