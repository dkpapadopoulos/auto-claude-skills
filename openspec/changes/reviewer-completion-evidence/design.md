# Design: observed reviewer completion

## Architecture

Two hooks, one exact key, no heuristic between them.

```
Agent dispatch                              Subagent finishes
      |                                            |
PostToolUse ^(Task|Agent)$                    SubagentStop
reviewer-evidence-hook.sh                reviewer-completion-hook.sh
      |                                            |
  predicate on tool_input.description        agent_type in allowlist? -> credit
  (unchanged, 9/9 @ 1/7)                     agent_type == general-purpose?
      |                                            |
  reviewer? -> record `reviewer-ran`           look up agent_id  <----+
            -> append agent_id to             in the pairing file     |
               ~/.claude/.skill-reviewer-dispatch-session-<sid>  -----+
                                                   |
                                             credit `reviewer-returned`
```

Both hooks read `session_id` from **their own payload**, and the two events
carry the identical value (measured in one run; it also equals the transcript
basename, so the filename is `_SESSION_TOKEN`-shaped and the session-start GC
excludes the live session with a plain `! -name` match).

This is deliberately **not** `resolve_own_session_token`. That resolver exists
for model-Bash-turn writers, which have no payload; its singleton fallback is
the last-writer-wins scatter behind #51/#97/#122/#131/#133/#151/#156. Here both
sides are payload-driven within one session, so symmetry holds by construction
rather than by convention — and cell (i) drives the real writer to prove it,
instead of asserting it against a hand-written fixture.

## Why a dispatch-time writer at all

`SubagentStop` carries `agent_type` but not the dispatch `description`. Three
ways to recover reviewer-ness were considered.

1. **Apply the existing predicate to the subagent's task prompt.** Rejected.
   The prompt is reachable (`agent_transcript_path` exists at hook time and its
   first `user` record is the prompt verbatim), but the predicate
   `*[Rr]eview|*[Rr]eview[!a-zA-Z]*` was **fitted on a short `description`
   label**. Its second arm matches "review" anywhere followed by a non-letter,
   so against multi-paragraph prompt text it structurally degenerates into the
   substring variant that measured 4/7 false positives. Lifting it "verbatim"
   onto a different population would ship exactly the widening that variant was
   rejected for, silently — the predicate would look unchanged in the diff.

2. **Read the parent transcript to find the dispatch record.** Rejected, and
   this one is closed by measurement rather than judgement. Instrumented from
   inside the hook: at `SubagentStop` time the parent transcript contained
   **zero** lines mentioning `agent_id` (18-line parent, 4-line subagent
   transcript readable). The `tool_result` carrying `agentId` is written after
   the event fires, so the link exists only post-hoc.

3. **Write the pairing at dispatch.** Chosen, by elimination — (2) proves no
   reader-side reconstruction exists.

## Trade-offs

**A lookup MISS records nothing.** The alternative — a weaker milestone on a
miss — was rejected on two grounds. A miss is indistinguishable from a genuine
reviewer whose dispatch went unrecorded (older plugin, hook disabled, GC'd
pairing), so the weaker record could not be interpreted; and the missing
population is dominated by ordinary implementation subagents, so it would be
mostly noise wearing an evidence label. Under-recording is the safe direction
for a signal whose whole purpose is fidelity.

**An empty `last_assistant_message` is not a return.** A reviewer that emitted
nothing — interrupted, crashed — did not produce a review. This under-credits an
interrupted reviewer, again the safe direction.

**The reviewer's output text is deliberately NOT recorded.** The payload carries
it inline and it would make the strongest-looking evidence, but it is unbounded
model output that can quote the diff, secrets, or private memory content into a
file that outlives the session. This repo already ships `hooks/publish-guard.sh`
because that class of content leaking outbound is a known risk; the ledger keeps
storing a sha and a timestamp.

**A size ceiling, not a trim.** Parallel dispatches in one turn run their hooks
concurrently, so a read-modify-write rotation would race. Appending short lines
and refusing to append past 64KB drops new records under pathological load
rather than corrupting existing ones.

**Ordering is load-bearing, and the first draft got it wrong.** The pairing
write initially sat above `branch_ledger_record "reviewer-ran"`. Under that
file's `trap 'exit 0' ERR`, `wc -c < <missing file>` is a redirection failure
that `2>/dev/null` does not suppress, so the hook exited 0 in silence and
stopped recording the **pre-existing** milestone. Caught by cell (i3), which
existed only because the end-to-end cell drives the real writer. New
best-effort work goes below the thing that must not be lost — this is the
#137/#198 class arriving from a new direction.

**Known misses, inherited and unfixed.** `branch_ledger_key` is
`sha1(origin remote URL, branch)`, so a review recorded on a task branch and a
push made from an integration branch do not share a key — which is the normal
shape of this repo's own `agent-team-execution` pattern — and a detached HEAD
re-keys on every commit. Misses are safe (a reader finds no record) but a
missing record must never be read as "no review happened".

## Dissenting views

**"This is a better-looking attestation, not better evidence."** Partly true and
stated in the proposal: observed completion does not establish that the output
was a review, that it examined this diff, or that anything was acted on. The
defence is narrow and specific — it is strictly more than the status quo (a
`Skill()` return at instruction-load time, which witnesses nothing) and strictly
more than observed dispatch (which credits a reviewer that crashed on spawn).
It is not a quality gate and the code says so in the header.

**"Remedy cost, not predicate strictness, is the binding constraint."** The
competing thesis is that the gate is already accurate, its escape (a human
typing `!`) is free and unrecordable, and tightening a gate whose escape is free
mostly buys more escaping. This change is deliberately the one candidate that
does not fight that thesis: it raises fidelity while **lowering** remedy cost,
because the dispatch already happens in compliant sessions and credit becomes
automatic with no extra CLI call. If the thesis is right, this change is still
the right shape; what it forecloses is any follow-up that raises the cost of
compliance.

**"Is any predicate over review findings non-theatre when one agent wrote both
the code and the review?"** Held open, deliberately, and it must be answered
before any deny-flip — not before this increment, which wires no gate. The
honest position today: a predicate over *findings* (count, severity, resolution)
is gameable by the same model that authored the code, so it measures compliance
theatre rather than review quality. What is not gameable by prose alone is that
a **second context** had to be spun up and had to produce output — that is a
real resource cost, not a claim. This change buys exactly that and nothing more,
which is why the label is "observed completion".

## Decisions

- **D1.** Record `reviewer-returned` as a new milestone rather than
  strengthening `reviewer-ran`. Dispatch and completion are different facts, and
  collapsing them would make existing `reviewer-ran` records silently mean
  something they never measured.
- **D2.** No gate reads the new milestone in this change. Pinned by a test cell
  asserting `openspec-guard.sh` does not mention it. The deny-flip decision
  belongs to a shadow corpus, as with the IMPLEMENT leg.
- **D3.** Not in `_GATE_ENFORCE_LIBS`. That list drives both the session-start
  precondition canary and the drift manifest; a diagnostic recorder joining it
  would make a missing recorder announce as a degraded gate. Pinned by a cell.
- **D4.** The allowlist arm needs no pairing, so it keeps working when the
  dispatch hook did not run (older plugin, hook disabled). Pinned by cell (a),
  which runs with no pairing file present at all.
- **D5.** `session_id` is validated as a single path-safe segment on both sides.
  The value is harness-supplied, but a recorder must not be the component that
  turns a surprising value into a read or write outside `~/.claude`.
