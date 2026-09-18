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

## Eval strategy

Deterministic parts are unit-tested: the checks' exit codes, the enumeration's
self-consistency, rule-ID uniqueness and coverage. The probabilistic claim — "a
model produces better UI with the seed than without" — is **not** asserted by
this change and has no eval here; the pilot's job is to produce the first
evidence, and n=1 licenses the method, not the default.

## Out of scope

Dion's financial logic, data, or brand inside the plugin; broad dashboards;
trading or approval controls; any new owned skill; any `DesignSync` dependency;
a component generator; pinned frontend dependencies; an upgrade/merge path for
already-copied seeds.
