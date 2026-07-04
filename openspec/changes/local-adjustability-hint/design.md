# Design: Local-Adjustability Hint

## Architecture

A single guarded block in `hooks/session-start-hook.sh`, placed immediately after the existing previous-session stats computation (`_PREV_ZM` from `.skill-zero-match-count`, `_PREV_TOTAL` from summed `.skill-prompt-count-*`) and before those files are cleaned. The block computes eligibility and, when eligible, appends one line to the session banner and touches the cooldown marker.

Eligibility (all must hold; each check individually guarded):
1. `_PREV_ZM` and `_PREV_TOTAL` are validated-numeric (already guaranteed by the existing block) with `_PREV_ZM >= 5`, `_PREV_TOTAL >= 8`, and `_PREV_ZM * 100 / _PREV_TOTAL >= 30` (integer arithmetic on validated operands — the Bash-3.2 quoted-`$(( ))` gotcha applies).
2. Cooldown: `~/.claude/.skill-adjustability-hint-last` absent OR older than 7 days (mtime compare via `find -mtime +6`, which matches only at ≥7 elapsed days — note the pre-existing state-prune uses `-mtime +7` for the same intent, a known off-by-one; do not copy that constant; malformed/missing → treated as expired).
3. No existing per-skill overrides: `jq -e '.skills | type == "object" and length > 0' ~/.claude/skill-config.json` false or errors. file absent or jq erroring → no overrides → still eligible. (A literal jq-missing environment never reaches this code: session-start exits at Step 2 without jq; the `command -v jq` guard in the block is defensive-only.)

Hint line (single banner line, no new JSON surface):
`Routing hint: last session <N> of <M> prompts matched no skill (<R>%). Tune triggers locally via ~/.claude/skill-config.json (missed prompts: ~/.claude/.skill-zero-match-log; debug a prompt with SKILL_EXPLAIN=1).`

On emission: `touch ~/.claude/.skill-adjustability-hint-last || true`.

## Trade-offs

- **Retrospective (fires one session late)** vs. in-session emission from the activation hook: chosen deliberately — a full-session denominator gives an honest rate, the activation hook's ~50ms budget and deliberate zero-match silence stay untouched, and once-per-session is structural rather than needing in-session dedup state.
- **Rate + floor thresholds** (5 misses, 8 prompts, 30%) vs. simple count: raw counts false-fire on long conversational sessions where unrouted prompts are correct behavior. The floors keep tiny sessions (1 miss of 2 prompts = 50%) from firing.
- **7-day cooldown** vs. every qualifying session: a user who ignores the hint has decided; repeating it daily is nag, not signal.
- **Suppress on existing overrides** vs. always hint: someone with per-skill overrides already knows the mechanism; the marginal value is negative (noise).

## Dissenting views

- "Emit in-session for timeliness" — rejected: breaks the zero-match path's deliberate silence, adds hot-path cost, and cannot compute an honest rate mid-session.
- "Include sample missed prompts in the hint" — rejected: the log path is one hop away, and echoing prompt text into the banner inflates every session start for marginal value.
- "Make thresholds configurable" — rejected (YAGNI): constants until real usage shows the defaults are wrong.

## Decisions

1. Session-start emission, previous-session rate evidence (approach A of three considered).
2. Thresholds: ZM ≥5, total ≥8, rate ≥30%; cooldown 7 days. Constants in the hook, named at the top of the block.
3. Cooldown marker is a bare `touch` file — mtime is the datum; no content, no token scoping (the hint is per-user, not per-session).
4. All failure modes suppress the hint (fail-open): unreadable files, non-numeric counters, jq errors, `find` errors, marker touch failure.
5. Capability: extends `skill-routing` (HIGH-confidence noun-family match; no new capability).
