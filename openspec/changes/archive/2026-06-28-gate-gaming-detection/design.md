# Design — Gate-Gaming Detection

## Architecture

Three coordinated edits on the existing REVIEW→SHIP verification trust path. No new hook, no new
capability, no trifecta surface.

### 1. Deterministic gate-gaming check (`project-verification`, Step 3, before PASS)

A bash check over the working-tree diff (the change being verified), run in-skill alongside the
existing gate execution:

```
# removed assertions (added side never re-adds them) + newly-added skip/disable markers
git diff <base>...HEAD -- <test globs> | grep -E '^\-.*\b(assert|expect|assertEquals|assertThat|require)\b'
git diff <base>...HEAD -- <test globs> | grep -E '^\+.*(@pytest\.mark\.skip|xfail|@Disabled|\.skip\(|xit\(|@Ignore|t\.Skip)'
```

- Any hit → `gate_gaming_status: suspect`; otherwise `clean`.
- `suspect` downgrades the emitted verdict to **SUSPECT** (a reported state, not a PASS), and the
  human is shown the offending lines. It does **not** hard-block — `project-verification` remains
  advisory by design.
- Language coverage is best-effort (py/js/ts/java/go markers above); unmatched ecosystems degrade
  to `clean` rather than failing the skill.

### 2. Tri-state evidence (`project-verification`, evidence JSON)

Add `could_not_verify[]` to the evidence schema (alongside `passed[]`/`failed[]`). A gate command
whose execution errored (non-zero from the *runner*, missing binary, env break — distinct from a
test *failure*) lands here. The verdict vocabulary becomes:

- **verified** — ran, exit 0, `gate_gaming_status: clean`
- **failed** — ran, non-zero test outcome
- **could-not-verify** — could not execute (missing binary, runner error, env break)

Note: `gate_gaming_status: suspect` surfaces as a distinct reported **SUSPECT** verdict (per the spec and deploy-gate SKILL.md), not as `could-not-verify` — `could-not-verify` is reserved for gates that could not execute at all, while SUSPECT means the gate ran but the diff looks gamed.

### 3. deploy-gate consumption contract (`deploy-gate`, local-verification-of-record)

Tighten `deploy-gate:44`: accept the local evidence file as verification-of-record only when
`failed[]` **and** `could_not_verify[]` are empty **and** `gate_gaming_status` ≠ `suspect`. This
closes the "empty failed[] = accepted" hole for both the gamed-green and could-not-run cases.

### 4. drift-check reference (`implementation-drift-check`, Step 3)

One sentence: when reviewing for drift, surface any gate-gaming finding from
`project-verification` (deleted assertions, added skips, loosened fixtures, stubbed subject) as a
blocking drift signal. Consumes the finding; does not re-grep.

## Trade-offs

- **Deterministic > prose.** A grep catches blatant and accidental weakening reliably and is
  testable as bash. It does **not** stop a *determined* adversary (rename "cleanup", move
  assertions into vacuous helpers, replace with tautologies, stub where grep can't see). We accept
  that ceiling explicitly — the goal is closing the accidental/blatant path and removing the
  false-confidence framing, not claiming reward-hacking is "solved".
- **Advisory, not enforcing.** Respects the prior shipped decision that in-hook evidence is not a
  trust boundary. Real enforcement remains external CI.

## Dissenting views (from the debate)

- **Critic:** self-run gate-gaming detection is structurally weaker than an external evaluator and
  risks false confidence. → Mitigated by making it deterministic + keeping it advisory + honest
  validation (red fixture), and by NOT claiming it stops determined hacking.
- **Critic/Pragmatist:** #7 (tri-state) looked like decoration. → Refuted by verifying a real
  consumer (`deploy-gate:44` branches on empty `failed[]`); reframed from "status rename" to
  "make could-not-run explicit so absence ≠ pass".
- **Pragmatist:** keep items 1+2 as one mirrored idea, don't bloat. → Adopted: drift-check
  references rather than reimplements.

## Decisions & rejected alternatives

- **Rejected:** prose-only gate-gaming guard (theater — unvalidatable beyond planted blatant cases
  that lie at small-n).
- **Rejected:** hard-block on `suspect` (re-litigates the non-trust-boundary boundary).
- **Deferred with revival triggers:**
  - `batch-scripting` per-file postcondition — *revive if* a real batch run ships a file logged
    `OK` with wrong content. (Retry-classification killed outright — contradicts the skill's own
    anti-pattern.)
  - `agent-team-review` inter-lens disagreement section — *revive if* a postmortem shows two lenses
    contradicted on one finding and the wrong call won, or when a multi-agent synthesis eval
    harness exists.
  - `outcome-review` failure-cause split — cheap and real but LEARN-phase; *revive / fast-follow*
    as a one-column edit when closing the LEARN loop is prioritized.
  - `runtime-validation` imperative-remediation template — killed (Step 5 is already directive; the
    empirical claim is the least validatable item).

## Eval strategy

Deterministic feature → standard TDD plus the acceptance scenarios in
`specs/project-verification/spec.md`. The gate-gaming grep gets a **red-first** behavioral-eval
scenario (diff that deletes assertions while the suite exits 0 → expect `suspect` / non-PASS) and a
deterministic unit grep test. No probabilistic/LLM-judge subset needed — the check is bash, not
model behavior. No external numbers imported.

## Implementation Notes (synced at ship time)

- **Inline snippet → committed script (intentional divergence).** §1 above sketched the gate-gaming
  check as an inline `grep` snippet run in-skill. As built, the logic ships as a committed,
  unit-tested script `skills/project-verification/scripts/gate-gaming-check.sh` (reads a unified
  diff on stdin → prints `clean`/`suspect` + offending lines), and the SKILL.md *invokes* it via
  `${CLAUDE_PLUGIN_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh`. This is the
  honest-validation form the debate demanded: a script is deterministic, external to the model's
  incentive, and testable as bash (8 unit cases incl. regression guards), whereas an inline snippet
  the model retypes is neither.
- **Detector grep, as shipped:** removed-assertion detection pre-filters unified-diff header lines
  (`grep -vE '^(---|+++)([[:space:]]|$)'`) on **both** the removed and added-marker paths, then
  matches real deletions (`^-`) / additions (`^+`). This catches indented and non-indented
  assertion deletions and added skip/xfail/disabled markers, without false-positiving on a keyword
  inside a `---`/`+++` file path. Accepted ceiling (advisory check): broad `expect`/`require.`
  patterns are unscoped, and a `--`-prefixed *already-commented* assertion line is not flagged
  (inactive code, not gate-gaming).
- **deploy-gate** surfaces the specific rejection reason (which gates could not be verified, or that
  the gate looks gamed), not merely "hosted CI absent".
- Commits: `d9702bf` (script) · `9947b97` (project-verification wiring + tri-state) · `8e96dfa`
  (deploy-gate) · `90276a3` (drift-check) · `b15ff3b`/`4dc0be6`/`3fb3a8b` (review fixes).
