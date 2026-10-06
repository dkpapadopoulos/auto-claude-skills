# Pre-registration — routing precision: stop repeating a chain step's mandate on a prompt that asked for nothing

Issue #333. **Frozen by the latest commit that changes this file** (see the amendment log
at the foot: the freeze has been replaced twice, each time before any row existed). That commit's
timestamp is the boundary: everything observed before it is development data and may not
be used to judge the rule. Changes after it go in the amendment log, with the reason,
before the data they affect is looked at.

## What is being tested

Once a prompt arms a composition chain, the activation hook re-emits the chain's CURRENT
step as `MUST INVOKE` on every later prompt of six words or fewer that selects no process
skill of its own ("sticky composition"). The rule:

> A block is not displayed when all of these hold: its process mandate was injected by
> sticky composition; the sticky step is the only skill in the block; and this session has
> already been shown that step, on the same chain, since the user last asked for a process
> step in their own words and since the last compaction.

- Display-only, through `_DISPLAY_SUPPRESS`. Scoring, the chain walk and every pre-existing
  state write are unchanged.
- It never hides a step's first display; a prompt whose own words select a process skill;
  a block that also carries a domain or workflow skill the prompt selected; a step on a
  different chain; a step of a new task (a new order in the user's own words, or a cancel,
  starts the list again); a step after a manual or automatic compaction; or anything when
  its marker cannot be believed.
- "Already shown" counts a display made either way (by the prompt's own words or sticky).
- **Re-anchor, a policy of the rule and not a detection.** Whenever the user's own words
  select a process step and it is displayed, the "already shown" list restarts with that
  step alone. The hook cannot tell a new task from the same task asked for again; this is
  chosen because it errs toward displaying. Its cost is stated here so it is not discovered
  later: the rule fires less often than "shown before on this chain" would, and stage A's
  would-hide rows are the ones this policy leaves.
- **The rule's version is 2.** Records carry `rule_version`; the readers accept 2 and
  nothing else. Version 1 is what builds before this freeze wrote. Any later change to
  when the rule fires, or to the chain walk that decides which step is injected, takes a
  new version and an amendment, and rows are never pooled across versions.

It ships **in shadow**: the hook displays exactly as before and records, for every mandated
block, whether the rule would have hidden it (`~/.claude/.sticky-repeat-shadow.d/`, no
prompt text). `ACS_STICKY_REPEAT` selects `shadow` (default), `trial`, `suppress`, `off`.

## What this can and cannot say

- **It is not known to be an improvement.** A repeated reminder may be what keeps an
  unfinished review in view. The development table below says these blocks are rarely
  followed by the mandated skill; it does not say they are useless.
- **It does not touch mandates a prompt earns by its own words.** The 83 wrong against 11
  right measured on 2026-10-04 are all of that kind. This is a different slice of the
  problem, one the earlier stateless replay could not see.
- **Stage A cannot license suppression.** Labels say whether a mandate was warranted. They
  do not say what happens when the reminder is gone. Only stage B observes that.
- One owner's sessions, and the owner knows the hypothesis.

## Stage A — the screen (labels). Decides whether the trial is worth running.

**Rows.** Every block with a process mandate that the hook recorded in shadow mode, that was
actually displayed, for a prompt the transcript labels as typed by the user, in a top-level
session that started at or after the freeze. A block hidden for another reason (a peer
session's message, for instance) was seen by nobody and is not a row. All of them are
labelled, not only the ones the rule would hide. Built by
`tests/probes/routing-precision/rows.py`, which writes the labeller's view and the key as
separate files; the labeller's view carries nothing about the rule, the session or what
happened next. If displayed records exist and not one of them joins a typed prompt,
`rows.py` exits 2 and writes nothing: that is a reader that no longer recognises a typed
prompt, not a small sample, and it must not be scored as INCONCLUSIVE. (Checked against
real transcripts on 2026-10-06: the twelve most recent top-level ones label typed prompts
`human`, and the only unlabelled entries are another session's messages.)

**The question** (verbatim in `tests/probes/routing-precision/rubric.md`): *at this turn —
given the task in progress, what the user just said, the work already done, and what is
still outstanding — is requiring this specific process skill now warranted?* Labels:
`WARRANTED`, `NOT_WARRANTED`, `INSUFFICIENT_CONTEXT`. A bare "yes" that approves the step
is `WARRANTED`. The rubric says so, because asking only "what does this prompt call for"
would rig the answer in the rule's favour.

**Who labels.** Two blind model labellers, same rubric. They share a model family with the
author, so their agreement is corroboration, not validation. The owner labels 20 rows
blind, drawn at random from the rows both labellers decided.

**Stopping, fixed now.** Collection closes when 60 rows the rule would hide have been
recorded, or on 2026-11-16, whichever is first. Scored once, by
`tests/probes/routing-precision/score.py`, whose `THRESHOLDS` are the values below.

| | Condition | Fails to |
|---|---|---|
| K0 | ≥ 40 hidden rows; from ≥ 10 sessions; no session supplying > 25% of them; Cohen's kappa ≥ 0.60 over all rows; owner labelled ≥ 20 rows **that the labellers decided** and agrees with the decided label on ≥ 80% of those | INCONCLUSIVE |
| K1 | hidden rows ≥ 15% of all mandated rows | STOP |
| K2 | rows DECIDED `NOT_WARRANTED` ≥ 75% of **all** hidden rows (undecided rows count against) | STOP |
| K2b | rows DECIDED `WARRANTED` ≤ 10% of all hidden rows | STOP |
| K3 | hidden rows that are `WARRANTED` **and** were followed by the skill being invoked in the same turn ≤ 5% of hidden rows, rounded down (2 of 40, 3 of 60) | STOP |

`PASS` sends the rule to stage B. `STOP` leaves it in shadow or removes it. Reported
alongside, without thresholds: hidden block text as a share of all mandated block text; the
one-sided 95% upper bound on the `WARRANTED` share; what the rule leaves (decided rows it
does not hide); hidden rows by skill.

**Why a screen and not a verdict.** K1 measures reach, K2 measures classification, and K3
measures what happened while the reminder was still being shown. None of them observes the
intervention. The most likely way all four pass while the rule is harmful: repeated
reminders keep an unfinished review salient; without them more work stalls or reaches the
push gate unfinished, while short-context labels call those reminders unwarranted and K3
misses the delayed effect. Stage B exists for exactly that.

## Stage B — the randomized trial (behaviour). Decides whether suppression may become the default.

Runs only after a stage A `PASS`, with `ACS_STICKY_REPEAT=trial`.

- **Assignment.** By session, fixed for the session: the last character of the session
  token (a hex digit; eight hide, eight show). The hook records the arm.
- **Unit.** An obligation = (session, gated skill) with at least one record the rule would
  hide, where the gated skills are `requesting-code-review` and
  `verification-before-completion`. Every obligation counts, including in sessions that
  never tried to push: dropping those would hide work that stalled.
- **Measures, per arm** (`tests/probes/routing-precision/trial.py`): obligations completed
  (the skill invoked at or after the first would-hide record); completed before the first
  push or merge attempt, by the order the assistant issued them; sessions whose first push
  attempt the gate denied; sessions with no push attempt; turns from the first would-hide
  record to completion; block text hidden.
- **Denominators.** Completion is over obligations that were joined to a prompt; an
  unjoined one is printed and counts toward neither the rate nor the floor. The
  denied-first-push rate is over all eligible sessions in the arm, including those that
  never tried to push.
- **Stopping, fixed now.** Closes at 20 obligations in each arm or six weeks after it
  starts, whichever is first. Fewer than 20 in either arm is INCONCLUSIVE.
- **Reading.** Suppression may be considered for the default only if the hide arm's
  completion rate is at most 10 points below the show arm's **and** its denied-first-push
  rate is at most 10 points above. Exactly 10 points is inside the limit; the comparison is
  done in whole numbers, because at 20 an arm ten points is exactly two obligations.
  Otherwise the rule returns to shadow or is removed.
- **Known noise.** A push is any Bash command containing `git push` or `gh pr merge`, and
  a denial is any result of one containing `PUSH GATE`. In this repository, whose tests and
  fixtures contain those words, that over-counts, in both arms alike.
- **What it is worth.** At 20 obligations an arm the comparison can catch a large
  difference and nothing smaller. It is a tripwire against serious harm. It is not evidence
  that there is none, and making suppression the default remains the owner's decision.

## What must hold whatever the data says (pass/fail, tested now)

- Every pre-existing state file is identical, turn by turn, between `off` and each other
  mode, with an exit-early mutant that must differ
  (`tests/test-activation-sticky-repeat.sh`, cells ID and X1). **This is what holds
  display-only.**
- The gate's answer after a hidden reply is the one it gives with the rule off
  (`tests/test-push-gate-display-suppression.sh`, cells SR). These cells cannot by
  themselves detect a hidden turn that skipped its state write, because a hidden turn is
  never the one that armed the chain; they are a check on the ordinary case, not the proof.
- Shadow displays byte-for-byte what `off` displays (cells SH), and writes nothing to
  standard error that `off` does not (cell F4).
- The marker is believed only for its own chain and only as a plain file; reading it
  cannot block the hook; and nothing of the rule's is modified in place, so a name linked
  onto a state file (symlink or hard link) cannot be used to write into it (cells F).

## Exploratory evidence already in hand (NOT pre-registered; observed before this file)

Local top-level transcripts, 2026-08-26 to 2026-10-04, typed prompts, the block the
INSTALLED hook showed. Counts only. "Sticky" was inferred by replaying each prompt alone
through the current hook with every skill available; "already displayed" was session-wide,
not per chain. The shipped hook records both directly and per chain, so the fresh numbers
will differ in definition as well as in data.

| Kind of mandated block | Rows | Share | Mandated skill invoked the same turn |
|---|---|---|---|
| Prompt's own words selected the skill, first display this session | 145 | 32% | 17 (11.7%) |
| Prompt's own words selected the skill, already displayed | 182 | 40% | 9 (4.9%) |
| Sticky, first display | 32 | 7% | 3 (9.4%) |
| **Sticky and already displayed** | **92** | **20%** | **4 (4.3%)** |

The 92 are in 32 sessions; 76 mandate `requesting-code-review`. That concentration is why
K0 requires ten sessions and caps any one at a quarter, and why stage B's unit is the gated
obligation.

Mechanism, measured against the real hook in isolated sessions: after one arming prompt,
"go", "yes", "the second one" and "thanks" each received a 2.6–6 KB mandated block; the same
replies in a session with no chain received nothing. A sticky reply also advances the
chain's recorded progress, hidden or not: state was identical between `off` and `suppress`
on every turn, and an exit-early version of the rule differed on five of six.

## Design review before the freeze

A cross-family reviewer (Codex) was given the candidate, the table above and a first keep
rule (K1–K3 alone, flipping the default on a pass). Its verdict: a sensible candidate for a
narrow experiment; the evaluation was not sufficient to turn suppression on. Adopted from
it: the two-stage structure; the labelling question about the obligation instead of the
prompt; `INSUFFICIENT_CONTEXT`; K2 over all hidden rows; K3 defined for any sample size;
the session floor and cap; the chain-scoped marker ("skill identity is not obligation
identity"); the randomized trial and its measures. Not adopted: a second label for whether
the reminder itself is useful, which it agreed needs behavioural evidence, and which
stage B supplies.

The same reviewer then said REVERT on the implementation twice, for defects in how the
rule's marker and record were read and written, and KEEP on the third cut. The defects,
the fixes and the one it left open are in
`openspec/changes/sticky-repeat-display/design.md`.

## Known threats, stated before the data

- **The owner knows the hypothesis** and may type short replies differently.
- **Volume.** Development rows arrived in bursts (84 in September, 8 in the first days of
  October). Either stage may close on its date first and be inconclusive.
- **The plugin may change during collection.** Rows count only while the record's
  `rule_version` is 1.
- **The join** from a record to its prompt is by session and time. Records that do not join
  are counted and printed.
- **Same-family labellers**; twenty owner labels is a small calibration.
- **Stage B measures invocation, not quality.** A review that is invoked and done badly
  counts as completed in both arms.
- **The chain's recorded progress carries over a cancel.** Straight after a cancel the next
  task can inherit the cancelled task's progress and skip a step entirely. That is the
  walker's behaviour, older than this rule and out of its scope, but it shapes which steps
  a session is ever shown.
- **`prompt_count` in a record is unreliable under `SKILL_VERBOSE=1`** (it stays at 1). The
  join uses time, not that field.
- **A failed compaction cleanup leaves a stale marker that is believed.** In stage A that
  is a wrong record (a block counted as "would hide" that should not be); in stage B's
  hide arm it is a block wrongly hidden after a compaction. Not fixed; see the design.
- **Trial sessions really hide blocks.** If hiding is harmful, the trial does that harm to
  half the owner's sessions for its duration. The push gate is unaffected.

## Out of scope

Narrowing trigger verbs (the 327 rows where the prompt's own words selected the skill);
rewording `MUST INVOKE`; whether automated text should arm a chain; whether sticky
composition should exist at all, or should advance the chain's progress on a bare reply.

## Amendment log

**A1 — 2026-10-05, before any row existed.** The first freeze was commit `71a837e3`. An
independent review of that commit (a dispatched reviewer, after the three cross-family
rounds) found defects in the rule and the instruments. No row had been built and none could
have been: the installed plugin does not contain the rule. The freeze is therefore moved to
the commit that makes these changes, and they are listed here rather than made silently.

*Correction to an earlier wording of this entry, which said no record existed.* Three did,
in the real `~/.claude/.sticky-repeat-shadow.d`, found by the same reviewer. They were not
usage: an existing test (`tests/test-attestation-measurement.sh`) ran the hook against the
real home directory, so each full run of this branch's suite wrote one record there, for
whichever live session last stamped the token file. All three are `sticky: false`,
`would_hide: false`; two predate the rule changes below. That test now runs in a throwaway
home; the three files and the two markers written with them were moved out of `~/.claude`
before the freeze and are not data. `rule_version` stayed 1 through these changes, so it
does not separate them: the freeze timestamp does, together with the rule that a row's
session must have started after it.

- *Rule narrowed.* A block that also carries a skill the prompt itself selected is no
  longer hidden (it was: a five-word documentation request lost its domain skill). Records
  gain `skills_in_block`.
- *Rule narrowed.* A new order in the user's own words, or a cancel, starts the "already
  shown" list again. Before, a cancelled task's entries hid the next task's first sight of
  the same step, because both tasks arm the same chain.
- *Compaction.* The marker is now removed by the pre-compaction hook, which fires for
  automatic compaction too. Before, it was removed only on the manual path, so every
  automatic compaction left records saying "would hide" where the rule says "shown".
- *Stage A rows.* Only displayed blocks for prompts the transcript labels as typed. Before,
  a peer message's hidden block became a row and inflated K1's denominator.
- *K0.* The owner floor is twenty labels on rows the labellers decided. Before, twenty
  labels of which one calibrated anything passed.
- *Stage B reading.* Compared in whole numbers; exactly ten points is inside the limit.
  Before, floating-point subtraction read 16 of 20 against 14 of 20 as harm and 12 against
  10 as fine. Denominators and the push-detection noise are now stated. "Before the first
  push" follows the order of events inside a turn. Records of another rule version are
  excluded here as in stage A.
- *Claims corrected.* The push-gate cells are a check on the ordinary case; the state
  identity cells are what hold display-only. The marker read is bounded by a two-second
  budget, not "about a minute", because the hook is killed at ten seconds.

- *Readers.* An input that cannot be read exits 2 in every script, never a verdict's code.

None of these was chosen by looking at fresh data: there was none. The thresholds K1–K3
and the stage B limits are unchanged.

**A2 — 2026-10-06, before any row existed.** A fourth cross-family review (Codex), of the
changes A1 lists, said REVERT. No row had been built: the installed plugin still does not
contain the rule. The freeze moves to the commit that makes these changes.

- *Rule version.* A1 changed when the rule fires and left `rule_version` at 1, relying on
  the freeze timestamp to keep earlier records out. Nothing in the readers enforced that a
  record was written by the frozen rule. The hook now writes 2 and the readers accept only
  2. A version-2 record with no `skills_in_block` is counted as malformed, not read as zero.
- *Re-anchor.* A1 described the list restart as recognising a new task. It recognises
  nothing; it is a policy, now stated as one in "What is being tested", with its cost.
- *Reader exit codes.* A1 said a failure to read the inputs exits 2. It did not for an
  input of the wrong shape (a label line that is a JSON array raised an exception the
  handler did not list, and exited 1, which is STOP). Every uncaught failure is now 2.
- *Instrument fault.* Displayed records with no typed prompt among them exit 2 from
  `rows.py` (see Stage A, Rows).
- *Stage B noise.* The statement that push detection over-counts "in both arms alike" was
  unsupported and is withdrawn: hiding a block can change which commands a session runs.
- *Not changed, and why.* The label thresholds, the labels, the trial's two comparisons and
  its floor are as frozen in A1.
