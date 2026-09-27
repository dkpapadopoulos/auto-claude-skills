# Negative routing corpus

224 prompts that must NOT route to a cross-family consultation skill (`second-opinion`,
`panel`) or to the other two consultation contracts (`design-debate`, `synthesize`),
accumulated across the consultation-routing work (PR #253). It was the instrument that
caught every false dispatch that session; until 2026-09-16 it lived only in a session
scratchpad.

`scan.sh`'s checked-skill list also covers `prototype-lab` (added 2026-09-27, alongside
the `side by side` trigger-narrowing fix below) as a general false-dispatch tripwire, not
a consultation contract. Unlike `frontend-design` — a separate plugin, forced to
`available: true` only in ad-hoc verification scripts because the synthetic HOME here
discovers no plugins (see memory note "routing A/B needs available skills") —
`prototype-lab` ships in THIS plugin and resolves `available: true` in that same
synthetic-HOME registry with no forcing needed, so it could be added directly to `scan.sh`
itself.

This is a **probe, not a suite test**: it runs the real activation hook once per prompt.

## Run

```bash
H=$(mktemp -d); mkdir -p "$H/.claude"
echo '{}' | HOME="$H" CLAUDE_PLUGIN_ROOT="$PWD" /bin/bash hooks/session-start-hook.sh >/dev/null < /dev/null
bash tests/probes/negative-corpus/scan.sh "$PWD" "$H" tests/probes/negative-corpus/negatives.txt > after.txt < /dev/null
diff tests/probes/negative-corpus/baseline-cc33396.txt after.txt
```

Each output line is `<skills that fired>\t<prompt>`.

## The rule

Scan **before** a routing-adjacent change and **after**; the delta must be empty, except
for a change that deliberately fixes a line listed as open below. A new line is a new
false dispatch until proven otherwise; a vanished line is lost recall.

The current baseline, `baseline-cc33396.txt`, has 10 firing lines — byte-identical to
`baseline-3367e49.txt`'s content, but produced by a `scan.sh` whose checked-skill list now
also includes `prototype-lab` (see above), so this file is the first to actually attest
that addition found zero steady-state false dispatches for it:

- **8 legitimate.** The same 8 as `baseline-0f86729.txt` (222 prompts), all adjudicated
  as legitimate cross-skill routings: explicit consultation requests that belong to a
  neighbouring contract.
- **2 known, open false dispatches.** Added 2026-09-17 from the round-7 held-out set
  (`tests/probes/consultation-acceptance/RESULTS-round7.md`), and not fixed:
  - `design-debate` on the "debate timer … rebuttal rounds" bug report. The bare word
    `debate` in its trigger matches, and that skill stays local.
  - `panel` on the HR "interview panel … each one of the reviewers' raw answers
    verbatim" prompt. The vendor-free clause matches, and that skill sends content to an
    external vendor, which since PR #255 still requires the user's approval. Left open
    on purpose on 2026-09-17: replaying 1,997 real prompts found none of this shape among
    the 588 a person typed, and a narrowing fix traded holes both ways. See
    `tests/probes/real-prompt-replay/README.md` for the measurement and the 2026-10-15
    revisit.

  A fix for either removes its line; the other lines must stay unchanged.

- **6 `prototype-lab` false dispatches, measured then fixed in the same change
  (2026-09-27), never appearing in a committed baseline.** Before `scan.sh` checked
  `prototype-lab` at all, its trigger's bare `side.by.side` alternative — plus an
  independent `"side by side"` entry in the SAME skill's `keywords` array in
  `config/default-triggers.json` (a substring-scored path that bypasses the trigger regex
  entirely, see `hooks/skill-activation-hook.sh`'s `keyword_score`) — fired on any
  "side by side" prompt regardless of subject. On this corpus that was: the dose-response
  plot, the API-response diff, the analysts'-opinions prompt, the hyphenated
  `side-by-side` eval-log prompt, the review-UI diff prompt, and the mobile
  layout-breakage bug report. These were display/comparison requests with no design
  variant in view, not prototype-lab's subject — fixed by gating the trigger on a nearby
  variant-shaped noun (variants/options/approach(es)/alternatives/designs/versions/
  mock-ups/layouts/prototypes) AND by dropping the now-redundant-and-too-broad
  `"side by side"` keyword entry. Both edits were necessary: the keyword alone kept 5 of
  the 6 firing even after the trigger regex was narrowed (measured — the keyword's exact
  literal match ignores the regex's proximity/noun conditions entirely, and the one line
  it didn't keep was the hyphenated `side-by-side` form, which doesn't substring-match the
  spaced keyword). See `tests/fixtures/routing/prototype-lab.txt` and
  `tests/test-routing.sh::test_side_by_side_requires_a_variant_noun` /
  `::test_side_by_side_pairs_differ_only_by_the_noun` for the regression fixtures.

Known limit: the registry is built in a synthetic HOME, so plugin-discovered skills that
could outscore a consultation skill are absent (see memory note "routing A/B needs
available skills"). Grow the corpus by adding prompts from real false dispatches; never
delete lines (`scan.sh` reads every line as a prompt, so there is no comment syntax;
record a retired prompt's reason in this README instead).
