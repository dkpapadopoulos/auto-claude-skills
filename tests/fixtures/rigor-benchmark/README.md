# Rigor Benchmark

Seeded (diff, verdict) cases giving objective ground truth for testing-rigor mechanisms,
independent of felt production pain. Six classes: untested-new-code, assertion-free-test,
bug-with-green-tests, weakened-test, adequate-clean, pure-refactor.

Splits: `dev/` tunes mechanisms; `held-out/` scores them and its cases MUST be sourced
from a **different codebase** than any mechanism was tuned on. Cases are never deleted —
**deprecate** a case with a dated rationale in its manifest line (`"deprecated":"YYYY-MM-DD reason"`).
