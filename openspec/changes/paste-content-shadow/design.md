# Design: pasted-content shadow (#409, stage 1)

## Intent

Mandates that come only from pasted text are mostly wrong (56 WRONG, 2 RIGHT among the 65 a scorer-side strip would remove, by two blind labellers). Fix the measurement first, without changing what the user or the push gate sees, then decide on display from data gathered after the rule is frozen.

## Capabilities Affected

- `skill-routing` (the activation hook gains a shadow record; nothing displayed or written for routing changes).

## The wrapper (measured, not assumed)

All 79 wrapped prompts on the owner's machine (Claude Code 2.1.277..2.1.311): a blank line, `<pasted_content id="hhhh">` with four lowercase hex digits, the pasted text, `</pasted_content id="hhhh">` with the same id, a newline. A tag inside the paste is escaped by the harness as `<\pasted_content>`. None unterminated, mismatched or nested. Whether the hook payload's `prompt` carries the wrapper exactly as the transcript does is not yet observed directly; the shadow record is the first instrument that will show it (a record with `pairs >= 1`).

## Approaches

| | What | Both arms on the 79 (consensus labels) | Gate |
|---|---|---|---|
| A | Strip inside the scorer (the issue's proposal) | removes 56 WRONG, 2 RIGHT; substitutes 4 WRONG | deletes chain state on 50/79: push-gate chain checks never run in a paste-opened session. Rejected. |
| B1 | Hide the whole block when the stripped text selects nothing | hides 52 WRONG, 2 RIGHT; 9 WRONG still shown | state identical |
| B2 | Show only skills the stripped text selects | removes the 9, but can display a process skill other than the chain anchor written to state | state identical; display disagrees with the gate. Rejected. |
| B3 | Show the intersection; never add or substitute; keep the sticky step | hides 56 WRONG, 2 RIGHT; 5 WRONG still shown; 0 WRONG domain lines shown | state identical |

Chosen: B3 (Codex round 1 proposed it; the owner approved), shipped as a shadow record only. Rendering B3 means filtering a block assembled by a stateful pipeline (phase label, chain walk, driver precondition, red flags), which only a trial needs; it is stage 2.

Multi-turn (dev replay to paste turn + 10): 14 of the 65 hidden mandates are shown again later by the chain (10 WRONG); identical in both arms, because state is identical. Hiding never adds a later display.

## Decisions

- Strict wrapper: 4 lowercase hex, same id both ends, lazy body, and no opener of the same id inside the body (otherwise a stray opener borrows a later block's closer and the typed text between them is stripped; found in review). A changed format strips nothing (today's behaviour) and leaves a record with `pairs: 0`, the drift signal. A body the regex engine gives up on (measured: 4 MB parses, 8 MB raises) is `error`, nothing stripped.
- Cost: each unmatched opener scans the rest of the prompt (measured 1,000 openers 0.5 s, 4,000 openers 3.3 s). Above 16 openers the regex does not run (`capped`). The real maximum is 2.
- Budget: scoring cost grows faster than the text, so re-scoring long typed text doubled the hook's time (review: 6.5 s -> 12.7 s at 39 KB, past the 10 s kill, which would change what is displayed). Over 16 KB of stripped text, or 3 s already spent, the second selection does not run and the record says `skipped` (after the fix: 6.53 s vs 6.58 s at 39 KB).
- Ordering: the parse and the second selection run after the print and after every state write (`_paste_shadow || true` is the hook's last call; as the last command its status is the hook's exit status), in a subshell, so no global the hook already used can change and a slow parse cannot cost a state write.
- The second selection uses the hook's own `_score_skills`, sticky injection (`_inject_sticky_step`, with the chain's step from before this turn's writes, and `_is_pure_cancel`) and `_select_by_role_caps` on the stripped, lowercased text. Without sticky, R hid the chain's step on "go + paste" turns that the hook answers with that step (found in review). The context bonus (+20 for successors of the last-invoked step) is not applied, so a role-cap pick can differ when that signal exists. The tentative phase is a function shared with the main flow.
- Blind spot of the confirmation replay: it runs each prompt in a fresh HOME, with no chain and no last-invoked signal, so it cannot see the chain-context cases; the production records can.
- Records follow the sticky-repeat precedent: `~/.claude/.paste-shadow.d/<token>.<prompt_count>.<random>.json`, exclusive create, no prompt text, not pruned (about 12 a week).

## Verified on the whole corpus

All 3,001 dev prompts replayed through the base commit and this change, each in a fresh HOME with a session token and production's 10 s limit: 0 display differences (after normalising each tree's plugin root, which preconditions render) and 0 differences in any `.skill-*` file over the 2,958 that finished; 43 hit the limit in both arms and none in only one. Controls: base against itself, 0 of 382; the strip-before-scoring mutant, 74 of 82 pasted prompts with different state. The records for the 79 wrapped prompts equal R computed independently from the dev runs' rendered blocks, 79 of 79.

Correction to the dev numbers: the dev replay's line parser missed `Required when …:` lines and the role-less layout used when no process skill is selected, so its domain/workflow counts are incomplete. The process-mandate counts (every `MUST INVOKE` renders a `Process:` line) are unaffected.

## Out-of-Scope

- Changing any display (stage 2, after the pre-registered read).
- Methodology-hint triggers, which also match pasted text (#412 is frozen).
- Prompts that are not wrapped by the harness (generated prompts, the ai-daily-brief case).

## Acceptance Scenarios

In `specs/skill-routing/spec.md`; pinned by `tests/test-pasted-content-lib.sh` and `tests/test-activation-paste-shadow.sh`.
