# In-turn compliance census — pre-registration

**Frozen by the merge commit of the PR that adds this file.** Data start `2026-10-12T00:00:00Z`;
the installed plugin was 3.95.9 at 2026-10-12 20:00 UTC, so every session started after
that carries the PR #349 hint cut and the PR #350 gate line. Changes after the freeze go in
the amendment log at the foot, with the reason, before the data they affect is looked at.

## What is being measured, and why

PR #349 shortened the routing block's per-phase hints to a condition plus the owning
`Skill(...)` name and moved the procedures into the skills (block 1,027,896 to 864,205 bytes
over 200 replayed prompts; live displayed-block mean 5,138 to 4,806 chars). Nothing says
whether a smaller block changes what the model does. This census is the zero-label
instrument that answers one question: **does the display path move behaviour at all?** It
decides whether any further display work is worth doing.

It is descriptive, on one owner's sessions, and the owner knows the hypothesis. Most
mandates are wrong (#333: 83 wrong against 11 right on held-out prompts), so **more obedience
is not itself good**; the census only settles whether display can move behaviour. A null is
"no evidence", never "no effect".

## Definitions (also in `census.py`'s header; the code is the authority)

- **Typed prompt**: a top-level user entry the transcript labels `origin.kind == "human"`
  whose text does not start with `<`. Same rule as `tests/probes/routing-precision/rows.py`.
- **Block**: the activation hook's `UserPromptSubmit` `hook_additional_context` attachment
  containing `SKILL ACTIVATION`, paired to the input it answered by walking `parentUuid`
  (as `tests/probes/real-prompt-replay/routed.py` does). A block paired to a non-typed input
  (a notification, a peer message, a headless prompt) is counted out, not in the denominator.
- **Mandate**: each distinct `<skill> MUST INVOKE` on a block line starting with `Evaluate:`.
  The same words in prose elsewhere are not a mandate.
- **Obeyed in-turn**: a `Skill` tool_use whose bare name equals the mandate, after the prompt
  and before the next text input of any source: a prompt, a queued prompt, or a notification
  wrapper. A tool result does not end a turn. **Obeyed later**: anywhere later in the session.
- **Gating invocations**: `requesting-code-review` and `verification-before-completion`
  invoked in a typed turn; routed when that turn's block names the skill, unrouted otherwise.
- **Version floor**: a session counts only when its SessionStart hook output or a skill-load
  entry names an installed plugin at or above `--min-version` (default 3.95.8). Below the
  floor, or no evidence, is counted out separately and never assumed current. A session
  keeps the build it started on, so the floor is what keeps pre-cut renders out of the
  post-cut count.

## Baseline reproduction (the control), read 2026-10-12 with this instrument

The 2026-10-05 to 10-12 week, every plugin version admitted (`--min-version 0.0.0`; the
window is pre-cut by date):

| | this instrument | measurements doc (uncommitted census) |
|---|---|---|
| sessions with a typed prompt | 14 | 102 sessions of any kind |
| typed prompts | 62 | "366 typed human turns" |
| typed prompts with a block | 51 | 55 human blocks |
| blocks on non-typed inputs | 9 | 9 on peer input |
| mandates rendered | 24 | 23 |
| obeyed in-turn | **1** (requesting-code-review) | 0 "in-window" |
| obeyed later in session | 2 | not reported |
| gating invocations in typed turns | routed 2, unrouted 0 | 11 unrouted, scope unstated |
| block bytes, median / mean | 5,121 / 5,492 | 5,121 / 5,526 |

The block counts and the median agree exactly; the typed-prompt count does not (every
prompt-bearing entry of every source in that window is 217: 65 human, 87 headless `sdk`, 65
unlabelled), and the doc's in-window rule and gating scope were never written down. **The
registered control is therefore this instrument's own read, 1 obeyed of 24**, so that the
census compares one instrument with itself. Robustness column, four weeks 2026-09-14 to
10-12, every version: 573 typed prompts, 471 with a block, 267 mandates, 13 obeyed in-turn
(4.9%), 46 later, 74 blocks unpaired (older transcript shapes); consistent with the week.

## Registration

- **Window**: from `2026-10-12T00:00:00Z`, closed by **count**: when 46 mandates have been
  rendered on typed prompts in sessions at or above the floor, or on `2026-11-09`, whichever
  is first. By count, not by date, because the cut is display-only and mandates per prompt
  are unchanged by construction; only the owner's prompting volume moves the count.
- **Control**: 1 obeyed of 24 (above).
- **Primary**: obeyed in-turn over mandates rendered, k of n. One-sided exact Fisher tail of
  the table [[k, n-k], [1, 23]], printed by `census.py` when the window closes.
- **Reading rule**, fixed before any post-cut read (tails from `--self-test-p`):
  - p < 0.05, which at n = 46 is **11 or more obeyed** (p = 0.034; 10 of 46 is p = 0.051 and
    reads as inconclusive): display moves behaviour. Keep the display path; PR #350's gate
    line survives only if routed gating invocations rose against the baseline.
  - **k of 0 to 2**: no evidence that display moves behaviour (the control's own rate). Close
    the display path as a cost-saving only; no further display proposals, the dropped
    newsletter hints included; the next cut removes per-phase hint prose entirely (with the
    #356 REMOVED delta).
  - **3 to 10 of 46**: inconclusive. Extend once by one week, then read again; a second
    inconclusive read is "no evidence".
  - If the cap date closes the window with n below 46, the exact p for the observed k of n is
    reported and the same two thresholds apply: p < 0.05, and k of 2 or fewer.
- **What this can detect**: with a 4% control and n = 46, only a rise to roughly one obeyed
  mandate in five is significant. A smaller real effect reads as "no evidence". That is the
  bar the owner's volume affords without labels, and it is stated here so a null is not
  oversold.
- **Side columns, reported and not tested**: routed vs unrouted gating invocations; obeyed
  later in session; block bytes median and mean; the sticky-shadow `block_chars` series.
- **Not an outcome measure for PR #350**: chain-review and chain-verify denies per push were
  1 in 47 since 3.94.5 and cannot move inside the window.

## Runbook

```bash
P=tests/probes/compliance-census
# While open: counts and "collection: OPEN"; it prints no verdict.
python3 "$P/census.py" --since 2026-10-12T00:00:00Z
# The registered tails, without data:
python3 "$P/census.py" --self-test-p 11 46      # p=0.0338 against the default control 1/24
python3 "$P/census.py" --self-test-p 10 46      # p=0.0514
# The control itself, re-derivable at any time:
python3 "$P/census.py" --since 2026-10-05T00:00:00Z --until 2026-10-12T00:00:00Z --min-version 0.0.0 --close-at 1
```

Exit 0 counted; 2 unreadable input, bad usage, or an instrument fault (blocks exist in the
window and none pairs with any input); 3 cannot check (no transcript, or no counted session
with a typed prompt in the window). A verdict is never an exit code. Output is counts only;
no prompt text is ever printed, so the output may be pasted into an issue.

## Known limits, stated before the data

- One owner, who knows the hypothesis and also drives the sessions. A before/after on one
  person cannot separate the cut from everything else that changed in the owner's work.
- "Obeyed" is a name match on the `Skill` tool. A skill followed without being invoked, or
  invoked under another name, is not seen; the control was counted the same way.
- The turn boundary is the next text input. A long autonomous turn can hold many tool calls
  and still be one turn; a notification cuts a turn short. Both apply to the control too.
- The version floor reads evidence the harness writes; a session whose SessionStart output
  was not recorded is counted out, which can only shrink n.
- Blocks whose `parentUuid` chain reaches no entry are counted as unpaired (74 of the
  four-week read, 3 of the control week, 0 since 2026-10-12); a window where every block is
  unpaired is reported as an instrument fault, not as zero obedience.

## Amendment log

(none)
