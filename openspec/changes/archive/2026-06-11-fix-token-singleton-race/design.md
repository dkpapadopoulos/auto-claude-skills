# Design: Fix Token Singleton Race

## Architecture

The session token (`session-<transcript-basename>`, PR #47) is directly
derivable from every hook's own stdin payload — each Claude Code hook event
delivers `transcript_path`. Readers therefore never need the shared pointer
file: they compute the same value the SessionStart writer computed, race-free.

```
stdin payload ──jq .transcript_path──▶ session_token_from_transcript ──▶ token
      │ (missing field / no jq)
      └────────────▶ cat ~/.claude/.skill-session-token (fallback) ──▶ token
```

`hooks/lib/session-token.sh` (new) holds the format in one place:
- `session_token_from_transcript <path>` → `session-<basename .jsonl>`
- `resolve_session_token <stdin-json>` → payload-first, singleton fallback,
  empty string on total failure (callers already treat empty as skip).

Converted readers: `openspec-guard.sh`, `skill-activation-hook.sh`,
`skill-completion-hook.sh`, `consolidation-stop.sh`,
`compact-recovery-hook.sh` (whose stdin read moves above its token use —
previously it consumed the singleton at line 17 and only drained stdin at 50).
Writer `session-start-hook.sh` sources the lib for the primary derivation;
session_id / reuse-window / random fallbacks and the singleton write stay.

## Dependencies

None new. jq remains optional (singleton/grep fallbacks preserved). Bash 3.2.

## Decisions & Trade-offs

- **Payload-first vs per-transcript pointer files:** pointer files
  (`.skill-session-token-<hash>`) add an indirection layer to reach a value
  already computable from the payload, and don't help no-payload consumers
  either. Payload-first wins on simplicity and has no write path at all.
- **Never prefer "the token that has state":** resolution must not check which
  candidate token has a state file — that reintroduces the race (a foreign
  session's state would capture resolution). Payload always wins when
  derivable; a payload-derived token with no state simply no-ops the gates
  (fail-open, no false denies). Adversarial review proposed the narrower
  fail-closed variant "derived token has no state AND singleton differs →
  evaluate the singleton's state"; rejected deliberately: an ad-hoc push
  (legitimately no chain for this conversation) would then be gated against a
  foreign session's incomplete chain — exactly the issue #51 false-deny this
  change removes. The residual false-allow it would defend against requires
  the harness to deliver `transcript_path` to PreToolUse while withholding it
  from UserPromptSubmit/PostToolUse in the same session (the state writers);
  when the writers have it, state converges to the transcript-derived token
  and the guard agrees. No such asymmetric delivery has been observed.
- **jq fork budget (~50ms activation hook):** transcript extraction is batched
  into existing jq calls using the repo's `\x1f` field separator, transcript
  field FIRST because the prompt may contain arbitrary bytes while a path
  cannot contain `\x1f`. Activation hook: net forks unchanged. Completion
  hook: net forks reduced by one (three extractions merged).
- **Singleton retained + re-stamped:** four SKILL.md flows read the singleton
  from the conversation with no payload available. The activation hook
  re-stamps the singleton with its resolved token each routed prompt,
  narrowing that residual window to one prompt-width. Eliminating it is out
  of scope (revival trigger: a SKILL.md helper observed writing state to a
  wrong token).
- **Derivation mismatch accepted:** if SessionStart's payload lacked
  transcript_path (token = session_id/random) but in-turn payloads carry it,
  payload-derived tokens won't match the state files; gates no-op. Fail-open
  and lean-correct; rare enough not to warrant the state-sniffing hazard above.

## Implementation Notes (synced at ship time)

- Review round added two hardenings beyond the upfront design: the activation
  hook's singleton re-stamp uses tmp+`mv` (adversarial review demonstrated
  torn empty reads under a 60-writer hammer against the plain `>` write), and
  the lib's `basename` call gained `--` (BSD errors / GNU prints help text on
  dash-leading basenames; pinned by U5). Both consistent with the spec's
  scenarios; no requirement text changed.
- The fail-closed singleton-fallback variant proposed in adversarial review
  was rejected with rationale recorded under Decisions & Trade-offs.
- Test count grew from the planned 12 to 14 assertions (U5 + ST1, the
  consolidation-stop regression pin the standard review requested).
