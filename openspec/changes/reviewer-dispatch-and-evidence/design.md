# Design: reviewer dispatch authorization + reviewer-ran evidence

## Architecture

Three defects, three independent mechanisms. They ship together because
fixing any one alone leaves the symptom (no review happens) intact.

### A. Standing authorization (defect 1)

`hooks/skill-activation-hook.sh` already renders REVIEW-phase context. It gains
a line derived from `phase_enforcement.review_dispatch` in
`~/.claude/skill-config.json`:

| Value | Rendered behavior |
|-------|-------------------|
| `auto` (default, and when the key is absent) | REVIEW context states that reviewer-subagent dispatch is pre-authorized and must not be deferred to the user for approval. |
| `ask` | No authorization line is rendered; current behavior. |

Read with the same fail-open shape as the existing readers
(`openspec-guard.sh:862`, `skill-gate.sh:86`): missing file, missing key,
missing `jq`, or unparseable JSON ⇒ treat as `auto`, because `auto` is the
default and a config read failure must not silently restore the stall this
change exists to fix.

**Why a config key rather than hardcoded text.** The authorization has to be
truthfully attributable to the user, since its whole job is to satisfy "unless
the user requested it". Two grounds, in order of strength:

1. An explicit `review_dispatch: "auto"` the user wrote — unambiguous.
2. The default: **invoking a review skill is itself the request.** A skill whose
   entire purpose is to obtain a review, that cannot dispatch a reviewer, does
   nothing. This is the reading the plugin adopts by default, and the `ask`
   opt-out exists so anyone who disagrees can say so.

**Scope: read-only reviewers only.** The rendered text authorizes dispatch of
agents that read and report. It does not authorize `general-purpose` agents
given write tasks, `agent-team-execution` implementers, or anything with
outbound reach. Those keep asking. Rationale: the user's ruling was about
*review*, and a standing pre-approval for file-writing agents is a materially
larger expansion of autonomous scope than what was asked for.

### B. Correct reviewer target (defect 2)

Replace `superpowers:code-reviewer` at all five sites. The replacement text
names `general-purpose` + the superpowers `code-reviewer.md` template as the
portable default (this is what superpowers itself specifies at
`skills/requesting-code-review/SKILL.md:34`), and names
`pr-review-toolkit:code-reviewer` / `feature-dev:code-reviewer` as preferred
when installed.

The text must not hard-require a plugin this repo does not control. Agent
availability is per-install; the instruction states a preference order and a
fallback that always exists (`general-purpose` is built in).

### C. Reviewer-ran evidence (defect 3)

**Writer** — `hooks/reviewer-evidence-hook.sh`, `PostToolUse` on `^(Task|Agent)$`.
On a successful reviewer-agent return it calls
`branch_ledger_record "reviewer-ran"`.

Reusing the branch ledger rather than a token-scoped evidence file is the
central choice, and it dodges two documented bug classes at once:

- **Writer/reader token symmetry** (the #51/#97/#122/#131/#133/#151/#156 class):
  the ledger is keyed by `remote-url + branch`
  (`hooks/lib/branch-ledger.sh:8-25`), not by session token, so there is no
  token to scatter.
- **7-day GC.** Token-scoped state is pruned at 7 days by
  `session-start-hook.sh`. The ledger is the documented cross-session carrier,
  so "reviewed Monday, pushed Friday" survives.

**Reader** — a leg in `hooks/openspec-guard.sh` on the REVIEW path. Population
is deliberately narrow: it evaluates **only** pushes where the
`requesting-code-review` milestone IS credited but `reviewer-ran` is absent.
That is exactly the defect — a claimed review with no reviewer. Where REVIEW is
not credited at all, the existing deny legs already fire and this leg says
nothing.

**REVIEW is gated at TWO independent sites, and both must be taught.**
`requesting-code-review` is checked by the chain-scoped Check 1
(`openspec-guard.sh:534-548`) *and* by the repo-wide global fail-closed gate
(`:797-829`, `_DECISION="deny:global-failclosed"`), which runs for every push
regardless of chain state. Both accept the same four evidence legs
(`:538-542`, `:800-813`). A reviewer-evidence leg wired into only Check 1
leaves the global gate passing on the old milestone alone — and because this is
a routing repo, its own pushes exercise the global path. The new predicate is
therefore a **single shared function called from both sites**, mirroring how
`_ledger_has` / `_invoc_ok` / `_bridge_has` are already shared. Surfaced by the
Codex pass; verified against both line ranges.

**Warn-first.** The leg appends to `_STALE_MSG` and sets no
`permissionDecision`, mirroring the IMPLEMENT leg at `openspec-guard.sh:372-389`.

### D. `^Task$` → `^(Task|Agent)$`

`hooks/hooks.json` currently matches `^Task$` for the cozempic checkpoint hook.
Measured against 12 local transcripts, this harness emits `Agent`, so that
matcher is dead. Widened rather than replaced: `Task` is kept for older Claude
Code builds, since the plugin ships to installs this repo cannot survey.

**Widening ACTIVATES a dormant hook, and that is a behavioral change, not just
a lint fix.** `cozempic-wrapper.sh checkpoint` has not been running on this
harness. After the widening it executes on **every subagent return**, in
sessions that dispatch many, and that entry carried no `timeout` while the new
reviewer-evidence hook has one. Reverting is not the answer — a `^Task$`-only
matcher is the copy-paste template that reproduces the exact bug this change
exists to fix. So the widening stands and the entry gains an explicit
`timeout`, bounding a newly-live hook on a hot path. Recorded here because a
consequence nobody wrote down is indistinguishable from one nobody noticed.

## Decisions

**D1 — Detection predicate: `subagent_type` allowlist, plus intent-matched `general-purpose`.**
Bash 3.2 has no associative arrays, so the allowlist is a `case`. Known reviewer
agents (`pr-review-toolkit:code-reviewer`, `:silent-failure-hunter`,
`:pr-test-analyzer`, `:comment-analyzer`, `:type-design-analyzer`,
`feature-dev:code-reviewer`) credit unconditionally. `general-purpose` credits
only when `description` matches a review-intent pattern — required, because
superpowers' own template dispatches `general-purpose`, and unavoidable, because
`general-purpose` is also the workhorse for implementation.

The error direction matters and **inverts at the deny-flip**:

| | While advisory | After deny-flip |
|---|---|---|
| False positive (credit a non-reviewer) | **Costly** — leg goes blind, defect persists silently | Cheap — a push allowed |
| False negative (miss a real review) | Cheap — a spurious advisory | **Costly** — false block |

So the predicate ships *tight* (favouring false negatives) while advisory, and
loosening it **in reaction to spurious advisories** is part of the deny-flip
work, not a later tweak. Recorded here because the natural instinct on seeing
spurious advisories is to loosen immediately, which would destroy the
measurement the flip depends on.

**Measured recall, and the one correction that rule does not forbid.** The
first implementation matched `[Rr]eview*` — a PREFIX. Measured against the real
`description` strings dispatched while building this change, it credited **3 of
9** genuine reviewer dispatches: real descriptions read "Task 1 review: spec +
quality" or "Scoped re-review of Task 1 fix", not "Review …". A predicate that
misses two thirds of real reviews does not measure compliance, it measures its
own blindness, and each miss enters the corpus as "no reviewer ran" on a branch
where one demonstrably did.

Three candidates were measured against that corpus:

| Pattern | Reviewers credited | False positives |
|---|---|---|
| prefix `[Rr]eview*` | 3/9 | 0/7 |
| substring `*[Rr]eview*` | 9/9 | 4/7 |
| word-boundary `*[Rr]eview\|*[Rr]eview[!a-zA-Z]*` | 9/9 | 1/7 |

**The shipped pattern MUST be word-boundary alone.** The first implementation
OR'd word-boundary with `*"code review"*` / `*"code-review"*` substring arms.

**Correction — an earlier version of this document claimed those arms added
"zero recall". That was false**, and the counterexample matters. The arms fire
additionally on `"code review"` / `"code-review"` followed by a LETTER, which
word-boundary cannot match. Measured arms-only strings:

| Arms-only description | Genuine review? |
|---|---|
| `"Dispatch a code reviewer for the auth changes"` | **yes** |
| `"Second code reviewer on the hooks diff"` | **yes** |
| `"code-reviewing the new gate leg"` | **yes** |
| `"Fix the code-reviewer dispatch bug"` | no — implementation |
| `"Task 1: remove dead superpowers:code-reviewer target"` | no — implementation |

So dropping the arms DOES lose real recall. The decision stands anyway, on the
accurate reasoning: the arms' extra matches are exactly the **noun/gerund
class**, which contains genuine reviews and implementation tasks in the same
syntactic shape, and no substring can separate them. D1's asymmetry decides it
— while the leg is advisory, a wrongly credited non-reviewer silently corrupts
the corpus, whereas a missed review costs one spurious advisory. Buying that
recall means buying the false positives inseparably.

The durable fix for this class is the dispatch convention noted below, not a
cleverer pattern. A predicate wider
than the one this table measured means the corpus is adjudicated against a
false-positive profile recorded nowhere, which silently invalidates the
pre-registered rate. If the pattern is ever changed, this table must be
re-measured in the same commit.

Word-boundary ships. Substring is rejected because it matches the *noun*
"reviewer" inside implementer task names. **The one surviving false positive is
`"Task 2: review_dispatch config key"`** — an implementation task whose subject
is literally named review-dispatch. That case credits `reviewer-ran` with no
reviewer having run, which biases the corpus **toward** clearing the deny-flip,
so it is named here and must be segmentable at adjudication rather than left
implicit.

This correction is not the loosening the rule above forbids: that rule is about
trading measurement integrity for quiet, whereas this is a measured recall
failure corrected with the tightest option that fixes it.

**The durable fix is not a better regex.** No regex makes intent exact. The real
answer is to make the DISPATCH side carry a convention the hook can match
exactly — an allowlisted `subagent_type`, or a marker the routing text
prescribes. That is deliberately out of scope here (it would change
reviewer-dispatch instructions already landed and reviewed) and is recorded as
a follow-up.

**D2 — Success detection, and one ASSUMED fact.** `tool_response.is_error`
gates the write, the same field `skill-completion-hook.sh:24` reads for
`^Skill$`. An errored or aborted reviewer is not evidence of a review.

**This is assumed, not measured.** Whether the `Agent` tool's `PostToolUse`
payload carries `is_error` the way `Skill`'s does was never confirmed — a probe
was scoped, then deliberately skipped because it required editing the user's
global settings and two session restarts, against a pattern already running in
production for a sibling tool. What IS confirmed is that agent failure reaches
the harness at all: an implementer subagent died in-session and surfaced as
`idleReason:"failed", failureReason:"Request timed out"`.

The residual risk is one-directional **only because of how the field is read**,
and the first implementation got that wrong. `.tool_response.is_error` is a
TYPED INDEX, not a lookup: jq raises an error indexing an array, string, or
number with a key. Measured end-to-end against the real hook:

| `tool_response` shape | shipped `.tool_response.is_error` | `(.tool_response \| objects \| .is_error)` |
|---|---|---|
| `{"is_error": false}` | credit | credit |
| `{}` / `null` | credit | credit |
| `{"wasInterrupted": true}` | credit | credit |
| `[ {content blocks} ]` | **jq exit 5 → NO RECORD** | credit |
| `"a string"` | **jq exit 5 → NO RECORD** | credit |

Under the naive form, an array-shaped `tool_response` — a plausible shape for
an agent returning content blocks — makes the hook record **nothing, forever,
silently**: `|| exit 0`, empty stdout, exit 0. That is a dead recorder,
indistinguishable from a perfectly compliant repo, and it would make the corpus
read as universal non-compliance while the leg fired an advisory on every push.

The `objects` guard is therefore not a nicety; it is what makes the residual
risk one-directional at all. Measured across ten payload shapes, every
malformed or unexpected one now falls in the CREDIT direction and none
produces a dead recorder: `tool_response` absent, `null`, an array, a string,
`is_error: null`, `is_error: "false"`, `is_error: 1`, and `is_error: {}` all
credit; only a boolean `true` or the string `"true"` blocks.

Two of those deserve naming rather than discovering later. A numeric
`is_error: 1` and an object-valued `is_error` both CREDIT, because the hook
skips only on the literal string `true`. If a harness ever signalled errors
with a truthy non-boolean, a failed reviewer would be credited. That is the
same bounded, pre-registered over-credit exposure as an absent field — not a
new class — and booleans are the JSON convention, but it is the direction the
corpus must be able to segment. With it, the only remaining exposure is the
pre-registered one: an absent `is_error` credits a crashed reviewer, which
inflates apparent compliance and biases the rate **toward** flipping to deny.
While the leg is advisory that costs a missed advisory. **Measuring this is a
precondition of the deny-flip, not of this change** — and the shadow record's
`is_error_field` dimension lets the corpus measure it directly. The producer
SHIPPED: `hooks/reviewer-evidence-hook.sh` writes the sidecar at credit time and
`openspec-guard.sh::_reviewer_is_error_field` reads it, so records carry real
`present`/`absent` data rather than a placeholder.

**`is_error_field: "absent"` is the observable signal for this whole class, and
it covers TWO distinct causes that an adjudicator must not conflate:**

| cause | what the payload looked like | what it means |
|---|---|---|
| object without the key | `tool_response: {}` or `{"wasInterrupted": true}` | the harness did not report an error field |
| non-object payload | `tool_response: [...]` or `"a string"` | the field is *unobservable*; the `objects` guard defaulted it |

Both record `absent`, and the record cannot tell them apart. That is acceptable
— both credit, and the exposure is identical in direction and size — but a rate
computed over `absent` rows is measuring "could not observe an error signal",
NOT "the harness said there was no error". State that when the flip is decided;
reading `absent` as a confirmed success would overstate compliance in the
direction that clears the flip.

`unknown` remains distinct from both, and means something weaker again: no
sidecar was readable at all (a record predating the write, or an unresolvable
ledger directory). It is not evidence about the payload and must be excluded
from any rate rather than folded into `absent`.

**D3 — No attestation escape in this change.** The IMPLEMENT leg accepts
`phase_attest`; REVIEW and VERIFY deliberately reject it — CLAUDE.md records
this as "the auditable-escape asymmetry is deliberate". `reviewer-ran` is a
sub-signal of REVIEW, so accepting attestation for it would quietly breach that
asymmetry through a side door. It stays rejected here. Whether the deny-flip
needs an escape for human/GitHub review is an **open question for that change**,
not a decision this one makes.

**D4 — Grandfathering is a deny-flip precondition, not built now.** **9** live
branch ledgers carry `requesting-code-review` with no possible `reviewer-ran`
(measured at review time; an earlier count of 8 was taken days before). While
advisory this costs 9 spurious advisories, which is acceptable and in fact
useful signal. A hard requirement would need a grace rule; that belongs to the
change that introduces the requirement.

**The steady-state noise risk is the STALE variant, not the missing one.**
Once the recorder is populated, the normal loop is review → fix → commit →
push, so `reviewer-ran`'s bound SHA trails HEAD almost immediately and
`REVIEWER EVIDENCE: stale` becomes the routine output on the global path —
which carried no staleness line at all before this change. Each such message is
TRUE, which is why it is not a defect, but a true message that fires on nearly
every push is the shape that trains people to skim past the gate. The shadow
corpus must therefore segment **fired-and-stale** from **fired-and-missing**,
and the deny-flip must decide separately whether the stale variant should stay
advisory permanently.

**D5 — Fail-open, and the reader announces.** The writer hook is a recorder: on
any failure it exits 0 silently, like every other recorder here. The *reader*
sits on the gate path, so per issue #198 a leg that could not evaluate must say
so rather than fall silent — silence there is indistinguishable from "checked
and clean".

**D6 — Source-guard form, and the one place it must NOT be copied.** The new
writer hook sources `branch-ledger.sh` under `trap 'exit 0' ERR`, so per the
#137 rule it uses
`. lib 2>/dev/null && command -v branch_ledger_record >/dev/null 2>&1 && _OK=true || true` —
never a bare `. lib`, never an `[ -f ]` existence check. Safe here because a
recorder has no deny to lose: the worst case is an unwritten record.

**The guard-side site is the opposite, and the Codex pass got this wrong.** It
advised copying `openspec-guard.sh:330-337`'s shape *including* a `command -v`
check. CLAUDE.md forbids exactly that: *"the `command -v <fn>` guard form is NOT
added to `branch-ledger.sh`'s source site … a lib that sources cleanly but
defines nothing currently DENIES … adding the check would set `_LEDGER_OK=false`
and flip that cell to ALLOW, i.e. weaken enforcement to buy a nicer message."*
The guard site keeps its `[ -f ] && . lib && _LEDGER_OK=true` shape unchanged.
The asymmetry is deliberate and directional: **add `command -v` where a failure
costs a record; omit it where a failure costs a deny.**

Issue #192's residual — a lib failing *during* execution of a sourced line —
is unchanged and not worsened. `branch_ledger_record` ends every command in
`|| return 0` (`branch-ledger.sh:40,44-45`), so it has no bare mid-file command
to trip the trap.

**D7 — Proxy-credited REVIEW is measured, not exempted.** `requesting-code-review`
is satisfiable by proxy: `openspec-guard.sh:434-439` and
`skill-completion-hook.sh:109-115` accept `subagent-driven-development`,
`agent-team-execution`, and `agent-team-review` as standing in for it, because
each embeds a mandated internal review. Whether those flows emit an `Agent`
call the writer hook can see is **unknown** — `agent-team-review/SKILL.md:35`
uses `TeamCreate`, which may not be an `Agent` tool call at all.

This is the highest-probability false-block in the design, so it is resolved by
*measuring* rather than guessing: the leg evaluates proxy-credited pushes and
**records which proxy credited REVIEW** in the shadow entry, so adjudication can
segment them. If proxy flows turn out never to emit a visible reviewer, that is
a finding the corpus will state plainly, and the deny-flip must then either
honor the proxy list or instrument those flows. Deciding it now, with no data,
is how a false-block regime ships.

**D8 — Evidence is SHA-bound at record time.** `_ledger_has` already emits a
staleness advisory when a milestone's recorded SHA differs from HEAD
(`openspec-guard.sh:412-415`). `reviewer-ran` must carry the same binding, or
it is weaker than the milestone it supplements: none of the allowlisted agents
is timing-bound to the pushed diff, so a `silent-failure-hunter` dispatched on
day 1 for unrelated exploration would otherwise credit a day-5 push of entirely
different code.

This is primarily a **measurement-integrity** requirement, not a gating one.
While advisory, an over-credit produces no deny and therefore prompts no
investigation — it silently enters the corpus as compliance and biases the
measured false-block rate *toward* flipping. `branch_ledger_record` already
stores `<sha> <utc-ts>` (`branch-ledger.sh:43-46`), so the binding is free;
the shadow entry records dispatch-time SHA against push-time HEAD so
`shadow-adjudicate.sh` can separate "reviewed this diff" from "ran once, long
ago". Not gated on yet.

## Pre-registration (deny-flip)

Recorded now so the flip is decided on evidence rather than appetite.

- **What is RECORDED vs what the RATE is computed over — two different sets, and
  conflating them is how a corpus silently measures the wrong thing.**

  *Recorded:* one row per **push** (never a merge) where the leg is consulted
  and **no other gate leg denies**, carrying `evidence_present` as
  `present` | `stale` | `missing` | `cannot_check`. Satisfied pushes ARE
  recorded — they are the denominator, exactly as `implement-shadow.sh` records
  `would_block:false` rows.

  *Rate computed over:* only the `missing` and `stale` rows — the ones where
  the leg would block under the flip. A false-block rate that pools `present`
  rows is arithmetically meaningless, in the direction that clears the flip.
  This mirrors CLAUDE.md's standing rule for the IMPLEMENT corpus: any rate
  over that log MUST filter `select(.would_block == true)`.

  `cannot_check` rows are excluded from BOTH — they record an infrastructure
  failure, not agent behavior, and counting them either way biases the result.

  Two exclusions, both deliberate, both corrections made after measurement:

  *Merges are excluded* because every input to `evidence_present` is computed
  from the LOCAL branch, while a `gh pr merge`'s subject is someone else's PR —
  which is exactly why the advisory is already suppressed for merges. A row
  naming the wrong subject is not honest, and `reviewer-shadow.sh` has no
  PR-file-list resolver of the kind `implement-shadow.sh` uses for its
  `diff_base`. Recording merges would require that resolver first.

  *Denied pushes are excluded* because a push blocked by a different leg can
  never be a false block attributable to THIS leg. Such rows would enter the
  corpus as k=0 filler, shrinking the Clopper–Pearson upper bound and biasing
  the decision **toward** flipping to deny. Since shadow rows are not
  retro-classifiable, accruing them under a wrong population discards the
  corpus rather than being fixable later.
- **Unit.** Independent episodes — `(repo, branch, session_token)` collapsed
  within 30 minutes, **anchored at the episode's first record**, matching
  `scripts/shadow-adjudicate.sh`. Record-level counting overstates n roughly 4×.
- **Labels.** `true_catch` = no reviewer genuinely ran. `false_block` = a real
  review happened and the leg could not see it (human review, `/code-review`
  in-process, detached-HEAD key rotation, predicate miss).
- **Floor.** n = 29 independent episodes. **Corrected from an initial n=20,
  which was arithmetically incapable of ever licensing the flip:** at k=0 false
  blocks the one-sided 95% Clopper–Pearson upper bound is 13.91% at n=20 and
  10.15% at n=28, both above the 10% DENY band; n=29 is the first value that
  clears it (9.81%). A floor that cannot clear its own band is a permanent
  advisory wearing a deadline. Same floor and same derivation as the IMPLEMENT
  corpus, for the same reason.
- **Deadline.** 2026-11-30. **Both** conditions are load-bearing: the IMPLEMENT
  corpus accrued at 0.22 episodes/day against a pre-registered 0.697 and its
  n=29 slipped from 2026-09-08 toward 2026-12. Reviewer-dispatch events are
  plausibly rarer still. An n-only rule stalls indefinitely; at the deadline the
  flip is decided on whatever n exists, or explicitly abandoned. Drifting is not
  an outcome.
- **Instrumentation is reused; adjudication is NOT yet built.** The shadow
  record follows `hooks/lib/implement-shadow.sh`'s shape and carries its own
  `predicate_version`. Records across predicate versions MUST NOT be pooled.

  **`scripts/shadow-adjudicate.sh` cannot read this corpus, and saying
  otherwise would be false.** Measured: it hardcodes the IMPLEMENT log path
  (`IMPLEMENT_SHADOW_LOG` → `.push-implement-shadow.jsonl`), pins
  `REQUIRED_PREDICATE_VERSION=2` while reviewer records ship
  `predicate_version=1`, and every field it renders is IMPLEMENT-shaped
  (`impl_in_chain`, `material_source`, `impl_evidence_kind`, `diff_base`,
  `impl_evidence_detail`). Pointing its env var at the reviewer log drops every
  record on the version check alone.

  **So this corpus is write-only as shipped**, and an adjudicator is a
  BLOCKING PRECONDITION of the deny-flip alongside the sample-size floor and
  the calendar deadline. It is deliberately not built here: the corpus needs
  months to accrue, and an adjudicator written before any real records exist
  would be fitted to imagined data — the same invented-input failure this
  change ran into four times. Build it against the first real rows, and reuse
  `shadow-adjudicate.sh`'s episode-collapsing and exact Clopper–Pearson logic
  rather than reimplementing either.
- **Bands.** Exact Clopper–Pearson on the false-block rate, read the same way
  `shadow-adjudicate.sh` reads them: DENY if the upper bound < 10%; NARROW if
  upper ≥ 10% and lower < 20%; ADVISORY-ONLY if lower ≥ 20%.
- **Self-grading exclusion.** Agent-claimed adjudications are excluded until a
  human re-confirms, same rule and same rationale as the IMPLEMENT corpus: the
  leg governs agent behavior and the subject has an incentive to self-grade.
- **Blocking precondition — measure the `Agent` success signal first, and the
  corpus itself can do it.** D2's `is_error` handling is assumed, not measured.
  If the field is absent for `Agent`, crashed reviewers credit `reviewer-ran`
  and the corpus overstates compliance in the direction that clears the flip.

  Rather than requiring a settings-editing probe, the shadow record carries
  whether `is_error` was **present or absent** on each credited return. That
  keeps the recorder functional (an absent field still credits, matching the
  proven `skill-completion-hook.sh` pattern) while making the uncertainty
  measurable: adjudication can segment "credited on an explicit `false`" from
  "credited because the field was missing". If the absent case never appears,
  the assumption is confirmed by observation and the probe is unnecessary. If
  it dominates, the flip must not proceed on that corpus.

  This is strictly better than choosing a default blind. The conservative
  alternative — absence means do not credit — was rejected because it makes the
  feature **inert and silently so** if `Agent` omits the field: a dead recorder
  is indistinguishable from a perfectly compliant repo, and would look correct
  for months.
- **Distinguish "returned without reviewing".** Observed four times in the
  session that built this change: a dispatched reviewer completed, went idle,
  and delivered no verdict until explicitly chased — twice having a substantive
  finding to give. Such a return is non-error and WOULD credit `reviewer-ran`.
  Adjudication must treat it as its own category rather than folding it into
  either "reviewed" or "no reviewer ran", or the corpus measures dispatch
  frequency while claiming to measure review.

## Capabilities Affected

- `pdlc-safety` — REVIEW-phase reviewer-dispatch authorization; warn-first
  reviewer-ran evidence leg on the outbound push/merge gate; correction of the
  reviewer agent target across the routing surface.

## Out-of-Scope

- **Denying on missing reviewer evidence.** Pre-registered above; a separate change.
- **Write-capable agent auto-dispatch.** Implementers, `agent-team-execution`
  teammates, and anything with outbound reach keep asking.
- **Review *quality*.** This proves a reviewer ran, not that it reviewed well.
  Quality stays human-review, consistent with `test-skill-anatomy.sh`'s
  presence-not-quality bar.
- **The `[ ! -t 0 ]` stdin class** (#142) and the **source-execution residual**
  (#192). Untouched; noted so a reader does not read this change as closing them.
- **Fixing `requesting-code-review` crediting itself.** The milestone still
  records on `Skill()` return. This change adds a second, independent signal
  rather than altering an enforcement path 8 branches currently depend on.

## Acceptance Scenarios

1. **Authorization renders by default.** No `skill-config.json`, or no
   `phase_enforcement` key ⇒ REVIEW context contains the dispatch
   authorization. Absent `jq` ⇒ same (fail-open to the default).
2. **Opt-out honored.** `phase_enforcement.review_dispatch: "ask"` ⇒ no
   authorization line rendered.
3. **No dead agent names.** No file under `hooks/`, `config/`, or `skills/`
   contains `superpowers:code-reviewer`.
4. **Reviewer return records.** A `PostToolUse` payload with tool name `Agent`,
   `subagent_type: pr-review-toolkit:code-reviewer`, `is_error: false` ⇒
   `reviewer-ran` present in the branch ledger.
5. **`Task` still records.** Same payload with tool name `Task` ⇒ recorded
   (older-harness compatibility).
6. **Errored reviewer does not record.** `is_error: true` ⇒ no `reviewer-ran`.
7. **Non-reviewer does not record.** `subagent_type: general-purpose` with an
   implementation description ⇒ no `reviewer-ran`.
8. **Leg is advisory.** A push with `requesting-code-review` credited and
   `reviewer-ran` absent ⇒ advisory text present, **no** `permissionDecision`
   in the emitted JSON.
9. **Leg is silent when satisfied.** Same push with `reviewer-ran` present ⇒
   output byte-identical to a pre-change control fixture.
10. **Fail-open announces.** `branch-ledger.sh` unreadable ⇒ the gate still
    emits a decision and the degradation is stated, never silent.

## Trade-offs

- **The hole stays open during measurement.** A determined skip still yields a
  green gate until the flip. Accepted: defects 1 and 2 mean reviewers now run,
  so the residual is compliance drift rather than the systematic gap that
  existed before, and the alternative has a measured 56–94% false-block record
  in this repo.
- **`general-purpose` detection is heuristic.** No amount of regex makes it
  exact. Accepted with the tight-predicate rule in D1; the honest statement is
  that the leg under-counts reviews rather than over-counting them.
- **A trivially-prompted reviewer credits the milestone.** The subject controls
  dispatch, so evidence-of-dispatch is not evidence-of-scrutiny. Accepted: the
  threat model is an honest-but-lazy agent, not an adversary. Stated plainly so
  nobody reads this leg as tamper-resistant.

  **Precisely what this closes and what it does not:** it closes
  *"asked for approval it did not need, then never dispatched at all"* — the
  reported symptom. It does **not** close *"dispatched a rubber stamp"*. The bar
  moves from "did `Skill()` return" to "did a reviewer subprocess run and return
  non-error", which is strictly higher — a lazy agent must actually spawn
  something and wait for it — but it is not a proof of scrutiny and must not be
  described as one.

- **`^Task$` is a live copy-paste landmine.** `hooks/hooks.json:122-131` is the
  obvious template for registering a new `PostToolUse` subagent hook, and it
  carries the dead matcher. Widening it in this change is not incidental
  tidying: left alone, the next person to add a subagent hook inherits exactly
  the bug being fixed here.

## Dissenting views

**Codex sparring pass — adopted findings.** Every code claim below was
re-verified against the cited lines before adoption.

- **Two deny sites** (`:534-548` chain-scoped, `:797-829` global fail-closed).
  Ranked its most severe finding, and correctly so: a leg wired into only the
  first would leave the global gate — the one this repo's own pushes traverse —
  passing on the old milestone alone. Adopted as a shared predicate; see
  Architecture C.
- **Proxy-skill non-coverage** as the highest-probability false-block. Adopted
  as D7, resolved by measurement rather than by a guessed exemption.
- **Timing/staleness over-credit contaminating the corpus.** Adopted as D8. This
  was the sharpest observation in the pass: over-crediting is invisible
  *precisely because* the leg is advisory, so it biases the flip decision with
  nothing to prompt investigation.
- **`n≥29`.** Correct, and it exposed an error in this document's first draft —
  see Pre-registration.
- **Sequencing: ship defect 2 alone, then 1+3 together.** Adopted; see below.
  Its reasoning is right that 3-without-1 cannot fire and 1-without-3 is
  strictly worse than today.
- **Session-token resolution copied from `skill-completion-hook.sh:29-40`**
  rather than re-derived, for the shadow-log write. Adopted.

**Codex finding rejected — one, and it would have weakened enforcement.** The
pass advised copying `openspec-guard.sh:330-337`'s source-guard shape
*including* a `command -v` check into the guard-side site. CLAUDE.md explicitly
forbids that: it would flip a currently-denying cell to allow. Rejected; the
reasoning and the resulting directional rule are recorded in D6. Noted here
because the advice was well-grounded in the repo's *general* #137 rule and
still wrong for this *specific* site — a reminder that the sparring partner's
output is evidence, not verdict.

**Codex position not adopted as framing.** It maintained approach B "was not
wrong" given the threat model, while separately concluding the 56–94%
precedent "kills" it and recommending warn-first. Those reconcile as: the
*mechanism* is right, the *day-one deny* is not. This design takes the
mechanism and defers the deny, which is what its own concrete recommendation
asked for.

**Unverified by the pass, flagged rather than assumed.** It could not confirm
the `Agent` `PostToolUse` payload shape or whether `tool_response` is
error-distinguishable for `Agent` as it is for `Skill`. It marked this
must-verify-before-build, and that is carried into the plan as a blocking
first step: if errored agents cannot be distinguished, a reviewer that crashed
on dispatch would credit `reviewer-ran`.

**Author's own reversal**, recorded because the reasoning matters: the first
recommendation was a hard deny (approach B), and the user selected it. It was
withdrawn on finding (a) `implement-evidence-gate/proposal.md:7`'s 56–94%
false-block precedent for unmeasured denies, and (b) 8 live branch ledgers that
a hard requirement would have blocked immediately. The user was re-consulted
and selected warn-first.

## Sequencing

1. **Defect 2 alone.** A text fix across five sites; small, reviewable, no
   behavior change. Lands under `routing-governance` (it touches
   `config/` and `hooks/`) so it needs its own clean verification verdict, but
   nothing about it should wait on the harder questions.
2. **Defects 1 + 3 together.** Not separable: 3 without 1 cannot fire, because
   the authorization gap is what stops the dispatch it would observe; 1 without
   3 auto-dispatches with no evidence layer at all, which is strictly worse than
   today's state where nothing auto-dispatches.
3. **Deny-flip.** Its own change, gated on the pre-registration above.

Author's own reversal, recorded because the reasoning matters: the first
recommendation was a hard deny (approach B), and the user selected it. It was
withdrawn on finding (a) `implement-evidence-gate/proposal.md:7`'s 56–94%
false-block precedent for unmeasured denies, and (b) 8 live branch ledgers that
a hard requirement would have blocked immediately. The user was re-consulted
and selected warn-first.
