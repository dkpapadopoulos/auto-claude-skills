# Pre-registration — outcome ablation pilot: bare vs superpowers vs superpowers+ACS

**Date:** 2026-10-04
**Status:** FROZEN at Revision 2, before any outcome run. Any change after the first outcome run is
an entry in the amendment log with its reason, never an in-place edit.
**Parent:** `docs/plans/2026-10-03-frontier-model-value-audit-design.md` (Phase 1).
**Question:** on current frontier models, does loading superpowers, or superpowers plus
auto-claude-skills (ACS), change the *outcome* of autonomous, fully specified coding tasks — and at
what cost — relative to a bare Claude Code session?

## Revision history (all before any outcome data)

- **R1** — first draft. Never run.
- **R2** — after a cross-family adversarial review by Codex (codex-cli 0.154.0, read-only, given R1
  and no conclusions). Seven findings, all accepted:
  1. The R1 rule "±3 of 16 = benefit/harm" was an effect-size threshold, not a test: at a true pass
     rate of 0.8 in every arm it would falsely declare a quality effect in ~26% of single comparisons
     and ~50% of the time across three. **Replaced by an exact paired test with one pre-selected
     primary comparison.**
  2. R1 turned "no detectable difference" into "net negative" when cost was higher — equivalence it
     could not support. **Quality and cost are now reported separately; a quality null is
     "inconclusive", never "equivalent".**
  3. Red/green alone does not show the hidden tests implement the spec or reject wrong fixes, and
     "outside the repo" is not "inaccessible to Bash". **Added a wrong-fix leg, a requirement→test
     mapping review, and a locked vault.**
  4. No manipulation check. **Added: per-run record of loaded plugins and hook output; frozen
     artifact hashes; a fresh HOME per run.**
  5. The headless sentence did not authorise skipping approval checkpoints, so a stall would measure
     instruction conflict, not coding. **The sentence now grants that authorisation in every arm, and
     the estimand is narrowed accordingly.**
  6. Concurrent arms share server-side prompt cache; observed cost is cache-luck-sensitive.
     **Primary cost measure is now cache-insensitive.**
  7. Caps, retries, ordering and stopping were under-specified. **Frozen below.**
  Also adopted: **16 tasks × 1 repetition instead of 8 × 2** — task diversity over repeats.

## What this pilot can and cannot say

Estimand: the effect of loading each plugin *package* on autonomous, fully specified, single-session
coding tasks of small-to-medium size. A2 vs A1 estimates the whole ACS package conditional on
superpowers, not "routing" in isolation.

It cannot establish equivalence, interactive-workflow value (requirement elicitation, approval
checkpoints), value on long or multi-session work, team workflows, the push/ship gates, or production
ROI. A null is "insufficient evidence", not "no effect".

## Arms

Every arm is a real `claude -p` session (CLI 2.1.285) in a fresh copy of the task repo, with
`--setting-sources project --strict-mcp-config --permission-mode acceptEdits`, the same `--model`,
default effort, the same `--allowedTools`, `--max-budget-usd 4`, and a **fresh isolated `HOME` per
run** copied from a per-arm template, so no run reads or writes the owner's real `~/.claude` and no
state carries between runs. Auth is the owner's OAuth (keychain reached through a `Library` symlink).

| Arm | `--plugin-dir` | HOME template |
|---|---|---|
| **A0** bare | none | empty `.claude` |
| **A1** superpowers | superpowers 6.4.2 | empty `.claude` |
| **A2** superpowers + ACS | superpowers 6.4.2 + auto-claude-skills 3.93.1 (installed build; no `skill-config.json` = `standard` preset) | plugin cache exposing only those two plugins; registry pre-built once by the plugin's own session-start hook (40 skills available, 5 companion skills correctly unavailable) |

Companion official plugins and MCP servers are absent in all arms (a stated limit). Shadow corpora
and gate capture are redirected by env so no run writes into a pre-registered corpus.

**Manipulation check (per run, recorded, not a quality measure):** the session's `init` event lists
exactly the intended plugins; A2 has ACS `UserPromptSubmit` hook output and A0/A1 have none; A1/A2
have the superpowers SessionStart injection and A0 has none. A run failing its manipulation check is
a harness failure (see Runs). Subagent models are not pinned; the models actually used are recorded.

## Tasks

Sixteen self-contained Python (stdlib-only, `unittest`) task repos **authored by Codex** from a
frozen authoring prompt, in a fixed order, with four spares in a fixed order. Four per category:
(a) small bug fix with a regression trap; (b) feature addition whose spec states its edge cases;
(c) debugging where the visible symptom's obvious fix is wrong; (d) "prepare this module for release:
find and fix the defects" with planted bugs. Each task has `repo/` (with `TASK.md` and partial visible
tests), and — in a vault the subject cannot read — `hidden_tests/`, a reference `solution/` overlay,
a plausible-but-wrong `wrong_fix/` overlay, and `META.md` mapping each hidden test to the `TASK.md`
sentence that requires it.

Fixture validity gate, per task, before any subject run. A task failing any leg is **replaced by the
next spare, never repaired by the experimenter**; rejections are logged.
1. hidden tests **fail** on the starting repo, with >0 tests run and no load error;
2. hidden tests **pass** with `solution/` applied;
3. visible tests run on the starting repo and pass with `solution/` applied;
4. hidden tests **fail** with `wrong_fix/` applied, while the visible tests pass with it — the hidden
   suite discriminates the tempting wrong answer;
5. no hidden-test or solution file is present in, or identical to, anything in `repo/`; `TASK.md`
   does not mention hidden tests;
6. **spec-derivability review** by the experimenter, recorded per task: every hidden assertion is
   required by a sentence of `TASK.md` or by behaviour the starting code and visible tests already
   establish. A task with an assertion that fails this is rejected.

During runs the vault (hidden tests, solutions, wrong fixes, mappings) is mode 000 and each run's
working copy lives outside the task tree. Scoring happens after all arms of a task have exited: the
vault is unlocked, each working copy is graded by the frozen `hidden_runner.py` with the hidden tests
and with the **original** visible tests (a subject editing visible tests cannot improve its score),
and the vault is locked again.

The task set, the authoring prompt, the scoring scripts and both plugin trees are frozen by SHA-256
in the amendment log before the first run.

Prompt, identical in every arm: the contents of `TASK.md`, then —
"You are authorized to implement this directly; no design or plan approval is needed. No one is
available to answer questions. Make reasonable assumptions, complete the task, and stop."

## Runs

Per model: 16 tasks × 3 arms × 1 run = 48 runs; the three arms of a task run concurrently. Models:
`claude-opus-5-5` (primary), then `claude-fable-5-1`. Tasks run in task-id order.

Frozen limits: budget cap USD 4 notional per run; wall cap 20 minutes; no turn cap. A run that hits a
cap **counts as it stands**. A harness failure (no assistant turn, or a failed manipulation check) is
re-run once; a second failure drops that task from the paired analysis for the comparisons it affects,
and is logged. Failures are adjudicated from `init`/hook fields only, never from the score.

Usage stop: after the first 4 tasks of a model, if projected notional cost for that model exceeds
USD 150, stop. A stopped model is published as **incomplete, with no verdict**.

## Measures

- **Q (primary quality):** per task, fraction of hidden tests passing (0–1). A load error or zero
  tests run scores 0.
- **Qbin (secondary):** every hidden test passes.
- **C (primary cost):** total tokens processed, summed over every model the run used, from
  `modelUsage` — input + cache-creation + cache-read + output — a measure that does not depend on
  which arm won the cache.
- **Secondary cost:** observed notional USD; wall seconds; turns.
- **Descriptive:** skills invoked, subagents dispatched, lines changed, whether any file was edited,
  original visible tests still passing.

## Analysis (per model, fixed now)

Primary comparison: **A2 vs A0**. Secondary: A1 vs A0, A2 vs A1 (Holm-adjusted across the two).

- **Quality:** exact two-sided paired sign-flip permutation test on the 16 per-task differences in Q
  (all 2^16 sign assignments). Report the mean difference, the per-task table, and p. Also report the
  Qbin discordant counts with the exact McNemar p.
- **Cost:** per-task ratio C(X)/C(Y); report the median ratio and its range, and an exact two-sided
  sign test on "X cost more than Y".
- **Vocabulary:** quality is **benefit shown** (p < 0.05, mean difference > 0), **harm shown**
  (p < 0.05, < 0), or **inconclusive**. Cost is **overhead shown** / **saving shown** (sign test
  p < 0.05) or **inconclusive**, always with the median ratio.
- No composite verdict is computed. What the owner does with "quality inconclusive, overhead shown" is
  a policy choice (the inverted burden of proof proposed in the parent document), and is labelled as
  policy, not as a finding of equivalence.

The result is reported whatever it says. Inspecting which tasks failed and then changing a plugin
spends the task set: it becomes development data and a new set must be authored to re-measure.

## Known threats, stated before the data

1. Tasks authored by another model family may favour either side in unknown ways; the gate checks
   soundness and discrimination, not representativeness.
2. Ceiling: if every arm solves nearly every task, quality is uninformative and only cost is learned.
3. n = 16 tasks: only large quality effects are detectable.
4. Headless, pre-authorised work removes exactly the human checkpoints some skills exist to create.
5. Token totals treat a cached token like an uncached one; notional USD is reported beside it.
6. A2 is a minimal install; an install with companion plugins may route differently.

## Exploratory evidence already in hand (NOT pre-registered; observed before this file)

Field census of the owner's local transcripts, 2026-08-26 → 2026-10-03, human-typed prompts only:
784 routing events, mean 4.9 KB injected each. First `MUST INVOKE` routing of a skill per session:
183 cases — invoked in the same turn 22, later in the session 28, already loaded 8, never 125.
Two blind LLM labellers (agreement 0.87, Cohen's kappa 0.76) judged the routing appropriate on the
prompt's face in 14 cases by consensus and not appropriate in 100. These numbers motivated the pilot
and are reported separately from it.

## Amendment log

(empty)
