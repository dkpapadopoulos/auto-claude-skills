# Design: missing-state placement in the design seed

## Architecture

No code path changes. The seed is a set of static files an adopter copies, so the
change is to what those files say and show:

1. `styleguide.md` states the rule.
2. `reference.html` demonstrates it. `ADOPT.md` calls this page "the house
   composition", so it has to agree with the styleguide.
3. The preset version identifies which guidance a copy holds.

The test has five lints, split by what each can see. Each states its population
in the test file.

| Lint | Population | Red control |
|---|---|---|
| 1. No reason hidden in an attribute | tags with class `missing` in the reference page | v1 reference: exactly three |
| 2. Prose does not teach hover | the reference page | v1 reference |
| 3. A row with a missing value has words | table rows containing a `missing` cell | the live page with its status pill removed |
| 4. Styleguide prescribes a visible reason and states the rule | the Missing row, and the file | v1 styleguide |
| 5. Every version statement agrees and is not 1 | every file in the seed, keyed on spelling | a copy with one site reverted |

Every control calls the same function as its lint.

## Decisions

**The rule is worded for units, not rows.** The issue asked whether "in that
row" is too strong for layouts that are not tables. It is. The rule names the
unit that holds the value, and gives row, card and field as examples.

**One reason per unit is enough.** The reference row has three missing values
with one cause. Repeating the reason in each cell would fight the density the
preset exists for, so the rule says to state it once in the unit.

**The `title` attributes are removed, not kept as detail.** The rule allows a
tooltip to add detail. The reference page still drops them, because a page that
is there to be imitated should show the required pattern without an optional one
beside it.

**The version lint is keyed on spelling, not on a file list.** The first count of
version sites found five. There were six: `tokens.css` states it in a comment.
A lint over named files would have passed with that site left at 1.

**The v1 fixtures are copies, and the test checks that.** Where git history is
available the test compares each fixture with `07cb5910` byte for byte. In a
clone without that commit it prints a SKIP line instead of passing.

## Trade-offs

- Lint 3 sees that a row has words. It cannot see whether the words are a good
  reason.
- Lint 1 sees a `title` attribute. It does not see `aria-label`, CSS generated
  content or a scripted tooltip.
- v1 passes lint 3, because its row already had the status pill. The v1 fixture
  therefore cannot be that lint's control, and a mutated copy of the live page is
  used instead.

## Out of scope

- Whether a reader follows the amended guidance. That is a question about
  generated screens and belongs to issue #298.
- Any upgrade path for projects that adopted v1. The seed has none by design.
- Line 29 of the styleguide, which keeps the unrounded source value in a tooltip.
  That tooltip adds detail to a value that is already shown, which the new rule
  allows.

## Dissenting views

None recorded. The scope, the version bump and the #298 comment were each put to
the owner as a choice, and the recommended option was taken in all three.

## A consequence for issue #298

The placement rule was written from the deductions the pilot's judges made, on
the pilot's own brief. A replication that reuses that brief would measure a seed
tuned to its instrument. This is recorded on #298 so that the next registration
uses a fresh brief or declares the limitation.
