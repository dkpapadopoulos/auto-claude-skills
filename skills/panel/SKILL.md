---
name: panel
description: Use to get independent perspectives on one prompt from multiple models — default roster is the strongest available Claude model plus Codex. Opt-in, phase-agnostic; pairs with synthesize for the merge.
---

# Panel

Adapted from patforna/core-skills (MIT).

## Preconditions

- Run from the main thread (subagents cannot spawn subagents).
- The prompt argument is mandatory. If it is missing, fail loudly and ask — never inferred.
- Phase-agnostic by contract: invocable during DESIGN, PLAN, REVIEW, or outside the SDLC chain. Never a required chain step.

## Step 1: Expand Skill References (single level)

If the prompt explicitly invokes a skill (`/name` form only — not bare names in prose), inline that skill's SKILL.md, clearly fenced, after the instruction. Expansion is single level: never recurse into references found inside an expanded body. Expanded bodies COUNT as outbound content for Step 3's preview.

## Step 2: Append the Anti-Sycophancy Block

Append verbatim to the prompt:

> Answer directly and honestly. Do not hedge or soften to be agreeable. If your honest answer differs substantively from what the prompt seems to expect, give that one.

## Step 3: Disclosure Preview (before any dispatch)

Cross-family dispatch sends content off this machine. Before dispatching, state the destination provider (e.g. Codex / OpenAI) and show what will be sent — the prompt, any expanded skill bodies, and nothing else (least-data: never whole-session context). Run secret detection (gitleaks) over the outbound payload when available; announce when it is not available. Proceed only with the user's go-ahead from the panel invocation itself or an explicit confirmation if the payload grew beyond what they asked about.

## Step 4: Resolve the Roster

Default: the strongest available Claude model + Codex (via the codex plugin's `codex-rescue` subagent). Availability is probed at dispatch, never assumed from cached or inherited beliefs.

- Default roster, second family unavailable: announce the degradation — a same-family panel is materially weaker per upstream evidence — and ask whether to proceed same-family or abort.
- A panelist the user explicitly requested is unavailable: say so and ask how to proceed. Never silently substitute another model for an explicit request.

## Step 5: Dispatch

Spawn one panelist per roster slot in parallel. Each panelist gets the identical prompt in a fresh context containing only the approved material. Single round: no cross-talk, no visibility into other panelists, no follow-ups. Every cross-family dispatch is read-only — `codex-rescue` defaults to a write-capable run, so the read-only request must be explicit in the forwarded task.

Write raw responses into a per-run scratch directory created with `mktemp -d` and `chmod 0700` — non-colliding, never a predictable path. Tell the user the directory is session scratch and how to delete it. Persist nothing to the repo unless asked.

## Step 6: Deliver

Present every response verbatim, each attributed to its model, with the scratch paths. Do not merge, reconcile, or edit. Recommend `Skill(auto-claude-skills:synthesize)` as the explicit next step — the caller decides; never silently chain into it.
