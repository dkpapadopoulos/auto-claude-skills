# Design: separate gate SELECTION from gate MEASUREMENT

## Architecture

`verify-and-record.sh` conflated two jobs and refused them together. It now
refuses only the first:

| Job | Owner | Needs judgment? |
|---|---|---|
| Which commands constitute the gate | caller (discovery ladder, possibly the user) | sometimes |
| Run them, record measured exit codes | this script | never |

`.verify.yml` remains the preferred path and is unchanged. Explicit mode
supplies `PAIRS` from arguments instead of from the YAML parser; everything
downstream — execution loop, token resolution, pre-gate sha, straddle
detection, gaming check, serialization — is the same code.

## Trade-offs

**Manifest auto-detection was cut, and that was the main design decision.**
It is the obvious next rung and it is a trap: *a declared tool is not a declared
gate*. `package.json` declares an executable script, a `Makefile` target is not
necessarily an aggregate acceptance gate, and a tool dependency declares tool
use rather than the correct invocation or scope. Two opposed failures follow —
under-verification (`"test": "echo ok"` wins while the real gate lives
elsewhere) and over-verification (optional, environment-dependent checks become
mandatory, and their failures become push denials). Multi-manifest precedence is
unspecified: first wins, merge, or prefer an aggregate? Nothing says.

Critically, auto-detection would **create verdicts where none was intended**,
which changes gate outcomes even with every predicate untouched. Explicit mode
does not: the model was already about to hand-author a verdict at that point, so
the population is the same and only its provenance improves. That asymmetry is
the whole reason one shipped and the other did not.

**The completeness obligation is a caller contract, not an enforced property.**
The artifact is replaced wholesale, so re-running one check after a failing run
would certify that check as if it were the entire gate. Nothing in the record
carries gate identity or completeness, so the script cannot detect it. Two
mitigations, both partial and both stated rather than implied: the SKILL.md text
makes the obligation explicit, and explicit mode is refused outright when
`.verify.yml` exists, which is where a declared complete gate is knowable.
Enforcing completeness would need a gate-identity field the schema does not have
— out of scope, and it would be a schema change with its own consumers.

**Refusing beats transforming.** The pair transport is `\x1f`-delimited and read
line-wise (`while IFS=$'\x1f' read -r name run`), and names are comma-split at
serialization (`csv($s): split(",")`). A multiline command or a comma in a name
would therefore corrupt the record into a shape no reader can detect. Both are
rejected. This follows the file's existing posture: a declared check whose `run:`
is missing is recorded in `could_not_verify[]` rather than dropped, because a
declared-but-never-run check silently vanishing under-gates toward a false clean.

**`--run` executes a caller-supplied string, and that adds no capability.** The
model can already run anything through Bash; what changes is that the exit code
is recorded by something other than the model. `command` is inert metadata for
every consumer — not replayed, not authorization. Worth stating because the flag
*looks* like an execution-privilege change and is not.

## Dissenting views

**Adversarial review (Codex) called the original design a ship blocker on two
counts, and both were adopted.**

First, that "an unchanged predicate means unchanged decisions" is false — with a
table of four newly reachable outcomes, including one the author had missed
entirely: `verify-hardening` can newly *deny*, and a later run can replace a
clean verdict with a failure. The effect is bidirectional. Recorded in
`proposal.md` under a heading that says so rather than buried.

Second, that manifest auto-detection should be cut. The author had reached the
same conclusion from under-verification alone; the review added over-verification
and unspecified multi-manifest precedence, which are the stronger arguments.

It also raised a hazard not previously considered: explicit mode could turn a
partial rerun into whole-gate certification. That produced the `.verify.yml`
precedence refusal and the completeness obligation above.

One recommendation was **not** adopted as stated: that the caller be allowed to
pass its discovery rung. That is an impersonation surface — explicit mode could
then claim `verify-yml` and imply a declaration that does not exist — so the
script owns `discovery_source` and there is no flag for it. The review's own
"script owns the provenance classification" point is what settled it.

## Decisions

1. Explicit mode ships; manifest auto-detection does not.
2. `.verify.yml`, when present, is authoritative — explicit args are refused.
3. `discovery_source` is script-owned; no caller flag.
4. Malformed input is refused, never transformed.
5. Completeness is a documented caller obligation, not an enforced property, and
   is labelled as such.
