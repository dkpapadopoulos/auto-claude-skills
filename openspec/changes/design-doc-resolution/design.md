# Design: readers find the design doc themselves

Approved by the owner 2026-11-16, after a Codex adversarial pass on the three follow-up
questions from PR #427.

## Intent

Stop depending on a model-performed state write for the two SHIP-time readers where a wrong
guess is cheap, and correct one printed sentence that states something unchecked. Add no
injected text.

## Goals, non-goals, anti-goals

- **Goal:** `openspec-ship`'s Divergences step and `deploy-gate`'s design-intent check resolve
  the design doc deterministically and say which outcome they got.
- **Goal:** the spec-driven session notice states only what is true.
- **Non-goal:** restoring any removed hint as prompt text, in any phase or at session start.
- **Non-goal:** moving or archiving a file on the strength of a filename match.
- **Non-goal:** a spec-driven presence check in CI or in the push gate.
- **Non-goal:** changing the PLAN-phase completeness note or the post-compaction change list.
- **Anti-goal:** a resolver that returns a plausible file as if it were the recorded one.

## Approaches

1. **Read-only resolver script called by the two skills (chosen).** One contract, testable
   without a model.
2. **A hook discovers and records the path.** Rejected: a filesystem scan on the per-prompt
   path (50 ms target) to serve two SHIP-time readers, and a state write on a guess.
3. **A shorter PERSIST DESIGN line.** Rejected: a display proposal; the original was run in 5 of
   188 sessions.
4. **Do nothing and document it.** Viable; rejected because the Divergences report is the one
   place design intent is compared with what was built, and it never ran in default mode.

## Decisions

1. **Four outcomes, and exit 3 is not one of them.** `resolved`, `stale`, `ambiguous`, `absent`.
   A state file that exists and is not exactly one JSON object of the expected shape exits 3
   with no output line. That includes a `design_path` of the wrong type: review measured a
   numeric one falling through to a filename match the caller would have described as "nothing
   recorded".
2. **A recorded path is checked and never silently replaced.** If the file is gone the outcome
   is `stale`, even when a file matches by name.
3. **`openspec-ship` resolves in Step 3, before anything is created or moved, and uses the
   answer in Step 7c.** Step 3 can write an as-built `design.md` into the change folder, Step 6
   moves that folder to `openspec/changes/archive/`, and Step 7b moves recorded docs to
   `docs/plans/archive/`. The first cut resolved at 7c and patched one of those moves inside
   the resolver (a same-named file under `docs/plans/archive/` counted as the recorded doc).
   The whole-branch review measured both halves failing: every spec-driven ship was told "No
   design doc found" because Step 6 had just archived it, and the patch resolved a recorded
   `openspec/changes/f/design.md` or a path outside the repo to an unrelated archive file with
   nothing in the output to say so, which is this design's anti-goal. The patch is removed. The
   reference file maps each source to where its doc is by Step 7c.
4. **No slug from the branch name** (Codex). A branch name is a candidate, not an identity. The
   calling skill knows the change slug and passes it. Without `--slug`, only the recorded arm
   runs, over changes not marked archived.
5. **Reading and archiving have different thresholds** (Codex). A filename match supports a
   labelled report; it never authorises a move. Step 7b is unchanged.
6. **Per-outcome instructions for `openspec-ship` live in a reference file.** The skill had 122
   bytes of its 19,500-byte re-attach budget left and Step 7c is near its end.
7. **The notice is a statement, not an instruction** (Codex; the owner picked the wording).
   "belongs in ... not verified this session". An instruction at session start would be a
   display proposal by another name.
8. **Diagnostics only where they change a decision** (Codex). "Design absent" and "no
   acceptance scenarios" are said at the Divergences step. "Plan omits existing scenarios" is
   left out: it needs the plan path, which has the same unrecorded-state problem.

## Trade-offs

- Exactly one date-prefixed filename match is evidence, not identity.
- The path-after-move mapping in the reference file is followed by a model, not computed. If
  the file is not where the table says, the instruction is to say so and write no report.
- Run a second time after a ship (a feature spanning sessions), the resolver reports a recorded
  doc that Step 7b already moved as `stale`, and the step asks the user.
- Content cells show the skill text is present; they do not show a model follows it.

## Dissent recorded

Codex's strongest objection stands: a deterministic helper called by an optional skill is not
deterministic coverage. A session that never runs `openspec-ship` or `deploy-gate` gets
nothing from this change.

## Verification

`tests/test-resolve-design-doc.sh`: each outcome and source, stale records with a same-named
decoy in the archive, prefix and metacharacter slugs, another session's state, twelve
wrong-shape state files each with and without a slug, no `jq` (with the
precondition asserted at run time), usage errors, and a before/after snapshot proving nothing
is written. Mutation controls on a scratch copy: seven of ten mutants fail a cell, three are
equivalent. The three tests pinning the notice moved to the new text and failed first.

## Left open

- A spec-driven presence check: define what it measures (missing spec at PR creation, at first
  code-bearing push, or at merge) before building anything.
- Whether the push gate's review record stays valid after later commits.
