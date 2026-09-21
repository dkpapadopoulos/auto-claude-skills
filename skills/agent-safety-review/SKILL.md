---
name: agent-safety-review
description: Use when a design or implementation involves autonomous agents, unattended/background operation, private-data access combined with external/untrusted input, or outbound actions (sending data, posting, pushing, API calls) — the lethal-trifecta risk
---

# Agent Safety Review

Architectural risk assessment for designs and implementations that involve autonomous agent behavior. Separate from security-scanner (which runs deterministic static analysis).

## When to Use

During DESIGN phase when the prompt involves autonomous agents, unattended operation, private data processing with external input, or outbound actions. Also co-selects during REVIEW phase when autonomy-related triggers match alongside requesting-code-review.

## Step 1: Assess the Three Fields

For the proposed design or implementation, evaluate each field:

| Field | Question | Examples |
|-------|----------|----------|
| `private_data` | Does the agent access information that should not be shared with all parties? | User email, credentials, internal logs, PII, private repos, API keys, session tokens |
| `untrusted_input` | Can an external party inject instructions the agent will process? | Email content, web pages, user-uploaded files, API responses from third parties, webhook payloads |
| `outbound_action` | Can the agent send data or take actions visible outside its sandbox? | Sending emails, posting to Slack, pushing to git, making API calls, writing to shared filesystems, creating PRs |

For each field, state:
- **Present** — with specific evidence from the design
- **Absent** — with explanation of why
- **Unknown** — flag for further investigation

## Step 2: Classify Risk

| Fields present | Classification | Action |
|---------------|----------------|--------|
| All 3 | **Lethal trifecta** — High risk | Require mitigation before proceeding |
| 2 of 3 | **Elevated risk** | Note which leg is missing. Recommend not adding the third without mitigation. |
| 0-1 | **Standard risk** | No special action required |

## Step 2b: Assess Autonomy–Control Coherence

Independent of the trifecta count above — **this does not change the trifecta
classification**; it adds a separate advisory. Data-flow risk and autonomy risk
are different axes.

State the agent's intended **autonomy level**:

| Rung | Meaning |
|------|---------|
| `advise` | Proposes; a human acts |
| `recommend` | Proposes a specific action; a human approves each one |
| `execute-reversible` | Acts autonomously; effects bounded, observable, easily undone |
| `execute-irreversible · unattended` | Acts autonomously with hard-to-reverse effects, **or** runs recurring/unattended with no per-run human checkpoint |

Then state whether **proportional oversight** is present — *strong* = per-run
approval, HITL checkpoint, manifest+dry-run review, or a bounded/reversible blast
radius; *weak* = none of those.

**Advisory rule:** if the level is `execute-reversible` or higher **AND**
oversight is weak, emit an advisory proportional to the rung (firmer for
`execute-irreversible · unattended`, softer "consider" for `execute-reversible`):
autonomy without proportional control is a liability, not power — recommend
designing in per-run approval, narrowing scope, or making actions reversible.
Stay **silent** when oversight is strong (a reviewed manifest, a required
approval, or reversible/bounded effects already supply the control). This is
guidance, not a veto.

## Step 3: Recommend Mitigation (if lethal trifecta)

The primary mitigation is **blast-radius control** — cutting at least one leg of the trifecta. Improved detection scores are NOT proof of safety.

**Cut private_data:**
- Isolate the agent to a sandbox with no access to sensitive data
- Use synthetic/test data instead of production data
- Limit access to only the specific data needed, not broad access

**Cut untrusted_input:**
- Pre-filter or sanitize external input before the agent processes it
- Use a quarantine boundary: a read-only agent processes untrusted content, extracts structured data, passes only the structured output to the privileged agent
- Restrict input sources to trusted parties only

**Cut outbound_action:**
- Make the agent read-only — it can analyze but not act
- Require human-in-the-loop approval for all outbound actions
- Use a narrowly scoped HITL: auto-approve low-risk actions, require approval for high-risk ones (sending data externally, deleting resources, creating public artifacts)

## Step 3b: Placement check — does the control's region contain the threat?

A control that exists is not a control that applies. For **each** identified risk,
write these down **separately**, then state whether they overlap:

1. **Threat region.** What the threat is, and *which region of the artifact it
   occupies* — which file, which part of that file, which field, which request.
2. **Control region.** Which region the control actually *inspects*. Not what it
   is called or intended to cover — what it reads.
3. **Overlap.** State plainly that region 2 contains region 1. If you cannot say
   that in one sentence, the control does not apply and the risk is unmitigated.

Then ask these two questions, **in this order**:

> 1. **What does this check NOT look at?**
> 2. **Does this check work?**

Answer the first in writing before you consider the second. The first is the
question that finds a control aimed at the wrong region; the second only ever
tests the region the control already inspects, so on its own it certifies a
misplaced check.

### `unvalidated-against`

When the real threat **cannot be exercised** in the environment at hand — the
sensitive data is absent, the account does not exist, the network is
unreachable — record the control as **`unvalidated-against: <threat>`**.

Do **not** report it as holding. Absent evidence is not evidence of absence, and
without this clause the gap stops being visible: "the controls stay as designed"
silently becomes "the controls hold".

### Why this step exists

Measured 2026-09-18. A control was written for a residual risk that had been
correctly identified in a trifecta assessment. It hashed one designated element
of the artifact against a frozen fixture. **The risk lived in a different region
of the same file.** An artifact carrying a real account identifier in a visible
table passed the check and exited 0. Two further bypasses followed: a second
data block under another id, and a remote asset reference that fired during
capture (proven against a local server — 8 requests before the fix, 0 after).

Nine tasks of red-first testing, mutation verification and adversarial probing
ran past it, because **every cell varied the contents of the inspected element
and nothing probed outside it**. The rigor was real and entirely inside the
wrong boundary.

Third property, and the one that makes this durable rather than a one-off: the
sensitive data happened to be absent from the machine, so the placement was
**unfalsifiable** — which is what the `unvalidated-against` clause above exists
to make visible.

## Step 4: Produce Risk Assessment

Output a structured assessment:

```
## Agent Safety Assessment

**Design:** <what is being evaluated>
**Date:** YYYY-MM-DD

### Risk Fields
| Field | Status | Evidence |
|-------|--------|----------|
| private_data | Present/Absent/Unknown | <specific evidence> |
| untrusted_input | Present/Absent/Unknown | <specific evidence> |
| outbound_action | Present/Absent/Unknown | <specific evidence> |

### Classification
**Risk level:** Lethal trifecta / Elevated / Standard
**Autonomy:** <advise | recommend | execute-reversible | execute-irreversible · unattended> · **Oversight:** <strong | weak>
**Autonomy advisory (if flagged):** <proportional recommendation, or "none">

### Placement (per risk)
- Threat region: <where the threat lives>
- Control region: <what the control inspects>
- Overlap: <one sentence, or "NONE — control does not apply">
- Not looked at: <what this check does not read>
- `unvalidated-against`: <threat that could not be exercised here, or "none">

### Mitigation (if required)
**Recommended approach:** <which leg to cut and how>
**Trade-off:** <what capability is reduced by the mitigation>
**Residual risk:** <what remains after mitigation>
```

## Constraints

- This is an architectural review, not a pass/fail gate. The user decides whether to accept the risk.
- Do NOT claim that improved prompt-injection detection scores solve the problem. 97% detection is a failing grade when the 3% leaks private data.
- Do NOT merge this analysis into security-scanner output. Keep architectural risk separate from deterministic code scanning.
- The skill produces an assessment, not a veto. The goal is informed decision-making.
- When the design is an AI/LLM or agent feature, the safety eval cases (injection, escalation, refusal, safety-routing-suppression) MUST be authored and failing (red) **before the behavior is implemented** — compose with `test-driven-development`. Detection added after the behavior exists is not a substitute: a feature that has never failed its safety cases has never been shown to pass them.
