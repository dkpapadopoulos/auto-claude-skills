## ADDED Requirements

### Requirement: Payload-First Session Token Resolution

Hooks that receive a stdin JSON payload MUST resolve the session token from
their own payload's `transcript_path` (as
`session-<basename of transcript_path without .jsonl>`) rather than reading
the shared singleton `~/.claude/.skill-session-token`. The singleton MUST be
used only as a fallback when the payload lacks `transcript_path` or jq is
unavailable, and remains the resolution source for consumers that have no
stdin payload. Resolution failures MUST fail open (empty token → the hook
skips its token-dependent behavior; it never blocks the user). The token
format MUST be defined in exactly one place (`hooks/lib/session-token.sh`)
and shared by the writer and all readers.

#### Scenario: Concurrent session overwrote the singleton

- **WHEN** session A's composition state (keyed to A's transcript-derived token) has an incomplete chain, the singleton contains session B's token, and `openspec-guard.sh` receives a `git push` PreToolUse payload carrying A's `transcript_path`
- **THEN** the gate evaluates A's composition state and denies the push; B's state is never consulted

#### Scenario: Gate allows when own chain is complete despite foreign singleton

- **WHEN** session A's chain is fully completed, the singleton contains session B's token whose chain is incomplete, and the guard receives a `git push` payload carrying A's `transcript_path`
- **THEN** the push is allowed

#### Scenario: Payload lacks transcript_path

- **WHEN** a converted hook receives a payload without `transcript_path`
- **THEN** it resolves the token by reading the singleton, preserving prior behavior

#### Scenario: Completion recorder keys to its own conversation

- **WHEN** the singleton contains a foreign token and `skill-completion-hook.sh` receives a successful chain-member Skill PostToolUse payload carrying this conversation's `transcript_path`
- **THEN** `.completed` advances in this conversation's state file, not the foreign one

#### Scenario: Activation hook re-stamps the singleton

- **WHEN** `skill-activation-hook.sh` resolves a payload-derived token that differs from the singleton's content
- **THEN** after routing, the singleton contains the resolved token, so no-payload SKILL.md consumers invoked later in the same turn read this conversation's token
