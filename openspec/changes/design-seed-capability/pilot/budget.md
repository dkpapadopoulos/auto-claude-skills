# Budget rules — frozen before launch

Identical for both arms. The clock starts at dispatch, BEFORE any adoption work,
so preparation cannot become unbudgeted effort.

- **Cap:** 60 tool calls per arm.
- **Stopping rule:** the arm stops at the cap, or when it reports done, whichever
  comes first. Work in progress at the cap is submitted as-is.
- **Timeout:** 45 minutes wall clock per arm.
- **Retry allowance:** none within a run. One whole-arm rerun is permitted ONLY
  for an infrastructure fault (harness crash, tool unavailable), declared and
  recorded before the rerun. Never for an unsatisfying result.
- **Recorded per arm:** tool calls used, wall clock used, and — for the seeded
  arm — the split between adoption and implementation.
