# pdlc-safety (delta)

## ADDED Requirements

### Requirement: Remote merges via gh are gated on the same milestones as push

An agent Bash command that actually invokes a PR merge MUST pass the same
REVIEW and VERIFY evidence gates as `git push` (composition checks,
verify-hardening, global fail-closed gate). This covers `gh pr merge` in any
flag order (including `--auto` and `-R/--repo`) and `gh api` naming the REST
pull-merge path or GraphQL `mergePullRequest`. `gh pr create` MUST NOT be gated. Detection MUST be
invocation-based (segment-aware), not phrase-based: a command that merely
mentions the words MUST NOT trigger the gate. All denies MUST honor the
human-only bypass and fail open on infrastructure errors (missing jq, missing
libs). Routing-governance remains push-scoped.

#### Scenario: gh pr merge without milestones is denied

- **GIVEN** a branch with no REVIEW/VERIFY evidence (empty ledger, empty
  `.completed`, no verdict)
- **WHEN** the agent runs `gh pr merge 123 --auto` through the Bash tool
- **THEN** the guard MUST deny, naming the missing milestone(s)

#### Scenario: gh pr merge with full evidence is allowed

- **GIVEN** a branch whose ledger carries both milestones and a clean verdict
  covering HEAD
- **WHEN** the agent runs `gh pr merge 123`
- **THEN** the guard MUST NOT deny

#### Scenario: gh pr create and phrase mentions stay ungated

- **GIVEN** any evidence state
- **WHEN** the agent runs `gh pr create --title "gh pr merge fix"` or a
  command that only mentions "gh pr merge" as data (e.g. `echo "gh pr merge"`)
- **THEN** the guard MUST NOT deny

### Requirement: Compound mutate-then-push commands are denied

A single Bash command MUST be denied when a content-mutating git subcommand
(`commit`, `merge`, `cherry-pick`, `rebase`, `revert`, `am`) is invoked in a
segment ordered before a `git push` segment, regardless of evidence state (the gate evaluates pre-exec state, so no evidence can cover the
not-yet-created commit), with a remedy instructing the agent to run the push
as a separate command. The deny MUST honor the human-only bypass. `git pull
&& git push` and a plain `git push` MUST NOT match.

#### Scenario: commit-and-push in one command is denied even with clean evidence

- **GIVEN** a branch with both milestones recorded and a clean verdict at HEAD
- **WHEN** the agent runs `git commit -m "fix" && git push origin HEAD`
- **THEN** the guard MUST deny with the separate-command remedy

#### Scenario: push as its own command is unaffected

- **GIVEN** the same evidence state
- **WHEN** the agent runs `git push origin HEAD` alone
- **THEN** the compound rule MUST NOT fire (other gates evaluate as usual)
