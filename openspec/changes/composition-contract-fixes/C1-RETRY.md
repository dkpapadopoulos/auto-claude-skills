# C1 retry: what the first attempt got wrong

> **STATUS: APPLIED.** The retry landed. Every counterexample below is now a line in
> `tests/fixtures/routing/second-opinion.txt`, `panel.txt` or `design-debate.txt`, and
> the dispatch controls are asserted by `tests/test-second-opinion-content.sh` —
> stripping them alone fails 10 cells. This file is kept as the record of WHY the
> shape is what it is, and the rule at the top generalises past this change.

C1 was implemented, reviewed, and **reverted**. Nothing of it is on the branch. This
file exists so the retry starts from the measured failures rather than rediscovering
them — every prompt below was measured against the real hook, and every one of them
passed the full suite, 299 regex fixtures, both new-skill done-gates, and a 22-cell
content test.

## Why it was reverted — the finding no gate caught

The first attempt moved panel's `(^|[^a-z])(ask|consult) codex` trigger clause to a new
`second-opinion` skill. That clause is an **outbound dispatch to another vendor**, and
`skills/panel/SKILL.md` is where the controls for that live:

- a disclosure preview naming the destination provider and showing the exact payload,
- a gitleaks secret scan over that payload, with an announcement when unavailable,
- availability probing with consent-gated degradation,
- an explicit **read-only** request in the forwarded task, which exists because the
  dispatch mechanism defaults to a **write-capable** run,
- `mktemp -d` / `chmod 0700` scratch handling.

The new skill had no dispatch section at all. Measured: `consult codex about the schema
change` went from `panel=46 <- slot 1/2` to `second-opinion=47 <- slot 1/2` with panel
no-match. So a "second opinion" would have shipped repository content to another vendor
with the secret scan and the read-only constraint removed — private data plus outbound
action, mitigations gone.

**The transferable rule: a new skill inherits an INTENT, not the controls attached to
wherever that intent previously lived.** No gate in this repo checks for that, and the
suite was green over it. Before moving any trigger clause between skills, diff what the
losing skill's SKILL.md *does* with that intent, not just what it matches.

## Rework list

1. **Carry the dispatch protocol** into any skill that can reach another vendor, or
   leave the dispatching intent with `panel`. Do not split an intent from its controls.
2. **Narrow panel's SKILL.md frontmatter `description:`**, not only its registry entry.
   The roster the model chooses from is built from frontmatter; the registry description
   feeds the hook's routing context. The audit's failure was the model picking panel
   *without being routed there*, so the registry copy is the surface that was never the
   problem. A test asserting the narrowing against the registry JSON reports the
   requirement as covered while checking the wrong surface.
3. **Require a participant term in every trigger clause.** The critique clause had none.
4. **Restore the `(^|[^a-z])` boundary guard** that panel's clause carried.
5. **Give panel back reach for explicit multi-model asks** before removing any of its
   clauses; it was left able to match only the literal `panel of models` / `model panel`
   / `cross-model <noun>`.
6. **`weigh` has no fixture coverage in either direction** in `design-debate.txt`. Any
   change to that clause is currently unmeasurable by the suite.
7. **Priority cannot express precedence here.** `trigger_score` accrues 30 per matching
   regex, so a 1-point priority gap (18/17/16) is dominated by match count and by the
   +100 full-name boost. The intended winner must be produced by match quality, not by
   adjacent priorities.

## Measured counterexamples — encode these as fixtures before retrying

Each was produced by the real hook. They are development data (they come from review,
not from a held-out set), so using them to design triggers is legitimate.

### Must NOT reach a single-model consultation skill

| Prompt | Why |
|---|---|
| `ask codex, gemini and gpt-5 each for their take on this design` | three models named; belongs to panel |
| `i want a cross-model review of the caching tradeoff, ask codex and gemini` | panel matched but was evicted by the 2-domain cap |
| `please critique my approach to caching` | asks *Claude*; no model word anywhere |
| `sanity check the deployment plan` | ditto; outranked verification-before-completion |
| `poke holes in my plan for the migration` | ditto |
| `tear apart the design doc i wrote` | ditto |
| `grade my answer to the interview question` | ditto |
| `red team the rollout plan with the infra team` | "team" is human |
| `let's use a different model for the pricing table` | ordinary engineering sense of "model" |
| `we should train another model on the new dataset` | ditto |
| `there is no other model of concurrency that fits` | ditto |
| `swap in an independent model for the risk score` | ditto |
| `get a second opinion on our threat model` | human second opinion; "model" is the noun |
| `add a task codex entry to the backlog` | `ask codex` inside "t**ask codex**" |
| `we need to get codex installed on this machine` | not a consultation |

### Must reach it, and did not

| Prompt | Why it missed |
|---|---|
| `here is my answer - have codex critique it` | **a frozen `answer_critique` acceptance case**; `have` absent from the verb list |
| `what does codex think of the proposed fix` | cited in `skill-activation-hook.sh` as a genuine consultation |
| `run this by codex` | verb list |
| `i'd like a second set of eyes from codex on the retry backoff fix` | a `consult_pure` case in `cases-round2.json` |
| `send this to gemini for a second look` | verb list |
| `double-check my conclusion with a second model` | `second` missing from the determiner list |

### Deliberation that must keep reaching design-debate

The `weigh` narrowing over-shot: an intervening word killed the clause.

`weigh these two options and tell me which is better` (routed **nowhere** after the
change), `help me weigh the two approaches for the cache layer`, `weigh our design
options`, `help me weigh up the different approaches`, `weigh both approaches carefully`,
`weigh a few options`.

## Validation constraint — read before claiming the retry works

**There is no uncontaminated held-out data left.**

- `cases.json` (round 1) became development data: the predicate's cue window was widened
  after inspecting which of its prompts failed.
- `cases-round2.json` has been spent on one acceptance measurement of the shipped
  consultation predicate.

The deterministic instruments — `tests/test-regex-fixtures.sh` and the frozen
`tests/test-routing-probe-regression.sh` baseline — remain valid and free, and the
counterexamples above make them sharp enough to catch every routing error listed here.
They cannot support an *acceptance* claim about paraphrases nobody has seen.

So: a retry can be validated deterministically against the fixtures, and MUST NOT be
reported as accepted against held-out paraphrases without a round-3 set authored by
someone who has not seen the predicate.

### Round 3 is BLOCKED, not skipped

Attempted 2026-09-16 and not obtained: the subagent pool hit an account session limit
(resets 04:10 Europe/Zurich). Codex cannot substitute as the author — it has now been
shown the full trigger text across four review rounds, so anything it writes is fitted to
the patterns by construction, which is exactly the contamination the authoring rule
exists to prevent.

To unblock: dispatch a fresh agent given ONLY the six contract descriptions, explicitly
barred from reading `config/`, `hooks/`, and both existing prompt sets, and verify it
recorded **zero tool uses** before trusting the result. Then freeze it in a commit before
measuring, spend it once, and report the number whatever it says.

Until that exists, the honest claim for this work is "validated deterministically against
fixtures and the frozen baseline" — NOT "accepted".
