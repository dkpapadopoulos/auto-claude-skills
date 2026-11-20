# Shadow readers: a shared record_id and a portable separator check (#453 items 3 and 4)

## Why

Issue #453 listed four items. Items 1 and 2 were fixed in PR #455, and the issue was then closed by a phrase in that PR's description, with items 3 and 4 still open. Neither is reachable by a current producer or caller.

- **Item 3.** When a countable record and a pre-separator record share a `record_id`, both readers counted a label for it twice: with the countable record, and again in the count of labels on pre-separator records, which the readout describes as not counted.
- **Item 4.** `shadow_acs_sep_json` in `hooks/lib/shadow-corpus.sh` validated the separator with a `[[ =~ ]]` test. The issue described this as validation skipped under dash. Measured, it is two different things: dash stops on that line with a syntax error, so the file does not load there at all, and zsh drops the backslash of the unquoted `\.`, so the two-part `3.103` resolved to `[3,103]`.

## What changes

- `_presep_labelled` in both readers leaves out an id that a countable record also carries.
- The separator is validated with `case` and parameter expansion: three components, each `0` or up to nine digits with no leading zero. The file now loads under dash.

## Not changed

- What the function returns for a valid separator, and for a predicate the separator does not apply to.
- A duplicated `record_id` within the countable population still resolves to its first record.
