# Design: verify evidence scope

Date: 2026-11-17. Issues: #295, #343, #374. One branch, one PR, three commits in the order below.

## Intent

The push gate defends against a non-adversarial model skipping a step, not against one that forges
evidence (owner's decision, 2026-09-25). Every VERIFY evidence source is a plain file the agent can write.
The gate's text and its predicates should match that: accept a verdict only if it at least names something
that ran, measure the same diff however the push is spelled, and stop running an experiment nobody reads.

## Goals

- A verdict that names no check does not satisfy any gate leg.
- The same push produces the same diff base in both spellings.
- The measured-verdict leg stops rendering and stops recording, and its record says honestly why.
- Both supported writers (`verify-and-record.sh`, and the hand-authored shape in
  `skills/project-verification/SKILL.md`) still produce accepted records. A record accepted today that
  reports no check is invalidated on purpose, including one already on disk when the plugin updates; the
  recovery is to verify again.

## Non-goals

- Making any evidence source unforgeable.
- Requiring `writer`, `discovery_source`, `ts` or `substrate`. Under the threat model a hand-authored
  verdict that names its checks is legitimate.
- Replacing the retired leg with another experiment.

## Anti-goals

- Describing the schema check as provenance or as a security boundary.
- Recording the retirement as the registered null result. It is not one.
- A deny whose remedy the agent cannot execute.

## Approaches

**For #295** (the issue's options, plus what Codex was asked independently):

| Approach | Trade-off | Decision |
|---|---|---|
| A. Accept only harness-observed evidence | No such source exists; all five are agent-writable (measured 2026-09-24) | Not built |
| B, full. Require `writer`, `ts`, `substrate`, `schema_version` | Rejects every hand-authored verdict, which is the flip #343 was registered to decide and never did | Not built |
| B, narrow. One object, typed arrays, at least one named check | Closes the filed two-field case; friction only; changes no decision for either real writer | **Chosen** |
| C, claim. Say in docs and deny text what the verdict is | No behaviour change | **Chosen**, same commit |
| C, behaviour. Verdict no longer sufficient on the fail-closed leg | Can strand a repo with no other executable remedy; needs its own measurement | Not built |

Codex (independent mode, 2026-11-17) recommended the same pair and the same order, and warned that
"changes no decision for honest writers" must be tested. Measured: of 64 verdict files on the owner's
machine, 58 are clean, and all 58 carry at least one `passed` entry and a 40-character sha.

**For #343:** label all 299 episodes and about 47 a week after that, or retire. The owner chose retire.
Sampling cannot satisfy clause 3 of the rule, and changing the rule to fit the data is not open.

**For #374:** make the `refs/heads/<b>` spelling resolve the upstream as `HEAD` does (both spellings then
agree on the branch's own remote copy, which hides already-pushed commits), or try the mainline names
first (both agree on the mainline). The second is chosen: the function's contract is "mainline merge-base",
and it is the direction that measures more.

## Slice 1: `_routing_base` (#374)

- Order becomes `origin/HEAD`, `origin/main`, `main`, `origin/master`, `master`, then the subject's own
  upstream. The upstream is formed from the rev with a leading `refs/heads/` removed.
- The invariant is **the branch's net change against the mainline**, which is what a clone with
  `origin/HEAD` set has always measured. Selection is unchanged in kind: the first candidate that yields
  a merge-base with the subject wins; a candidate that does not resolve or shares no history is skipped.
- Effect in a repo with `origin/HEAD` unset and a `main`: the `HEAD` spelling now diffs against the
  mainline. Usually that is more files. It is not monotonic (Codex, critique): a routing file changed and
  pushed, then restored locally, shows in the diff against the branch's remote copy and not in the net
  diff against the mainline, so that push stops firing routing-governance. That is the chosen invariant,
  it matches every normal clone, and a test cell pins it so nobody later describes the reorder as
  "fires at least as often".
- Not settled here, and unchanged: detached HEAD, a stale local `main`, and `origin/HEAD` naming a branch
  other than `origin/main`. They behave as they do today.
- Effect on `scripts/verify-and-record.sh`: the gate-gaming diff uses the same base, so the case listed
  as F16 in #295 (an upstream naming the feature tip gives an empty diff) is closed when a mainline name
  resolves. It stays open when none does; the comment says so.
- Shadow corpora: this changes when `_diff_touches_material_source` is true, which the IMPLEMENT and
  REVIEW legs record. **My call, for the owner to overrule: no predicate-version bump.** `origin/HEAD` is
  first in both the old and the new order, so wherever it yields a merge-base the two predicates return
  the same base by construction, not by sampling. Measured 2026-11-17: every repository behind a
  current-version record (IMPLEMENT 6, REVIEW 3) that still exists has `origin/HEAD` set. So every pooled
  record, past and future, is one the NEW predicate would have produced. Codex argued for a bump on the
  ground that a version names semantics; the cost would be the REVIEW v3 window (106 records) for no
  record whose outcome differs. The commit and the telemetry rule state this argument.
- Test: one push, both spellings, `origin/HEAD` unset, equal base asserted; a control with no mainline
  name where both fall back to the upstream; the red control that the old order splits them; the
  restored-file cell above.

## Slice 2: retire the measured-verdict leg (#343)

- Remove Check 2b from `hooks/openspec-guard.sh` and the `_guard_load` of `verify-shadow.sh`.
- Before deleting anything, establish that Check 2b only appends to `_STALE_MSG` and writes a record:
  list every `_vm_*` variable and confirm none is read below the block. Then a paired cell: the same
  inputs give the same decision and the same deny text before and after the removal.
- Delete `hooks/lib/verify-shadow.sh`, `scripts/verify-shadow-adjudicate.sh` and
  `tests/test-verify-measured-verdict.sh`. They are deleted, not frozen, because git keeps them: the
  retirement section names the last commit that carries them and the command that re-reads the corpus
  from that commit.
- The 1,807-line test is inventoried first. A cell that pins a surviving reader (`verdict_is_measured`,
  `verdict_discovery_source`, failure precedence, the one-document rule) moves to `tests/test-verdict-lib.sh`;
  only cells exclusive to the leg are deleted. The plan carries the inventory as a table.
- Delete from `hooks/lib/verdict.sh` the readers nothing else calls after that. `verdict_is_measured` and
  `verdict_discovery_source` stay (`scripts/verify-receipt.sh` uses them). The plan lists consumers with
  `git grep -nw` before each deletion.
- Move `openspec/changes/verify-measured-verdict/design.md` to
  `docs/history/verify-measured-verdict-registration.md` and delete the change directory. Its spec delta
  adds requirements for a leg that no longer exists and must never be archived.
- The moved file gains a **Retirement** section holding: the `--status` output of 2026-11-17 verbatim;
  the record format, `schema_version` and `predicate_version`; the last commit carrying the reader and how
  to run it from there; and three statements kept apart. (1) Fact: no label was ever collected and no
  fortnightly read was made. (2) Fact: 341 of 383 records are pushes with no verdict file in repositories
  that declare no gate. (3) The owner's interpretation, not something the registration says: the recorded
  fields cannot show whether such a push skipped verification, so labelling them was judged not worth the
  work. It ends with: this is an owner decision informed by exposure data, it is not the registered null
  result, and predicate version 2 was never changed.
- `~/.claude/.push-verify-shadow.jsonl` and its sidecar are left where they are on every machine.
- Update `CLAUDE.md` (command table row), `docs/enforcement-map.md`, the globs and bullets in
  `.claude/rules/push-gate-telemetry.md`, and the `_COMBINED_BASELINE` ratchet in
  `tests/test-claude-md-rule-split.sh`, re-measured, in this commit.
- My call: `verify-shadow.sh` is not in `_GATE_ENFORCE_LIBS` (diagnostic only), so neither canary list
  changes. The plan verifies that before relying on it.

## Slice 3: a verdict must name a check (#295)

`verdict_is_clean` becomes, in one `jq -es` program:

- exactly one document, and it is an object;
- `failed`, `could_not_verify` and `passed`, where present, are arrays; `failed` and `could_not_verify`
  are empty or absent;
- `passed` is present, every entry is a string, and at least one entry has a non-whitespace character;
- `gate_gaming_status == "clean"`.

This requires a **reported** check. It does not show the check ran, and no text may say it does.

Not added: any check on `sha` (binding is `verdict_covers_head`'s job and #432 already refuses a
non-full object name there), and any check on who wrote the record.

- Error mapping is unchanged and stated: an absent file, no jq, or a file jq cannot parse all return
  non-zero (not clean), exactly as today. Callers already decide what that means: routing-governance is
  `_JQ_OK`-gated, and the global leg treats the verdict as one of five sources.
- `verdict_unclean_remedy` covers every way the predicate can now fail, and reports all that apply to one
  record, as it does today for the existing blockers. Two sentences are new: the record is not one
  well-formed verdict (more than one document, not an object, or a result field of the wrong type), so
  verify again to replace it; and the record reports no check, so verify again. A record that is both
  `suspect` and without `passed` gets both sentences. Asserted through routing-governance's deny and
  through `scripts/gate-status.sh`, not only at the function.
- The remedy named is the one today's "no covering verdict" deny already names. Where a repository has
  no declared gate, `project-verification` reaches the writer through `--name/--run` (#303). This change
  adds no deny in a state that had none except a record with no reported check.
- `scripts/verify-receipt.sh` already demands typed arrays and at least one check. The contract is one
  direction only: receipt PASS implies `verdict_is_clean`. A shared matrix (mixed entry types, a
  whitespace-only name, two documents, absent fields, a reported failure, a non-clean status) asserts
  that implication cell by cell.
- `verdict_any_failed`, `verify-hardening` and the token resolver are unchanged: a failing verdict stays
  authoritative whatever else it lacks.
- Text: the chain-verify deny note in the guard says "a two-field file satisfies the predicate", which
  becomes false. It is reworded to the claim that stays true: the verdict is written by the model or by a
  script the model runs, and no source is forgery-proof. `docs/enforcement-map.md`, the header of
  `hooks/lib/verdict.sh` and `skills/project-verification/SKILL.md` state the scope in the same words.
- Tests: the lib test takes its accepted fixture from a real `verify-and-record.sh` run and from the
  SKILL.md example with its `could_not_verify` emptied, not from a hand-typed record. Cells: the two-field
  record is rejected at the predicate and denies end to end on the fail-closed leg (control: the same
  record plus `passed:["tests"]` allows); a string-typed `failed` is rejected; two concatenated documents
  are rejected. The 72 seed lines that omit `passed` are classified first: a seed that stands for "a clean
  verdict" gains `passed`; a seed that is deliberately minimal or malformed stays as it is and its cell's
  expectation is checked. Each file is run after its edit.

## Constraints

- Bash 3.2, fail-open on infrastructure error, jq forks kept to the one existing call in the predicate.
- `hooks/lib/verdict.sh` is sourced by the model through skills, so zsh rules apply to anything added.
- Every edited file under `hooks/`, `scripts/`, `tests/` or `skills/` is opened with Read first.

## Verification

`bash scripts/verify-and-record.sh` on the final tree, read with `scripts/assert-suite-complete.sh`; the
push needs that recorded verdict because the branch touches `hooks/`. An independent reviewer reads the
branch before the push question.

## Left to the builder

The exact wording of the retirement section and of the reworded deny note; whether the seed-line edits go
through a shared helper or stay inline. One commit per slice.

## Critique record

Codex critiqued this design on 2026-11-17 (critique mode; it saw the design). Twelve findings. Taken:
the reorder is not monotonic (1), the compatibility goal was unprovable as worded (3), the remedy must
cover every new failure and combinations (4), `passed` entry typing (6), the receipt matrix (7), the
error mapping stated (8), reader auditability and a test inventory (10), the retirement's three
statements (11), the control-flow check before removing Check 2b (12). Narrowed: the base-resolution
contract beyond the two spellings (2) and remedy reachability where no gate is declared (5) are stated
as unchanged, not redesigned. Declined with reasons above: the predicate-version bump (9).

## Calls made on the owner's behalf

- One PR for the three slices, so the 13-minute gate and the review run once.
- The reader and its 1,807-line test are deleted with the writer instead of being kept as a frozen reader.
- The registration moves to `docs/history/` instead of staying under `openspec/changes/`.
- Spec deltas under `specs/` are written in the plan's first task, after reading the canonical
  requirement text they modify.
- GitHub comments and closes on #295, #343 and #374 are drafted at ship time and sent only on a yes.
