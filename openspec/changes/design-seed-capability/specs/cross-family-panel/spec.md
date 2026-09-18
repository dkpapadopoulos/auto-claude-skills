# cross-family-panel

## MODIFIED Requirements

### Requirement: Cross-family sends are refused without a user-answered, payload-bound receipt

The binding rule is unchanged — a send requires a fresh, unused, digest-bound receipt
produced by the user's own answer. What changes is WHERE the preview is verified, because
the harness-returned preview annotation is size-gated and absent for every real package.

The PostToolUse `AskUserQuestion` hook MUST write a receipt only when: exactly one question
in the call carried an `[egress-consent:<digest>]` marker in its question text; the same
`tool_use_id` was recorded as a clean ask at PreToolUse and has not been consumed; the
answer for that question is exactly `Approve and send`; and the approved preview is bound to
the digest by **one** of these, recorded in the receipt as `preview_verified`:

- `post` — the harness returned a preview annotation for that question and it hashes to the
  digest; or
- `pre` — the harness returned **no** annotation for that question, in which case the
  binding is the PreToolUse snapshot, which the ask hook writes ONLY after the approve
  option's preview hashes to the marker digest.

A returned annotation that exists but carries no readable preview string MUST be refused,
never treated as absent. A returned preview that exists and does NOT hash to the digest MUST
be refused. The `pre` path MUST be announced, never silent.

#### Scenario: A real package is approvable although the harness returns no preview

- **GIVEN** a clean consent ask whose approve-option preview hashed to the marker digest at
  PreToolUse, and a package large enough that the harness returns `annotations: {}`
- **WHEN** the user answers `Approve and send`
- **THEN** exactly one receipt MUST be written, carrying `preview_verified: "pre"`, and the
  weaker verification MUST be announced

#### Scenario: An unreadable returned annotation refuses rather than downgrading

- **GIVEN** a clean consent ask whose answer carries an annotation for that question with no
  readable preview string
- **WHEN** the receipt hook processes the answer
- **THEN** no receipt MUST be written, and the refusal MUST state that an unreadable preview
  is not the same as an absent one
