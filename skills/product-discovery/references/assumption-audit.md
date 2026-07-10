# Assumption Audit — ledger schema and authoring rules

Reference for the `## Assumption Ledger` and `## Options` sections that
`## Step 3b: Assumption Audit` adds to the discovery brief. The deterministic
checker `scripts/assumption-audit-check.sh <discovery-doc>` parses these sections;
keep the column order and cell rules below exact or the checker false-FAILs.

## Ledger format

Emit these two sections into the discovery doc verbatim in this shape:

```markdown
## Assumption Ledger

Logic chain: We achieve <outcome> because the assumptions below hold.

| id | belief | category | importance | evidence_kind | source_ref | observed_at | grade | kill_threshold |
|----|--------|----------|------------|---------------|------------|-------------|-------|----------------|
| A1 | Users abandon at step 3 because of latency | customer | H | direct_metric | posthog:funnel_q2#step3_dropoff | 2026-07-01 | B | fix ships, dropoff stays >30% -> kill |
| A2 | Competitors will not match pricing in 2 quarters | competitor | M | expert_judgment | PM interview | 2026-07-08 | D | untested (cutoff) |

## Options

| option | summary |
|--------|---------|
| do-nothing | Keep current funnel; revisit next quarter |
| A | Rebuild step 3 client-side |
```

Column order is fixed and positional: `id | belief | category | importance |
evidence_kind | source_ref | observed_at | grade | kill_threshold`. The checker
reads by position, so reordering or dropping a column corrupts every row.

## evidence_kind enum and evidence ceiling

`evidence_kind` is one of: `direct_metric`, `direct_observation`, `analogous`,
`expert_judgment`, `none`. Each kind caps the best grade the belief may claim —
grade the evidence, not the authority or confidence behind it:

| evidence_kind | grade ceiling |
|---------------|---------------|
| direct_metric or direct_observation | A |
| analogous | C |
| expert_judgment | D |
| none | F |

A row whose `grade` outranks its ceiling (A best, F worst) is a checker
violation. A strongly held, confidently asserted belief with only a person's
say-so behind it is `expert_judgment` and caps at **D** — no matter how senior
or certain the source.

## A-F rubric

- **A / B** — validated by direct data or a run experiment.
- **C** — analogous evidence (it worked in a comparable case).
- **D** — expert judgment alone (opinion, intuition, a confident assertion).
- **F** — unexamined wishful thinking; no evidence offered.

A strongly held D-grade belief is still a D. Grade evidence, not authority or
confidence.

## Grade A/B extra rule

Grade A or B rows MUST carry a non-empty `source_ref` and `observed_at`. When a
`source_ref` has the form `<path>#<literal>` and `<path>` is an existing repo
file, the `<literal>` must appear in that file (the checker greps it). Other
`source_ref` forms (URLs, `posthog:...`, prose like "PM interview") are
presence-only — they just have to be non-empty.

## Fragile rows and the materiality cutoff

A row is **fragile** when `importance` is `H` AND `grade` is C, D, or F. Every
fragile row MUST have a non-empty `kill_threshold`.

You cannot kill-shot everything. Rank fragile assumptions by materiality and take
the **top 3**: for each, design a kill-shot test and pre-declare a concrete
kill/validate threshold in `kill_threshold` (e.g. `fix ships, dropoff stays >30%
-> kill`) BEFORE running it. For fragile rows below the top-3 cutoff, set
`kill_threshold` to the literal marker `untested (cutoff)` — this is a valid,
checker-accepted value that records the row was consciously deferred, not missed.

## Options and do-nothing

The `## Options` section MUST contain a `do-nothing` row (keep-the-status-quo
baseline). State the recommendation conditionally: proceed / proceed-with-
conditions naming a hard-number condition / hold.

## Cell authoring rule (avoids false FAILs)

Table cells MUST NOT contain a literal `|` character. The checker splits rows on
`|` with `awk -F'|'`, so a stray pipe inside a cell shifts every downstream field
and produces spurious violations. If a belief or threshold needs a pipe, rephrase
it — use the word "or", or a "/". Likewise keep each row on a single line (no
newlines inside a cell).
