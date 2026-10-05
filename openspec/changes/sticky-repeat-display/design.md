## Architecture

Three points in `hooks/skill-activation-hook.sh`, and no change to scoring or selection.

1. `_apply_sticky_composition` records the skill it injects (`_STICKY_SKILL`). It injects only after establishing that no process skill scored from the prompt, so a prompt whose own words select a skill never sets it.
2. In `_format_output`, immediately before the print, the block's final process skill is compared with it (`sticky`) and looked up in the session's marker (`already`). Only in `suppress`, or in `trial` for a session in the hide arm, does `sticky && already` set `_DISPLAY_SUPPRESS`.
3. At the very end of `_format_output`, after the last-invoked and composition-state writes, the marker is replaced and one shadow record is written as a new file.

The hide also requires that the sticky step is the only skill in the block. The marker's first line names the chain. Its list of shown steps starts again on a different chain, when the user's own words select a process step, on a cancel, and at a compaction (`pre-compact-hook.sh` removes it for manual and automatic compaction; `compact-recovery-hook.sh` does again on the manual path). The trial arm is the last character of the session token: no fork, and it cannot change during a session.

## Trade-offs

**Shadow first.** The rule could have shipped on. It does not, because the only evidence for it is that the blocks are rarely followed by the mandated skill, and that is equally what one would see if the reminders work slowly or if the model ignores every mandate.

**A new file, outside the routing-state family.** "Already shown" cannot be derived from composition state: a step can become current through a skill's return, without any display. The marker (`.sticky-repeat-shown-<token>`) and the records (`.sticky-repeat-shadow.d/`) are deliberately not named `.skill-*`: that family is routing state, which every display-suppression proof in this repository requires to be identical whether or not a block was displayed, and these two record what was displayed. The first cut named the marker `.skill-steps-shown-*`, and the existing non-human suppression test failed six cells on it — correctly.

**What the marker is trusted for.** One thing: a line naming a step, under a first line naming this chain, means the step was displayed. It is ignored (which displays) when missing, unreadable, a symlink, a directory, written for another chain, or consulted with no chain walked. At most 64 lines of 1,024 characters are read, an over-long line voids the whole file, it is opened read-write so that a FIFO cannot block the open, each read gives up after one second, and the whole loop stops after two: the hook is killed at ten seconds, and the read comes before the state writes.

**Nothing is modified in place.** Pathname checks cannot see a hard link and cannot close a check-then-open race, so the writes do not rely on them: the marker's new content goes to a name that must not exist (noclobber) and is renamed over the marker, and each record is a new exclusively created file. A rename changes a name and an exclusive create makes a new inode; neither can write into a file some other name already points at. The cost is one `mv` when a step is first shown, and a directory of small files instead of one log.

**Chain-scoped, not session-scoped.** The same skill name on a different chain is a different obligation. The cost is that a detour through another chain shows each step once more.

**The trial really hides blocks** in half the sessions. That is the only way to observe the intervention; the push gate is unaffected in both arms.

**Forks added to the hot path:** one per mandated prompt (`date`, for the record's timestamp), plus one `mv` when a step is shown for the first time and one `mkdir` the first time ever. The record is built by `printf` with no `jq`. Nothing is added on prompts with no process mandate, or in `off`.

## Dissenting views

- **Hide every repeat, including prompts whose own words select the skill** (182 more rows in the development data). Rejected: a prompt that asks is fresh evidence of intent, and hiding on "already displayed" alone is the shape-rule mistake that removed the question guard.
- **Flip the default on a label-based threshold.** This was the first plan. Cross-family review rejected it: labels measure whether a mandate looked warranted, not what happens when the reminder is gone. Adopted as the two-stage design.
- **Infer "sticky" offline by replaying prompts instead of recording it.** Rejected: it reconstructs a state machine from outside. The hook records its own decision, and a test audits each record against the display of the same turn.
- **Reuse `hooks/lib/shadow-corpus.sh`.** It holds the push-gate legs' band rule and episode grouping. This record is not a push-gate leg and its decision rule is not a band; the pre-registration carries its own thresholds.

- **Cross-family review of the implementation said REVERT, twice.** First round, five defects, all fixed: with no chain walked the header check was skipped, so a step listed under another chain's header counted as shown; the marker read was unbounded; the marker and the log were written through a symlink, and the log's path could be overridden to name a state file; an unreadable marker printed a diagnostic in shadow that `off` does not (`done < file 2>/dev/null` opens the file before redirecting); and the record's count field was not checked to be a number. Second round, on the fixes: a pathname check cannot see a hard link, so the writes could still land on a state file; opening the marker could still block on a FIFO swapped in after the check; `read -n` returns chunks, so the tail of an over-long line could be read as an entry; and a failed header write did not stop the append after it. Those are closed structurally rather than by more checks (see "Nothing is modified in place"). Its third verdict, on that rework, was KEEP: the remaining issues are robustness limits and none gives an actor a capability it lacks. Two of the first round's points were over-claims in the author's wording, corrected rather than argued: "every marker failure displays", and "the record cannot carry prompt text" (what holds is that no value in it is taken from the prompt).

- **An independent dispatched review of the committed change said READY AFTER FIXES**, with no critical finding and seven important ones, five of them reproduced against the real hook: automatic compaction never removed the marker; cancel-then-re-arm hid the new task's first display; a hidden block also hid a skill the prompt itself had selected; a peer message's hidden block became a stage A row; the stage B boundary was decided by floating-point rounding; the owner-calibration floor counted labels that calibrated nothing; and the push-gate cells could not fail for the defect they were cited for. All fixed or corrected; each new cell was shown to fail against the hook with that one protection removed, which also exposed two of the author's own cells as vacuous (both compaction cells reached a new step, which is displayed whatever the marker says).

## Decisions

- Default `shadow`. An unrecognised switch value is `shadow`, never suppression.
- The record carries the session token, the skill, the chain's step names, flags and counts. No prompt text.
- `rule_version` is 1. A change to when the rule fires bumps it, and records are not pooled across versions.

## Known limits

- Sticky composition also advances the chain's recorded progress on a bare reply, and that progress carries over a cancel into the next task. Both are unchanged and out of scope; the rule hides a display and nothing else.
- `prompt_count` in a record stays at 1 under `SKILL_VERBOSE=1`. Nothing reads it for the join.
- **A compaction whose removal of the marker fails while `~/.claude` is otherwise writable leaves stale entries that are believed.** In shadow that is a wrong record; in `suppress` or the hide arm it hides a block that should be shown again. Refusing the marker when the directory is not writable is a partial stand-in, not a signal that the removal happened. The third cross-family review, which said KEEP, named this as the one remaining defect and accepted it for a default-shadow change. A real fix needs a compaction generation the activation hook can observe.
- Nothing defends the marker against another process racing the hook's own check-then-open or check-then-rename: a FIFO or a directory planted at an output name can stall or misplace a write (after the state writes), and a FIFO with a cooperating slow writer can hold the read for about three seconds. None of this gives such a process anything it lacks: it can already rewrite the state files directly.
- The record directory is never pruned. It is the experiment's data.
- The marker is read before the print, and so before the state writes. That read is bounded and cannot block on a FIFO; a test bypasses the plain-file check to show the hook still finishes and still writes its state.
- The trial arm is balanced only if session tokens end in a uniformly distributed hex digit. They are derived from the transcript's UUID. A token that ends in anything else is in the show arm; the reader prints sessions per arm.
- Stage B has few units; see the pre-registration.
