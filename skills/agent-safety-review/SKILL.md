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
