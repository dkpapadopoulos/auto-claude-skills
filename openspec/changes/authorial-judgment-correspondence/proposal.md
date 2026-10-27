# authorial-judgment: fit the skill to its measured use; make the UI hint actionable

## Why

`authorial-judgment` is used on emails, cover letters, recommendation letters and website
copy, always invoked by name, never through the router. Its scope says essays, posts,
op-eds, newsletters and talks; its triggers produced 12 mandates on the owner's machine,
all wrong, and missed every real use (measured 2026-10-27 over 1,487 transcript files).
Two third-party sources (a "humanizer" skill and its article; a "not vibe-coded" article)
add a few things the skill lacks (a diagnose-only output, voice matching from a sample, a
fact-preservation check, a marker for missing specifics) and many it must refuse
(mechanical burstiness, banned-word lists, invented precision, detector gaming). The
plugin's IMPLEMENT/REVIEW `frontend-quality-rules` hint names two uninstalled skills first
and rendered 9 times for one real UI task.

## What Changes

Skill content and hint text only. No trigger widening, no new routed skill, no change to
the external `frontend-design` skill.

- D1: description rewritten as "Use when ..." triggers covering correspondence and site
  copy; six correspondence prompts and two decoys added to `evals/evals.json`.
- D2-D7, D9: candidate wording for a per-genre applicability table, three output
  contracts (diagnose, rewrite, voice-match), a preservation check with `[NEEDS: ...]`,
  minimum effective edit, a conditional move 6, deletion of a canned sentence, and
  gate bulletproofing. **Each lands only if its RED baseline fails** on the current
  SKILL.md (writing-skills Iron Law); the decision rule is fixed in design.md.
- D8: the "procedural writing should be certain" rationale softened, with the spec
  delta below.
- D10: the `frontend-quality-rules` hint body replaced by an evidence-and-behaviour
  baseline; name, triggers and phases unchanged.
- D12 (builder's call): a `bash scripts/preserve-check.sh` for the mechanical part of
  the preservation check.

## Capabilities

- `prose-quality` (MODIFIED): the suppression requirement's rationale, and an explicit
  statement that suppression governs inferred activation only. Further ADDED
  requirements for the output contracts and the preservation check are added to this
  change once RED decides which items land.

## Impact

- `skills/authorial-judgment/SKILL.md`, `references/red-flags.md`, `evals/evals.json`,
  `evals/pressure-test.md` (extended with the 2026-10-27 RED/GREEN runs).
- `tests/test-authorial-judgment-content.sh` (anchors for items that land).
- `config/default-triggers.json` (hint text only) and the regenerated
  `config/fallback-registry.json`; `tests/test-adversarial-governance.sh` assertions
  must still pass; negative-corpus scan before/after must be an empty diff.
- Routing precision: zero new mandates by construction (no trigger edit).

## Deferred (out of scope, with revival triggers)

1. Name aliases for `authorial-judgment` in the hook's name boost ("authorial
   judgement", "authoreal judgement"). Revive if a named request is ever NOT invoked.
2. Stripping `<pasted_content>` blocks from trigger, keyword and name-boost scoring.
   Revive with a negative-corpus replay using the real producer's wrappers.
3. `tests/fixtures/keyword-path/decisions.tsv` row 68 (`newsletter`): a field
   observation now exists.
4. G6 of the 2026-10-03 external-skill-repos design: slop patterns admitted only with a
   named defect and a leave-unchanged counterexample.

## Skipped

- `apple-design` routing, the article's aesthetic bans, `frontend-design` trigger
  widening, `[NEEDS]` as a general texture device. Reasons in design.md D11.
