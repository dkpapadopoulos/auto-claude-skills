# The IMPLEMENT shadow reader reads past a malformed line (#454)

## Why

Four reads in `scripts/shadow-adjudicate.sh` used plain `jq`, which stops at the first line it cannot parse and returns only what came before. Found by the review of the #453 fix; both predate it.

- Sidecar (`_adjudicated_ids`, `_episode_verdict`): one truncated line hid every label after it. Measured on a 30-episode corpus with the truncated line ahead of the only `false_block`: the rate went from 1/30 to 0/29 and the band to DENY. `--next` offered the labelled record again.
- Corpus (`_record_field`, `_episode_wb`): `--next`, which already read with `-R fromjson?`, offered a record after a truncated line; the label command answered "no record", and `--status` filed its episode under malformed `would_block`.

## What changes

- All four reads use `-R` with `fromjson?` and keep objects only.
- `--status` prints `unparseable labels N` for sidecar lines that hold no label: unparseable, not an object, or an object without a string `record_id` and one of the three verdicts. Such a line no longer supersedes an earlier label for its record. Measured before: an object with no verdict, appended after a human `false_block`, turned 1/30 into 0/29, band DENY, and counted 0.
- `--status` prints `rate cannot check` in place of a rate, band and worst case while any of five counts is above zero: unparseable labels, orphan labels (a label naming a record the corpus does not hold; new row), unparseable corpus lines, adjudicable records with a malformed `ts`, and episodes excluded for a malformed `would_block`. In each case a record can leave the denominator while its label stays behind unseen (measured for each: 1/31 became 0/30, band DENY). The REVIEW reader blocks its floor on the first, third and fourth (#386) and only warns about orphans; here an orphan withholds as well.
- The corpus line count is bytewise (`LC_ALL=C`) and counts objects, not printed ids, so a line of invalid bytes is counted and an id holding a newline cannot cancel an unparseable line.
- A label whose `claimant` is not a string is read as agent-claimed instead of vanishing.

## Consequence

The corpus is append-only and this reader never rewrites it, so one truncated corpus line withholds the rate for good unless the line is repaired by hand. Removing the line does not help when the record was labelled: the label becomes an orphan and the rate stays withheld. That is deliberate. The reader cannot tell a lost `false_block` from a lost `true_catch`.

## Not changed

- No predicate or schema version, no writer, no band rule.
- A corpus record that parses but makes a jq filter fail (a numeric `ts`, an object in `branch`) is still dropped with no row. No writer produces one.
