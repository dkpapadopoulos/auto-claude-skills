# Design: IMPLEMENT-leg shadow event (Stage C1)

## Architecture

### Where the record is written

A **dedicated append-only JSONL** at `~/.claude/.push-implement-shadow.jsonl`,
emitted from the existing Check-0 warn branch in `hooks/openspec-guard.sh`.

Three homes were considered; two are wrong:

- **`.phase-gate-events.log` (existing).** `phase_gate_log`
  (`hooks/lib/phase-evidence.sh`) writes a fixed five-field human-readable line
  and is shared with the attest and skill-seq gates. Changing its signature
  would break those callers; adding a parallel rich format to the same file
  would force every reader to handle two shapes.
- **`.push-gate-invocation-log` (capture).** That log records the *final push
  decision*. The IMPLEMENT leg never reaches a `_DECISION`, so its events would
  be indistinguishable from allows. It also rotates 1000→500, which would orphan
  adjudications of older records.
- **A dedicated file.** Chosen. Independent schema, independent lifecycle, and
  no rotation (below).

`phase_gate_log` continues to fire unchanged — the shadow record is additive.

### Record schema

```json
{
  "schema_version": 1,
  "record_id": "<content hash>",
  "ts": "2026-07-27T18:00:00Z",
  "predicate_version": 1,
  "gate": "push-implement",
  "would_block": true,
  "action": "push" | "gh-merge",
  "repo": "<repo path>",
  "branch": "<branch>",
  "head_sha": "<sha>",
  "impl_in_chain": true,
  "material_source": true,
  "impl_evidence_kind": "none",
  "session_token": "<token>",
  "transcript_path": "<path>"
}
```

**Schema 3 adds** (corpus-validity audit, 2026-08-06):

```json
  "impl_evidence_detail": {
    "ledger":      "present | missing | cannot_check",
    "invocation":  "...",
    "bridge":      "...",
    "attestation": "..."
  }
```

`not_evaluated` is reserved but has **no producer**: both record sites fire only
after every leg has been consulted for every slot, so no leg is ever skipped in
a written record. It is named so a future short-circuiting caller has an honest
value available, but a `not_evaluated` filter over this corpus returns empty
because nothing emits it — not because every leg ran.

The distinction it carries is the one the pre-registered `false_block`
definition turns on. Each of the four predicates returns 1 for BOTH "checked,
no evidence" and "could not check" — `_bridge_has` alone collapses three
causes (branch-ledger lib unsourceable, `branch_ledger_bridge_has` undefined,
genuinely no record). Only the last means "no implementation work"; the other
two are infrastructure failures where the constant advisory names the **wrong
remedy**, which is a `false_block` by the definition below.

This could not be deferred to adjudication time. `hooks/session-start-hook.sh`
GCs `.skill-composition-state-*`, `.skill-invocation-evidence-*` (the glob also
matches the `-sha-` sidecar) and `.skill-phase-attest-*` at **7 days**, and
`branch_ledger_record` overwrites in place — so every input needed to re-derive
the per-leg outcome is gone long before the corpus reaches n=29. Measured
2026-08-06: 2 episodes over 9 days = 0.22/day against the pre-registered
0.697/day, putting n=29 nearer 2026-12 than the 2026-09-08 horizon, i.e. the
adjudication inputs for the earliest records expire roughly four months before
the rate is computable.

`null` is a meaningful value here: an omitted or malformed detail records null,
never a fabricated all-missing object, because "not recorded" and "checked and
absent" are different states.

`guard_cksum` and `plugin_version` were considered for the schema but are
**deferred, not emitted by v1** — `hooks/lib/implement-shadow.sh`'s
`implement_shadow_record` does not construct or write either field today.
Add them in a follow-up if drift-across-guard-versions turns out to matter
for adjudication.

- **`record_id`** is a content hash over `ts + pid + session_token +
  command_sha + action + nonce`. A first draft used only `ts + pid +
  command_sha`; review flagged that as too weak — `command_sha` repeats and
  `pid` recycles.
- **`predicate_version`** is the load-bearing field. When the IMPLEMENT
  predicate changes, this increments, and records from an older predicate MUST
  NOT be pooled with newer ones. Without it a future refactor silently mixes
  populations.
- **`impl_evidence_kind`** is intended to record which evidence checks were
  tried and missed (ledger / invocation / bridge / attestation), so an
  adjudicator can see *why* the leg fired without re-deriving it. **As built,
  the Check-0 call site hardcodes the literal `"none"`** — by construction
  that is the only value v1 can ever produce, not a summary of which checks
  ran. Deriving the real per-check outcome is future work.
  **RESOLVED in schema 3** (corpus-validity audit, 2026-08-06): the per-leg
  outcome now lands in a NEW field, `impl_evidence_detail`, rather than by
  widening `impl_evidence_kind` — that field's `"none"`/`"attested"` literals
  are asserted in `tests/test-push-gate-implement-leg.sh` and
  `tests/test-shadow-adjudicate.sh` and pinned in three specs under
  `openspec/changes/`, so it is format-frozen. `predicate_version` stays **2**:
  this changes what a record DESCRIBES, not when the leg fires, so the corpus
  stays poolable and the horizon does not restart.
- **`transcript_path`** is the adjudication pointer. Raw command text stays
  unlogged — the existing secret-safety posture is unchanged, and the transcript
  carries richer context than a command line anyway.

### No rotation in v1

The capture log rotates at 1000→500 records. Applying that here would silently
drop unadjudicated events. At ~0.4 events/day, 500 records is years away, so v1
is append-only with no rotation, documented explicitly rather than left implicit.
If the rate rises, rotation MUST exclude unadjudicated records or snapshot their
facts before dropping them.

### Population fix

Check 0 currently requires `_gc_is_push = true`. The spec requires the leg on a
push **or merge**. Extend the condition to accept `_gc_is_ghmerge`. The leg stays
advisory, so this widens an advisory, never a deny. Widening the leg only makes
the record get *written*; it does not make the advisory text reach the user on
a merge outside SHIP phase — `_flush_push_advisories` is still push-gated, so
that half of the population fix is issue #161, tracked and deliberately
deferred, not shipped here.

**Diff-base caveat.** `_diff_touches_material_source` resolves `material_source`
via `_branch_diff_names` — the same branch-local `merge-base(mainline,HEAD)..HEAD`
delta that routing-governance, `_flush_push_advisories`, and the evaluator
surface all use, each with an explicit comment that this delta is unrelated to
the PR actually being merged for `gh pr merge <other-branch>`. A merge record's
`material_source`, `branch`, and `head_sha` therefore describe the invoking
session's *local* branch state, not the merged PR's diff — the two can name
different content entirely (merging someone else's PR from a session sitting on
an unrelated branch). Merge records must be segmented at adjudication time on
this basis; a `diff_base` field that names what was actually diffed shipped
later in PR #168, which measures a merge's `material_source` against the merged
PR's file list and bumped `predicate_version` to 2 — so v1 merge records are
unpoolable with v2 (CLAUDE.md), and the v1 log is dead weight for this rate.

### Failure posture

Every write is best-effort and fails open: an unwritable path, a missing `jq`, or
any error in record construction MUST leave the gate decision byte-identical.
The shadow log is diagnostic and is deliberately NOT added to
`_GATE_ENFORCE_LIBS` — same posture as `push-gate-capture.sh`.

## Pre-registration (committed before any data is collected)

> **`false_block`** — the human could not proceed, OR the gate's message named
> the wrong remedy.
> **`true_catch`** — includes a deny resolved by a single truthful
> `phase_attest`. That is forced explicit intent, not harm.
> **`unknown`** — terminal for the record, but counted against the stage (below).
>
> **Decision rule:** a **one-sided** 95% upper bound below 10%. One-sided is
> correct because the threshold is directional — we care only whether the rate
> is below 10%, not about a symmetric interval.
> **Unadjudicated records are excluded from the rate and reported alongside it.**
>
> **All three bands read off the same interval.** `phase-gate-backtest.sh:7`
> pre-registers three bands (`<10%` deny / `10-20%` narrowed / `>20%` advisory);
> applying an interval to only the first would leave a rigorous test for DENY and
> point estimates for the other two. Instead:
> - **DENY** — one-sided 95% **upper** bound < 10%.
> - **NARROWED** — upper ≥ 10% AND lower < 20%. The honest inconclusive zone:
>   cannot rule out <10%, cannot rule out ≥20%.
> - **ADVISORY-ONLY** — one-sided 95% **lower** bound ≥ 20%. Note this requires
>   *positive* evidence the rate is bad, not merely failure to prove it good; at
>   n=23 that needs **9** false blocks (39.1%), where the point estimate alone
>   would have called it at 5 (21.7%). The gap between those two numbers is the
>   whole reason the bands are expressed as bounds.
>
> Both bounds are **exact Clopper–Pearson**, matching the floor above. Stated as
> a direct comparison so no interval inversion is needed:
> DENY ⟺ `P(X ≤ k | n, 0.10) < 0.05`; ADVISORY-ONLY ⟺ `P(X ≥ k | n, 0.20) ≤ 0.05`.
> Do not substitute Wilson here — it is anti-conservative in the tail and would
> call ADVISORY-ONLY at 8/23 where the exact rule says 9.
>
> **Denominator = independent episodes, not records.** Collapse records sharing
> `(repo, branch, session_token)` within a 30-minute window into ONE episode
> before counting. Measured basis: the entire v1 log is 11 records from a single
> repo+branch inside one 9-minute window (6 `gh-merge` + 5 `push`, interleaved) —
> one episode retried eleven times, not eleven trials. Across 33 days of local
> transcripts the same clustering holds at ~4.4 events per repo+branch, so a
> record-level denominator overstates n by roughly 4x.
>
> **Sample-size floor.** Arithmetic implied by the decision rule above, not a new
> bar. With zero adjudicated false blocks the rule requires **n = 29 independent
> episodes** (one-sided Clopper–Pearson exact; Wilson at z=1.645 gives 25 — exact
> is the conservative choice for a warn→deny flip and costs four episodes).
> 1 false block ⇒ 46; 2 ⇒ 61; 3 ⇒ 76. A point estimate never clears this gate:
> "0/3 = 0%" is not below 10%, it is unmeasured.
>
> **Diversity requirement.** The floor additionally requires episodes from
> **≥2 distinct repos**. Raw count is not enough: n=29 accumulated entirely
> inside one repo's sprint reproduces the single-branch correlation this
> denominator exists to prevent, just at a larger number.
>
> **Dated horizon (pre-registered 2026-07-28, before the data exists).** At the
> measured 0.697 independent-units/day, n=29 lands ≈ **2026-09-08**. That rate is
> the *transcript-proxy* rate for any candidate push/merge; the v2 log records
> only events where the leg actually fires, a strict subset — so treat the date
> as an optimistic lower bound, not a due date. Recording it now is what makes
> "wait for the forward corpus" falsifiable rather than open-ended: if
> 2026-09-08 passes with n well short, the accumulation assumption was wrong and
> the leg's population is rarer than the predicate's design assumed — itself a
> finding, and grounds to revisit whether `<10%` is the right threshold at all
> (the Dissenting-views item below).
>
> **Unknowns also get a worst-case bound** — the rate recomputed counting every
> `unknown` as a `false_block`, reported next to the headline rate. Excluding
> them from the numerator alone lets the gate clear 10% by leaving hard cases
> unlabeled.

Recording this now is the point: defining the bar after seeing the data is the
post-hoc fitting this repo's discipline warns against.

**Amendment 2026-07-28 (denominator, floor, unknowns).** The three clauses above
were added after C1 shipped. They are not fitted to data, on three checks a
reviewer can verify: (1) the v2 corpus governed by this rule is **empty** —
recording began 2026-07-28T08:31Z with PR #168, and the 11 pre-existing records
are `predicate_version:1`, which CLAUDE.md forbids pooling with v2; (2) the floor
is derived from the already-committed one-sided-95%-below-10% rule by arithmetic,
so it changes no bar; (3) all three clauses move the bar **stricter** — a ~4x
smaller denominator, an explicit floor, and a worst-case unknowns rate — and none
loosens it. Direction-of-change is the auditable guard here: post-hoc fitting is
what makes a gate easier to clear after seeing the data.

**Denominator filter (amended #169).** The shadow log now also carries
`would_block: false` records, for episodes the IMPLEMENT leg resolved via
attestation alone. Any false-block rate computed over the log MUST first filter
`select(.would_block == true)`. Schema-1 records are uniformly `would_block:
true`, so the filter is correct across both schema versions. Counting raw lines
would dilute the rate with episodes that were never blocks.

This is strictness-neutral for the pre-registered rule — the would-block
population it measures is unchanged — and additive for interpretation: the
attested records give `attested / (attested + would_block:true)`, i.e. of the
episodes where the leg found no real evidence, how many were attested away
rather than left unresolved. It does NOT give `attested / all-eligible`;
evidence-backed episodes are deliberately still not recorded (see
`attestation-measurement/design.md`, Unit E).

**Predicate v3 (#219, 2026-08-29) — the v2 corpus is closed.** The leg's
`material_source` for a PUSH was measured against whatever the SESSION cwd had
checked out, which is not the tree or the branch the pushed command names
whenever the session sits in a different worktree or the refspec names another
branch. That is the same wrong-subject defect #161 fixed for the merge path, and
it changes **when the leg fires**, so `IMPLEMENT_SHADOW_PREDICATE_VERSION` is now
**3** and v2 records MUST NOT be pooled with v3. Records also now carry the
subject's branch and sha rather than the checkout's, so episode identity
`(repo, branch, session_token)` names the work the record describes.

The v2 corpus that closes here is **2 would-block episodes** (2026-08-02 and
2026-08-03, `27884d11399402ac` and `b9f3ca7066b17c01`, neither adjudicated) plus
21 attestation-resolved ones, over 32 days. That is 0.0625 would-block
episodes/day against the pre-registered 0.697 — the dated horizon's falsification
condition, met with room to spare and now compounded by a restart. The
re-registration that decision demands is issue #199 and is recorded in its own
section below. Note what it does and does not touch: it moves the horizon, which
the Pre-registration already flagged as resting on a provisional rate assumption,
and it leaves the threshold, floor, denominator and diversity requirement exactly
as written. Changing THOSE in the same edit that resets the data would be the
post-hoc fitting that section exists to prevent.

## Re-registration 2026-08-29 (issues #199 + #219)

Two independent things have happened to this measurement, and both are recorded
here. **Nothing in the Pre-registration above is edited.** The threshold, the
floor, the episode denominator and the diversity requirement are unchanged and
explicitly not renegotiated — only the *horizon*, which that section already
flagged as resting on a provisional accumulation-rate assumption, moves.

### 1. The predicate changed, so the corpus resets — independent of any rate

#219 moved the leg's `material_source` onto the subject the pushed command names
(the session cwd's branch was being measured instead, which for a concurrent
session or a worktree is a different branch entirely). That changes **when the
leg fires**, so per the standing pooling rule `IMPLEMENT_SHADOW_PREDICATE_VERSION`
goes 2 → 3 and the v2 corpus — 2 would-block, 21 attested, 0 adjudicated —
becomes permanently unpoolable. **n resets to 0 under v3**, effective at #219's
merge commit.

This ground is worth separating from the one below because it is *independent of
whether the data looked favourable*: the instrument got a correctness fix. A
corpus measured against the wrong subject is not a smaller corpus, it is not
evidence — the same finding #161 recorded when it bumped v1 → v2 for this exact
defect class on the merge path.

### 2. The accumulation-rate assumption is falsified — the tripwire firing as designed

At 2026-08-29, 32 days into v2 recording (`scripts/shadow-adjudicate.sh --status`):

| | |
|---|---|
| episodes (all) | 23 |
| **would-block episodes — the only population the rate is computed over** | **2** |
| attestation-resolved episodes | 21 |
| adjudicated | 0 |
| distinct repos among adjudicated episodes | 0 |

That last row is the diversity counter, which counts repos among **adjudicated**
episodes; nothing has been adjudicated, so it reads 0 for that reason and not
because the episodes lack repos. Measured directly against the log, the two
would-block episodes span **two distinct repos** (`auto-claude-skills` and
`SuperTrain`).

Be precise about what that does and does not say. Both counters are presently
unmet — n is 2 of 29 and adjudicated diversity is 0 of 2, trivially, because
nothing is adjudicated. What the measurement rules out is diversity being a
*structural* obstacle: the population this leg fires on is not confined to one
repo, so reaching the floor is a question of volume and adjudication effort, not
of the corpus being inherently single-repo.

Both would-block episodes are from 2026-08-02 and 2026-08-03; none has occurred
in the 26 days since. That is **0.0625 would-block episodes/day** against a
pre-registered 0.697.

Do not quote that as a clean 11x: 0.697 was a *transcript-proxy* rate for any
candidate push/merge, which the Pre-registration itself flags as an optimistic
bound, while 0.0625 counts only episodes where the leg fired and found no
evidence — a strict subset. The sound statement is the one the horizon clause
asks for: **the proxy badly overpredicted usable corpus accumulation**, by an
order of magnitude rather than a little. (Issue #199's own "~3x", written
2026-08-06, predates the `would_block` population filter and pooled attestation
episodes that cannot contain a false block; it understates the shortfall.)

### The decision

1. **The threshold, floor, denominator and diversity requirement stand,
   reaffirmed and not open under this re-registration.** Those were never flagged
   as provisional. "We did not clear the bar, so we are moving the bar" is the
   post-hoc move this document exists to prevent, and being an order of magnitude
   behind schedule makes it more tempting, not more true.
2. **No new horizon date is committed.** Re-dating off the v2 rate would repeat
   the original mistake with fresher numbers: the predicate itself changed what
   counts as a qualifying push, so the v2 rate does not necessarily carry to v3.
   How much it changes is genuinely unmeasured: the fix alters which pushes
   qualify, in a direction this section has no evidence about, so a projection
   off the v2 number would be a guess wearing a date — and a date is what gets
   quoted later. Horizon is therefore **unknown, pending re-estimate**, and this
   section deliberately makes no claim about how far off 2027-12 was.
3. **Re-estimate after the first 14 days of v3 recording**, then compute a
   horizon by the same arithmetic used on 2026-07-28. That check is a new,
   differently-shaped tripwire and gets its own issue rather than reusing #173.
4. **The leg stays advisory and the log keeps recording.** Nothing becomes deny.

**Falsification condition for this re-registration:** if the 14-day v3
re-estimate is again off by an order of magnitude from what it predicts, that is
a second independent miss, and it is grounds to hold the pre-committed "is <10%
the right threshold at all" question **explicitly and in the open, in its own
dated section** — never to adjust the threshold quietly as a third patch to this
same rule.

### Why this is a re-registration and not post-hoc fitting

The `<10%` threshold and the n=29 floor are the decision rule; the 2026-09-08
date is a **diagnostic tripwire on a separately-flagged assumption**, and the
Pre-registration pre-commits what a missed horizon means — "grounds to revisit
whether `<10%` is the right threshold at all". Note it says *revisit*, not
*lower*. That distinction is the whole basis for touching the date and nothing
else.

**It is NOT the same evidentiary class as the 2026-07-28 floor derivation**, and
claiming so would be the overclaim this section is trying to avoid. That floor
was *arithmetic*: mechanically implied by an already-committed threshold, so it
could not have come out differently. Declining to re-date is an **empirical
governance decision** made after seeing results. It is defensible, but it is
defensible on different grounds, and the grounds are these two — neither of which
is "the data were inconvenient":

1. the rate assumption was explicitly flagged provisional and its own
   pre-committed trigger fired, exactly as designed;
2. the predicate changed for reasons unrelated to the rate, which voids pooling
   under a standing rule regardless of what the data said.

Both leave the threshold, floor, denominator and diversity requirement untouched.

**What was considered and rejected:** withdrawing the flip outright — declaring
the leg permanently advisory and closing the question. It was drafted, and it is
wrong. It buys nothing operationally (the leg is advisory either way and the log
records either way), it forecloses a future decision, and it is a project-level
stop taken immediately after inconvenient data. That is outcome-dependent
stopping: not threshold manipulation, but not categorically immune to
rationalisation either, and it needs a defence that re-dating simply does not.
Also rejected: adopting a bounded-harm kill-switch flip now. Codex proposed
almost exactly that on 2026-07-28 and it was declined; being behind schedule does
not make the argument more true, and under v3 it would have **zero** evidence to
stand on.

### Two corrections to arguments that looked stronger than they are

**The escape hatch does not bound the whole harm model.** It is tempting to argue
that because a deny from this leg is escapable by one truthful `phase_attest`
— already classified a `true_catch` — the `<10%` bar is close to vacuous. That
holds for only ONE of the two `false_block` disjuncts. "The human could not
proceed" is structurally foreclosed by attestation. **"The gate's message named
the wrong remedy" is not**: an agent can attest truthfully and still have been
pointed at the wrong fix, and that is exactly the `cannot_check`-vs-`missing`
distinction `impl_evidence_detail` exists to expose. So the bar is carrying less
weight than n=29 implies, but it is not vacuous, and the component that still
needs measuring is remedy correctness — a smaller and cheaper target than
"false-block rate in general".

**"21 of 23 attested" cannot settle the value question, and there is a cheap
instrument that can.** Those records say the hatch was USED, never whether the
reason was true — so they distinguish neither "the hatch works" from "attestation
is a reflex", and arguing from them about the value of denying the 2 would-block
episodes also mixes populations. The instrument that answers it needs no schema
change and no predicate change: **adjudicate a sample of the attestation-only
episodes for whether the `phase_attest` reason is situation-specific or
boilerplate.** `--next`/`--verdict` already label non-blocking records, and the
rate-gate excludes them, so this costs only human attention and answers a
real-vs-theatre question no value of n can reach.

### Consequences for other work

- **Issue #173** (the dated check against 2026-09-08) should **close citing this
  section**, not fire against a floor already known unreachable — it now has two
  converging reasons, the rate miss and the corpus-invalidating predicate bump.
  The 14-day v3 re-estimate is a differently-shaped check and belongs in a fresh
  issue.
- **The two v2 would-block records** (`27884d11399402ac` in `auto-claude-skills`,
  `b9f3ca7066b17c01` in `SuperTrain`) are orphaned by the v3 bump. Labelling them
  is nearly free and gives an early read on whether the rare population behaves as
  designed, but it feeds no rate and **an agent must not label them** — agent
  claims are excluded until a human re-confirms, which is the rule working, not
  an obstacle to route around.
- **An opt-in deny** — `phase_enforcement.implement: "deny"` for users who want
  the leg to block on their own machines — is a coherent follow-up and is
  deliberately NOT proposed here. It would be a user choice rather than a default,
  so it does not inherit this decision rule; it needs its own issue.

## Trade-offs

- **Deferred payoff.** No usable rate for weeks. Accepted because the
  episode→outcome link provably cannot be reconstructed retroactively — the
  reason this backtest is blocked today.
- **Softer false-block definition is easier to clear.** Mitigated only by
  pre-registration; it is committed before collection, in this file.
- **Human adjudication is socially, not technically, enforced.** There is no
  genuinely human-bound signal available in this harness — TTY, env, and
  parent-process checks are all forgeable by an agent with shell access. C2 will
  therefore record provenance (`$USER`, tty, parent process, script sha, repo
  HEAD, whether agent env vars were present) and label the output
  "human-claimed" rather than "human-verified".

## Dissenting views

- **Codex:** "C2/C3 are not worth building as proposed — they will produce a
  polished rate for the wrong population." Accepted in full; this change is C1
  only, and it retargets the corpus from `deny:*` records to shadow events.
- **Codex:** "The threshold may also be wrong, not just the measurement. A
  first-deny on a legitimate no-implementation push is often forced explicit
  intent, not a hard false block." Accepted — it is the basis for the
  pre-registered `false_block` definition above.
- **Codex (2026-07-28):** the retroactive transcript corpus should be rebuilt as
  a one-directional **kill switch** — too weak a proxy to authorize the flip, but
  good enough to detect a catastrophic false-block rate early (the asymmetric
  stopping-boundary precedent from interim trial monitoring). **Principle
  accepted, build DECLINED**, on three grounds it did not weigh. (1) The leg is
  **warn-only**: a bad false-block rate today blocks nobody, so the kill switch
  guards a harm that cannot yet occur. (2) Under the three-band scheme adopted
  above, the retro corpus returns ADVISORY-ONLY only at **8/23** adjudicated
  false blocks — 23 human counterfactual adjudications for a verdict that needs
  a third of them to come back bad. (3) The forward v2 corpus yields *faithful*
  records rather than a proxy on roughly the same horizon (~2026-09-08). Codex's
  own point (b) compounds this: the proxy miscounts an **errored** Skill
  `tool_use` as evidence and substitutes "edited non-docs source in-session" for
  `_diff_touches_material_source`'s merge-base diff, so its error profile is
  unquantified in both directions. **Revisit if** the dated horizon passes with n
  well short — at that point the forward corpus is not arriving and a coarse
  early signal becomes worth its adjudication cost.
- **Unresolved:** whether `<10%` is the right threshold at all. Not settled
  here; this change only makes it *measurable*. Revisit once ~10 real
  **episodes** (per the denominator above, not 10 raw records) exist.

## Decisions

1. Dedicated JSONL, not the shared events log and not the capture log.
2. Identity now (`record_id`, `ts`, `schema_version`), because it cannot be
   backfilled.
3. `predicate_version` from day one, so a later predicate change invalidates
   rather than silently pools.
4. Merge coverage added, so the sample matches the spec.
5. Adjudication tooling (C2) and the backtest reader (C3) deliberately deferred
   until real events exist.
6. Spec reconciliation (the spec named `scripts/phase-gate-backtest.sh`, which
   measures the skill-sequencing gate, not this leg) was **out of scope here**
   and filed as issue #160 rather than silently corrected. RESOLVED 2026-07-28:
   `implement-evidence-gate`'s spec, proposal, and design now point at this
   file's Pre-registration instead.

## Out-of-Scope

- Any change to a `permissionDecision`, deny path, or the deny-flip itself.
- Adjudication tooling (C2) and the backtest consumer (C3).
- Changing or reconciling the `<10%` threshold or the spec's instrument
  reference.
- Rotation, retention, or pruning policy beyond "none in v1".
- The push-gate capture log's schema.
