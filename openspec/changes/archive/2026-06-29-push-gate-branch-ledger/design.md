# Design — Push-Gate Branch Milestone Ledger

## Architecture

Additive layer over the existing push gate. `.completed` (transient, per-chain) is untouched; a new
durable **per-(repo+branch) milestone ledger** becomes a second, authoritative source the gate ORs
in. Three touch-points + one helper.

### 1. `hooks/lib/branch-ledger.sh` (new helper)
- `branch_ledger_key()` → a stable `<repo>-<branch>` hash. Reuse `consol-marker.sh`'s identity
  pattern: remote URL → toplevel path → `shasum`; branch via `git rev-parse --abbrev-ref HEAD`,
  with **detached HEAD → `detached-<shortsha>`** as its own boundary. Empty/undeterminable → empty
  key (caller falls back to `.completed`).
- `branch_ledger_record(milestone)` → append a marker for `(key, milestone)` recording HEAD sha +
  UTC ts. **Append-only / per-milestone file** (e.g. `~/.claude/.skill-branch-ledger-<key>/<milestone>`),
  never read-modify-write a shared JSON — avoids concurrent-session contention.
- `branch_ledger_has(milestone)` → true if a marker exists for `(current key, milestone)`.
- `branch_ledger_sha(milestone)` → the recorded HEAD sha (for staleness comparison).
- Bash 3.2; fail-open (any error → empty/false, never abort the hook).

### 2. `hooks/skill-completion-hook.sh` (writer)
After the existing `.completed` advance, if the completed skill is a gating milestone
(`requesting-code-review` | `verification-before-completion`), call `branch_ledger_record`. No
behavior change to the existing `.completed` write. Degrades silently if the helper/branch is
unavailable.

### 3. `hooks/openspec-guard.sh` (gate)
Replace each gating check's condition. For milestone M in the active chain:
- **PASS** if `branch_ledger_has(M)` OR `.completed` contains M.
- **DENY** only if M is in the active chain AND neither source has it (current message preserved).
- After a PASS via ledger, if `branch_ledger_sha(M) != current HEAD`, append a **soft staleness
  WARNING** to the gate output (advisory, never converts to deny).
- If the branch key is undeterminable, use the current `.completed`-only path (no regression).

## Trade-offs

- **Additive `OR`, not replacement.** In-flight sessions with no ledger still gate on `.completed`;
  the deny baseline is unchanged. This is why it can't *weaken* enforcement (a gate in the active
  chain with neither source still denies).
- **Durable pass + soft staleness.** The one new risk — review once, add risky commits, push — is
  downgraded to a warning, matching the *current* gate's existing HEAD-agnosticism (it never
  re-blocked on new commits either). Net: removes a false-negative (false-block), adds no
  false-positive.
- **Per-milestone marker files over JSON.** Slightly more files, but no read-modify-write race
  across concurrent sessions sharing `~/.claude/` — the exact failure class the #51 token fix
  addressed.

## Dissenting views (from the design debate + Codex sparring)

- **My initial lean was design A** (preserve `.completed` across re-anchor, scoped to branch).
  Codex + grounding refuted it: the *unconditional* A-variant stuffs non-chain-member entries into
  `.completed`, breaking the sticky-emission "non-member = malformed" invariant
  (`skill-activation-hook.sh:390-399`); the *membership-filtered* A-variant drops the gates on
  LEARN/DEBUG chains that genuinely lack them (`outcome-review` precedes only `product-discovery`;
  DEBUG/LEARN phase_compositions carry no review/verify steps). Hybrid-B avoids both by not
  touching `.completed` at all.
- **Hard HEAD-invalidation** considered and rejected (friction; conflicts with the post-verify
  commit workflow and the review→fix→re-review loop). Soft warning chosen.
- **Branch-only keying** rejected for repo+branch hash (a same-named branch in another repo/worktree
  must not inherit milestones).

## Decisions

- Source of truth: `ledger OR .completed`; deny when neither + gate in active chain.
- Reset boundary: repo+branch (detached HEAD isolated).
- Staleness: soft warning, HEAD-sha based; tree-hash deferred.
- Fail-safe: undeterminable branch → `.completed`-only path (current behavior).

## Eval strategy

**Deterministic** (bash hook logic) → TDD with regression fixtures in `tests/test-routing.sh`
(no probabilistic/LLM behavior, no eval set). Required cases:
1. LEARN/DESIGN chain re-anchor that resets `.completed` → push still eligible via ledger.
2. Genuinely-new branch → ledger empty → gate denies (re-earn milestones).
3. No ledger present (in-flight session) → falls back to `.completed` (no regression; existing
   push-gate tests still pass).
4. Branch rename / different repo, same branch name → no milestone inheritance (key isolation).
5. Detached HEAD → isolated `detached-<sha>` boundary.
6. HEAD advanced past recorded sha → soft warning emitted, NOT a deny.
7. Concurrent writes (two milestones) → both recorded (append-only, no clobber).

## Trifecta

private_data Absent, untrusted_input Absent, outbound_action Absent — local hook state only. No
`agent-safety-review` required. Governance (adversarial-review checklist): touches `hooks/` phase
enforcement, but is strict-or-stricter (new branch gated; only a false-negative removed; durable
pass bounded by soft staleness) — not a guardrail weakening.

## Implementation Notes (synced at ship time)

- As-built per the design. Three commits: `hooks/lib/branch-ledger.sh` (helper) → `skill-completion-hook.sh` (writer, fail-open guarded source) → `openspec-guard.sh` (gate: `ledger OR .completed`, soft staleness, fail-safe).
- **Additional coherence fix (not in the original spec):** the SHIP-phase advisory **Check 4 (REVIEW GUARD)** was *also* made ledger-aware, so it cannot emit a "review not completed" advisory that contradicts a ledger-satisfied push gate. Same `OR branch_ledger_has(...)` relaxation.
- **Reviews:** Task 3 (gate) opus governance review = APPROVED, verdict NEUTRAL→STRENGTHENS, deny-path + fail-safe + ERR-trap-safety confirmed by injection. Final whole-branch opus review = Ready; writer↔reader key contract confirmed (both resolve `shasum(origin-url \x1f branch)` from the same working-tree cwd).
- **Deferred follow-ups (reviewer-endorsed, non-blocking):** (F1) staleness can accumulate for an out-of-chain milestone (advisory noise) — gate behind the in-chain flag; (F2) the stale path emits explicit `permissionDecision:allow` + early-exit (auto-approves + suppresses downstream SHIP advisories) while the fresh path falls through — friction inversion; prefer a bare `systemMessage` warning. Neither touches the deny path or fail-safe.
- Tests: `test-branch-ledger.sh` (7), `test-completion-ledger.sh` (5), `test-push-gate-ledger.sh` (7); full suite 67/67.
