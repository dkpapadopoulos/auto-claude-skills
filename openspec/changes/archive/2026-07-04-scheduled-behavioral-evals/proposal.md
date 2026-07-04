# Proposal: Scheduled LLM-Judged Behavioral Evals

## Why

The behavioral eval layer is the weakest link relative to the deterministic layer (~40:1 ratio). `tests/run-behavioral-evals.sh` is opt-in (`BEHAVIORAL_EVALS=1`), runs one scenario at a time, judges only by regex/tool-call assertions, and never runs in CI. For a plugin whose product IS model behavior, there is no continuous signal for the "routed correctly but behaved wrong" regression class. A skill-body edit that degrades incident-analysis behavior would today only be caught if someone hand-runs the pack.

## What Changes

1. **`judge` assertion kind** in `tests/run-behavioral-evals.sh`: a pinned judge model (`claude -p`, sandboxed, no tools) scores the subject's output against a per-assertion rubric, returning strict JSON `{"verdict": "pass"|"fail", "reason": ...}`. Regex assertions remain the deterministic floor; judge assertions cover semantic criteria regex cannot express. Judge output is retried once on parse failure, then recorded as FAIL with detail `judge-unparseable` (loud, never silently green).
2. **Pack-level runner** `tests/run-eval-pack.sh`: loops every scenario in a behavioral pack with `--variance N` (default 3), aggregates per-assertion pass rates from the per-iteration JSON artifacts, classifies (stable ≥90% / flaky 50–89% / broken <50%), compares against a committed baseline, and exits non-zero on regression. Scenarios tagged `"safety": true` are hard pass/fail gates: any failed iteration is a regression, never averaged.
3. **Committed baseline** `tests/baselines/incident-analysis-behavioral.baseline.json` + `--update-baseline` flow. Never-delete discipline: a baseline scenario missing from the pack (without an explicit baseline update in the same change) is a tooling error, not a silent pass.
4. **Scheduled workflow** `.github/workflows/behavioral-evals.yml`: weekly cron + `workflow_dispatch`, main-branch-only (no PR/fork surface), pinned CLI version, runs the pack runner, publishes `$GITHUB_STEP_SUMMARY`, uploads artifacts, and creates/updates a single tracking issue on regression. Advisory: it cannot block merges.
5. **Judge assertions + safety tags for the incident-analysis pack**: `safety: true` on the three injection/HITL scenarios; 3–5 judge assertions on scenarios where regex is known-brittle (evidence synthesis, attribution rigor), each validated red-first against a crafted bad transcript.

## Capabilities

### Modified
- `behavioral-evaluation` — extends the existing runner (judge kind, safety tag) and adds pack-level orchestration, baselines, and scheduled CI execution.

### Added
- none

## Impact

- `tests/run-behavioral-evals.sh` (judge kind, safety tag pass-through)
- `tests/run-eval-pack.sh` (new)
- `tests/baselines/` (new, committed)
- `tests/fixtures/incident-analysis/evals/behavioral.json` (judge assertions, safety tags)
- `.github/workflows/behavioral-evals.yml` (new)
- `tests/test-run-behavioral-evals.sh`, new `tests/test-run-eval-pack.sh`, `tests/test-eval-pack-schema.sh` (deterministic coverage via mock-claude)
- `docs/eval-pack-schema.md` (schema additions)
- Weekly token cost: ~42 subject runs + ~15 judge calls per run (incident-analysis, variance 3)
- Not: routing config, hooks, merge gates, alert-hygiene pack (fast-follow)
