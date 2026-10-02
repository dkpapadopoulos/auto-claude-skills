# Design: VERIFY requires a measured verdict

## Architecture

`verdict_is_measured` reads the verdict's existing `discovery_source` field. Nothing in
`hooks/` or `scripts/` reads that field today, so this adds a reader over data already
populated on every artifact — no schema change, no producer change.

Accepted (emitted by `scripts/verify-and-record.sh`, so real exit codes were captured):
`verify-yml` (line 131), `explicit` (line 138).
Rejected (hand-authored by the model on `project-verification`'s lower rungs):
`claude-md-commands`, `contributing-md`, and any absent/unrecognised value.

The leg sits with the existing VERIFY status check, **advisory-only**: it appends to the
advisory text and never sets `permissionDecision`. It cannot bypass a deny below it.

## Trade-offs

Requiring a measured verdict closes the accidental path (invoke, execute nothing) but
does **not** close the class. `verify-and-record.sh --name tests --run true` was measured
2026-09-28 in a scratch repo and produced a fully clean verdict
(`passed:["tests"], failed:[], gate_gaming_status:"clean"`) having executed `true`.

That is accepted, not overlooked. Authoring `--name x --run true` is a **deliberate** act,
which puts it in #295's tier (needs intent), not #301's (needs only distraction). The
achievement is moving the accidental path into the deliberate tier. Claiming closure
would be the over-report this repo has repeatedly settled as worse than silence.

`explicit` is therefore accepted despite being model-chosen: it still captures real exit
codes, and rejecting it would false-block every repo without a `.verify.yml`.

## Dissenting views

**"Reject `explicit` too."** It is model-chosen, so accepting it leaves the `--run true`
hole. Rejected because it false-blocks every repo lacking a declared gate — a far larger
population than the hole, and the hole needs intent.

**"Fix the ladder first, then narrow the gate."** This was the recommendation when the
ladder looked like ~50% of verdicts. Measurement (below) put it at 8.5% and falling, so
the prerequisite is disproportionate to the population it protects.

**"Skip the shadow and flip straight to deny."** Rejected: the leg narrows the gate, so
the risk is a false block, and the affected population is measured on ONE install only.

## Decisions

1. Accept `verify-yml` and `explicit`; reject hand-authored rungs.
2. Advisory-first with a shadow corpus, and **the reader ships in the same change**.
3. Gate the flip on **unexplained** would-blocks, not on the total rate — see below.
4. No change to the artifact schema, the producer, or any existing deny leg.

## Pre-registration (decision rule for the deny-flip)

Registered 2026-09-28. `predicate_version: 1`, `schema_version: 1`.

> **The decision rule in this section is SUPERSEDED** by "Re-registration
> 2026-10-02" at the end of this file. It is kept because the baseline and the
> reasoning are still the record of what was measured and why; the rule itself
> (n >= 5, zero `unexplained`, positive control) no longer decides anything.
> Implementation readings 1 and 2 are superseded with it.

### Measured baseline (state the scope, it is not universal)

47 verdict artifacts spanning 2026-08-02 → 2026-09-28 (57 days) on **one install**:

| `discovery_source` | n | share |
|---|---|---|
| `verify-yml` | 42 | |
| `explicit` | 1 | |
| **measured subtotal** | **43** | **91.5%** |
| `claude-md-commands` | 3 | |
| `contributing-md` | 1 | |
| **hand-authored subtotal** | **4** | **8.5%** |

Newest hand-authored verdict: 2026-09-17. Newest verdict overall: 2026-09-28 — so the
last 11 days produced zero. **Scope caveat, load-bearing:** this measures one machine's
habits. A repo with no `.verify.yml` would produce hand-authored verdicts at ~100%, and
those installs are invisible from here. The 8.5% is an install-scoped figure and must
not be quoted as a population rate.

### Why this is NOT a rate floor, and why copying n=29 would be a mistake

Hand-authored verdicts accrue at **4 / 57 days = 0.070/day**. Reaching the IMPLEMENT
leg's n=29 floor would take **413 days (1.1 years)**. Registering that floor would
repeat #199 and #239 exactly: a pre-registration whose corpus cannot reach its own bar.

More importantly, the false-block **source is already known and enumerable**. A
would-block explained by a hand-authored `discovery_source` is a *predicted cost*, not a
discovery. So the quantity worth measuring is the **unexplained** would-block.

### Classification (every shadow record carries exactly one)

- `explained_ladder` — a clean verdict covers HEAD, `discovery_source` is a hand-authored rung.
- `unexplained` — the leg would block for any other reason.
- `cannot_check` — the verdict exists but does not parse, or omits `discovery_source`.
  Never counted as `unexplained` (that direction biases toward clearing the flip).

### Decision rule

Flip to deny when **all** hold:
1. **n >= 5** shadow episodes recorded (feasible: ~71 days at the measured rate).
2. **Zero `unexplained`** episodes among them.
3. **At least one `explained_ladder`** episode observed — otherwise the instrument has
   not demonstrated it can classify the case it was built for, and a zero count is
   indistinguishable from a leg that never fired.
4. Episodes span **>= 2 distinct repos**, keyed on origin URL (not worktree path — the
   review-shadow instrument was satisfiable by two worktrees of one repo).

Do NOT flip on (1)+(2) alone: zero unexplained with n=5 and no explained case is a
positive control failure, not evidence.

### Episode definition

Collapse `(repo, branch, session_token)` within 30 minutes, **anchored at the episode's
first record** (a rolling gap chains a whole day into one episode).

### Starvation backstop

If **n < 3** by **2026-12-31**, this window closes as a permanent **null result** and the
leg stays advisory by decision, not by inertia. No re-dating off the observed rate — that
is the discretion #239 exists to refuse.

### Adjudicator and cadence — named, because #239 failed here

The corpus is reviewed by the **repo owner** at a **fortnightly** cadence, starting
2026-10-12. `scripts/verify-shadow-adjudicate.sh` **ships in the same change as the
writer** and prints n, the classification split, accrual/day, repo diversity, and which
decision-rule clauses are unmet. #239's REVIEW corpus reached its floor on 2026-09-03
and nobody could see it for three weeks because no reader existed; that is the specific
failure this clause prevents.

### Implementation readings — fixed 2026-10-02, at zero records

Each of these was underdetermined by the text above. They are written down
before the corpus holds a single record, so none was chosen after seeing data.
None changes a registered number.

1. **`n` counts every recorded episode, `cannot_check` included.** Clause 3 is
   only non-redundant under that reading: if `n` counted would-blocks alone,
   `n >= 5` with zero `unexplained` would already imply five `explained_ladder`.
   `cannot_check` still never counts as `unexplained`.
2. **No verdict at all is `unexplained`** (reason `absent`), per "the leg would
   block for any other reason". Consequence, stated rather than hidden: the
   case the leg exists to catch — invoke the skill, execute nothing — is itself
   an `unexplained` episode and holds the flip. The rule as registered therefore
   flips only on a corpus where every would-block was a hand-authored rung. That
   is the registered rule; changing it is the owner's call and needs a
   `predicate_version` bump.
3. **`explained_ladder` rungs** are `claude-md-commands`, `contributing-md` and
   `heuristic:<manifest>` — the third is a rung `discovery-ladder.md` names and
   the baseline table happened not to contain. Any other value the writer does
   not emit is `unexplained` (reason `unrecognised-source`).
4. **Readability is decided before coverage.** An artifact that omits
   `discovery_source` is `cannot_check` whatever its `sha` says.
5. **Population (predicate_version 1):** the composition-chain VERIFY leg only,
   milestone in the chain and already credited, `git push` only (the spec's
   scenarios say push; a merge's subject is the PR, not a branch-local commit),
   content-bearing (a pure ref deletion ships nothing). `material_source` is
   RECORDED on each record and is not a fire condition. The global no-chain
   gate is not instrumented.
6. **An episode's class is worst-wins:** any `unexplained` record, else any
   `explained_ladder`, else `cannot_check`. Arrival order never decides.
7. **The backstop counts episodes whose first record is on or before
   2026-12-31**, so later episodes cannot reopen a closed window.
8. `would_block` is `false` on a `cannot_check` record: the leg is fail-open and
   would not block on a verdict it could not read even after a flip.

9. **A measured verdict under ANY token at the exact commit satisfies the leg.**
   `verdict_resolve_token` returns one artifact and does not rank by
   provenance, so an own hand-authored verdict shadowed a sibling session's
   measurement of the same commit (found in review, reproduced). Exact-commit
   only; ancestor acceptance stays scoped to the own token. **Not when the
   resolved verdict is not-clean:** `verdict_resolve_token` is deny-biased (a
   failure at the commit outranks a clean verdict elsewhere), and reading 10
   follows it rather than letting a sibling's clean run erase a recorded
   failure.
10. **A measured verdict that is not clean is `unexplained`** (reason
    `not-clean`), because the proposal requires a *clean* measured verdict. A
    measured FAILING verdict is also denied by verify-hardening, so "ran the
    gate, it failed, tried to push" is recorded here even though the push never
    proceeded — the leg records at evaluation, before the legs below it decide.
11. **The reader reports NOT MET while any record is uncountable** — an
    unparseable line, a `ts` the shared grouper cannot place (malformed or
    before 1970), a `record_id` that is empty or not a plain token, a
    `predicate_version` that is not a whole number, an unknown classification,
    or a duplicated `record_id`. Any of them may be the `unexplained` event, so "zero
    unexplained" is not a measurement until each is accounted for. A record
    carrying a whole-number other `predicate_version` is a legitimate older
    band and does not block. **Limit, stated:** that band is not inspected, so
    a record relabelled to another version leaves the count. The corpus is an
    agent-writable file and this reader defends against corruption and drift,
    not against a deliberate edit.
12. **`repo_id` is the origin URL normalised to `host/path`** (scheme, userinfo,
    port, query string and fragment removed; scp-style separator converted;
    host lowercased; trailing `.git` and slashes removed), so one repository
    reached through different URL spellings is one repo for clause 4.
    Userinfo is cut through the LAST `@` in the string, so a credential
    containing `@`, `/`, `#` or `?` does not survive. Limits: two clones with
    NO origin are two identities; an IPv6 literal in scp form is not
    normalised; a path containing `@` loses what precedes it (one stable
    identity per repository, never a leak).

### Owner rulings on the two open questions — 2026-10-02

Review raised two questions that change what the rule accepts. The owner
delegated both ("apply best practice") and they are settled in
"Re-registration 2026-10-02" below:

- *The leg's own true catches held the flip.* Settled: a would-block is judged
  by a human as a true catch or a false block; a true catch counts FOR the rule.
- *`cannot_check` counted toward `n` and repo diversity.* Settled: it is
  reported and never counted.

### Prerequisite settled by driving the producer (2026-10-02)

`scripts/verify-and-record.sh` was RUN, not read, in a scratch repo with an
isolated `HOME`:

| Repo state | Arguments | Result |
|---|---|---|
| no `.verify.yml` | `--name tests --run true` | verdict written, `discovery_source: explicit` |
| no `.verify.yml` | none | exit 1, no verdict |
| no `.verify.yml` | `--run false` / missing command | recorded as `failed` / `could_not_verify` |
| `.verify.yml`, `substrate: local` | none | verdict written, `discovery_source: verify-yml` |
| `.verify.yml`, any substrate | `--name/--run` | exit 1, refused (declared gate wins) |
| `.verify.yml`, `substrate: ci` | none | exit 1, unsupported substrate |

So a repo with no declared gate CAN reach a measured verdict, which is what
accepting `explicit` assumed. **One population cannot:** a repo whose
`.verify.yml` declares a non-local substrate is refused on both routes, so its
only verdict is hand-authored and it would be an `explained_ladder` would-block
on every push. No such repo is known on the measured install. Under
predicate_version 1 this was left as a cost to weigh at the flip; the
re-registration below takes that population out of scope instead.

## Re-registration 2026-10-02 (`predicate_version: 2`, `schema_version: 2`)

Registered at **zero records**: version 1 shipped in 3.92.0 hours earlier and
no install had recorded anything. Nothing below was chosen after seeing data.
A record carrying `predicate_version: 1` is a different population and is never
pooled.

### What was wrong with the registered rule

1. **It counted the leg's successes against it.** "Invoked the skill, ran
   nothing" and "ran the gate, it failed, pushed anyway" were `unexplained`, and
   one `unexplained` episode held the flip. The rule could only be met by a
   corpus in which every would-block was a hand-authored verdict: the more the
   leg was needed, the less it could ever be enabled.
2. **It counted "could not look" as evidence.** `cannot_check` episodes counted
   toward `n` and toward repo diversity, so a broken install could supply both.
3. **It treated `explained_ladder` as acceptable by construction.** A
   hand-authored verdict in a repo where the writer refuses to run has no
   reachable remedy. "Predicted and enumerable" describes a cause; it does not
   establish that blocking it is acceptable.

The classification vocabulary is unchanged and still recorded on every event.
What changes is that a classification no longer decides anything by itself.

### The quantity

**False blocks among would-block episodes.** Not false blocks per push, and not
missed catches: neither is measured here. A would-block episode is one holding
at least one `explained_ladder` or `unexplained` record.

Every would-block episode is labelled by a **human**:

- `true_catch` — the remedy the advisory named (re-run the gate through
  `project-verification`, which records measured exit codes) was reachable in
  that repo at that time and was the right thing to ask for. "The gate failed
  and has to be fixed first" is a true catch.
- `false_block` — the agent could not have proceeded by that remedy (the writer
  refuses this repo, or there is no gate to run), or the advisory named the
  wrong remedy. **The existence of the human bypass does not make a block a true
  catch**; that would empty the term.
- `unknown` — it cannot be told from the evidence. The episode stays unresolved.

A label claimed from inside an agent session is ignored. This leg governs agent
pushes, so the subject has a live incentive to grade its own gate.

### Scope (the fire condition; this is the `predicate_version` bump)

Unchanged from reading 5, with one exclusion: **a repo whose `.verify.yml`
declares a non-local substrate is out of scope.** The writer refuses to run
there by any route, so no measured verdict can exist. A check that can only
fire and never be satisfied measures the repo's configuration, not the agent.
The declaration is read from the pushed commit. Any future deny-flip inherits
this scope: it must not deny in a repo the shadow never measured.

A repo declaring nothing stays in scope, because the explicit route is
reachable whenever a gate exists. Whether one existed is what the label
decides, and each record carries `gate_declaration` (`local` | `absent` |
`unknown`) as contemporaneous evidence for that judgement.

### Decision rule

Flip to deny when **all** hold:

1. **n >= 29** would-block episodes.
2. **Zero** false-block episodes, across the whole corpus. One confirmed false
   block means the rule cannot be met under this `predicate_version`: fix the
   leg, bump the version, start again.
3. **Zero** unresolved episodes: every would-block episode carries a human
   `true_catch`. Silence never clears anything.
4. The true catches span **>= 2 distinct repositories**, keyed on the
   normalised origin (reading 12).

And nothing uncountable is present (reading 11, extended to the label sidecar:
a corrupt label line may be hiding a `false_block`).

`cannot_check` episodes are reported and never counted, in `n` or in
diversity. There is no "unhealthy share" threshold: with successes silent, the
share of `cannot_check` among recorded episodes is not a failure rate, and a
threshold nobody can define is not a registered rule. An installation smoke
test of the leg is a precondition of the flip change instead.

The positive-control clause is deleted. Once every counted episode is a
human-confirmed true catch, "at least one true catch" adds nothing.

### Why 29

It is the bar the REVIEW and IMPLEMENT legs use, computed by the same shared
code (`hooks/lib/shadow-corpus.sh::shadow_band`): a one-sided 95%
Clopper-Pearson upper bound below 10%. At zero false blocks that first holds at
n = 29; the upper bound at n = 5 is 45%.

The arguments for keeping five do not survive: inspecting each episode improves
the label, not the sample size; the leg is fail-open only on `cannot_check`,
while the events being studied become hard denies; and a bypass lowers the cost
of a false block, not its incidence.

What the bound is **not**: it is a binomial-model bound, and thirty-minute
separation does not make episodes independent — one configuration repeated can
dominate, and two repositories is minimal diversity. It is the same model-based
statement the sibling legs make, no stronger.

The original objection to a rate floor was that hand-authored verdicts accrue
at 0.07/day. That measured a different population: the would-block population
now includes every push with the milestone credited and no measured verdict,
and its rate is unknown. If it turns out to be too slow, the result is a null
result at the deadline — not a lower bar.

### Episodes

Collapse `(repo, branch, session_token)` within 30 minutes, anchored at the
episode's first record (unchanged). Within an episode, over its would-block
records only:

- any human `false_block` → the episode is a false block;
- otherwise any record without a human `true_catch` → unresolved;
- otherwise → a true catch.

A `cannot_check` record neither qualifies an episode nor clears one. A record
joining an episode after it was labelled is unlabelled, so the episode reads
unresolved again: a label never covers evidence the labeller did not see. The
latest human label per record wins, so a correction supersedes what it corrects.

### Deadlines

- **Starvation:** fewer than **3** would-block episodes by **2026-12-31** closes
  the window as a permanent null result.
- **Final:** a final deadline of **2027-03-31**. Any clause unmet then closes the
  window as a null result, and the leg stays advisory by decision. An episode
  that begins after that date is not counted, and a label made after it is
  ignored. The version-1 rule had no final deadline: three to twenty-eight
  episodes, or unlabelled ones, could leave it open for ever.

No re-dating off the observed rate.

### Adjudicator and cadence

Unchanged: the **repo owner**, **fortnightly** from 2026-10-12.
`scripts/verify-shadow-adjudicate.sh --next` shows the oldest unresolved episode
with its evidence and the definitions above; `--adjudicate <record_id>
--verdict ...` labels it into a sidecar; `--status` reports every clause. The
shadow log is never mutated.

### Sparring record

The first draft of this re-registration was critiqued by a second model
(Codex, read-only, 2026-10-02) before it was written down. Five points changed
the draft: `explained_ladder` is labelled like everything else; the
`cannot_check` share threshold was dropped; 29 replaced 5; the positive control
was deleted; and a final deadline was added. One point was adopted in a
narrower form: non-local substrates are excluded from scope outright, while
"no gate at all" is left to the label, because nothing recorded can establish
it automatically.

### What is NOT open

The definition of a false block, the n >= 29 floor, zero false blocks, zero
unresolved, the 2-repository requirement, the scope, the episode rules and both
deadline dates. A change to the leg's fire condition, or to what a pooled count
or label means, requires a `predicate_version` bump and makes earlier records
unpoolable.

## Superseded: what was not open under predicate_version 1


The classification vocabulary, the `unexplained`-only rule, the n>=5 floor, the
positive-control clause, the 2-repo diversity requirement, and the backstop date. A
change to the leg's fire condition requires a `predicate_version` bump and makes earlier
records unpoolable.
