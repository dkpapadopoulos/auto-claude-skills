## ADDED Requirements

### Requirement: Cross-family sends are refused without a user-answered, payload-bound receipt

`panel` and `second-opinion` MUST send cross-family content only through
`scripts/consult-dispatch.sh`. Digests MUST be sha256 over the package bytes with trailing
newlines removed, and no other normalisation. The dispatcher MUST refuse to send unless a
consent receipt for the frozen package's digest exists, is no older than 900 seconds, and is
claimed by an atomic move before sending; one receipt MUST authorise at most one send, and a
send whose outcome is uncertain MUST NOT restore it. The dispatcher MUST accept only
receipts in the format the PostToolUse `AskUserQuestion` hook writes, and that hook MUST
write one only when: exactly one question in the call carried an
`[egress-consent:<digest>]` marker in its question text; the same `tool_use_id` was recorded
as a clean ask at PreToolUse and has not been consumed; the answer for that question is
exactly `Approve and send`; and the harness-returned preview annotation for that question
exists and hashes to the digest. A marked question MUST be denied at PreToolUse when its
input contains an `answers` key, when it comes from a subagent, when its `tool_use_id` was
already recorded, or when it violates the consent-question schema. Receipt files are
agent-writable, so these rules defend against a skipped ask, not a deliberate forgery.
Session identity MUST be resolved without the shared singleton on both sides. When the
dispatcher cannot verify consent it MUST refuse and MUST say that verification could not
run, naming the missing component, distinctly from a missing approval — unless the user has
set `consultation.egress_consent` to `warn`, in which case it MUST announce on every send
that consent enforcement is off.

#### Scenario: an approved package is sent exactly once

- GIVEN a package prepared with digest D and a clean `AskUserQuestion` whose question
  carries `[egress-consent:D]`, answered `Approve and send` with the package as preview
- WHEN `consult-dispatch.sh send D` runs
- THEN the package is sent read-only from an isolated directory, AND a second
  `send D` is refused as not approved

#### Scenario: a pre-answered consent question is denied

- GIVEN an `AskUserQuestion` call whose question carries `[egress-consent:D]`
- WHEN its `tool_input` contains an `answers` key
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
