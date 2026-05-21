# Tasks: Pre-PR Stack Improvements

## Completed

- [x] 1.1 Add `test_fallback_registry_in_sync_with_default_triggers` to `tests/test-registry.sh`
- [x] 1.2 Resolve initial drift (`forgetful_memory` key alignment)
- [x] 2.1 Add failing regression test `test_max_iterations_role_allowlist` to `tests/test-routing.sh`
- [x] 2.2 Add iteration-cap enforcement to `_score_skills` in `hooks/skill-activation-hook.sh` with hardcoded role-allowlist (`domain` + `required` only)
- [x] 2.3 Set `max_iterations: 1` on `agent-team-review` in `config/default-triggers.json`
- [x] 2.4 Regenerate `config/fallback-registry.json` to match
- [x] 2.5 Add CLAUDE.md gotcha entry naming the invariant and push-gate independence
- [x] 3.1 Add passive telemetry append block to `hooks/skill-completion-hook.sh`
- [x] 3.2 Smoke-test telemetry write (JSONL line confirmed with all 4 fields)
- [x] 4.1 Full test suite pass: 46/46 files
- [x] 4.2 Code review: no critical, no important findings
