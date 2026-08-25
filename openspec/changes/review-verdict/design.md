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
- **A null result is a real result.** n short on the horizon date **is** the finding, not grounds to extend the window.

**Known risk, stated up front:** the IMPLEMENT corpus was pre-registered at 0.697 episodes/day and is measured at 0.22, putting its n=29 near 2026-12 rather than its 2026-09-08 horizon. This corpus will likely accrue slower still, because it only fires when STATUS is already satisfied. The horizon is therefore set by *rate observed at n=5*, not guessed now — and that deferral is itself pre-registered here so it cannot be presented later as a rescue.

`predicate_version` starts at 1. Bump it whenever the fire condition changes; never pool records across versions.
