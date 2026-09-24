
## `regress-*.sh.txt` — synthetic, and deliberately named apart

Two checker regressions found in PR review needed inputs that do not exist in
the suite's history, so these are AUTHORED rather than harvested. They are
named `regress-` precisely so the "harvested verbatim" claim, and the
`red-`/`green-` count floors that enforce it, keep meaning what they say.

- `regress-two-sections.sh.txt` — two independent sections, each arranging an
  absent tool. The first dedup keyed on `(file, rule)`, so the second was
  swallowed: the checker under-reported the file that needs it most.
- `regress-escaped-quote.sh.txt` — a `\"` inside a double-quoted string,
  followed on the SAME line by a `#` that is still inside that string, and then
  by the `PATH=` arrangement. `_strip_comment` walked with `for ... enumerate`
  and `continue`, which advances to the escaped character and then processes
  it, closing the string early; the `#` then reads as a comment and the rest of
  the line — including the arrangement — is discarded, so the rule stops firing.

  The one-line layout is load-bearing and the first draft did not have it: with
  the escaped quote and the `PATH=` on separate lines, the broken walk truncated
  nothing that mattered and the mutation failed no cell. `_strip_comment` is
  called per line, so a fixture can only discriminate when the mis-stripping
  removes something the rule depends on **from that same line**.

They live here rather than inline in the test file for a reason the checker
itself demonstrates: constructed inline, they ARE cells that arrange a
precondition, and the lint correctly flagged its own test file for containing
them.
