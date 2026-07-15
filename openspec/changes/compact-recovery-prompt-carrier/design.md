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
  └─ skill-activation-hook.sh
       ├─ [ -f marker ] — single stat on the common path
       └─ if present: render_compact_recovery <token> into output, rm marker
```

`hooks/lib/compact-recovery-render.sh` renders, in order: team checkpoint
(`~/.claude/team-checkpoint.md`), composition chain state
(`.skill-composition-state-<token>`), confirmed intent
(`openspec_state_read_intent`), and a bounded (max ~6 lines) summary of
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
- **Integrating into skill-activation-hook vs a new UserPromptSubmit hook**: a
  separate hook script costs a full bash+jq startup on every prompt; integration
  costs one `[ -f ]`. Budget wins; fail-open wrapping keeps the activation hook's
  routing path safe from renderer errors.
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
- Renderer sources `openspec-state.sh` guarded (`|| true`) per the ERR-trap /
  unguarded-source gotcha; every sub-render degrades independently.
- Telemetry: the prompt-carrier path appends `event=post_compact_prompt` to
  `~/.claude/.compact-events.log`, so carrier drift stays observable the same
  way this bug was found.

## Dissenting views

Codex sparring (2026-07-15) endorsed the carrier move; it flagged that the
OpenSpec state has no scalar "active slug" — hence the bounded map summary
rather than a single-slug lookup. Filing the upstream regression (SessionStart
source=compact no longer fired on auto-compaction) is worthwhile but out of
scope here.

## Out-of-Scope

- Session-rules ledger for ad-hoc user directives (constraintguard item 3).
- Any change to routing, scoring, push-gate, or composition-walker logic.
- Upstream Claude Code bug report (tracked separately).
