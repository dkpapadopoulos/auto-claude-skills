## Why

Two defects in what a `suspect` verdict is made of and what an agent is told about it.

`gate-gaming-check.sh` matched deleted assertions with a fixed list of names between word boundaries. `_` is a word character, so a deleted `assert_equals` line read `clean` — this repository's own idiom, about 5,300 lines of it — and so did `assertFalse(`, `assertRaises(` and every camelCase name outside the four listed.

For every not-clean verdict the routing-governance deny said to run project-verification until it reports a clean verdict. For `suspect` that cannot work: the check re-reads the same branch diff. An agent loops, or concludes that pushing is impossible.

## What Changes

- **A second pass counts the missed assertion families per file and reports a net loss.** The fixed list and its any-deletion rule are unchanged and run on the same input; the result is old OR new.
- **Lines are attributed to a file by hunk structure**, never by what a line looks like.
- **The verdict records what was flagged** (`gate_gaming_hits`), and the writer prints it.
- **One helper turns a not-clean verdict into a remedy**: every blocker and what clears each. It is used by the push guard's deny and by `gate-status.sh`, and only for a verdict at exactly the pushed commit.
- **The deny carries no free text from the branch.** Flagged lines appear as a count; a gate name is shown only if it is a plain label.

What is denied does not change. Only the text does.

## Capabilities

### Modified Capabilities
- `project-verification`: gate-gaming detection covers the snake_case and camelCase assertion families; a not-clean verdict carries a remedy that can be carried out.

## Impact

`skills/project-verification/scripts/gate-gaming-check.sh`, `scripts/verify-and-record.sh`, `hooks/lib/verdict.sh`, `hooks/openspec-guard.sh`, `scripts/gate-status.sh`; `tests/test-gate-gaming-missed-assertions.sh`. Over the 537 mainline commits that touch tests, the new rule flags 12, of which 10 were not already suspect.
