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
structural finding was that *the two legs are never co-located in one agent* —
and the first version of this paragraph overstated how that was achieved. Arm
subagents were said to have "no egress path at all". They do not: arms are
dispatched as `general-purpose`, whose tool access is `*`; the Agent tool
exposes no tool-restriction parameter; and at the time of writing no deny rules
existed in the subject worktree, in user settings, or in a local settings file.
Arms are **instructed** not to transmit, and an instruction is prose about a
prompt, not a bound on a capability. What backs the claim now is a real
mechanism: a `PreToolUse` deny hook (`.claude/hooks/pilot-arm-deny.py`, wired
in Dion's `.claude/settings.json`, regression
`tests/design_seed_pilot/test_arm_capability_boundary.py`) that refuses
`WebFetch`, `WebSearch` and the whole `mcp__` namespace by tool name, and
refuses reads of an enumerated set of sensitive paths across every path-bearing
tool. The orchestrator has egress but sends only a frozen package the user
previewed and approved, scanned by gitleaks.

**Where the cut is made, and why it moved.** The earlier claim that "cutting
`outbound_action` at the arm level is a construction, not an instruction" named
the right distinction and landed on the wrong side of it. The cut is now made
on the **`private_data`** side instead. That is not a retreat; it is the only
side that can be cut soundly. Enumerating every way a tool-unrestricted agent
can send bytes is unbounded — a network fetch in a shell one-liner, a push to a
remote, a socket opened from Python, a verb on some MCP server nobody listed —
whereas enumerating the sensitive paths is finite, so a complete list is
actually writable. The tool-name leg of the deny hook is complete by
construction for the tools it names; **Bash-level network egress is NOT closed
and is stated here as residual**, rather than covered by a list that would only
look complete.

**Residual risk and its control.** An arm could read `data/` by absolute path
and inline real holdings into its HTML, which would then be frozen and sent — a
plausible-looking row of real positions is exactly what survives a human
preview of a 7 KB file. Instruction does not close this. A **pre-egress hash
assertion** narrows it: the data embedded in the designated `id="dion-report"`
block MUST hash-match the frozen fixture bytes, and any mismatch refuses egress
with no human judgement involved. Per the skill's red-first rule it is authored
**failing** — a deliberately contaminated artifact must be refused before
either arm runs.

**What that assertion does not do, said plainly.** It certifies the designated
data block, not the artifact. The threat this section opens with — real
holdings rendered into the *visible body* of the HTML — is **not** caught by
it: the body is not the data block, and an arm that inlined a row of real
positions into a table would pass the check. So the hash assertion is not
"doing the real work on this path".

Nor does it close the payload-substitution route as such — it closes **one
spelling** of it. The duplicate-block counter is a quote-style-aware literal
match on `<script … type="application/json" …>`, so a smuggled second payload
is counted only when written that way. Measured against the checker itself,
each of the following carries a second block straight past it, while a browser
treats every one as an inert data block whose text a script reads identically:

| Second block, as written | Counter |
|---|---|
| `<script type="application/json" id="holdings">` | refused — the one spelling it catches |
| `<script type=application/json id=holdings>` | **allowed** — unquoted attribute value |
| `<SCRIPT TYPE="application/json" …>` | **allowed** — uppercase tag or attribute name |
| `<script type = "application/json" …>` | **allowed** — whitespace around `=` |
| `<script type="text/json" …>` | **allowed** — a different MIME spelling |

(A newline between `<script` and its attributes *is* caught — incidentally,
because the matcher's character class excludes it, not by design.)

Those are named here as **residual and deliberately unfixed**. Extending the
matcher to cover them is the same unbounded enumeration this design refuses two
paragraphs above for `outbound_action`: a longer list of attribute spellings
would read as complete without being a parser, which is worse than a stated
limit. The honest claim is the narrow one — the counter catches a duplicate
block spelled the way `brief.md` mandates, so it constrains an arm that follows
the format and substitutes the payload, and not one that does not.

What carries the rendering route is weaker and worth naming precisely, because
the deny hook does **not** cover it: the hook's path list is
`~/.config/gh/hosts.yml`, `~/.ssh`, `~/.claude.json` and
`~/.claude/projects/*/memory/`, and Dion's `data/` store is not on it. What
actually stands between an arm and real holdings is that **no private store
exists in the arm worktrees** — a fact, not a control, which is why Task 8 now
re-measures it (`find … -name '*.duckdb'`) immediately before dispatch rather
than relying on a measurement taken hours earlier — plus the human preview.
Validating the whole artifact is deferred work: it requires a `brief.md`
change, and `brief.md` is frozen. gitleaks, separately, catches credentials and
not portfolio positions.

**The human preview only carries anything if nothing has already been sent by
the time a human looks.** That was not true until now: `scripts/pilot-capture.sh`
rendered the artifact with the network live, so a remote `<link>`, `<img>`,
`fetch()` or `WebSocket` in an arm's HTML reached its host — carrying whatever
that arm chose to put in the URL — during capture, twice, once per
colour-scheme pass, with nothing in any pilot output showing it. `brief.md`
already instructs arms not to include remote references, which is the exact
shape of control this wave exists to distrust. Capture is now a construction:
every non-`file:`/`data:`/`blob:`/`about:` request is aborted by a per-context
interceptor, and the browser additionally runs behind a dead proxy with
loopback bypass disabled, which closes WebSockets — the one shape page-level
routing does not see in the pinned Playwright. Measured against a local server,
the same artifact went from 8 requests reaching it to 0, while still producing
both PNGs. Regression: the egress cell in `tests/test-pilot-capture.sh`, which
asserts against a real server rather than against the code.

**The three legs, each with its real status.** Worth stating together, because
the oversight has been lopsided:

- `private_data` — **absent in fact today** (the pilot's only input is a
  committed synthetic fixture), **present the moment a portfolio store
  exists**, and — the part that matters — **never validated against the real
  threat**. The classification was reasoned about, not exercised. That is how
  the gap above survived nine tasks of otherwise careful work.
- `untrusted_input` — **absent at the arms**, whose inputs are all committed.
  But **present-but-low-risk at the orchestrator**: it reads judge responses,
  which are third-party model output, and acts on them in Task 12.
- `outbound_action` — **present**.

And the inversion deserves naming rather than leaving for the next reader to
find: the heaviest machinery in this design sits on the outbound consultation —
freezing, hashing, gitleaks, a previewed package — while the arms, which hold
far broader capability than the dispatcher ever does, are governed by an
instruction plus the deny hook added here.

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

## Out of scope

Dion's financial logic, data, or brand inside the plugin; broad dashboards;
trading or approval controls; any new owned skill; any `DesignSync` dependency;
a component generator; pinned frontend dependencies; an upgrade/merge path for
already-copied seeds.
