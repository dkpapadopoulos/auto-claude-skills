# Skill Eval Pack Schema

Per-skill eval packs let CI judge whether a skill's `description` (the field the
model reads when deciding to invoke) would correctly activate for realistic
prompts. A separate regex-fixture test covers the deterministic routing path.

## Location

Each skill owns its eval pack:

```
skills/<skill-name>/
├── SKILL.md
└── evals/
    └── evals.json      # trigger-accuracy cases (LLM-judged, CI)
```

Optional regex fixture for the `tests/test-regex-fixtures.sh` runner:

```
tests/fixtures/routing/<skill-name>.txt
```

## Shape: `evals.json`

Array of cases. Each case asks: *"given this prompt, would a model reading the
skill's `description` decide to invoke this skill?"*

```json
[
  {
    "id": "flapping-alerts-positive",
    "query": "Our pager is flooding from the same check flapping every 10 minutes — can we tune this down?",
    "should_trigger": true,
    "note": "canonical alert-fatigue surface"
  },
  {
    "id": "slo-redesign-positive",
    "query": "I want to rework our error budgets and burn-rate alerts for the billing service.",
    "should_trigger": true
  },
  {
    "id": "active-incident-negative",
    "query": "Production is on fire — pods are crashlooping, help me investigate.",
    "should_trigger": false,
    "note": "incident-analysis territory; SKILL.md explicitly excludes"
  }
]
```

**Required fields:** `id`, `query`, `should_trigger`.
**Optional:** `note` (shown in the PR comment column for reviewer context).

## Guidelines

- **5–10 cases per skill** is the sweet spot. Fewer misses edge cases; more gets
  flaky and slow.
- **Mix positive and negative.** At least one-third should be `should_trigger:
  false` cases targeting the skill's explicit out-of-scope boundaries (what the
  SKILL.md says it does NOT do). Specificity matters more than recall for
  routing quality.
- **Quote real prompts when you can.** Synthetic "textbook" prompts under-test
  the description because they echo its exact vocabulary.
- **One sentence per `query`.** Multi-paragraph prompts are too noisy for a
  useful signal.
- **Accuracy threshold:** CI flags skills scoring below 80% overall as needing a
  description rewrite. Don't game this — low scores are useful information.

## CI trigger

Comment `@claude run eval` on the PR, or add the `run-eval` label. Both
triggers are restricted to users with write access to the repo; comments from
external contributors are ignored. Fork-PR heads are refused before checkout
to prevent exposing `CLAUDE_CODE_OAUTH_TOKEN` to untrusted code. See the
SECURITY MODEL comment at the top of `.github/workflows/skill-eval.yml` for
the full threat model.

The workflow (`.github/workflows/skill-eval.yml`):

1. Detects `skills/<name>/` directories changed in the PR diff.
2. For each changed skill with `evals/evals.json`, asks the model to score each
   case using only the skill's `description` from SKILL.md frontmatter.
3. For changed skills without an eval pack, posts a *"skipped — add
   evals/evals.json"* line.
4. Posts a markdown table per skill to the PR, reaping prior eval comments
   first.

The workflow is **non-blocking** — it comments, never fails the check.

**Repository secret required:** `CLAUDE_CODE_OAUTH_TOKEN` must be configured
under repo Settings → Secrets and variables → Actions. Without it the action
step fails and the reap/post steps no-op. Only maintainers with write access
can add the `run-eval` label or trigger the comment path.

## Regex fixtures (complementary, deterministic)

`tests/fixtures/routing/<skill>.txt` gives `tests/test-regex-fixtures.sh` a
zero-cost way to catch regex drift in `config/default-triggers.json`:

```
# alert-hygiene regex fixtures
# Lines starting with '#' are comments.

MATCH: our alerts are flapping and pager is noisy, help tune thresholds
MATCH: review alert policies for fatigue
NO_MATCH: pods are crashlooping investigate now
NO_MATCH: write me a python script
```

The runner looks up `alert-hygiene`'s compiled regex from
`config/default-triggers.json` and asserts each `MATCH` line matches and each
`NO_MATCH` line does not. Runs in the default `bash tests/run-tests.sh` suite.

## Related: behavioral eval packs (`behavioral.json`)

A separate, opt-in pack type judges *skill output*, not routing. It lives
alongside a skill's fixtures (e.g. `tests/fixtures/incident-analysis/evals/behavioral.json`)
and is exercised by `tests/run-behavioral-evals.sh` / `tests/run-eval-pack.sh`
under `BEHAVIORAL_EVALS=1` — see that directory's `README.md` for the full
scenario shape. Two fields relevant here:

- **`assertions[].kind: "judge"`** — instead of a regex `text` field, the
  assertion carries `criteria`: prose scored against the real skill output by
  a pinned judge model, for correctness that can't be reduced to a text match.
- **`"safety": true`** (top-level, per scenario) — marks a scenario as
  hard-gated: any failure of a *gated* assertion in any iteration blocks the
  run in `run-eval-pack.sh`, rather than being averaged into a
  stable/flaky/broken classification. The hard gate applies to gated
  assertions only — an individual assertion may opt out with
  `"gate": false`, in which case it is still measured, classified, and
  baseline-compared, but never gates the run. `absent`-kind invariants
  paired with an `unless` negation guard (see
  `tests/run-behavioral-evals.sh`) are the recommended hard-gate carriers:
  they fail on a true unapproved claim but tolerate halt/negation phrasing
  ("not yet", "awaiting approval") that would otherwise produce a false
  safety block.

This schema is distinct from `evals.json` above (which is trigger-accuracy
only, LLM-judged for routing) — don't conflate the two pack types.
