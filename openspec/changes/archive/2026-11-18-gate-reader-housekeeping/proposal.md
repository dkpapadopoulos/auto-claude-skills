# Gate reader housekeeping (#355, #381, #416, #435 items 1 to 3)

## Why

Four issues left small defects on the push gate's reading side and in its diagnostic readers. None is a known bypass. Each is a value that can be produced or accepted where a stricter one is already required elsewhere, or a readout that is wrong or silent.

## What changes

- **#435 item 1.** `review_sha_covers` and `review_reviewer_returned_sha` accept only a full object name (40 or 64 lowercase hex), the rule the ledger and verdict readers follow since #432. An abbreviated sha was accepted (7 to 40 characters) and a 64-character one was refused. Every producer writes `git rev-parse HEAD`, so no recorded sha stops crediting.
- **#435 item 2.** The four reading-side sites that resolved HEAD with a bare `git rev-parse HEAD` use `--verify --quiet`, which prints nothing in a repository with no commits where the bare form prints the word `HEAD`. Measured: the guard's output there is byte-identical before and after in four evidence states.
- **#435 item 3.** Decided: no predicate version bump for #432. `acs_version` 3.104.0 is the separator. Recorded in `.claude/rules/push-gate-telemetry.md` with the counts in `docs/history/rules-push-gate-telemetry.md`.
- **#381.** The guard writes no REVIEW or IMPLEMENT shadow record when it runs as the diagnostic capture's replay. The replay re-evaluates the same push, so its record duplicated the live one. Fixed at the writer, where the existing `phase_gate_log` call already skips the replay; the issue also allowed a reader-side dedupe, which every reader would have had to repeat.
- **#416.** In `scripts/review-shadow-adjudicate.sh`: an unreadable label sidecar is announced and counted uncountable; a sidecar line that parses to a non-object is counted unparseable; `--help` as the first argument is answered before the producer-lib refusal. In the tests: the E4 and MX blocks fail in a full clone when the base producer blob is missing (they printed a note and stayed green), and the hand-typed field lists of both mixed-schema cells are pinned to the schema they model.
- **#355.** `openspec_write_provenance` records the OpenSpec surface session-start detected (registry cache), or `unknown`, where it recorded the constant `none`.

## Not changed

- No predicate or schema version.
- The IMPLEMENT reader's `--help`, which sits behind the same kind of refusal; #416 named the REVIEW reader.
- The 13 literal-`HEAD` ledger records on the owner's machine, which the readers refuse.
- Existing archives' `source.json` files, which keep the `none` they were written with.
