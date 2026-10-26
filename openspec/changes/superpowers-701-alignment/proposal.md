## Why

superpowers 7.0.1 is the installed backbone (ACS supplements it and does not re-implement its phases). Since our routing text was written against 6.x, three things have changed:

- **DESIGN exit contradicts brainstorming.** brainstorming's HARD-GATE now says, at every size: "After the design doc is approved, the next step is the plan: invoke superpowers:writing-plans and no other skill." Our brainstorming precondition says to invoke `agent-safety-review` "before leaving DESIGN". Whenever the trifecta check fires, the model receives two direct contradictions. In 6.4.2 the SP rule covered only the architectural path; in 7.0.1 it covers every size.
- **Two red flags push against SP's own choices:**
  - PLAN's "Not saving the plan to docs/plans/ before executing" calls a correct SP run (default `docs/superpowers/plans/`) a violation.
  - IMPLEMENT's "Not using subagent-driven-development or agent-team-execution for parallelizable tasks" pressures the model to override the execution method the user picked at the plan handoff. SDD itself forbids parallel implementers.
- **Duplicate or drifted text:**
  - Three DESIGN red flags restate 7.0.1 brainstorming's own rules, at a cost on every DESIGN prompt.
  - The `verification-before-completion` description promises "no TODOs, docs updated", which the skill does not say.
  - The `using-superpowers` registry entry can never be selected: it has no triggers or keywords and no composition reference, and SP injects that skill itself at SessionStart.
  - The description-drift test is dated to 6.4.2, and its advisory D4 leg looks only in `superpowers-marketplace`.

Evidence: the 2026-10-25 superpowers-evolution research, which compared the cached 6.4.2, 7.0.0 and 7.0.1 trees and upstream `obra/superpowers`.

## What Changes

- **The brainstorming precondition** moves the trifecta classification and any `agent-safety-review` invocation to **before the design doc is approved**. The classification goes in the design doc, so that after approval the next step is writing-plans and nothing else. The `product-discovery`-first clause is unchanged; it runs before brainstorming starts and does not conflict.
- **DESIGN red flags** keep only the ACS-unique routing obligation ("Editing implementation files before invoking Skill(superpowers:brainstorming)").
- **Two red flags are reworded:**
  - PLAN: the plan is saved to a file before executing, with no path named.
  - IMPLEMENT: the execution method the user chose at the plan handoff is used.
- **The `verification-before-completion` description** states what the skill does: run the verification fresh and read its output before any success claim.
- **The `using-superpowers` registry entry is deleted** from both configs.
- **`tests/test-superpowers-description-drift.sh`:**
  - re-dated to 7.0.1;
  - D4 scans every marketplace;
  - new advisory needles for brainstorming 7.0.1's DESIGN exit;
  - D1-D3 cover the new descriptions and red flags.

Not changed (owner's call, precision/recall): the phase-enforcement hint "Small changes still require the full flow — scaled down, not skipped", which 7.0.1's "quick, clear task: do it" path now contradicts.

## Capabilities

### Modified Capabilities

- `skill-routing`: a requirement that the routing text does not contradict the superpowers backbone at the DESIGN exit, the PLAN save and the IMPLEMENT method choice.

## Impact

`config/default-triggers.json`, `config/fallback-registry.json`, `hooks/skill-activation-hook.sh` (RED_FLAGS), `tests/test-superpowers-description-drift.sh`, `tests/test-injection-budget.sh` (equality ratchet falls), and any test pinning the old strings. No gate changes: nothing enforces `agent-safety-review`, and red flags are advisory text.
