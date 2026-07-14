# Design: composition-uptake-baseline

## Architecture

Mirrors the shipped discovery-precondition eval (PR #104 pattern) end to end:
self-contained prompts that embed a production-shaped SKILL ACTIVATION block
(composition chain with [DONE]/[CURRENT]/[NEXT] markers, mandatory eval line,
IMPORTANT continuation directive) followed by a task framing ("state what you
will do FIRST — name the specific Skill") and a user message. One judge
assertion per arm with PASS/FAIL criteria written against named behaviors,
matching approval-and-refusal families where relevant (arm 2 passes on any
route-through-review response, not one phrasing).

Measurement stack:
- Runner: existing `tests/run-behavioral-evals.sh` (opt-in, claude -p
  subjects, judge kind pinned per repo convention). Smoke = 1 call on arm 1
  before any full run (harness-gotchas memory).
- Baseline artifact: `tests/baselines/composition-uptake.baseline.json`
  `{judge_model, date, reps, arms:[{id, pass, total}]}` — same family as the
  two existing baselines.
- Deterministic CI layer is the STRUCTURE test only (pack shape, marker
  presence, unique ids, pinned judge) — presence-not-quality, the same
  deliberate bar as the fixture/content done-gates.

## Trade-offs

- **Real-environment measurement vs clean-room:** subjects run with repo cwd,
  so CLAUDE.md and skills are readable and could reinforce the directives.
  Deliberate: the quantity of interest is uptake in the DEPLOYED environment
  (directive + surrounding context together), not the directive's isolated
  persuasive power. A clean-room arm is a documented possible extension, not
  built (would require the cwd-isolation harness from the
  subject-read-contamination memory).
- **Informational, not gating:** run-to-run variance is unmeasured; a 5-rep
  baseline cannot gate without lying (small-n memory). Revival criterion for
  gating: two independent full runs whose per-arm rates differ by <=1/5,
  plus a pre-registered threshold.
- **Four arms, not more:** covers the audit's uptake question (does the
  model follow CURRENT-step, resist skip pressure, honor the continuation
  directive) plus one over-fire control. More arms = more cost per run with
  diminishing information; extend when a specific routing change needs it.

## Dissenting views

- The audit's tests-explorer suggested gating CI on uptake. Rejected here
  (variance unknown; probabilistic gate in CI is flake-by-design until the
  revival criterion is met) — consistent with the scheduled-behavioral-evals
  design, which runs packs on a schedule rather than per-PR.

## Decisions

1. Judge model pinned to `claude-sonnet-5` (matches discovery-precondition
   and scheduled-evals precedent); recorded in the baseline artifact.
2. Never-delete: arms are never removed, only deprecated with a dated
   rationale in the README (eval-strategy convention).
3. Trifecta: none (local fixtures, opt-in local runs, no outbound actions);
   no agent-safety-review needed.
