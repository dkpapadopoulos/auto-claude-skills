# The design seed must put a missing-state reason where the reader meets the value

## Why

Issue #299 reported that `assets/design-seed/styleguide.md` names the three value
states (zero, missing, empty) but never says where a treatment has to appear. Two
seeded pilot arms lost the same dimension: one put the reason in a `title`
tooltip, one in a note below the table.

Reading the seed showed the gap is larger than the issue states. The seed did not
merely omit the placement rule. It prescribed the losing pattern in three places:

| Site | v1 text |
|---|---|
| `styleguide.md`, Missing row | "`—` in `--value-missing`, with a title attribute saying why" |
| `reference.html`, three cells | the reason carried only in `title="…"` |
| `reference.html`, caption | "a different glyph, a different token, and a reason on hover" |

The arm that lost on the tooltip was following the seed. Appending the rule the
issue suggests, and nothing else, would leave the styleguide contradicting itself
three lines apart, with the reference page still demonstrating hover.

## What Changes

- The styleguide's Missing treatment becomes a visible reason, in words, beside
  the value.
- The styleguide states the placement rule in terms that are not table-specific:
  the reason belongs in the same unit as the value (row, card, field). A `title`
  attribute, a footnote or a legend may add detail and does not treat the state.
- The reference page drops the three `title` attributes. Its row already carried
  a visible reason (the "Stale price" status), and the caption now points at it.
- The preset version moves from 1 to 2 at all six sites that state it.

## Capabilities

- Modified: `design-foundations`

## Impact

- `assets/design-seed/styleguide.md`, `reference.html` — guidance and its
  demonstration.
- `assets/design-seed/tokens.css`, `tokens.json`, `ADOPT.md` — version only.
- `tests/test-design-seed-missing-state.sh` — new.
- `tests/fixtures/design-seed/v1-missing-state/` — the v1 bytes, copied verbatim
  from `07cb5910`, used as red controls.

Projects that already adopted the seed are unaffected. A copied seed belongs to
the adopter and the plugin never rewrites it, so their `design/` keeps the v1
guidance and their `adopted.json` keeps `"version": 1`. That is why the version
changes: it is the only record that tells the two apart.
