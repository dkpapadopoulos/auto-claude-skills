# Proposal: compact-recovery prompt-carrier

## Why

Post-compaction state recovery is silently dead for automatic compaction. Evidence
(2026-07-15 probe, `~/.claude/.compact-events.log` + surviving transcripts):

- Every auto-compaction through 2026-06-02 was followed by a recovery event.
- The three most recent auto-compactions (Jun 10, Jun 18 @ CC 2.1.179, Jun 29 @ CC
  2.1.195) fired `PreCompact` (`trigger=auto` logged) but produced **no**
  `SessionStart(source=compact)` event and **no** `compact_boundary` transcript
  record, while both sessions continued for hours afterward.
- Manual `/compact` at the *adjacent* version (2.1.178, Jun 17) wrote a
  `compact_boundary` and recovery fired.

Conclusion: since Claude Code ~2.1.179, auto-compaction no longer emits
`SessionStart(source=compact)`. `hooks/compact-recovery-hook.sh` is keyed
exclusively to that event, so composition-chain and team-checkpoint recovery now
happens only on manual `/compact` — precisely the wrong way round, because auto
compaction is the unattended case where re-injection matters most (arXiv:2606.22528
measures constraint violations rising 0%→30-59% when declared constraints are lost
to compaction).

Secondary gap (adopted from the constraintguard triage, 2026-07-15): the recovery
payload omits the confirmed-intent marker and the active OpenSpec change context, so
even a successful manual recovery loses the intent/out-of-scope boundary outside
DESIGN phase.

## What Changes

1. `hooks/pre-compact-hook.sh` writes a per-session-token pending-compaction marker
   (`~/.claude/.skill-compact-pending-<token>`) — before its cozempic dependency
   check, which today aborts the hook (including event logging) on machines without
   cozempic.
2. `hooks/compact-recovery-prompt-hook.sh` (new, dedicated `UserPromptSubmit`
   hook, registered in `hooks/hooks.json` with a 5s timeout, after
   `skill-activation-hook.sh`) checks for the marker via a single `compgen -G`
   glob test; when present it emits the recovery context and clears the
   marker. The no-marker path costs one glob test — no stdin read, no jq
   fork — independent of the activation hook's own routing budget.
3. Recovery rendering moves to a shared lib (`hooks/lib/compact-recovery-render.sh`)
   used by both the new prompt-carrier path and the existing
   `compact-recovery-hook.sh` (kept: it recovers instantly on manual `/compact`
   and clears the marker so the next prompt does not double-inject).
4. The rendered payload additionally includes the confirmed-intent marker
   (`~/.claude/.skill-confirmed-intent-<token>`) and a bounded summary of
   non-archived entries in the session's OpenSpec `changes` map.

## Capabilities

### Modified
- `compact-recovery` — post-compaction state re-injection (carrier + payload).

## Impact

- Touched: `hooks/pre-compact-hook.sh`, `hooks/compact-recovery-hook.sh`,
  new `hooks/compact-recovery-prompt-hook.sh`, new
  `hooks/lib/compact-recovery-render.sh`, `hooks/hooks.json` (registration),
  new `tests/test-compact-recovery.sh`.
- No routing/scoring changes; no registry or config changes. All additions
  fail-open. Concurrent sessions are isolated by session-token-scoped marker and
  state files.
- Out of scope: a user-declared session-rules ledger (constraintguard triage item
  3) — separate DESIGN-phase feature with its own eval.
