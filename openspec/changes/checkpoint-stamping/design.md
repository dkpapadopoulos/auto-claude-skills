# Design: checkpoint stamping (issue #129)

## Architecture

Two units, one seam:

1. **Attribution (model, SHIP-time)** — `openspec-ship` Step 3 gains stamping guidance: while generating `tasks.md` from the Superpowers plan, consult `git log --oneline <merge-base>..HEAD` and append ` [checkpoint: <sha7>]` to each completed task the model can map to a specific commit with confidence. Tie-breaker (Codex C): stamp only when exactly one in-range commit matches the task by number or strong keyword; otherwise bare — never guessed. The `tasks.md` header carries a resolution note with the honest caveat (Codex A): after squash-merge, branch SHAs are *typically* recoverable via GitHub's PR refs when merged through GitHub's default squash flow — retrieval is `gh pr view <N> --json commits` (the squash title usually carries `(#N)`), and plain clones/forks do not fetch `refs/pull/*/head` by default.
2. **Integrity floor (deterministic)** — `scripts/checkpoint-validate.sh <tasks.md> [base-ref]` extracts every `[checkpoint: …]` stamp (all stamps on a line, not first-match; input case-normalized) and fails if any is malformed (not exactly 7 hex chars) or not a commit in `merge-base..HEAD`. Exit 0 clean, 1 integrity violation (skill must fix stamps before `openspec validate`), 2 unrunnable (missing file / not a git repo / unresolvable base — reported, never blocking anything downstream). Prints `checkpoints: N stamped / M completed tasks`; the skill folds that line into the ship report, which is the artifact the kill-criterion review reads. **Scope: pre-merge, on the feature branch only** (Codex B) — after squash-merge the stamped SHAs are no longer in main's history, so re-validating archived `tasks.md` is explicitly unsupported and out of scope, stated in both the script header and the skill step.

The split mirrors house style (cf. `verify-and-record.sh`): model judgment for content, deterministic external check for honesty.

## Capabilities Affected

- `openspec-ship` (modified): tasks.md artifact contract + mandatory validator step.

## Trade-offs

- **Squash-merge reality:** per-task SHAs are unreachable in fresh local clones after merge; resolution requires GitHub PR refs. Accepted and documented in the artifact itself (header note) — the alternative (stamping only the squash SHA) adds nothing over `git log` and would fail the kill criterion on day one.
- **Model attribution can be incomplete** (bare tasks) but not silently wrong: the validator catches fabricated/foreign SHAs, and bare-when-unsure is the honesty rule for the rest.
- **Validator is advisory tooling**, not a gate: wiring it into hooks would violate the issue's no-enforcement scope and the false-block discipline.

## Dissenting views

- Codex sparring (2026-07-19), verdict ADJUST: (A) the raw `refs/pull/N/head` durability claim was FLAWED as stated — server-side only, `(#N)` title is a default not a guarantee → header reworded, `gh pr view` named as retrieval; (B) post-merge re-validation of archived tasks.md would spuriously fail every stamp → declared out of scope rather than engineered around; (C) bare-when-unsure blocks false stamps but not confidently-misattributed ones → unique-match tie-breaker added, accepted as sufficient for doc-grade output; (D) `[base-ref]` retained (test fixtures need it); (E) no conflict with `openspec validate` (tasks.md is outside its schema) or the archive move.
- "Commit-message convention instead of model attribution" was rejected: this repo's `type: description` style gives near-zero retrospective coverage and imposes new discipline the issue explicitly excludes.

## Decisions

- Granularity: per-task stamps + header note; no phase headings (the template has none).
- Order-zip attribution rejected (silent misattribution in a traceability artifact).
- Stamp grammar: exactly 7 hex chars, case-normalized on read; multiple stamps on one line are all validated (duplicate-stamp fixture required).
- Kill criterion instrumentation = the validator summary line in the ship report; no new telemetry.

## Out-of-Scope

- Revert-with-task-state-reset (deferred in issue #129 until checkpoints prove useful).
- Any hook/gate/config wiring; stamping archived tasks.md files; commit-message conventions; PR-number embedding at SHIP time (unknowable — PR is created later in the chain).

## Acceptance Scenarios

See `specs/openspec-ship/spec.md` (GIVEN/WHEN/THEN).

## Implementation Notes (synced at ship time)

- Built as designed; three review-driven additions beyond the upfront spec: (1) the skill invokes the validator via `${CLAUDE_PLUGIN_ROOT:-.}` so it resolves in adopter repos, not only in this one (Opus review — near-critical); (2) the validator exits 2 when its validation loop is silently skipped (here-doc temp-file failure) instead of falsely reporting clean (Codex review); (3) stamp extraction tolerates a missing space after the colon and the completed-count includes indented subtasks.
- Dogfooded on this change's own `tasks.md`: `checkpoints: 3 stamped / 4 completed tasks`, exit 0 (task 1.4 bare per the unique-match tie-breaker — two review-fix commits are ambiguous).
- Archive deliberately deferred (matches current repo practice: recent shipped changes stay active under `openspec/changes/` so CHANGELOG spec pointers remain valid; archive happens in a later pass).
