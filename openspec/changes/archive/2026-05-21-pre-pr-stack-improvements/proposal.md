## Why

Two documented pain points in the pre-PR review stack remained unaddressed despite the stack already being heavy. (a) Silent drift between `config/default-triggers.json` and `config/fallback-registry.json` on jq-less setups produced cases where new triggers never fired (memory: `feedback_default_triggers_source_of_truth`). (b) Advisory review iterations past the first produce diminishing-to-contradictory signal — PR #34 iteration 3 went as far as asking to revert a deliberate Task-1 decision (memory: `feedback_bot_review_asymptote`), and the documented 2-3 iteration policy was admitted to have been blown past with no mechanical enforcement.

A 3-perspective design debate (architect/critic/pragmatist) plus an independent Codex assessment converged on the unpopular answer: the marginal value of adding more lenses is near zero, and the leverage is in *trim plus measure*. Three small additions implement that conclusion without expanding the stack.

## What Changes

- **Fallback-registry drift gate** — `tests/test-registry.sh::test_fallback_registry_in_sync_with_default_triggers` regenerates `fallback-registry.json` from `default-triggers.json` using the same jq pipeline session-start uses and fails on any diff. Closes the silent drift class on jq-less setups.

- **Per-skill iteration cap with role-allowlist** — new optional `max_iterations` field in trigger blocks; honored by `hooks/skill-activation-hook.sh::_score_skills` only for skills with `role: domain` or `role: required`. Process and workflow roles are NEVER capped — invariant hardcoded in the hook, not config-driven, locked by `tests/test-routing.sh::test_max_iterations_role_allowlist`. Applied to `agent-team-review` (cap 1).

- **Passive advisory-lens telemetry** — `hooks/skill-completion-hook.sh` appends one JSONL line per Skill completion to `~/.claude/.advisory-lens-log.jsonl` with hashed session token and a coarse line-count proxy. No labels, no aggregation, no rotation in v1. Substrate for evidence-based trim decisions in 30+ days.

## Capabilities

### Modified Capabilities

- `skill-routing`: adds the iteration-cap requirement and role-allowlist invariant; adds the fallback-registry sync requirement; adds the passive telemetry requirement.

## Impact

- **Code:** `hooks/skill-activation-hook.sh` (+25 lines, cap-check block inside `_score_skills`), `hooks/skill-completion-hook.sh` (+31 lines, telemetry append block), `tests/test-registry.sh` (+71 lines, sync gate), `tests/test-routing.sh` (+94 lines, role-allowlist regression).
- **Config:** `config/default-triggers.json` (`max_iterations: 1` added to `agent-team-review`), `config/fallback-registry.json` (regenerated).
- **Docs:** `CLAUDE.md` gotcha entry explicitly naming the role-allowlist invariant and push-gate independence.
- **Push gate:** untouched. `hooks/openspec-guard.sh` enforcement of composition state remains authoritative for SHIP gating.
- **Dependencies:** none new. Bash 3.2 + jq, both already required.
- **Runtime:** activation hook adds one bounded jq fork per matched domain/required skill; cap fires only when composition state is non-empty for the session.
- **Telemetry side effect:** new append-only file `~/.claude/.advisory-lens-log.jsonl` per user.
