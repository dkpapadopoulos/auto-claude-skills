# org-hub-connector Specification (delta)

## ADDED Requirements

### Requirement: Descriptor-driven org-hub injection

The session-start hook MUST inject org-hub context only when a committed `.claude/org-hub.json` descriptor exists, MUST read only the descriptor-declared frozen index file (no hub tree-walk or frontmatter parsing at session start), and MUST apply the knowledge-lane contract: index lines only, 8192-byte cap with refuse-not-truncate, untrusted-reference framing, active scope printed in the injection header, and a staleness advisory when the index-built SHA differs from the local clone HEAD. Repos without a descriptor MUST see zero org-hub output. All failure paths (missing clone, malformed descriptor, unreadable index, missing jq) MUST fail open.

#### Scenario: Connected repo gets scoped injection

- GIVEN a repo with a valid committed `.claude/org-hub.json` and a frozen index under the cap
- WHEN the session-start hook runs
- THEN the injected block contains the index lines, the usage note, the active scope in the header, and the untrusted-reference framing, within the 8192-byte cap

#### Scenario: Oversized index is refused, not truncated

- GIVEN a frozen index exceeding 8192 bytes
- WHEN the session-start hook runs
- THEN the hook MUST emit a one-line regenerate/prune notice and MUST NOT inject a truncated index

#### Scenario: Stale index surfaces an actuator

- GIVEN a descriptor whose `index_built_at_sha` differs from the hub clone's current HEAD
- WHEN the session-start hook runs
- THEN the injection block MUST include a staleness advisory naming `/setup` as the remedy

#### Scenario: Absent or broken configuration is silent

- GIVEN a repo with no descriptor, or a descriptor pointing at a missing clone, or malformed JSON
- WHEN the session-start hook runs
- THEN the hook MUST emit no org-hub content and no error, and the session MUST proceed normally

### Requirement: Onboarding authors all inferential artifacts

The `/setup` onboarding flow SHALL be the only place hub structure is inferred: the model explores the hub clone (manifest and conventions are inputs), proposes scope, and emits the descriptor and the scope-filtered frozen index. Both artifacts MUST be human-confirmed before commit, and onboarding MUST warn that the descriptor encodes org structure and MUST NOT be committed to public or wider-access repos.

#### Scenario: Onboarding freezes scope at build time

- GIVEN a hub with org and multi-tribe context and a user selecting one tribe's scope
- WHEN onboarding builds the frozen index
- THEN the index MUST contain only artifacts within the selected scope, and the descriptor records that scope

#### Scenario: Onboarding is human-gated

- GIVEN onboarding has drafted the descriptor and frozen index
- WHEN the user has not confirmed
- THEN nothing is committed and the session-start behavior is unchanged

### Requirement: Hub content trust ceiling

Org-hub content MUST never be framed above reference level in injected context, instruction bodies MUST NOT be auto-loaded, and any REVIEW-phase body loading MUST be gated by a descriptor allowlist entry pinning the file's content hash; a hash mismatch MUST skip the body and surface an advisory.

#### Scenario: Poisoned allowlisted path does not load

- GIVEN a descriptor allowlist entry `{path, sha256}` and a hub file at that path whose current hash differs
- WHEN the REVIEW-phase lens attempts to load it
- THEN the body MUST NOT enter context and an advisory MUST be shown
