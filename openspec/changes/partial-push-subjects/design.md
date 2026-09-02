# Design: partial push subjects (#229)

## The asymmetry, and why it is the whole design

`command_push_ref` returning empty is ambiguous across three shapes. #227
announced that ambiguity and refused to act on it, for a reason worth restating
because it is the trap this change has to walk around:

> `command_push_subject_is_partial` fires if **any** push segment is partial, so
> suppressing a gate on it would let `git push --delete origin x; git push origin
> main` excuse the second push.

That reasoning is correct and it is not repaired by better parsing. It is
repaired by a **different predicate**. `command_push_is_all_deletions` is the
ALL-form: it returns 0 only when *every* push segment in the command deletes a
ref. Applied to the counter-example above it returns 1, because segment 2 is an
ordinary push — so the property "this command ships no content" is established
for the command, not inferred from one of its segments.

The ANY-form remains, unchanged and still announce-only. It is the right
predicate for "this command mixes a deletion with a real push", which is a real
thing to tell the user and which neither new predicate covers.

## Every segment must be accounted for — the regression this nearly shipped

The first working version of the ALL-form walked only the segments
`_gc_segment_git_sub` reports as `push`. An adversarial review caught that this
proves a **weaker** claim than the one being acted on:

> "All *recognized push* segments are deletions" ≠ "this command ships no content."

Measured against that version — all three certified as deletion-only while
shipping real content:

```
git push --delete origin x && git -c alias.p=push p origin main
git push --delete origin x && ./deploy.sh
git push --delete origin x && bash -c "git push origin main"
```

The first is the sharpest and needs nothing new from git: a **git alias** makes
`_gc_segment_git_sub` report the alias word rather than `push`, so the segment is
invisible to every precise predicate in the lib — and an alias sitting in
`~/.gitconfig` works exactly as well as the inline `-c alias.…=push` above.
Reproduced end-to-end against the real guard: a routing branch with no covering
verdict, ordinary push **DENIED**, the alias compound **ALLOWED** with the gate
announcing "ships no content".

**Why this had to be fixed rather than documented as a ceiling.** The lib already
documents that string detection cannot see through `bash -c`. But everywhere else
that ceiling degrades to *"fall back to measuring HEAD"* — safe. Certifying
deletion-only made the same ceiling degrade to *"skip the gate"* — a false allow.
That inversion is the whole difference, and it is introduced by this change: the
pre-#229 HEAD fallback covered this shape.

The fix is `_gc_seg_is_inert`: a segment that is not a recognized `git push`
disqualifies the command unless it is **inert** — empty, pure group punctuation
(`{ git push …; }` splits into a command segment and a bare `}`), or a `cd`
(which cannot push, and which the subject resolver already models).

**A whitelist, deliberately, not a blocklist of git subcommands.** The narrower
mitigation — "disqualify on a git invocation whose subcommand is not `push`" —
closes the alias case and leaves `./deploy.sh` and `bash -c` open; that is
pinned as mutation M11. An allowlist of non-pushing git *builtins* was also
considered and rejected: `git subtree push`, `git submodule foreach`, and
`git send-pack` all push, so the list would have to be provably complete rather
than merely plausible, and any future subcommand would silently join the safe
side.

The cost is bounded and is only a **forgone optimisation**: a compound command
whose extra segment cannot be accounted for falls back to measuring HEAD, which
is exactly today's behaviour. This can lose a skip; it can never add a deny.
Even `echo` is refused — the parser cannot tell `echo` from `./deploy.sh`
without exactly the kind of table this design just rejected.

## A command substitution runs wherever it appears

A second adversarial pass broke the whitelist itself. `cd $(git push origin main)`
has `cd` as its first word, so `_gc_seg_is_inert` vouched for it — while the
substitution executed a real push. Confirmed against real bash: the inner push
completes and the ref reaches the remote *before* the outer `cd` does anything
with the captured output (it then fails on git's stderr as a bogus path, long
after the damage).

Probing the shape rather than accepting the report showed it is **not specific
to `cd`**. Every one of these certified as deletion-only:

```
git push --delete origin scratch && cd $(git push origin main)
git push --delete origin scratch && cd `git push origin main`
git push --delete origin $(git push origin main)      <-- inside the DELETION
git push --delete origin x$(git push origin main)
git push --delete origin x < <(git push origin main)  <-- process substitution
```

The third is why the fix is a **whole-command** guard rather than a `cd`-scoped
one: the substitution is an argument of the *recognised deletion segment*, which
the obvious fix — guarding the whitelist entry — does not touch. Mutation M13
pins exactly that: narrowing the guard to `cd` leaves four of the five shapes
open.

`command_push_is_all_deletions` therefore refuses any command whose raw text
contains `$(`, a backtick, `<(` or `>(`. Per-segment or per-token is the wrong
level twice over: `_gc_split_segments` does not treat `$(` as a boundary, and
after word-splitting the construct is scattered across tokens (`$(git`, `push`,
…, `main)`) — which is precisely how it slipped past a first-word whitelist.
Coarse on purpose: a substitution inside single quotes is literal data and is
refused anyway, and an ordinary `"$VAR"` expansion is untouched (pinned).

## An untrustworthy parse cannot certify anything

A third pass found a bypass that contains **no substitution syntax at all**, so
neither guard above sees it:

```
git push --delete origin scratch; cd \'; git push origin main
```

The scanner does not interpret backslash escapes — its own header says so. To
real bash, outside an active quote, `\'` is a literal quote character; to the
scanner it is a quote that opens quote mode, and everything after it (a genuine
`;`, then a real push) is swallowed as quoted text. The result is one segment
whose first word is `cd`, which the whitelist vouches for. Confirmed against
real bash: the deletion runs, `cd \'` fails harmlessly, `;` does not care, and
the push lands on the remote.

The scanner **already knew**: it sets `_GC_UNBALANCED`, and `_gc_precise` in
`openspec-guard.sh` gates the other precise predicates on exactly that signal.
`command_push_is_all_deletions` simply was not asking. The check now lives in the
library function rather than at the call site: the function's contract is
already "any doubt returns 1", an unbalanced parse *is* that doubt, and a future
call site cannot forget to gate what the function gates itself. The same one
check covers the rest of that family — an incomplete heredoc, the 4096-character
scan budget — because they all set the same flag.

**Not applied to the announce-only predicates**, and that is a considered
difference from "apply it everywhere for consistency":
`command_push_subject_is_partial` and `command_push_is_multi_ref` fail toward a
possibly-wrong *advisory*, never a skipped gate — and their advisory ("HEAD may
not be what is pushed") is if anything *more* true when the parse is
untrustworthy. Gating them would suppress information to buy symmetry.

### The optimisation that silently re-opened it

`command_parse_balanced` re-runs the char scan, which is O(n²) in bash 3.2, and
this runs synchronously in a PreToolUse gate. Measured end-to-end against the
real guard with the check at the head of the function: **+44 ms** on a typical
push and **+535 ms** on a 4 KB command, against a pre-existing baseline of
727 ms / 6.1 s — so ~9%, not dominant, but avoidable. Moving the check onto the
**success path** confines the second scan to commands that would otherwise be
certified, and the typical-push cost drops into measurement noise.

That move is semantically identical — it can only turn a `return 0` into a
`return 1` — and it **silently re-opened the bypass**. `set -- ${_shape}` inside
the loop replaces the positional parameters, so at the end of the function `$1`
is a shape digit rather than the command. `command_parse_balanced "0"` parses
balanced, so the gate passed everything. The function now binds `_cmd="$1"`
before the loop.

The lesson is about how it was caught, not about the slip: it was found by
**re-running the attack probe after a change believed to be pure refactoring**.
The unit cell for it would also have caught it — but only on the next test run,
and the temptation after a "no behaviour change" edit is to skip that. In a file
where `set --` is the normal idiom for argument walking, `$1` below a loop is
not the argument, and nothing about the edit looks like it touches the predicate.

## Three orthogonal layers, and why none subsumes another

| Layer | Catches | Missed by the others |
|---|---|---|
| Segment whitelist (`_gc_seg_is_inert`) | a second command that ships content — alias, script, `bash -c` | parses fine, no substitution |
| Whole-command substitution refusal | `$(…)`, backticks, `<(…)` anywhere, including inside the deletion's own arguments | parses fine, every segment looks accountable |
| Balanced-parse gate | anything that makes segmentation itself wrong — escaped quotes, incomplete heredoc, scan-budget cutoff | contains no substitution syntax, and the bad segment's first word looks inert |

Each was found only after the previous one shipped, and each was reported first
as a single instance whose obvious fix would have closed just that instance.
Probing the *class* rather than the reported case is what turned three
one-off patches into three layers — and is what found the
substitution-inside-the-deletion shape, which the reported `cd $(…)` fix would
have left open.

## Deletion: skip the content legs, keep the phase gates

Three legs are content-dependent — their predicate is a diff of the subject
commit — and all three are skipped when every push is a deletion:

| Leg | Predicate | Why it must not run |
|---|---|---|
| routing-governance (deny) | `diff_touches_routing` | The named false block: denies a deletion for routing files it cannot ship. |
| verify-hardening (deny) | `verdict_sha_is_head` + `verdict_has_test_failure` | A failure is authoritative for the commit it was measured at — a commit the deletion does not send. |
| evaluator-surface (advisory) | `diff_touches_evaluator` | Would name evaluator files no deletion can ship. |

Three things deliberately keep firing:

- **the composition-chain REVIEW/VERIFY gates**, and
- **the global fail-closed gate**, because they gate the *phase*, not the
  shipped commit. Deleting a remote ref is still an outbound action, and
  "narrow the subject" must not quietly become "a deletion is ungated". A
  regression cell pins this: with the REVIEW/VERIFY milestones incomplete, a
  pure deletion still denies.
## The IMPLEMENT leg: skipped too, and why the cost had to be measured first

The IMPLEMENT-evidence leg is a fourth content-dependent check — its
`material_source` comes from `_diff_touches_material_source` on the subject —
and its premise ("this push edits source") is equally false for a deletion. But
it is not free to change: when it fires it appends to
`~/.claude/.push-implement-shadow.jsonl`, a **pre-registered corpus** gating a
future deny-flip at n=29 independent episodes, and CLAUDE.md's rule is that a
change to the firing predicate MUST bump `predicate_version`, after which older
records cannot be pooled.

The first draft of this design therefore left the leg alone, reasoning that
discarding the corpus was too expensive for an advisory-only leg. **That
reasoning was based on a stale number and was wrong.** Measuring the live corpus
before acting:

- `IMPLEMENT_SHADOW_PREDICATE_VERSION` was already **3**, bumped days earlier by
  #219/#227 for the same wrong-subject class;
- the corpus held **51 records, all at v2, and zero at v3**.

So the v3 population that a bump would discard was empty, and the bump costs
nothing. The leg is skipped for deletion-only pushes and
`IMPLEMENT_SHADOW_PREDICATE_VERSION` becomes **4**.

Keeping it would not have been merely noisy. A deletion-only would-block record
is adjudicable **only** as a `false_block`, so it moves the pre-registered rate
in the direction of *not* clearing the deny-flip for a reason that has nothing to
do with the predicate under test — it corrupts the measurement rather than
biasing it safely, and it spends a scarce human adjudication on a non-event.

The generalisable point, and the reason this is written down: **measure the
corpus before deciding a bump is unaffordable.** The "too expensive" instinct
came from CLAUDE.md's #199 note about the corpus being behind schedule, which was
true of v2 and irrelevant to v3. The reader (`scripts/shadow-adjudicate.sh`)
derives its required version from the producer lib, so the bump propagates
without the silent-blackout failure #219 hit.

## Multi-ref: an explicit decision, not an omission

`--all`, `--mirror`, `--tags` and 2+ refspecs keep measuring HEAD. The
alternative — resolving and measuring every named ref, denying if any fails —
was considered and rejected for now:

- it is a materially larger change with its own false-block surface;
- `--all`/`--mirror` cannot be enumerated from the command at all, so it would
  fix only the 2+-refspec case and still fall back for the rest;
- the under-measure direction requires someone to push with `--all`/`--mirror`,
  which is not a shape this repo's workflows produce.

What changes is honesty: the message no longer conflates the two shapes. A
deletion now says it ships no content and that the content checks were skipped;
a multi-ref push says HEAD is at best one of the refs being pushed and the
checks may **under-measure**. A regression cell asserts that `--all` does *not*
claim the deletion skip, so the two cannot silently re-merge.

## One parser, and what consolidating it exposed

`_gc_push_seg_shape` is now the single place `git push` arguments are parsed for
shape. `command_push_subject_is_partial` and both new predicates are expressed on
it; `command_push_ref` keeps its own scan because it needs the refspec's *value*
rather than a count, and is the one remaining copy of the preamble.

The consolidation was checked by differential testing rather than by reading:
the pre-change function was extracted from `HEAD` and both versions run over a
48-command corpus. **45 answers identical, 3 deliberately different**, and each
of the three is now a pinned cell:

1. `git push origin +:x` — the old private loop matched `:*` *literally*, which
   `+:x` does not start with, so a force-marked deletion was **never announced**
   and the gate measured HEAD in silence. Now recognised.
2. and 3. `( git push origin main )` / `{ git push origin main }` — the
   bare-closer fix below.

A **fourth** difference showed up on the first attempt and was a regression, not
an improvement: `git push origin :` stopped being announced as partial. That is
why the shape carries a fifth field, `odd`. A bare `:` is empty on both halves,
so the two callers must disagree about it — `command_push_is_all_deletions` must
refuse it (a security predicate guesses toward "keep measuring"), while
`command_push_subject_is_partial` should still announce it, which costs nothing.
Collapsing `odd` into either `refs` or `empty` silently changes one of those two
answers. Without the differential probe this would have shipped as an invisible
loss of an advisory.

## The bare-closer defect, found while extending the parsers

`_gc_split_segments` does not split `( git push origin main )` — spaces, no
trailing `;` — so the trailing `)` arrives as its own **word**, and all three
push parsers counted it as a positional argument. Measured against the parser
before the fix: `command_push_ref '( git push origin main )'` returned **empty**
(so the gate fell back to the checkout's HEAD) and
`command_push_subject_is_partial` reported that single-ref push as carrying more
than one ref.

Both symptoms are in the safe direction, which is why it survived. It is fixed
in all three parsers with one `case` per positional branch (fork-free, Bash 3.2
safe) and pinned by unit cells asserting the resolved ref for the parenthesised,
braced and plain forms.

## Failure direction

Every predicate here fails toward **saying nothing**, which leaves today's HEAD
measurement in place — i.e. toward denying, never toward skipping a gate:

- no push segment found, or an unparseable segment ⇒ `command_push_is_all_deletions`
  returns 1;
- a segment carrying `--all`/`--mirror`/`--tags` ⇒ returns 1 regardless of its
  refspecs (those flags push refs no refspec names — mutation-tested, see below);
- a bare `:` (empty on both halves) ⇒ not counted as a deletion; guessing there
  would guess in the unsafe direction;
- the lib failing to load ⇒ the `command -v` guard leaves `_SUBJ_DELETION_ONLY`
  false and the gate behaves exactly as before.

That direction is **structural**, which is what makes it trustworthy against
model-authored text. There are exactly two routes to "deletion": an explicit
`--delete`/`-d`, or every refspec literally beginning with `:` — which by
construction has no source half. Word-splitting and quoting differences between
what the scanner sees and what bash would execute can only **add** positionals,
and an added positional that is not `:`-prefixed moves the answer toward
not-a-deletion. Measured, not assumed: `$(echo main)`, `"$BRANCH"`, `"$SPEC"`,
`\:a`, `":a main"`, `--` in three positions, and every value-taking option form
(`--repo`, `-o`, `--push-option`, `--receive-pack`, `--exec`, plus their `=`
forms) all classify correctly or conservatively, including the case where an
option's value is itself ref-shaped (`--receive-pack main origin :a`).

**One documented ceiling**, asserted as a cell so it is a known state rather
than a surprise: `--delete` supplied as the value of an option the parser does
not model would be read as the deletion flag. Every value-taking `git push`
option that exists today is modelled, so reaching it requires a git option that
does not exist — the same class as the `bash -c` indirection ceiling the guard
already documents. If git gains a value-taking push option, it must be added to
the skip list in **both** `_gc_push_seg_shape` and `command_push_ref`.

## Verification

Seven mutations, each reverting one piece of the change, each producing its named
failing cell:

| # | Mutation | Cell that fails |
|---|---|---|
| M1 | routing-governance skip removed | `deletion-only push => routing governance does not fire` |
| M2 | verify-hardening skip removed | `failing verdict at HEAD does not deny a deletion` |
| M3 | deletion announcement removed | `deletion-only push says it ships no content` |
| M4 | ALL-form weakened to ANY-form | `deletion then real push` (unit), `deletion followed by a real push => still deny` (e2e) |
| M5 | bare-closer fix reverted | `grouped push resolves its ref` |
| M6 | all-refspecs weakened to any-refspec | `deletion mixed with a refspec` |
| M7 | broad-flag disqualifier removed | `--tags with a deletion refspec`, `--all combined with --delete`, `--mirror combined with --delete` |
| M8 | IMPLEMENT-leg deletion skip removed | `deletion-only push appends no shadow record` |
| M9 | deletion skip widened to the chain REVIEW gate | `...and it is the REVIEW gate that denies` |
| M10 | segment whitelist removed | `alias-hidden push in the same command` (unit), `alias-hidden push in a deletion command => still deny` (e2e) |
| M11 | whitelist weakened to a git-subcommand check | `script segment alongside a deletion`, `bash -c segment alongside a deletion` |
| M12 | whole-command substitution guard removed | `substitution inside a cd argument`, `substitution inside the deletion itself`, +3 |
| M13 | substitution guard narrowed to the `cd` entry | `substitution inside the deletion itself`, `process substitution`, +2 |
| M14 | balanced-parse gate removed | `escaped quote hides a trailing push` (unit), `unbalanced parse in a deletion command => still deny` (e2e) |

M9 is worth recording alongside M7. The boundary cell originally asserted only
that a deletion still denies when the phase milestones are missing — and it
**passed** with the skip wrongly widened to the REVIEW gate, because VERIFY then
denied instead and `"deny"` could not tell the two apart. The cell now asserts
*which* gate denied. An assertion loose enough to be satisfied by the fallback
path pins nothing.

M7 is worth recording: on the first run it applied cleanly and produced **no**
fault, because the three `--all`/`--mirror`/`--tags` cells that existed all pass
on the refspec count alone (`git push --all origin` names no refspec, so it is
already not-all-deletions). The disqualifier was load-bearing but untested — a
mutation that applies is not a fault that reproduces. The three cells in the M7
row were added to close that.
