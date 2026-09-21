# Design-seed pilot — result

Adjudicated under the rules frozen in `pilot/HASHES.md` and the "Pilot pre-registration
— 2026-09-18" section of `design.md`, applied as written. The unblinding happened after
both judge responses were recorded.

## Outcome

**Pre-registered outcome 1 on the screen comparison, and outcome 5 on the process gates.**
Both arms rendered, both judges favoured the same artifact, and one process gate failed —
which the registration requires be reported separately rather than dropping the run.

Unblinded: `artifact-a` = arm C (control), `artifact-b` = arm S (seeded). Mapping written
2026-09-20T20:41:19Z, before anything was renamed.

## The claim this licenses, in the pre-registered wording

> On this task, fixture, model configuration and resource cap, the seeded-adoption run
> received a higher blinded rubric score than the comparator run. This single pair does
> not distinguish a repeatable workflow advantage from generation variation.

The registration's wording continues "and the required process gates were satisfied."
**They were not** — criterion (a) failed — so that clause is struck rather than asserted,
and the failure is reported below.

Measurement dependence, stated as part of the claim rather than as a footnote: the
procedure did not exercise arm S's declared dark theme, and arm S did not satisfy the
adaptation-documentation gate.

## Scores

Two fresh framing-free consultations to `codex`, presentation order reversed, each
scoring both artifacts per dimension before any comparative verdict.

| | arm C (artifact-a) | arm S (artifact-b) |
|---|---|---|
| judge 1 (C shown first) | 20/32 | **26/32** |
| judge 2 (S shown first) | 20/32 | **25/32** |

Order reversal moved arm S by one point and arm C not at all, so the verdict is not an
artefact of presentation order. Both judges independently named **R7** — distinguishing
an explicitly empty collection from an absent section — as the largest difference, and
both flagged that **neither** artifact implements the host repo's declared numeric
precision policy (R1: 2/4 for both, in both calls).

Per-dimension detail is in `judge-1.md` and `judge-2.md` verbatim.

Both judges confirmed they viewed the supplied renders. Asked after scoring, both
reported forming no impression of either artifact's origin.

## Process gates, scored separately

**(b) Freeze boundary — PASS.** `design/` was committed at `1714a14` before arm S began;
`git status --porcelain design/` is empty afterwards. No `design/` edit followed.

**(a) Adaptation — FAIL.** Arm S recorded neither an adaptation nor an explicit "no
justified adaptation needed". Two readings of the criterion are available and the frozen
wording does not settle which was intended — an obligation the protocol never
communicated, or a test of whether documentation appears unprompted. The gate fails under
either. The absence does not distinguish absent adaptation *reasoning* from absent
*reporting*. See `arm-consumption.md`.

**(c) Contract delta — both arms produced one.** Assessed against the frozen
`advance-disclosures.md`, where restating a disclosed gap scores zero:

| | arm C | arm S |
|---|---|---|
| entries | 9 | 10 |
| restating a frozen disclosure (score zero) | 1 (`symbol` empty) | 2 (`symbol` empty; `integrity_evidence` absent) |
| labelled with what surfaced the need | 2 of 9 | **10 of 10** |
| substantiated `screen-discovered` | ~0 | 7 |

Arm C's entries are well-formed on the first three required parts — screen behaviour,
example payload, testable acceptance criterion — and its unlabelled entries are not
thereby worthless; they simply cannot be *counted* as screen-discovered, because the
criterion states a self-label is not evidence and silence is not a label. Arm C's one
explicit "Discovered" label is attached to the empty-`symbol` gap, which the frozen
disclosures already name, so it scores zero by the stated rule.

This is a difference in **documentation discipline**, not a demonstration that arm S
understood the data better. Both arms found the same core gaps (FX rate, price as-of,
missing `current` metrics, currency on the portfolio total).

## Consumption

| | arm C | arm S |
|---|---|---|
| tool calls | 44 / 60 | 24 / 60 |
| wall clock | 853s / 2700s | 1058s / 2700s |
| skill invocations (observed) | 0 | 0 |
| stop reason | completed | completed |

Neither hit a cap, so neither submitted work-in-progress.

## Frozen apparatus this was measured with

| artifact | sha256 (first 16) |
|---|---|
| `pilot/rubric.md` | `62f0b5351a163b7c` |
| `pilot/brief.md` | `165924c0014e6b9b` |
| `pilot/budget.md` | `8ab5d14392798d60` |
| `pilot/advance-disclosures.md` | `74f4cfddb917504e` |
| `scripts/pilot-egress-check.sh` | `863bf5d26353173d` |
| `scripts/pilot-capture.sh` | `1d8feccb444e2a3b` |
| `.claude/hooks/pilot-arm-deny.py` | `9172e24fdb5026b7` |
| `review_report_envelope.json` | `c4c7dcd6c99ae3f2` |

Base commits: auto-claude-skills `design-seed-pilot-impl`, Dion `a6475eb`.

## What this does not establish

- **How often arm S wins.** n=1 per arm. One pair.
- **That the seed's rules, rather than the workflow, caused the difference.** The
  treatment is the whole first-use workflow, and this design cannot separate its parts.
- **That any adaptation improved anything.** Arm S made no adaptation to `design/`.
- **Anything about dark-theme quality, for either artifact.** The capture procedure
  recognises `prefers-color-scheme` and arm S's dark theme is gated on `data-theme`, so
  its dark appearance was never exercised. Arm C declares no dark theme. This is a
  permanent gap in this run; neither judging nor source inspection repairs it.
- **That the arms were treated identically.** They were not, by design: arm S received
  the seed. Brief, fixture, model, cap and tool access were matched; the seed package is
  the intended difference.
- **That two judges agreeing is corroboration.** Two calls to one model with reversed
  order measure order sensitivity and some judging variance. They are not independent
  perspectives, they share systematic biases, and they add no runs.
- **That adaptation assessment worked.** Criterion (a) was uncommunicable or unmet; either
  way this run did not assess it.

## Instrument defects found by running it

Recorded because a pilot that only reports its result hides what it cost to get one.

1. **Criterion (a) may be uncommunicable.** It asks arm S to produce an artifact the
   framing-free brief forbids requesting. Either the criterion or the framing rule needs
   to change before a second run.
2. **The capture procedure recognises one theme mechanism.** A future protocol needs an
   implementation-independent rule for reaching theme states, or an explicit requirement
   that dark mode respond to OS preference.
3. **The arms' own gate cannot pass from inside an arm worktree.**
   `TestNormalSessionIsUntouched` asserts the deny hook is inert at cwd, but the hook
   matches any path component `pilot-arm-*` and the arms' cwd is exactly that. Symmetric
   and harness-caused; it cost both arms a clean gate run.

## What licensing follows

The registration permits this result to license promoting the **method** — adopting a
seed as a first-use workflow — and explicitly never the **default preset**. Nothing here
supports a claim that the shipped tokens are good, only that on this one task the seeded
run scored higher against a rubric that deliberately excludes resemblance to the seed.
