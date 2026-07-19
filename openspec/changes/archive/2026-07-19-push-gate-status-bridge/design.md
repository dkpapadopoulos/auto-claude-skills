# Design: push-gate STATUS-layer cross-location evidence bridge

## Capabilities Affected

- `skill-routing` — push-gate STATUS layer (REVIEW/VERIFY milestone
  resolution) in `hooks/openspec-guard.sh`, the branch-ledger lib, and the
  completion-hook writer.

## Out-of-Scope

- Cross-token scanning of sibling `.completed` / invocation-evidence files.
  Those artifacts carry no repo/branch/SHA binding, so a cross-token read
  would accept another session's review of a different repo or branch —
  over-acceptance with no forgery-resistant binding. Only the SAME resolved
  token's invocation evidence is consulted.
- Recording milestones under all worktree branches at completion time
  (considered per issue #131 direction 2). Rejected: it would credit MY
  review to every branch currently checked out in any worktree of the repo,
  including unrelated concurrent-session branches.
- The VERDICT layer (already bridged, PRs #97/#123) and routing-governance
  semantics — untouched.
- The #127 stale-in-process live-deny (separate defect, capture already
  shipped in PR #128).

## Decisions

### D1 — completion hook: ledger write becomes state-independent

`_record_gating_milestone` (and its `case "${_BARE}"` dispatch, including the
review-embedding proxy skills) moves above the
`[ -f "${_STATE}" ] || exit 0` gate, directly after the invocation-evidence
write. Rationale mirrors the invocation record's own earlier move: roughly a
third of sessions have no composition state under their resolved token at
Skill-return time (scattering, pre-chain ad-hoc invocations), and the ledger
is the documented cross-session carrier — it must be written whenever a
gating Skill actually returns. The per-chain-step ledger (codex #4) stays
below the gate: it is defined in terms of chain membership.

### D2 — bridge binding: branch-local SHA, not bare ancestor

`branch_ledger_bridge_has <milestone> <proj_root>` scans
`~/.claude/.skill-branch-ledger-*/<milestone>` (excluding the own key's dir)
and accepts iff the recorded SHA is:

- exactly HEAD, or
- an ancestor of HEAD that is NOT reachable from the mainline merge-base
  (i.e. a commit on this branch's unmerged local segment).

Bare ancestor-of-HEAD would over-accept: a milestone recorded on `main` at an
old commit is an ancestor of every feature branch. Requiring branch-locality
means the recording session had THIS branch's own commits checked out — the
same forgery-resistant posture as the verdict bridge's exact-HEAD rule,
relaxed only along first-party history. When no mainline base resolves, the
bridge degrades to exact-HEAD-only (deny-bias for the bridge; the primary
path is untouched). Because keys are opaque hashes, the scan does not need to
know which (repo, branch) a sibling dir was for — the SHA binding does all
the work, which also covers remote-URL-variant key splits for free.

Cost: the bridge runs only after the primary checks miss (the would-deny
path), and short-circuits per milestone file with `cut` + at most two
`merge-base --is-ancestor` forks.

### D3 — invocation-evidence as a session-local evidence leg

The gate's session-local fallback additionally consults
`~/.claude/.skill-invocation-evidence-<token>` (same resolved token only).
Trust argument: its ONLY writer is the completion hook on a successful Skill
return — the same bar as the branch-ledger, and stronger than `.completed`
(which the walker also writes). The review leg honors the same
review-embedding proxies as the ledger writer
(`subagent-driven-development`, `agent-team-execution`, `agent-team-review`)
— PAIRED with the completion hook's case list. Scope widening is bounded:
"this session really ran the gating Skill" replaces "this session's active
chain has it completed" — the same trust class as the existing `.completed`
fallback, without its reset fragility.

Acknowledged divergence (review finding): this artifact carries no
repo/branch/SHA binding — the same limitation the Out-of-Scope section cites
against cross-token scans — and, unlike `.completed`, it never resets within
a session, so a session that ran review/verify for feature A satisfies the
gate for a later feature B push in the same session. This is accepted
deliberately: the PR #130 repro is only rescuable by unbound session-local
evidence (the recording cwd's SHA is unrelated to the push branch there), a
type guard rejects non-array files, and acceptance is always advisory-noted
(D4), never silent. SHA-binding the record (soft, preference-order) is filed
as issue #133.

### D4 — advisory on every non-primary acceptance

When a milestone is satisfied via the bridge OR the invocation-evidence leg
(not the primary key/`.completed`), the guard appends a `_STALE_MSG`
advisory naming the milestone — the bridge's note includes the recorded SHA
(parity with the primary path's staleness note) — so non-primary evidence is
surfaced to the session rather than silently consumed. No new JSON emission
path (the guard's one-object-per-run contract holds).

## Acceptance Scenarios

Provenance: issue #131 (fix directions), PR #130 live repro, memory
`push-gate-status-layer-no-cross-token-bridge`.

1. **Ledger write without composition state** — Given no
   `.skill-composition-state-<token>` exists for the resolved token, when the
   completion hook processes a successful `requesting-code-review` return,
   then the branch-ledger records the milestone for the cwd (repo, branch).
2. **Invocation-evidence rescue (the repro)** — Given empty branch-ledger and
   `.completed` for the push branch/token but
   `.skill-invocation-evidence-<token>` listing both gating skills, when the
   guard evaluates `git push`, then it does not deny.
3. **Bridge accept (branch-local SHA)** — Given both milestones exist only
   under a foreign ledger key with recorded SHA equal to a branch-local
   commit (or HEAD) of the push branch, when the guard evaluates `git push`,
   then it does not deny and emits a cross-location advisory.
4. **No over-acceptance (mainline SHA)** — Given a foreign-key milestone
   recorded at a mainline-base commit or an unrelated SHA, when the guard
   evaluates `git push`, then the fail-closed deny stands.
5. **No over-acceptance (foreign session, unrelated skills)** — Given
   invocation evidence containing only non-gating skills, when the guard
   evaluates `git push`, then the fail-closed deny stands.

## Implementation Notes (synced at ship time)

All five acceptance scenarios implemented as designed
(`tests/test-push-gate-status-bridge.sh`, 22 assertions). Review-driven
refinements beyond the upfront design:

- D2: `@{upstream}` moved to LAST in the mainline-base ref list — for a
  feature branch it is normally `origin/<itself>` (`git push -u`), and
  consulting it before mainline refs set the base to the branch's own pushed
  tip, excluding legitimately branch-local commits (reviewer-reproduced
  false-block; pinned by U7). The bridge also prints the matched SHA so the
  guard's advisory can name it.
- D3: acknowledged-divergence paragraph added (the invocation leg is
  session-scoped, not branch-bound; never resets within a session); jq
  `type=="array"` guard added (string `index()` is substring search);
  SHA-binding follow-up filed as issue #133.
- D4: widened to cover invocation-leg acceptances too — every non-primary
  acceptance is advisory-noted.
