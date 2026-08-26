# Spec delta: pdlc-safety — reviewer dispatch authorization + reviewer-ran evidence

## ADDED Requirements

### Requirement: REVIEW-phase reviewer dispatch is pre-authorized by default

The activation hook MUST render, into REVIEW-phase context, a standing
authorization to dispatch reviewer subagents without seeking per-dispatch
approval from the user.

The authorization MUST be controlled by `phase_enforcement.review_dispatch` in
`~/.claude/skill-config.json`, with value `auto` (default) rendering it and
value `ask` suppressing it.

The default MUST apply when the config file is absent, the key is absent, `jq`
is unavailable, or the file does not parse. A config read failure MUST NOT
suppress the authorization, because suppression restores the stall this
requirement exists to remove.

The authorization MUST be scoped to agents that only read and report. It MUST
NOT authorize dispatch of agents able to modify files, push, or take outbound
actions.

#### Scenario: default install renders the authorization

- **GIVEN** no `~/.claude/skill-config.json`
- **WHEN** the activation hook routes a REVIEW-phase prompt
- **THEN** the rendered context contains the dispatch authorization

#### Scenario: opt-out suppresses the authorization

- **GIVEN** `~/.claude/skill-config.json` containing
  `{"phase_enforcement":{"review_dispatch":"ask"}}`
- **WHEN** the activation hook routes a REVIEW-phase prompt
- **THEN** the rendered context does NOT contain the dispatch authorization

#### Scenario: unparseable config falls back to the default

- **GIVEN** a `~/.claude/skill-config.json` that is not valid JSON
- **WHEN** the activation hook routes a REVIEW-phase prompt
- **THEN** the rendered context contains the dispatch authorization

### Requirement: The routing surface MUST NOT name an unregistered reviewer agent

No TRACKED file MUST instruct dispatching `superpowers:code-reviewer`. That
agent type is not registered by the `superpowers` plugin, which ships no
`agents/` directory.

The scan MUST cover tracked files rather than a fixed directory list, because
the requirement is about what ships. A directory-scoped scan missed a live
instruction in `.claude/`, found only in review.

Two exclusions are deliberate and MUST be stated wherever the scan is
implemented: `openspec/`, whose specs quote the string as evidence of the
defect being fixed, and `tests/`, which holds the scanning test itself plus
frozen behavioral-eval prompt snapshots that legitimately embed the historical
string.

Reviewer-dispatch instructions MUST name a target that exists on a default
install. `general-purpose` combined with the superpowers `code-reviewer.md`
template MUST be the stated fallback, since it is available on every install.
Installed reviewer agents MAY be named as preferred alternatives but MUST NOT
be stated as required.

#### Scenario: no dead agent reference remains in shipped content

- **GIVEN** the repository at HEAD
- **WHEN** tracked files outside `openspec/` and `tests/` are searched for the
  literal `superpowers:code-reviewer`
- **THEN** there are no matches

#### Scenario: the scan covers instruction files outside the routing directories

- **GIVEN** a tracked file under `.claude/` that instructs dispatching
  `superpowers:code-reviewer`
- **WHEN** the scan runs
- **THEN** it reports a match, even though the file is not under `hooks/`,
  `config/`, or `skills/`

### Requirement: A returning reviewer subagent records durable branch-scoped evidence

A `PostToolUse` hook matching the subagent tool MUST record a `reviewer-ran`
milestone into the per-(repo+branch) branch ledger when a reviewer agent
returns successfully.

The matcher MUST cover both `Task` and `Agent` tool names, because the tool is
named `Agent` on current Claude Code and `Task` on older builds.

Evidence MUST be written to the branch ledger rather than to token-scoped
state, so that it is neither lost to session-token scattering nor to the 7-day
GC of token-scoped files.

A return with `tool_response.is_error` true MUST NOT record.

Reviewer identification MUST use a `subagent_type` allowlist. A
`general-purpose` dispatch MUST record only when its `description` matches a
review-intent pattern. The predicate MUST be biased toward under-crediting: a
missed real review costs a spurious advisory, whereas a wrongly credited
non-reviewer blinds the measurement the deny-flip depends on.

All failures — absent ledger library, unresolvable branch key, absent `jq`,
unwritable ledger — MUST exit 0 silently and MUST NOT alter any gate decision.

#### Scenario: a reviewer agent return is recorded

- **GIVEN** a `PostToolUse` payload with tool name `Agent`, `subagent_type`
  `pr-review-toolkit:code-reviewer`, and `is_error` false
- **WHEN** the reviewer-evidence hook runs
- **THEN** `reviewer-ran` is present in the branch ledger for the current
  repo and branch

#### Scenario: the older tool name is still recorded

- **GIVEN** the same payload with tool name `Task`
- **WHEN** the reviewer-evidence hook runs
- **THEN** `reviewer-ran` is present in the branch ledger

#### Scenario: an errored reviewer is not evidence

- **GIVEN** a reviewer payload with `is_error` true
- **WHEN** the reviewer-evidence hook runs
- **THEN** `reviewer-ran` is absent from the branch ledger

#### Scenario: an implementation agent is not credited

- **GIVEN** a payload with `subagent_type` `general-purpose` and a description
  describing implementation work
- **WHEN** the reviewer-evidence hook runs
- **THEN** `reviewer-ran` is absent from the branch ledger

### Requirement: The push gate distinguishes a claimed review from a performed one, advisorily

The outbound push/merge gate MUST evaluate a reviewer-evidence leg whose
population is exactly those actions where the `requesting-code-review`
milestone IS credited and `reviewer-ran` is absent.

The leg's ADVISORY MUST NOT be surfaced for `gh pr merge`, because every input
to the finding is computed from the local branch while a merge's subject is a
different PR.

The leg's diagnostic RECORD MUST be written only for pushes, and only where no
other gate leg denies the action. A merge record would name the wrong subject.
A record for a push that a different leg blocked can never be a false block
attributable to this leg, so it would enter the corpus as filler that biases
the pre-registered rate toward flipping to deny. Records are not
retro-classifiable, so a wrong population cannot be corrected after accrual.

The leg MUST be implemented as a single shared predicate invoked from **both**
sites that gate `requesting-code-review` — the chain-scoped check and the
repo-wide global fail-closed gate. A leg wired into only one site leaves the
other passing on the old milestone alone.

Recorded evidence MUST carry the SHA it was recorded at, and the leg MUST
surface staleness when that SHA differs from HEAD, matching the existing
milestone staleness advisory. Evidence that is not SHA-bound is weaker than the
milestone it supplements, because no reviewer agent is inherently timing-bound
to the pushed diff.

Where the `requesting-code-review` milestone was credited by a proxy skill
rather than the literal skill, the leg MUST record which proxy credited it, so
that proxy-credited episodes can be segmented during adjudication rather than
silently pooled.

The leg MUST be advisory: it MUST append to the advisory text and MUST NOT set
`permissionDecision`, and MUST NOT alter the gate's exit code.

Where the leg cannot evaluate — ledger library unsourceable, branch key
unresolvable — it MUST state the degradation rather than fall silent, because
silence is indistinguishable from a satisfied check.

Where `reviewer-ran` is present, the gate's output MUST be byte-identical to
its output before this change.

The leg MUST NOT accept a `phase_attest` attestation for `reviewer-ran`.
REVIEW and VERIFY reject attestation by deliberate asymmetry with IMPLEMENT;
accepting it for a REVIEW sub-signal would breach that asymmetry indirectly.

#### Scenario: claimed review without a reviewer produces an advisory only

- **GIVEN** a branch whose ledger contains `requesting-code-review` and not
  `reviewer-ran`
- **WHEN** `git push` is evaluated by the gate
- **THEN** the emitted JSON contains no `permissionDecision`
- **AND** the advisory text states that no reviewer subagent was observed

#### Scenario: evidence present leaves the gate unchanged

- **GIVEN** a branch whose ledger contains both `requesting-code-review` and
  `reviewer-ran`
- **WHEN** `git push` is evaluated by the gate
- **THEN** the output is byte-identical to the pre-change control fixture

#### Scenario: degradation is announced

- **GIVEN** `hooks/lib/branch-ledger.sh` is unreadable
- **WHEN** `git push` is evaluated by the gate
- **THEN** the gate still emits a decision
- **AND** the degradation is stated in the advisory text

#### Scenario: the global fail-closed gate is also taught

- **GIVEN** a branch whose ledger contains `requesting-code-review` and not
  `reviewer-ran`
- **WHEN** a push is evaluated on the repo-wide global fail-closed path with no
  active composition chain
- **THEN** the reviewer-evidence advisory is present on that path too

#### Scenario: stale evidence is surfaced

- **GIVEN** a `reviewer-ran` record whose recorded SHA differs from HEAD
- **WHEN** `git push` is evaluated by the gate
- **THEN** the advisory states that the evidence is stale, naming both SHAs

#### Scenario: a denied push writes no diagnostic record

- **GIVEN** a branch where `requesting-code-review` is credited, `reviewer-ran`
  is absent, and `verification-before-completion` is ALSO absent
- **WHEN** `git push` is evaluated and the gate denies on the missing VERIFY
  milestone
- **THEN** the gate denies exactly as it did before this change
- **AND** no reviewer-evidence diagnostic record is written
