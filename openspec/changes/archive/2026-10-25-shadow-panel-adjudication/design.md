# Design: panel adjudication of the shadow corpora

Decided with the owner on 2026-10-23. Codex was consulted on how to build it
before seeing this design; its recommendations are adopted where marked. A
builder check (fresh Claude subagent) raised eight questions. Two were settled by
the owner (decisions 7 and 9). The rest are marked *builder's call*.

## Intent

Get both shadow legs to a decision before their evidence decays. A human
labeller was a bottleneck nobody scheduled, so the owner replaced them with a
model panel. The work is to make that panel's labels trustworthy enough to feed
a pre-registered rule whose costly error is a deny-flip wrongly granted.

## Goals, non-goals, anti-goals

- **Goal:** both legs get human-free labels that the readers count. The
  adjudicator, cohort, cadence and pass criteria are all fixed before the first
  label.
- **Goal:** the tooling is reusable. Later cohorts run the same pipeline under a
  fresh registration.
- **Non-goal:** flipping any leg to deny. That stays a separate owner decision.
- **Non-goal:** changing a floor, band, definition or episode rule.
- **Anti-goal:** a clean rate produced by selection. Easy episodes get labelled
  while hard ones go missing, disputed, expired or quota-delayed, and the
  denominator is clean because it is selected. This is Codex's second most likely
  failure. The frozen cohort, the single decision point, the completion
  requirement and the 10% unknown cap exist to prevent it.
- **Anti-goal:** confident unanimous mistakes from shared missing evidence. All
  three judges see "no review found" because the extractor missed it. This is
  Codex's most likely failure, and the coverage manifest, the end-to-end controls
  and the rule that an absence needing proof is `unknown` exist to prevent it.

## Approaches considered

- **A. Fixed evidence packets.** Chosen by the owner, recommended by Codex and
  by me. A deterministic extractor builds one packet, and all three judges label
  it independently. It is the cheapest on Codex quota and auditable. Its weakness
  is shared omission, which the controls exercise end to end.
- **B. Agents discover evidence.** Claude readers find transcript spans, which
  are unioned into the packet. Fewer omissions, but more cost, and the evidence
  selected depends on the readers.
- **C. Two-round evidence requests.** Judges ask for more from a fixed menu.
  More calls and more room for selective retrieval, and a poor fit for quota.

## What the owner decided

1. The panel replaces the human adjudicator for both legs.
2. The REVIEW leg gets a new window. The 2026-09-23 window stays closed.
3. Codex may be sent anything this work needs without per-send consent. The
   owner set `consultation.egress_consent: "warn"` on 2026-10-23. Every package
   is still gitleaks-scanned, and least-data still applies.
4. Claude agents may sit on the panel.
5. Approach A, with **80 planted controls**.
6. `cleanupPeriodDays: 180`, set by the owner on 2026-10-23.
7. **Unknowns get a cap, not a worst-case veto.**
   - The worst-case rate counts every `unknown` as `false_block`. It is
     REPORTED, as the original registrations say, and decides nothing.
   - A leg is DENY-eligible only if `unknown` (including `lost`) is at most
     **10%** of its cohort.
   - A binding worst case was drafted and dropped. It allowed 1 bad-or-unknown
     episode in 58 (IMPLEMENT) and 8 in 142 (REVIEW), and 6 IMPLEMENT episodes
     were already lost, so that leg could never have qualified.
   - The cap keeps hard cases from being set aside quietly.
8. **Episodes lost before registration leave the cohort.** They were lost by
   age (30-day retention), not by content, so excluding them selects on nothing
   the rate measures. They are listed with their cause. Measured 2026-10-23:
   6 IMPLEMENT and 2 REVIEW. An episode lost after registration becomes `lost`,
   which counts as `unknown`, and therefore against the cap.
   - *Extension, decided by the owner 2026-10-24: `compacted`.* An episode
     whose push evidence compaction destroyed before registration also leaves
     the cohort, with cause `compacted`. The rule: the push is found in neither
     the transcript nor any `.bak` copy, AND the earliest surviving history is
     later than the episode's first record. Surviving history is the earliest
     timestamped line that is not a compaction marker (a `compact_boundary`
     system line, or a line with `isCompactSummary`), across the transcript and
     its `.bak` copies. Markers keep their original timestamps, so counting
     them kept every IMPLEMENT episode whose history was gone (measured
     2026-10-24: 15 of 15). A push not found, with real earlier history, stays
     in as a locator gap. After registration such a loss is `lost`.
9. **"Warned, pushed anyway" is a true catch.**
   - The label is `true_catch` when the gate's premise held (there really was
     no review, or no implementation evidence, for the changes pushed) and its
     message named the right remedy. It does not matter whether anyone acted
     on it.
   - A review of an earlier commit counts as a review only if it covers the
     changes actually pushed (the REVIEW `unbound` reason).
   - This reads the registered definitions; it does not change them. The rubric
     states it verbatim, and the true-catch controls include this shape.
10. **Absence is established by a whole-session search, not a window**
    (owner, 2026-10-24). See §3a. Window packets could not do it: measured
    2026-10-24, no IMPLEMENT episode has a decisive event anywhere before its
    push, so every IMPLEMENT label rests on an absence, and sessions run a
    median of about 180 events (up to 469) before the push. At every cap from
    16,000 to 32,000 bytes and every N from 40 to 160, 97% of IMPLEMENT and at
    least 48% of REVIEW items were likely `unknown`, against a 10% cap.
11. **The experiment's own sessions are excluded** (owner, 2026-10-24). Every
    record on this change's own branch (`feat/shadow-panel-adjudication` in
    this repository) is excluded in both legs, by `--exclude`, with the reason
    stated. Sessions that build the instrument are not independent of it, and
    the branch was never pushed, so each such record is text the scanner read
    as a push. This selects on provenance, not on anything the rate measures.

## The pipeline

### 1. Preservation (weekly, and first on 2026-10-23)

Copy every transcript a poolable would-block record points to into
`~/.claude/.shadow-transcripts/<project-dir>/<session>.jsonl` (dir `0700`, files
`0600`). Re-copy a file when the source has grown, since sessions keep running.
Resolution order:

1. the archive copy, if it is at least as large as the live file;
2. the recorded `transcript_path`;
3. an exact basename match under `~/.claude/projects/*/`.

Several basename matches leave the identity unresolved. The extractor never
picks the most convenient one. A record with no transcript is reported as
`lost`, with its cause (`no-pointer`, `deleted`, `ambiguous`), and is never
dropped silently.

### 2. Cohort and order (once, at registration)

- **Cohort.** The leg's existing **rate population**: exactly the episodes the
  reader computes the rate over today. That excludes IMPLEMENT's advisory-silent
  records and any malformed `would_block`. It is taken at the adjudicable
  `predicate_version` and built by the readers' existing episode grouping over
  the corpus snapshot. The snapshot is the corpus file copied at registration,
  with its sha256 recorded in the amendment. Episodes already lost at
  registration are removed (decision 8). Episodes after the snapshot belong to a
  later cohort. *(Builder's call: the cohort is the reader's population, so the
  panel never labels an episode the reader then excludes.)*
- **Order.** Sort the cohort by `record_id` of each episode's first record, then
  shuffle with a seed equal to the registration commit's sha. Python
  `random.Random(int(sha[:16], 16))`.
- **The manifest** `cohort-<leg>.json` stores, in order: episode id, member
  record ids, and the snapshot digest. The excluded lost episodes are listed
  separately with their causes.
- **An episode lost after registration stays in the cohort** with a terminal
  label of `lost`. It is reported beside the rate and counts as `unknown`.

### 3. Evidence packet (deterministic, `scripts/shadow-panel-packet.py`)

One packet per episode. Plain text, at most 6,000 bytes, with these sections:

1. **Records.** Every member record's fields, with paths and repo names
   pseudonymised consistently within the packet (`repo-A`, `branch-1`).
2. **Gate output.** The advisory or deny text the agent saw, taken from the
   transcript's hook attachments next to the push.
3. **Before.** Tool calls and tool results, the actual output, from the last N
   turns before the first push (N fixed in the amendment). This covers skill
   invocations, review dispatches, test runs and commits.
4. **After.** What happened in the window after the push, up to the next 20 tool
   events or 2 hours: retries, attestation, a review run, abandonment.
5. **Coverage manifest.** Sources searched, transcript resolution outcome,
   truncation (bytes cut and from where), redactions, and unresolved references.

How the extractor handles the text:

- It never summarises. It copies spans, and transcript content is fenced and
  labelled as evidence, not instructions.
- Control characters and invalid UTF-8 are replaced deterministically, because
  the dispatcher refuses them.
- The packet is gitleaks-scanned during extraction. Any flagged span is
  redacted and recorded in the coverage manifest, so a secret never makes an
  item unsendable.
- The packet's sha256 is recorded.
- *(Builder's call: 6,000 bytes is a default, like N. It may be raised before
  registration if measured packets show the cap cutting decisive spans.)*
  Raised to 16,000 on 2026-10-24: at 6,000 the gate's own advisory was cut in
  about half of all packets, and in 0 of 36 IMPLEMENT and 1 of 129 REVIEW from
  16,000 up. N stays 40; with §3a, N only shapes the narrative window.

### 3a. Whole-session search (amendment 2026-10-24, decision 10)

Every packet gets a **SEARCH** section. It is how a packet establishes an
absence; the BEFORE window no longer has to.

- **Scope.** Every line of the resolved transcript and of each `.bak` copy,
  from each file's first line up to the push the packet anchors (to the end
  of the file when no push was found, and SEARCH says so). Lines repeated
  across copies count once.
- **Did it reach the start?** SEARCH states whether the session's first line
  was among the lines searched. The first line is a line with no parent
  (`parentUuid` null) that is not a compaction marker. When none was
  searched, SEARCH says that history before its earliest line survives only
  as compaction summaries, which are searched like any other line.
  *(Builder's call: verify that indicator on every cohort transcript and
  report how many have one before relying on it.)*
- **What counts as a match.** Only what the agent or the user did: tool call
  inputs, text the user typed (slash commands included), and Skill tool
  results. Never hook output or system reminders: the router and the gate
  name the skills in every hint, so matching them would find a "call" in
  every session. Matchers are deliberately broader than the gate's own
  check, so the search can find evidence the gate missed:
  - IMPLEMENT: any mention of `executing-plans`,
    `subagent-driven-development`, `agent-team-execution` or `phase_attest`.
  - REVIEW: a Skill name or slash command containing `review`; any Agent or
    Task call; any SendMessage; a Bash command naming
    `record-review-verdict`, `consult-dispatch` or `codex`.
  The builder may broaden a matcher, never narrow one, and the amendment
  lists the final matchers.
- **What it prints.** The number of matches per kind, then each match as an
  excerpt, with the same excerpt sizes, pseudonymisation, fencing and
  gitleaks scan as BEFORE, labelled with its file and its distance from the
  push in events. A match already shown in BEFORE is listed by distance
  only. When matches overflow the budget, the nearest to the push are kept
  and the number left out is stated.
- **Never a verdict.** SEARCH reports what it found and where. The judges
  decide what a match means; a match on `review` in an unrelated command is
  theirs to discount.
- **Budget.** Its own share of the 16,000 bytes. *(Builder's call: size it
  from the measured match counts.)*

The rubric's unknown rule already says an absence counts only when "COVERAGE
shows the relevant window was searched and present". The rubric now names
SEARCH as that window: an absence of a searched kind is established only when
SEARCH says the session's first line was searched. Decision 9 stays verbatim.

**Controls.** All 80 packets are rebuilt with the new extractor, and
acceptance is re-run on every one:

- A true-catch control must have a SEARCH that reached the session's first
  line and found no decisive match, replacing "BEFORE reaches the transcript
  start".
- IMPLEMENT's cut-evidence `unknown` control (impl-22) no longer represents
  anything, because SEARCH shows the call whatever the window cuts. It is
  replaced by a withheld-transcript `unknown`, the same shape as REVIEW's.
  *(Builder's call: prefer a session whose call was lost to compaction, the
  realistic hard case, if one can be produced.)*
- Any control the new acceptance rejects is regenerated.

**Before freezing, re-measure** with the rule fixed before the numbers. An
item is likely `unknown` when no decisive event is visible in SEARCH or
BEFORE and SEARCH did not reach the session's first line, or when its push
was not found. If that is more than 10% of a leg, that leg is closed
INCONCLUSIVE before registration instead of being run.

### 4. Judges

- **Claude, twice.** `claude -p` in a fresh isolated HOME (recipe:
  memory `isolated-home-headless-ab`), with tools disabled, the model pinned by
  id, and every `CLAUDE*` env var stripped. Stripping matters doubly here,
  because the run itself happens inside a session. Two separate invocations, so
  the two have no shared context. With no tools they cannot read past the
  packet, which makes "identical evidence" true by construction.
- **Codex, once.** `consult-dispatch.sh prepare` then `send`, read-only, from an
  isolated directory. Up to 3 packets per call, to save quota. The batch
  composition is fixed by the cohort order (consecutive items) and recorded.
- **Prompt.** A frozen rubric: the registered definitions verbatim, decision 9's
  reading verbatim, the output schema, and the rule that a decisive absence the
  coverage manifest cannot establish means `unknown`. Its sha256 goes in the
  amendment.
- **Output.** JSON `{"label": "true_catch"|"false_block"|"unknown", "evidence":
  [<packet line refs>], "reasoning": "<=80 words"}`. A response that fails
  schema validation is `invalid`, and the same packet is retried once with the
  same prompt. A second failure makes the item `pending`.
- **Stuck items** *(builder's call)*. A `pending` item is retried on the next
  weekly run, for up to **three** weekly runs, and then becomes a terminal
  `unknown` with cause `stuck`. An item is `pending` if it was invalid twice, if
  Codex reported `MAY HAVE SENT`, or after any other send failure. So one bad
  response can neither block completion forever nor vanish.

### 5. Aggregation (deterministic)

- Three valid, identical substantive labels: that label.
- Any disagreement, or any judge saying `unknown`: `unknown`.
- Any judge `pending`: the item stays unadjudicated, never fabricated. Valid
  answers already stored are kept, and the resumed run asks only the missing
  judge.
- **No re-running a valid answer to get agreement.** Two Claude votes never
  outvote Codex.

The result is appended to the leg's existing sidecar
(`~/.claude/.push-{implement,review}-adjudication.jsonl`), one row per member
record, with `claimant: "panel"` and these extra fields: `cohort`,
`panel_config_sha`, `packet_sha`, `judge_labels`, and `run_dir`. Raw judge
responses stay in `~/.claude/.shadow-panel/<leg>/<episode>/` (`0700`).

### 6. Planted controls (80)

**Per leg, 40:** 29 known `false_block`, 10 known `true_catch`, and 1 where the
decisive evidence is made unavailable (expected `unknown`).

- **Generation.** Run the real plugin and gate in headless `claude -p` sessions
  in throwaway repositories, under an isolated HOME, with `*_SHADOW_LOG`
  redirected into a control corpus and `PUSH_GATE_CAPTURE_DISABLE=1`. Each
  scenario is a scripted prompt plus a repo setup, and its ground truth comes
  from the execution manifest: what was actually done, verified from artifacts.
  It never comes from a model's description of the scenario.
- **Scenario families**, with variation in repo, language, commit count, noise
  and order:
  - IMPLEMENT false block: the evidence exists, but path resolution misses it
    (worktree, `cannot_check`). Or the advisory names a remedy that cannot
    resolve the situation.
  - IMPLEMENT true catch: no implementation evidence, and the agent attests
    truthfully. Or the agent is warned and pushes anyway (decision 9).
  - REVIEW false block: a review ran via a typed slash command, which the
    credit hook never sees (measured 2026-10-23). Or an infrastructure failure
    lost the artifact and the advisory misnames the cause.
  - REVIEW true catch: no review, then the author runs one. Or the agent is
    warned and pushes anyway. Or the review covers an earlier commit and
    material changes follow it.
  - Missing evidence: the decisive file is deleted before extraction.
- **Fault injection is allowed** *(builder's call)*. A scenario may break the
  throwaway environment (move a worktree, make a lib unreadable, lose an
  artifact) to produce a false-block shape, provided the gate code is the real
  installed version. A family the current gate cannot produce at all is dropped
  before registration, and its count is rebalanced across the other families.
- **Same pipeline.** Controls go through the same extractor, pseudonymisation,
  packet format and judges as real episodes. The answer key lives in a `0700`
  file the judges never see.
- **Controls run first, as a qualifying round** *(builder's call)*. They are
  judged in a seeded random order before any real episode.
  - The judges are stateless (no-tools `claude -p`, ephemeral Codex), so
    interleaving controls with real episodes would buy no blinding that a
    qualifying round lacks.
  - Running the controls first means a failure costs no real labels and never
    causes a second look at the real cohort.
- **Pass criterion, per leg:**
  - all 29 false-block controls labelled `false_block`, with `unknown` counted
    as wrong. With zero misses in 29, the one-sided 95% upper bound on the panel
    missing a false block is below 10%, on the represented scenario
    distribution;
  - at least 9 of 10 true-catch controls labelled `true_catch`;
  - the missing-evidence control labelled `unknown`.
- **Failure.** If a leg fails, that leg's real cohort is not started. A retry
  needs a new frozen configuration and fresh, held-out controls. The same answer
  key is never re-run.
- **Honest scope.** 29 related scenarios are not 29 independent trials. The
  bound is a smoke test of known failure shapes, not an independent audit. This
  is stated in the amendment and in the reader's output. Codex proposed 236
  controls, and the owner chose 80 knowing that.

### 7. Readers

Both readers gain one provenance, `claimant == "panel"`, under these conditions:

- **Countable** only when its `cohort` matches the registered cohort id for that
  leg, and the control status file reports `PASS` for that leg and
  `panel_config_sha`.
- **Agent-claimed** rows stay excluded, as today.
- **Human-claimed** rows stay reported, but under an amended window they do not
  enter `n`. One adjudicator per window.
- **`n` is named once, for both legs** *(builder's call)*.
  - `n` is the panel-counted episodes with a substantive label, `true_catch`
    plus `false_block`, and `k` is the `false_block` count.
  - `unknown` and `lost` are reported beside `n` and never counted in it.
  - Today the IMPLEMENT reader uses `tc+fb` and the REVIEW reader uses
    `fb+tc+unk`. The amended windows use `tc+fb` for both. That is the
    conservative reading, since unknowns cannot inflate `n` toward the floor,
    and it is what the 2026-09-23 closing amendment asked a successor to fix.
- **Report.** The band through `shadow_band` (no re-derivation), the worst-case
  band (reported only), the unknown share against the 10% cap, the counts of
  `lost`, `unknown` and `pending`, and the control status.
- **DENY-eligible** is printed only when all of these hold:
  - the cohort is complete, meaning every item is labelled, `unknown` or `lost`;
  - the headline band is DENY;
  - `unknown` plus `lost` is at most 10% of the cohort;
  - the repo floor is met over counted episodes;
  - the controls PASS.
- Otherwise it prints why not.
- **Futility stop** *(builder's call)*. Once DENY-eligibility has become
  arithmetically impossible for the rest of the cohort, the runner reports
  "DENY ruled out at item i" and may stop that leg. That happens when there are
  enough `false_block` labels, or when unknowns pass the cap. Stopping can only
  withhold a deny, never grant one, so this look does not touch the costly error
  direction.

### 8. Cadence and the decision point

The owner is the named accountable operator. The weekly run happens **inside a
Claude Code session**: the owner asks for it, or types `! bash
scripts/shadow-panel.sh --weekly`. It has to be in a session because
`consult-dispatch.sh` needs a session identity before it checks the consent mode,
and refuses without one. Loosening the dispatcher so it runs from a bare
terminal is out of scope; it would be an outbound-guard change of its own.

`--weekly`:

1. preserves transcripts;
2. extracts packets for the next items, controls first and then cohort order;
3. runs the judges on as many items as quota allows;
4. aggregates;
5. prints progress.

On quota exhaustion it stops and resumes from the first item that is not
complete.

**There is one decision analysis per cohort**, run when the cohort is complete.
Apart from the futility stop, there is no interim test: repeated looks void the
binomial guarantee. If the cohort is not complete by **2027-01-31**
*(builder's call)*, the result is reported as INCONCLUSIVE, and nothing is
authorised from the completed subset.

## Constraints

- Bash 3.2 for orchestration, Python 3 for extraction, aggregation and
  shuffling, jq for inspection. Never `set -e`. Never read stdin.
- Diagnostic-only. Excluded from `_GATE_ENFORCE_LIBS`, no `permissionDecision`
  output, no gate state.
- Codex quota is the throughput limit. At about 3 packets per call, 272 items
  (80 controls, 52 IMPLEMENT, about 140 REVIEW) take about 90 Codex calls, so
  plan on weeks, not days.

## Residual risks (stated, not solved)

- **An orchestrating agent could forge judge responses.** The panel run is
  agent-orchestrated. Packet and response digests make forgery deliberate rather
  than accidental, which is the same standard the human-claimed path met.
- **Controls may be distinguishable** from real episodes (headless prompts,
  scripted repos). Pseudonymisation reduces the cues; it does not remove them.
- **Same-family judges.** Two Claude votes are not two independent sources.
  Unanimity across families is the mitigation.
- **Shadow mode cannot prove** what a block would have caused. "Could not
  proceed" needs affirmative evidence, and silence is `unknown`.
- **On IMPLEMENT, the search largely decides the gate's premise** (§3a). A
  matcher, not a judge, says whether any implementation evidence exists in
  the session. It is broader than the gate's check, but a skill run under
  another name is invisible to both. Evidence in another session on the same
  branch is not a gap: the gate reads the branch ledger, so such evidence
  would have satisfied it. What the panel adds on this leg is mostly whether
  the remedy was right and whether the person could proceed.
- **Broad REVIEW matchers put noise in front of the judges** (any Agent
  call). That pushes toward `unknown`, never toward a wrong label, and the
  re-measure before freezing counts it.

## Left to the builder

- The value of N turns before the push, and the after-window bound, if the
  measured transcripts show the defaults cut evidence. They must be set before
  registration.
- The rubric wording, within the definitions and decision 9 verbatim.
- Packet section budgets inside 6,000 bytes.
- The control scenario scripts, within the families above.

## Outcome 2026-10-25 — not registered: both legs closed INCONCLUSIVE before registration

Nothing was frozen or registered. No real episode was judged and the control
qualifying round never ran; the judges were run only on a few pilot control
packets while the controls were being authored. The rule in §3a, approved
before its numbers were seen, closed both legs.

**Measured** (cohort snapshots of 2026-10-24, cap 16,000, N 40, SEARCH on,
decision 11 applied; `task-S4` measurement). An item counts as likely
`unknown` when its push was not found in the transcript or any `.bak` copy (P), or when no
decisive event is visible in SEARCH or BEFORE and SEARCH did not reach the
session's first line (U). "Decisive" uses the narrow kinds: the gate's own
evidence for IMPLEMENT (the implementation-skill call or `phase_attest`),
and for REVIEW a reviewer dispatch, a review skill, a recorded verdict or a
Codex review run.

| leg | kept | P | decisive event visible | absence established | U | likely `unknown` |
|---|---|---|---|---|---|---|
| IMPLEMENT | 37 | 0 | 0 | 14 | 23 | **62.2%** |
| REVIEW | 130 | 12 | 96–107 | 6–12 | 5–10 | **13.1–16.9%** |

The REVIEW range spans the two SEARCH matcher versions measured.

**Why, per leg.**

- **IMPLEMENT: compaction.** In all 23 U items, every surviving copy of the
  session begins at a compaction marker, and no surviving compaction summary
  names an implementation skill. They cluster: 16 of the 23 come from one
  long session. No packet design can show history that compaction deleted.
  In the earlier window-only measurement (before SEARCH), 97% were likely
  `unknown`.
- **REVIEW: mostly the instrument.** The 12 P items (9.2%) are episodes whose
  push the locator could not find although earlier history survives (locator
  gaps under decision 8). Of the 10 U items at the later matcher version, 7
  exist only because SEARCH drops matches past its budget (U falls from 10
  to 3 with every match shown); 5 of those 7 come from the broadened
  matchers crowding decisive matches out, and 2 overflowed already before
  the broadening. With every match shown, REVIEW would
  be at 11.5% under the narrow kinds, two items over the cap.
- **Retention contributed nothing** to either rate: episodes already lost by
  age left the cohort before measurement (decision 8).

**Consequences.**

- **IMPLEMENT:** the panel adjudicator is not registered, so the window in
  `implement-shadow-event` stands as it was: open, human-claimed labels only,
  horizon unknown pending re-estimate. The deny-flip criterion is not met and
  the leg stays advisory.
- **REVIEW:** the successor window is not registered. The first window was
  closed as a null result on 2026-09-23, so no REVIEW window is open. The leg
  stays advisory, as decided then.
- The instrument is not merged. It stays, reviewed and tested, on the
  unmerged branch `feat/shadow-panel-adjudication` (at `dbd06f6c`). The
  `--rate-episodes` reader option is the one piece merged.
- Defects found and not fixed, because nothing will run on them: the search
  can report reaching the session start while overflow hides reviewer
  dispatches (10 of 12 REVIEW "absence established" items); the broadened
  matchers crowd decisive matches out; `controls._SECTION_RE` does not know
  SEARCH; the 80 controls were accepted at 6,000 bytes without SEARCH.

**What a successor needs.** Capture the evidence when the gate decides,
rather than reconstructing it from transcripts afterwards: what the gate
checked, what it found, and what it would have told the agent, written beside
the shadow record at decision time. That removes all three causes above:
compaction, the push locator and the search budget. A REVIEW-only panel on a
fixed locator and overflow policy might also clear the cap; that would be a
new registration, not this one.
