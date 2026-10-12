# Prioritization after the AI Daily Brief review (2026-10-12)

Decision record from: 38 AI Daily Brief digests (2026-09-02..10-11) -> ten recommendations ->
Codex critique (cross-vendor, critique mode) -> design debate (architect / critic / pragmatist,
two rounds, repo read-only) -> lead verification of every load-bearing number.

## Problem statement
Decide which plugin improvements to pursue in the next 4-6 weeks, given newsletter-derived
ideas, the plugin's own measured audit (routing precision is the defect), and a solo owner
whose binding constraint is labelling hours, not code.

## Facts established this session (verified by lead, not inherited)
- #239 is CLOSED (2026-09-22, null result: review-shadow corpus had an empty transcript pointer in
  every record). No REVIEW deny-flip registration exists.
- Recommendation 2 (post-compaction re-injection of intent) ALREADY EXISTS: pre-compact-hook.sh,
  compact-recovery-hook.sh (SessionStart matcher compact), compact-recovery-prompt-hook.sh (prompt
  carrier), hooks/lib/compact-recovery-render.sh, tests/test-compact-recovery.sh.
- ~/.claude/.compact-events.log: Sep 11 auto compactions / 11 post_compact recoveries; Oct 9 auto +
  1 manual / 8 post_compact + 1 prompt-carrier. SessionStart(compact) pairs with auto compaction
  again, contradicting the carrier's premise comment ("since ~2.1.179 auto no longer emits").
- #343 VERIFY shadow (scripts/verify-shadow-adjudicate.sh --status, 2026-10-11T22:27Z): 18 records,
  15 would-block episodes, all unexplained, all unresolved; accrual 1.9/day; clause 1 needs 29
  (~2026-10-19); clauses 3,4 need owner labels; first fortnightly read due 2026-10-12 (today).
- #333 stage A shadow: 48 records, rule_version 3, would_hide=true in ZERO; by skill brainstorming
  16, systematic-debugging 18, requesting-code-review 10, product-discovery 3, receiving-code-review 1.
  Closes at 60 would-hide rows or 2026-11-16 -> will close by date as a null result. Same records
  carry block_chars: mean 5,074 chars per displayed block (~1,200-1,500 tokens per blocked prompt).
- #295: hooks/lib/verdict.sh verdict_is_clean reads only failed / could_not_verify /
  gate_gaming_status; every VERIFY source is agent-writable; the provenance-aware predicate exists as
  the #301 shadow leg. 48 of 52 verdict artifacts on disk were written by verify-and-record.sh.
- #297: hooks/skill-activation-hook.sh:1444 renders [DONE?]/[CURRENT]/[NEXT]/[LATER]; no text says a
  missing requesting-code-review or verification-before-completion denies the push.
- #304: hooks/session-start-hook.sh:697-717 merges triggers/role/phase/priority/precedes/requires
  from discovered frontmatter onto config-owned names by basename; measured reachable, measured NOT
  a push bypass (global fail-closed leg still denies).
- #249: both halves accounted for (#270 message field, #291 branch-scoped evidence named in deny);
  skill-gate capture log 140 rows, 25 denies, all replay deny->deny. Recurrence watch only.
- brainstorming's second trigger is a bare verb alternation:
  build|create|implement|develop|scaffold|init|bootstrap|introduce|enable|add|make|new|start.
  No record exists of WHICH alternative matched in the 327 trigger-word wrong mandates.
- Transcripts since 2026-10-04: 353 distinct typed user turns (one fresh labelled set's worth).

## Consensus program (all three participants, Codex's top three adapted)
1. Adjudication budget: one fixed owner hour per fortnight, starting today. Label the 15 #343
   episodes (this IS the #295 measurement: pushes allowed on a non-measured verdict). New corpora
   admitted only with a labelling line. Zero code. Evidence: measured-in-repo.
2. #297 consequence marker on the two gating milestones when unmet. Render-only; _DISPLAY_SUPPRESS
   and the state write untouched; flipping pair extending tests/test-activation-progress-truth.sh.
   3-4 h. Evidence: measured defect (a real missed gate).
3. Display cost, display-only: cut routing-block boilerplate, measured by block_chars before/after
   with state byte-identical AND gate decisions identical on replay. 1-2 days. Instrument advisory
   hint display (not recorded today) if retirement of methodology_hints is ever to have a denominator.
   Evidence: block size measured; which lines are cuttable is hypothesis.
4. Compaction pairing canary + continuity re-verification: compare trigger=auto with post_compact
   over 30 days (report no-events as cannot-check); if paired, retire the prompt carrier and its
   stale premise comment. This is the first retirement with evidence already on disk, and the pilot
   for a retirement rule keyed to HARNESS behaviour, not model generation. 0.5 day.
5. #304: refuse role/phase/precedes/requires from discovered frontmatter for config-owned names;
   keep triggers/priority; planted-plugin control in both directions
   (tests/test-adversarial-governance.sh). Last, because measured non-bypass. 0.5-1 day.

## Unresolved (owner decision)
- Brainstorming verb deletion. Critic: right next precision experiment, IF matched-alternative
  attribution is added to the census first and block_chars per prompt is the registered second
  metric; fresh set from the 353 turns; gate-decision replay mandatory (not display-only, un-arms
  chains). Architect: dropped; saves ~70 tokens/prompt averaged vs the block's ~1,200-1,500, and
  changes routing for every installer. Pragmatist: 1.5-2 days code incl. a NEW recorded-input gate
  replay (the 924046cb method is a fixture pair, not a replay), decision possible 2026-10-30.
- #239 dispatch_observed stamp (2 h): architect conditional yes, critic no (predicate advisory,
  labels are the constraint).

## Dropped this window, with reason
- Rec 2 (exists). Rec 4 cross-vendor judge (two-blind-labeller method is the instrument; egress
  cost). Rec 6 risk tiers (decorates a predicate that credits invocation; no REVIEW registration).
  Rec 7 effort/cost hints (plugin cannot set effort; cost already measured; answer is fewer
  invocations). Rec 8 mod migration (availability unestablished; 6.8k lines; portability tests exist).
  Rec 9 (improvement-miner has revival criteria; "park, don't kill" contradicts retirement).
  Rec 10 (no local defect). Rec 3 eval isolation deferred until a non-ceiling fixture set exists;
  record the exposure audit as a precondition in that pre-registration. Rec 5: only a narrow
  consultation-laundering case if a concrete gap is shown. #295 option B (friction, no decision
  change, de-facto deny-flip on two legs). Generation tags on config (no reader). #333 stage A
  labelling (nothing to label). #249 (close or watch).

## Dissenting views kept
- Codex: newsletter claims are not repo evidence; the plugin's own audit outranks every digest item.
  Accepted in full.
- Critic: retirement in an incident-paid repo fails silently (recurrence has no signal); split the
  population: experiments get a sunset at creation (shadow legs already do), incident-paid gotchas
  retire only when their regression test is proven obsolete. Accepted as the retirement rule.
- Critic: the compaction pairing canary must report "no events" as cannot-check, never as paired.

## Out of scope
Any deny-flip (REVIEW or VERIFY) this window. Rebuilding shape-based routing guards. Controls
that read chain of thought. New mandatory process steps or new always-on hints.

## Acceptance scenarios
- GIVEN the #343 corpus WHEN the owner runs --next/--adjudicate on each of the 15 episodes THEN
  --status reports unresolved=0 for that set and the fortnightly read is posted on #343.
- GIVEN a chain whose requesting-code-review step is unmet WHEN the activation hook renders the
  composition THEN the marker for that step states the push will be denied, AND the state file is
  byte-identical to the pre-change render, AND openspec-guard.sh's decision is unchanged.
- GIVEN 30 days of compact events with trigger=auto count equal to post_compact count WHEN the
  canary runs THEN it prints one paired note; GIVEN an empty log THEN it prints cannot-check.
- GIVEN a planted SKILL.md named after a config-owned skill with precedes/requires set WHEN the
  registry builds THEN the config entry's precedes/requires are unchanged and its triggers may
  still be overridden; GIVEN an unowned name THEN all six fields still merge.

## Decision
Pending owner. Recommended: consensus items 1-5 in order; decide the verb-deletion experiment
after the first #343 read, since both compete for the same labelling hour.
