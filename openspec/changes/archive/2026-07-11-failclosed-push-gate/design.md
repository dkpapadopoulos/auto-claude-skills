# Design: Fail-closed push gate

## Architecture

The push gate lives in the `git push` branch of the `PreToolUse` hook
`hooks/openspec-guard.sh`. Three composition-independent gates now run in order,
all fail-open on infrastructure error:

1. **Composition-scoped gate** (pre-existing) — when an active composition state
   file exists, denies pushes that skipped a chain-member REVIEW/VERIFY milestone.
2. **Global fail-closed gate** (this change) — fires for every agent push. Denies
   unless the branch carries a durable `requesting-code-review` record AND a passing
   `verification-before-completion` signal. Evidence sources, in order of strength:
   branch-ledger milestone (`branch_ledger_has`), session-local `.completed`
   fallback (write-lag window), and a SHA-bound clean verdict (`verdict_is_clean` +
   `verdict_covers_head`) which is stronger VERIFY evidence than a status milestone.
3. **Routing-governance gate** (pre-existing) — pushes touching `skills/|config/|hooks/`
   in a routing repo require a clean verdict covering HEAD.

### Human/agent boundary
A `PreToolUse` hook only intercepts the agent's Bash tool calls, so a human pushing
from their own terminal never reaches the gate — this is the structural (not
heuristic) escape hatch. The in-session override `ACSM_SKIP_PUSH_GATE=1` is read
ONLY from the hook's own process environment, inherited from the environment that
launched Claude Code. A human sets it; the agent cannot mutate the hook's process
env from a Bash subshell.

## Dependencies

None new. Reuses `hooks/lib/branch-ledger.sh` and `hooks/lib/verdict.sh`.

## Decisions & Trade-offs

- **Human-only bypass (no inline command-string scan).** An earlier form also
  matched `*ACSM_SKIP_PUSH_GATE=1*` in the command string. Because the agent
  composes that string, it could self-exempt from the gate — an agent-forgeable
  bypass contradicts "fail-closed." Rejected in favor of env-var-only, which is
  genuinely human-gated. The human retains two bypasses (terminal push, or relaunch
  with the env var exported), so no legitimate workflow is stranded.
- **jq presence is required for the gate to run.** Every evidence leg is
  jq-dependent (the ledger's sole writer exits early without jq; the `.completed`
  fallback is jq-guarded; the verdict lib returns non-clean without jq). Without jq
  no evidence is establishable, so denying every push would violate the "jq optional
  at runtime, fail-open" invariant. The gate guards on `command -v jq`, matching the
  composition block. This was a review finding (the reader lib loading does not imply
  the writer could ever have run).
- **Fail-open bias throughout.** Only a check that runs and finds NO record denies;
  missing lib, missing jq, or an unresolvable state degrades to allow.

## Implementation Notes (synced at ship time)

- Built retrospectively: a prior session implemented the base gate (commit 4cc4e32);
  this session ran REVIEW, applied two Important review findings (jq fail-open,
  human-only bypass), and re-verified (commit 9a7f1c5). No upfront design doc existed.
- Red-green verified: the three new test assertions (no inline-scan wiring, inline
  bypass rejected, no-jq fail-open) each fail against the un-fixed hook and pass with
  the fix.
