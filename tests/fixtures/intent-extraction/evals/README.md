# Intent-extraction behavioral eval (PR2a ship gate)

Red-first quality gate for the intent-extraction DESIGN directive. The directive ships
**only** if it shows measurable intent-capture improvement over brainstorming alone. This
eval is **opt-in and manual** — it spawns `claude -p` and costs API budget. It is NOT part of
CI `tests/run-tests.sh`. Run it before shipping PR2a and record the result below.

## What the gate measures

The directive's payoff is **multi-turn**: it runs a one-question-at-a-time intent pass and,
once the user answers, *converges* on a one-line confirmed intent + an explicit out-of-scope
boundary before brainstorming proposes approaches. So the gate is a **two-turn** A/B:

- **Turn 1** = an underspecified ask (`prompt`).
- **Turn 2** = the user answers with who/why/success/constraints (`followup`), delivered via
  `claude -p --resume <session_id>`. Assertions evaluate the **turn-2 (convergence)** output.

The `followup` deliberately supplies substance **without** the delta vocabulary (no "out of
scope" / "confirmed intent" / "confidence"), so matches reflect the *model's own* framing, not
an echo of the user's words.

### Convergence deltas (assertions on turn 2)

| id | delta | counts toward gate? |
|----|-------|---------------------|
| C1 | states an explicit out-of-scope boundary | **yes** |
| C2 | states a one-line confirmed-intent statement | **yes** |
| C3 | indicates it will persist the confirmed intent (`openspec_state_set_intent`) | **no — sandbox artifact** |

C3 is excluded from the quality verdict: the eval sandboxes the inner agent
(`--disallowedTools Edit,Write,Bash`), so it *cannot run* the persist command and therefore
rarely narrates it. The persistence handoff is the *mechanism*, already covered deterministically
by the hook tests (`openspec_state_set_intent` unit tests + the seeded handoff test in
`tests/test-routing.sh`). Keeping C3 in the quality blend would drag the signal down with a
structural artifact, not a capability gap.

## Mechanism — high-fidelity directive injection

`run-behavioral-evals.sh` injects the skill body from `SKILL_PATH` and does **not** fire the
working-tree hook (a live `claude -p` would fire the *installed* plugin hook, not the edit). Two
injection modes were tried:

1. **Buried** (append the directive to the end of the brainstorming `SKILL.md`): under-measures
   efficacy — the directive competes with brainstorming's dominant "propose 2-3 approaches"
   instruction and is only followed ~1/3 of the time.
2. **Prominent** (`--directive-file`): injects the directive as a standalone
   `<activation_directive>` block **above** the skill guidance — mirroring how the activation
   hook places it in `additionalContext`. This is the faithful representation. **Use this mode.**

Both modes share the **same unmodified brainstorming body** for baseline and treatment; treatment
adds only the directive. Baseline = real brainstorming (the cheapest honest alternative — do not
strawman it with a hand-written stub):

```bash
export BS="$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills/brainstorming/SKILL.md | sort -V | tail -1)"
echo "$BS"   # record the resolved path + version below
```

## Pinned judge

The runner is regex-only (no LLM judge). "Pinned judge" = the pinned inner `claude -p --model
<model>` + the date of the gating run. Record both below.

## Pre-registered safety-stop

If the adversarial subset (`intent-mechanical-noninterview`) shows the directive induces a
multi-question intent interview on a mechanical ask, **HALT the ship** and revise the
suppression / prose before re-running. The developer running the gate may call this stop.

## Never-delete

Scenarios are append-only. Never delete one; deprecate with `deprecated_on: YYYY-MM-DD` + a
one-line rationale in `expected_behavior`.

## Scenarios

| id | role | turns | gate |
|----|------|-------|------|
| `intent-underspecified-converge` | quality A/B | 2 (prompt + followup) | C1 + C2 red→green |
| `intent-underspecified-ask` | single-turn (deprecated for gating) | 1 | retained for history; D1/D3/D4 are multi-turn end-states a single turn can't reach |
| `intent-mechanical-noninterview` | adversarial (hard) | 1 | no intent interview on a mechanical ask |
| `intent-respects-existing-brief` | adversarial (hard) | 1 | builds on brief, no re-elicitation |

## Run commands

```bash
export BS="$(ls -d "$HOME"/.claude/plugins/cache/*/superpowers/*/skills/brainstorming/SKILL.md | sort -V | tail -1)"
PACK=tests/fixtures/intent-extraction/evals/behavioral.json
# directive prose — the SOURCE OF TRUTH is the INTENT EXTRACTION block in
# hooks/skill-activation-hook.sh (Scenario-1 emit branch). Copy it VERBATIM here
# (unescape the bash \" \$ and backticks). If you edit the hook prose, re-paste —
# a stale paste silently tests the wrong text.
DIR=/tmp/intent-directive.txt

# Baseline (expect RED on C1/C2):
BEHAVIORAL_EVALS=1 SKILL_PATH="$BS" tests/run-behavioral-evals.sh --pack "$PACK" \
  --scenario intent-underspecified-converge --variance 5

# Treatment, faithful injection (expect GREEN on C1/C2):
BEHAVIORAL_EVALS=1 SKILL_PATH="$BS" tests/run-behavioral-evals.sh --pack "$PACK" \
  --scenario intent-underspecified-converge --variance 5 --directive-file "$DIR"

# Adversarial (run against treatment; inspect artifact for interview behavior):
BEHAVIORAL_EVALS=1 SKILL_PATH="$BS" tests/run-behavioral-evals.sh --pack "$PACK" \
  --scenario intent-mechanical-noninterview --variance 3 --directive-file "$DIR"
```

## Results

**Model:** `claude-opus-4-8[1m]` · **Baseline body:** superpowers brainstorming `SKILL.md` @ 6.0.3 · **Dates:** 2026-06-26

### The single-turn eval was mis-designed (recorded for history)

First gate used a single-turn scenario (`intent-underspecified-ask`) asserting four deltas. Result:
baseline 0/3 on all four; treatment moved only D2 (confidence) to 40%, D1/D3/D4 stayed at 0%. Reading
the artifacts showed why: the directive runs a **one-question-at-a-time** pass and correctly **stops
after question 1** to await the user (5/5 treatment runs end with a question), so out-of-scope,
deeper-probe, and confirmed-intent **convergence behaviors structurally cannot appear in a single
turn**. The eval was measuring multi-turn end-states in one shot. → rebuilt as the two-turn
`intent-underspecified-converge` scenario above.

### Multi-turn gate — buried vs prominent injection

| delta | baseline | treatment (buried) | treatment (prominent) |
|-------|----------|--------------------|-----------------------|
| C1 out-of-scope | 0/3 (0%) | 1/3 (33%, flaky) | 2/2 ✓ (partial, n=2 — see below) |
| C2 confirmed-intent | 0/3 (0%) | 1/3 (33%, flaky) | 2/2 ✓ |
| C3 persist (excluded) | 0/3 | 0/3 | 0/2 (sandbox artifact) |

The flakiness was an **injection-fidelity artifact**: buried in the skill doc → 1/3; injected
prominently the way the hook does → 2/2 (a run cut short at iter 3 by an API session limit). A full
variance pass at the prominent fidelity follows.

### Gate — prominent injection, variance 5, two directive revisions — 2026-06-26

| delta | baseline 5× | v1 prose 5× | **v2 prose 5× (shipped)** | classification (v2) |
|-------|-------------|-------------|---------------------------|---------------------|
| C1 out-of-scope | 0/5 (0%) | 1/5 (20%) | **5/5 (100%)** | stable |
| C2 confirmed-intent | 0/5 (0%) | 1/5 (20%) | **5/5 (100%)** | stable |
| C3 persist (excluded) | 0/5 | 0/5 | 1/5 (20%) | sandbox artifact |

**v1 prose FAILED** the gate at proper n=5: only 20% convergence (the n=2 "2/2" that looked promising
was sampling noise — inspection confirmed *genuine* non-convergence, the model jumping to "propose
approaches" as brainstorming's default pull won). **v2 prose PASSES decisively:** making convergence an
imperative pre-proposal gate ("do NOT propose approaches… you MUST — BEFORE proposing ANY approach —
emit this convergence block and stop for confirmation") lifted both quality deltas to **5/5 stable**.

**Verdict: the gate PASSES on v2 prose.** Baseline 0/5 → treatment 5/5 (stable) on both out-of-scope and
confirmed-intent is a clear, reliable measurable improvement over brainstorming alone (which never
produces a confirmed-intent lock). C3 (persist) stays at 20% purely because the eval sandboxes Bash so
the model can't run `openspec_state_set_intent` — that path is covered deterministically by the
`set_intent` unit test + the seeded handoff test in `tests/test-routing.sh`. **v2 is the prose shipped in
`hooks/skill-activation-hook.sh`.**

**Lesson (recorded):** small-n eval results lie — the n=2 fidelity pass read 100% but the proper n=5 read
20%. Always run full variance before a ship/park call. And a multi-turn directive cannot be gated by a
single-turn eval.

Example treatment convergence (turn 2):
> *"My confidence is now **high**. Let me lock the intent before proposing approaches.
> **Confirmed intent:** Desktop-notify this plugin's developers within ~1–2s when
> `openspec-guard.sh` blocks their git push… **Out of scope:** email/phone alerts ·
> repeated/nagging popups · non-blocking events."*
