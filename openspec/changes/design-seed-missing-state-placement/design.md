# Design: missing-state placement in the design seed

## Architecture

No code path changes. The seed is a set of static files an adopter copies, so the
change is to what those files say and show:

1. `styleguide.md` states the rule.
2. `reference.html` demonstrates it. `ADOPT.md` calls this page "the house
   composition", so it has to agree with the styleguide.
3. The preset version identifies which guidance a copy holds.

The test has six lints, split by what each can see. Each states its population
in the test file.

| Lint | Population | Red control |
|---|---|---|
| 1. No `title` attribute in a row holding a missing value | table rows containing a `missing` cell | v1 reference: exactly three |
| 2. Prose does not teach a hidden channel | the reference page, flattened | v1 reference |
| 3. A row with a missing value has words | the same rows as lint 1 | the live page with its status pill removed |
| 4. Styleguide prescribes a visible reason and states the rule | the Missing row, and the rule paragraph | v1 styleguide |
| 5. Every version statement agrees and is not 1 | every file in the seed, keyed on spelling | a copy with one site reverted |
| 6. Regenerating `tokens.json` keeps the adopter's version | the regenerate fence in `ADOPT.md`, run whole in bash and zsh | a copy of `ADOPT.md` with the version hardcoded |

Every control calls the same function as its lint.

## Decisions

**The rule is worded for units, not rows.** The issue asked whether "in that
row" is too strong for layouts that are not tables. It is. The rule names the
smallest unit that holds the value, and gives row, card and field as examples.
"Smallest" matters because units nest: the reference table sits inside a card,
and without it a note under the table would be "in the card".

**The Missing row and the rule paragraph say the same thing.** The first cut had
the row say "beside it" and the paragraph say "same unit". The reference page's
reason sits one to three columns from the dashes, so a reader following the row
literally would have found the reference page non-compliant.

**Lint 1 is keyed on rows, not on the missing cell's own tag.** Review fed the
first cut ten spellings of a hidden reason and six passed, including a `title`
on a child element and on the row. Each was a new spelling of the same fault, so
the lint's key changed instead of its pattern list growing.

**The regenerate command reads the version from `adopted.json`.** That file is
the record of what the adopter copied. The alternative was to keep a version in
the command and bump it, which is what restamped a v1 adopter as v2. The command
also writes to a temporary file and moves it into place, and `jq` raises an
error when it read no tokens, because a pipeline reports only its last command
and `awk` failing on an absent `tokens.css` would otherwise replace
`tokens.json` with empty maps.

**One reason per unit is enough.** The reference row has three missing values
with one cause. Repeating the reason in each cell would fight the density the
preset exists for, so the rule says to state it once in the unit.

**The `title` attributes are removed, not kept as detail.** The rule allows a
tooltip to add detail. The reference page still drops them, because a page that
is there to be imitated should show the required pattern without an optional one
beside it.

**The version lint is keyed on spelling, not on a file list.** The first count of
version sites found five. There were six: `tokens.css` states it in a comment.
A lint over named files would have passed with that site left at 1. There are
five again now, because the regenerate command no longer states one.

**The v1 fixtures are copies, and the test checks that.** Where git history is
available the test compares each fixture with `07cb5910` byte for byte. In a
clone without that commit it prints a SKIP line instead of passing.

## Trade-offs

- Lint 3 sees that a row has words. It cannot see whether the words are a good
  reason: `NaN` in the cell counts.
- Lint 1 sees a `title` attribute. It does not see `aria-label`, CSS generated
  content or a scripted tooltip. It also cannot tell a reason from other detail,
  so a `title` holding an unrounded value in such a row is reported too.
- Lints 1 and 3 see table rows. A missing value in a card outside any table is
  covered by the styleguide's rule and by no lint.
- Lint 4 pins phrases. A rewording that keeps every pinned phrase and changes
  the meaning passes.
- v1 passes lint 3, because its row already had the status pill. The v1 fixture
  therefore cannot be that lint's control, and a mutated copy of the live page is
  used instead.
- The reference page shows several values missing for one reason. It does not
  show a reason written inside a single cell.
- An adopter with no usable `design/adopted.json` can no longer regenerate
  `tokens.json`. The command fails and says why. That includes a project whose
  own `adopted.json` has a different shape, such as one with no `version`.
- The regenerate command replaces `tokens.json` with `mv`. A symlinked
  `tokens.json` becomes an ordinary file, its permissions return to the default,
  and a read-only one is replaced without a prompt. `ADOPT.md` says so.
- The temporary file has a fixed name. A symlink planted at
  `design/tokens.json.new` is written through. It needs write access to the
  reader's own `design/`, so it is left as it is.
- A reader who pastes every line of the command except the last gets exit 0 and
  a stale `tokens.json`. That is inherent to a command of several lines.
- The command sees an empty theme. It does not see a truncated one: a dark block
  holding one token passes.
- Lints 1 and 3 split the page on `<` and `>` and do not parse it. Either
  character inside an attribute value hides a tag from lint 1 and makes attribute
  text read as words to lint 3. A pill carrying `hidden` still counts as words.
- The test ran on BSD tools under bash 3.2 and zsh. GNU `grep`, `sed` and `awk`
  are unverified: none is installed on the machine that ran it.

## Out of scope

- Whether a reader follows the amended guidance. That is a question about
  generated screens and belongs to issue #298.
- Any upgrade path for projects that adopted v1. The seed has none by design.
- Line 29 of the styleguide, which keeps the unrounded source value in a tooltip.
  That tooltip adds detail to a value that is already shown, which the new rule
  allows.

## Dissenting views

The scope, the version bump and the #298 comment were each put to the owner as a
choice, and the recommended option was taken in all three.

An independent review of the first cut found no fault in the direction of the
guidance and six gaps, five of them in the test. The author's ten mutations had
each reverted one of the author's own edits, so they held the lints against one
spelling of each fault. The reviewer's inputs are now cells in the test.

A second round found a fault in the fix for the sixth gap. The replacement
command read `adopted.json` without checking it, and `jq --slurpfile` reads an
empty file as zero documents, so an empty or version-less record made the
command exit 0 and write `null` for the preset and version. It also found five
branches whose named cells passed by another path: a cell that changes one of
three missing cells never tests the class quoting, because the other two keep
the row in the population.

## A consequence for issue #298

The placement rule was written from the deductions the pilot's judges made, on
the pilot's own brief. A replication that reuses that brief would measure a seed
tuned to its instrument. This is recorded on #298 so that the next registration
uses a fresh brief or declares the limitation.
