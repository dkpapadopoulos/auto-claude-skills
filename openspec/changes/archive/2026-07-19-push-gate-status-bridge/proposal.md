# Push-gate STATUS-layer cross-location evidence bridge (issue #131)

## Why

The push gate has two evidence layers with asymmetric handling of
concurrent-session token divergence. The VERDICT layer got a cross-token
bridge in PR #97 (`verdict_resolve_token`, hardened in #123): a clean verdict
bound to the exact HEAD is found under any sibling token. The STATUS layer
(REVIEW + VERIFY milestones) has no equivalent — it reads the session-scoped
`.completed` and one per-(repo+branch) branch-ledger key, so under
concurrent-session token scattering plus a worktree/cwd split the fail-closed
gate cannot find `requesting-code-review` / `verification-before-completion`
and denies genuinely-complete work.

Live repro (2026-07-18/19, PR #130 ship): milestones recorded while the
session cwd sat on the main checkout; push evaluated the worktree branch;
`.completed` empty under the push's own token; deny. The on-disk replay
reproduced the deny (a real evidence-location miss, not the #127 stale-hook
drift). Resolved via the sanctioned human `!` push; the mechanism is
documented in issue #131.

Three concrete gaps in current code:

1. **`hooks/skill-completion-hook.sh`** — the durable gating-milestone ledger
   write sits *below* the composition-state existence gate, so a session
   whose composition state is missing under its resolved token (exactly what
   token scattering causes) never records review/verify to the branch-ledger
   at all, despite real Skill returns.
2. **`hooks/openspec-guard.sh`** — the fail-closed gate's session-local
   fallback reads only `.completed`. It ignores
   `~/.claude/.skill-invocation-evidence-<token>`, the append-only artifact
   the completion hook writes *unconditionally* on every successful Skill
   return (the F1-trusted, real-return-only record). In the repro, that file
   under the push's own token carried both milestones — the gate never looked.
3. **No cross-location ledger read** — milestones recorded under a different
   branch-ledger key (worktree/cwd split, detached HEAD, branch rename,
   remote-URL variant) are invisible even when their recorded SHA is a commit
   of the push branch.

## What Changes

- **`hooks/skill-completion-hook.sh`**: move the gating-milestone
  branch-ledger recording above the composition-state existence gate, next to
  the invocation-evidence write (same rationale as that write's earlier
  move): the durable cross-session carrier must not depend on transient
  composition state existing.
- **`hooks/lib/branch-ledger.sh`**: add `branch_ledger_bridge_has` — a
  cross-location read that scans sibling ledger dirs and accepts a milestone
  only when its recorded SHA is bound to the push branch: SHA == HEAD, or SHA
  is an ancestor of HEAD that is NOT reachable from the mainline merge-base
  (a branch-local commit). Mainline-only or foreign-branch evidence never
  bridges. Fail-open as "no bridge" (the bridge can rescue, never deny).
- **`hooks/openspec-guard.sh`**: the status checks (composition block and
  global fail-closed gate) gain two additional evidence legs, tried only
  after the existing ones miss: (a) the same-token invocation-evidence
  artifact (real-Skill-return records, honoring the review-embedding proxy
  skills), and (b) the branch-ledger bridge. Bridge acceptance appends an
  advisory note so cross-location evidence is never silently consumed.

Acceptance is not widened — only where evidence is looked for, mirroring the
PR #97 verdict-bridge discipline. The F1 invariant is preserved: every new
evidence leg is written exclusively by real Skill returns (the completion
hook); trigger-match backfill still cannot fabricate gating milestones.

## Capabilities

- **Modified: skill-routing** — push-gate STATUS layer gains
  cross-location/session-local evidence resolution (delta spec: ADDED
  requirement under `specs/skill-routing/spec.md`).

## Impact

- `hooks/openspec-guard.sh`, `hooks/lib/branch-ledger.sh`,
  `hooks/skill-completion-hook.sh` — all three are gate-enforcement /
  evaluator surfaces (canary + evaluator-surface advisory lists), so this
  branch's push is routing-gated and the evaluator-surface advisory will
  fire; the verification verdict is partly self-referential and the PR calls
  these files out for explicit human review.
- New regression file `tests/test-push-gate-status-bridge.sh` (auto-discovered
  by `tests/run-tests.sh`); no `.verify.yml` change needed.
- False-block class removed; deny posture for genuinely-absent evidence
  unchanged (proven by no-over-acceptance tests).
