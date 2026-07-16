# Design: compact-recovery prompt-carrier

## Architecture

Two-emitter, one-renderer, marker-coordinated:

```
PreCompact (auto + manual, still fires on both — proven)
  └─ pre-compact-hook.sh
       ├─ log event (moved above dependency checks)
       ├─ write ~/.claude/.skill-compact-pending-<token>   ← NEW marker
       └─ cozempic checkpoint + prune (unchanged, still optional)

SessionStart matcher=compact (manual /compact only, since CC ~2.1.179)
  └─ compact-recovery-hook.sh
       ├─ render_compact_recovery <token>                  ← shared renderer
       └─ rm marker                                        ← consumes it

UserPromptSubmit (every prompt, every version)
  └─ compact-recovery-prompt-hook.sh          ← NEW, registered after
       ├─ compgen -G marker glob — sole cost     skill-activation-hook.sh
       │  on the common path (no stdin, no jq)
       └─ if our token's marker exists: render_compact_recovery <token>,
          rm marker, emit hookSpecificOutput additionalContext
```

`hooks/lib/compact-recovery-render.sh` renders, in order: team checkpoint
(`~/.claude/team-checkpoint.md`), composition chain state
(`.skill-composition-state-<token>`), confirmed intent — read directly from
`~/.claude/.skill-confirmed-intent-<token>` via `head -c 2048`, no lib
sourcing — and a bounded (max ~6 lines) summary of
non-archived `changes` entries (slug, capability, design/spec paths) from
`.skill-openspec-state-<token>`. Output framed as recovered reference state.

Whichever emitter runs first consumes the marker; the other emits nothing.
Marker files older than 24h are ignored-and-removed (stale-marker guard: a
crashed session must not inject into a much later one that reuses the token).

## Trade-offs

- **UserPromptSubmit carrier vs SessionStart matcher change**: no `SessionStart`
  event exists on auto-compaction any more (probe: no `compact_boundary`, no
  recovery, session continues) — a matcher cannot catch a non-event. Rejected.
- **Recovery at next prompt vs immediately**: the prompt-carrier injects one turn
  late. Acceptable: identical timing to constraintguard's mechanism, and the
  manual path keeps immediate recovery via the retained SessionStart hook.
- **Integrating into skill-activation-hook vs a new UserPromptSubmit hook**:
  the activation hook has 8+ early-exit paths (short prompts, greetings,
  zero-match, etc.) that would swallow recovery on exactly the prompt most
  likely to follow an auto-compaction ("proceed"). A dedicated hook's common
  path is one `compgen -G` glob test, so the per-prompt cost argument for
  integrating was moot — the dedicated hook wins on both correctness and
  budget.
- **Marker vs re-deriving "compaction happened" from transcripts**: transcript
  heuristics are version-fragile — the exact fragility that caused this bug.
  The marker is written by the one hook proven to still fire.

## Decisions

- Token resolution is payload-first via `resolve_session_token_from_transcript`
  (issue #51 discipline), falling back to the singleton token file.
- `pre-compact-hook.sh` reordering is a bug fix in its own right: today a
  cozempic-less machine exits before logging the compaction event.
- Marker content: `<utc-timestamp> trigger=<auto|manual>` — human-debuggable,
  and the renderer surfaces the trigger in its header.
- Renderer reads `~/.claude/.skill-confirmed-intent-<token>` directly
  (`head -c 2048`, no lib sourcing) — sidesteps the ERR-trap /
  unguarded-source gotcha entirely for that section; the composition and
  openspec-changes sections are gated behind a single `command -v jq` check,
  so every sub-render degrades independently.
- Telemetry: the prompt-carrier path appends `event=post_compact_prompt` to
  `~/.claude/.compact-events.log`, so carrier drift stays observable the same
  way this bug was found.

## Dissenting views

Codex sparring (2026-07-15) endorsed the carrier move; it flagged that the
OpenSpec state has no scalar "active slug" — hence the bounded map summary
rather than a single-slug lookup. Filing the upstream regression (SessionStart
source=compact no longer fired on auto-compaction) is worthwhile but out of
scope here.

## Implementation Notes (synced at ship time)
- Carrier moved from a skill-activation-hook integration to the dedicated
  `hooks/compact-recovery-prompt-hook.sh` (amendment b79beec): the activation
  hook's early-exit paths would swallow recovery on short post-compaction
  prompts. Spec/proposal synced in d0d6e2c.
- Final review added: orphaned-marker GC joined the session-start state prune
  (with an explicit current-token exclusion — the `*-state-<token>` pattern
  cannot protect the marker name), and the prompt-carrier JSON emission is
  guarded against jq failure (spec Scenario 4).
- Renderer hardening from task review: confirmed-intent renders without jq;
  negative `current_index` clamps to "unknown" (jq negative-index wraparound
  was reachable via the walker's `-1` initialization).

## Out-of-Scope

- Session-rules ledger for ad-hoc user directives (constraintguard item 3).
- Any change to routing, scoring, push-gate, or composition-walker logic.
- Upstream Claude Code bug report (tracked separately).
