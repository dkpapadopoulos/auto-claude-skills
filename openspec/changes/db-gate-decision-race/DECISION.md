# db-gate-race — Decision

Generated: 2026-07-03T07:58:30Z

## Per-arm results

| arm | detection_rate | false_positive_rate | score | n_defect_assertions | n_clean_assertions |
|---|---|---|---|---|---|
| A0 | 0.9500 | 0.1000 | 0.8500 | 20 | 8 |
| B1 | 0.9294 | 0.0000 | 0.9294 | 17 | 0 |
| B2 | 0.0000 | 0.0000 | 0.0000 | 0 | 0 |

score(v) = detection_rate(v) - false_positive_rate(v).

## Frozen decision rule

- DET_MARGIN = 0.20 (variant must beat A0 detection by >= 20pp)
- FP_CEIL = 0.10 (variant false-positive must be <= 10pp, INCLUSIVE)
- TIE = 0.10 (|score(B1)-score(B2)| < 10pp => point-don't-own tiebreak => ship-B1)
- A variant "clears the bar" iff (det_variant - det_A0) >= DET_MARGIN AND fp_variant <= FP_CEIL.
- If neither B1 nor B2 clears -> park.
- If exactly one clears -> ship that one.
- If both clear: ship-B1 if |score(B1)-score(B2)| < TIE, else ship whichever score is higher.

## Safety-stop note

A full statistical overlap test between arms is out of scope for this
deterministic scorer. The n_defect_assertions / n_clean_assertions
columns above are a cheap spread indicator only (sample size per arm).
The human/controller applies the safety-stop judgment before acting on
the verdict below.

## Verdict

`park`

---

## FINAL VERDICT: PARK (gate redundant) — by frozen-rule foreclosure

**Decided on the complete A0 arm; race stopped early by design once the verdict became
mathematically determined (avoids ~200 confirmatory inner calls).**

| Arm | detection | false-positive | n_defect | n_clean | status |
|-----|-----------|----------------|----------|---------|--------|
| A0 (bare REVIEW)          | **0.95** | 0.10 | 20 | 8 | COMPLETE |
| B1 (external-content gate)| 0.93 | 0.00 | 17 | 0 | partial (corroborating) |
| B2 (owned-checklist gate) | — | — | 0 | 0 | not run (immaterial) |

**Why the verdict is already final.** The frozen rule (pre-registered in design.md, never
altered) ships a gate only if it beats A0 by **≥20pp detection at ≤10pp FP**. A0's COMPLETE
detection is **0.95**, so any gate would need det ≥ **1.15** — above the 1.0 ceiling.
**No arm can clear the bar, regardless of B1/B2's remaining scores.** B1's partial 0.93
(near-ceiling, below A0) corroborates. Verdict: **PARK**.

**What this measures (the objective conclusion the eval was built to reach):** a general
strong REVIEW-phase reviewer already catches ~95% of held-out DB defects across all five
taxa — including the subtle `-02/-03/-04` variants — at a 10% false-positive rate, with
**no DB-specific gate**. A dedicated DB-review phase gate adds no measurable detection value
under our PDLC. This confirms the original opportunistic-eval discipline (GitNexus /
cross-LLM / Miora lineage): do not add the gate.

**Honest caveats (do not overclaim):**
- B2 (owned checklist) detection was not directly measured. It is immaterial to the verdict:
  the +20pp bar is unreachable from A0=0.95 by any arm. If the rule were reframed around
  false-positive reduction instead of detection, A0's fp=0.10 still leaves little headroom
  and the pre-registered rule is detection-based — reframing post-hoc would violate the freeze.
- A0=0.95 is on THIS corpus (20 cross-model, held-out, blind-to-B2 defects; obvious→moderate
  difficulty). A materially harder corpus (deeply obfuscated defects) could lower A0 and
  reopen headroom — that is the revival trigger below.
- Measurement validity depended on the structured-verdict fix (free-text regex gave invalid
  fp=1.0; the machine `DEFECTS:` line fixed it — see Pilot round 2).

**Revival trigger.** Re-run the race (resume B1/B2 to completion, or author a harder corpus)
if a future baseline reviewer is shown to detect <0.80 of DB defects — only then does a gate
have ≥20pp of headroom to justify itself. Until then: **park; point DB-heavy users at
`npx skills add planetscale/database-skills` (coexists cleanly).**
