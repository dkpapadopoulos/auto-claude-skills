# Held-out triggering validation (skill-creator REVIEW stage)

The designated REVIEW-phase skill-authoring check. `skill-creator`'s `run_loop`
optimizes *description-based* triggering (the vanilla "model reads description and
decides" path); this repo instead routes on **regex triggers** in
`config/default-triggers.json`. So the faithful adaptation applies skill-creator's
held-out *methodology* to the repo's *actual* mechanism: 20 fresh realistic prompts
(none in the routing fixture), evaluated against the real regex with the same
lowercase + `[[ =~ ]]` engine the activation hook uses.

## Result

| | Fire | Silent |
|---|---|---|
| Should-trigger (persuasive prose) | 9 (TP) | 1 (FN) |
| Should-NOT-trigger (reference/procedural/code) | 1 (FP) | 9 (TN) |

Precision 0.90, recall 0.90 after two fixes applied from the first pass (0.80/0.80):

- **Fixed FP** — "make this error message less generic": T4's bare `it`/`this` matched
  any object. Tightened to require a prose noun (`this|the|my (piece|copy|writing|
  draft|prose|essay|blog|newsletter|intro)`); noun list kept free of substring
  colliders (`post`→"postgres", `article`→"particle", `column`→db-column excluded).
- **Fixed FN** — "draft a linkedin post arguing…": bare `post` was removed earlier
  (substring safety), which dropped LinkedIn posts. Re-added `linkedin post` as a full
  phrase (no substring risk) to triggers 1 and 2.

Both locked into `tests/fixtures/routing/authorial-judgment.txt`.

## Accepted residuals (deliberate scope, not defects)

- **FP** "write a blog post that explains step by step how to configure CI" — the
  `blog post` form triggers, but the content is a tutorial. Form-based routing can't
  read content; the SKILL.md "When NOT to use → tutorials" guidance handles this at
  apply-time. Not worth weakening the `blog post` trigger.
- **FN** "i need a keynote intro…" — authoring intent phrased as "i need" rather than
  write/draft/compose. Broadening the verb set to need/want would re-introduce false
  positives; the current verb scope is the safe boundary.
