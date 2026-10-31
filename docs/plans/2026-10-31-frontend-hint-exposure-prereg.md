# Frontend guidance: reach, uptake and the named phone check (#412), pre-registration

Status: FROZEN on merge to `main` of the commit that adds it (2026-10-31). The owner approved DRAFT v2 and ruled the
labellers be fresh subagents; the instruments' final review (no Critical, 1 Important, 8 Minor) changed D1 and D2 as
stated there before the freeze. The D3 cutoff is that merge commit's committer time (UTC). v1 was critiqued by Codex (session
01a18a0d-dcbd-7d80-937a-9557a29c7312, round 3: 3 Critical, 5 Important, 1 Minor, all taken; one taken differently,
noted at D7). Frozen by the commit that adds it, with its manifests, on `main` (force-added, as
`docs/plans/2026-10-05-routing-precision-prereg.md` was). Extraction, artifact preparation and renderability checks
may precede the freeze. Subject runs, labelling of the drawn rows and outcome scoring begin only after every
manifest, label rubric, variant and scoring rubric below is frozen.

## Why

Evidence on #412 (issue comment 2026-10-31) and memory `ui-episode-classification-2026-10-30`:

- **Reach is short.** Over 8 real UI episodes (157 typed prompts), the router listed `frontend-design` on 10 prompts
  in 2 episodes; 5 of the 10 already named it.
- **Uptake is short.** On the 5 unnamed UI requests where it was listed, the model invoked it in-turn 0 times.
  `runtime-validation` was named in all 8 episodes and invoked in 0.
- **Precision is low where it fires.** `frontend-quality-rules` rendered on a relevant prompt 1 time in 13
  (2026-10-27); `frontend-playwright` rendered on a no-code article question (2026-10-30).
- **A named checklist works offline; a generic one does not.** Two pre-registered, blind-scored tests: a paragraph
  naming defect classes caught 3/5 and 5/5 of two real owner-caught defects against 0/5 and 0/5 for the control, with
  0 false alarms in 30 runs; a neutral "inspect as a user" paragraph caught 0/5 and 0/5.

## Questions

- **Q1 (lexical reach, offline).** For each of the three hints (`frontend-playwright`, `frontend-quality-rules`,
  `design-seed`) and the `frontend-design` domain route, and for each trigger variant: on real typed prompts, what
  share of UI-work prompts does the trigger MATCH (recall), and what share of its matches are UI work (precision)?
  Lexical matches only: phase eligibility, name boosts, role caps and actual renders are separate, descriptive
  measures, and no routing-reach claim follows from this replay.
- **Q2 (uptake, descriptive).** When `frontend-design` or `runtime-validation` is listed in an observed routing block
  on a UI-work prompt, what happens in that turn? No intervention.
- **Q3 (named phone check, offline).** On independent real defects of the classes the checklist names, does it raise
  detection over control, and does it stay silent on the corrected screens? Unnamed-class detection is exploratory.

## Decisions (owner delegated 2026-10-31; each is the author's call, open to override before the freeze)

- **D1. Q1 qualification (recall primary, precision floor).** Per route, a variant qualifies when either
  (A) Δrecall ≥ 0.15 and Δprecision ≥ 0, or (B) Δprecision > 0 and Δrecall ≥ −0.05, both against V0 on the same
  rows. Rank qualifying variants by recall, then precision, then V1 before V2. An undefined denominator (no UI-work
  rows, or no matches) is cannot-check. A branch that is mathematically unreachable (e.g. V0 recall > 0.85 for (A))
  is reported as such and scored as failing, so it cannot leave the verdict inconclusive. Qualification nominates a prospective test; it does not authorize adopting any trigger.
  Reason for recall-primary: the measured failures are reach and uptake; a misfire costs context, a missing skill
  costs the work.
- **D2. Labels define UI work.** A prompt is UI work when acting on it would create or change what a person sees or
  does on a screen (layout, visual design, copy shown in an interface, interaction, a rendered page or mockup).
  Article discussions, routing or plugin work about frontend skills, and backend work in a UI repo are NOT UI work
  unless the prompt asks for a screen change. Labels come from the rubric frozen below (`## Rubric (frozen)`). The two
  blind labellers are fresh headless `claude -p` runs in an isolated HOME (owner's ruling, 2026-10-31: "use fresh
  subagents as labellers"): L1 on `claude-opus-5-5`, L2 on `claude-sonnet-5-5` (author's call: two models reduce
  correlated error). Each sees only the rubric and the rows (id and prompt text), never the stratum, route, match or
  weight, and has no tools. The owner labels only the rows where L1 and L2 disagree; that is exactly the 2-of-3
  majority, since the owner's vote cannot change a row on which the other two agree. The owner labels from a worksheet
  holding only each such row's id and prompt (`score.py --worksheet`), blind to stratum, routes, weights and the two
  votes. A malformed or missing labeller answer is re-asked once, alone, then treated as a disagreement. A labeller
  RUN that fails (non-zero exit, timeout, unparseable output, `is_error`) answers nothing; a row left FAILED makes the
  harness exit 4, and that labeller is rerun before any adjudication, so an outage never turns 2-of-3 into
  owner-plus-one. Any row still unresolved: Q1 is cannot-check, never a
  guess. Prompt text reaches the labellers through the same model API every session already uses, and is written
  only outside any repository.
- **D3. Corpus and weighting.** Freeze before drawing: the transcript manifest (paths and sizes), UTC cutoff (the
  freeze commit's time), extractor revision, sort order and random seed. Seeds: 412 for the stratum B draw, the
  bootstrap and each labeller's batch shuffle. Instruments: `tests/probes/hint-exposure/` (`draw.py`, `label.py`,
  `q1.sh`, `score.py`) at the freeze commit; the manifest's sha256 is posted on #412, never the manifest (it lists
  transcript paths). Typed prompts by the census definition, from
  top-level transcripts with `.bak` copies merged and deduplicated by session id and entry uuid (`census.py
  --include-bak` semantics), 2026-09-14 to the cutoff, all projects. Stratum A: every prompt on which any of the four
  routes rendered in an observed block. Stratum B: the remaining prompts; N_B = its size, n_B = min(300, N_B), drawn
  uniformly with the frozen seed. Weights: 1 in A, N_B/n_B in B. For every route × variant:
  precision = Σ w·UI·match / Σ w·match; recall = Σ w·UI·match / Σ w·UI. Report raw stratum counts, and results for
  prompts that name the skill separately from those that do not (a prompt names it when it contains `frontend-design`
  or `frontend design`, case-insensitive; the hints have no user-facing name, so the same rule splits every route).
  Stratum A membership comes from the prompt's own paired block: `frontend-design` on its verdict line, or a hint's
  leading label (every label each hint carried since 2026-09-14, frozen in the drawer as `HINT_LABELS`). Uncertainty: a stratified bootstrap (2,000
  resamples, frozen seed) over both strata; if the 95% interval for a D1 quantity spans both passing and failing,
  that quantity is inconclusive: a condition `Δ ≥ t` passes when the interval's lower bound is ≥ t, fails when its
  upper bound is < t, and is otherwise inconclusive (strict `>` likewise); a branch is the AND of its conditions and a
  variant qualifies on the OR of its branches, both three-valued. V0 and the variant are evaluated on the same
  resample. A resample in which a quantity is undefined is dropped and counted; above 5% dropped, that quantity is
  inconclusive. Zero sampled misses is not proof of full recall. No sample extension after outcomes
  are seen. Prompt text never leaves a non-repo path (the replay probe's privacy rules); results are counts.
- **D4. Variants are complete trigger arrays, frozen before labelling.** An appendix written before the freeze holds,
  for each route × variant (V0 current, V1 narrowed, V2 = V1 plus screen-shaped phrases), the complete trigger array
  as it would appear in `config/default-triggers.json`, the baseline commit, and the matcher (the hook's own matching,
  as `tests/probes/real-prompt-replay/replay.sh` applies it). Non-trigger fields are unchanged. Intent, to be made
  exact in the appendix: V1 removes single-word alternatives that matched non-UI prompts in the 2026-10-27 audit
  (`style`, `page`, `card`, `tab`, `dashboards?`); V2 adds `screen`, `layout`, `looks?`, `mock-?ups?`, `ui`, `ux`,
  `on (a|the) phone`, `mobile` where absent. The appendix is `docs/plans/2026-10-31-frontend-hint-variants.json`,
  frozen in the same commit. A variant equal to V0 is reported as identical, not scored. Nothing may be edited after
  labels exist.
- **D5. Q3 fixtures are independent of the checklist.** Every defect and episode consulted when authoring or revising
  the checklist is excluded: the 8 episodes of 2026-10-30 (five sessions of project P1: 2be82c78, 46048393, 62bf256e,
  56f2a129, 87db4504; two of P2: 2d625a35, 8f8006c3; one of P3: 7154a16f) and both test fixtures. Projects are
  aliased in every committed file; the alias key stays local. Before the freeze, a manifest enumerates the exact test
  fixtures: project alias, pre-fix and corrected commits, build command, capture spec, artifact hashes, the class each
  represents, and its hit rubric. No alternatives remain in it. Where to look: real owner-reported UI defects in
  sessions not among the 8 (for example a fourth project's coaching feature), or new defects that arise after the
  freeze. Each fixture must render and visibly show its defect before it is listed; a
  failed candidate is recorded and not listed. Fewer than two independent NAMED-class fixtures: Q3 is cannot-check.
  An UNNAMED-class fixture, if listed, is exploratory (detection reported), and a desktop one is a descriptive
  off-target check, not evidence of phone-class specificity.
- **D6. Q3 rule.** Each fixture × state (pre-fix, corrected) × arm (control, checklist) has 5 runs. The checklist
  passes screening when, on EVERY named-class fixture, checklist hits − control hits ≥ 2, AND the checklist raises
  zero false alarms on each corrected fixture. A control at 4 or 5 of 5 on a fixture (ceiling) or a missing required
  fixture makes the result inconclusive; nothing is dropped from the conjunction. These are screening criteria, not
  significance or non-inferiority claims. No Q3 result authorizes shipping text; a pass nominates the checklist for a
  prospective in-session test.
- **D7. Harness manifest (frozen).** Model id and CLI version, settings, the exact arm prompts, hashes of the hint
  text, the frontend-design SKILL.md and each design excerpt, allowed tools (Read only), viewport and capture spec,
  artifact paths, randomized run order with seed, and the per-fixture hit and false-alarm rubric. Subjects run in an
  isolated HOME with no access to this registration, answer keys or prior results. Outputs are scored anonymized
  (arm labels and treatment phrases masked) before arms are revealed. Taken differently from the critique: instead of
  supplying identical DOM measurements to both arms, the checklist under test no longer asks the subject to measure
  horizontal overflow, which a screenshot-only subject cannot do; overflow belongs to an automated check, outside
  this test.
- **D8. Q2 is descriptive.** Observed `UserPromptSubmit` blocks paired by `parentUuid` only (never replayed
  exposures; compaction resumes are not typed prompts). Per listed skill on a UI-work prompt, classify the turn:
  already loaded earlier in the session, invoked in-turn, invoked later, validation done directly without the skill
  (screenshots or browser runs), or unknown. "Directly" means an in-turn tool call whose name contains `browser`,
  `chrome` or `playwright`, or an in-turn Bash command matching `playwright|screenshot|chromium|headless`. The turn
  boundary is the census's. Q2 counts are over labelled rows: a prompt listing `runtime-validation` with no frontend
  route rendered sits in stratum B and is only sampled. Absence of an invocation does not establish absence of the
  behaviour.

## Rubric (frozen)

`label.py` sends the text between the two `RUBRIC` fences below, verbatim, followed by a blank line and one batch of
rows, each `<id><TAB><prompt>` with tabs and newlines in the prompt replaced by spaces.

<!-- RUBRIC-BEGIN -->
You are labelling messages that a software developer typed to a coding assistant. For each message, decide one thing:
would acting on this message create or change what a person sees or does on a screen?

Answer UI when the message asks for, or is a step of, work on an interface: layout, visual design, styling, the copy
shown on a screen, an interaction (a button, a form, a gesture), a rendered page, a screen, or a mockup of one. A
follow-up inside such work counts ("make it smaller", "now do the same for the settings tab") when the message itself
asks for a change someone would see.

Answer NOT for everything else, including: discussing an article or a tool about frontend design without asking for a
screen change; work on routing, plugins, skills or prompts that are about frontend work; backend, data, test or build
work in a project that has a user interface, unless the message asks for a change on the screen; questions, approvals
and short replies ("yes", "proceed", "merge it") that do not themselves ask for a visible change.

Judge only the message. Do not guess at context you cannot see; if the message alone does not ask for a visible change,
answer NOT.

Examples (invented, not from the messages you will label):
- "the pricing cards wrap badly on a phone, stack them and shrink the headings" -> UI
- "add a dark mode toggle to the header" -> UI
- "the empty state on the inbox screen should say what to do next" -> UI
- "read this article about design systems and tell me what you think" -> NOT
- "the frontend skill keeps triggering on backend prompts, tighten its regex" -> NOT
- "add an index on orders.created_at, the dashboard query is slow" -> NOT

Reply with exactly one line per message, in the order given, each `<id><TAB>UI` or `<id><TAB>NOT`, and nothing else.
<!-- RUBRIC-END -->

## The checklist under test (frozen with this document)

> PHONE CHECK: look at the screens as a person would scroll them on a phone. State how many screens the page takes
> and how many separate jobs it asks of the user; say whether its main job is done within the first screen and
> whether anything further down belongs on another tab or behind a tap. Check that every image, thumbnail and line of
> text is legible at its rendered size and that no word or figure is stranded on its own line. Matching the design is
> necessary but not sufficient: a screen that matches its design can still be crowded or illegible, and you should
> say so when it is.

Named classes: crowding (screens and jobs), legibility at rendered size, stranded words or figures.

## Out of scope

Changing any shipped hint, trigger or skill text; an uptake intervention; a rendered-output aesthetic trial (#298's
instrument problem is unsolved); the census (#420, A2); automated overflow measurement.

## Known limits, stated before the data

One owner, who names skills often, so recall on unnamed UI requests rests on a small stratum. Q1 is lexical, not
routing. Q3 has n = 5 per cell on few fixtures: a screening read, never an estimate. Independent fixtures may not
exist yet, in which case Q3 waits for new defects rather than reusing consulted ones.

## Built before the freeze

1. The label rubric (D2, above) and the variant appendix (D4, `docs/plans/2026-10-31-frontend-hint-variants.json`).
2. `replay.sh` replays methodology hints as the hook's hint loop matches them, takes `--config`, and writes
   per-record hits (`tests/test-real-prompt-replay.sh`, cells H1-H5).
3. `tests/probes/hint-exposure/`: the corpus drawer, the labeller harness, the Q1 orchestration and the scorer
   (`tests/test-hint-exposure-probe.sh`; run order in its README).
4. The Q3 fixture search and manifest (D5, D7): `docs/plans/2026-10-31-frontend-hint-q3-manifest.md`.
