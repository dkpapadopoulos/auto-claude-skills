# Design: Format Handoff Eval

## Architecture

Three-layer reuse of existing eval infrastructure — no new runner was built:

1. **Renderings (fixtures):** 4 real PDLC artifacts × 3 formats. F1 = original markdown;
   F2 = F1 with a flat YAML front-matter block prepended (schema from the paused
   `artifact-frontmatter` design); F3 = DocLang XML via docling 2.98.0
   `export_to_doclang()`. Committed as fixtures so re-runs need no docling install.
2. **Pack:** one probe scenario per artifact (4 comprehension probes with ground-truth
   regexes + 2 absence probes whose only correct answer is "not specified in the
   document") plus 2 drift scenarios (planted implementation divergences). Assertion kind
   is encoded as a `[tag]` prefix in the description field — the runner's schema is
   unchanged.
3. **Driver:** `tests/run-format-evals.sh` pairs `SKILL_PATH=<rendering>` with each
   scenario and delegates to `tests/run-behavioral-evals.sh --variance N`; per-format
   `ARTIFACTS_DIR` isolates per-iteration artifact files so per-format drivers can run concurrently.
   Aggregation `awk`s the variance-report markdown tables.

The constant `<skill_guidance>` wrapper and ambient banner noise are identical across
formats, so relative ranking is internally valid even without `--bare`.

## Dependencies

- No new runtime dependencies. docling (Python venv, offline) produced the F3 fixtures.
- Inner runs require an authenticated `claude` CLI and `BEHAVIORAL_EVALS=1` (cost gate).

## Decisions & Trade-offs

- **Reuse runner vs purpose-built harness:** reused. The `<skill_guidance>` framing is
  semantically odd for document QA but constant across formats; a purpose-built harness
  would re-derive variance/reporting for no ranking benefit.
- **Prompt via stdin (runner fix):** chosen over comma-joining `--disallowedTools` (still
  swallowed — the flag is variadic and eats any following positional) and over reordering
  args (fragile against future variadic flags).
- **`--bare` disabled by default in driver:** `claude -p --bare` fails auth ("Not logged
  in") under the current CLI in nested sessions. Documented with a dated comment;
  runner's `--bare` flag retained for when the CLI fixes it.
- **Frozen criteria before first run:** adoption thresholds (≥15pp DocLang quality edge +
  zero content errors; front-matter no-degradation + extraction win) were committed to
  the hypothesis doc before any `claude -p` call, per race-before-debate discipline.
- **Ceiling effect accepted:** all formats hit 100%; the eval cannot rank above the
  ceiling but decisively shows markdown is not the handoff bottleneck at our artifact
  sizes. A harder eval (multi-doc, distractors) is listed as a DocLang revival condition,
  not built now (YAGNI).

## Implementation Notes (synced at ship time)

Retrospective change — created at SHIP time from as-built code. Findings beyond the
original brainstorm: (1) the runner was completely broken under the current CLI
(variadic `--disallowedTools`); (2) `--bare` auth failure; (3) the real-specimen
guard miss (`## Out of Scope` vs `^## Out-of-Scope`) found while building Eval 2.
