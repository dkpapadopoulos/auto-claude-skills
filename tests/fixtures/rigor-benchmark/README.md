# Rigor Benchmark

Seeded (diff, verdict) cases giving objective ground truth for testing-rigor mechanisms,
independent of felt production pain. Six classes: untested-new-code, assertion-free-test,
bug-with-green-tests, weakened-test, adequate-clean, pure-refactor.

Splits: `dev/` tunes mechanisms; `held-out/` scores them and its cases MUST be sourced
from a **different codebase** than any mechanism was tuned on. Cases are never deleted —
**deprecate** a case with a dated rationale in its manifest line (`"deprecated":"YYYY-MM-DD reason"`).

## Limitations

- **Case-class coverage is partial.** Of the six design classes, only `untested-new-code`
  and `adequate-clean` currently have seeded cases. `assertion-free-test`,
  `bug-with-green-tests`, `weakened-test`, and `pure-refactor` are NOT yet seeded —
  recall/precision numbers reported by the scorer only speak to the two classes that
  exist today, not the full design surface.
- **Held-out is not yet from a real external codebase.** Despite the spec's intent that
  `held-out/` be sourced independently from the tuning corpus, every case currently in
  `held-out/manifest.jsonl` is `"source":"seeded-synthetic"` — hand-authored fixtures
  written for this benchmark, not mined from a real external project. A genuinely
  real-external, varied-difficulty held-out set is a **REQUIRED PRECONDITION** before
  this benchmark is used to arbitrate any Phase-2 escalation race (mutation testing,
  spec-derived test generation, or cross-model peer review) — scoring a frozen-criteria
  race against seeded-synthetic held-out cases risks measuring how well a mechanism
  matches this benchmark's authoring style rather than real-world generalization.
