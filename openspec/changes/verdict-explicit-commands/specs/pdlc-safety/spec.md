# pdlc-safety: verdict production

## MODIFIED Requirements

### Requirement: A verification verdict SHOULD be produced by measurement, not assertion

The deterministic writer MUST be usable in a repository that declares no
`.verify.yml`. When the caller supplies the gate commands explicitly, the writer
MUST execute them and record its own measured exit codes, using the same
execution, token-resolution, subject-sha and straddle-detection paths as the
declared-gate flow.

The writer MUST NOT infer a gate from build manifests. Selecting a gate is a
judgment the caller owns; this requirement moves measurement only.

Where a `.verify.yml` exists, it is the repository's declared contract and MUST
outrank caller-supplied commands: explicit commands MUST be refused rather than
substituted for the declaration.

This requirement is scoped to the **caller-supplied argument surface**. It is not
a claim about the repository state: a caller that removes `.verify.yml`, or runs
from a tree where it is absent, reaches explicit mode legitimately, and the
resulting verdict still covers the subject commit. That is consistent with the
writer's own statement that the artifact is not a trust boundary, and with
`verdict_is_clean` ignoring `writer` and `discovery_source`. Closing it would
require a different trust model, not a stronger refusal.

The recorded provenance (`discovery_source`) MUST be determined by the writer and
MUST NOT be settable by the caller, so that an explicitly-supplied gate cannot
claim to be a declared one.

Input that the record's transport cannot represent — a command spanning lines, a
name containing the serializer's separator — MUST be refused. It MUST NOT be
silently transformed, truncated or split, because the resulting record is
indistinguishable to every reader from a well-formed one. A declared check that
would otherwise be dropped MUST cause a refusal rather than a verdict recording
fewer checks than the caller named.

Callers MUST supply the complete gate. The record is replaced wholesale and
carries no completeness marker, so a partial re-run would otherwise be recorded
as though it were the whole gate. This is a documented caller obligation and MUST
be described as such rather than as an enforced property.

#### Scenario: A repo with no declared gate still gets a measured verdict

- GIVEN a git repository containing no `.verify.yml`
- WHEN the writer is invoked with an explicit name and command that succeeds
- THEN a verdict is written recording that check as passed
- AND the verdict is stamped with the deterministic writer and a script-owned provenance of `explicit`

#### Scenario: A failing explicit command is never laundered to clean

- GIVEN a git repository containing no `.verify.yml`
- WHEN the writer is invoked with an explicit command that exits non-zero
- THEN the verdict records that check as failed
- AND the verdict is not clean

#### Scenario: A declared gate cannot be substituted

- GIVEN a repository whose `.verify.yml` declares a failing gate
- WHEN the writer is invoked with an explicit command that would succeed
- THEN the explicit command is refused
- AND no verdict records the caller's command as passed

#### Scenario: Unrepresentable input is refused, not transformed

- GIVEN a git repository containing no `.verify.yml`
- WHEN the writer is invoked with a command spanning multiple lines, or a name containing a comma, or a name with no accompanying command
- THEN no verdict is written
- AND the writer reports the refusal
