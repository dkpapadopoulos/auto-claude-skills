## ADDED Requirements

### Requirement: A bare mention of a newsletter does not select the prose skill

The shipped `keywords` of `authorial-judgment` MUST NOT contain `newsletter`, in `config/default-triggers.json` and in `config/fallback-registry.json`. Run through the activation hook with the skill's shipped entry, a prompt that mentions a newsletter without a writing verb, a topic marker or another keyword of the skill MUST NOT select it, and a request to write or rework a newsletter MUST still select it through a trigger.

#### Scenario: A question about newsletter emails does not route to the prose skill

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "what other improvements did we gather from the ai newsletter emails?"
- **THEN** `authorial-judgment` is not selected

#### Scenario: A request to rework a newsletter draft still routes to it

- **GIVEN** the shipped entry of `authorial-judgment`
- **WHEN** the prompt is "punch up this newsletter draft so it sounds human"
- **THEN** `authorial-judgment` is selected

#### Scenario: The keyword is put back

- **WHEN** `newsletter` is added to the `keywords` of `authorial-judgment` and the keyword-path audit runs
- **THEN** the audit fails, reporting the question above as a `NO_MATCH` fixture line selected via keywords
