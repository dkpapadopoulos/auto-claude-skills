# Postmortem Template — Built-in Default Schema

Used by POSTMORTEM Step 1 when no project template (`docs/templates/postmortem.md`)
or GitHub template (`.github/ISSUE_TEMPLATE/postmortem.md`) is found.

Ordered for reviewer flow — decisions first, evidence after.

```
## 1. Summary
One sentence in plain language (who was affected, what happened).
Then one paragraph of technical detail.

## 2. Impact
User impact first (who was affected, error count, support tickets, business impact).
Then infrastructure scope (pods, services, nodes, capacity loss).
Include duration: verified start and end timestamps in UTC.

## 3. Action Items
Ordered by priority (P0 first). Each item MUST have a suggested owner and due date.
Items without owners should be flagged: "⚠ Owner needed".
Include: priority, action, type, current state, owner, due date, status.
**Type** classifies how the item reduces future incidents — exactly one of:
- **Detect** — improves time-to-detection for this failure class (alert, SLO, monitoring).
- **Prevent** — stops the root cause from recurring (validation, CI gate, guardrail).
- **Mitigate** — reduces blast radius or speeds recovery when it recurs (runbook, automation, capacity).
A postmortem with several Prevent items and zero Detect items signals an unaddressed detection gap.

## 4. Root Cause & Trigger
Concise explanation of why the incident happened.
Include causal chain diagram if the mechanism has multiple steps.
**Links:** Include verification links after the root cause statement (max 3).
Format: `**Links:** [label](url) · [label](url)` — see references/evidence-links.md.

## 5. Timeline (all timestamps UTC)
Markdown table: timestamp | event | evidence source.
Interleave infrastructure events AND human actions (alerts, notifications, manual interventions).
Must include verified recovery timestamp.
Evidence column should contain clickable links to Logs Explorer, audit logs, or commit URLs where query parameters were captured during investigation.

## 6. Contributing Factors
Ordered by impact (most impactful first, not discovery order).
Each factor: what it is, why it made things worse.
When resource exhaustion or capacity constraints contributed to the incident, include a **Capacity Context** entry:
- Current utilization vs allocatable (node level, at incident time)
- Resource request coverage: actual/requested ratio for key workloads
- HPA scaling ceiling: current replicas vs max, and whether max was reached
- Whether the condition is chronic (weeks of headroom drift) or acute (single event triggered exhaustion)
This prevents "increase resource limits" action items without context on whether the headroom trend is systemic.

**Systemic factors** (CAST — see `references/cast-framing.md`). Each category MUST have a non-empty observation or `N/A — <reason>`. Bare "N/A" blocks Q12 of the completeness gate.
- **Safety Culture:** <observation or `N/A — <reason>`>
- **Communication/Coordination:** <observation or `N/A — <reason>`>
- **Management of Change:** <observation or `N/A — <reason>`>
- **Safety Information System:** <observation or `N/A — <reason>`>
- **Environmental Change:** <observation or `N/A — <reason>`>

## 7. Lessons Learned
What went well, what went wrong, where we got lucky.

**Mental model gaps** (CAST — see `references/cast-framing.md`). One bullet per relevant controller using the shape `<controller> believed <X>; actual was <Y>`. `N/A` acceptable only for single-controller incidents where the controller's model was correct; state the reason.
- `<controller>` believed `<X>`; actual was `<Y>`.
- …

**Hindsight-bias check:** Scan Sections 6–8 for `should have`, `failed to`, `could have easily`, `obviously`, `it was clear that`. Replace with evidence-grounded framing (see `references/cast-framing.md` for replacement patterns) or move the claim to an open question if the supporting evidence is missing.

## 8. Investigation Notes
Hypotheses investigated and ruled out. Each ruled-out hypothesis should include
a `**Links:**` line (max 2) with verification URLs when available.
Confirmed findings should include inline links to source code, config files, or log queries.
Confidence notes (what is confirmed vs inferred).
Open questions remaining.

### Investigation Path (optional appendix)
If the investigation involved hypothesis revisions or completeness gate loop-backs,
offer to include an investigation path. The path has two parts: a decision tree
(the reasoning arc at a glance) and evidence steps (the verification chain).

**Format rules:**
- **Decision tree first:** an indented text tree showing the branching logic.
  ✗ for ruled-out paths (with reason), ✓ for confirmed paths.
  Include recovery, blast radius, and any disproved claims from other investigations.
  A reviewer can read just this tree and understand the full reasoning in 30 seconds.
- **Evidence steps second:** question → decisive evidence → conclusion per step.
  Dead ends: **Ruled out:** lines with evidence source and reason.
  Disconfirming checks: **"prediction" → confirmed/contradicted** with evidence.
  All timestamps explicitly **UTC**.
- Steps may be combined, reordered, or omitted based on what the investigation
  actually required. Number sequentially based on what was done. Do not pad.
- End with a single-sentence **Reviewer takeaway** linked to the top action item.

**Template:**

  **Decision tree:**
  ```
  ├─ [proximate cause found] ([evidence source])
  │  └─ [question: why did this happen?]
  │     ├─ ✗ [ruled-out hypothesis] ([reason])
  │     ├─ ✗ [ruled-out hypothesis] ([reason])
  │     └─ ✓ [confirmed trigger]
  │        └─ [deeper question: why did the trigger occur?]
  │           ├─ ✗ [ruled-out hypothesis] ([reason])
  │           └─ ✓ [confirmed root cause]
  │              [key evidence]
  │              └─ Disconfirming checks: [N/N pass] → ROOT CAUSE CONFIRMED
  ├─ Recovery: [verified duration and mechanism]
  ├─ Blast radius: [scope and ongoing risk]
  └─ Disproved: [claims from other investigations that were contradicted]
  ```

  **Evidence steps:**

  1. **Inventory** — What exists and how is it configured?
     Evidence: [deployment/infrastructure query] → [instance count, distribution, resource config].
     Conclusion: [what the inventory reveals about risk or scope].

  2. **Proximate cause** — What directly caused the user-facing impact?
     Evidence: [error logs, connection logs, HTTP status] → [what broke, when, how many affected].
     Conclusion: [the immediate mechanism].

  3. **Ruled-out triggers** — What did NOT cause this?
     Ruled out: [hypothesis] ([evidence source]: [why excluded]).
     Ruled out: [hypothesis] ([evidence source]: [why excluded]).
     Actual trigger: [what the evidence points to instead].

  4. **Root cause** — Why did the trigger occur?
     Evidence: [infrastructure metrics, system logs] → [what was unhealthy and for how long].
     Deeper: [scheduling/capacity/config data] → [why the unhealthy state existed].
     Conclusion: [the systemic cause].

  5. **Disconfirming checks** — What would disprove this root cause?
     "[testable prediction]" → [confirmed/contradicted] ([evidence]).
     "[testable prediction]" → [confirmed/contradicted] ([evidence]).
     "Explains all symptoms?" → [yes/no, with list if no].

  6. **Recovery** — When was service actually restored?
     Evidence: [recovery indicators] → [verified timestamps UTC].
     Conclusion: [actual duration, recovery mechanism, any surprises].

  7. **Blast radius** — What else was affected or is at risk?
     Evidence: [cross-service/cross-node checks] → [scope of impact].
     Conclusion: [single-service or systemic, ongoing risk if any].

  **Reviewer takeaway:** [One sentence: the most important thing this investigation
  revealed, linked to the top action item.]
```
