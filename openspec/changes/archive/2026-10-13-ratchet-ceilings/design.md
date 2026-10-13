## Architecture

No code path changes. Two test files change their comparison from equality to an upper bound, one documentation line changes, three hook comments change, and one spec file has two requirement sentences rewritten.

## Decisions

- **Which constants stay equality.** A total a user pays on every prompt or every session start (the injection budget `_INJECTION_BASELINE`; the instruction-file total `_COMBINED_BASELINE`) stays an equality ratchet, because an unbanked reduction there is a saving nobody recorded and a later regrowth to the old pin would be invisible. An internal count that approximates a cost (the per-phase hint byte totals, the fork count over a fixture) becomes a ceiling: growth still fails with a reason required, a reduction passes.
- **Evidence for the tax, stated precisely.** Across PRs #347 to #353 on 2026-10-12 the constants that were re-pinned by a LATER PR were `_INJECTION_BASELINE` (24,988, 21,849, 21,917, 22,253, 22,379 across #349 and #350), `_COMBINED_BASELINE` (173,886, 174,089, 174,140 across #352, and 174,397 here) and `_SS_FORK_BASELINE` (30 to 33 by #351). The hint pins moved only within #349's own commits. The conversion of the hint pins is therefore prospective: same shape of constant, same tax expected; the fork count paid it once.
- **Spec and tests move together.** The canonical requirements said "equality ratchets" and "growth and an unbanked shrink both fail"; left as written they would invite a reader to revert the tests (the "genericising code leaves the spec demanding the specific" failure). They are MODIFIED here and applied to the canonical spec by `openspec archive` in the same PR.
- **The latency line states measurements, not a new budget.** The 200 ms session-start budget and the ~50 ms activation target are kept as stated targets with the measured numbers beside them; choosing new budgets is an owner decision, not a documentation fix.

## Trade-offs

- A ceiling lets a reduction go unbanked, so the hint totals and the fork count can regrow to the ceiling unseen. Accepted for internal counts: the user-paid totals still catch any regrowth that reaches a prompt or a session start.
