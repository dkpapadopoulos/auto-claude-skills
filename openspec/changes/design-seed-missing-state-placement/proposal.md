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

- The styleguide's Missing treatment becomes a reason in words, visible in the
  same row, card or field as the value.
- The styleguide states the placement rule in terms that are not table-specific:
  the reason belongs in the smallest unit that holds the value (row, card,
  field). A `title` attribute, a footnote or a legend may add detail and does not
  treat the state.
- The reference page drops the three `title` attributes. Its row already carried
  a visible reason (the "Stale price" status), and the caption now points at it.
- The preset version moves from 1 to 2 at the five sites that state it.
- The command in `ADOPT.md` that regenerates `tokens.json` stops stating a
  version. It reads the preset name and version from the adopter's
  `design/adopted.json`, and replaces `tokens.json` only when it succeeded.

## Capabilities

- Modified: `design-foundations`

## Impact

- `assets/design-seed/styleguide.md`, `reference.html` — guidance and its
  demonstration.
- `assets/design-seed/tokens.css`, `tokens.json` — version only.
- `assets/design-seed/ADOPT.md` — version in the adoption block, and the
  regenerate command.
- `tests/test-design-seed-missing-state.sh` — new.
- `tests/fixtures/design-seed/v1-missing-state/` — the v1 bytes, copied verbatim
  from `07cb5910`, used as red controls.

A copied seed belongs to the adopter and the plugin never rewrites it, so an
earlier adopter's `design/` keeps the v1 guidance and their `adopted.json` keeps
`"version": 1`. That is why the version changes: it is the only record that
tells the two apart.

There is one path by which the plugin's current files still reach an earlier
adopter. Adoption deletes their copy of `ADOPT.md`, so anyone regenerating
`tokens.json` reads the plugin's current one. Before this change that command
stated the version itself. Review measured the result of bumping it: a v1
adopter's `tokens.json` came out stamped version 2 while their guidance and
their `adopted.json` stayed at 1. The hardcoded version predates this change,
but it could not mislabel anything until there was a second version.
