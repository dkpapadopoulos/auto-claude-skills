# Delta: adversarial-review — proportionality and root-cause question in the quality lens

## ADDED Requirements

### Requirement: The quality-reviewer lens asks whether a change fixes the root cause or routes around it

The `quality-reviewer` brief in `skills/agent-team-review/SKILL.md` MUST ask whether the diff is proportional to the defect and whether each added conditional corrects the root cause or routes around one that stays unfixed. The question SHALL treat "the root cause is still unfixed and this survives it" as the finding, and SHALL NOT treat the existence of a compensating layer as a finding in itself: a bridge, fallback, or sidecar is legitimate when the root cause is also fixed and the residual gap it closes is stated.

The question SHALL require the reviewer to name the input that still fails. That is the observable failure path the severity floor already demands of `quality`-category findings, so a real finding survives triage while a speculative one is correctly floored. The severity floor MUST NOT be given a carve-out for this question, because exempting it would reopen the nit accretion the floor exists to prevent.

This requirement is deliberately narrower than the external rubric it derives from. The full rubric rejects guards, fallbacks, retries, fail-open modes, watchdogs, truncation, and new state files on sight, which is incompatible with this project's deliberately fail-open hook architecture.

#### Scenario: a compensating layer with a fixed root cause is not a finding

- **WHEN** a diff adds a bridge or sidecar, the underlying root cause is also fixed, and the residual gap the layer closes is stated
- **THEN** the reviewer does not raise it as a proportionality finding

#### Scenario: a routed-around root cause is a finding with a named failing input

- **WHEN** a diff adds a conditional that survives a defect whose root cause remains unfixed
- **THEN** the reviewer raises it and names the input that still fails

### Requirement: The proportionality question is pinned to the quality lens specifically

`tests/test-adversarial-governance.sh` MUST assert the question is present in the `quality-reviewer` block specifically, not merely somewhere in the skill file, because the same words under a different lens are a different contract. The extraction SHALL bound the block at the next reviewer header generically rather than at a named sibling, since a third reviewer block sits between `quality-reviewer` and `adversarial-reviewer` and terminating on the latter silently includes the former's neighbour.

The header pattern MUST be anchored so that the adjacent `team_name:` key, which contains the header key as a substring, cannot terminate the range early. When the extracted block is empty the test SHALL fail explicitly rather than letting the content assertions decide.

#### Scenario: the question is moved to a different reviewer lens

- **WHEN** the question is relocated into any other reviewer block, including one positioned between quality-reviewer and the next header
- **THEN** the assertions fail

#### Scenario: the block anchors move

- **WHEN** the `quality-reviewer` header is renamed so the range cannot be extracted
- **THEN** the test reports an explicit extraction failure
