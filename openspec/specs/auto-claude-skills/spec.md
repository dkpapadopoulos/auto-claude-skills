## Purpose

Plugin-level safety and observability infrastructure. Shared preflight scripts, composition-state guards, and cross-cutting checks that keep every phase's tooling honest — fail-open, bash 3.2 compatible, and consistent across all hooks.
## Requirements
### Requirement: On-Demand Observability Preflight
The plugin MUST provide a shared observability preflight script at `scripts/obs-preflight.sh` that checks gcloud authentication status, kubectl cluster connectivity, and GCP Observability MCP configuration.

The script MUST output JSON with keys `gcloud`, `kubectl`, `observability_mcp`, and `summary`.

The script MUST exit 0 always (fail-open). On internal error, it MUST emit a valid JSON error object and exit 0.

#### Scenario: All tools missing
- **WHEN** gcloud, kubectl are not on PATH and ~/.claude.json has no observability MCP configured
- **THEN** output MUST contain `{"gcloud":"missing","kubectl":"missing","observability_mcp":"unavailable",...}`

#### Scenario: gcloud unauthenticated
- **WHEN** gcloud is installed but has no active credentials
- **THEN** output MUST contain `{"gcloud":"unauthenticated",...}` with summary suggesting `gcloud auth login`

### Requirement: Preflight Integration in Observability Skills
The incident-analysis skill, alert-hygiene skill, and /investigate command MUST invoke `obs-preflight.sh` before performing data collection or tier selection.

#### Scenario: Skill activation with missing auth
- **WHEN** a user invokes incident-analysis and gcloud is unauthenticated
- **THEN** the skill MUST report the preflight issue before attempting any log queries

### Requirement: REVIEW-Before-SHIP Guard
The openspec-guard hook MUST warn when `requesting-code-review` is present in the composition chain but absent from the completed list during the SHIP phase.

The guard MUST NOT warn when no composition state file exists, when the phase is not SHIP, or when requesting-code-review is not in the chain.

The guard MUST remain fail-open (exit 0 always).

#### Scenario: REVIEW skipped during SHIP
- **WHEN** a git commit is attempted during SHIP phase with requesting-code-review in chain but not completed
- **THEN** the hook MUST emit a warning containing "REVIEW GUARD"

#### Scenario: No composition state
- **WHEN** a git commit is attempted during SHIP phase with no composition state file
- **THEN** the hook MUST NOT emit a REVIEW GUARD warning

### Requirement: CI-Time PR Review Backstop
The plugin MUST provide a GitHub Actions workflow at `.github/workflows/claude-code-review.yml` that runs `anthropics/claude-code-action` against every pull request touching plugin code (`skills/`, `commands/`, `hooks/`, `config/`, `scripts/`, `.claude-plugin/`, `.github/workflows/`, `CLAUDE.md`, `AGENTS.md`, `docs/eval-pack-schema.md`).

The workflow MUST be a **backstop**, not a replacement, for the in-session `requesting-code-review` step. The composition chain's in-session review remains the primary SDLC gate; the CI workflow catches PRs created without an active session.

The review prompt MUST encode the plugin's CLAUDE.md conventions: bash 3.2 compatibility, fail-open routing hooks, jq-optional fallback, US/SOH field separators, the 11,500-word `incident-analysis` ceiling, the `disable-model-invocation` rule for action-only skills, scope-duplication detection across existing skills, grep-`-F` for literal regex characters in runtime-output parsers, and a GitHub Actions security checklist (full peeled-SHA pinning for third-party actions, lockstep across workflows, env-block pattern for user inputs, fork-PR refusal, permission API gate, allowlist over denylist for tool restrictions).

#### Scenario: PR opened against plugin paths
- **WHEN** a pull request is opened or synchronized against a path matching `skills/**`, `hooks/**`, `config/**`, `.claude-plugin/**`, `.github/workflows/**`, or other listed plugin paths
- **THEN** the `claude-code-review.yml` workflow MUST trigger
- **AND** post exactly one structured review comment per push (deleting any prior review comment from the same workflow)

#### Scenario: PR with no plugin paths touched
- **WHEN** a pull request changes only documentation outside the listed paths (e.g., `README.md`, top-level `LICENSE`)
- **THEN** the workflow MUST NOT trigger

#### Scenario: Workflow paths touched without skill changes
- **WHEN** a pull request changes only `.github/workflows/*.yml`
- **THEN** the workflow MUST trigger
- **AND** the review prompt MUST receive `touched_workflows == true` so the GitHub Actions security checklist activates

### Requirement: Fork-PR Review Refusal
Workflows that access repository secrets and run against PR-derived code MUST include a fork-PR refusal step that compares `github.event.pull_request.head.repo.full_name` against `github.repository` and aborts before any subsequent step that touches secrets when the values differ.

The trigger MUST be `pull_request`, NOT `pull_request_target`. The `pull_request_target` event combined with checking out `pull_request.head.sha` is the classic exfiltration pattern and is forbidden.

#### Scenario: Fork PR opened
- **WHEN** an external contributor opens a PR from a fork
- **THEN** the workflow MUST emit a `::notice::` explaining the refusal
- **AND** MUST NOT execute any step that handles `CLAUDE_CODE_OAUTH_TOKEN` or other secrets

### Requirement: Action-Layer Tool Allowlist
The `claude-code-review.yml` workflow MUST restrict the action's tool surface via `claude_args --allowed-tools '<list>'` rather than `--disallowed-tools`. The allowlist MUST be the minimum set required for read-only review (`Read`, `Grep`, `Glob`, plus exact read-only Bash patterns such as `Bash(wc:*)`, `Bash(git diff:*)`, `Bash(git log:*)`, `Bash(git status:*)`, `Bash(git rev-parse:*)`).

Allowlist enforcement MUST be at the action layer, not relied upon as prompt-only guidance. Prompt text MAY explain the boundary for clarity but MUST NOT be the boundary itself.

#### Scenario: Adversarial PR attempts to invoke disallowed tool
- **WHEN** the review action is run against a PR whose contents instruct Claude to fetch a URL via `WebFetch` or run `gh api` to exfiltrate
- **THEN** the action layer MUST reject the tool invocation
- **AND** the model's attempt MUST NOT reach the GitHub or external network

### Requirement: Peeled Commit SHA Pinning
Third-party GitHub Actions that receive secrets or execute code from PR diffs (i.e., publishers other than `actions/` and `github/` orgs) MUST pin to a full 40-character peeled commit SHA, NOT the tag-object SHA, NOT a branch, NOT a short SHA.

The bump procedure MUST be a two-step peel: `gh api repos/<owner>/<repo>/git/refs/tags/<tag>` returns the annotated tag object SHA; `gh api repos/<owner>/<repo>/git/tags/<obj>` returns `.object.sha` which is the actual commit. Workflow comments MUST document this procedure.

GitHub-published actions (`actions/`, `github/` org publishers) on major-version tags are acceptable; SHA-pinning them is good hygiene but not required by this requirement.

#### Scenario: Bumping `claude-code-action`
- **WHEN** a contributor wants to bump the `anthropics/claude-code-action` pin
- **THEN** they MUST follow the peel procedure documented in `claude-code-review.yml`
- **AND** update all three workflows (`claude-code-review.yml`, `claude.yml`, `skill-eval.yml`) in the same change so SHAs remain in lockstep

### Requirement: `@claude` Assistant Hardening
The `.github/workflows/claude.yml` workflow MUST gate every `@claude` invocation through:
1. An `author_association` allow-list (`OWNER`, `MEMBER`, `COLLABORATOR`) as a cheap pre-filter in the job `if:` condition.
2. An authoritative permission API check (`gh api /repos/.../collaborators/<actor>/permission`) requiring `admin|write|maintain` as the first job step.
3. A fork-PR refusal step covering all four event types (`issue_comment`, `pull_request_review_comment`, `pull_request_review`, `issues`).

User-controlled inputs (comment body, issue title, branch name, etc.) MUST flow through `env:` blocks and be referenced as `"$VAR"` in `run:` shell, never as direct `${{ github.event.* }}` substitution.

The workflow MUST NOT request `id-token: write` permission unless the action is configured for OIDC token exchange (Bedrock/Vertex/Foundry). With `claude_code_oauth_token` authentication, OIDC is unused.

#### Scenario: Triage-role user mentions @claude
- **WHEN** a user with only triage permission comments `@claude fix this` on a PR
- **THEN** the `author_association` pre-filter may pass (triage may surface as COLLABORATOR in some configurations)
- **AND** the permission API check MUST reject with `permission == 'triage'`
- **AND** the workflow MUST NOT execute the action step

#### Scenario: Trusted user mentions @claude on a fork PR
- **WHEN** a maintainer comments `@claude` on a PR whose head is from a fork
- **THEN** the fork-PR refusal step MUST abort before checkout
- **AND** secrets MUST NOT be exposed to fork-derived code

### Requirement: Owned skills fit the post-compaction re-attach budget

Every owned `skills/<name>/SKILL.md` MUST be at most 19,500 bytes, so the whole file survives Claude Code's post-compaction re-attachment (first 5,000 tokens per skill). Detail beyond that MUST live in `skills/<name>/references/` files that the core names together with the condition under which to Read them. A skill not yet split, or one whose rules alone exceed the budget, MAY exceed the budget only while listed as pending with a recorded ceiling equal to its current size; the ceiling MAY rise only in a commit whose message states the reason, and a pending skill whose size changes without its ceiling changing in the same commit MUST fail the guard. A pending skill's core MUST be ordered rules-first. Its every-run rules and stop and approval gates MUST end inside the first 19,500 bytes, or be restated or indexed there. Each pinned span and restated line MUST have an end-offset cell in the skill's content test.

#### Scenario: An over-budget skill fails the guard
- **GIVEN** an owned SKILL.md of 19,501 bytes that is not on the pending list
- **WHEN** the skill-size test runs
- **THEN** it fails naming that file and its size

#### Scenario: A pending skill may not grow
- **GIVEN** a pending skill with a recorded ceiling of 47,871 bytes
- **WHEN** its SKILL.md grows to 47,900 bytes
- **THEN** the skill-size test fails

#### Scenario: A pending skill leads with its rules
- **GIVEN** a pending skill whose content test pins its every-run rule spans and restated gate lines by end offset
- **WHEN** any pinned span or restated line is moved, or grows, past byte 19,500
- **THEN** its content test fails naming that span or line

#### Scenario: A raise is recorded, never silent
- **GIVEN** a pending skill whose SKILL.md grows from 83,053 to 85,310 bytes because its gates are restated inside the re-attach window
- **WHEN** the same commit raises its recorded ceiling to 85,310 and its message states the reason
- **THEN** the skill-size test passes, and the raise is visible in the diff and the commit message

