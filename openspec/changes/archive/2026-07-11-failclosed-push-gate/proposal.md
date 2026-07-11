## Why

The push gate in `hooks/openspec-guard.sh` had a fail-open hole: its deny logic
was nested under `if [ -f "$_COMP_STATE" ]`, so a `git push` from a session with
**no active composition state** (not driven by the spec-driven preset) was allowed
unconditionally. The entire REVIEW→VERIFY gate could be sidestepped by simply not
being in a driven session — the most common way an agent pushes un-reviewed,
un-verified work.

## What Changes

A global fail-closed gate now fires for **every** agent-attempted push, composition
or not, and denies unless the branch carries **both** a durable `requesting-code-review`
record **and** a passing `verification-before-completion` signal (branch-ledger
milestone, session-local `.completed` fallback, or a SHA-bound clean verdict). The
gate is scoped to the AGENT (a Claude Code PreToolUse hook — human terminal pushes
never reach it) and is fail-open on infrastructure error: it runs only when the
ledger lib loaded AND `jq` is present, because every evidence leg is jq-dependent.

The in-session override `ACSM_SKIP_PUSH_GATE=1` is honored **only** as a human-set
env var in the hook's own (Claude Code launch) process — the command string is
deliberately NOT scanned for the token, since the agent composes that string and an
inline scan would be an agent-forgeable bypass that defeats a fail-closed gate.

## Capabilities

### Modified Capabilities
- `skill-routing`: adds the global fail-closed push-gate requirement to the push-gate
  governance contract (composition-independent REVIEW+VERIFY enforcement, human-only
  bypass, and jq/infra fail-open).

## Impact

- `hooks/openspec-guard.sh` — global fail-closed gate + human-only bypass + jq fail-open guard.
- `tests/test-push-gate-failclosed.sh` — new suite (12 cases): human-only bypass,
  verify-leg isolation, no-jq fail-open, review/verify deny paths.
- No change to `test-push-gate-ledger.sh` / `test-push-gate-verdict.sh` (regression-clean).
- Dogfooding: because this is a routing repo, pushes touching `skills/|config/|hooks/`
  now require a clean verification verdict covering HEAD.
