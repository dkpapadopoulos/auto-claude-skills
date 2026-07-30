# Proposal: no private memory text on a public tracker (fix #174)

## Why

`improvement-miner` instructs the model to quote local memory files **verbatim**
(`skills/improvement-miner/SKILL.md:59`, `:77`) and then publishes that text with
`gh issue create --body-file` (`:150-152`). This repo is public. Nothing on that
path inspects what the text says.

The one control that looks adjacent is not one. `SKILL.md:140-145` mandates
`--body-file` over string interpolation, scoped explicitly to **command
injection** — "a backtick or `$( )` embedded in a title/body would otherwise
execute in the user's shell". It governs how the bytes are *passed*, never what
they *mean*. `scripts/mine-evidence.sh`'s documented trust boundary (author
allowlist, field exclusion) governs what the miner may **read**, never what it
may **publish**.

### The mechanism is live, and larger than #174 states

Measured 2026-07-29 against the local corpus (164 files) at 16-word granularity,
after subtracting text already present in the repo's tracked content:

| population | flagged |
|---|---|
| miner-authored issues | **7 of 8** — #124 #125 #127 #137 #138 #142 #143 (only #129 clean) |
| non-miner issues | 1 of 19 — **#131**, a genuine 16-word verbatim run, human-authored |

#174 reports 3 of 8. That count came from checking only `^> ` blockquote lines;
most leakage is verbatim prose embedded in the body, which line-level matching
misses. Spot-checked: #127's first hit originates in
`project_push_gate_unexplained_live_deny.md`; #131's in
`push_gate_status_layer_no_cross_token_bridge.md`.

Severity of what has already shipped stays **low by luck, not design** — those
source files carry no org/client tokens. #174 measured **21 of 162** memory files
that *do* name an org or client, and they are quotable by the identical path.

### Why prose cannot fix it

`CLAUDE.md` and `feedback_anonymize_before_public_commit` already carry an
"anonymize before public commit" rule. It is enforced nowhere on the one path
that publishes. That is the shape this repo has repeatedly found inadequate
(`feedback_verification_prose_self_policing_theater`): the fix is a deterministic
check plus a red fixture, not a stronger sentence.

## What Changes

1. **`scripts/memory-leak-check.sh`** — deterministic engine. Flags any 16-word
   run in a candidate body that appears in the private memory corpus and not in
   the repo's tracked content.
2. **`hooks/publish-guard.sh`** — new PreToolUse `Bash` hook. Denies
   `gh issue create|comment|edit` and `gh pr create|comment|edit` whose body
   carries flagged text. Separate from `openspec-guard.sh`, so the push gate's
   fail-open ERR trap is untouched.
3. **`skills/improvement-miner/SKILL.md`** — published bodies cite
   `memory/<file>.md:<line>`; the in-session report keeps verbatim quotes.
4. **Remediation** — rewrite the flagged bodies to citations, so the repo
   passes its own gate. A full sweep of every issue in every state raised the
   set from the 8 above to **9** (a closed, human-authored issue was also
   carrying two leaked passages); all 9 are remediated and the tracker is
   34/34 clean.

## Impact

- Affected specs: `pdlc-safety` (ADDED), `improvement-mining` (MODIFIED)
- Affected code: `scripts/memory-leak-check.sh` (new),
  `hooks/publish-guard.sh` (new), `hooks/hooks.json`,
  `hooks/lib/git-command.sh` (publish predicates, including `gh api` write
  endpoints),
  `skills/improvement-miner/SKILL.md`, `hooks/session-start-hook.sh`
  (drift-canary manifest), `tests/test-memory-leak-check.sh` (new),
  `tests/test-publish-guard.sh` (new), `tests/test-improvement-miner.sh`
- Not affected: the miner's human-approval gate (`SKILL.md:128`), its read
  access to memory, and `.claude/knowledge/` (human + PR gated by design)
