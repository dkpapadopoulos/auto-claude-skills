# Enforcement map

One page, anti-folklore: everything in this plugin that can BLOCK an action,
in the order it is checked, plus everything that only warns. Run
`bash scripts/gate-status.sh` for a live replay of these checks against your
current branch (`--help` prints the compact version of this map; the two are
pinned together by `tests/test-gate-status.sh`).

## Hard blocks (permissionDecision: deny)

All live in `hooks/openspec-guard.sh` (PreToolUse:Bash), evaluated in ORDER —
the first failing gate wins. They see only agent-run commands: a human
terminal is outside the hook by construction.

| # | Gate | Denies when | Remedy |
|---|------|-------------|--------|
| 1 | compound mutate-then-push | one command commits/merges/rebases/cherry-picks/reverts/ams AND pushes (evidence is pre-exec; the inline mutation can't be covered) | run the mutation first, then `git push` as a separate command |
| 2 | chain REVIEW gate | `requesting-code-review` is in the active composition chain but not completed (.completed ∪ branch ledger) | invoke Skill(superpowers:requesting-code-review) |
| 3 | chain VERIFY gate | `verification-before-completion` in chain, not completed | invoke Skill(superpowers:verification-before-completion) |
| 4 | verify-hardening | the verification verdict AT HEAD (sha must equal HEAD, not ancestor) reports failing gates | fix failures, re-run Skill(auto-claude-skills:project-verification) |
| 5 | global fail-closed gate | ANY agent push lacks a REVIEW record AND a VERIFY signal for this branch (ledger, .completed, or clean verdict covering HEAD) | run the missing Skill(s); this fires even with no composition chain |
| 6 | routing governance | push touches `skills/`, `config/`, or `hooks/` in a routing repo without a clean verdict covering the routing changes (clean at HEAD, or clean ancestor with routing unchanged since) | Skill(auto-claude-skills:project-verification) until clean at HEAD |

`gh pr merge` and `gh api` merge endpoints traverse the same gates 2–5
(audit F2). `gh pr create` is deliberately ungated — creation starts review.
Gates fall OPEN (never deny) on infrastructure absence: missing jq, missing
lib, unresolvable diff base. `PUSH-GATE CANARY` at session start warns when a
gate component is missing/unsourceable.

**Human-only bypasses:** push from your own terminal, or launch Claude Code
with `ACSM_SKIP_PUSH_GATE=1` in its environment. The agent cannot set either.

## Advisory only (additionalContext, never a deny)

- REVIEW staleness — HEAD moved past the recorded review SHA. This is
  ADVISORY BY DESIGN, now empirically backed: the 2026-07-15 pre-registered backtest
  (openspec/changes/gate-status/) found every deny variant would have blocked
  56–94% of the last 48 clean merges (SHIP commits + review fixes + merges
  from main land after review structurally) and caught 0 defects.
  `gate-status.sh` prints the delta (docs vs src) via
  `hooks/lib/staleness-delta.sh` to keep collecting live data.
- SHIP-phase guards: openspec-ship not run, memory consolidation missing,
  archived delta specs unsynced, REVIEW-in-chain-not-completed.
- Verdict states `could_not_verify` / gate-gaming `suspect` (never hard-block).
- Design/plan guard, trifecta check, phase-reality block, drift canary.

## CI (merge-time, outside the hooks)

- `tests/run-tests.sh` via `.verify.yml` — includes the owned done-gates:
  routing-fixture coverage and skill-content coverage (both CI-blocking).
- OpenSpec Validate workflow (spec-driven mode) — hard-blocks only if marked
  Required in branch protection (docs/CI.md).

## Non-gates (folklore corrections)

- `role: required` in triggers is routing emphasis, NOT merge-blocking.
- `max_iterations` caps only `domain`/`required` roles (hardcoded allowlist).
- Evidence artifacts live in `~/.claude/` and are NOT CI-visible; CI's
  backstop is the test suite, not milestone artifacts.
