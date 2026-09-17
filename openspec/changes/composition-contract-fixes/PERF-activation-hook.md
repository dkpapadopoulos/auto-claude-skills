# Measured: activation-hook latency on this branch

**This file was WRONG on first publication and is corrected below. The original numbers
(main 64ms, HEAD 103ms, delta +39ms) came from a harness that created a temp directory and
rebuilt the JSON payload on every iteration, so filesystem and jq noise dominated. The
tell was a nonsense result: a plain dev prompt measured SLOWER than a consultation prompt,
which cannot be true if regex work drives the cost.**

## Method (corrected)

Fixed `HOME`, registry written once, payload built once, 25 iterations, repeated twice and
agreeing within 4ms. An EMPTY registry is measured as a control, isolating fixed hook
overhead from all trigger work.

| configuration | total | attributable to triggers |
|---|---|---|
| empty registry (no skills at all) | **61 ms** | 0 |
| `main` | 103 ms | **42 ms** |
| this branch (HEAD) | 124 ms | **63 ms** |
| **delta introduced here** | **+21 ms** | +21 ms |

## The two findings that matter

1. **61ms is FIXED overhead** — bash startup, jq forks, registry read, composition walking.
   It is 49% of the total and is unrelated to routing triggers. Any latency work should
   start here, not with the regexes.
2. **Trigger cost does NOT vary with whether the prompt matches.** A plain dev prompt
   ("fix the failing test in…") and a full consultation prompt cost the same within noise
   (137/136ms and 133/134ms across two runs). Every clause is evaluated either way.

## The optimisation I was about to build would have saved NOTHING

The plan was a per-clause literal prefilter, on the theory that ordinary prompts waste time
in the consultation regexes. Finding 2 refutes it: matching and non-matching prompts already
cost the same, so skipping clauses that were never going to match saves no measurable time.
Bash's regex engine is not where the money is. Measuring first prevented both wasted effort
and a config-schema change that would have bought nothing.

## Judgement

124ms on a `UserPromptSubmit` hook is not user-perceptible — model latency exceeds it by
orders of magnitude. `CLAUDE.md` states the budget as "~50ms", and the hook was already
over it at 103ms before this branch. This branch adds 21ms on top. Recorded as an explicit
acceptance rather than a later discovery; the fixed-overhead finding is the lead worth
following if anyone wants the budget back.

---

## Follow-up: where the 61ms of fixed overhead actually goes

Profiled with a PATH shim that logs every `jq` invocation, so these are EXECUTIONS, not
call sites (the file has 61 `jq` call sites; only 11-12 run per invocation).

| | cost |
|---|---|
| 11 jq forks | **30 ms** |
| bash startup | 2 ms |
| everything else (registry parsing, string work, composition walk, grep/cat/git forks) | ~29 ms |
| **total fixed overhead** | **61 ms** |

So jq forking is HALF the fixed overhead — and more than this whole branch added (+21ms).
`CLAUDE.md` already states the convention being violated: "Minimize jq forks — batch into
single calls."

### Which forks are batchable, and which are not

Eight of the eleven read the SAME registry file with different filters. Five run EARLY,
before any skill is selected, and could merge into ONE call emitting delimited sections:

1. registry validation (`empty <cache>`)
2. the skills list (name / role / triggers / priority …)
3. `methodology_hints` with plugin gating
4. `phase_compositions[$phase]`
5. `required_when` pairs

Three CANNOT be hoisted: `walk_fwd(precedes)`, `walk_bwd(requires)` and the per-skill
`precedes` lookup all take a skill name that is only known AFTER scoring. The remaining
two are the stdin read (`-Rs .`) and the output builder (`-n`), both structural.

Estimated recovery: 5 forks -> 1 saves roughly 11ms, about 9% of total hook time.

### Deliberately not done here

This is a hot-path refactor of a 2009-line hook: the five calls emit differently-shaped
output consumed by different parsers, so batching means changing both the query and every
reader. The suite (141 files, 446 fixture assertions, the frozen baseline) would catch a
regression, but "the tests would catch it" is not a reason to attempt a mechanical
refactor of the routing hot path at the end of a long session — the same judgement applied
to the prefilter above, which measurement then proved would have saved nothing at all.

Recorded at this level of detail so the follow-up is a small specified task, not an
investigation: batch calls 1-5 into one delimited jq invocation, leave 6-11 alone.

---

## Follow-up done (2026-09-17)

Calls 1-5 now run as ONE `jq -nj` invocation at registry load. It emits four sections
separated by RS (`\x1e`), and the phase compositions are emitted for every phase and
filtered in bash, because the phase is known only after scoring. Calls 6-11 are
unchanged.

- **Forks.** Five become one when a phase is selected, confirmed with the same jq PATH
  shim. The old hook ran the required_when call only once a skill scored and the
  composition call only once a phase was chosen, so otherwise the saving is two or three
  forks. The greeting early-exit path still runs one fork. The rare RS fallback (below)
  runs the single call and then the separate calls, so it saves nothing.
- **Latency.** Fixed `HOME`, all skills available, 25 iterations x 3 rounds. The
  original and new hook bodies ran back to back, twice, and the two passes agreed within
  about 1 ms:

  | prompt | before (ms) | after (ms) |
  |---|---|---|
  | "fix the failing test in the ingest worker" | 128.9-130.4 | 119.3-120.5 |
  | "review the PR diff for bugs" | 157.6-158.3 | 147.2-148.5 |
  | "ask gemini cold whether this migration is safe" | 122.6-125.4 | 113.1-114.3 |

  That is about 10 ms per prompt, close to the 11 ms estimated above. Absolute times
  differ from the first table because machine load differs between sessions; compare
  within a table only.
- **Splitting has to be linear.** Under bash 3.2 on a 50 KB output:

  | split method | time per split |
  |---|---|
  | `${var#*pat}` / `${var%%pat*}` | 278-529 ms |
  | `read -d` | 16 ms |
  | word splitting with `IFS` set to RS alone | about 2 ms |

  The first two would have cost more than the whole saving.
- **Equivalence.** Full stdout, debug trace and written state files were compared before
  and after, with paths and timestamps masked. They are byte-identical across:
  - 633 prompts (fixtures, the negative corpus, all consultation rounds) on two registries;
  - 81 prompts on each of nine edge-case registries;
  - fourteen targeted registries built from the review findings below.

  My own comparison found one difference, a concatenated two-document cache.
  Two rounds of independent review (Codex and a Claude reviewer) then found four more,
  each reproduced with a pair of runs:
  - **Document isolation.** A non-object document before the real registry hid it.
    jq's CLI reports a runtime error and continues with the next document, so each
    old call isolated documents. Fixed with a `try` per document.
  - **RS in a value.** An escaped RS inside a string shifted the sections. The single
    call now reports `REGISTRY-HAS-RS`, and the hook runs the same filters as separate
    calls.
  - **Newline or US in a phase key.** Such a key could forge another phase's line prefix.
    These keys are now skipped; the old exact-key lookup could never select them.
  - **NUL in a phase key** (second round). Bash drops NUL from the captured output, so
    `IMPLEMENT<NUL>` read as `IMPLEMENT`. NUL-bearing keys are skipped too. The check
    uses `explode`, because jq 1.6's `contains` stops at NUL and would match every key.

  Each section filter is now defined once and shared by both paths. Fifteen deliberate
  breakages (including one re-introducing each defect above) are each caught by
  `tests/test-activation-registry-extract.sh`.
