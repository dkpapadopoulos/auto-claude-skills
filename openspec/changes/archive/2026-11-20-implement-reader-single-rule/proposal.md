# The IMPLEMENT shadow reader withholds the rate on one rule (#454)

## Why

The #454 fix (PR #455) withheld the rate over five named kinds of damage. Four review rounds each found another input that removed a labelled `false_block` from the count while a band still printed, because every kind needed a check of its own. The fourth round's list: a `ts` with a trailing newline, a `would_block` edited from true to false, an edited or string `predicate_version`, record ids compared as numbers, ids holding a space, and records jq dropped on a runtime error.

## What changes

`--status` now withholds on three more counts, in addition to the five. The first two are subtractions that name no cause:

- **Labels outside the rate.** Every record with a valid human-claimed label must be a member of a would-block episode the readout found a label for. If it is not, it must be of another predicate version (new row `other-predicate labels`, no withhold: a predicate bump leaves such labels behind) or pre-separator (existing row, no withhold) or absent from the corpus (existing `orphan labels`, withholds). Anything else is counted in the new row `labels outside the rate` and withholds. No cause is named, so an input nobody listed lands there too.
- **Unplaced records.** The adjudicable records with an id and a parseable `ts` must be exactly the records the episodes hold, compared id by id. A difference either way is the new row `unplaced records` and withholds. This catches a record `@tsv` cannot print and an id holding a comma.
- **Superseded human labels.** An adjudicable record whose latest label is not human-claimed while an earlier one was. The verdict is the latest line per record, so one agent command removed a human `false_block` from k: alone in its episode the record became agent-claimed, and beside a human-labelled sibling the agent's verdict was counted as a human's. Found by the review of this change, and older than #454. New row `superseded human labels`; withholds until a human labels the record again.

Fixed outright, because they made the reader wrong on input that needs no damage:

- Labels are matched to records as strings. awk compared `100` and `1e2` as numbers; record ids are hex digests and can look like either.
- Episode ids are split on the comma only and never globbed.
- A repository name starting with a dash is no longer read by `grep` as an option, which counted every episode as a new repository.
- The `ts` check is one definition, type-checked and anchored with `\A..\z`. A numeric `ts` is now counted as malformed instead of being dropped by a jq error.
- Whitespace-only lines are not unparseable lines.
- `--next` uses the same definition of a label as `--status`, and no longer offers a labelled record again when its id starts with a dash or holds a backslash.
- New row `no record_id` for records that cannot be addressed. It does not withhold.

One behaviour change outside `--status`: the label command refuses a record `--next` never offers (not would-block, advisory-silent, or unplaceable `ts`), and compares `predicate_version` by JSON type. Without the refusal, one human label typed against an attested record would withhold the rate for good.

## Consequence

A human label already in someone's sidecar for a record in an attestation-only or advisory-silent episode now withholds the rate until the line is removed by hand. The reader could write such a label before this change, though `--next` never offered the record.

## Evidence

`tests/fuzz/shadow-adjudicate-fuzz.py` compares `--status` with an independent oracle over generated corpora. Against the reader as merged in #455, 238 of 2,000 cases failed, 144 of them with a rate printed over a human label that was not counted. Against this change, 0 of 20,000.

## Not changed

- No predicate or schema version, no writer, no band rule, no floor.
- A duplicated `record_id` still resolves to its first record. The writer's ids carry a nonce.
- The latest label per record still wins whoever wrote it. An agent's line after a human's now withholds the rate; it is not ignored.
- The REVIEW reader.
