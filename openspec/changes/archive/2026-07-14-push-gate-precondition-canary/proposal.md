# Proposal: Push-gate precondition canary at session start (audit F5)

## Why

The push gate is deliberately fail-open on infrastructure error: missing jq
makes every evidence leg unestablishable, and a missing/unsourceable
`hooks/lib/branch-ledger.sh` silently skips the entire global fail-closed
gate (`_LEDGER_OK` guard). Those are the right deny-semantics, but the
degradation is INVISIBLE — the 2026-07-14 enforcement audit (F5, medium)
found no signal anywhere that the gate has collapsed; an environment could
run for weeks with enforcement silently off. The audit's agreed remedy:
surface degradation at session start, where a human actually reads output.

## What Changes

- `hooks/session-start-hook.sh`, two additions:
  1. **jq-less path** (existing early-exit message): the fallback MSG now
     also states that the fail-closed push gate cannot establish evidence
     and falls open until jq is installed. (This path cannot use jq, so the
     wording stays a simple ASCII string.)
  2. **jq path — canary block**: existence-check plus a single
     `/bin/bash -n` parse (one fork, all files) over the gate's load-bearing
     components — `hooks/openspec-guard.sh`, `hooks/lib/branch-ledger.sh`,
     `hooks/lib/verdict.sh`, `hooks/lib/git-command.sh`,
     `hooks/lib/session-token.sh`. Any missing or unparseable file appends
     one `PUSH-GATE CANARY:` warning naming the component and stating the
     consequence (gate silently falls open / affected checks skipped).
     Healthy environments emit NOTHING (no noise). The canary itself is
     fail-open: any error in the check degrades to no warning, never a
     broken session start.
- New behavioral test `tests/test-push-gate-canary.sh`: runs the REAL hook
  in a temp plugin root — healthy → no canary; syntax-broken lib → canary
  naming it; deleted lib → canary; jq-less PATH → gate-falls-open wording.

## Capabilities

- **Modified: pdlc-safety** — gate degradation visibility.
- Touched: `hooks/session-start-hook.sh`, `tests/test-push-gate-canary.sh`,
  CLAUDE.md (gotcha note), CHANGELOG.

## Impact

- Closes audit F5: silent gate collapse becomes a visible session-start
  warning. No enforcement behavior changes — visibility only.
- Budget: one extra fork (`/bin/bash -n` batched over 5 files) + stat calls
  on the jq path; measured against the 200ms session-start budget.
- Bash-3.2 parse check doubles as a regression tripwire for the documented
  "quoted operands in $(( ))" class of hook-killing syntax errors.
