## Architecture

Two functions and one block in `scripts/verify-and-record.sh`, immediately before the gate-gaming diff is taken.

1. `_gg_declared_scope` reads a `.verify.yml` on stdin and prints `none`, `bad <reason>`, or `ok` followed by one path per line. It recognises this one key; it is not a YAML validator.
2. `_gg_scope_at <rev>` applies it to `<rev>`'s `.verify.yml` — only if that is a regular file in `<rev>`'s tree — and checks each entry against `<rev>`'s own tree (a diff of the empty tree against `<rev>`, under ordinary pathspec rules).
3. The writer resolves it twice: at the merge-base `_routing_base` already resolves for the diff, and at `HEAD`.
4. The merge-base's result selects the pathspec: declared paths plus `.verify.yml`; or the name glob when there is no declaration; or nothing at all — the check does not run — when the declaration cannot be applied.
5. If the two results differ, and it is not the case that every path declared at the merge-base is still declared at `HEAD`, a `clean` status becomes `suspect`.
6. The verdict gains `gate_gaming_scope`, `gate_gaming_paths` and `gate_gaming_scope_change`.

The checker is not changed. It matches text and cannot tell a marker from a quotation of one; which files it is shown is the caller's decision, and that is where the change is.

## Trade-offs

**What the declaration costs.** It is a claim that the listed paths cover what the gate runs, and nothing checks the claim. `tests/test-gate-gaming-scope.sh` holds an inventory for this repository (every `tests/test-*.sh`, every test-named script elsewhere, and the two scripts one test delegates to), which catches a known file leaving the declaration. It does not catch a new file added elsewhere and wired in (cell K1).

**What it gains beyond #332.** A declaration can name paths the name glob misses. This repository's now includes `scripts/db-gate-race/validate-corpus.sh`, which the gate runs and the glob never selected.

**Two outcomes are stricter than before, both measured.** Moving a test file out of the declared paths reads `suspect` (its assertions leave the scope as deletions; under the glob it was a rename and read `clean`). And any branch that touches the declaration other than by adding paths reads `suspect`.

**Failing closed on an unusable declaration** means one bad entry on the mainline leaves every branch's check `unverified`, which denies routing pushes repo-wide until a person fixes it. That cost is accepted for two reasons: the alternative reads `clean` over a file the repository asked to have checked (cell Dn2), and a bad entry cannot arrive silently — the branch that introduces it is `suspect` and the writer prints the entry (cell F5).

**Reading from the merge-base** means a new false positive on a branch cannot be cleared from that branch. That is deliberate: a remedy an agent can apply to its own branch is also an evasion an agent can apply to its own branch.

## Dissenting views

- **Anchor the marker to the start of the line.** Rejected: the #332 line starts with the decorator, so it would not have helped, and it creates real misses (`pytestmark = pytest.mark.skip(...)`, `marks=pytest.mark.xfail`).
- **A reviewed exemption list keyed by file and line.** Rejected: read from the branch it is a self-exemption; read from the merge-base it saves nothing over a hand push, because once merged the line never appears in a diff again.
- **Track string literals in the checker.** Rejected: a per-language lexer in Bash 3.2, and the skill already records that more regex did not generalise across held-out sets.
- **Fall back to the name glob on an unusable declaration** (this change's first cut). Withdrawn after cross-family review produced a declaration for which the fallback is narrower than what was declared.
- **Leave edits to the declaration unflagged** (also the first cut, argued from "an edit has no effect on its own branch"). Withdrawn after the same review: it lets a scope reduction read `clean`, and an advisory about an evaluator surface is weaker than recording the weakening.
- **Cross-family review's verdict on the first cut was REVERT**, on those two points and on over-stated claims. The claims are corrected here rather than defended: "a branch cannot change the scope it is judged by" holds only against a fixed base, and the inventory cell is not proof of coverage. **Its verdict on the rework was KEEP**, with three corrections that are applied: K1 shows the checker's blindness and not a loss of executed coverage; a changed declaration turns `clean` into `suspect` but leaves `unverified` as it is; and `widened` means only that no base path was lost.

## Decisions

- Option 1 of the four in issue #332, chosen by the owner on 2026-10-05.
- The name glob stays the default. No installer's verdict changes until they add the key and merge it.
- `scripts/backtest-evaluator-surface.sh` keeps the name glob. It is a calibration instrument over history, each row of its table carries its own measuring commit, and changing its population would silently change what those rows mean.
- The hand-authored fallback in the skill (no `.verify.yml`) keeps the name glob: with no `.verify.yml` there is no declaration to read.

## Known limits

- **A new test file outside the declared paths**, imported from inside them, is not reported (K1). Against deliberate evasion this costs nothing new — a file without "test" or "spec" in its name was never selected by the glob either. Against an accidental weakening it is a real loss: the glob caught a conventionally named test file wherever it lived, and a declaration does not. That is the trade this change makes. K1 measures the checker's output, not test execution.
- **The merge-base is resolved from local refs.** Moving the local mainline ref to HEAD empties the diff, with this change and without it (K2a). Moving it onto a commit that narrows the declaration is the same primitive, and is new only in that there is now a declaration to reach (K2b). The verdict file is itself writable by the same shell. The declaration adds no cheaper route than already existed, and it is not a trust boundary.
- **A merged narrowing governs later branches** (F7).
- **Not addressed, and found on the way:** the checker's removed-assertion pattern wants `assert` as a whole word, so deleting an `assert_equals …` line — this repository's own assertion helper — is not matched at all. A removed comment line containing the word "assert" is still `suspect` (3 of the 9 historical commits), and a marker quoted inside a real test file is still `suspect` (this change's own tests). All three are the checker's text match, not its scope.
- **Only BSD awk was exercised.** The parser uses no construct known to differ under gawk or mawk, but that is a reading, not a measurement.

## Out of scope

The deny text for a `suspect` verdict still tells the agent to re-run verification, which cannot clear it. Fixing that needs the verdict to carry the offending lines and is a separate change.
