# The IMPLEMENT shadow reader reports unreadable files and counts only what it offers (#453)

## Why

Two defects in `scripts/shadow-adjudicate.sh` that predate #452 and were filed from its review.

- A corpus or label sidecar that exists but cannot be read was treated as empty. Every read discards jq's error, and the checks used `-f`, not `-r`. Measured before the fix: with an unreadable sidecar, `--status` showed a labelled `false_block` as unadjudicated and `--next` offered the same record again; with an unreadable corpus, a label was refused as "no record". The REVIEW reader has reported both states since #416.
- `--next` ended with "all N record(s) are adjudicated", where N was every record of the adjudicable predicate. Records it never offers (attested, advisory-silent, or with an unparseable `ts`) were counted as adjudicated.

## What changes

- `--status` and `--next` say which file is unreadable and report no count, rate or record for it. `--rate-episodes` says it on stderr and exits 2, because its stdout is parsed and no rows would read as no episodes. A label is refused with that cause.
- `--next` counts the records it offers from, using the one filter it offers with, and names how many others were never offered. A corpus with records but none offerable says so, in words different from "no records yet" and from "all adjudicated".

## Not changed

- No predicate or schema version, no writer, and no rate rule.
- The REVIEW reader. Its `--next` has the same two gaps and is not touched here.
- Items 3 and 4 of #453 (a `record_id` shared across the separator; the lib's validation under dash), which nothing reaches today.
- Recording a label still repairs an unreadable sidecar's mode (`chmod 600`) before appending, as before.
