# Design: supply the evidence the push gate demands

## Architecture

Three defects, three independent fixes. None touches a deny predicate.

### 1. Bypass telemetry (`hooks/openspec-guard.sh`)

The capture EXIT trap is armed at `:552`, after `_PUSHGATE_SKIP` is resolved at
`:512` and after `_DECISION="allow"` at `:527`. A bypassed push therefore already
produces a record; it simply claims to be an allow. The fix inserts one assignment
between `:527` and the trap:

    [ "${_PUSHGATE_SKIP}" = "true" ] && _DECISION="bypass:env"

Nothing else moves. The bypass keeps working exactly as before — it is not gated,
delayed, or reported anywhere outside the local diagnostic log.

**Ceiling, to be stated in the PR and not oversold.** This captures only the
`ACSM_SKIP_PUSH_GATE=1` path. A human pushing from their own terminal never
invokes the hook, so no record is possible by construction — and that is plausibly
how the 7 sampled PRs shipped. This buys a clean *denominator*, not compliance
visibility.

### 2. Verdict supply (`config/default-triggers.json`, `config/fallback-registry.json`)

Add `project-verification` as the first step of the SHIP `sequence`. Sequence
entries render to the model through one existing jq path in
`hooks/skill-activation-hook.sh`; this is a data change with no code path of its own.

It goes first in the sequence, before `openspec-ship`, because `openspec/` commits
do not touch `skills/|config/|hooks/`, so the existing ancestor-acceptance rule
(`verdict_routing_delta`) keeps a verdict valid across the rest of SHIP.

The step's `purpose` text must carry two warnings, because both are load-bearing
and neither is discoverable from the step name:
- the suite is **15m43s**, so it will be backgrounded; and
- per issue #181, a HEAD move mid-run records `gate-run-straddled-commit` and
  covers **no** commit.

### 3. Branch protection

`gh api repos/:owner/:repo/branches/main/protection` returns 404 — `main` is
unprotected. This is the only currently-realized hole found in the investigation,
and it is closed by a settings toggle rather than by any change to the guard.

Done Gates is required (its recent history is clean). The `review` check stays
**optional**: its one recent failure was an empty `ANTHROPIC_API_KEY` killing the
action's entrypoint — an infra false-block, not a caught defect.

## Evidence

Measured this session unless marked otherwise.

| Fact | Value | Verified by |
|---|---|---|
| Gate invocations / denies | 210 / 97 | direct |
| Deny replay agreement | 97 / 97 `deny` | direct |
| Deny split | review 38, verify 18, routing 16, failclosed 15, mutate 10 | direct |
| `chain-review` evidence state | 38/38 "NO RECORD for this branch" | direct |
| `routing-governance` verdict state | 14/16 clean; 12 not covering HEAD | direct |
| `gate_status_mirror` populated | 97/97 denies, **0/113 allows** | direct |
| Session conversion | 16/32 (~50%) — **contaminated, see below** | direct |
| Reviews on 7 bypassed PRs | **0 on every one**; CI green 5, mixed 2 | direct |
| Collaborators | 1 (`dkpapadopoulos`) | direct |
| Workflows running `run-tests.sh` | 0 (comments only) | direct |
| `main` branch protection | absent (404) | direct |
| `project-verification` in compositions | **0** | direct |
| Suite runtime | 943s (15m43s), 129 files green | pragmatist |
| Guard growth vs deny rate | 302→900→1688 LOC / 60d; 43%→56% flat | pragmatist |
| Ledger credit without observed dispatch | 15 of 22 | architect (self-flagged upper bound) |
| PR #236 `review` check failure cause | empty `ANTHROPIC_API_KEY` | critic |

Three claims were asserted during the investigation and then **refuted by
measurement** — recorded here so they are not revived:

- "0% in-band conversion" — an artifact of grouping allows by a field only denies
  carry. Real figure ~50%, itself contaminated by defect 2.
- "ACS and Superpowers talk past each other" — false; the ledger bridge works.
- "Ship intents cannot route to REVIEW" — false; 4 of 5 phrasings do route.

## Decisions & Trade-offs

**Item 1 ships alone.** The pragmatist proposed bundling it with a demotion of the
VERIFY chain-gate, then rated that demotion's magnitude "medium until (a)
de-contaminates the allow count." Bundling would rest a governance reduction on a
number known to be wrong. It also runs against the measured base rate for editing
this file: #219 (wrong subject, 3 live false denies), #229 (deletion false-block
followed by three successive certify-bypasses, each found only after the previous
fix shipped), #192/#137 (silent allow), #198 (silent fall-open), #213 (jq-absent
silent no-op) — roughly one new silent failure per iteration.

**No prose changes.** Four channels already fire at the REVIEW step: the skill
name, a red-flag list, a standing "dispatch without asking" pre-authorization, and
`[CURRENT] Step 4` in the chain. The deny text at `:950` already names the exact
remedy. A `precondition` string would be a fifth channel where four measurably
fail. Codex, the architect, and the pragmatist independently reached this.

**The demote date is a commitment, not a code change.** On **2026-10-07** the gate
goes advisory unless a named, attributable defect has been prevented. Default-demote,
so inaction produces demotion rather than drift. This exists because the critic
argued against its own recommendation: "do nothing this week is the most common way
a known-bad control survives indefinitely, and I am supplying the rationalisation."
The project has pre-registered a horizon, missed it 11x, and re-registered; the
shadow corpus still reads `adjudicated 0`. Without a default, "wait 30 days" is that
pattern again.

## Dissenting views

**Architect** — the real lever is the *acceptance predicate*: the REVIEW gate accepts
a bare `Skill()` return, which `PostToolUse ^Skill$` fires before any reviewer can
exist. Swapping acceptance to `reviewer-ran` (observed dispatch) or a branch-bound
review verdict would convert hollow compliance into real reviews or honest denies.
Deferred, not rejected: the architect conceded it *lowers* the allow rate, and in a
one-collaborator repo the resulting artifact is still self-graded. It should ride the
existing #197 shadow corpus with a baseline recomputed over post-hook keys.

**Critic** — the endpoint should be advisory-everywhere except `mutate-then-push`
(the only leg decidable from command text alone, with no evidence lookup, no
staleness dimension, and no self-satisfaction path). Not adopted now because
demotion is a one-way door and the only evidence for it is absence-of-evidence: no
revert exists for any of the 7 bypassed merges, in a repo with no defect-attribution
process. The 2026-10-07 default answers this directly.

**Critic, on item 1** — instrumenting the bypass is surveillance of a channel
`openspec-guard.sh:502-511` explicitly reserves for the human. Partially accepted:
the record already exists and merely lies, so correcting it is a data-integrity fix
rather than new tracking, and the terminal-push path stays unrecordable by
construction. The objection is why item 1 stays a relabel and acquires no new
collection, no new file, and no agent-readable corpus.

**Pragmatist** — ship the bypass relabel and the VERIFY demotion as one PR.
Sequencing rejected above; the diagnosis is adopted wholesale.

## Out of scope

- Any change to a deny predicate, deny site, or evidence read.
- Demoting the VERIFY chain-gate or `routing-governance`.
- The architect's acceptance-predicate swap.
- `record-review-verdict.sh --from-github` adoption — correct, but it imports an
  empty set today (0 reviews exist).
- Merging the staircase deny messages into one.
- A macOS CI job running the suite. Every workflow is `ubuntu-latest` (bash 5),
  which cannot reproduce the Bash 3.2 class this repo is built around — so CI is
  not yet a substitute for local VERIFY here, and "CI covers VERIFY" must not be
  asserted until it does.
- Any new skill, hook, shadow corpus, or `predicate_version` bump.
