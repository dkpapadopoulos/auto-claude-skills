## Context

ACS treats superpowers as the explicit backbone; ACS supplements and never re-implements its phases. Rendered routing text that contradicts the backbone makes the model choose between two instructions. Either choice violates one of them, and neither is caught by a gate.

## Decisions

1. **The trifecta check runs inside DESIGN, before approval, not on the way out.** Exiting DESIGN is owned by brainstorming ("writing-plans and no other skill"). Classifying the data flow belongs in the design the user approves, which also puts the risk in front of the person approving it. Rejected alternative: keep "before leaving DESIGN" and tell the model the ACS rule wins. That pits ACS against its backbone on every design and fixes nothing.
2. **Red flags are cut, never extended, where SP now owns the rule.** A red flag that restates the invoked skill costs injection bytes on every prompt in that phase and adds nothing. One that contradicts the skill is worse than none. ACS keeps only the lines that are routing obligations no skill can carry.
3. **The IMPLEMENT flag defers to the user's choice.** Since 6.4.1 the human picks Subagent-driven or Native at the plan handoff. A hook line that overrides that choice is an instruction-following hazard, not a safeguard.
4. **The drift check stays advisory for upstream text (D4).** Upstream wording is not under this repo's control, and the suite is the push gate. D1-D3 assert our own text.
5. **The phase-enforcement "full flow" hint is out of scope.** Whether small changes may skip design and plan is a precision/recall call for the owner. It is recorded in the proposal and not changed here.

## Risks

- **Measured wording.** Fixtures under `tests/fixtures/*/evals/` and `tests/probes/fixtures/` hold frozen hook output and keep the old text. Only graded expectations are checked, as `test-superpowers-description-drift.sh` D1 already does.
- **Injection budget.** `tests/test-injection-budget.sh` is an equality ratchet. Every rendered string here gets shorter or is deleted, so the constant falls in the same commit.
