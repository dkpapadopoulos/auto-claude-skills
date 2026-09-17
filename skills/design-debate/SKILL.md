---
name: design-debate
description: Multi-Agent Debate (MAD) for complex designs — architect, critic and pragmatist who RESPOND TO EACH OTHER, so independence is deliberately not claimed. Use when you want positions challenged and converged. For independent answers with no cross-talk use panel; for ONE other model's opinion use second-opinion.
---

# Design Debate (MAD Pattern)

## Overview

Escalation skill for the DESIGN phase. When brainstorming detects competing architectures, cross-cutting concerns, or high-stakes decisions, this skill orchestrates a Multi-Agent Debate with three perspectives to avoid echo-chamber thinking.

**Participants are SAME-FAMILY and LOCAL.** The architect / critic / pragmatist are
`general-purpose` subagents on this machine. Nothing here leaves the machine and there is
no disclosure preview, because there is nothing to disclose. If a prompt names another
vendor ("have codex and gemini argue this out"), say plainly that this skill debates with
local Claude subagents and offer `panel` or `second-opinion` for an actual cross-vendor
pass — do not silently substitute. Anyone wiring real cross-vendor dispatch in here must
send through `scripts/consult-dispatch.sh`, which refuses without the user's approval of
the exact package; any other path is only observed (by `hooks/outbound-consent-hook.sh`,
advisory, partial coverage), never consent-gated.

**This skill is opt-in.** It only activates when brainstorming explicitly escalates after user approval.

## When to Escalate

The brainstorming skill should consider escalating when it detects:

| Signal | Example |
|--------|---------|
| Multiple competing architectures | "We could use microservices or a monolith" |
| Cross-cutting concerns | Auth + data + API all affected |
| High-stakes decisions | "This will be hard to change later" |
| User explicitly requests debate | "I want different perspectives on this" |
| Ambiguity after 3+ questions | Still unclear on approach after extended exploration |

**Always ask the user first:** "This has competing approaches. Want me to run a design debate with multiple perspectives?"

## Team Composition

| Teammate | Role | Lens |
|----------|------|------|
| `architect` | Lead designer | Proposes architecture, defends trade-offs |
| `critic` | Devil's advocate | Attacks assumptions, finds blind spots, proposes alternatives |
| `pragmatist` | Implementation realist | Evaluates feasibility, YAGNI, timeline, complexity cost |

## Debate Protocol

```
1. TeamCreate("design-debate")

2. Share context with all teammates:
   - Problem statement
   - Constraints identified during brainstorming
   - Options explored so far
   - User preferences expressed

3. Round 1 (parallel):
   - subagent_type: "general-purpose"
   - architect: Proposes approach with reasoning
   - critic: Identifies blind spots and alternatives
   - pragmatist: Evaluates feasibility and complexity cost

4. Round 2 (parallel):
   - Each responds to the others' positions
   - Converge toward consensus or clearly articulated trade-offs

5. Lead synthesizes:
   - Present recommendation with dissenting views noted
   - Highlight unresolved trade-offs

6. User decides:
   - Approve → TeamDelete, write design doc
   - Reject → another round or manual override
```

### Constraints

- **2 rounds maximum** — prevents runaway token burn
- **Opt-in only** — brainstorming asks user before escalating
- **Ephemeral team** — created and destroyed within DESIGN phase
- **Output is a design doc** — `docs/plans/YYYY-MM-DD-*-design.md`

## Communication Contract

All inter-agent messages use plain text via SendMessage. No structured JSON.

```
POSITION: [propose | critique | evaluate]
Stance: Use event sourcing for audit trail
Reasoning: Provides immutable history, enables replay, fits compliance requirements
Risks: complexity, learning curve, storage growth
Confidence: high | medium | low
```

## Spawn Prompts

### Architect
```
You are the architect in a design debate. Your job is to propose the best architecture for the problem and defend your trade-offs.

Context: {problem_statement}
Constraints: {constraints}
Options explored: {options}

Propose your recommended architecture using the plain-text POSITION format. Be specific about components, data flow, and integration points.
```

### Critic
```
You are the critic in a design debate. Your job is to attack assumptions, find blind spots, and propose alternatives the architect may have missed.

Context: {problem_statement}
Architect's proposal: {architect_position}

Challenge the proposal using the plain-text POSITION format. Focus on: hidden assumptions, failure modes, scaling issues, maintenance burden, and alternative approaches.
```

### Pragmatist
```
You are the pragmatist in a design debate. Your job is to evaluate feasibility, complexity cost, and whether the proposed approach is the simplest thing that could work.

Context: {problem_statement}
Architect's proposal: {architect_position}
Critic's challenges: {critic_position}

Evaluate using the plain-text POSITION format. Focus on: implementation timeline, team skill requirements, YAGNI violations, incremental delivery options, and operational complexity.
```

## Output

**Check session preset first.** Read `~/.claude/skill-config.json` or check the activation context for the active preset. If the preset has `openspec_first: true` (e.g., `spec-driven`), use the spec-driven mode below. Otherwise, use solo mode.

### Spec-driven mode (preset: `spec-driven`)

After the debate, create `openspec/changes/<topic>/` (committed, visible to teammates):

1. `openspec/changes/<topic>/proposal.md`:
   - **Why** — problem statement
   - **What Changes** — summary of the decision
   - **Capabilities** — Added/Modified capabilities this change touches
   - **Impact** — affected code, APIs, dependencies

2. `openspec/changes/<topic>/design.md`:
   - **Architecture** — consensus or lead's recommendation
   - **Dissenting views** — what the critic and pragmatist flagged
   - **Trade-offs** — what we're accepting
   - **Decisions & Trade-offs** — rejected alternatives and rationale

3. `openspec/changes/<topic>/specs/<capability>/spec.md`:
   - **Acceptance Scenarios** — 2-4 GIVEN/WHEN/THEN scenarios defining success
   - Use RFC 2119 keywords (MUST, SHOULD, MAY) in UPPERCASE

**Capability taxonomy inference (before deciding on `<capability>`):**

First enumerate existing capabilities: `ls openspec/specs/`. Then apply this heuristic:

1. **Noun-family match** — core domain noun matches an existing capability? → **prefer extending** that capability.
2. **Subsystem overlap** — touches code paths already owned by an existing capability? → **prefer extending** that capability.
3. **Genuinely new** — no match? Auto-create `openspec/specs/<new-capability>/`.

When two existing capabilities look equally applicable, **ask the user** — do not guess.

When creating a new capability, emit a visible warning:
> ⚠️ NEW CAPABILITY: This change introduces capability `<new-capability>`. Confirm the taxonomy is correct before archive. Existing capabilities considered and rejected: `<list>`.

**Bias:** err toward fewer, coarser capabilities. Micro-capabilities fragment review routing; a single capability with multiple requirements scales better.

### Solo mode (default)

After the debate, synthesize into a design document at `docs/plans/YYYY-MM-DD-{topic}-design.md` containing:

1. **Problem statement** — what we're solving
2. **Capabilities affected** — every subsystem/module this touches
3. **Explicit out-of-scope** — what this change does NOT do
4. **Recommended approach** — the consensus or lead's recommendation
5. **Dissenting views** — what the critic and pragmatist flagged
6. **Trade-offs** — what we're accepting
7. **Acceptance scenarios** — 2-4 GIVEN/WHEN/THEN scenarios defining success
8. **Decision** — what the user approved

**Persistence:** This artifact is the canonical design intent. It will be:
- Read by `writing-plans` to carry acceptance scenarios into the plan
- Read by `agent-team-review` for spec compliance checking
- Compared against as-built output by `openspec-ship` at archive time
- Archived to `docs/plans/archive/` when the feature ships

Then return to the brainstorming skill's sequential flow → writing-plans.
