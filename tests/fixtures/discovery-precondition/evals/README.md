# Discovery-precondition uptake eval (opt-in)

Measures **uptake**, not presence: does the model actually route a new-feature
DESIGN ask to `product-discovery` FIRST when the discovery check is carried as a
CURRENT-step **PRECONDITION** in the composition context (vs. the old advisory hint)?

Presence is covered deterministically by `tests/test-context.sh`
(`test_precondition_renders_on_current_only`, `test_discovery_precondition_wiring`).
This pack covers the behavior those tests cannot: whether the model obeys it.

## Why this exists (the red baseline)

PR #102 shipped the discovery check as a `discovery-audit-companion` **hint**. A
25-rep uptake eval with real captured hook context measured it at **0/5 uptake and
0/5 acknowledgment** — a hint-removed control was identical, so its causal
contribution was zero (see memory `feedback_advisory_hint_vs_must_directive_uptake`).
The same LEARN pass measured the **step-text embedding at 5/5 uptake, 5/5
no-over-fire**. This feature ships that validated fix; the pack below re-confirms it
against the *actual rendered context* produced by this implementation.

The baseline (old-hint) arm is **not** re-run here — it is the already-measured 0/5
from #102. Reproducing it requires reverting the config and adds cost for a known
result; it is documented as the red baseline this change closes.

## Arms

Each scenario's `prompt` embeds the **real captured** UserPromptSubmit context from
this implementation (`hooks/skill-activation-hook.sh` output for a new-feature DESIGN
prompt, including the CURRENT-step PRECONDITION), then a user message, and asks the
model to state its FIRST action.

- **`precondition-routes-to-discovery`** (arm B) — new feature, no brief. PASS =
  states it will invoke `product-discovery` first, before brainstorming.
- **`brief-exists-no-overfire`** (control) — an approved brief already exists
  (session-state `discovery_path` set). PASS = proceeds to brainstorming/design
  WITHOUT re-invoking `product-discovery` (honors the precondition's brief-exists
  exclusion).

## Run

```bash
# smoke (1 rep/arm)
BEHAVIORAL_EVALS=1 JUDGE_MODEL=claude-sonnet-5 \
  bash tests/run-behavioral-evals.sh --scenario precondition-routes-to-discovery \
  --pack tests/fixtures/discovery-precondition/evals/behavioral.json

# full acceptance (5 reps/arm)
BEHAVIORAL_EVALS=1 JUDGE_MODEL=claude-sonnet-5 \
  bash tests/run-behavioral-evals.sh --scenario precondition-routes-to-discovery \
  --pack tests/fixtures/discovery-precondition/evals/behavioral.json --variance 5
# repeat with --scenario brief-exists-no-overfire
```

## Acceptance

- arm B ≥ 4/5 route-to-discovery-first
- control ≥ 4/5 correct-skip (no over-fire)

If arm B under-routes, escalate per the design's rung 2 (walker-level deterministic
re-anchor: DESIGN + no `discovery_path` → prepend `product-discovery` to the chain).
Do NOT weaken the judge criteria to force a pass.

## Recorded results

- Judge: `claude-sonnet-5` (pinned). Subject: `claude-opus-4-8[1m]`.
- **2026-07-11 (5 reps/arm):**
  - arm B `precondition-routes-to-discovery`: **5/5 (100%, stable)** — routes to
    product-discovery first. Clears ≥4/5.
  - control `brief-exists-no-overfire`: **4/5 (80%, stable)** — clears ≥4/5.
    **Genuine over-fires to product-discovery: 0/5.** The single non-pass was NOT
    an over-fire (the judge noted it was "a different failure mode than an
    over-fire"): the subject surfaced an assumption and asked a clarifying question
    — brainstorming-adjacent — instead of cleanly proceeding into design. The
    property this arm guards (no re-routing to discovery when a brief exists) held
    5/5.
  - Baseline (old `discovery-audit-companion` hint): 0/5 uptake, measured in #102
    LEARN (not re-run here). Delta: 0/5 → 5/5.

### Control-arm eval-fixture note

The first control draft pointed to a discovery brief at a **fake file path**; the
diligent subject halted to flag that the file didn't exist (a fabricated-premise
confound, cf. `.claude/knowledge/behavioral-eval-subject-read-contamination`). The
committed control **inlines the approved brief as given content** (no file lookup),
which isolates the over-fire measurement.
