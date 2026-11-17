# Pasted-content fixtures (#409)

Real bytes, copied exactly (trailing newline included) from this repository's own work.
Prompts from other projects were measured but are never committed.

| File | Source | Shape |
|---|---|---|
| `paste-only-escaped-inner-tag.txt` | The owner's #409 work order, pasted as the first prompt of session 17a24129 (2026-11-16, Claude Code 2.1.311). | Paste only. The harness escaped a tag inside the paste as `<\pasted_content>`. |
| `typed-before-and-after.txt` | A prompt of 2026-10-27 in this repository: typed text, a pasted PR #406 review, typed text. | Typed before and after one block. |
| `negative-issue-409-body.txt` | The body of issue #409 as filed. | Prose quoting the bare tag names; contains no wrapper. |

The wrapper the harness writes, in all 79 wrapped prompts measured 2026-10-01..11-16: a
blank line, `<pasted_content id="hhhh">` (4 lowercase hex), the pasted text, a closer
`</pasted_content id="hhhh">` with the same id, a newline. No unterminated, mismatched
or nested block was observed, so the tests DERIVE those shapes from these files by one
stated edit each and label them derived.

Consumers: `tests/test-pasted-content-lib.sh`, `tests/test-activation-paste-shadow.sh`.
