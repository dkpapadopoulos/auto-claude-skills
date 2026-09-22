# Design: REVIEW verdict artifact

## Architecture

Three layers, mirroring the VERIFY split that already works.

```
  STATUS  (unchanged)   .completed / branch-ledger / invocation / bridge
                        answers "did requesting-code-review run"   -> can DENY

  VERDICT (new)         ~/.claude/.skill-review-verdict-<token>
                        answers "did a review happen, and did it pass"
                        read by hooks/lib/review-verdict.sh          -> WARN ONLY

  CORPUS  (new)         ~/.claude/.push-review-shadow.jsonl
                        one record per would-block, episode-adjudicated
```

### Artifact schema (v1)

```json
{
  "schema_version": 1,
  "provider": "local-agent|human|github-import|agent-team-review",
  "reviewed_base_sha": "<40-hex>",
  "reviewed_head_sha": "<40-hex>",
  "changed_file_digest": "<12-hex of sorted name-only list>",
  "changed_file_count": 7,
  "findings_total": 6,
  "unresolved_blocking": 0,
  "verdict": "clean|findings-open|could-not-review",
  "dispatch_attempted": true,
  "dispatch_succeeded": true,
  "ts": "2026-08-25T09:00:00Z",
  "writer": "record-review-verdict.sh"
}
```

`verdict` is terminal and independent of `unresolved_blocking` being zero — a provider that cannot establish the reviewed subject writes `could-not-review` rather than guessing. Per the issue, `dispatch_*` stay **separate telemetry fields and are never collapsed into one bit**, and never become a deny predicate on their own.

`changed_file_digest` is what makes the artifact about a *diff* rather than a *commit*. Two different branches can share a HEAD sha in a worktree-heavy repo; the digest disambiguates and is cheap (`git diff --name-only base..head | sort | shasum | cut -c1-12`).

### Subject binding

The failure to avoid is documented: naive exact-HEAD staleness measured **56–94% false blocks with zero catches** (`openspec/changes/gate-status/backtest-results.md`). So binding is deliberately permissive and the strictness lives in the corpus, not in a block.

`review_verdict_covers_head` accepts when `reviewed_head_sha` is HEAD **or a branch-local ancestor of HEAD** — the same rule the ledger bridge and the SHA sidecar already share via `branch_ledger_sha_is_branch_local`, reused rather than re-derived. Mainline-reachable and unrelated shas never bind.

**Review-fix commits are deliberately NOT classified.** Detecting "this commit only addresses review findings" is exactly the kind of fitted heuristic the repo's publish-guard design already rejects for proper-noun matching. Instead the delta since the reviewed sha is *recorded* (`delta_files_since_review`) and measured. If the corpus later shows ancestor acceptance is the dominant false-block source, that is evidence to tighten with — guessing now is not.

### Where the leg sits

Alongside Check 1 (chain REVIEW), after it, and structurally identical to the IMPLEMENT warn-first leg: appends to `_STALE_MSG`, sets no `_DECISION`, no `exit`. It therefore cannot bypass any deny below it, and on a healthy run adds nothing to output.

## Trade-offs

**A Skill return still credits STATUS.** This change does not remove that, and could not: removing it without a mature verdict layer would deny every legitimate push from a session whose provider never wrote an artifact. Status stays as-is; the verdict leg reports the gap. The deny-flip is the follow-up the corpus exists to justify.

**The artifact is in-band and forgeable.** A model with filesystem access can write a clean review verdict. This is true of every local store here including the verify verdict, and is why the proposal names GitHub branch protection as the eventual anchor. The artifact's value is that *not writing one* is now visible, which it currently is not.

**`github-import` is the only forgery-resistant provider**, and it needs network and a PR. It is therefore not the default, and its absence must never be treated as evidence of anything.

## Dissenting views

- **"Record whether a Task ran during the skill's span."** Rejected, per the issue: it relocates the same fallacy one level down. A dispatch still counts when the reviewer returns empty, reads the wrong base ref, sees one file of ten, or has its findings discarded. It is also race-prone — the session token is conversation-scoped, not subagent-scoped, and nothing establishes a shared parent/child invocation id. Kept as telemetry (`dispatch_attempted`/`dispatch_succeeded`), never as a predicate.
- **"Just make the Skill return `is_error` on dispatch failure."** Architecturally impossible in this harness: the tool returns the instruction body before any dispatch is attempted.
- **"Concede local REVIEW is unenforceable; move entirely to branch protection."** Correct about the trust boundary, and branch protection should be enabled regardless. Rejected as the *whole* answer because it discards the early-warning and telemetry value on local branches and pre-PR pushes, where most of this repo's work happens.

## Decisions

1. Advisory-first. The leg never denies in this change. Non-negotiable given the 56–94% false-block precedent.
2. Reuse `branch_ledger_sha_is_branch_local` for ancestor acceptance rather than re-deriving it — the #133/#131 lesson about two implementations of one rule drifting.
3. `review-verdict.sh` stays OUT of `_GATE_ENFORCE_LIBS` while advisory; PAIRED note recorded so the deny-flip adds it.
4. `finding_count_estimate` is renamed rather than repaired in place. It measures the skill body; a field whose name implies otherwise is worse than no field. The real count lives in the artifact.
5. No REVIEW attestation, at writer or reader. Double-locked decision, no new evidence to reverse it.

## Pre-registration (decision rule for the deny-flip)

Registered **before** the observation window so the result cannot be reinterpreted afterwards.

- **Population.** Every `git push` or `gh pr merge` where the chain contains `requesting-code-review`, the push touches material source, and STATUS is satisfied. A record is written whenever the verdict leg *would* warn.
- **Excluded: sessions launched with `ACSM_SKIP_PUSH_GATE=1`.** Amended 2026-08-25 in review, while the corpus held **zero** records — stating it up front, because amending a population *after* seeing data is exactly the move this pre-registration exists to prevent. The leg sits inside the guard's `_PUSHGATE_SKIP` block, so a bypassed session emits no advisory and writes no record. Measured, not assumed: under `ACSM_SKIP_PUSH_GATE=1` the IMPLEMENT leg and this one both stay silent while the evaluator-surface advisory still emits. That is the correct alignment — the evaluator-surface advisory needs no composition state and is a different class, whereas the IMPLEMENT warn-first leg is this leg's structural twin and shares its corpus discipline. Making this leg emit under bypass while IMPLEMENT does not would leave the two corpora sampling different populations while claiming the same method. The cost is a narrower denominator: episodes where a human deliberately bypassed the gate are unobserved, so the measured rate describes non-bypassed pushes only, and any future deny-flip claim MUST be read with that scope.
- **Denominator is independent EPISODES, not records.** Collapse `(repo, branch, session_token)` within 30 minutes, anchored at the episode's **first** record — not a rolling gap, which would chain a whole day into one episode. Record-level counting overstates n by roughly 4x on this repo's history.
- **`false_block`** = the leg would have blocked a push for which a real review demonstrably did occur, or where the artifact was absent for an infrastructure reason the advisory misnames (provider unavailable, lib unsourceable, subject unresolvable). A would-block resolved by the author actually running a review is a **true catch**, not a false block.
- **Bands**, all read off one exact Clopper–Pearson interval — Wilson is anti-conservative and is not used:
  - **DENY** ⟺ `P(X≤k | n, 0.10) < 0.05`
  - **NARROWED** ⟺ upper ≥10% and lower <20%
  - **ADVISORY-ONLY** ⟺ `P(X≥k | n, 0.20) ≤ 0.05`
- **Floor:** n = 29 independent episodes at zero false blocks across ≥2 distinct repos, matching the IMPLEMENT leg's one-sided 95% bound.
- **Agent-claimed adjudications are EXCLUDED** from the rate until a human re-confirms. This leg governs agent pushes; the subject has an incentive to self-grade.
- **A null result is a real result.** n short on the horizon date — or n<5 at the backstop above — **is** the finding, not grounds to extend the window.

- **Backstop: if n<5 by 2026-11-24, that IS the null result for this leg.** Without this the window is unbounded *by construction*: the null-result clause below can only fire once a horizon exists, a horizon only comes into existence at n=5, and nothing obliged anyone to reach n=5 — so a corpus stalling at n=3 would leave the leg advisory forever, reached by doing nothing rather than by deciding anything. 91 days is deliberately generous against the IMPLEMENT leg's measured 0.22 episodes/day (n=5 ≈ 23 days there) because this leg fires only once STATUS is satisfied and will accrue slower; the point is that a deadline exists, not that it is tight.
- **Horizon formula, fixed now so the deferral is arithmetic and not judgement:** `horizon = date(n=5) + ceil(24 / observed_episodes_per_day_at_n5)` days — 24 being the episodes still needed to reach the n=29 floor. Computed ONCE at n=5, recorded in this file with the observed rate, and never recomputed. Deferring a *value* under a *fixed rule* is the honest form of this move; deferring the value AND the rule would leave discretion at exactly the moment the data first becomes visible, which is indistinguishable from picking a horizon to suit the result.
- **Corpus state at registration: ZERO records** (verified 2026-08-25, `~/.claude/.push-review-shadow.jsonl` absent). This is what makes both amendments above clean, and it matters for one more reason: `false_block` is defined partly by the record's `reason` field, so the I2 classifier fix (c131dc4) is a pre-registration dependency, not just a UX repair. Any record written before that fix with `reason:"absent"` could actually have been a not-clean-and-unbound artifact and would not be poolable under this definition. There are none, so the question is closed rather than managed.

**Known risk, stated up front:** the IMPLEMENT corpus was pre-registered at 0.697 episodes/day and is measured at 0.22, putting its n=29 near 2026-12 rather than its 2026-09-08 horizon. This corpus will likely accrue slower still, because it only fires when STATUS is already satisfied. The horizon is therefore set by *rate observed at n=5*, not guessed now — and that deferral is itself pre-registered here so it cannot be presented later as a rescue.

`predicate_version` starts at 1. Bump it whenever the fire condition changes; never pool records across versions.

## Amendment 2026-09-23 — reconstruction, not a horizon

Recorded late, and that is the first thing this section has to say.

### What was missed

The horizon clause above says the value is `Computed ONCE at n=5, recorded in this file with the observed rate, and never recomputed`. **It was never computed.** n=5 was reached 2026-08-27; the n=29 floor was passed 2026-09-03; this section is being written 2026-09-23 with the corpus at 99 episodes across 5 repositories.

Nothing enforced the clause because **no reader existed**. `scripts/shadow-adjudicate.sh` serves the IMPLEMENT leg only, and until this change the sole consumer of `REVIEW_SHADOW_LOG` outside the writer was a test. A pre-registration with a floor, a formula and a backstop but no instrument reaches its floor silently and stays advisory by inertia — the exact outcome the IMPLEMENT leg's history was cited here to avoid.

The registered rate expectation was also wrong in the direction nobody guarded against. This file predicted accrual *slower* than the IMPLEMENT leg's measured 0.22 episodes/day. Observed: **3.68 episodes/day**, with 42 episodes in the last seven days.

### `n` is used in two senses above, and they disagree about whether a deadline is live

Found in review of this amendment, and it is a defect in the amendment as much as in the original text. An earlier draft of this section asserted that "only the starvation backstop could ever have fired, and it could not" — **that sentence is retracted**, because it silently adopts one reading of `n` while the instrument this change ships adopts the other.

| clause | reading `n` requires | value today |
|---|---|---|
| Floor (L89) — "n = 29 … **at zero false blocks**" | **adjudicated**; the qualifier cannot be evaluated without labels | **0** |
| "Agent-claimed adjudications are EXCLUDED from **the rate**" (L90) | adjudicated, human-confirmed | 0 |
| Backstop (L93) — sized against "measured 0.22 **episodes/day**", "a corpus stalling at n=3" | **recorded**; its whole argument is accrual | 99 |
| Horizon formula (L94) — "24 being the **episodes still needed**", `observed_episodes_per_day_at_n5` | recorded; under an adjudicated reading it has no referent, since nothing generates adjudications per day | 99 |

Both readings are supportable from the registered text. That is not the defect. **The defect is choosing a different one per clause** — and an earlier draft chose, in each case, the reading that keeps the experiment open.

What follows differs materially:

- **Recorded `n` throughout.** The floor's `n=29` has been met since 2026-09-03; the conjunct that fails is *"at zero false blocks"*, not `n`. The backstop is dead.
- **Human-confirmed `n` throughout** — what `scripts/review-shadow-adjudicate.sh` actually computes, and the conservative reading. Then **the backstop is LIVE**: `n = 0`, and `n<5 by 2026-11-24` converts continued non-adjudication into the registered permanent null result on that date.

### Operative reading, and why not simply defer

A first draft of this section stated both readings and chose neither, leaving it "for the owner to settle". Review found that to be the backstop's own failure signature wearing a different hat, and it was right:

- A state **reached by doing nothing**, in which **no clause can be shown to have fired**, is exactly what "unbounded *by construction*" describes. On 2026-11-24, with no ruling, nobody could say whether the backstop had fired.
- It defers a binary interpretive choice **to the day its consequence lands**. Whoever settled it then would be settling it with the outcome already visible — the retrospective discretion this very amendment condemns two paragraphs above.
- And the decisive one: **`scripts/review-shadow-adjudicate.sh` already implements human-confirmed `n`.** A document that declines to choose while the shipped instrument has chosen is the same defect as the retracted sentence — asserting one reading while shipping another — only harder to notice.

So: **human-confirmed `n` is the operative reading, unless and until the repository owner rules otherwise.** Three things make that a defensible act rather than a seizure of authority:

1. **The outcome is not yet realised.** n=0 adjudicated is known, but whether the backstop fires is 62 days out and still changeable by doing the adjudication work. No reading is being picked to make a result come out a particular way.
2. **It is the against-interest choice.** Of the two, the recorded reading is the attractive one: it kills the deadline and imposes no obligation. The human-confirmed reading **re-imposes a deadline on the people choosing it**. The integrity rule exists to stop someone picking the reading that gets them what they want; this is definitionally not that.
3. **Its error is the recoverable one.** Adopt it and be overruled: nothing is lost — the leg was advisory throughout and some adjudication happened early. Adopt the other (or adopt nothing, which behaves the same) and later be ruled the other way: the backstop may have fired unnoticed and the window closed with nobody deciding. That is unrecoverable. **Default to the reading whose error can be undone.**

**Consequently the backstop is LIVE**: `n = 0`, and `n<5 by 2026-11-24` converts continued non-adjudication into the registered permanent null result on that date — the leg advisory by *decision* rather than by inertia, and the window closed.

**The owner's override has its own deadline: 2026-10-27.** A ruling after that is a ruling made with the consequence in view, which is the thing being guarded against. Silence past that date is not consent to anything except the operative reading already stated here.

**A cleaner route exists and is recommended over ruling between the two.** Declare *this* window closed as a null result on the honest ground that **it was never instrumented** — documented above and not in dispute — and register a NEW prospective window with an unambiguous `n`, a named adjudicator and a date. This amendment already requires any future window to be "registered as explicitly new", so that concession is spent; and it is the only route on which nobody has to adjudicate a textual ambiguity bearing on their own obligations.

**The remedy this amendment owes and does not otherwise give.** It diagnoses that the real blocker is unscheduled human labelling, then registers no fix for it. With a backstop 62 days out, 99 unlabeled episodes and a `--next` that now works, naming **who adjudicates and by when** is concrete and cheap — and it is the whole difference between the null result being a decision and being another lapse.

### The reconstruction, and why it does not settle the horizon

Applying the formula to inputs that were already fixed facts at n=5:

| reading of `observed_episodes_per_day_at_n5` | elapsed | rate | horizon | episodes by then |
|---|---|---|---|---:|
| first record → 5th episode | 1.04 d | 4.81/day | 2026-09-01 | **21** |
| registration (2026-08-25) → 5th episode | 2.90 d | 1.73/day | 2026-09-10 | 56 |

The 29th episode arrived 2026-09-03. **The two readings give opposite pre-registered outcomes**: the first is below the n=29 floor and therefore *is* the registered sample-shortfall null result; the second is not. An earlier draft of this amendment reported that every reading fell in the past and treated the ambiguity as moot — that framing concealed precisely the distinction the clause protects, and selecting the later reading now, having seen which one clears the floor, would be the retrospective discretion the clause forbids.

So this is a **reconstruction**, not a horizon. The rate's time origin was never uniquely specified, and no contemporaneous evidence resolves it.

**This section computes nothing that constrains any future decision.** A deadline derived after the floor was already passed cannot do the job a stopping rule exists to do — that job was to fix a date before anyone knew whether the corpus would clear it, and it is unrecoverable now. Even the reassurance that "a pessimistic 1.0/day still lands in the past" is hindsight-directed: it is only reassuring to someone who already knows today's date. The table above is recorded as historical actuals, not asserted as binding. Any future prospective window must be registered as explicitly new, not presented as a continuation of this one.

### The pre-registration modelled the wrong risk

Worth carrying into the next one rather than patching here. Every safeguard in this file — the backstop, the deferred horizon, the "known risk" note — guards against **slow episode accrual**. The corpus accrued 15x faster than predicted and stalled anyway, on a step the pre-registration never mentions: the floor is n=29 *adjudicated* episodes, adjudication is human work, and nobody scheduled any. Zero of 99.

No horizon arithmetic can diagnose that, because the horizon clause measures supply and the blocker is labelling. A pre-registration whose floor depends on human effort has to name who does it and when, or it registers a bar that can be reached and still never cleared.

### The corpus is not poolable, for a reason that predates this amendment

`78aa21e` ("measure the push gate's subject from the gated command, not the session cwd", #219, 2026-09-01) changed **this leg's own fire condition** — `_diff_touches_material_source` and `review_verdict_covers_head` both moved from the session root to the resolved subject. That commit bumped `hooks/lib/implement-shadow.sh` and left `hooks/lib/review-shadow.sh` untouched.

All 199 live records therefore carry `predicate_version 1` while spanning two different fire conditions. The field whose entire job is to prevent pooling does not partition this corpus, and a timestamp cannot recover the provenance: sessions run cached plugin versions.

Versioning is corrected as follows, keeping the three changes distinct:

- `predicate_version 1` — pre-#219 fire condition (session-derived).
- `predicate_version 2` — post-#219 fire condition (subject-derived). This bump has **two independent grounds**, and recording only the first would license treating the next recorder change to the episode key as schema-only:
  - (a) `78aa21e` changed this leg's own fire condition on 2026-09-01 and the writer was never bumped; and
  - (b) **the recorder fix independently qualifies**, because `repo` and `branch` are not description — they *are* the episode key `(repo, branch, session_token)`, the denominator this floor is computed over, and `head_sha` is the adjudicator's anchor. A session-derived branch can name a concurrent session's parked branch, so pooling can split one real episode into two (inflating `n` toward the floor) or send an adjudicator to the wrong branch's history.

  So the rule stated in the original text — *fire condition ⇒ predicate, describes ⇒ schema* — **has a gap, and this record is the evidence.** The test is not "does this change when the leg fires" but "does this change what a pooled episode denominator, or a pooled true_catch/false_block label, MEANS". Read literally, the old rule gives the wrong answer here in good faith.
- `schema_version 2` — the record now *describes* the subject rather than the session checkout. Descriptive, and carried alongside (b) above rather than instead of it.

Records already on disk are reportable but **not poolable**, and `--status` says so in those words with the cause named. Silently counting them and silently dropping them are the same error facing opposite ways; the second is what blacked out the IMPLEMENT corpus.

### Standing conclusion

**The deny-flip criterion is NOT established and the leg stays advisory.** This does not depend on resolving the horizon ambiguity: the floor is *n=29 at zero false blocks*, there are **zero adjudications**, and zero adjudications is not zero false blocks — it is no measurement.

**Unchanged and not open:** the floor's *value*, the bands, the episode definition, the `false_block` definition and the diversity requirement. They were registered before any data existed. Missing the horizon is a reason to build the instrument, never a reason to renegotiate the bar.

One honest exception to that heading, stated rather than buried: the floor's **denominator** was ambiguous in the original text (above), and the shipped reader necessarily implements *one* reading — human-confirmed episodes. That is a **resolution, not a preservation**, and its direction is conservative: it makes the flip harder to clear, never easier, and it makes the terminating null result reachable again. The choice is still the owner's to ratify.

Also worth recording, because it is what makes the version bump cheap rather than merely principled: since **zero episodes were ever adjudicated**, discarding the 199 older records destroys no measurement value at all. Only unlabeled supply is lost.

At the observed rate the floor is reachable again in roughly a week and a half of ordinary work, which is why a corpus nobody can vouch for is not worth keeping.
