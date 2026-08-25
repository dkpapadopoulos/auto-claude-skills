# pdlc-safety: REVIEW verdict layer

## MODIFIED Requirements

### Requirement: REVIEW verdict artifact and advisory leg

The push gate MUST separate REVIEW **status** (a gating Skill returned) from REVIEW **verdict** (a review actually happened and reached a terminal outcome), mirroring the existing VERIFY split.

A review verdict artifact MUST record, at minimum: `schema_version`, `provider`, `reviewed_base_sha`, `reviewed_head_sha`, `changed_file_digest`, `unresolved_blocking`, and a terminal `verdict` of `clean`, `findings-open`, or `could-not-review`. `dispatch_attempted` and `dispatch_succeeded` MUST be recorded as separate telemetry fields and MUST NOT, alone or collapsed, act as a deny predicate.

The reader MUST be Bash 3.2 compatible and MUST fail open: an absent, unreadable, malformed, or unparseable artifact yields no advisory and never blocks. A verdict binds when `reviewed_head_sha` is HEAD or a branch-local ancestor of HEAD; mainline-reachable and unrelated shas MUST NOT bind.

In this change the verdict leg MUST be advisory only: it appends to the gate's advisory text, sets no `permissionDecision`, and MUST NOT alter any existing deny decision. The REVIEW status leg is unchanged.

`hooks/lib/review-verdict.sh` MUST NOT be added to `_GATE_ENFORCE_LIBS` while the leg is advisory, and MUST be added if the leg ever becomes gate-enforcing.

`phase_attest` MUST continue to reject `requesting-code-review` at both writer and reader. This change MUST NOT introduce a REVIEW attestation path.

#### Scenario: A bare Skill return does not produce a clean review verdict

- GIVEN a session where `Skill(superpowers:requesting-code-review)` has returned successfully and no reviewer ran
- WHEN the push gate evaluates the REVIEW verdict leg
- THEN no clean review verdict is found for HEAD
- AND the gate emits a review-verdict advisory naming the missing artifact
- AND the gate emits no `permissionDecision` of `deny` for that advisory

#### Scenario: A recorded review binds to the reviewed commit

- GIVEN a review verdict recorded with `verdict: clean` and `reviewed_head_sha` equal to HEAD
- WHEN the push gate evaluates the REVIEW verdict leg on a push
- THEN no review-verdict advisory is emitted

#### Scenario: A verdict for an unrelated commit does not bind

- GIVEN a review verdict whose `reviewed_head_sha` is reachable from the mainline base and is not a branch-local ancestor of HEAD
- WHEN the push gate evaluates the REVIEW verdict leg
- THEN that verdict does not satisfy the leg
- AND the advisory is emitted as though no verdict existed

#### Scenario: Missing reader library degrades silently, never blocks

- GIVEN `hooks/lib/review-verdict.sh` is absent or fails to source
- WHEN the push gate runs on a `git push`
- THEN the gate's deny decisions are unchanged
- AND no review-verdict advisory is emitted
