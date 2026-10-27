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
  A block whose chain reaches no entry, or reaches a skill-load meta entry, is "unpaired".
- **Mandate**: each distinct `<skill> MUST INVOKE` on the block's verdict line. That line is
  `Evaluate: **Phase: [X]** | ...` in the hook's compact formats and `**Phase: [PHASE]** | ...`
  with no prefix in the full format it renders on a session's first prompt when three or
  more skills route. The same words in prose elsewhere ("Process skills marked MUST INVOKE
  are mandatory") are not a mandate. Both shapes are pinned against the real hook's output.
- **Obeyed in-turn**: a `Skill` tool_use whose bare name equals the mandate, after the prompt
  and before the next text input of any source: a prompt, a queued prompt, or a notification
  wrapper. A tool result, a skill-load meta entry (`Base directory for this skill: ...`) or a
  sidechain entry does not end a turn. **Obeyed later**: anywhere later in the session.
- **Gating invocations**: `requesting-code-review` and `verification-before-completion`
  invoked in a typed turn; routed when that turn's block lists the skill on its verdict line
  (mandated or `YES/NO`), unrouted otherwise, including a skill named only in prose or no
  block at all.
- **Obeyed later** is per mandate and can overlap another prompt's in-turn count: one
  invocation can be in-turn for prompt B and "later" for an earlier prompt A that mandated
  the same skill. The primary (in-turn) has no such overlap; "later" is a side column.
- **Version floor**: a session counts only when its SessionStart hook output or a skill-load
  entry names an installed plugin at or above `--min-version` (default 3.95.8). Below the
  floor, or no evidence, is counted out separately and never assumed current. A session
  keeps the build it started on, so the floor is what keeps pre-cut renders out of the
  post-cut count. The FIRST version evidenced in a transcript is the session's version; a
  resumed session that later evidences a newer build is still judged by its first, which can
  only exclude it (shrinking n), never admit a pre-cut render.

## Baseline reproduction (the control), read 2026-10-12 with this instrument

The 2026-10-05 to 10-12 week, every plugin version admitted (`--min-version 0.0.0`; the
window is pre-cut by date):

| | this instrument | measurements doc (uncommitted census) |
|---|---|---|
| sessions with a typed prompt | 14 | 102 sessions of any kind |
| typed prompts | 62 | "366 typed human turns" |
| typed prompts with a block | 51 | 55 human blocks |
| blocks on non-typed inputs / unpaired | 3 / 9 | 9 on peer input |
| mandates rendered | 35 | 23 |
| obeyed in-turn | **2** (both requesting-code-review) | 0 "in-window" |
| obeyed later in session | 1 | not reported |
| gating invocations in typed turns | routed 3, unrouted 2 | 11 unrouted, scope unstated |
| block bytes, median / mean | 5,121 / 5,492 | 5,121 / 5,526 |

The block counts and the median agree; the mandate count does not: the doc counted 23, this
instrument 35, because a first prompt that routes three or more skills renders the verdict
line without the `Evaluate:` prefix and a reader anchored on that prefix misses every such
mandate (the first cut of this instrument did; a reviewer caught it). The typed-prompt count
does not reproduce either (every prompt-bearing entry of every source in that window is 217:
65 human, 87 headless `sdk`, 65 unlabelled), and the doc's in-window rule and gating scope
were never written down. **The registered control is therefore this instrument's own read,
2 obeyed of 35**, so that the census compares one instrument with itself. Robustness column,
four weeks 2026-09-14 to 10-12, every version: 573 typed prompts, 471 with a block, 320
mandates, 20 obeyed in-turn (6.3%), 50 later, gating routed 15 unrouted 18, 111 blocks
unpaired (older transcript shapes and skill-load inputs); consistent with the week.

## Registration

- **Window**: from `2026-10-12T00:00:00Z`, closed by **count**: at the 46th mandate rendered
  on a typed prompt in a session at or above the floor, by time, or on `2026-11-09`,
  whichever is first. By count, not by date, because the cut is display-only and mandates per
  prompt are unchanged by construction; only the owner's prompting volume moves the count.
  **Exactly 46**: a read made after the 46th mandate reads the first 46 by time and reports
  how many later ones it did not read, so the result cannot depend on when the owner reads
  (optional stopping). A close by date caps the window at the cap date even when read later.
- **Control**: 2 obeyed of 35 (above).
- **Primary**: obeyed in-turn over mandates rendered, k of n. One-sided exact Fisher tail of
  the table [[k, n-k], [2, 33]], printed by `census.py` when the window closes.
- **Reading rule**, fixed before any post-cut read (tails from `--self-test-p`):
  - p < 0.05, which at n = 46 is **10 or more obeyed** (p = 0.041; 9 of 46 is p = 0.067 and
    reads as inconclusive): display moves behaviour. Keep the display path; PR #350's gate
    line survives only if routed gating invocations rose against the baseline.
  - **k of 0 to 2**: no evidence that display moves behaviour (at or below the control's own
    rate). Close the display path as a cost-saving only; no further display proposals, the
    dropped newsletter hints included; the next cut removes per-phase hint prose entirely
    (with the #356 REMOVED delta).
  - **3 to 9 of 46**: inconclusive. Extend once by one week, then read again; a second
    inconclusive read is "no evidence".
  - If the cap date closes the window with n below 46, the exact p for the observed k of n is
    reported and the same two thresholds apply: p < 0.05, and k of 2 or fewer. A window that
    closes with **zero** mandates is cannot-check (exit 3), never a verdict.
- **What this can detect**: with a 6% control and n = 46, only a rise to roughly one obeyed
  mandate in four (10 of 46 is 22%) is significant. A smaller real effect reads as "no evidence". That is the
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
python3 "$P/census.py" --self-test-p 10 46      # p=0.0414 against the default control 2/35
python3 "$P/census.py" --self-test-p 9 46       # p=0.0669
# The control itself, re-derivable at any time:
python3 "$P/census.py" --since 2026-10-05T00:00:00Z --until 2026-10-12T00:00:00Z --min-version 0.0.0 --close-at 1
```

Exit 0 counted; 2 unreadable projects directory, bad usage, or an instrument fault (blocks
exist in the window and none pairs with any input); 3 cannot check (no transcript, no counted
session with a typed prompt in the window, or a window that closed with no mandate). A single
transcript that cannot be read is counted (`transcripts unreadable`) and skipped. A verdict is never an
exit code. Output is counts and skill names only; no prompt text is ever printed, so the
output may be pasted into an issue.

## Known limits, stated before the data

- One owner, who knows the hypothesis and also drives the sessions. A before/after on one
  person cannot separate the cut from everything else that changed in the owner's work.
- "Obeyed" is a name match on the `Skill` tool. A skill followed without being invoked, or
  invoked under another name, is not seen; the control was counted the same way.
- The turn boundary is the next text input. A long autonomous turn can hold many tool calls
  and still be one turn; a notification cuts a turn short. Both apply to the control too.
- The version floor reads evidence the harness writes; a session whose SessionStart output
  was not recorded is counted out, which can only shrink n.
- Blocks whose `parentUuid` chain reaches no entry, or a skill-load meta input, are counted
  as unpaired (111 of the four-week read, 9 of the control week, 0 since 2026-10-12); a
  window where every block is unpaired is reported as an instrument fault, not as zero
  obedience. A window with typed prompts and no block at all is not treated as a fault,
  because a prompt that routes nothing renders no block; it reads as zero mandates and, at
  the cap, as cannot-check.

## Companion: verb attribution census (`verbs.py`), descriptive, not registered

`verbs.py --skill <name> --since ISO` says WHICH trigger alternative earned each mandate of a
skill on typed prompts, using the same readers, pairing and turn boundary as `census.py`.
Each of the skill's trigger regexes from `config/default-triggers.json` is split into its
top-level alternatives, and each alternative runs over the lowercased prompt as the hook does
(rescanning from one past each hit; a hit interior to a word on both sides is not a match;
`.` crosses newlines as in bash ERE). A matching alternative is named by its own source text
in the config ("build", `set.?up`, `how.(should|would|could)`, `check.*(code|changes|diff)`),
never by what it matched, because a wildcard's matched span is prompt text. `sole` counts
prompts where exactly one
alternative matched, the population a deletion of that alternative would change. A mandate
matching no alternative was earned by chain injection, the keyword path or a name mention and
is reported as unattributed. It decides nothing: whether a mandate was warranted needs labels,
and the frontier audit's labels over its 652-prompt gold set are gone (the prompts came from
real transcripts and could be re-extracted; the labels lived in a session scratchpad and
would have to be made again). Any deletion study is a new, separately registered experiment.

Read 2026-10-13 over four weeks (2026-09-15 to 10-13, every version, 63 sessions, 576 typed
prompts). Brainstorming, 94 mandates, 65 with exactly one alternative, 8 unattributed:

| alternative | mandates | sole | in-turn | later |
|---|---|---|---|---|
| new | 24 | 18 | 0 | 0 |
| design | 19 | 6 | 5 | 0 |
| approach | 15 | 7 | 2 | 0 |
| make | 15 | 14 | 0 | 2 |
| create | 12 | 3 | 3 | 0 |
| add | 10 | 6 | 2 | 0 |
| build | 9 | 5 | 3 | 0 |
| start | 8 | 4 | 2 | 0 |
| set.?up | 4 | 2 | 0 | 0 |
| seven others | 13 | 0 | 1 | 0 |

"new" and "make" are 32 of the 65 sole matches and were followed by the skill in the same
turn zero times, while the design words carry the same-turn invocations; read that as a
description of where the mandates come from, not as a ranking of what to delete, because
same-turn invocation is a weak proxy for "warranted" (the census above found display rarely
moves behaviour at all) and a verb's absence from the in-turn column says nothing about the
work orders it correctly routed. requesting-code-review,
149 mandates: `pr` 52 (48 sole, 4 in-turn), `review` 28 (22 sole, 1 in-turn),
`check.*(code|changes|diff)` 4, `lint` 3, 69 unattributed (chain-injected; 30 followed later
in the session). The requesting-code-review rows sum past the attributed prompts (87
alternative hits over 80 attributed prompts) because a prompt can match two alternatives.

## Amendment log

### A1 (2026-10-27): how the one-week extension is read

The window closed by count at the 46th mandate, rendered `2026-10-24T01:19:27Z`. The
registered read, made 2026-10-27, was **9 obeyed in-turn of 46, p = 0.0669: inconclusive**,
so "extend once by one week, then read again" applies. This README did not say how an
extension is read; A1 fixes that.

**A1 departs from the freeze rule at the top of this file**, which requires an amendment
"before the data they affect is looked at". Part of the extension's data had been looked at
when A1 was written. What was seen:

- The registered read prints its count table over every mandate up to the read, not only the
  first 46. At that read the table held 95 mandates, the last rendered
  `2026-10-27T12:15:13Z`, and 11 obeyed in-turn: 2 of the 49 after the 46th (p = 0.2641 for
  11 of 95). It reproduces with `--until 2026-10-27T12:16:00Z` added to the command below.
- The per-skill split of that table: requesting-code-review held 7 of the 11 in-turn obeys
  (31 mandates). The side column below was designed after seeing it.
- What that implies, stated so no one reads the result as a surprise: p < 0.05 at the close
  needs about 19 of 100, 20 of 105 or 21 of 110, that is 8 to 10 obeys among the next 5 to
  15 mandates, against 2 of the 49 after the 46th. When A1 was written the read was, in
  effect, foreseeable as "no evidence".

The registered thresholds, control, floor and data start are unchanged. To leave no choice
made after the peek, the window end is the exact one the registered "one week" names, not a
rounded one.

- **Window**: data start unchanged (`2026-10-12T00:00:00Z`) to `2026-10-31T01:19:28Z`, the
  first whole second at least seven days after the 46th mandate (half-open: a mandate at
  that instant is out). Every mandate in the window counts, the first 46 included.
- **Command**, run on or after **2026-11-02** (the `--cap-date` test uses the local date, and
  turns that started before the end need time to finish), never before it: before the cap
  date the tool prints OPEN and no verdict line, but its count table IS the extension's
  running k of n, so an early run is a peek at the primary result.
  ```bash
  P=tests/probes/compliance-census
  python3 "$P/census.py" --since 2026-10-12T00:00:00Z --until 2026-10-31T01:19:28Z \
    --cap-date 2026-11-01 --close-at 1000000 --min-version 3.95.8 --control 2/35
  ```
  A `--close-at` above any reachable count makes the date the close; an `--until` before the
  cap date is kept, so the window ends at `--until`. The tool will label the end
  `2026-11-01 (cap date reached)`; the window is still the `--until` one.
- **Reading**: p < 0.05 is "display moves behaviour", with that arm's registered actions.
  Anything else is "no evidence that display moves behaviour": this is the second
  inconclusive read the registered rule names, there is no further extension, and **the
  registered "no evidence" arm's actions apply in full**: close the display path as a
  cost-saving only, make no further display proposals (the dropped newsletter hints
  included), and the next cut removes per-phase hint prose entirely (with the #356 REMOVED
  delta). The tool's verdict line will still print "inconclusive; extend once" in that case;
  A1 overrides that line. The "k of 2 or fewer" arm cannot fire, because the window holds
  the first 46 and 9 of them were obeyed (rerun with `--until 2026-10-24T01:19:28Z
  --close-at 46` to confirm 9 of 46 still reproduces; without that `--until` its count table
  covers the whole window to the day of the run, which is a peek); that is stated now so its absence is not read as a
  result.
- **Side column, reported and not tested**: the same k of n with the two gated skills
  (`requesting-code-review`, `verification-before-completion`) removed from both, taken from
  the `by skill` rows, against the control week with the same removal, **0 of 20** (the
  control's 15 requesting-code-review mandates held both of its obeys). k and n subtract the
  two skills' `by skill` rows (a missing row is 0). Why: 7 of the 11 in-turn obeys seen were
  requesting-code-review, which the push gate also demands, so a gate deny can produce an
  in-turn invocation the display did not; and PR #379 (merged 2026-10-26) changed what the
  REVIEW gate credits mid-extension. The column removes the push-gate route, not every gate
  route: `skill-gate.sh` can deny a chain step until its predecessor has evidence, which can
  drive an in-turn invocation of a process skill that stays in the column.
