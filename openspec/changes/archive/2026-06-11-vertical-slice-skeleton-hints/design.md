# Design: Vertical-slice PLAN hint + skeleton-first Serena steering

## Architecture

Both changes are content additions to existing, already-wired delivery paths — no new code paths.

**Vertical-slice hint.** PLAN-phase hints live in `phase_compositions.PLAN.hints[]` in `config/default-triggers.json`. The activation hook (`hooks/skill-activation-hook.sh`) flattens each hint to a single `HINT:`-prefixed line via `jq` and emits it as `UserPromptSubmit` additional context when `PRIMARY_PHASE == PLAN`. `config/fallback-registry.json` carries a byte-identical mirror used on the jq-less runtime path; the fallback-drift gate requires the two stay in sync. The new hint is a second array element alongside `CARRY SCENARIOS`, with `"when": "always"`.

**Skeleton-first steering.** A documentation directive in the `serena = true` branch of `internal-truth.md` Tier 1, plus a row in the tier's decision table. No runtime behavior change — it steers the agent's tool-selection at read time.

## Dependencies

None. `get_symbols_overview` is an existing Serena tool (`mcp__serena__get_symbols_overview`); no new package, API, or schema.

## Decisions & Trade-offs

- **Inject via config hint, not by editing `writing-plans`.** `writing-plans` is `superpowers:writing-plans`, a vendored external skill — editing its body would be blown away on upgrade and is not ours to own. The PLAN composition hint is the injection point we control and is upgrade-safe. Rejected alternative: fork the skill.
- **Mode-agnostic hint, not spec-driven-only.** Vertical slicing applies in both default and spec-driven presets, so the hint deliberately avoids the `CARRY SCENARIOS` text that the session-start rewrite keys on. Verified isolated by code review.
- **Two delta specs, not one.** The change touches two distinct capabilities (`skill-routing`, `unified-context-stack`); each gets its own ADDED requirement rather than collapsing into a single coarse spec, because they are enforced by different tests and own different subsystems.
- **Scope held to two of three candidates.** The spec→eval-loop candidate was deferred to a dedicated `design-debate` (deterministic NL→assertion translation is non-trivial); GraphRAG/KG was confirmed already-rejected, with the reference's own tipping-point criteria (>20–30% context on docs, multi-hop, high volatility, thousands of docs) banked as revival triggers — none currently crossed.
- **Advisory, not enforced.** Both additions are guidance only; no gate, role-cap, or HITL step is added or weakened. Adversarial-governance self-check returned no blocking finding (config files touched, but additively).
