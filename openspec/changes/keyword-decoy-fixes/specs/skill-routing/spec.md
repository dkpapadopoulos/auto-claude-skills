## ADDED Requirements

### Requirement: Two fixture decoys are not selected through a keyword

The shipped `keywords` of `authorial-judgment` MUST NOT contain `less generic`, and the shipped `keywords` of `improvement-miner` MUST NOT contain `mine improvements`, in `config/default-triggers.json` and in `config/fallback-registry.json`. Run through the activation hook with each skill's shipped entry, the prompts their routing fixtures list as `NO_MATCH` MUST NOT select the skill, and the prompts listed as `MATCH` MUST still select it.

#### Scenario: A request about an error message does not route to the prose skill

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "make this error message less generic so users understand what went wrong"
- **THEN** `authorial-judgment` is not selected

#### Scenario: A request about a piece of writing still routes to it

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "make this piece less generic, it reads like AI"
- **THEN** `authorial-judgment` is selected

#### Scenario: A phrase inside a longer word does not route to the miner

- **GIVEN** the shipped entry of `improvement-miner`
- **WHEN** the prompt is "determine improvements to the onboarding flow"
- **THEN** `improvement-miner` is not selected

#### Scenario: The phrase on its own still routes to the miner

- **GIVEN** the shipped entry of `improvement-miner`
- **WHEN** the prompt is "mine improvements"
- **THEN** `improvement-miner` is selected
