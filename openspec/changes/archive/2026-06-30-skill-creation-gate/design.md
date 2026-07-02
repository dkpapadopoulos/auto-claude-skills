# Design: Skill-Creation Gate (Phase A)

## Architecture

Two halves close the "skill done = files exist" gap:

- **Behavioral half (external, guaranteed):** `writing-skills` becomes
  `role: required` so it is always selected when skill-creation triggers match.
  Its Iron Law (failing pressure-test first) supplies the *does-it-teach-the-
  right-thing* validation. We can only route to it; we cannot edit it.
- **Routing half (owned, deterministic):** a per-skill regex fixture
  (`tests/fixtures/routing/<skill>.txt`) plus a **coverage test** that every
  non-external skill has one. This supplies the *does-it-route-correctly*
  validation and is CI-blocking via `.verify.yml` → `bash tests/run-tests.sh`.

The three creation skills are a **flow, not a merge**:

```
DESIGN   writing-skills   (role=required, always)   discipline + failing pressure-test + anatomy
DESIGN/  skill-scaffold   (emit seeds)              SKILL.md skeleton + routing entry (BOTH config files)
 PLAN                                                + tests/fixtures/routing/<skill>.txt stub
                                                     + skills/<skill>/evals/evals.json stub (optional)
REVIEW   skill-creator    (held-out trigger eval)   advisory: 60/40 train/held-out, best-by-test-score
GATE     run-tests.sh     (owned, deterministic)    fixture content + fixture coverage + dual-file sync
```

### Components (each independently testable)

1. **Required-role `writing-skills`** — registry data change in both config
   files. Behavior verified by a skill-routing regression: a skill-creation
   prompt selects `writing-skills` even when domain slots are full.
2. **`skill-scaffold` content** — emits the fixture stub (positives + borrowed
   decoy negatives) and the evals.json stub; documents the dual-file routing
   requirement. Verified by a content-assertion test.
3. **`tests/test-fixture-coverage.sh`** (new) — reads non-external skill names
   from `config/default-triggers.json`, asserts a matching fixture file exists.
   Run by `run-tests.sh`. Verified red-first (a skill with no fixture fails).
4. **Docs** — CLAUDE.md gains the 3-stage flow + the silent-pass gotcha.

### What "non-external skill" means for coverage

A skill whose `invoke` targets this plugin (`Skill(auto-claude-skills:<name>)`).
External skills routed via our registry (`Skill(superpowers:...)`,
`Skill(skill-creator)`) are EXCLUDED from the coverage requirement — we don't own
their behavior and shouldn't gate on fixtures for them. (External skills MAY
still have fixtures; coverage only *requires* them for owned skills.)

## Trade-offs

- **Deterministic fixture vs LLM eval as the gate.** The fixture re-checks the
  author's own regex against author-chosen prompts — positives alone are
  tautological. Mitigation: **mandatory NO_MATCH decoys borrowed from other
  skills' fixtures**, which makes an over-broad regex fail. The richer semantic
  check (held-out LLM trigger-eval) stays advisory because `skill-eval.yml` is
  manual-trigger, secret-dependent, fork-refusing, comment-only — it cannot be a
  clean local hard gate.
- **Reward-hacking residue.** Borrowed decoys are still gameable by picking weak
  decoys. We require reviewer-visible rationale and borrowing from *existing*
  fixtures, not author invention. Accepted residual risk; the alternative
  (LLM-judge over the diff) is the prior 93%/14% trap until a labeled corpus
  exists.
- **External-plugin dependency.** The recommended flow uses two external skills.
  If absent, the *workflow* degrades (no guaranteed discipline / held-out eval)
  but the *gate* still holds, because the floor is fully owned. This is the
  decisive reason the gate is deterministic-and-owned, not LLM-and-external.

## Dissenting views (from sparring)

- Codex argued Decision-1 option (b): build a thin **owned** eval wrapper so the
  held-out loop runs without `skill-creator`. **Rejected for Phase A** — it
  reinvents a mature external tool (against the repo's no-reinvent lesson). The
  owned floor is *deterministic*, not a second LLM eval engine. Revisit only if
  users report the external held-out loop is load-bearing and frequently absent.
- An alternative to `role=required` was an always-on imperative hint. Chosen
  `role=required` for a hard guarantee via the scoring engine (Pass 0), matching
  existing `using-git-worktrees` / `agent-team-review` usage.

## Decisions

- **D1:** 3-stage flow, divide labor; enforceable floor owned + deterministic.
- **D2:** Deterministic fixture (with borrowed decoy negatives) + coverage test +
  dual-file sync = hard CI gate. Held-out LLM eval = advisory REVIEW step.
- **D3:** `writing-skills` → `role: required` (Pass 0 selection), DESIGN phase.
- **D4:** Coverage requirement applies to owned (`auto-claude-skills:*`) skills
  only.

## Verification strategy (deterministic feature)

Standard TDD + the acceptance scenarios below. Each component gets a failing test
first. No probabilistic behavior in the owned floor, so no eval set is required
for Phase A itself (the LLM trigger-eval is the *subject*, not the *verifier*).

## Implementation Notes (synced at ship time)

- Built as-designed across 6 commits. No deviation from the 5 ADDED requirements.
- Tasks 2 and 3 were executed as ONE commit (coverage gate + 11-fixture backfill) to avoid an intermediate red-test commit — deliberate, keeps every committed state green.
- The gate validated itself during the build: it caught a non-matching MATCH line in the plan's worked example, a `deploy-gate.txt` fixture that was passing the borrowed-decoy check only via a NO_MATCH-substring loophole (which the Task-5 hardening then closed), and the independent task reviewer caught a Task-4 implementer false "suite green" claim.
- Deferred non-blocking minors (opus whole-branch review, READY): M1 `writing-skills` over-fires on the bare `skill`/`skills` substring in DESIGN prompts (advisory noise only); M2 borrowed-decoy check matches substring-prefix rather than full-line verbatim; M3 8 fixtures share one donor line (fails closed). Out-of-scope deferrals: held-out LLM eval as a hard gate, Phase B (status≠verdict), Phase C (correction-ergonomics).
