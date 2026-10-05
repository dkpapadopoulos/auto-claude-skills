# Task-authoring brief (frozen)

Create 20 self-contained coding-task fixtures under `./tasks/`, named exactly:
`a1-…` `a2-…` `a3-…` `a4-…` `a5-…` (category a), `b1…b5`, `c1…c5`, `d1…d5` — e.g. `tasks/a1-invoice-rounding/`. The fifth of each category is a spare. Use a short kebab-case slug after the id.

These fixtures will be used to compare coding agents. A capable agent receives ONLY `repo/` and is asked to do what `repo/TASK.md` says. Afterwards a grader runs `hidden_tests/` against the agent's version of the repo. You are the fixture author: your job is to make tasks that are fair, fully specified, objectively gradable, and hard enough that a careless-but-strong engineer would plausibly get them partly wrong.

## Categories (5 each)
- **a — small bug fix with a regression trap.** TASK.md reports a concrete bug. The obvious fix resolves the reported case but breaks, or fails to handle, a neighbouring behaviour that the code or TASK.md already defines.
- **b — feature addition with stated edge cases.** TASK.md specifies a new capability including explicit edge cases (empty input, boundaries, ordering, error type and message contract, idempotence, …). Fitting it in correctly requires reading at least two existing modules.
- **c — debugging with a misleading symptom.** TASK.md describes a symptom (and includes a failing visible test). The root cause is in a different function or module from where the symptom appears; patching at the symptom site passes the visible test but leaves the underlying defect.
- **d — release hardening.** TASK.md says: this module is about to be released; review it against the documented behaviour (docstrings / README section inside the repo) and fix every defect. Plant 3–4 independent, realistic defects of varied kinds (off-by-one, wrong default, mutation of an argument, unhandled documented error case, wrong comparison, resource not closed, etc.). The documented behaviour must make each defect unambiguous.

## Hard requirements for every task
1. Python 3.11+ standard library only. Tests use `unittest` only. No network, no clock-of-day dependence, no randomness without a fixed seed, no files outside the repo directory. Everything must run offline in under 5 seconds.
2. Layout:
   ```
   tasks/<id-slug>/
     repo/                 # what the agent sees
       TASK.md             # the request, written the way a teammate would write an issue; states EVERY behaviour the hidden tests check
       <package or modules>   # 150–450 lines of realistic, readable source across 2–5 files
       tests/test_*.py     # partial visible tests (unittest); they must not cover everything the hidden tests cover
     hidden_tests/test_*.py  # 6–14 unittest tests; file names must differ from every file name in repo/tests
     solution/             # overlay: ONLY the files that change, at the same relative paths as in repo/; a correct reference fix
     wrong_fix/            # overlay, same convention: the tempting-but-wrong fix. With it applied, repo/tests PASS but hidden_tests FAIL (at least one failure)
     META.md               # table: each hidden test name -> the exact TASK.md sentence (or existing documented behaviour) that requires it; plus one line describing the trap
   ```
3. Imports: hidden tests and visible tests import the code as it is importable from the `repo/` directory being the current working directory and first on `sys.path` (e.g. `from inventory.stock import reserve`). Do not rely on package installation.
4. Fairness: every assertion in `hidden_tests/` must be derivable from `TASK.md` plus behaviour already documented in the repo (docstrings, README, existing tests). Never test an unstated preference (naming, formatting, exact wording of messages unless TASK.md quotes it). Accept any correct implementation: test behaviour through public functions that already exist or that TASK.md names with their exact signature.
5. `TASK.md` must NOT mention hidden tests, graders, traps, or this brief, and must not hint at where the trap is. It should read like a normal issue. It may say which visible test currently fails.
6. On the untouched `repo/`: `hidden_tests` must FAIL (at least one failing test, no import errors). With `solution/` applied: all `hidden_tests` and all `repo/tests` PASS. With `wrong_fix/` applied: all `repo/tests` PASS and at least one hidden test FAILS. For category a/b where visible tests fail before the fix, that is fine, but with `solution/` they must all pass.
7. Vary the domains (e.g. inventory, scheduling, text diffing, rate limiting, config merging, CSV/ledger parsing, caching, graph/dependency resolution, pagination, retry/backoff logic, interval arithmetic, state machines, permission checks, unit conversion, queue/priority handling). No two tasks may share a domain or a trap type within a category.
8. Difficulty: not toy-level. A task should take a careful engineer 10–25 minutes. Avoid puzzles and trick wording; the difficulty must come from realistic code that requires reading before changing.
9. Do not put any file named or containing the hidden tests or the solution inside `repo/`.

## Self-check you must run before finishing
Write `./selfcheck.py` that, for every task, copies `repo/` to a temp dir and verifies requirement 6 exactly (three configurations: untouched, +solution, +wrong_fix; running hidden tests and visible tests with `python3 -m unittest discover`), and prints one PASS/FAIL line per task with the counts. Run it and fix your fixtures until every task passes. Leave `selfcheck.py` and its final output in `./selfcheck.out`.

When done, print a one-line summary per task: id, domain, the trap in ≤12 words.
