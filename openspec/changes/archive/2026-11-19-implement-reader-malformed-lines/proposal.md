# The IMPLEMENT shadow reader reads past a malformed line (#454)

## Why

Four reads in `scripts/shadow-adjudicate.sh` used plain `jq`, which stops at the first line it cannot parse and returns only what came before. Found by the review of the #453 fix; both predate it.

- Sidecar (`_adjudicated_ids`, `_episode_verdict`): one truncated line hid every label after it. Measured on a 30-episode corpus with the truncated line ahead of the only `false_block`: the rate went from 1/30 to 0/29 and the band to DENY. `--next` offered the labelled record again.
- Corpus (`_record_field`, `_episode_wb`): `--next`, which already read with `-R fromjson?`, offered a record after a truncated line; the label command answered "no record", and `--status` filed its episode under malformed `would_block`.

## What changes

- All four reads use `-R` with `fromjson?` and keep objects only.
- `--status` prints `unparseable labels N` for sidecar lines that are unparseable or parse to a non-object, and prints `rate cannot check` in place of a rate, band and worst case while N is above zero. A lost line may have been a `false_block`, and the REVIEW reader blocks its floor on the same count (#386).

## Not changed

- No predicate or schema version, no writer, no band rule.
- The corpus-side `unparseable lines` row, which already existed and does not withhold the rate.
