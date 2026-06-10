# Proposal: Format Handoff Eval

## Why

A session-level design debate proposed (a) converting approved PDLC markdown artifacts to
DocLang XML before LLM handoff ("lossless parsing avoids hallucinations") and (b) adding
YAML front-matter to generated artifacts for deterministic machine consumption. Per the
race-before-debate discipline, both claims required measurement before any adoption:
no prior eval ranked markdown vs markdown+front-matter vs DocLang on comprehension,
fabrication, or drift-detection, and the front-matter design had no measured benefit.

## What Changes

A reusable format-handoff evaluation harness was built on the existing behavioral-eval
runner, plus two incidental fixes discovered while building it:

- `tests/run-format-evals.sh` — opt-in driver looping (scenario × format) combos through
  `tests/run-behavioral-evals.sh`, aggregating pass rates per format and assertion kind
  (comprehension / absence / drift) from variance reports.
- `tests/fixtures/format-eval/` — eval pack (6 scenarios, 34 POSIX-ERE-checked assertions)
  and 12 renderings of 4 real PDLC artifacts (spec, proposal, design, postmortem) in
  3 formats (markdown, markdown+front-matter, DocLang via docling 2.98.0).
- `tests/test-frontmatter-extraction.sh` — deterministic extraction-robustness test:
  design-guard heading-grep vs a minimal `fm_get` awk reader across 5 heading mutations,
  including a real-specimen regression (approved serena design doc's `## Out of Scope`
  is missed by the guard's `^## Out-of-Scope` grep in production).
- `tests/run-behavioral-evals.sh` — bugfix: prompt delivered via stdin; the current
  Claude CLI parses `--disallowedTools` as variadic and swallowed the trailing prompt
  positional, breaking every eval pack under the current CLI.
- `tests/test-run-behavioral-evals-variance.sh` — stub now guards the stdin contract
  (bounded `read -t`; fails loudly on argv regression instead of deadlocking).

**Measured outcome (criteria frozen before any run):** DocLang REJECTED — +13–99% tokens,
lossy round-trip (postmortem lost 14.8% of words incl. P0/P1 action items; design lost its
`<100ms` budget), and zero quality edge (all three formats scored 100% on 102
assertion-evaluations each, variance 3). Front-matter UNPAUSED — zero LLM-side degradation
and 5/5 vs 2/5 deterministic extraction win. Markdown remains the sole handoff format.

## Capabilities

### Modified Capabilities
- `behavioral-evaluation`: gains a format-comparison driver, a multi-format eval pack
  convention (assertion-kind tags in descriptions), a deterministic extraction eval, and
  a runner that survives the current CLI's variadic `--disallowedTools` parsing.

## Impact

- Files added: `tests/run-format-evals.sh`, `tests/test-frontmatter-extraction.sh`,
  `tests/fixtures/format-eval/**` (pack + 12 renderings)
- Files modified: `tests/run-behavioral-evals.sh` (stdin fix),
  `tests/test-run-behavioral-evals-variance.sh` (stdin regression guard)
- No hook, config, or skill changes. No new runtime dependencies (docling used only
  offline to produce committed fixtures).
- Decision record: `docs/plans/2026-06-10-format-handoff-eval-hypothesis-and-plan.md`
  (frozen criteria, results, DocLang revival criteria) + auto-memory entry.
