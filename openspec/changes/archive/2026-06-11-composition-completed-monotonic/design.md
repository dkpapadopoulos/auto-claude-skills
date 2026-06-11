# Design: composition-completed-monotonic

## Architecture

Single-site change in the walker's composition-state write block (`hooks/skill-activation-hook.sh` ~line 1050). Before the final `jq -n` write, if `~/.claude/.skill-composition-state-<token>` exists, one jq call (`--slurpfile`) compares the prior `.chain` to the new chain; on equality it replaces the computed prefix with `[ $chain[] | select(member of prefix ∪ prior completed) ]` — a chain-ordered, deduplicated union that also drops out-of-chain debris. All readers (`_comp_active`, sticky CURRENT lookup, push-gate membership checks) are order-insensitive and unchanged.

## Dependencies

None new. `--slurpfile` requires jq ≥1.5 (2015); on older jq the call fails and the write degrades to the pre-fix prefix-only behavior — fail-open holds, only monotonicity is lost.

## Decisions & Trade-offs

- **Union, not a length floor.** A `max(disk length, prefix length)` floor would fabricate entries when the disk array is not a chain prefix (e.g. completion hook recorded a later skill while an earlier one was skipped): it could mark requesting-code-review done because openspec-ship's completion bumped the count. The union keeps exactly what was recorded plus the anchor-implied prefix.
- **Chain equality as the union gate.** Chain switch is a legitimate reset (new feature cycle anchors a different chain); unioning across chains would leak stale completions. Pinned by `test_completed_resets_when_chain_differs`.
- **`current_index` not floored.** It drives only the display markers; flooring it would couple display to gate semantics. The push gate reads `.completed` membership only. Accepted display quirk: after a backward re-anchor, a completed step can show as CURRENT.
- **Was the old truncation a safety feature?** No — reviewed and rejected: ce88014's own comment treats `.completed` regression as a bug; the completion hook already promised idempotent append-only merge; and the re-arm fired only when prompt wording happened to contain an earlier trigger substring ("pr" in "PR49"), which is noise, not a control.
- **Fixture prompt wording matters:** "openspec" contains "spec" and hijacks the anchor to writing-plans (chain switch). The monotonic fixture uses "archive the feature as built" (no `spec`/`plan` substring) plus preconditions (chain-unchanged assert, writer-ran canary via `current_index` 2→1) so registry edits cannot make it pass vacuously.
