## ADDED Requirements

### Requirement: Verdict artifact SHA freshness

The owned verification verdict artifact `~/.claude/.skill-project-verified-<token>` MUST record a `sha` field equal to `git rev-parse HEAD` at the time `project-verification` writes it, and the push gate MUST honor a verdict only when that `sha` covers the pushed HEAD (equals HEAD, or is an ancestor of HEAD on the current branch). A verdict whose `sha` is absent or does not cover HEAD MUST be treated as if no verdict were present, falling back to the status-layer behavior.

#### Scenario: Verdict covers the pushed HEAD
- **GIVEN** `~/.claude/.skill-project-verified-<token>` records `sha` equal to the current HEAD
- **WHEN** the push gate evaluates the verdict
- **THEN** the verdict MUST be honored (its clean/failed status governs)

#### Scenario: Stale or cross-branch verdict is ignored, never denies
- **GIVEN** a verdict artifact whose `sha` is absent, or names a commit that is not HEAD and not an ancestor of HEAD on the current branch
- **WHEN** the push gate evaluates the verdict
- **THEN** the verdict MUST NOT cause a denial
- **AND** the gate MUST fall back to the existing status-layer (`.completed` OR branch-ledger) behavior

### Requirement: Verify-verdict hardening

The push gate MUST deny `git push` when a verification verdict **at HEAD** (its `sha` equals HEAD) reports a test failure — `failed[]` non-empty — even if the status layer records `verification-before-completion` as completed. Only positive test-failure evidence at the exact pushed commit denies: a `could_not_verify[]` entry and a `suspect` gate-gaming status remain advisory and MUST NOT hard-block, and a failing verdict that is merely an ancestor of HEAD (a later commit may be fixed) MUST NOT deny. When no such verdict is present, the gate MUST preserve its status-only behavior and MUST NOT introduce a new denial.

#### Scenario: Failing verification at HEAD blocks the push despite recorded status
- **GIVEN** the status layer records `verification-before-completion` as completed
- **AND** a verdict whose `sha` equals HEAD reports `failed` containing `tests`
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny and name the failing gate (`tests`)

#### Scenario: Ancestor failing verdict does not block a later HEAD
- **GIVEN** a failing verdict whose `sha` is an ancestor of HEAD (HEAD advanced past it)
- **WHEN** `git push` is attempted
- **THEN** the gate MUST NOT deny on verdict grounds (the failure is authoritative only for the commit it was measured at)

#### Scenario: Absent verdict preserves status behavior
- **GIVEN** no verdict artifact exists for the session
- **AND** the status layer records `verification-before-completion` as completed
- **WHEN** `git push` is attempted
- **THEN** the gate MUST NOT deny on verdict grounds

### Requirement: Routing-governance push gate

In a skill-routing plugin repository (detected by the presence of `config/default-triggers.json`), when the pushed diff touches routing paths (`skills/`, `config/`, or `hooks/`), the push gate MUST require a clean verdict that covers the pushed routing changes: either a clean verdict at HEAD, or a clean verdict at an ancestor whose routing files are unchanged since. The gate MUST deny with a `project-verification` remedy when no clean verdict covers HEAD, or when a clean verdict is an ancestor but routing files changed after it (an unverified routing delta). A clean ancestor verdict with no routing change since MUST warn (advisory) rather than deny. This gate MUST fire independent of an active composition chain. Repositories without `config/default-triggers.json` MUST NOT be subject to this gate.

#### Scenario: Routing change without a clean verdict is denied
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `hooks/`
- **AND** no clean verdict covering the branch exists
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny and instruct the user to run `Skill(auto-claude-skills:project-verification)`

#### Scenario: Routing change with a clean covering verdict is allowed
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `config/`
- **AND** a clean verdict covering HEAD exists
- **WHEN** `git push` is attempted
- **THEN** the gate MUST allow the push

#### Scenario: Routing changed after an ancestor verdict is denied
- **GIVEN** the repository contains `config/default-triggers.json`
- **AND** a clean verdict exists whose `sha` is an ancestor of HEAD
- **AND** a routing file (`skills/`, `config/`, or `hooks/`) changed in a commit after that `sha`
- **WHEN** `git push` is attempted
- **THEN** the gate MUST deny (the routing delta is unverified) and instruct the user to run `Skill(auto-claude-skills:project-verification)`

#### Scenario: Non-routing repository is unaffected
- **GIVEN** the repository does not contain `config/default-triggers.json`
- **AND** the pushed diff modifies a file under `skills/`
- **WHEN** `git push` is attempted
- **THEN** the routing-governance gate MUST NOT deny the push

### Requirement: Review milestone remains status-only

The push gate MUST NOT derive a pass/fail verdict for `requesting-code-review` from the skill's return text or any model-attested signal. The review milestone MUST remain governed by the status layer only.

#### Scenario: Review is not verdict-gated
- **GIVEN** `requesting-code-review` has returned and is recorded in the status layer
- **WHEN** the push gate evaluates review readiness
- **THEN** the gate MUST rely on the status layer alone and MUST NOT parse review output for a verdict
