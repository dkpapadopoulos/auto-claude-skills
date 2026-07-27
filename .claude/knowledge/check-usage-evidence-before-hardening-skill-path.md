---
type: convention
title: Check usage evidence before hardening a skill path
description: Before adding gates, preconditions, or workflow steps to a skill, verify the skill actually fires — transcript Skill() invocations and ledger/invocation artifacts; an unused path makes any hardening dead prose.
tags: [skills, triage, usage-evidence, dead-code, yagni]
source: skills/agent-team-execution/SKILL.md:Mode Selection
timestamp: 2026-07-23T21:27:47Z
---

Before investing in hardening or extending a skill path (new preconditions,
coherence gates, prose workflow steps), pull usage evidence first:

    # real Skill() invocations across local session transcripts
    grep -l '"skill"[^,}]*<skill-name>' ~/.claude/projects/<project-dir>/*.jsonl | wc -l
    # durable evidence artifacts
    grep -l "<skill-name>" ~/.claude/.skill-branch-ledger* ~/.claude/.skill-invocation-evidence-* 2>/dev/null

**How it bit (2026-07-23 triage):** after a cross-model debate (Claude + Codex,
both grounded in repo files), the top-ranked improvement was wiring
implementation-drift-check into agent-team-execution's Phase 3 finalization.
Neither model checked usage: agent-team-execution had **zero** real invocations
across all local transcripts (subagent-driven-development: 14 sessions,
executing-plans: 16) — its <3-file-disjoint-groups fallback rule means typical
change sizes never trigger team mode. A human question killed the item in one
turn. Hardening an unused path is dead prose — the same failure mode as the
measured 0/5 uptake of ambient advisory hints.

**Rule:** usage evidence before path-hardening. If the path is unused, PARK the
improvement with revival trigger "first real invocation (transcript or
branch-ledger evidence)" instead of building. Model consensus — even
adversarial cross-model consensus — does not substitute for a ground-truth
usage check.
