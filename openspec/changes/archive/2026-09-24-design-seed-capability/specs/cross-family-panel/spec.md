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

#### Scenario: an approved package is sent exactly once

- GIVEN a package prepared with digest D and a clean `AskUserQuestion` whose question
  carries `[egress-consent:D]`, answered `Approve and send` with the package as preview
- WHEN `consult-dispatch.sh send D` runs
- THEN the package is sent read-only from an isolated directory, AND a second
  `send D` is refused as not approved

#### Scenario: a pre-answered consent question is denied

- GIVEN an `AskUserQuestion` call whose question carries `[egress-consent:D]`
- WHEN its `tool_input` contains an `answers` or `annotations` key
- THEN the PreToolUse hook denies it, AND no receipt for D is ever written

#### Scenario: a repeated PostToolUse cannot resurrect a spent approval

- GIVEN a receipt for D was issued from ask T and then consumed by a send
- WHEN a PostToolUse event for T is delivered again
- THEN no new receipt is written, AND a further `send D` is refused as not approved

#### Scenario: approval of one payload does not authorise another

- GIVEN the user approved a preview whose sha256 is not D
- WHEN the question carried `[egress-consent:D]`
- THEN no receipt for D is written, AND `send D` is refused as not approved

#### Scenario: an unverifiable send is refused and says why

- GIVEN no session token can be resolved for the dispatcher, or jq is absent
- WHEN `send D` runs with enforcement on
- THEN nothing is sent, AND the message states consent could not be verified and names the
  missing component, rather than asking the user to approve again

#### Scenario: a later decline revokes an earlier unused approval

- GIVEN the user approved package D and the approval has not been used
- WHEN the user is asked about D again and chooses `Do not send`
- THEN the earlier approval is revoked, AND `send D` is refused as not approved
