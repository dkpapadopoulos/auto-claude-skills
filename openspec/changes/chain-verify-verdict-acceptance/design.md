# Design: a structural bar for the chain-block VERIFY widening

**Status: rules frozen 2026-09-24. Bar DISCHARGED 2026-09-24 — outcome REFUSE, and separately REPAIR. See "Discharge".**

This document is a pre-registration. "The claim", "Operational contract",
"Enumerated falsifiers" and "Decision rule" were written and committed **before
any measurement of the population the widening would newly allow**, so that the
result cannot select the rule. Findings go in "Discharge", appended — never by
editing the sections above. A falsifier added after the freeze is added as a
**dated amendment stating why the list was incomplete**.

## Architecture

### The claim under test

> **C.** If `verdict_is_clean(T)` and `verdict_covers_head(T, root, rev)`, then
> verification meaningfully covered the commit named by `rev`.

C is what the global fail-closed leg already assumes. The flip under
consideration is whether Check 2 may assume it too.

Predicate parts, from `hooks/lib/verdict.sh`:

- `verdict_is_clean` — artifact present and parseable, `.failed == []`,
  `.could_not_verify == []`, `.gate_gaming_status == "clean"`. Missing `.failed`
  and `.could_not_verify` **default to empty**.
- `verdict_covers_head` — `.sha` equals the subject commit **or is an ancestor**.
- `verdict_resolve_token` — own-token at exact HEAD; else a cross-token bridge
  over artifacts bound to the exact HEAD; else own-token ancestor coverage.

### Operational contract: what "meaningfully covered" means

**A finite enumeration cannot certify an undefined predicate.** Without a
boundary there is always one more falsifier, and "the list is complete" is not a
claim anyone can evaluate. So the contract is fixed first, and the enumeration is
organised as *failure transitions across its boundaries* rather than as a list of
remembered mishaps. This is the correction that makes the bar checkable.

Verification **meaningfully covered** commit `X` iff all seven hold:

| | Boundary | Requirement |
|---|---|---|
| **B1** | **Shipping-subject identity** | `X` is what the gated command actually ships — every ref it moves, in the repository it moves them in. |
| **B2** | **Byte identity** | The bytes measured are the bytes of `X`: no uncommitted, untracked, or mid-run-mutated divergence. |
| **B3** | **Command adequacy** | The commands run are the repo's declared gate, not a weakened or re-baselined version of it. |
| **B4** | **Execution completeness** | Each declared command ran to completion and its true status was observed — not masked by a pipeline, a background launch, or a trailing success. |
| **B5** | **Provenance** | The record was produced by an observed run, not asserted by its beneficiary. |
| **B6** | **Environment and freshness** | Result-determining inputs outside the commit were the same as at push time. |
| **B7** | **Claim scope** | The declared gate exercises what is being shipped. |

A falsifier is a **reachable** state in which the antecedent of C holds and at
least one boundary fails.

### What "reachable" means

*An executed sequence against the real guard, in a state where Check 2 currently
denies, that the widening turns into a **guard-level allow**.* Not an argument
that such a sequence exists; not a predicate returning true in isolation — the
other legs still run, so a falsified predicate is not yet a false allow. This is
the **marginal** population: currently-denies AND would-allow AND every remaining
deny passes.

Per #205, each determination is **paired** — falsifier present and absent, all
else fixed, the two runs must disagree — with a **positive control** in the same
harness, so "did not reproduce" is distinguishable from a harness that
reproduces nothing. A non-flipping pair has three explanations (claim false /
intervention incomplete / preconditions unmet) and the applicable one must be
named. Reproduction runs in a detached worktree, never the shared tree.

## Enumerated falsifiers

Frozen 2026-09-24. Sixteen, mapped to the boundaries they break. F9–F16 and the
corrections to F1–F8 come from adversarial review (see Dissenting views);
recorded before the freeze, which is the point of holding it.

| # | Falsifier | Breaks | Expected |
|---|---|---|---|
| **F1** | **Ancestor drift** — `.sha` is an ancestor; the intervening delta is unverified. Classify by whether that delta is behaviour-changing; ancestry alone is not absence of coverage. | B1 | Reachable |
| **F2** | **Dirty measurement tree, flag true** — `worktree_dirty` recorded and deliberately never deny-wired. | B2 | Reachable |
| **F3** | **Mid-run HEAD straddle, unequal endpoints** — `gate-run-straddled-commit` enters `could_not_verify[]`, which `is_clean` rejects. | B2 | **Closed for unequal endpoints only.** A→B→A and unchanged-HEAD byte mutation are NOT closed by it — those are F10. |
| **F4** | **Gate self-grading** — name-preserving `run:` rewrite to a trivial command; the checker documents this limitation itself. | B3 | Reachable |
| **F5** | **Artifact authorship** — the record is shell-writable and `verify-and-record.sh` says in its own header it is **not a trust boundary**. Broader than forgery: `project-verification/SKILL.md` Step 3 *instructs the model to write the artifact* from values it read out of its own output. | B5 | **Decisive — see below** |
| **F6** | **Consumer-argument consistency** — both legs pass the same `_SUBJ_ROOT`/`_SUBJ_REV`. | — | Closed **as consistency only**, never as a shipping-subject guarantee. That is F12. |
| **F7** | **`test_delta: missing`** — advisory, not deny-wired. | B7 | **In scope, reclassified.** The earlier "the milestone does not guarantee it either" is a comparative argument and not a rebuttal to a universal claim. It is also not proof of absent coverage — existing tests may cover the change — so coverage is judged behaviourally, not by whether a test file changed. |
| **F8** | **Semantic mismatch** — `verification-before-completion` is a behavioural discipline (do not claim done without checking your own claim); `project-verification` runs the declared suite. Different evidence; neither is categorically stronger. | B7 | Reachable |
| **F9** | **Exit zero without a completed run** — the writer takes `eval "$run"`'s status with no `pipefail` (documented at `verify-and-record.sh:146`) and no completion or test-count check. Failing verifier into a successful consumer; backgrounded launch; trailing success masking an earlier failure; successful no-op. Writer-authored, no forgery, survives exact-SHA and clean-tree. | B4 | Reachable |
| **F10** | **Measurement-time mutation with clean endpoints** — `worktree_dirty` is sampled *before* execution and HEAD only at the ends. Concurrent edit mid-run; A→B→A checkout; tests that replace and restore source; untracked/ignored files affecting discovery, imports, config or build. The dirty probe excludes untracked files and no tree snapshot is bound to the record. | B2 | Reachable |
| **F11** | **Non-atomic compound read** — `verdict_is_clean` and `verdict_covers_head` each reopen the file. Reader sees clean artifact A; a writer replaces it with B naming the subject sha but carrying `could_not_verify`; the reader takes coverage from B. The conjunction holds though neither artifact is clean-and-covering. | B5 | Reachable |
| **F12** | **Shipping-subject incompleteness** — `gh pr merge <other-PR>` keeps the local subject; multi-ref/`--all`/`--mirror`/`--tags` deliberately keep measuring HEAD and only announce under-measurement; an unmatched common-git-dir falls back to the session repo rather than refusing; configured implicit push refspecs are not consulted; a named branch stays symbolic and is not bound to the checked object id. | B1 | Reachable |
| **F13** | **Token selection suppresses contrary evidence** — own-token exact-sha clean wins immediately even against a failing sibling at the same sha; sibling scanning prioritises only non-empty `failed`, so `could_not_verify` or `suspect` siblings do not displace a clean one; same-token concurrent writers overwrite by publication order, not evidentiary strength; `SKILL_SESSION_TOKEN` selects the destination ahead of normal resolution. | B5 | Reachable as a **precedence matrix**, not as "the bridge works" |
| **F14** | **Replay across time, worktree and environment** — the bridge matches on sha alone: no repository identity, environment, gate digest or timestamp. `ts` is written and never read by the acceptance predicates, and session GC does not prune these artifacts. Same-sha worktrees can differ in ignored dependencies, generated output, local config and external services. Detached HEAD is *not* itself a bypass (these predicates are commit-keyed), and cross-worktree reuse is not inherently invalid when the inputs match. | B6 | Reachable; requires the contract to state which inputs and what freshness |
| **F15** | **Schema permissiveness** — `verdict_is_clean` requires no non-empty `passed`, no recognised writer, command, timestamp, substrate or schema version, and defaults missing arrays to empty. `{"sha":…,"gate_gaming_status":"clean"}` satisfies it. Also: the skill's discovery-fallback pipes `git diff` into the gaming checker, so a failed diff delivers empty input. | B5 | **Predicate half confirmed by execution during enumeration-building** (see Discharge note) |
| **F16** | **Gaming baseline erases the weakening** — `_routing_base` tries `origin/HEAD`, then the branch upstream. With no `origin/HEAD` and an upstream already naming the feature tip, the gaming diff can be empty; a weakening already present in the chosen baseline is invisible regardless. | B3 | Reachable; broader than F4 |

### F5 is the falsifier that decides this change

The verdict artifact is model-authored **by design**, not merely writable. If
that is so, the global fail-closed leg is already satisfiable by assertion, and
Check 2 is a second lock on the same door — under which reading the
"inconsistency" #254 reports is defence-in-depth and the flip removes it. The
standing rule `never-suppress-a-gate-on-agent-writable-state` points the same way.

The qualification matters and is recorded now: a `Skill`-return milestone does
**not** prove the discipline happened either, so "second lock" is a claim about
*independence* of two weak signals, not about one being sound. That is measured,
not assumed.

## Decision rule

Frozen 2026-09-24. The rule separates two decisions that must not be bundled:
**(i)** whether to add an acceptance path to Check 2, and **(ii)** whether the
shared infrastructure behind that evidence needs repair. A finding about (ii)
never licenses (i).

**WIDEN** — no falsifier is reachable at guard level in the marginal population
beyond those already reachable on the global fail-closed leg. Check 2 then
accepts using the same verdict predicate, token resolution and subject as that
leg, so the two cannot diverge.

**NARROW** — a falsifier is reachable *and* closable by tightening what Check 2
accepts. Ships only under the tightening. Named in advance:

- `verdict_sha_is_head` instead of `verdict_covers_head` (F1);
- `worktree_dirty == false` **explicitly recorded false**, not merely "not true"
  (F2 — an absent field must not read as clean).

Recorded now: **NARROW is risk reduction, not a soundness result.** F9–F16
survive it in relevant forms. Adopting NARROW is a decision to accept those,
and must say so in the shipping PR rather than implying the hole is closed.

**REFUSE, and separately REPAIR** — a falsifier is reachable and no named
tightening closes it. Check 2 is left exactly as it is, and #254 d2 closes as
*not the defect it was reported to be*, with the #291 advisory corrected so it
stops implying the chain leg is in the wrong.

Repairs are then filed against the **shared component**, not against the global
leg alone: token selection, non-atomic reads, subject resolution and writer
provenance are consumed by `routing-governance` and `verify-hardening` too, so a
fix scoped to one leg leaves the others exposed. Each gets its own change and
its own argument.

A tightening or repair not named here may be adopted only as a dated amendment
explaining why this list was incomplete.

### Two recorded limits of the rule

**WIDEN's comparison is relative, deliberately.** Any falsifier of C is inherited
by both legs, so an absolute standard returns REFUSE for every possible
measurement and the bar would decide nothing. The comparison is against the leg
that already ships.

**Narrowing the verdict path does not establish the invariant.** Global VERIFY is
an OR over ledger, composition, invocation, bridge and verdict evidence. If the
desired property is meaningful commit coverage, removing one disjunct while
unbound status alternatives remain cannot deliver it. Out of scope here; stated
so the next change does not mistake a narrowed verdict path for a solved problem.

## Trade-offs

**A structural bar can be wrong by omission; a rate bar can only be wrong
slowly.** If the enumeration misses a falsifier the flip ships with an unmeasured
hole and nothing later surfaces it, because a false allow leaves no record. That
is the price of matching the instrument to the risk direction. It is paid down
by deriving the list from the contract's boundaries rather than from recalled
examples, by adversarial review before the freeze, and by recording the list as
**known-possibly-incomplete rather than as a proof** — the enumeration went from
8 entries to 16 under one review pass, which is itself the evidence for that
label.

**No corpus means no ongoing signal.** Once discharged this bar says nothing
about the future: a later change to `verdict_is_clean`, `gate-gaming-check.sh`
or the writer can reopen a falsifier silently. Mitigation is the spec's binding
of Check 2's predicate to the global leg's, pinned by test, so the two move
together.

**Two of three outcomes cost more than shipping the flip.** REFUSE and REPAIR
both end with more work than WIDEN, and one ends with defects filed against
components that currently ship and are believed correct. Recording that before
measuring is the point: a rule whose cheapest outcome is also its default is not
a rule.

## Dissenting views

**Adversarial review (Codex, 2026-09-24), on the enumeration.** Supplied F9–F16
and the corrections to F1–F8 above. Its headline position: *"I would not WIDEN,
and your proposed NARROW is insufficient — exact SHA plus `worktree_dirty ==
false` still permits unmeasured bytes, incomplete execution, and evidence
assembled from different concurrent runs."* Ranked execution completeness (F9),
measurement identity (F10), atomic reading (F11) and shipping-subject identity
(F12) first, on the ground that each defeats NARROW without requiring forgery.

Recorded as a dissent rather than adopted as a finding: it is a source-derived
analysis, explicitly not a reachability measurement, and the bar's own standard
is an executed guard-level pair. If discharge confirms it, the outcome is REFUSE
and the dissent becomes the finding.

**On the rule's shape.** The same review held that the original three outcomes
conflated adding an acceptance path with repairing an existing one. Adopted —
that is why REFUSE now carries a separate REPAIR limb addressed at shared
components rather than at the global leg.

**On the contract.** The same review held that a finite enumeration cannot
certify an undefined "meaningfully". Adopted — B1–B7 exist because of it, and
the enumeration is organised across those boundaries rather than as a list.

## Discharge

Run 2026-09-24 against the real guard at `7eed100` (+ this change's commit), in
the detached worktree `/private/tmp/acs-254-d2`. Capture replay disabled
(`PUSH_GATE_CAPTURE_DISABLE=1`) so each cell measures one guard process.

### Outcome: REFUSE, and separately REPAIR

**F5 is reachable at guard level in the marginal population, and no named
tightening closes it.** Check 2's acceptance predicate is left unchanged.

### F5 — paired measurement

The falsifier is the artifact an agent can write for itself:
`{"sha":"<HEAD>","gate_gaming_status":"clean"}`. Two fields. No verification ran.

| Cell | Guard | Falsifier | Result |
|---|---|---|---|
| A | widened | present | **ALLOW** |
| B | widened | absent | deny — *the pair disagrees* |
| C | on-disk (today) | present | deny — *marginal population confirmed: this state denies today* |
| D | on-disk, milestone genuinely credited | — | ALLOW — **positive control**: the harness can produce an allow |
| E | widened **with only the patch removed** | present | deny — the flip is caused by the widening, not by a neighbouring mechanism |

The allow in A is a full guard-level allow: every remaining deny leg passed.

### The named tightenings do not close it — measured, not argued

Symmetry matters here: the registration forbids recording reachability by
argument, so un-closability was measured the same way. NARROW was built exactly
as registered — `verdict_sha_is_head` instead of `verdict_covers_head`, plus an
explicitly recorded `worktree_dirty == false`.

| Artifact | Result |
|---|---|
| 2-field, as in A | deny — *the tightening is active* |
| 3-field: agent adds `"worktree_dirty": false` | **ALLOW** |
| control: `"worktree_dirty": true` | deny |
| control: ancestor sha | deny |

Both tightenings are defeated by adding **one field** to a file the agent writes.
The two controls establish that the tightening really was in force, so the ALLOW
is not passing on a disabled check.

### F5 is also reachable on the global fail-closed leg, today, unpatched

With no composition state (so Check 2 cannot fire) and REVIEW satisfied from the
branch ledger:

| Artifact | Result |
|---|---|
| minimal 2-field | **ALLOW** |
| full-shape (`failed:[] … passed:[…]`) | ALLOW |
| none — control | deny, naming `verification-before-completion` |

This is what selects REPAIR over a Check-2 fix. The evidence Check 2 was asked to
start trusting is **already** sufficient on the leg downstream of it, so the
"inconsistency" in #254 is Check 2 being the one leg that does **not** accept a
self-authored file.

**Correction, from review — the first draft of this paragraph overclaimed, and
the frozen section had already flagged exactly this.** It said Check 2 is "a
second, independent lock" whose four sources "require a harness-observed `Skill`
return, which the agent cannot produce by writing to `~/.claude/`". That is
false, and measured so:

| Check 2 source, hand-written | Result |
|---|---|
| CONTROL: nothing forged | deny `chain-verify` |
| `.skill-composition-state-*` `.completed` | **ALLOW** |
| `.skill-invocation-evidence-*` | **ALLOW** |
| branch-ledger record (`<sha> <ts>`) | **ALLOW** |
| SIBLING ledger dir at HEAD (the #131 bridge) | **ALLOW**, carrying the bridge advisory |
| CONTROL: sibling ledger dir at an unrelated sha | deny — the bridge's HEAD binding holds |

All four sources are plain files under `~/.claude/`, and the ledger key is no
obstacle — it is a sha1 of (origin URL, branch) computed by a lib that ships in
the repo. The bridge is the only one that announces itself, and its sha binding
is real: an unrelated sha does not bridge.

The frozen enumeration anticipated this: it recorded that a `Skill`-return
milestone "does **not** prove the discipline happened either, so 'second lock'
is a claim about *independence* of two weak signals, not about one being sound.
That is measured, not assumed." It was then asserted here without being
measured. The pre-registration's own discipline is what caught it.

**The distinction that actually survives is production, not forgeability.** The
verdict arrives with **no deliberate act** — `project-verification` instructs the
model to author it — so widening Check 2 would add an allow path satisfied in
the ordinary course of doing the work wrong. The other four are normally written
only by hooks, so supplying them takes a decision to fake evidence. Neither is a
security boundary.

**This does not disturb the outcome.** REFUSE rests on the measured cells above:
F5 is reachable in the marginal population and no named tightening closes it.
"Independent lock" was rationale, and the decision rule never referred to it. If
anything the surviving reason is the stronger one, because it is true.

Note this is not forgery in the hypothetical sense. `project-verification/SKILL.md` Step 3 instructs the model to author this artifact from
values it read out of its own output, and `verify-and-record.sh` says in its own
header that the artifact is not a trust boundary. The measurement shows what
that already costs.

### What was NOT measured, and why

**F1–F4, F6–F14 and F16 were not measured at all.** The decision rule terminates
on the first reachable falsifier no named tightening closes, and F5 is that
falsifier. They remain enumerated-but-unmeasured, and the bar must not be
credited with evidence it did not collect.

**F15 is the one exception, and it is a partial one.** Its frozen row says
"predicate half confirmed by execution", which is accurate and narrower than it
may look: during enumeration-building `verdict_is_clean` was called directly on
`{"sha":"deadbeef","gate_gaming_status":"clean"}` and returned CLEAN. That is a
**predicate evaluated in isolation**, which `specs/pdlc-safety/spec.md` expressly
forbids recording as reachability — the guard's other legs still run, so a true
predicate is not yet an allow. F15 therefore has **no reachability pair** and is
not a measured falsifier; what was confirmed is only that the schema accepts a
two-field record. An earlier draft of this section stated a blanket "F1–F4,
F6–F16 were not measured", which contradicted the frozen row and left its
"(see Discharge note)" pointing at a paragraph that same draft had deleted.
Both are corrected here; the frozen row is untouched. Several are relevant to the repair and are the natural
starting set for it — F9 (exit zero without a completed run), F11 (non-atomic
compound read) and F15 (schema permissiveness) all bear directly on artifact
provenance.

### Consequences

1. **#254 d2 closes as not the defect it was reported to be.** Check 2 declining
   the verdict is the correct behaviour of the only leg that still requires
   harness-mediated evidence.
2. **The #291 advisory text is wrong in emphasis** and should be corrected: it
   tells the reader the global leg treats the verdict as "stronger evidence",
   which measurement shows is true only in the sense that it is *easier to
   supply*. It should stop implying Check 2 is the leg in the wrong.
3. **A defect is filed against the shared component** — verdict provenance and
   schema, `verdict_is_clean` accepting a two-field self-authored record — not
   against the global leg alone, because `routing-governance` and
   `verify-hardening` read the same predicates.

### Pre-freeze execution, disclosed

Restored after being dropped in a rewrite. While verifying the factual basis of
F15 during enumeration-building, its predicate half was run directly:
`{"sha":"deadbeef","gate_gaming_status":"clean"}` returns CLEAN from
`verdict_is_clean`. That is a check on a source claim, not a measurement of the
marginal population, and it is **not** a discharge — the bar requires a
guard-level paired run with a positive control. Recorded so the bar cannot later
be credited with evidence it did not collect.

### Probe faults hit on the way, recorded so the cells are auditable

Five, each of which produced a plausible wrong reading before it was caught. The
fourth was mine while trying to REFUTE a review finding, which is the one worth
remembering:

- **The first matrix measured the unpatched guard.** With capture enabled, a
  deny appeared on stdout carrying none of the patched copy's text. Caught by
  fingerprinting the message in the copy under test and finding the marker
  absent; settled by disabling capture. A subsequent clean check confirmed the
  capture trap does **not** leak — exactly one JSON object in every
  configuration, zero on an allow — so there is no defect here to file.
- **`sed` corrupted a guard copy** whose deny message contains a multibyte
  em-dash, flipping one cell's result while `bash -n` stayed green. All
  instruments were rebuilt byte-safely in Python. This is the
  `perl-pipe-delimiter-corrupts-file` class.
- **The attempted refutation of the review finding denied uniformly, control
  included** — and would have "disproved" a correct finding. Once this branch
  touched `hooks/`, every cell run in a fresh `HOME` denied at
  **routing-governance**, never reaching Check 2; the control denied for the
  same wrong reason, so the matrix looked coherent. Seeding a clean covering
  verdict isolated the gate under test and all four sources then flipped. A
  control that agrees with the cells is not a control.
- **An advisory-carrying ALLOW was scored as a DENY.** Measuring the bridge
  source, the classifier keyed on "is stdout non-empty" — but an allow still
  emits `additionalContext` when it has an advisory to deliver, so the one
  source that ANNOUNCES itself was the one misread. Classify on
  `permissionDecision`, never on output presence.
- **The global-leg cells first denied uniformly, control included.** The guard
  reads the branch ledger from the *process-derived* root (#219, deliberately),
  so running it from the session cwd keyed the ledger to a different branch than
  the worktree under test. Aligning the cwd made the control discriminate. A
  uniform result across a control is the tell.
