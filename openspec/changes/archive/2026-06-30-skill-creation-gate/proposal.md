# Proposal: Skill-Creation Gate (Phase A)

## Why

When this plugin helps a user **create or edit a skill**, "done" today means *the
SKILL.md file exists and a routing entry was added* — at most one in-sample
routing assertion. There is no postcondition that the new skill actually routes
correctly on a held-out / decoy prompt set. This is the exact failure mode the
repo already burned on (a 93%-in-sample detector scored 14% held-out): in-sample
success lies.

Three skills touch skill creation but have **no defined flow** and overlapping
advice:

- `writing-skills` (external, superpowers) — authoring **discipline**: "writing
  skills IS TDD for docs", Iron Law = failing pressure-test first.
- `skill-scaffold` (ours) — repo-native **seed files** (skeleton + routing entry
  + test snippets).
- `skill-creator` (external, superpowers plugin) — **measurement**: a built-in
  held-out trigger-eval loop (60% train / 40% held-out, best description by test
  score).

Evidence (audited 2026-06-30, corroborated by Codex): only 1/28 skills has an
`evals/evals.json`; the LLM eval CI (`skill-eval.yml`) is non-blocking,
comment-only, secret-dependent. The deterministic fixture runner
(`test-regex-fixtures.sh`) **silently passes a skill with no fixture** — it only
iterates files that already exist (`for fixture in .../*.txt`), so a new skill
can merge with zero routing coverage and CI stays green.

This adapts learnings from OpenTrajectory (validate on held-out, not in-sample;
separate *attempted* from *verified*) and TrueCall (postcondition before "done";
fail-closed) to the artifact plugin users produce most: skills themselves.

## What Changes

1. **Guarantee `writing-skills` on skill creation** — promote it to
   `role: required` so the scoring engine always selects it (uncapped) when its
   skill-creation triggers match. Updated in **both** `config/default-triggers.json`
   and `config/fallback-registry.json`.
2. **Define a 3-stage skill-creation flow** (not a merge): `writing-skills`
   (DESIGN, always) → `skill-scaffold` (emit seeds) → `skill-creator` (REVIEW,
   held-out eval). Documented in CLAUDE.md; add a REVIEW-phase `skill-creator`
   hint.
3. **`skill-scaffold` emits eval artifacts** — a `tests/fixtures/routing/<skill>.txt`
   stub (MATCH positives + NO_MATCH decoys *borrowed* from other skills' fixtures)
   and an optional `skills/<skill>/evals/evals.json` trigger-eval stub; emit the
   routing entry for **both** config files.
4. **New owned deterministic gate** — a fixture-coverage test asserting every
   non-external skill in `default-triggers.json` has a `tests/fixtures/routing/<name>.txt`,
   wired into `tests/run-tests.sh` (CI-blocking via `.verify.yml`). Closes the
   missing-fixture silent-pass.

The **enforceable floor is fully owned and deterministic** — it must not depend
on `writing-skills`/`skill-creator` being installed. The external skills are the
recommended quality layers on top (behavioral pressure-test + held-out LLM
trigger eval), not merge preconditions.

## Capabilities

### Added
- **skill-creation-gate** — deterministic done-gate + flow for creating/editing
  skills: required `writing-skills`, fixture-coverage enforcement, scaffold eval
  stubs, decoy-negative reward-hack resistance.

### Modified
- (none — new requirements are ADDED under a new capability to avoid MODIFIED
  canonical-body matching; the routing-engine changes are exercised by
  skill-routing regression tests but expressed as ADDED requirements here.)

## Impact

- `config/default-triggers.json`, `config/fallback-registry.json` (writing-skills
  role; REVIEW skill-creator hint).
- `skills/skill-scaffold/SKILL.md` (emit fixture + eval stubs, dual-file routing).
- `tests/` (new fixture-coverage test; regression for required-role selection).
- `CLAUDE.md` (3-stage flow + gotcha documentation).
- No runtime hook latency change (coverage test is CI-time, not hook-time).

## Out of Scope (deferred)

- Held-out LLM trigger-eval as a **hard** gate (stays advisory: manual-trigger,
  secret-dependent, fork-refusing).
- Phase B (composition `.completed` status≠verdict split).
- Phase C (correction-ergonomics rewrite of fix-loop / could-not-verify messages).
- LLM-judge / disagreement-as-signal over test diffs (revive only once a labeled
  held-out corpus exists).
