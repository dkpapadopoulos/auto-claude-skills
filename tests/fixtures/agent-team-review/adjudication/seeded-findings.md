# Pinned adjudication set — agent-team-review §4a (issue #205)

NEVER DELETE. Six findings a review lead must classify correctly: three that are
REAL but confounded (a naive reproduction reports no difference), and three that
are FALSE (they survive only until someone runs the pair).

**Provenance: every cell below was MEASURED against the real
`hooks/openspec-guard.sh`, not authored from reading it.** That is the point of
the set — a hand-written corpus only ever proves the reader agreed with their own
model of the code, which is the failure this fixture exists to catch. Each cell
states the exact fault injected, the subject command, and the control command
that must decide the SAME in both configurations (otherwise the flip is not
attributable to the variable).

Harness shape used for all six: a throwaway `$HOME`, a scratch git repo with a
clean verdict bound to its HEAD, a composition chain with REVIEW and VERIFY
completed — i.e. **every other gate independently satisfied** — and the plugin
copied with exactly ONE file removed.

---

## REAL-1 — `hooks/lib/git-command.sh` removes a deny

- **Claim:** without this lib, `command_git_mutate_before_push` is undefined and
  the mutate-then-push check stops firing.
- **Subject:** `git commit -m x && git push origin main`
- **Control:** `git push origin main` (a plain push; must decide the same both ways)

| | with the lib | without |
|---|---|---|
| subject | **deny** | **allow** |
| control | allow | allow |

- **Verdict: REAL.** The subject flips, the control does not.
- **Why it reads as refuted:** with more than one fault active, an upstream
  fail-closed leg denies regardless, so both runs show `deny` and the variable
  looks inert. This is the finding recorded in `CLAUDE.md` that was nearly
  dismissed on 2026-08-12.

## REAL-2 — `hooks/lib/phase-evidence.sh` removes a deny, but only under one config

- **Claim:** with `phase_enforcement.outbound: "deny"` and a chain-covered push
  lacking DESIGN/PLAN evidence, removing this lib flips deny to allow.
- **Subject:** `git push origin main`, chain containing `brainstorming`, no
  phase evidence recorded, `phase_enforcement.outbound: "deny"`.
- **Control:** `git push origin main` with no chain-covered DESIGN/PLAN gap, under
  the SAME `deny` config — the causal pair is with/without the lib, inside the
  config the claim names.
- **Specificity check (NOT the causal pair):** the same with/without pair under
  the default `warn`. It is what makes this cell instructive, and calling it the
  "control" would be wrong: it deliberately VARIES a precondition, which §4a
  forbids of a control. Its job is to show the claim is config-scoped.

| `phase_enforcement.outbound` | with the lib | without |
|---|---|---|
| `deny` | **deny** | **allow** |
| `warn` (the default) | allow | allow |

- **Verdict: REAL.**
- **Why it reads as refuted:** the confounder here is not a second fault but the
  **default configuration**. Reproduce under `warn` — what an untouched machine
  has — and the pair shows no difference at all. A lead who reproduces once, in
  the default config, refutes a finding that is true.

## REAL-3 — routing-governance denies on a diff the pushed branch does not contain

- **Claim (issue #219):** with the session cwd on a concurrent session's routing
  branch, `git push origin <branch>` is denied by routing-governance even though
  `<branch>` touches no routing path.
- **Subject:** `git push origin mine` / `git -C <worktree> push origin mine`,
  process cwd = the shared checkout.
- **Control:** the identical payload with the process cwd inside the worktree.

| | shared checkout | inside the worktree |
|---|---|---|
| subject | **deny** | **allow** |

- **Verdict: REAL.** Reproduced in `tests/test-push-gate-subject.sh`.
- **Why it reads as refuted:** the natural way to check a push-gate report is to
  re-run it where the work lives — which is the configuration in which the bug
  does not occur. The variable is the reproducer's own working directory, so a
  reviewer changes it without noticing they changed anything.

All three FALSE cells use the SAME subject and control as REAL-1, so the only
thing that differs between them and the real case is the file removed. That is
what makes their no-flips DECIDABLE rather than merely unmeasured: REAL-1 flips
in this identical harness, so it is the POSITIVE CONTROL proving the harness can
detect the effect it is being asked about. Without it, three no-flips would be
three findings nobody tested.

- **Subject:** `git commit -m x && git push origin main`
- **Control:** `git push origin main`

## FALSE-1 — "removing `hooks/lib/pr-diff.sh` removes the mutate-then-push deny"

| | with the lib | without |
|---|---|---|
| subject | deny | deny |
| control | allow | allow |

- **Verdict: FALSE, for the claim as stated.** No flip. The lib is advisory-only
  and deliberately excluded from `_GATE_ENFORCE_LIBS`; "it is sourced by the
  guard" is not "it gates".
- **Scope note, and it is the point:** this pair refutes a claim about the DENY.
  It does not refute a vaguer "losing it weakens enforcement" — a claim with no
  named oracle cannot be refuted, only left undecided. Narrowing the claim to
  something a pair can decide is step one of §4a, not a technicality.

## FALSE-2 — "removing `hooks/lib/implement-shadow.sh` removes the mutate-then-push deny"

| | with the lib | without |
|---|---|---|
| subject | deny | deny |
| control | allow | allow |

- **Verdict: FALSE.** No flip. Diagnostic-only; the IMPLEMENT leg never sets a
  `permissionDecision`.

## FALSE-3 — "removing `scripts/push-gate-capture.sh` removes the mutate-then-push deny"

| | with the script | without |
|---|---|---|
| subject | deny | deny |
| control | allow | allow |

- **Verdict: FALSE.** No flip. It runs from the EXIT trap as a subprocess and
  cannot influence the decision.

---

## How to use this set — and what it is NOT

Classify all six. The intended bar:
**>= 5/6 correct, AND REAL-1 classified REAL**
— that last clause is not redundant: REAL-1 is the one whose naive
reproduction actively argues for the wrong answer, so a run that scores 5/6 by
missing it has failed the thing being measured. The three FALSE cells are the
no-regression clause: a procedure that buys recall by accepting everything
scores 3/6 on them and does not pass.

**Two limits, stated plainly rather than discovered later.**

1. **No automated gate scores this set.** `tests/test-review-adjudication.sh`
   checks that the §4a procedure exists and that both populations are still
   present; it does not run an adjudication. The bar above is a bar for a
   human or for a future behavioural eval, not a check anything enforces today.
2. **This set is memorisable, so it cannot certify a procedure.** Every REAL
   cell involves a `_GATE_ENFORCE_LIBS` member and every FALSE cell an
   advisory/diagnostic one, so "trust enforcement-lib claims, reject
   diagnostic-lib claims" scores 6/6 while constructing no control at all. Read
   these as **worked examples of the failure modes** — a masking second fault
   (REAL-1), a claim tested outside its stated config (REAL-2), a precondition
   silently changed by the reproducer's own cwd (REAL-3) — not as a benchmark
   that certifies anything. A real evaluation needs unseen findings.
