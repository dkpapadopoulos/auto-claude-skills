# Design: design seed capability

## Architecture

Three artifacts, one boundary, no new routing surface.

```
plugin (this repo)                      target project (e.g. Dion)
──────────────────────────              ─────────────────────────────
assets/design-seed/       ──copy──►     design/
  presets/<name>/                         tokens.json   (owned, edited)
    tokens.json                           tokens.css    (owned, edited)
    tokens.css                            styleguide.md (owned, edited)
  styleguide.md                           reference.html(owned, edited)
  reference.html                          checks/*.sh   (owned, run in CI)
  checks/token-lint.sh
  checks/identity-pass.sh
docs/design-seed-method.md ──read──►    the method (stays in the plugin)
config/*.json  (one DESIGN hint pointing at both)
```

**The copy is one-way and unconditional.** After it, the project owns every
file. The plugin never reads them at runtime, never rewrites them, and holds no
upgrade mechanism in this change (a later diff-and-offer is possible; a silent
overwrite is not).

**Why a copied template rather than generated content.** A generated token set
has no taste floor — it is exactly the invented-defaults failure the capability
exists to prevent. Copy-then-adapt gives a floor immediately and still produces
a project-owned artifact after the identity pass.

**Why `tokens.json` is the load-bearing file.** It is a finite enumeration, so a
lint can decide membership. `styleguide.md` cannot be checked by a machine, so
it is capped at what the lint cannot express. Prose that restates the lint is
deleted, not written.

**Why one static `reference.html`.** Concrete markup changes model output more
than rules do. Making it framework-free removes the rot argument entirely: it
depends on nothing that ships a major version.

## Decisions & Trade-offs

**D1 — No new skill; reach via a DESIGN hint.** Selection is role-capped (1
process, 2 domain, 1 workflow) and DESIGN already spends both domain slots on
`frontend-design` and `prototype-lab`. A new domain skill would *displace* an
incumbent, and the repo's gates (`test-fixture-coverage.sh`,
`test-skill-content-coverage.sh`) are presence checks that cannot detect
eviction. Worse, `frontend-design`'s trigger already contains `style`, so a
`styleguide` regex collides by construction. A hint renders whenever DESIGN is
active regardless of which domain skills win — strictly broader reach than a
skill that must beat two incumbents — at zero displacement risk. *Rejected:*
adding the skill now behind a ~3h displacement baseline (negative corpus plus a
positive set, measured against the real installed registry). Deferred, not
refused: if the pilot shows the hint is insufficient, that measurement is the
precondition for adding it.

**D2 — No identity check; record provenance instead.** *Reversed after the
cross-family critique, which is the strongest argument in this document.* A
byte-diff establishes whether values changed, never whether the result has an
identity, and `--strict` inverts the goal: it penalises a project that
legitimately adopts the shipped default and rewards an arbitrary edit. Since
"benefit immediately" means the default must be usable **as-is**, a check that
fails on using it as-is is self-defeating. Adoption therefore writes
`design/adopted.json` (preset name, version, date). If distinctiveness matters
for a given project, the thing to evaluate is the rendered result against that
project's brief — not the bytes of a token file.

**D2a — Adoption edits the project's own agent instructions.** A hint proves
visibility, not adoption: implementation may never consult a copied file. The
copy procedure therefore adds one pointer line to the project's CLAUDE.md /
AGENTS.md telling implementation to read `design/styleguide.md` and run
`design/checks/token-lint.sh`. The plugin still never reads those files.

**D3 — The `DesignSync` bridge is cut.** It is unavailable in the author's
environment and to an unknown fraction of users, and its degraded form ("write a
markdown file") is not worth a skill. The method documents the local lane as the
primary lane, not the fallback.

**D1a — The hint's trigger was measured against the negative corpus before widening.**
The repo's standing lesson is that four trigger widenings measured clean and shipped
defects, and only the fifth — which baselined negatives first — was clean. So: plurals
were added (`screens?`, `components?`, `dashboards?`, …) after a reviewer measured that
the singular-only form missed "build the React components", "design the screens",
"update our design tokens", "polish the dashboards", "add wireframes". Re-measured over
`tests/probes/negative-corpus/negatives.txt` (224 prompts): **6 fire, and 5 of them are
genuinely frontend work** ("panel component", "review ui", "settings screen") — true
positives for this hint even though they are negatives for the consultation skills the
corpus was built for. The **one** real false positive is "is my entity component setup
overengineered" (ECS jargon, not UI). 1/224 noise, no displacement possible, accepted.

**D4 — Lint diagnostics carry stable IDs (`TL-<n>`); prose rules do not.**
Diagnostic IDs give stable, greppable failures. Numbering prose rules and
asserting "coverage" over them would measure id-uniqueness, never behaviour —
an assertion that looks like a gate and proves nothing. Prose gets an ID only
when something references it.

**D5 — Evidence must fit the claim; there is no round quota.** A screenshot is
observation, a check is bounded evidence, another model is another opinion, and
they are not interchangeable. The method asks for evidence relevant to the
improvement being claimed, and drops the "every round needs external signal"
ritual as unfalsifiable ceremony.

**D7 — The lint enforces token REFERENCES, over a declared file set.** The
ambiguity that would otherwise sink it: is a raw literal acceptable when its
value matches a token? If yes, code bypasses `var()` and stops responding to
theme changes, so finiteness enforces nothing; the real property is reference
usage. The lint therefore requires `var(--token)` for the properties it names,
over an explicit file set, with documented exceptions (comments, media-query
conditions, `calc()` operands, non-style numerics). Its coverage boundary is
declared in `styleguide.md` and in `--help`. It does not claim general
enforcement, and a shell scanner on Bash 3.2 is not a CSS parser.

**D6 — Generation and comparison stay separate.** Variant generation belongs to
the method's explore step; comparison belongs to `prototype-lab`. One artifact
doing both is how a comparison quietly becomes an advocacy document.

**D8 — The pilot's treatment is the whole FIRST-USE WORKFLOW, not "the seed".**
Arm S receives a seed *plus* a mandatory adaptation exercise, a staged
freeze, and an obligation to record its reasoning. Those are not separable
within one pair, so no result here can isolate the seed's own contribution.
Naming the treatment this way is what makes an arm-S **loss** interpretable
rather than ambiguous — otherwise a loss could equally mean the seed is bad,
adaptation cost too much budget, or the process obligations crowded out
implementation. *Rejected:* framing the treatment as "the seed" and reporting a
win as evidence for the tokens. That is the specific overclaim this
pre-registration exists to prevent.

## Cross-family critique (Codex, 2026-09-18) — what it changed

Sent read-only through `scripts/consult-dispatch.sh` under user consent; the
raw answer is session scratch. Four of its five findings were adopted:

- **The pilot cannot validate the visual default.** A Python/DuckDB CLI teaches
  numeric display and missing-value semantics; it cannot validate tokens,
  density, typography or a reference page. Adopted: a separate frontend
  acceptance fixture (`tests/fixtures/design-seed/sample-project/`), and the
  stack recommendation is cut from this change.
- **`identity-pass.sh` is a fig leaf and `--strict` is backwards.** Adopted in
  full — see D2. This reverses the position this session had recommended and
  both local reviewers had endorsed in stronger form.
- **The lint's real property is reference usage, not finiteness.** Adopted — D7.
- **Cut independent maintenance of JSON and CSS; cut elevation/motion until
  used; cut extra presets; cut prose-rule IDs; cut the round quota.** Adopted —
  parity test, D4, D5, one default preset.
- **Rejected:** its claim that "n=1 licenses the method, not the default" should
  itself be dropped. The critique is right that one pilot establishes neither,
  but the sentence is a limit on what may be *claimed*, not a claim, and the
  repo's habit is to state such limits explicitly rather than leave them
  implied.

## Dissenting views

- **Critic (unresolved, recorded):** a shipped default "industrialises one house
  style" across every consumer, which is worse than per-project drift. Mitigated
  but not eliminated by presets-to-pick plus the identity pass; the residual risk
  is accepted and re-examined after the pilot.
- **Critic (upheld as a condition):** a pilot of n=1 licenses promoting the
  *method*, never the *default*. Recorded in the acceptance criteria.
- **Architect (conceded, recorded):** wanted a full Vite/React/shadcn reference
  app; conceded on rot and on the hidden cost of standing up Node in a uv-only
  repo. The static page is the surviving residue of that argument.
- **Pragmatist (partially accepted):** wanted `reference.html` cut entirely and
  the pilot's own screen to become the reference. Rejected for the first project,
  which by definition has no screen yet; accepted thereafter — the method tells a
  project to replace the shipped reference with its own once one exists.

## Lethal-trifecta classification (DESIGN gate)

- `private_data`: **Present** — a target project may hold private data (Dion
  does). The design ships synthetic, frozen fixtures only; no browser path
  reaches a live database.
- `untrusted_input`: **Absent** — nothing external is ingested.
- `outbound_action`: **Absent in this slice** — the design-project push is cut
  (D3). No network egress exists in the seed or the checks.

One leg, so `agent-safety-review` is not triggered. **Re-run this
classification before any slice that adds the outbound push**, which would make
it two.

### Re-classification — 2026-09-18 (the pilot slice)

Done as the paragraph above instructs. The pilot adds the predicted leg.

- `private_data`: **Present** — unchanged. Note the sharp edge: `dion report`'s
  `--db-path` **defaults to `data/dion.duckdb`**, so the private store is one
  omitted flag away from the pilot's own happy path. That is why the explicit
  throwaway path is asserted in a test, not stated in a doc.
- `untrusted_input`: **Absent** — inputs are a committed synthetic fixture, a
  committed brief, and the repo. **This leg must not be acquired:** no arm may
  fetch a URL, read a downloaded file, or consume a third-party API response. A
  future slice wanting live market data or a remote design reference re-runs
  this classification first.
- `outbound_action`: **Present** — judging sends artifacts and screenshots to
  Codex.

**Two legs → elevated. `agent-safety-review` was run (2026-09-18).** Its
structural finding: *the two legs are never co-located in one agent.* Arm
subagents have no egress path at all — no network tools, no dispatcher, they
emit files. The orchestrator has egress but sends only a frozen package the
user previewed and approved, scanned by gitleaks. Cutting `outbound_action` at
the arm level is a construction, not an instruction.

**Residual risk and its control.** An arm could read `data/` by absolute path
and inline real holdings into its HTML, which would then be frozen and sent — a
plausible-looking row of real positions is exactly what survives a human
preview of a 7 KB file. Instruction does not close this. A **pre-egress hash
assertion** does: the data embedded in an artifact MUST hash-match the frozen
fixture bytes, and any mismatch refuses egress with no human judgement
involved. Per the skill's red-first rule it is authored **failing** — a
deliberately contaminated artifact must be refused before either arm runs.
gitleaks catches credentials, not portfolio positions, so this assertion is
doing the real work on this path.

## Eval strategy

Deterministic parts are unit-tested: the checks' exit codes, the enumeration's
self-consistency, rule-ID uniqueness and coverage. The probabilistic claim — "a
model produces better UI with the seed than without" — is **not** asserted by
this change. It now has an eval: the two-arm pilot pre-registered below (D8).
That eval deliberately does **not** assert the sentence above; it licenses a
strictly weaker one, because one pair cannot separate a repeatable advantage
from generation variance. n=1 licenses the method, not the default.

## Pilot pre-registration — 2026-09-18

Committed **before either arm runs**. Anything changed after results are seen
makes this v2, and v1 results are not pooled with it. Precedent for the form:
`openspec/changes/implement-shadow-event/design.md`.

### Treatment and claim

Treatment is the **first-use workflow** (D8). The strongest claim a completed
pilot may licence is:

> On this task, fixture, model configuration and resource cap, the
> seeded-adoption run received a higher blinded rubric score than the
> comparator run, and the required process gates were satisfied. This single
> pair does not distinguish a repeatable workflow advantage from generation
> variation.

Anything stronger — "the seed improves UI", "the tokens work" — is **not**
licensed by this design, whatever the result.

### Arms

Two fresh subagents, disjoint context, each in its own `git worktree` off the
same base commit (subagents must not write to a shared checkout, and Dion's
pre-push gate defines a clean tree narrowly enough that a stray arm trips it).

**Identical:** task brief, fixture bytes, model, tool access, output shape,
budget. **Different:** arm S's worktree carries the seed **UNADAPTED**, plus
the `ADOPT.md` pointer line in that worktree's agent instructions. Arm C has
none of it.

The brief is **framing-free for both** — "build a read-only execution-list
screen from this JSON" plus hard constraints. It never mentions tokens,
styleguides, design systems, a hypothesis, or that another arm exists.

**Arm blinding is impossible and is not attempted.** Arm S can see `design/`.
Only the judge is blinded. Awareness is part of the workflow under test.

### Budget

Equal **total** budget, clock starting at launch — i.e. **before** adoption, so
author preparation cannot become free adoption work. Adoption and
implementation expenditure are reported separately. The cap is defined
operationally before launch (tokens, tool calls, elapsed time), with identical
stopping rules, timeout handling and retry allowance, and actual consumption
recorded alongside the cap.

This is a deliberate handicap: arm S spends budget adopting that arm C spends
on the screen. A pilot designed by the seed's author should lean against itself
where it can do so cheaply.

### Fixture

Produced through the **store-then-retrieve** path, never by calling
`build_review_report()` directly. `dion report` reads a stored `report_json`
column and wraps it in an envelope; `comparators` and `integrity_evidence` are
live on the in-memory dataclass and only go missing across persistence. A
builder-constructed fixture would carry them, erase two of the four known gaps,
and make criterion (c) unfalsifiable. **This is the one shortcut that silently
destroys the experiment.**

Consumed shape is the envelope, not a bare report. An explicit throwaway
`--db-path` is asserted in a test. Fixture bytes are hashed and both arms
provably receive the same bytes. **Fidelity is not adequacy:** before either
arm runs, verify the fixture actually exercises every scored state — numeric
edge cases, intentional omissions, and the distinction between a missing value,
an absent field, and unavailable evidence.

### Criteria

**(a) Adaptation — with a null outcome permitted.** Arm S records *either* an
adaptation (the original rule, its predicted failure against this task, the
change, and a check distinguishing original from adapted, with the screen
exercising it) *or* an explicit **"no justified adaptation needed"** with
reasoning. Both are valid. Forcing an adaptation manufactures a deficiency.
Scope is declared honestly as a **selected adaptation test**, not a general
test of seed usefulness. The distinguishing check proves behaviour *changed*,
never that it *improved*.

**(b) Freeze boundary.** Permitted before freeze: reading the fixture and repo,
adoption work, and any rendering probe genuinely needed to evaluate the seed
against the task. The boundary is a `git commit` of `design/` in S's worktree,
sha recorded. After it: no new styling instruction, no reference design, no
manual visual correction, no further `design/` edits. All prompts and edits
retained. Arm C has nothing to freeze, so (b) is an **S-only process gate** and
is assessed outside the blinded judging.

**(c) Contract delta — from BOTH arms, under identical requirements.** Each
entry names a requested field or representation change, the specific screen
behaviour the frozen envelope cannot support, an example payload, and a
testable acceptance criterion; and is labelled `supplied-in-advance` or
`screen-discovered`. **Advance disclosures are frozen before either arm runs**,
including what Dion's own code and comments already reveal. A `screen-discovered`
label requires traceable screen behaviour and evidence of when the need arose —
a self-label is not evidence. Rediscovering the four known gaps counts as
**zero**.

**Failure condition:** an arm whose entire output is backend code leaves the
method unevidenced there, however much the data contract improved.

**Process compliance is scored separately from quality.** Arm S earns no
quality credit for producing adoption evidence.

### Rubric

Derived only from sources predating the seed: Dion's declared Numeric Policy;
its existing "missing stays `None` so the renderer shows a gap rather than a
plausible-but-wrong 'free trade'" comment; its "never invent prices, returns,
or holdings" principle; plus the independently-stated list of visual hierarchy,
readability of financial values, consistency across repeated elements and
states, and honest handling of missing information. Plus envelope fidelity:
displayed values match the fixture bytes.

**Excluded from scoring:** token usage, presence of a design system,
resemblance to the seed. Quality is never defined as looking like the thing
under test.

Committed before either arm runs; its `sha256` recorded here on commit. Git is
an **audit trail, not a trusted timestamp** — local history and dates are
rewritable — so the pre-run commit is pushed to the remote before launch, and
the guarantee is not overstated beyond that.

### Frozen artifacts — digests (recorded 2026-09-23)

The artifacts named above are frozen in **Dion** (private) at commit
`710938d14844026261a5d287aa78bb75bfd7bcd6`, branch `design-seed-pilot`. This
repository is public, so it records their paths and digests only — no Dion
content is reproduced here. Each digest is re-checked on every Dion test run
(`tests/design_seed_pilot/test_fixture_fidelity.py`), so an artifact edited
after freezing fails that suite rather than drifting quietly.

| Artifact | sha256 |
|---|---|
| `tests/fixtures/design_seed_pilot/review_report_envelope.json` | `c4c7dcd6c99ae3f21f0230b29c443292624e8cb96c31e83e967f6e498f35fadf` |
| `tests/design_seed_pilot/build_fixture.py` | `b9fe6512e55a3eb86fdf8dd86bf84ae3b63c88f1921ca036884cf226a2885bdb` |
| `docs/design-seed-pilot/advance-disclosures.md` | `d0dc7c7d0e7d565674528ebb6887535e96b2c56e512674a2b2d182ab27d01b1d` |
| `docs/design-seed-pilot/budget.md` | `100b4a118546ec5c2554d061cd14a98d4dae107ce2210042b9a854a90f07140b` |
| `docs/design-seed-pilot/rubric.md` | `001206a1870602c3f8f7a14473a0d8f7fb3881f7e7f834b02add787a9ef1dbff` |
| `docs/design-seed-pilot/relevance-audit.md` | `8a137838e705fd7d5496ed6c8d9444bb727cf66eaf061f25400d0979349a39ab` |
| `docs/design-seed-pilot/provenance-appendix.md` | `717bfd75280f9c02fc6261718d77877e351b3041a65e11a9136c7123ebd6895e` |
| `docs/design-seed-pilot/brief.md` | `20183b4dd11bf1bc41f24b180ef3c2cb875fce86ce942a8a364a2268fceb8f82` |

Two notes the sections above did not anticipate:

- **The disclosure list is derived, not inherited.** This document refers to
  "the four known gaps" without enumerating them anywhere. Rather than guess
  which four were meant, the frozen list was re-derived from Dion's source and
  from the frozen envelope, and contains **five** entries, each pinned by a
  test. An arm reporting any of them scores zero regardless of whether it was
  among the original four.
- **The arms receive the fixture at a neutral path.** The fixture's own
  directory is named after the treatment, so delivering it at that path would
  tell both arms the subject of the study from a filename. The brief names
  `input/report.json`, and the bytes are hash-checked against the digest above.

### Rubric citation provenance — an open weakness, recorded not hidden

A fresh reviewer checked the rubric against the citation requirement above
("every dimension MUST cite a source that predates the seed or is independent
of it") and found three dimensions that satisfy neither limb. R5 (visual
hierarchy), R6 (readability of financial values) and R7 (consistency across
repeated elements and states) rest on the presentation list stated in **this
document**, which `git log -S` places at `14e02a5` — after the seed shipped at
`2c038b1`, by the same author, in the same change. "Independent of it" cannot
reasonably mean "another section of the document that defines the treatment",
or the requirement is satisfiable by writing one more paragraph.

Two things were fixed rather than argued: the rubric no longer *claims* those
sources are independent, and R2 was re-grounded. R2 had cited Dion's Numeric
Policy table for a display-precision rule that table does not contain — it is
a DuckDB storage-type table that gives quantities and prices the **same**
type — while the rule it actually stated ("decimal places fixed per column")
is the seed styleguide's. It now cites `src/dion/cli_text.py:184-199`, the
execution-list formatter Dion already ships, which is genuinely independent of
the seed and is about display.

**Still open, and it is a judgement for the owner, not the author:**

1. R5/R6/R7 either get genuinely external sources, or the owner records a
   ruling accepting author-stated dimensions. They are currently marked in the
   rubric as an advance-committed list, with no claim of independence.
2. The same reviewer observed that dimension *selection* tracks the seed
   styleguide's section headings even where each citation is clean. No
   rewording fixes that; it is a question of whether the instrument was
   designed around the treatment.

Recorded here, before either arm runs, because a weakness in the instrument
that is discovered after a result is indistinguishable from an excuse.

The same review closed three post-hoc escapes. The disclosure list is now
**closed** — a gap not listed scores as `screen-discovered`, and no entry may
be added once an arm has run, which removes the "that was known too" move. The
**budget is a frozen artifact** rather than a phrase in the brief: outcome 4
("exceeded the cap") was not decidable against a cap nobody had written down.
And the generator is digested alongside the fixture, since it is what the
regeneration test compares against — editing both would have left every check
green.

### Judging

**Two** fresh, framing-free consultations with presentation order reversed
between them, same frozen rubric, pinned model and version. Each artifact is
scored **independently** per dimension with cited evidence **before** any
comparative verdict; comparative-first is banned.

Inputs: HTML source plus matched browser screenshots. **The Python gate does
not cover rendering** — `ruff`/`pyright`/`pytest` prove the generator sound and
say nothing about whether the HTML renders. Captures use a frozen browser,
viewport, zoom and declared font availability, light and dark. An arm with no
dark theme shows what it shows; that is a finding, not a disqualification.

Blinding is **presentational only**: filenames normalised, provenance headers
and generator comments stripped. **Visible design is never altered to hide
treatment**, so a judge may infer provenance from semantic variable names —
acceptable; ask whether they inferred it *after* scoring and record the answer.

The label mapping is written to a file **before** the judges are asked.

### Pre-registered outcomes

1. Both arms render, process gates satisfied, **both judges favour S** →
   observed comparison favouring the seeded workflow, reported in the claim
   wording above. Licenses promoting the **method**, never the default.
2. **Both judges favour C** → recorded as such, and interpretable because the
   treatment is the whole workflow: it cost more than it returned within this
   budget.
3. **Judges split** → **judge-sensitive / inconclusive.** No third call. A
   tiebreaker added after seeing a split manufactures the verdict.
4. An arm fails to render, exceeds the cap, or trips the gate → reported
   visibly. **One rerun only for an infrastructure fault** (harness crash, tool
   unavailability), declared and recorded — never for an unsatisfying result.
   Selective retries are a larger threat than the missing arm blinding.
5. Process-gate failure on (a) or (b) → reported **separately** from the screen
   score. The run is not dropped.

### What this pilot cannot establish

How often S wins; that the seed's substantive rules (as opposed to the
workflow) caused any difference; that an adaptation improved the screen; or
that a narrow victory means anything at all. Two judge calls to one model
measure order sensitivity and some judging variance — they are not independent
perspectives and share systematic biases, and no amount of judging compensates
for one generated artifact per arm.

### Preserved artifacts

Base commit, seed version, rubric and its hash, both briefs, fixture and its
hash, budget rules, all arm prompts and edits, both artifacts, screenshots,
label mapping, both judge responses, and the adjudication — not merely this
document.

## Registration v2 — 2026-09-24 (committed before the relevance audit runs)

v1 never ran. No arm executed, no artifact was produced, no judge was asked, so
there are no v1 results and nothing to pool or discard. v2 replaces v1 outright.

### Why

Two defects in v1's instrument, both verified rather than argued. Three of seven
dimensions cited a presentation-quality list that `git log -S` places in
`14e02a5` — the commit that wrote this pre-registration, a direct child of
`2c038b1`, which shipped the seed, same author, same change; the "predates the
seed" limb fails on the commit graph. And five of seven dimensions mapped
one-to-one onto the seed styleguide's own section headings, which no rewording
reaches, because it is a fact about which qualities were chosen to measure.

A separate instrument was then derived by a different model family shown only
the task, the operator's decisions and the frozen payload — never the seed,
never the rubric, never the fact that a comparison exists. A three-way design
debate and a cross-family critique of that debate's consensus followed. The
decisions below are the result.

**The ordering of this document is itself a control.** These rules are
committed and pushed *before* the relevance audit is run, because a disposition
rule chosen with the findings already in view is not a rule.

### v2-1 — The instrument is replaced, not repaired

The derived instrument becomes the scoring instrument, subject to the audit in
v2-2. v1's seven dimensions are published **unscored**, as a provenance
appendix. Repair was rejected: the defect is selection, and the only party
available to repair it is the one who cannot un-see the seed.

Two honest limits on that reasoning, recorded because they cut against the
decision. A different model family is **not** a certificate of independence —
the protection is restricted access to information, and the task framing handed
to the deriving model was written by the seed's author, so it could carry
seed-derived assumptions. And repair was rejected as *less credible*, not as
logically impossible.

### v2-2 — Relevance-audit disposition rule

Applied to every dimension **and every subcriterion** of the derived
instrument, before freezing, with the outcome and reason recorded per item:

1. Is it justified by the **task** — an operator decision named in the brief,
   or a fact in the payload that those decisions make relevant? If yes, keep it
   and record the justification.
2. Failing that, is it a requirement the **arms' brief already states**? If
   yes, keep it: both arms were told.
3. Otherwise **cut it.**

Presence in the payload is necessary but not sufficient: a payload may contain
facts the screen should omit. Overlap with the seed is not itself
disqualifying either — a valid criterion may coincide with seed guidance. The
decisive test in both directions is independent task relevance.

**"Move the requirement into the brief" is deliberately NOT a permitted
disposition.** It was argued for and rejected: equalising the brief answers a
different question ("given an explicit requirement, which workflow delivers
it better?"), and mutating the shared input reopens "what else should the brief
name?" without a principle that terminates it.

### v2-3 — Dark theme is cut; captures are width-only

Measured: the seed's files mention dark in five of six, `ADOPT.md:45` calls a
light/dark role mismatch "the most common mistake", and its lint checks for it,
while the arms' brief mentions themes **zero** times. Under v2-2 the dimension
fails at every step — no operator decision requires it, no payload fact implies
it, and the brief does not state it. The only arguments for keeping it were
that the derived instrument measures it and that the seed supports it, which is
the instrument manufacturing the task to justify its own inclusion criteria.

The v1 capture protocol ("light and dark") is amended: captures are taken at
**1280px and 400px**, both stated in the brief, under a pinned browser,
viewport, zoom and declared font availability, with no theme forced and no
theme scored. An artifact that ships a dark theme is neither credited nor
penalised for it.

### v2-4 — The judge decision rule

v1 registered a direction call per judge and never said how dimension scores
become one. Dropping the derived instrument's weights without supplying a rule
would leave each judge to invent an unregistered one, which is worse than
weights. Registered now, applied in order:

1. **Fidelity tier.** A score of 0 on any dimension in the fidelity class —
   corrupted or wrong execution values, invented data, or a false claim of
   clearance — is disqualifying for direction. If exactly one artifact in a
   pair has such a failure, the other is favoured, whatever the remaining
   scores. A presentation advantage never outweighs a factual failure, because
   the operator is transcribing these numbers into a broker.
2. **Dimension count.** Otherwise, the artifact scoring strictly higher on more
   dimensions is favoured.
3. **No direction.** If the counts tie, that judge reports no direction, which
   feeds the pair rule in v2-6 exactly as a split does.

### v2-5 — What is kept and what is dropped from the derived instrument

**Kept:** the 0-3 anchors; the shared reference-fact sheet, prepared and frozen
before any candidate is viewed; and the double-counting table — amended, per
the critique, to prevent two penalties for the same *consequence* rather than
asserting that one defect can have only one relevant harm.

**Kept as a validity screen, not as scoring:** an artifact that does not render,
requires the network, or violates the read-only constraint is reported under
outcome 4 rather than scored. v1 had no predefined treatment for this.

**Dropped:** the weighted total and the eligibility floor, both superseded by
v2-4; and the unresolved-disagreement interval rule, which directly contradicts
the registered "split = inconclusive, no third call".

### v2-6 — n = 3 paired repetitions of the same task

Three independent S/C pairs on the **same** frozen fixture, brief and budget,
each run from fresh context, with pairing and presentation order fixed in
advance.

Three *different fixtures* were rejected: with one pair each, fixture
differences and generation variance stay entangled, which is the opposite of
what this buys. Repetition on one task isolates the single thing no amount of
instrument work can address — whether a first observed direction repeats under
identical conditions.

Each pair is judged by two judges under v2-4 and resolves to S, C, or
inconclusive under the v1 agreement rule, unchanged. **All three pair outcomes
are reported.** No overall verdict is produced and none may be introduced
later: a majority rule adopted after seeing the pattern is the move this
document exists to prevent. Six judge calls are three paired repetitions
evaluated twice, and will never be described as six observations.

### v2-7 — Calibration read

Before any arm runs, both judges score one decoy artifact under the frozen
instrument. Its purpose is narrow and registered: to expose unclear anchors, a
missing evidence input, or an unusable scoring procedure, and to measure judge
alignment — because "split = inconclusive" is a live outcome and alignment on a
decoy is the only thing that separates *the instrument cannot discriminate*
from *the arms were genuinely close*.

**The alignment read is published whatever the pilot's outcome, including when
the pilot is inconclusive.** Reported only alongside a decisive result it would
be decoration.

If the read exposes a serious problem, the permitted responses are to repair
and re-freeze **before any arm runs**, or to stop. "Mark it and proceed anyway"
is not one of them.

### v2-8 — Versioned registration instead of a stopping rule

A pre-committed "this is the final instrument change" was proposed and
rejected: it creates an incentive to knowingly keep a defect in order to
preserve a claim label. Instead, this registration is **versioned and dated**.
Any further substantive change before the arms run increments it to v3, states
what changed and why, and is pushed before launch. A discovered flaw triggers
correction or cancellation, never a ceremonial demotion.

### v2-audit — Outcome, recorded 2026-09-24

Run after v2-1..v2-9 were pushed at `1b1c91f`. Seven dimensions audited,
**seven kept, one subcriterion cut** (the theme requirement, per v2-3). The
aggregation machinery was dropped and the delivery screen retained as a
validity check, as registered. Full dispositions with per-item justification
and the seed-overlap assessment: `docs/design-seed-pilot/relevance-audit.md`
in Dion, digest below. The superseded list is published unscored at
`docs/design-seed-pilot/provenance-appendix.md`.

A high keep rate is not a vindication. The instrument was derived by a party
with no access to the seed, so few leaks were expected; the one that was found
was found by looking, which is not evidence it was the only one. The audit
records R3 as the weakest kept dimension — the exposure gates are
portfolio-level while the rest of the card is row-level — rather than hiding
the concession.

One dimension of the superseded instrument was **withdrawn as incorrect**, not
merely as contaminated: it required limit prices at two decimals, citing this
project's text-mode formatter, against an input whose limit endpoints carry
four decimals. It would have marked a correct build defective and rewarded
discarding execution precision.

### v2-9 — What v2 can no longer claim

- **Requirement discovery is out of scope.** Whether the seed surfaces
  requirements an unaided build would miss is not tested here, and no result
  may be read as evidence about it either way.
- **Generalisation remains out of scope**, as in v1. Three repetitions on one
  fixture can show whether a direction repeats under identical conditions. They
  cannot show it holds for another task, another payload, or another model.
- At this sample size every control here buys only that the signal was not
  fabricated. None of it buys generalisation, and that sentence travels with
  any quotation of the result.

## Out of scope

Dion's financial logic, data, or brand inside the plugin; broad dashboards;
trading or approval controls; any new owned skill; any `DesignSync` dependency;
a component generator; pinned frontend dependencies; an upgrade/merge path for
already-copied seeds.
