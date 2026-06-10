# Format Handoff Eval — Hypothesis & Plan

**Date:** 2026-06-10
**Status:** Criteria frozen BEFORE any eval run (race-before-debate discipline)
**Branch:** `format-eval` (worktree `.worktrees/format-eval`)
**Origin:** DocLang PDLC evaluation session. Token race showed DocLang costs +13–99% tokens
on born-digital markdown; this eval tests *quality* claims (hallucination, drift, comprehension)
that token counts cannot settle. `artifact-frontmatter` openspec change is PAUSED pending verdict.

## Hypotheses

- **H-doclang:** Converting approved markdown artifacts to DocLang before LLM handoff reduces
  hallucination / improves drift detection enough to justify ~2× token cost. (User's claim:
  "lossless, correctly parsed docs avoid hallucinations.")
- **H-frontmatter:** YAML front-matter (a) does not degrade LLM comprehension vs plain markdown,
  and (b) materially beats heading-grep for deterministic field extraction by hooks/scripts.
- **H-null:** Plain markdown is no worse than either alternative on all quality metrics.

## Formats

- **F1** — plain markdown (original artifact, unmodified)
- **F2** — markdown + flat YAML front-matter (schema from paused B-design)
- **F3** — DocLang XML via `docling` 2.98.0 `export_to_doclang()` (venv `~/.cache/doclang-eval`)

## Corpus (real artifacts, one per PDLC type)

| id | file | type |
|----|------|------|
| spec | `openspec/specs/pdlc-safety/spec.md` | openspec capability spec |
| proposal | `openspec/changes/context-economy-defaults/proposal.md` | proposal |
| design | `docs/plans/2026-05-23-serena-auto-register-design.md` | design doc |
| postmortem | `docs/postmortems/2026-04-08-hcs-gb-billing-tab-500-calendar-api-removed.md` | postmortem |

## Eval family 1 — LLM handoff quality (behavioral runner, `--variance 3 --bare`)

Reuses `tests/run-behavioral-evals.sh` unchanged: `SKILL_PATH=<rendering>` injects the artifact
in a constant `<skill_guidance>` wrapper (identical across formats → relative ranking valid).

Per artifact, one **probe scenario** (single `claude -p` call, numbered questions):
- 4 comprehension probes with ground-truth regex assertions (answers exist in doc)
- 2 absence probes (answers deliberately NOT in doc; correct answer = "not specified");
  assertion regex matches the refusal phrasing → a fabricated answer FAILS the assertion

Plus 2 **drift scenarios** (design + spec artifacts): prompt contains a diverged implementation
summary; assertions check the model names the planted drifts.

Run matrix: probes 4 artifacts × 3 formats + drift 2 × 3 = 18 scenario-runs × variance 3 =
**54 inner `claude -p` calls** (session model, `--bare`, tools disallowed by runner).

### Metrics (per format, aggregated across variance runs)
- `comprehension_pass_rate` — pass rate over comprehension assertions
- `fabrication_rate` — 1 − pass rate over absence assertions
- `drift_detection_rate` — pass rate over drift assertions
- `token_cost` — already measured (F3 = +13–99%; F2 ≈ +30–60 tokens flat)

## Eval family 2 — deterministic extraction robustness (no LLM, pure bash)

Fixture mutations of a design doc: (m1) `## Out of Scope` vs `## Out-of-Scope` spelling —
**a real bug: the approved 2026-05-23 serena design doc uses spaces; the guard at
`hooks/skill-activation-hook.sh:1461` greps the hyphenated form and silently reported the
section missing** — (m2) heading demoted to `###`, (m3) sections reordered, (m4) heading
emoji/decoration. Compare: guard-style heading grep vs 10-line `fm_get` on F2 front-matter.
Metric: extraction success per mutation.

## Decision criteria (FROZEN before first run)

1. **Adopt DocLang handoff** only if F3 beats F1 by ≥15 percentage points absolute on
   `fabrication_rate` OR `drift_detection_rate`, sustained across variance runs, AND
   round-trip introduces zero content errors. Otherwise REJECT (token cost unjustified).
2. **Unpause `artifact-frontmatter`** only if F2 shows no degradation vs F1 (within 5 pp on
   comprehension + fabrication) AND Eval 2 shows front-matter succeeding on ≥3 of 4 mutations
   where heading-grep fails.
3. **Ties / F1 wins both** → markdown stays sole format; decision memory with revival criteria.

## Tasks

- [x] Freeze hypothesis + criteria (this doc)
- [x] Build renderings under `tests/fixtures/format-eval/renderings/` (F1 copy, F2 prepend, F3 docling)
- [x] Author pack `tests/fixtures/format-eval/evals/format-eval.json` (6 scenarios, 34 assertions, all ERE-compile-checked)
- [x] Driver `tests/run-format-evals.sh` (loops matrix → existing runner; Bash 3.2; opt-in env gate)
- [x] Eval 2 fixture test `tests/test-frontmatter-extraction.sh`
- [x] Run Eval 2 — **fm_get 5/5 mutations, guard-grep 2/5; real specimen confirmed** (guard misses the approved 2026-05-23 serena design doc's `## Out of Scope` today)
- [x] Round-trip fidelity check — **F3 FAILS criterion #1's zero-content-error requirement**: design loses `<100ms` budget (angle bracket eaten), postmortem loses 14.8% of words incl. P0/P1 action-item text (table cells). Probe ground-truth facts verified still present in F3, so Eval 1 remains fair.
- [x] Smoke-test Eval 1 wiring (spec-probes × F1, 8/8 PASS)
- [x] Eval 1 full run (3 parallel per-format drivers, variance 3, 54 calls, completed 2026-06-10T20:53Z)
- [x] Aggregate → verdict vs frozen criteria (below)
- [ ] REVIEW → SHIP chain for whatever lands on the branch

## Results (Eval 1, variance 3, 18 reports, 102 assertion-evaluations per format)

| fmt | comprehension | absence (fabrication) | drift detection |
|-----|---------------|----------------------|-----------------|
| F1 markdown        | 54/54 = 100% | 24/24 = 100% (0% fabrication) | 24/24 = 100% |
| F2 md+front-matter | 54/54 = 100% | 24/24 = 100% (0% fabrication) | 24/24 = 100% |
| F3 DocLang         | 54/54 = 100% | 24/24 = 100% (0% fabrication) | 24/24 = 100% |

**Ceiling effect, honestly stated:** at our artifact sizes (3.5–20KB) the session model
answers grounded QA, refuses absent facts, and detects planted drift perfectly in ALL
three formats. The eval cannot rank formats above the ceiling — but it decisively
answers the adoption question: plain markdown is NOT the bottleneck in LLM handoff
quality for our PDLC artifacts. Caveats: variance 3 is modest; ambient (constant)
banner noise; tiktoken token-cost proxy.

## Verdict vs frozen criteria

1. **DocLang: REJECT.** Criterion #1 required ≥15pp improvement on fabrication or
   drift AND zero round-trip content errors. Measured: 0pp delta (F1 already at
   ceiling) and round-trip content LOSS (design: `<100ms` budget dropped; postmortem:
   14.8% of words incl. P0/P1 action items). The "lossless parsing avoids
   hallucinations" premise inverts for born-digital markdown: the conversion is the
   only lossy step, and 0% fabrication was measured on markdown itself. Token cost
   +13–99% buys nothing.
2. **Front-matter: UNPAUSE `artifact-frontmatter`.** Criterion #2 satisfied: F2 shows
   zero degradation (identical 100/100/100) AND Eval 2 shows fm_get 5/5 mutations vs
   guard-grep 2/5, including a confirmed production miss (approved serena design doc).
   Front-matter is additive metadata for deterministic consumers, not a format change.
3. **Markdown stays the sole handoff format** for both humans and LLMs.

## Revival criteria for DocLang (pre-committed)

- Anthropic documents DocLang-native training/comprehension in Claude models → re-run
  this pack (`tests/run-format-evals.sh`) and a harder variant (multi-doc, distractors).
- Real PDF/scan/image inputs enter discovery with logged quality pain → evaluate
  Docling-the-parser (markdown export first); DocLang export only if fidelity loss
  from markdown export is demonstrated on the actual documents.
- md→DocLang converter reaches lossless round-trip on this corpus AND artifact sizes
  grow to where a harder eval differentiates formats.

## Incidental bugs found (branch deliverables)

1. `tests/run-behavioral-evals.sh`: current Claude CLI parses `--disallowedTools` as
   variadic → it swallowed the trailing prompt positional; runner was broken under
   current CLI. Fixed: prompt now passed via stdin. (Caught by smoke test.)
2. `claude -p --bare` fails auth ("Not logged in") under current CLI in nested
   sessions — driver defaults BARE=0 with a dated comment; runner's --bare flag
   unchanged. Constant ambient banner noise across formats keeps ranking valid;
   noted caveat: inner hook banner may spuriously satisfy the `systematic-debugging`
   assertion equally across formats (weakens that probe's discrimination only).
3. Eval 2 real specimen: design-guard `^## Out-of-Scope` grep misses the approved
   serena design doc (`## Out of Scope`, spaces) in production today.

## Out of scope

- Any edit to superpowers plugin files
- Shipping `hooks/lib/frontmatter.sh` or guard changes (gated on criteria #2)
- Back-migration of existing artifacts
- DocLang ingestion of external PDFs (separate, rejected earlier with revival criteria)
