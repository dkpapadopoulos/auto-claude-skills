# Invoke provider precedence for config-owned skills

## Why

Issue #354, the residual PR #351 recorded when it protected config-owned topology (#304). The registry's invoke map was a single object built from every discovery in directory order, so the last plugin to ship a skill directory named after a config-owned skill set that entry's `invoke`. An external plugin whose marketplace directory sorted after the config's own provider therefore renamed the step: the composition chain and its remedy lines named `Skill(<that-plugin>:<name>)`.

Reproduced before the change in an isolated HOME with `verification-before-completion` planted in two plugins:

| Layout | `invoke` in the registry |
|---|---|
| superpowers present, other plugin's marketplace sorts before | `Skill(superpowers:…)` |
| superpowers present, other plugin's marketplace sorts after | `Skill(otherplug:…)` |
| superpowers absent, other plugin only | `Skill(otherplug:…)`, available |
| other plugin names a bundled skill | `Skill(auto-claude-skills:…)` |

Only the second row was wrong. It was never a push bypass, and this change does not alter what a returned Skill credits: `hooks/skill-completion-hook.sh` records it by its bare name in any namespace.

One credit path does read `invoke`, so it moves with the second row: a typed `/<prefix>:<name>` REVIEW command is credited only when the registry's `invoke` is exactly `Skill(<prefix>:<name>)` (`hooks/lib/typed-slash-credit.sh`). In that layout `/superpowers:requesting-code-review` is now the credited prefix and `/otherplug:requesting-code-review` is not; before, it was the reverse. The bare typed form is unaffected.

## What Changes

- `hooks/session-start-hook.sh` builds the invoke map in two tiers, `loc` (bundled, then user, last-wins as before) and `ext` (every external claimant of a name, kept as a list), in the same single jq call.
- For a config-owned skill the merge picks `invoke` by provider, not by directory order: a local-tier provider; else the provider the config's own `invoke` names, when an external plugin discovered it; else the last other external claimant.
- The third rung is kept deliberately. Where the config's provider is not installed, another plugin shipping the skill is the only way to reach the step, and refusing it would mark the step unavailable while an invocation of it still credited.
- `tests/test-frontmatter-topology-tier.sh` gains the planted-plugin cells in both directory orders, the sole-provider cell, the no-provider cell, the local-tier cells and a non-config control.

## Out of scope

- Which namespaces the completion hook credits for a gating milestone. That is a separate decision about the gate, not about the registry.
- Changing the rule for two external plugins claiming a config-owned name when neither is the config's provider: still the last in directory order, now pinned by a test.

## Impact

- Affected spec: `skill-routing`.
- Affected code: `hooks/session-start-hook.sh` (Step 6), `tests/test-frontmatter-topology-tier.sh`.
- Fork count unchanged (one jq for the map, as before).
