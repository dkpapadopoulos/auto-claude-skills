# Design: observed reviewer completion

## Architecture

Two hooks observe two halves of one fact. Neither can credit alone, and
**neither is guaranteed to run first**.

```
   PostToolUse ^(Task|Agent)$                    SubagentStop
   reviewer-evidence-hook.sh              reviewer-completion-hook.sh
            |                                          |
   classify (description predicate                observe completion
   + subagent_type allowlist)                     (non-empty final message)
            |                                          |
   record `reviewer-ran`                               |
            |                                          |
   [HALF 1] write  <agent_id> <ledger_key>      [HALF 1] write <agent_id>
            |                                          |
   [HALF 2] is agent_id in the                 [HALF 2] is agent_id in the
            completion file?  ---------------.          dispatch file, with a
            |                                 \         MATCHING ledger key?
            +--> yes: record `reviewer-returned` <------+
                        (whichever hook ran second)
```

Both hooks read `session_id` from **their own payload**, and the two events
carry the identical value (measured; it also equals the transcript basename, so
the filenames are `_SESSION_TOKEN`-shaped and session-start's GC excludes the
live session with a plain `! -name` match). This is deliberately **not**
`resolve_own_session_token` — that resolver exists for model-Bash-turn writers,
which have no payload, and its singleton fallback is the last-writer-wins
scatter behind #51/#97/#122/#131/#133/#151/#156. Here both sides are
payload-driven within one session, so symmetry holds by construction.

`hooks/lib/reviewer-pairing.sh` owns the file format and key derivation so the
writer and reader cannot drift — the same reason CLAUDE.md insists a third
caller of `_advisory_text_for_action` must call it rather than re-derive it.

## Why the join is symmetric — the measurement that killed the first design

The first cut was one-directional: dispatch writes, completion reads. It is a
systematic no-op for foreground dispatches. Measured end-to-end with both real
hooks registered and timestamped, on CLI 2.1.236:

| dispatch mode | firing order |
|---|---|
| `run_in_background: true` | dispatch **1.44s before** completion |
| `run_in_background: false` | completion **~30ms before** dispatch (3 of 3) |

The live probe on the one-directional build recorded `reviewer-ran` and **no**
`reviewer-returned` for a foreground reviewer. After the symmetric rewrite, the
identical probe — same firing order, completion still 462ms first — records
both. This is why every credit path in the test matrix is asserted in **both**
orders: a one-directional design passes the background order cleanly.

The general lesson, and the reason the probe existed at all: two hooks on two
events are a distributed system, and "the dispatch obviously happens before the
completion" is a statement about the world, not about hook delivery.

## The join cannot double-miss

Write-own-half-then-read-the-other is not merely "a small window". The
both-miss interleaving is impossible, and the argument is short enough to check.

Let `Wd`/`Rd` be the dispatch hook's write and read, `Wc`/`Rc` the completion
hook's. Each hook writes before it reads, so `Wd < Rd` and `Wc < Rc`.

Suppose both miss. The dispatch hook missing means it read before the completion
half existed: `Rd < Wc`. The completion hook missing means `Rc < Wd`. Chaining:

    Wd < Rd < Wc < Rc < Wd

which requires `Wd < Wd`. Contradiction — so at least one side always observes
the other, and exactly one or both record the milestone (the ledger write is an
idempotent overwrite, so a double credit is harmless).

This holds because each half is a single `printf >>` whose fd is closed when the
command ends, and each read `awk`s a freshly opened file — there is no buffered
writer holding data back across the two processes.

The one way a half legitimately never appears is an append that did not happen
(size ceiling, unwritable `~/.claude`). That is the `|| true` path, and it fails
toward UNDER-crediting.

## Why a dispatch-time writer at all

Three ways to identify a `general-purpose` reviewer at completion were
considered.

1. **Apply the existing predicate to the subagent's task prompt.** Rejected. The
   prompt is reachable (`agent_transcript_path` exists at hook time and its first
   `user` record is the prompt verbatim), but the predicate
   `*[Rr]eview|*[Rr]eview[!a-zA-Z]*` was **fitted on a short `description`
   label**. Its second arm matches "review" anywhere followed by a non-letter, so
   against multi-paragraph prompt text it structurally degenerates into the
   substring variant that measured 4/7 false positives — the widening that
   variant was rejected for, shipped silently, with the predicate looking
   unchanged in the diff.
2. **Read the parent transcript to find the dispatch record.** Rejected by
   measurement, not judgement: instrumented from inside the hook, at
   `SubagentStop` time the parent transcript contained **zero** lines mentioning
   `agent_id` (18-line parent; the 4-line subagent transcript was readable). The
   `tool_result` carrying `agentId` is written after the event fires.
3. **Pair against what the dispatch hook already classified.** Chosen — (2)
   proves no reader-side reconstruction exists.

## Trade-offs

**A lookup MISS records nothing.** The alternative — a weaker milestone on a
miss — is indistinguishable from a genuine reviewer whose dispatch went
unrecorded, and the missing population is dominated by ordinary implementation
subagents, so it would be mostly noise wearing an evidence label. Under-
recording is the safe direction for a signal whose purpose is fidelity.

**But a miss must not be invisible.** A refused credit leaves a
`# branch-mismatch` line in the completion file. This is not decoration: the
foreground ordering defect produced no trace anywhere, which is precisely why it
nearly shipped. "No reviewer ran" and "a reviewer ran and the join was refused"
must not look identical from the outside — the same reason the IMPLEMENT leg
splits `missing` from `cannot_check`.

**An empty `last_assistant_message` is not a return.** A reviewer that emitted
nothing — interrupted, crashed — did not produce a review, and its completion
half is not published, so a later dispatch cannot join against a crash. This
under-credits an interrupted reviewer: the safe direction.

**The reviewer's output text is deliberately NOT recorded.** The payload carries
it inline and it would make the strongest-looking evidence, but it is unbounded
model output that can quote the diff, secrets, or private memory content into a
file that outlives the session. `hooks/publish-guard.sh` and
`scripts/memory-leak-check.sh` exist because that class of leak is a known risk
here, and that scanner watches only `~/.claude/projects/*/memory/` — a ledger
holding raw reviewer text would be a second surface it does not know exists. The
IMPLEMENT shadow corpus settled the same trade the same way: "raw command text is
never written; `transcript_path` is the adjudication pointer."

**The size ceiling is a real limit, and exhausting it is silent.** Once the
completion file is full, `note_mismatch` is suppressed by the same condition —
so the diagnostic that exists to keep a refused credit visible disappears exactly
when the join starts failing, restoring the indistinguishability this design says
must not exist. The failure is also ORDER-ASYMMETRIC: the background order keeps
working off the separate dispatch file, so it degrades rather than stopping
cleanly. The completion file records EVERY subagent completion (correct — it is
the join key), which makes it fan-out-driven in exactly the agent-team sessions
this evidence is for. Mitigated by raising the ceiling to 1 MiB (~26k
completions), not by pruning, which would need the read-modify-write this design
avoids. Pinned as a documented miss by cell (j3) rather than left implicit.

**A size ceiling, not a trim.** Parallel dispatches run their hooks
concurrently, so a read-modify-write rotation would be a real race, while a short
`printf >>` interleaves safely at line granularity. Dropping new records past the
ceiling is safer than corrupting existing ones. The TOCTOU between the size check
and the append can overshoot slightly; that is inherent to bounding a
pathological case, not a correctness bug.

**Ordering inside `reviewer-evidence-hook.sh` is load-bearing.** The pairing work
runs AFTER `branch_ledger_record "reviewer-ran"`, never before. Under that file's
`trap 'exit 0' ERR`, `wc -c < <missing file>` is a redirection failure that
`2>/dev/null` does not suppress; the first draft put the pairing block above the
record, and the hook exited 0 in silence having deleted the pre-existing
milestone. New best-effort work goes below the thing that must not be lost.

**Every call into the pairing lib is `|| true`-guarded on a path that must
continue.** `reviewer_pairing_note_complete` returns non-zero whenever the append
does not happen (ceiling reached, unwritable `~/.claude`), and unguarded under
`trap 'exit 0' ERR` that terminates the hook *before* the join — silently ending
every credit for the rest of the session. Found by a mutation whose real fault
was masked by that very early exit.

**Known misses, inherited and unfixed.** `branch_ledger_key` is
`sha1(origin remote URL, branch)`, so a review recorded on a task branch and a
push made from an integration branch do not share a key — the normal shape of
this repo's own `agent-team-execution` pattern — and a detached HEAD re-keys on
every commit. Misses are safe, but a missing record must never be read as "no
review happened".

**Unmeasured, and stated as such.** `agent_id` uniqueness within a session is
not proven; 8 ids observed across the probes were 17 random hex characters and
all distinct, including 3 dispatched in one session, so reuse is implausible but
not excluded. Reuse now requires a collision *and* a matching branch key on
either half. That was NOT true when first written: the dispatch-side join
credited on membership alone, so a collision ALONE recorded `reviewer-returned`
at spawn time for a reviewer that had produced nothing. Caught in review,
reproduced against the real hooks with a positive control, and closed by storing
the ledger key in the completion half too. A doc asserting double protection over
a single-guarded path is worse than no claim — it stops the next reader looking. `isolation: "worktree"` WAS probed after
`session-token.sh` flagged the same gap for the adjacent mechanism: both halves
land under the same `session_id`, the ledger key matches (both hooks run in the
parent session's cwd, not the worktree), and the credit is recorded.
`isolation: "remote"` remains unprobed. A pairing record written in the pre-join format degrades to a
miss rather than a false credit (the key field is empty, and an empty key never
compares equal), which is the correct direction for a format change.

## Dissenting views

**"This is a better-looking attestation, not better evidence."** Partly true and
stated in the proposal: observed completion does not establish that the output
was a review, that it examined this diff, or that anything was acted on. The
defence is narrow: it is strictly more than a `Skill()` return at
instruction-load time (which witnesses nothing) and strictly more than observed
dispatch (which credits a reviewer that crashed on spawn). It is not a quality
gate and the code says so in its header.

**"Remedy cost, not predicate strictness, is the binding constraint."** Endorsed,
including by the sparring review, and this change is deliberately consistent with
it rather than in tension: it raises fidelity while **lowering** remedy cost,
because the dispatch already happens in compliant sessions and credit becomes
automatic with no extra CLI call. Sharpened form, which is the more accurate
framing: this is not tightening a screw past where it buys anything — the current
gate is satisfied by an event carrying *less* information than "the reviewer
started running", so this closes a gap in the free ride rather than raising a bar
anyone must clear.

**"Is any predicate over review findings non-theatre when one agent wrote both
the code and the review?"** No — and this was the sparring review's answer too,
without hedging. Any classifier over what the reviewer *said* (keyword density,
a `Findings:` header, file:line citations, absence of "LGTM") is satisfiable by
boilerplate cheaper than a real review the moment the dispatching model has an
incentive to unblock; citations are especially weak, since the model wrote the
diff and can cite plausible lines without having reasoned about them. This repo
has already paid for that lesson once, and #205's adjudication rule needed an
actual *reproduction* step precisely because content review was untrustworthy
even for human-originated findings.

The narrow exception worth recording so "no content predicate works" is not
overstated into "no further signal is possible": a **behavioural** check on the
reviewer's own transcript — did its tool-call trace touch the files under review
before it emitted a final message — is not grading findings. It is still gameable
by an instructed rubber-stamp, but it is harder to fabricate than zero-effort
text and does not inherit the self-grading problem. Possible next increment, in
the same procedural spirit. Not built here.

## Decisions

- **D1.** Record `reviewer-returned` as a new milestone rather than
  strengthening `reviewer-ran`. Dispatch and completion are different facts;
  collapsing them would make existing records silently mean something they never
  measured.
- **D2.** No gate reads the new milestone in this change. Pinned by a cell
  asserting `openspec-guard.sh` does not mention it. Any future deny-flip must be
  framed as narrowly as the IMPLEMENT leg's — "closes a measured completion gap",
  never "review quality is now assured".
- **D3.** Not in `_GATE_ENFORCE_LIBS`. That list drives the session-start
  precondition canary and the drift manifest; a diagnostic recorder joining it
  would make a missing recorder announce as a degraded gate. Pinned by a cell.
- **D4.** Classification for BOTH arms lives in the dispatch hook. The earlier
  design let the allowlist arm credit at completion with no dispatch record,
  which was simpler but left the branch-binding hole open for exactly the
  backgrounded case where it bites.
- **D5.** `session_id` and `agent_id` are validated as single path-safe segments.
  The values are harness-supplied, but a recorder must not be the component that
  turns a surprising value into a read or write outside `~/.claude`.
- **D6.** TWO guards are knowingly redundant and kept: the `[ -f ]` before
  `wc -c` (the `|| bytes=0` is the live handler) and `|| true` on
  `note_mismatch` (the hook exits immediately after either way, so the two paths
  are observably identical). No test can catch their removal, and each says so in
  a comment rather than being presented as covered.

  A THIRD was claimed redundant here and was not. `[ -n "${_DKEY}" ] || exit 0`
  is redundant *for crediting* — the branch comparison also rejects an empty key
  — but removing it is observable and harmful: the hook then fabricates a
  `# branch-mismatch` line for every ordinary subagent completion. That is a
  FALSE diagnostic ("never dispatched as a reviewer" is not "branch mismatch")
  and it multiplies the completion file's growth rate, bringing the ceiling below
  closer. Caught in review; the gap was that only the PRESENCE of a mismatch line
  was ever asserted, never its absence. Cell (j4) closes it.
