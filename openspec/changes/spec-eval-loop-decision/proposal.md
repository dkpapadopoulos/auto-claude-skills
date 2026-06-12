# Proposal: spec→eval loop — decision record

## Why

Deferred from PR #55's harness/context-management adoption wave as candidate 3 ("wire OpenSpec acceptance scenarios into the behavioral-evaluation runner as a test oracle"). Resolved here via a 3-perspective design debate (architect/critic/pragmatist, 2 rounds) plus an independent Codex external review. The debate's job was to answer the user's two framing questions: **what value would closing the loop deliver, and can we test it?**

## What Changes

**Rejected (no build):**
- **B — NL→assertion generation** (LLM/rules translate a scenario's `THEN` prose into a `kind:text` regex / `kind:tool_call` assertion). Dispositive evidence: only **62 of 272 `THEN` clauses (~23%)** are mechanically parseable; the repo has a documented history of brittle auto-regex (5 dead `.*?` patterns shipped in PR #41; markdown-distance grep failures in the format eval). Generated assertions would be *more* over-permissive than hand-authored ones, and would pull a non-deterministic LLM check toward the deterministic CI gate.
- **C — constrain scenario format** so `THEN` is a machine-parseable assertion DSL. Touches all 387 scenarios across 14 committed specs (teammate-visible churn in spec-driven mode) and destroys the human-readability that makes GIVEN/WHEN/THEN reviewable. Premature; only B would need it.

**Approved and built (user greenlit "backfills + coverage report"):**
- **A — `scripts/scenario-coverage.sh`**: deterministic, advisory, fail-open coverage report. For each `openspec/specs/<cap>/spec.md` where a runnable `skills/<cap>/SKILL.md` exists AND the spec has ≥3 probabilistic-verb `THEN` clauses, it reports whether a behavioral execution pack (`tests/fixtures/<cap>/evals/behavioral.json` or `…/<cap>/behavioral.json`) exists. It reports **linkage existence, not scenario-level percentages** (scenarios have no stable IDs; faking a percentage was the over-precision the debate rejected). Exits 0 in advisory mode; `--strict` exits 1 on an uncovered gap for opt-in CI. Logic pinned by `tests/test-scenario-coverage.sh` (15 assertions, controlled temp-root fixture).
- **Two pack backfills**: `tests/fixtures/security-scanner/evals/behavioral.json` (4 cases: no-tools LLM fallback, partial-tools gap-noting, opengrep-preference, bounded fix-rescan) and `tests/fixtures/incident-trend-analyzer/evals/behavioral.json` (4 cases: failure-mode synonym grouping, <3 insufficient-corpus, MTTR computation, service-name confidence).

**Correction (found during the build):** the decision-record's draft pack counts conflated two pack *types*. `evals.json` (trigger-accuracy, LLM-judged invocation) is distinct from `behavioral.json` (skill-execution, consumed by `run-behavioral-evals.sh`). Behavioral *execution* packs existed for only **three** skills (`serena`, `incident-analysis`, `supply-chain-investigation`) — `alert-hygiene`'s pack is `evals.json` (trigger), not behavioral. This makes the execution-coverage gap slightly larger than the draft implied.

**Surfaced-but-deferred (the report's first run earned its keep):** running the new report flagged **two more** uncovered skill-execution capabilities the user did not name — `alert-hygiene` (7 probabilistic THENs, no behavioral pack) and `unified-context-stack` (31, no pack). These are recorded as known gaps for opportunistic backfill; `unified-context-stack` in particular needs human triage (some of its 31 may be deterministic tier-selection, i.e. the heuristic may slightly over-flag).

## Capabilities

- **Modified:** `behavioral-evaluation` — gains an advisory behavioral-pack coverage report (ADDED requirement in `specs/behavioral-evaluation/spec.md`) plus two backfilled execution packs.

## Impact

- New `scripts/scenario-coverage.sh` (~110 LOC, Bash 3.2, fail-open, lives in `scripts/` so it is NOT run by the default `tests/run-tests.sh` suite; intended for the opt-in `BEHAVIORAL_EVALS=1` CI path or manual `--strict` use).
- New `tests/test-scenario-coverage.sh` (glob-discovered by the default suite; validates the report's classification + fail-open + strict logic against a controlled temp-root fixture — does not gate on live repo coverage).
- New `tests/fixtures/security-scanner/evals/behavioral.json` and `tests/fixtures/incident-trend-analyzer/evals/behavioral.json` (4 cases each; schema-valid, ERE-compiling; behavioral validation runs under opt-in `BEHAVIORAL_EVALS=1`, like every existing pack).
- B and C remain rejected; no NL→assertion generator, no format constraint, no scenario-format migration, no `scenario_id` schema field (deferred — contract-without-consumer).
