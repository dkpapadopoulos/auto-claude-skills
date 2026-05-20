## ADDED Requirements

### Requirement: Memory consolidation precedes git push in SHIP phase

The Ship & Learn phase documentation (`skills/unified-context-stack/phases/ship-and-learn.md`) MUST specify that memory consolidation completes before the first `git push` of the SHIP phase. The phase doc MUST name the push gate by its exact path (`hooks/openspec-guard.sh`), MUST explain the failure mode (the operator recovery path after a gate interrupt is fragile and tends to drop the consolidation step), and MUST give a concrete ordered sequence covering as-built documentation, memory consolidation, the consolidation marker write, and `git push`.

#### Scenario: Phase doc states the push-ordering rule

- **GIVEN** the repository at HEAD on branch `docs/forgetful-consol-sequencing` or its merge into `main`
- **WHEN** `skills/unified-context-stack/phases/ship-and-learn.md` is read
- **THEN** the file contains a `**Sequence:**` callout in the `Memory Consolidation` section
- **AND** the callout states that memory consolidation MUST complete before the first `git push` of SHIP
- **AND** the callout references `hooks/openspec-guard.sh` by path
- **AND** the callout lists the ordered sequence `as-built docs → memory consolidation → consolidation marker → git push`

#### Scenario: Phase doc does not contradict surrounding sections

- **GIVEN** the same file
- **WHEN** the `REQUIRED Before Memory Consolidation: As-Built Documentation` section and the new `Sequence` callout are read together
- **THEN** as-built documentation is still required before consolidation
- **AND** the consolidation marker write is still positioned after consolidation
- **AND** no section instructs the model to push before consolidating

### Requirement: Kill criterion for guard hardening is recorded and dated

The decision to defer hard-deny enforcement of the consolidation guard MUST be recorded with a concrete trigger and review date. The trigger MUST specify a numeric threshold of additional misses, a review date no later than 2026-06-17, and the exact code locus (`hooks/openspec-guard.sh:99-121`) that would be modified if the trigger fires.

#### Scenario: Kill criterion is queryable from Forgetful

- **GIVEN** the Forgetful MCP is connected
- **WHEN** `mcp__forgetful__query_memory` is called with query terms `"forgetful consolidation kill criterion 2026-06-17"`
- **THEN** a memory titled `Forgetful consolidation guard kill criterion (auto-claude-skills)` is returned in `primary_memories`
- **AND** the memory body names the threshold (`2+ more`), the review date (`2026-06-17`), and the code locus (`hooks/openspec-guard.sh:99-121`)
