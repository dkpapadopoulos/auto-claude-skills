## MODIFIED Requirements

### Requirement: External plugins cannot rewrite config-owned topology

At registry build, frontmatter from an external-marketplace plugin's `SKILL.md` whose directory name matches a config-owned skill MUST NOT change that skill's `role`, `phase`, `precedes` or `requires`. It MAY still supply `triggers` and `priority`, and `skill-rules.json` triggers for that name SHALL still reach it through the external tier. An external skill whose directory name the config does not own keeps its own topology. Frontmatter from this plugin's bundled skills and from the user's skills directory keeps its overrides. (`invoke` and `available` are governed by "Invoke for a config-owned skill is chosen by provider, not directory order".)

#### Scenario: Planted external skill

- **WHEN** an external plugin ships `skills/verification-before-completion/SKILL.md` with `role: domain`, `phase: DESIGN`, `precedes`, `requires`, `priority: 1` and `triggers`
- **THEN** the registry entry keeps the config `role`, `phase`, `precedes` and `requires`, and carries the planted `priority` and `triggers`

#### Scenario: Bundled skill with topology frontmatter

- **WHEN** `skills/deploy-gate/SKILL.md` declares `role`, `phase`, `precedes` and `requires`
- **THEN** the registry entry equals the config entry, as today

## ADDED Requirements

### Requirement: Invoke for a config-owned skill is chosen by provider, not directory order

At registry build, the `invoke` of a config-owned skill SHALL be chosen in this order: a provider in a local tier (this plugin's bundled skills, then the user's skills directory); else the provider named by the config entry's own `invoke`, when an external plugin discovered it; else the last other external plugin that ships a skill directory of that name. The order in which marketplace and plugin directories are scanned MUST NOT change the result while a local-tier provider or the config's provider is present. A skill with any provider is `available: true`; a skill with none keeps the config's `invoke` and is `available: false`. A skill name the config does not own keeps the namespace of the plugin that ships it.

#### Scenario: Another plugin ships the same name beside the config's provider

- **WHEN** superpowers and a second external plugin both ship `skills/verification-before-completion/SKILL.md`, with the second plugin's marketplace directory sorting before or after superpowers'
- **THEN** the registry entry's `invoke` is `Skill(superpowers:verification-before-completion)` and it is available

#### Scenario: The config's provider is not installed

- **WHEN** superpowers is absent and one external plugin ships `skills/verification-before-completion/SKILL.md`
- **THEN** the registry entry's `invoke` names that plugin and it is available

#### Scenario: A local tier provides the skill

- **WHEN** the user's skills directory holds `verification-before-completion` and external plugins ship it too
- **THEN** the registry entry's `invoke` is `Skill(verification-before-completion)`

#### Scenario: An external plugin names a bundled skill

- **WHEN** an external plugin ships `skills/project-verification/SKILL.md`
- **THEN** the registry entry's `invoke` stays `Skill(auto-claude-skills:project-verification)`
