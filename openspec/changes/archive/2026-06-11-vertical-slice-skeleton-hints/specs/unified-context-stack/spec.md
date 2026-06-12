# unified-context-stack — delta spec: vertical-slice-skeleton-hints

## ADDED Requirements

### Requirement: Skeleton-first reads in Internal Truth Tier 1

The Internal Truth tier (`skills/unified-context-stack/tiers/internal-truth.md`) MUST, in its `serena = true` (Tier 1) guidance, instruct reading a file's symbol skeleton via `get_symbols_overview` before `Read`-ing whole files, locating the target symbol from the outline and then reading only the needed body. The guidance MUST state the rationale (reading entire files inflates the context window and degrades reasoning). The tier's decision table MUST include a row routing the question "what's in this file / where's the right symbol?" to the skeleton-first approach. The directive MUST remain gated on `serena = true` and MUST NOT alter the Tier 0 / Tier 1 / Tier 2 fallback ordering.

#### Scenario: Tier 1 guidance names the skeleton-first step

- GIVEN a session with `serena = true`
- WHEN the Internal Truth tier doc is consulted for how to read code
- THEN it directs use of `get_symbols_overview` to read the signature skeleton before reading full implementation bodies

#### Scenario: Decision table routes the locate-symbol question

- GIVEN the Internal Truth tier's "When to use which" table
- WHEN looking up "what's in this file / where's the right symbol?"
- THEN the table routes it to Tier 1 `get_symbols_overview` (skeleton first, body on demand)
