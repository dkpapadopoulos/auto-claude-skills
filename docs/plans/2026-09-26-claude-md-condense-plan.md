# CLAUDE.md size: what shipped, and why phase 2 changed shape

## Phase 1 — DONE, verbatim relocation (+ a re-partition the measurements forced)

36 Gotchas bullets; 30 moved into seven path-scoped `.claude/rules/*.md`, 6 kept.
CLAUDE.md 155,496 -> 11,078 chars. Byte-identity of every moved bullet verified by
diffing sorted bullet sets before/after; 0 duplicates; frontmatter YAML parse-checked
(a rule whose YAML fails to parse loads UNCONDITIONALLY with no error, which would
silently undo the whole change); every glob asserted to resolve to real files.

**The headline number was misleading and measurement caught it.** `git log -200`:
`config/*.json` is touched by 169/200 commits, `tests/` by 200/200. The first cut put
bullet #248 (22,097 chars, whose subject is the `config/*.json` precondition render)
in `push-gate-enforcement.md`, so that 84,270-char file was globbed onto
`config/*.json` and would have loaded in ~85% of sessions. #248 is now its own rule
with narrow globs. Still zero prose deleted.

Effective always-loaded context, by session shape:

| session | before | after |
|---|---|---|
| docs / prose only | 155,496 | 11,078 (-93%) |
| typical routing or config edit | 155,496 | ~62,700 (-60%) |
| editing the guard itself | 155,496 | ~124,700 (-20%) — the session that wants the detail |

## Phase 2 — condensing the prose: NOT RECOMMENDED as previously planned

A critique round with Codex (critique mode, package
`e6ec9341...de15f4`) landed eight objections. Seven are accepted; two were verified
by measurement rather than taken on trust, and both held:

1. **Isolation was broken (verified).** A `git worktree add --detach` subject
   recovered all 155,496 chars via `git show HEAD:CLAUDE.md`, including the pilot
   bullet. Detaching HEAD changes branch attachment, not object access. Any behavioral
   A/B needs an exported snapshot with no original git metadata, not a worktree.
2. **"Mechanism" is not a safe deletion class — the strongest objection.** My anatomy
   sorted sentences by literary form. What reads as implementation detail is often a
   trust boundary, a compatibility contract, or a negative requirement: "the parsers
   report and validate nothing", "ledger reads deliberately stay on the process root",
   "omitting the new arg is byte-identical prior behaviour". "The code is the mechanism"
   fails exactly when the task is to CHANGE the code — current code shows what exists,
   not which properties must survive the edit. Correct classifier: **what wrong edit
   does this passage prevent?**
3. **The 5,000-char target was fitted to look achievable.** It was. Derive a target from
   an obligation inventory, then measure the size; treat size as an outcome, not a goal.
4. **Behavioral gate was underpowered.** 3 tasks x 5 runs = 3 tested situations, not 15.
   At 15 iid trials, 0 failures gives a one-sided 95% upper bound of ~18% on regression
   probability. This repo applies an n=29 Clopper-Pearson floor to its own deny-flips;
   3x5 is far below the bar it uses elsewhere.
5. **18/20 averages non-fungible items.** The two permitted misses could be repo-identity
   validation and revision-only lookup. This repo's own rule: safety dimensions are hard
   pass/fail gates, never averaged into a quality blend. Violated by my own threshold.
6. **Test headers preserve storage, not instruction.** Nobody reads a test header unless
   already editing that test. Keep >=1 minimal counterexample per distinct tempting
   mistake in the scoped rule; archive only repetitive chronology.
7. **Cheap gates can pass a destructive condensation.** Also: my claim that rot is "the
   actual decay mode" is unsupported — measured rot is ZERO (all 52 named test files,
   every path, every fixture exist). Link integrity is a maintenance check, not evidence
   for semantic preservation.
8. **A bullet is a formatting boundary, not an experimental one.** The pilot bullet spans
   command parsing, guard validation, verdict helpers, ledger writers and deny rendering.
   The right experimental unit is one obligation cluster.

**And the argument that decides it, which neither the plan nor the critique put first:
phase 2 has no measured benefit.** Phase 1 already removed this prose from every session
that does not touch the guard. Phase 2 only affects sessions that ARE editing the guard —
precisely the sessions that want the detail. So it trades a real, unmeasured risk of
deleting a load-bearing constraint against a context saving in the one place the context
is earning its keep.

## Recommendation

- **Do not condense now.** Re-partitioning is strictly better: same mechanism, measurable
  win, zero deletion risk, reversible.
- **Ship two cheap maintenance gates** — a per-rule-file char ratchet and a link-integrity
  check with a count floor — labelled as maintenance, explicitly NOT as evidence that any
  future condense was safe.
- **If condensing is ever revisited**, the unit is an obligation cluster, the classifier is
  "what wrong edit does this prevent", the target is derived not chosen, safety obligations
  are mandatory rather than averaged, and the subject runs in an exported snapshot with no
  git metadata. If that evaluation is unaffordable, keep the prose.

## Verification performed

- byte-identity of all 36 bullets, before vs after, sorted-set diff: PASS
- 0 duplicate bullets across the 7 rule files
- frontmatter YAML parses for all 7; `paths` a non-empty list of strings
- all 7 glob sets resolve to existing files (no dead patterns)
- control-character scan clean
- tests: incident-analysis-content 256, project-verification 46, done-gate-ci 12,
  knowledge 29, registry 199 — all pass. No working-tree mutation from test runs.
