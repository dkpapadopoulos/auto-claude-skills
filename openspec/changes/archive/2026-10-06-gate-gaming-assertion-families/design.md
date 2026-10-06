# Design: gate-gaming assertion families and a workable remedy

Retrospective: written after PR #339 merged.

## Architecture

- `gate-gaming-check.sh` runs its existing pipelines unchanged, then one awk pass over the same diff. The pass reads each hunk header's line counts and consumes exactly that many lines as the hunk's body, counting assertion lines per file. A file is reported when more were deleted than added.
- `verify-and-record.sh` stores up to ten flagged lines in the verdict as `gate_gaming_hits`.
- `hooks/lib/verdict.sh::verdict_unclean_remedy` renders a not-clean verdict as text. `verdict_gate_gaming_hits` returns the flagged lines for diagnostics.
- `openspec-guard.sh` uses the remedy in its routing-governance deny when the verdict is for exactly the pushed commit; otherwise the previous text stands. `gate-status.sh` prints the same remedy, and the flagged lines under a label saying they are data.

## Decisions & Trade-offs

- **Net loss, not any deletion.** `suspect` denies a push. Over 537 mainline commits that touch tests, any-deletion over the new families flags 83 (ordinary edits to an assertion's expected value); per-file net loss flags 12.
- **Per file, not over the whole diff**, so assertions deleted from one file are not paid for by unrelated ones added to another. The cost is a known false positive: a test file split in two reads `suspect`.
- **The old list keeps any-deletion.** Changing it would loosen current evidence. Whether it should move to net loss is an open owner decision.
- **No branch text in the instruction.** Cross-family review rejected the first cut for quoting flagged diff lines inside text a model reads as the guard's instruction; a later review found gate names had the same property. Both are text the branch author chooses.
- **Hunk structure.** The first cut treated any line starting with three dashes or pluses as a file header, so a source line imitating one moved later deletions to another file, where new assertions paid for them. Measured: that diff read clean.

## Known limits

- An assertion swapped for a vacuous one in the same file reads clean.
- A house idiom not named assert-something is not seen.
- A combined diff, and input cut off inside a hunk, are not read by the new pass.
