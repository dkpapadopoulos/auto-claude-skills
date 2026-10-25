---
name: agent-team-review
description: Use when a code change touches 5+ files or modifies auth/secrets/permissions/hooks/CI paths and needs multi-lens parallel review (security, quality, spec, governance) before merge.
---

# Agent Team Review

## Overview

Parallel code review using agent teams. The lead spawns 2-4 reviewer teammates, each with a different review lens. Reviewers investigate independently, then the lead synthesizes findings into a unified review report.

**Prerequisite:** Implementation must be complete (all tasks marked done). Activates for larger implementations (5+ files changed, or any change touching sensitive paths — see Sizing Rule).

## Sizing Rule

| Condition | Action |
|-----------|--------|
| < 5 files changed | Use single-agent requesting-code-review |
| 5+ files changed | Spawn reviewer team |
| Change touches auth, secrets, permissions, hooks, or CI config | Spawn reviewer team regardless of file count (minimum: security-reviewer + adversarial-reviewer) |

## Reviewer Composition

| Teammate | Lens | Focus |
|----------|------|-------|
| `security-reviewer` | Security | Auth flows, input validation, secrets, OWASP risks |
| `quality-reviewer` | Code quality | Patterns, maintainability, test coverage, edge cases |
| `spec-reviewer` | Spec compliance | Does implementation match the design doc and plan? |
| `adversarial-reviewer` | Governance | HITL bypass, scope expansion, safety gate weakening, permission escalation |

## Communication Contract

All messages use plain text via SendMessage. No structured JSON.

### Reviewer → Lead: Individual Finding

```
FINDING: [blocking | warning | suggestion]
File: src/auth.ts:42
Category: security | quality | spec | governance
Confidence: high | medium | low
Evidence: observable failure path or concrete reproduction — what input/call triggers it and what breaks
Oracle: what observably differs when the claim holds — an exit code, an emitted field, a log line, a recorded artifact, a count (omit for a structural finding)
Issue: SQL injection via unsanitized input
Suggestion: Use parameterized queries
Autofix: exact old→new edit; suggestion severity only; omit unless all four eligibility conditions hold
```

**Evidence is mandatory.** A finding may be classified `blocking` only if its `Evidence` describes an **observable failure path** — a concrete input, call, or sequence that produces the failure. A theoretical or stylistic concern with no demonstrable failure path is at most a `warning` (or a `suggestion`). This is the cheapest false-positive control: a real defect can name how it breaks; a nit cannot.

**Exception — `security` and `governance` findings may be `blocking` on structural grounds** (per the adversarial-reviewer's criterion: a finding is blocking if it removes or weakens an existing safety constraint) even without a runnable proof-of-concept. Do not demote them for lacking an observable failure path.

**Confidence is advisory only.** The `Confidence` field is context for the user's judgment — it is **not** a filter or demotion input, and the synthesis step never gates on it. The evidence / observable-failure-path rule, not self-rated confidence, is the discriminator: self-rated confidence is exactly the self-preferential-bias signal this design avoids, so do not add confidence-weighted drop/demote rules.

**`Autofix:` marks mechanically certain trivia, additive to `Suggestion:` and never replacing it.** Eligible only when all four hold: the fix is a single exact text transformation stateable precisely; it is essentially certain to be correct and complete; it touches only code this diff introduced or changed; it has zero behavioural ambiguity. Only `suggestion`-severity findings may carry it — `blocking` and `warning` findings never carry the bypass and keep the full return-to-IMPLEMENT path, even when a reviewer attaches the line.

The lead's own report format follows §6.

## Protocol

### 1. Preparation

```
TeamCreate("code-review")

Gather context:
- Design doc from docs/plans/*-design.md
- Implementation plan from docs/plans/*-plan.md
- Acceptance spec from docs/plans/*-spec.md (if exists)
- Legacy fallback: docs/superpowers/specs/*-design.md
- Git diff: git diff {base_sha}...HEAD
- List of files changed
```

### 2. Spawn Reviewers

Each reviewer gets:
- The full diff
- The design doc
- Their specific review lens instructions
- The communication contract

**Claim-withheld dispatch:** reviewers receive the artifact and the contract only — diff, files changed, design doc, plan, acceptance spec. Never include the implementer's self-summary, claims of correctness, or completion notes in a reviewer prompt: handing a reviewer the implementer's conclusion biases it toward agreement.

**Before spawning, Read `references/reviewer-prompts.md`** and send each lens its prompt verbatim, filling only the `{…}` Context fields; a reviewer sees no other copy of its rules. With `org_hub=true`, follow that file's org-hub step first.

### 3. Parallel Review

Reviewers work independently using Read, Grep, and analysis tools. They do NOT modify the
shared working tree; a reviewer that must RUN something works in its own detached worktree.

**Do not flag — reviewer scope, two categories only.** These are *scope* rules for what a
reviewer raises, NOT a filter the lead applies afterwards. The lead never demotes a
delivered finding on these grounds — §4 step 3 and the `security`/`governance` exception
below it are unaffected.

| Do not raise | Why | Raise it anyway when |
|---|---|---|
| `pre-existing` — a defect on the merge base that appears in no changed hunk | The review is of this change; unchanged code was already shipped and reviewed | The diff changes its blast radius, or the change makes it newly reachable |
| `tool-owned` — lint, formatting, type errors, test failures, SAST results | `project-verification` and `security-scanner` are separate skills, so restating their output is duplication **by construction** | The gate did not run. Then the finding is *that the gate did not run*, not the individual violation |

The list stops at two entries deliberately. Broader provenance categories — notably
"speculative" — would demote exactly the structural `security` and `governance` findings
that §4 and the Evidence rule protect, which is the hole those rules exist to close. Do
not extend this table without re-reading both.

**PAIRED — this table is the LEAD's copy; the reviewer's copy ships in the spawn templates** (each lens's `## Scope` block). Read `references/scope-copies.md` before editing either.

**Trivial is not the same as droppable.** A finding small enough to fix in one line is
still reported; these two categories are about *ownership*, not size.

**Authorship guard.** Authored the change under review in this context? Follow `### Authorship guard (§3)` after §6: say so, call it convention-checking, keep each finding's earned severity, record `--self-authored`.

**Collect the reports — they do not arrive on their own.** A background reviewer in this
harness signals idle with no findings attached, because its final text is a return value,
not a message to the lead. Observed on one push-gate change: of four reviewers, three went
idle empty and produced full reports only when asked, and one errored out and produced
nothing.

| Reviewer state | What the lead does |
|----------------|--------------------|
| Report received via SendMessage | Count it. This is the only state that counts as delivered. |
| Idle, no findings attached | **Idle is not a report.** SendMessage the reviewer asking for the report, listing the exact questions you want answered. |
| Idle again after one nudge | Chase a quiet reviewer **at least twice** before writing it off — reviewers chased twice have delivered substantive findings that a single nudge would have lost. |
| Errored, timed out, or killed | **A timeout is not a pass.** Re-dispatch it and never count it toward coverage. |
| Still nothing after re-dispatch | Record the lens as uncovered and carry it into the verdict (below). Do not silently reduce the team. |

**Before re-dispatching anything, run `git status` and `git log`.** The first move on a quiet
agent is not re-dispatch — subagents here frequently finish the work and stall before
reporting, leaving completed changes sitting uncommitted in the tree. Re-dispatching without
looking duplicates work that is already done.

**Coverage is what was delivered, not what was spawned.** If any lens never delivered, the
review is not `clean` — record `--verdict could-not-review` (see "Record the Review Verdict")
and say which lens is missing. Silence and "we could not review" are different states.

**Reap the reviewers' worktrees before TeamDelete.** A reviewer that timed out or was killed
never ran its own `git worktree remove`, and `git worktree add` registers under the shared
repo's `.git/worktrees/` — which `git status --porcelain` cannot see, so a leak is invisible
to the main-tree cleanliness check. Run `git worktree list`, remove any left by this round,
then `git worktree prune`.

### 4. Lead Synthesis

After collecting the reports per §3 — including any lens recorded as uncovered:

1. Group findings by severity (blocking → warning → suggestion)
2. Deduplicate overlapping findings
3. **Severity floor.** Drop `quality`- and `spec`-category `suggestion`-severity findings that do not map to a capability named in the design doc, and demote any `quality`/`spec` `blocking` finding whose `Evidence` lacks an observable failure path to `warning`. **Never drop or demote `security` or `governance` findings on these bases** — those catch unplanned risks no design doc anticipated, and may rest on structural criteria (e.g. removing or weakening a safety constraint) rather than a runnable failure path. This curbs the bot-asymptote nit accretion (advisory findings that accumulate every round without ever being actionable). Defer `Autofix:`-carrying suggestions to step 4 — the floor decides them only if validation strips the routing.
4. **Autofix validation — the token never self-certifies.** This validation IS the finding's adjudication — a mechanical edit has no manipulable causal variable, so per §4a it is disposed on its own terms. In order:
   Its six steps follow §6 (`### Autofix validation, in order`); apply them to every `Autofix:` line.
5. Adjudicate per §4a every finding you are about to accept or reject at `blocking` or `warning` — a `suggestion` needs one only if you intend to action it
6. Present unified report to user

**Dropped findings stay visible.** Never silently discard a floored finding — the count and one-line reason for each is reported under "Dropped (below severity floor)" in the summary, so the user can audit the filter and the `doubt theater` signal (systematic non-actioning) remains detectable.

### 4a. Adjudicating one finding: isolate exactly one fault

The severity floor decides which findings are worth deciding. This step decides them, and it has one rule:

**Change exactly one thing, and build a pair that COULD disagree.**

Reproduce with the claimed cause present, and again with it removed, holding everything else fixed, and read the oracle the finding itself names. Three outcomes, and only the first two decide anything:

| pair | you may conclude |
|---|---|
| the runs **disagree** | the claim holds |
| the runs **agree**, and a comparable positive control disagrees in the same harness | the claim is false |
| the runs **agree**, with no positive control | nothing — you have not tested the claim |

Requiring the pair to *disagree* is the design constraint on the experiment, not the verdict: an experiment that could not have come out either way was never a test.

"One thing" means **one causal variable, with every other precondition held equal** — not one changed token. Reproducing an input-triggered failure legitimately changes the input *and* whatever setup that input requires; what must not vary is anything else that could produce the outcome on its own.

**Scope: this applies to findings that make an experimentally decidable causal claim** — "X causes Y", "removing X changes Y", "input I produces failure F". It does NOT apply to structural findings, and specifically **not** to `security`/`governance` findings blocking on the structural criterion the finding contract already allows (a change that removes or weakens an existing safety constraint). Those are decided by reading what the change removes, exactly as before; demanding a runnable pair for them would quietly repeal that exception. If a finding has no manipulable variable, it is not in scope here — say so and adjudicate it on its own terms.

**The oracle is whatever the finding predicts**, not necessarily allow/deny: an emitted field, an exit code, a log line, a recorded artifact, a count. Name the oracle before you run, or you will find one afterwards that agrees with you. The finding contract carries an `Oracle:` line for this; when a report omits it, derive one and **state it in your disposition** — an oracle chosen silently by the adjudicator is the same freedom the rule exists to remove.

The mechanism generalises: **an upstream fail-closed gate masks a downstream fall-open one.** Until every other gate is independently satisfied, the variable under test contributes nothing observable, so the "removed" run carries no information about it — and a test written from that run asserts nothing.

Both directions are in scope:

- **Before rejecting** a finding that "failed to reproduce": show the paired control. Absent it, you have not refuted the finding, you have only failed to trigger it — say that instead.
- **Before accepting** a finding: the same pairing. A finding accepted without a control that flips is a guess with a file:line attached, and the test it motivates will pass whether or not the code is fixed.

**A pair that does not flip is not, on its own, proof of falsity.** It has three candidate explanations and you must name which one you are asserting: the claim is false; the intervention was incomplete (you removed less than the claim describes); or the preconditions were not met (a masking gate, the wrong config, the wrong subject). The second and third are experiment failures, and reporting them as "refuted" is the original 2026-08-12 mistake wearing a control.

**So a non-flip decides "false" only once the other two are ruled out, and the way you rule them out is a POSITIVE CONTROL.** Run, in the same harness, a variable you already know does flip. If the harness demonstrably detects that one and not yours, "the claim is false" is the surviving explanation; if it detects neither, you have learned nothing about either.

**The control must be COMPARABLE, not merely known-good.** Same subject, same oracle, same preconditions — otherwise it proves the harness detects *something*, which is not the same as proving your intervention was complete or your preconditions were met. A positive control drawn from a different subject tells you the wiring works and nothing about your claim. This is what makes the seeded set in `tests/fixtures/agent-team-review/adjudication/` decidable at all: `REAL-1` flips under the identical subject, control command and preconditions that the three `FALSE` cells use, so it *is* their positive control — without it, three no-flips would be three unmeasured findings, not three refutations.

State the positive control alongside the verdict whenever you reject a finding. "It did not reproduce" and "it did not reproduce in a harness that provably reproduces something else" are different claims, and only the second is evidence.

Escalation when the pairing is not obtainable — a fault that needs credentials, hardware you do not have, or a genuinely probabilistic effect:

1. Say so explicitly, in the finding's disposition: `could-not-reproduce (single-fault control not obtainable: <why>)`.
2. Keep the finding at the severity it carries **after** the floor. Do not silently demote what you could not test.
3. Route it to the user as an open question, not as a resolved one, under "Open" in the summary.
4. A probabilistic effect is obtainable statistically: N runs each side with a stated rate difference is a valid pair. Reach for escalation only when even that is out of range.

**Isolation is mandatory and is not optional politeness.** Run every reproduction in a detached worktree, never in the shared working tree. Adjudication injects faults on purpose; doing that where a concurrent session or a running suite can see it corrupts other people's work and, on this repo's own push gate, measures a tree nobody is pushing. Never write to the shared working tree while adjudicating.

Before any reproduction, Read `references/adjudication-worktree.md` and run its commands: detached worktree at `{head_sha}`, uncommitted work carried with `git diff HEAD` (never `{base_sha}`), needed untracked files copied, worktree removed after.

**Record the pairing, not just the verdict.** Each finding adjudicated *by pairing* carries one line: what was changed, what the with-run decided, what the without-run decided, and — on a rejection — the positive control that proves the harness could have detected it. A structural finding decided by reading has no pair and records the constraint it removes instead; do not manufacture a pairing line for it. A verdict with no pairing recorded is indistinguishable from an unexamined one, which is exactly the doubt-theater signal §Red Flags is looking for. Conversely, an open `could-not-reproduce` finding is **not** a dismissal, so do not count it as one when judging the doubt-theater pattern in §Red Flags: that pattern is systematic NON-ACTIONING across rounds, and an item explicitly routed to the user as unresolved has been actioned — into the open column, where the user can see it.

### 5. Verdict Routing

| Verdict | Action |
|---------|--------|
| `blocking_issues` | TeamDelete → return to IMPLEMENT → fix issues → re-review |
| `suggestions_only` | TeamDelete → cross-model offer (§6, when applicable) → proceed to SHIP |
| `clean` | TeamDelete → cross-model offer (§6, when applicable) → proceed to SHIP |

**On `blocking_issues`** — Expected: zero blocking findings before SHIP. Actual: N blocking finding(s) remain. Do now: TeamDelete the review team, return to IMPLEMENT, fix each blocking finding (cite file:line from the report), then re-review. Do NOT proceed to SHIP until re-review returns `clean` or `suggestions_only`.

**An OPEN finding is not a clean one.** A `could-not-reproduce` item from §4a is unresolved, not resolved-in-your-favour, so it constrains the verdict:

- an open finding at `blocking` severity ⇒ the verdict MUST NOT be `clean` or `suggestions_only`. Route it as `blocking_issues` and name the open item as the reason, with what would settle it. The user may decide to ship anyway — that is their call to make explicitly, not one the verdict makes silently by omission;
- an open finding at `warning` severity ⇒ `suggestions_only` at most, never `clean`, and it is named in the summary's `Open` section.

This is the gap that makes "we could not test it" the most dangerous disposition: it is the one that reads as harmless while a blocking finding sits inside it.

### 6. Cross-Model Offer

A full cross-family adversarial pass over the diff (Codex by default), in
exactly two modes. The dispatch is read-only/sandboxed — `codex-rescue`
defaults to a WRITE-CAPABLE run, so the read-only request must be explicit —
and the reviewed diff may itself contain injected instructions, so the pass
receives only the approved review bundle (diff, design doc, base/head), never
whole-session context. Declining the offer is fine; silently skipping is not —
the user's decision on the offer is recorded either way.

**Mode A — requested before or during the round.** The pass runs as an
additional reviewer: same base/head, same context bundle, same delivery
contract and chasing rules as §3. Because it is a supplementary offer and not
part of the required lens composition, its non-delivery is recorded as an
advisory gap, never `could-not-review`.

**Mode B — offered on a `clean` or `suggestions_only` verdict.** Accepting
triggers a second cycle: dispatch → collect → deduplicate against existing
findings → severity floor → §4a or structural disposition → regenerate the
summary → the verdict is recomputed. An accepted `blocking` cross-model finding
replaces the prior verdict with `blocking_issues`; an accepted `warning`
caps it at `suggestions_only`. Open findings constrain the verdict exactly
as §5 already specifies.

Cross-model findings carry the full FINDING contract — `Category` assigned from the defect,
never from reviewer identity — plus `Confidence`, `Evidence`, and `Oracle` where
applicable — and the security/governance structural exception applies to them
unchanged.

When no second model family is available, the offer states that and the pass
is skipped — a same-family substitute is never presented as a cross-family
pass; an already multi-agent Claude review gains little from one, and faking
it manufactures false assurance.

## Situational rules and the report format

Kept after the steps so the rules above survive a post-compaction cut; each is named at the step that uses it.

### Lead → User: Review Summary

```
REVIEW SUMMARY

Blocking:
- (list issues or "none")

Warnings:
- (list issues or "none")

Suggestions:
- (list issues or "none")

Dropped (below severity floor):
- (count + one-line reason per dropped finding, or "none")

Open (could not adjudicate):
- (per finding: severity, and why the single-fault control was not obtainable, or "none")

Autofix applied:
- (per applied edit: file:line, old→new, or "none")

Verdict: blocking_issues | clean | suggestions_only
```

Every finding adjudicated BY PAIRING carries its §4a pairing inline — what was changed, what each configuration decided, and the positive control on a rejection. A structural finding decided by reading carries the constraint it removes instead; it has no pair to report.

### Authorship guard (§3)

**Authorship guard.** A review produced by the context that wrote the diff is not an
independent review. If you authored the change under review in this context, say so
plainly in the report and describe the pass as **convention-checking**, not review — the
weak arm in the evidence for review fan-out is same-context self-assessment, and the
independence claim is what fails, not the findings. Withdraw the claim; keep every
finding at the severity its evidence earns.

Say it explicitly, and record it: `record-review-verdict.sh --self-authored` writes
`independence: "self-authored"` onto the verdict artifact. Prose alone reaches only whoever
reads the report — the push gate's STATUS layer credits a Skill return, not a review that
happened, so without the flag a self-review reaches SHIP with a green gate and no durable
signal that the independence was never there. The flag is provenance, not a gate: it denies
nothing, and it never downgrades a finding. Context isolation is still the mechanism doing
the work; the declaration only records when it was absent.

### Autofix validation, in order (§4 step 4)

   1. The lead validates every `Autofix:` line independently against the four eligibility conditions, checks the `old` text is present, unique, and unstale against the tree, and deduplicates overlapping or conflicting edits.
   2. A validated line routes past the severity floor into the autofix batch; a line that fails validation loses the routing — the finding reverts to a normal suggestion under normal floor rules, and the failed validation is reported.
   3. The batch is presented only after §6 resolves — an accepted Mode B pass reviews the pre-application tree, and validated `Autofix:` lines from cross-model findings join the same batch.
   4. After the verdict, present the batch for per-item approval ("apply all except …" supported), listing every old→new edit.
   5. On approval, apply, then assert the applied diff is byte-identical to the approved batch — on mismatch, revert and return to IMPLEMENT.
   6. Application happens before verification and verdict recording, so the recorded verdict describes the final tree state.

## Adversarial review checklist

The REVIEW-phase hint `ADVERSARIAL REVIEW` points here. In addition to standard
code review, evaluate these governance checks against the change:

1. Does any change weaken or remove an existing safety gate, HITL requirement,
   or approval step?
2. Does any change expand autonomous action scope (new outbound actions, broader
   permissions, reduced human oversight)?
3. Does any change modify hook behaviour, permission settings, or composition
   routing in ways that reduce guardrails?
4. Does any change add `dangerouslyDisableSandbox`, `--no-verify`, `force`, or an
   equivalent bypass pattern?
5. Does any change touch files in `hooks/` or `config/` that govern skill routing
   or phase enforcement?
6. If any answer is YES: flag it as a blocking governance finding with specific
   file:line evidence.
7. Does the resulting change have two or more lethal-trifecta fields
   (`private_data`, `untrusted_input`, `outbound_action`), or add a missing leg
   to an existing two-field flow? If so, invoke
   `Skill(auto-claude-skills:agent-safety-review)` and treat unmitigated,
   unacknowledged lethal-trifecta risk as a blocking governance finding. The
   user may still explicitly accept the risk.

## Red Flags

- **Silent drop:** a reviewer went idle or errored and the round was reported as complete without its lens. Coverage counts reports delivered, not agents spawned — an undelivered lens is an uncovered lens. Chase it per Protocol §3; if it still does not deliver, name the gap and record `could-not-review` rather than approving around it.
- **Doubt theater:** across 2 or more review rounds, reviewers surfaced substantive findings and zero were classified actionable. That is doubt theater — you are validating, not reviewing. Stop and surface the dismissal pattern to the user instead of proceeding to SHIP.

## Verification

Before emitting an APPROVE verdict, confirm:

- Every spawned reviewer returned a finding set this session -- no reviewer silently dropped.
  This is an outcome, and Protocol §3 is the mechanism that reaches it: an idle or errored
  reviewer was chased and re-dispatched, not counted. A lens that never delivered means
  `could-not-review`, not APPROVE.
- Each actionable finding was resolved or explicitly accepted with rationale -- not waved through.
- The verdict cites evidence / confidence / severity per the finding contract, not a bare "looks good".
- The doubt-theater pattern is not present (see Red Flags above) — if it is, surface it instead of approving.

## Record the Review Verdict

After adjudication, record the outcome so the push gate can tell that a review
actually happened. This is the point of the artifact: the REVIEW *status* leg
credits a `Skill()` return, which fires before any reviewer is dispatched, so a
credited milestone is not evidence a review ran (#197).

The verdict is recorded once, after the offer is resolved — the §6 Cross-Model
Offer accepted and cycled, declined, or unavailable — and after any §4-batch
autofixes are applied, so the artifact describes the final tree state and its
counts include cross-model findings.

Run this in ONE Bash call. `record-review-verdict.sh` resolves the session
token internally (issue #157) — you author only the verdict fields, no token
line to retype:

```bash
PR='<PLUGIN_ROOT>'
bash "$PR/scripts/record-review-verdict.sh"   --provider agent-team-review   --verdict clean   --base "$(git merge-base HEAD origin/main)" --head "$(git rev-parse HEAD)"   --findings <total> --unresolved-blocking <count>
```

Do not pass `--dispatch-attempted`/`--dispatch-succeeded` here: when a
reviewer subagent actually ran, the script observes it from the branch ledger
regardless of these flags, so passing them adds nothing; when one did not
run, passing them would falsely assert a `true` dispatch that never happened.

DO pass `--self-authored` when this context authored the diff it just reviewed — the
Authorship guard above. It is the one provenance flag the script cannot observe for
itself: an observed dispatch proves a subagent ran, never that it reviewed *this* diff
in a context that did not write it. Because it is an admission against interest it
outranks an observation, so the artifact records `self-authored` even where a dispatch
was witnessed.

Do not resolve the token by reading `~/.claude/.skill-session-token`
directly. It is a shared last-writer-wins singleton that under concurrent sessions
names a DIFFERENT conversation, so the verdict would land where the payload-first
guard never looks (issue #157).

Rules:

- `--verdict clean` ONLY when every actionable finding was resolved or explicitly
  accepted. If any blocking finding is open, use `--verdict findings-open` and pass
  the real `--unresolved-blocking` count.
- If reviewers did not return — the doubt-theater / silent-drop cases in Red Flags —
  use `--verdict could-not-review`. Recording that is more useful than recording
  nothing: silence and "we could not review" are different states, and only one of
  them tells the next reader what happened.
- Never pass `--verdict clean` without `--base`/`--head`. The writer will refuse and
  downgrade it anyway, because a clean verdict with no reviewed subject is a claim
  about nothing.

## Reference files

Read each when its condition holds; never send a reviewer prompt or run an adjudication worktree from memory.

| File | Read it |
|---|---|
| `references/reviewer-prompts.md` | Before spawning reviewers (§2): the four lens prompts, sent verbatim, and the org-hub lens step when `org_hub=true`. |
| `references/adjudication-worktree.md` | Before any §4a reproduction: the detached-worktree commands. |
| `references/adjudication-example.md` | Before calling a finding refuted because its §4a pair did not flip: the 2026-08-12 worked failure. |
| `references/scope-copies.md` | Before editing the do-not-flag table or any lens's `## Scope` block. |
| `references/integration.md` | When choosing the fallback or a neighbouring skill. |
