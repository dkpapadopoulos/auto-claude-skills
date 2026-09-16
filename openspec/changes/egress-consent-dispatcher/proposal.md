# Proposal: an enforceable consent boundary for cross-family egress

## Why

`panel` and `second-opinion` send repository content to an external model vendor.
Since PR #253 the only thing between a routing mistake and that send is SKILL.md
prose ("ask, and wait for an answer") plus `hooks/outbound-consent-hook.sh`, which is
advisory by construction: it emits a `systemMessage` and can never block.

Four measured facts (2026-09-16) make "just flip the observer to deny" the wrong fix:

1. **The observer's population is not the consultation population.** 1,518 local
   transcripts over 60 days: ~250 cross-family tool calls, **zero** from
   `panel`/`second-opinion`. All came from `/codex:rescue`, direct `codex exec`, or the
   model proactively choosing the `codex:codex-rescue` subagent. None of those paths
   records consent, so a destination-keyed deny would have blocked ~100% of real use.
2. **The observer's predicate is not an egress predicate.** `*codex-companion*` also
   matches `status` (45) and `result` (23), which only read local job state.
3. **The consent record is agent-writable.** `scripts/record-outbound-consent.sh` is a
   Bash call the model can make without ever asking. A gate that allows on that file
   enforces "the model ran the record step", not "the user consented".
4. **The approved text is not the sent text.** `codex-rescue` may rewrite the prompt
   before its own Bash call, and Codex then reads workspace files itself.

The observer also writes no log, so warn-first as built can never produce the corpus a
deny flip is supposed to be earned from.

## What Changes

- **New sender: `scripts/consult-dispatch.sh`.** `prepare` freezes an exact package
  and prints its sha256; `send` refuses unless a single-use, fresh consent receipt
  names that digest, then runs `codex exec` read-only from an isolated temp directory
  on exactly those bytes. `panel` and `second-opinion` MUST send cross-family content
  only through it.
- **Consent from the user's answer, not a model-run script.** A PreToolUse hook on
  `AskUserQuestion` records a *clean ask* (no pre-filled `answers`, main thread only)
  for any question carrying an `[egress-consent:<digest>]` marker, and denies a marked
  question that arrives pre-answered. A PostToolUse hook writes the receipt only when
  that same `tool_use_id` was a clean ask, the selected label is the fixed approve
  label, and the selected option's preview hashes to the marker digest — so the
  receipt binds to the bytes the user saw.
- **Observer fixed and made measuring.** Payload-first token resolution; local
  companion verbs (`status`/`result`/`cancel`/`setup`/`--help`) excluded; each
  recognised cross-family dispatch that does not go through the dispatcher appends a
  text-free record to a shadow log. Still never a `permissionDecision`.
- **Escape hatch (user's choice):** `consultation.egress_consent: "warn"` in
  `~/.claude/skill-config.json` turns the refusal into a send that announces
  "consent enforcement is OFF" on every dispatch.
- `scripts/record-outbound-consent.sh` is retired.
- The 222-prompt negative routing corpus moves from a session scratchpad into
  `tests/probes/negative-corpus/`.

## Capabilities

### Modified
- `cross-family-panel` — cross-family sends go through an enforcing dispatcher bound
  to a user-answered, digest-matched, single-use receipt.

## Impact

- New: `scripts/consult-dispatch.sh`, `hooks/egress-consent-ask-hook.sh`,
  `hooks/egress-consent-receipt-hook.sh`, tests, probe corpus.
- Changed: `hooks/outbound-consent-hook.sh`, `hooks/hooks.json`,
  `hooks/session-start-hook.sh` (GC), `skills/panel/SKILL.md`,
  `skills/second-opinion/SKILL.md`, `skills/design-debate/SKILL.md`, `CLAUDE.md`.
- Removed: `scripts/record-outbound-consent.sh`.
- Unchanged, deliberately: `/codex:rescue`, direct `codex exec`, proactive
  `codex-rescue` (observed only), the Codex stop-time review gate (not a tool call;
  out of reach of any PreToolUse mechanism). Routing triggers are unchanged.
