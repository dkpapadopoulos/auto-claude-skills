# Tasks: Fail-closed push gate

## Completed

- [x] 1.1 Add global fail-closed push gate to `hooks/openspec-guard.sh` (composition-independent REVIEW+VERIFY enforcement)
- [x] 1.2 Scope the gate to the agent (PreToolUse hook; human terminal push unaffected)
- [x] 1.3 Review finding: guard the gate on `command -v jq` so a no-jq env falls open
- [x] 1.4 Review finding: remove the agent-forgeable inline command-string bypass; honor only a human-set env var
- [x] 1.5 Refresh the stale composition-header comment (two composition-independent gates)
- [x] 1.6 Tests: `tests/test-push-gate-failclosed.sh` — human-only bypass, verify-leg isolation, no-jq fail-open, review/verify deny paths (red-green verified; 12/12)
- [x] 1.7 Update CHANGELOG entry to reflect human-only bypass + jq fail-open

Note: no Superpowers execution plan was archived for this feature — it was recovered
from a prior session's commit (4cc4e32) and hardened via review (9a7f1c5). See git log.
