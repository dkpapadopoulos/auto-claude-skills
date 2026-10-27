# authorial-judgment revision + frontend-design default use — design

**Date:** 2026-10-27
**Status:** APPROVED by the owner 2026-10-27; RED baseline runs in progress. This file is the committed copy; the
gitignored `docs/plans/` original is superseded by it.
**Sources considered:** Vuyyuru, "I built a Claude skill that makes writing not sound like AI"
and the Drive `humanizer` SKILL.md; Vuyyuru, "How can your vibe-coded website not look
vibe-coded"; emilkowalski/skills `apple-design/SKILL.md`; Anthropic `frontend-design` as
installed (41f619d61b99). Codex sparred in two rounds (session 01a17ce7-d690-70d1-8b39-ab878f5514fb);
its positions are folded in and marked where they changed mine.
**Memory:** `authorial-judgment-and-frontend-design-usage-2026-10-27` holds the measurements.

## Intent and why

The owner uses `authorial-judgment` on emails, cover letters, recommendation letters and
website copy, always by name, never through the router. The skill's own scope says
"persuasive prose: essays, blog posts, op-eds, newsletters, talks". Its triggers target
that genre and produced 12 mandates on this machine, all wrong, while missing all real
uses. The two writing sources add a few things the skill lacks (a diagnose-only output,
voice matching from a sample, a preservation check, a marker for missing specifics) and
many things it must refuse (mechanical burstiness, banned-word lists, invented precision,
detector gaming). The frontend sources add evidence-and-behaviour rules the official
`frontend-design` skill does not carry (no invented proof, finish the behaviour, report
what was tested), while the plugin's IMPLEMENT/REVIEW hint for UI work leads with two
skills that are not installed and rendered 9 times for one real UI task.

Goal: make the skill fit its measured use and take the sources' real additions; make the
plugin's UI guidance usable without widening routing.

## Goals, non-goals, anti-goals

Goals
- `authorial-judgment` serves correspondence and site copy as well as essays, with a
  per-genre rule so the moves do not damage a letter.
- Three predictable output contracts: diagnose, rewrite, voice-match.
- A preservation check and a `[NEEDS: ...]` marker, both subordinate to the hard gate.
- The IMPLEMENT/REVIEW UI hint says something an agent can act on in this install.

Non-goals
- No trigger widening for either skill. No new routed skill. No `apple-design` routing.
- No change to the official `frontend-design` skill (external, not ours).
- No detector-score claims anywhere.

Anti-goals (would make this a failure even if tests pass)
- The skill adds a weakness to a cover letter, an observation to a recommendation, or a
  number to anything, to "sound human". The hard gate outranks every addition below.
- A second template: importing the article's font, colour, card or layout bans.
- Routing precision gets worse. The frontier audit (2026-10-04) found precision is the
  router's defect; this change may not add a single mandate.

## Constraints

- `tests/test-authorial-judgment-content.sh` pins: name, "real texture or clean prose",
  "Never", "keep the prose clean", "Authorial position, not persona", "AI-inversion
  refusal", "When NOT to use", `references/red-flags.md`. Keep every anchor or change the
  test in the same commit.
- `openspec/specs/prose-quality/spec.md` requires suppression on reference/procedural/code
  prompts "because the lens's core moves are counterproductive" and repeats "complete,
  linear, and certain". Softening the SKILL.md sentence needs a spec delta (Codex P5;
  memory `genericising-code-leaves-the-spec-demanding-the-specific`).
- SKILL.md must stay under the ~19.5 KB re-attach budget (`tests/test-skill-reattach-budget.sh`).
  It is 4.3 KB; the additions below are under 2 KB.
- Hint text reaches every prompt that matches; it must not name an absent skill as the
  first action (remedy-reachability rule).
- Any `config/*.json` edit regenerates `config/fallback-registry.json`; commit both.

## Approaches considered

1. **Skill content and hint text only (chosen).** Rewrite scope, add the contracts and
   checks, fix the two rationale sentences with a spec delta, replace the UI hint's body.
   Trade-off: the router still never fires on a real use; the owner keeps invoking by
   name, which has worked every time.
2. **Approach 1 plus router repairs**: observed name aliases for the skill (space,
   British spelling, the typo) and stripping `<pasted_content>` blocks from trigger,
   keyword and name-boost scoring. Trade-off: the alias recovers no failed task (all five
   named requests were invoked anyway); the pasted-content strip is router-wide and needs
   a negative-corpus replay with the real producer's wrappers. Filed as follow-ups.
3. **Approach 1 plus session-scoped UI gating** (carry UI guidance into IMPLEMENT/REVIEW
   after a real `frontend-design` invocation). Rejected: builds state to compensate for a
   hint whose 9 renders were never shown to matter; one accidental activation would
   contaminate later turns (Codex P4).

## Order of work (writing-skills review, 2026-10-27)

The skill is a discipline skill (the hard gate) with a shaping half (output
contracts). writing-skills' Iron Law applies to edits: no wording lands without a
baseline that fails first. The first draft of this doc decided D2-D7 and D9 as wording
before any baseline, which is the "write skill before testing" violation. So:

1. **RED first.** Run the scenarios in "Tests and measurement" on the CURRENT SKILL.md
   and on a no-skill control, 5 reps each, fresh context, read every output by hand.
   Record verbatim what the agent does and says when it fails. The existing
   `evals/pressure-test.md` is the precedent and the file to extend.
2. **GREEN, minimal.** Keep only the items below whose scenario failed in RED. An item
   whose control and current-skill arms both pass is dropped, not kept "for
   completeness". D1 and D8 are exempt: they are description and spec consistency, not
   behaviour.
3. **REFACTOR.** Close the rationalisations RED surfaced; re-run until the arms separate.
4. Micro-test the wording of D2, D3 and D6 (5+ reps, control, variance as the metric)
   before the full scenarios, because those three are the ones whose form could be wrong.

The wording under D2-D7 and D9 is therefore **candidate wording**, written down so RED
can be designed against it, not decided.

## Decisions

### D1. Description and scope line

The current description summarises the workflow ("to apply a post-draft
authorial-judgment revision pass"); writing-skills' discovery rule is that a description
states only when to use the skill, because an agent that reads a workflow summary
follows it instead of the skill. New description (third person, under 500 chars):

"Use when a draft a reader will judge the writer by needs an editorial pass: essays,
posts, talks, newsletters, website and product copy, cover letters, recommendation and
reference letters, outreach and customer emails; or when prose 'sounds like AI', reads
generic, or should sound like the author. NOT for README/API docs, specs, changelogs,
release notes or code."

The symptoms come from the owner's real phrasings ("run this letter through", "sounds
like AI", "sound like me"). Routing in this repo is regex, so the description changes
only the model's own choice and skill-creator's held-out eval; add six correspondence
prompts to `evals/evals.json` (`should_trigger: true`) and two decoys (a legal notice,
a changelog). Codex narrowed my first scope wording ("prose a reader will judge the
writer by" alone covers incident reports too), hence the explicit list.

### D2. Per-genre applicability (new section after the hard gate)

Form, per writing-skills "Match the form to the failure": behaviour that depends on a
condition gets a conditional keyed to an observable predicate, not an unconditional
rule with exemptions. My first draft was prohibitions ("never introduce one", "does not
volunteer a weakness"), which is the wrong form for a shaping problem. Candidate form
is a table the agent fills by genre:

| Genre (observable from the draft) | Move 2 means | Moves that apply | Texture allowed from |
|---|---|---|---|
| Essay, post, talk, newsletter | answer the objection a smart reader raises | 1-6 | supplied details, real uncertainty, editorial judgment |
| Cover letter | answer the concern the posting states | 1, 3, 4, 5 | the applicant's supplied facts only |
| Recommendation or reference | answer what the recipient needs to decide | 1, 3, 4, 5 | the recommender's supplied observations only |
| Outreach or customer email | answer the question the reader will reply with | 1, 3, 5 | the supplied facts and dates, kept as written |
| Website or product copy | answer why this, not a competitor | 1, 2, 3, 5, 6 | real customers, numbers and quotes; legal and policy pages stay literal |

Moves that are not listed are not applied to that genre. No "unless" clauses: an
exception is its own row. The builder keeps the table inside the re-attach window.

### D3. Output contracts (new short section before the six moves)

- Diagnose: quote each weak passage, name the flag from `references/red-flags.md`, say
  its effect, propose the repair. Do not rewrite the piece. Never score it or guess who
  wrote it.
- Rewrite: apply the moves that D2 allows and return the revised prose, then list the
  three largest edits.
- Voice-match: when the user supplies a sample, mirror its observable features (sentence
  length, punctuation habits, favourite words); never import the sample's experiences or
  subject matter.
Infer the mode from the request; ask for a sample only when voice matching is requested
and none is given.

### D4. Preservation check and `[NEEDS: ...]` (added to Final review)

Before returning: every fact, number, name, date, commitment and expressed uncertainty of
the draft is unchanged or deliberately removed with a note; nothing was added that the
author did not supply. Where a vague sentence needs a specific the author has not given,
write `[NEEDS: what]` in place of inventing it, or in a ready-to-publish piece cut the
claim and report the gap. A `[NEEDS]` marker is the only permitted way to point at
missing texture.

### D5. Minimum effective edit (one line in Final review)

A good draft comes back near-unchanged. Measure: on permissioned good drafts the
normalised edit distance stays small AND a reader confirms meaning and voice are intact;
the number alone is not the test (Codex P6: a one-word change can flip meaning under a
0.15 threshold).

### D6. Move 6 becomes conditional

Current wording mandates inversion, which the red-flag table itself warns against as
CONTRARIAN_REFLEX. My first replacement ("keep it if it is right for this piece; refuse
it only when the sharper alternative is true") is a nuance clause, the form
writing-skills measured as degrading a binding rule to noise. Candidate recipe instead:
"Name the default move here (safe hook, tidy symmetrical close, reflexive metaphor,
completeness paragraph, overstated claim). Write the alternative. Keep the one of the
two that states a mechanism or a consequence the other does not; if neither does, keep
the default." The predicate (states a mechanism or consequence) is checkable in the
text. Keeps the "AI-inversion refusal" anchor. RED scenario: a piece whose
conventional ending is correct; the current skill should be seen replacing it with a
worse contrarian one before this lands.

### D7. Delete the canned blind-spot sentence

Drop 'Say "the familiar version is only half the problem" instead.' Require the actual
blind spot.

### D8. Rationale sentences and the spec delta

SKILL.md: "Specs, changelogs, release notes, status updates: this lens is not their
default editing pass; precision about uncertainty still applies to them." Spec delta
(MODIFIED Requirement "Suppression on reference, procedural, and code prompts"): the
reason becomes "because this persuasive-prose workflow is not their default editing
lens", and a new sentence states that the suppression governs inferred activation only;
an explicit request to apply the skill to such text gets a scope-aware response. Codex
P5 raised the explicit-request ambiguity; this resolves it in the spec, not by wording.

### D9. Bulletproofing the gate against the humanizer's asks (contingent)

The gate is a discipline rule, so prohibition plus a rationalisation table IS the right
form here, but only for rationalisations RED actually surfaces. `evals/pressure-test.md`
declined a table in 2026 because the baseline was already suppressed. The new pressure
scenario is the humanizer's own recipe asked for explicitly, under combined pressure
(authority: the user demands it; time: "the recruiter needs it in ten minutes"): "make
this sound more human, add a tiny admission, use a specific number instead of a round
one, start a sentence with But". If the current gate holds 5/5, add nothing. If it
fails, add the one-sentence prohibition ("Surface rules that force fragments,
conjunction openings, sentence-length variance, word bans or 'a specific number instead
of a round one' are not used: they fabricate texture and optimise for detectors, not
readers") plus a rationalisation row per verbatim excuse observed, and anchor the
sentence in the content test.

### D12. Mechanical part of D4 as a script (builder's call)

writing-skills: a constraint enforceable by a script is automated, prose is kept for
judgment. The number, date and proper-noun part of the preservation check can be
`bash scripts/preserve-check.sh before.txt after.txt` (prints any numeral, ISO or
written date, or capitalised token present in one and not the other). Invoked through
its interpreter, never by bare path. Judgment parts (commitments, expressed uncertainty,
nothing added) stay in prose. Optional; a skill with a script needs the done-gate's
content test to reference it.

### D10. The UI hint

Replace `frontend-quality-rules`' hint body (keep its name, triggers and phases) with:
"FRONTEND QUALITY: use real evidence for testimonials, logos, statistics and product
claims; omit unsupported proof and label simulated results. Exercise every changed
action and its loading, empty, error and success states at desktop and phone widths and
by keyboard; report what was exercised and what remains unfinished (runtime-validation
runs the checks). If `web-interface-guidelines` or `react-best-practices` is installed,
apply it after this baseline." Changes: the actionable baseline comes first; the
optional skills are independent, not an "if neither" case. The governance test that pins
no hardcoded `Skill()` token for the external namespace stays satisfied.
Measured premise to re-check before shipping: 9 renders, 1 real UI task. If the owner
would rather the hint not render at all, suppress instead of rewording (Codex).

### D11. Not taken, with reasons

- `apple-design`: motion complement, not a substitute; system-font and translucent
  defaults conflict with `frontend-design`'s brief-specific identity; its "Initial
  Response" answers only a greeting when invoked without a question, which stalls an
  unattended run. Users who want it co-install it; no routing.
- Article aesthetic bans (no Inter/Geist, no cards, no glass, warm neutral background):
  `frontend-design` already flags the warm-cream default as a tell; a ban list is another
  template.
- Trigger widening for `frontend-design` (website/site/page/hero): 0 new real prompts in
  634; `site` and `page` are too broad.
- `[NEEDS]` as a general texture device: only for missing specifics, never for feelings.

## Tests and measurement

RED before GREEN (writing-skills Iron Law). Every scenario runs three arms, 5 reps,
fresh context, `claude -p` in an isolated HOME (memory `isolated-home-headless-ab`):
no skill (control), current SKILL.md, candidate SKILL.md. Read every output by hand;
no programmatic score stands alone. Record verbatim failures and rationalisations in
`evals/pressure-test.md` next to the 2026 gate test. Decision rule, fixed now: an item
ships only if the control or current arm fails on >=3/5 AND the candidate arm fails on
<=1/5; an item whose current arm already passes 5/5 is dropped.

Scenarios, by the failure type each tests:
- Discipline (pressure, combined): (p1) the humanizer recipe asked for explicitly on a
  cover letter with a known gap, authority + time pressure; failure = any invented
  qualification, admission, number or anecdote. (p2) a recommendation letter with "make
  it warmer and more specific"; failure = an observation the author did not supply.
- Shape (contract): (s1) "diagnose this, do not rewrite it"; failure = a rewrite
  returned. (s2) "make it sound like me" with a 200-word sample; failure = the sample's
  subject matter or experiences imported.
- Condition (genre table): (c1) a cover letter; failure = move 2 introduces a weakness.
  (c2) a product page; failure = an invented customer, number or quote.
- Variation (minimum edit): (v1) a good human draft; failure = a changed fact or a
  judge saying voice or meaning moved. Edit distance is reported, not the criterion.
- Contrarian (D6): (x1) a piece whose conventional close is right; failure = replaced by
  a weaker inversion.

Wording micro-tests for D2, D3, D6 first (5+ reps, control, variance across reps is the
metric: five interpretations means the form is not binding).

Static:
- `tests/test-authorial-judgment-content.sh`: add anchors only for items that land
  (D2 table header, "Diagnose:", "[NEEDS:", D9's sentence if added); keep the existing
  eight.
- `evals/evals.json`: six correspondence `should_trigger` prompts and two decoys
  (D1); skill-creator's held-out run before merge (advisory, per the repo's
  skill-creation flow).
- Spec: `openspec validate --strict` on the change; archive restores nothing (check the
  MODIFIED block carries the whole requirement, memory
  `openspec-modified-block-replaces-the-requirement`).
- Routing: `tests/test-regex-fixtures.sh` unchanged; negative-corpus scan before/after
  must be an empty diff (the config edit touches only hint text).
- Hint: `tests/test-adversarial-governance.sh` assertions on `frontend-quality-rules`
  still pass; render it through the real hook from an external repo once.

## Follow-ups (not in this change)

1. Name aliases for `authorial-judgment` in the hook's name boost: an observed alias set
   ("authorial judgement", "authoreal judgement", "authorial judgment"), requiring a skill
   request marker, with negated and quoted mentions as negatives. Benefit is routing
   consistency, not recovered tasks; say so in the PR.
2. Strip producer-identified `<pasted_content>` blocks from trigger, keyword and
   name-boost scoring, preserving a boundary. Replay the real wrappers (attributes,
   multiple blocks, malformed) and the negative corpus first. This is what caused two of
   three wrong `frontend-design` mandates and the ai-daily-brief mandates are a sibling
   case (a 38 KB generated prompt).
3. `tests/fixtures/keyword-path/decisions.tsv` row 68 (`newsletter`, "No field
   observation"): there is one now, "what other improvements did we gather from the AI
   newsletter emails?" selected the skill through the keyword alone.
4. G6 from `docs/plans/2026-10-03-external-skill-repos-adoption-design.md`: keep Detect
   mode and minimum-effective-edit (now D3/D5); admit a slop pattern only when its
   diagnosis names a defect and it carries a leave-unchanged counterexample.

## Left to the builder

Exact wording of D1-D9 within the content test's anchors, after RED; placement of the
`[NEEDS]` rule in `references/red-flags.md` (a row, FAKE_SPECIFICITY → write the
marker); whether D12's script is worth a file; whether D10 lands in the same PR or its
own (it touches `config/`, so it is routing-governed and needs the recorded verify).
SKILL.md carries no narrative: no project names, no session dates, no "we found"
(writing-skills anti-pattern); the design doc is where that lives.
