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
- The review verdict artifact's `dispatch_evidence` field records one of
  `observed` | `asserted` | `imported` — provenance for `dispatch_attempted`/
  `dispatch_succeeded`, never a gate input. `observed` is written only when
  `hooks/reviewer-evidence-hook.sh` (`PostToolUse` on `^(Task|Agent)$`, which
  fires at spawn, not return) recorded an actual reviewer-subagent dispatch
  for this branch; `imported` only
  for a resolved `--from-github` PR; everything else — including an explicit
  `--dispatch-attempted`/`--dispatch-succeeded` on the CLI — is `asserted`.
  None of `dispatch_attempted`, `dispatch_succeeded`, or `dispatch_evidence`
  may act as a deny predicate, alone or collapsed (#197's spec). Regression:
  `tests/test-review-verdict.sh`, `tests/test-reviewer-evidence-hook.sh`.
- SHIP-phase guards: openspec-ship not run, memory consolidation missing,
  archived delta specs unsynced, REVIEW-in-chain-not-completed.
- Verdict states `could_not_verify` / gate-gaming `suspect` (never hard-block).
- Design/plan guard, trifecta check, phase-reality block, drift canary.

## CI (merge-time, outside the hooks)

- **NOTHING IN CI HARD-BLOCKS A MERGE TODAY.** `main` has no branch protection
  rule at all (verified 2026-07-29:
  `gh api repos/<owner>/<repo>/branches/main/protection` → `404 Branch not
  protected`). Both workflows below run and go red on a violation, but a red
  check does not stop a merge. Treat them as visible signals, not gates.
  Enabling protection is NOT a settings toggle here: `version-bump.yml` pushes
  directly to `main` with `[skip ci]`, so required checks would block it and
  version bumps would stop silently. See docs/CI.md before changing this.
- Done Gates workflow (`.github/workflows/done-gates.yml`) — runs three content
  checks on every PR: the two owned done-gates (routing-fixture coverage,
  skill-content coverage) plus the reviewer dispatch-brief gate
  (`tests/test-reviewer-dispatch-brief.sh`, issue #204). The third is a
  single-skill content gate, not a third owned done-gate — it is here because
  its own fixture and openspec proposal CLAIMED it ran in CI while it was
  reachable only through `tests/run-tests.sh`, i.e. the folklore corrected in
  the bullet below. All three would hard-block only if marked Required (see the
  caveat above). Regression: `tests/test-done-gate-ci.sh` pins the workflow to
  this claim — extend it when adding a step, or the claim rots.
- OpenSpec Validate workflow (spec-driven mode) — same: runs on every PR, not
  currently Required, so it does not block.
- **The FULL `tests/run-tests.sh` suite does NOT run in CI.** `.verify.yml` is
  `substrate: local`: it is read by `hooks/lib/verdict.sh`, the
  `project-verification` skill and tests — by no workflow. Until this file was
  corrected it claimed the opposite, which is the folklore this document exists
  to prevent. Wiring the full suite in is a separate decision (116 files, 10+
  minutes, known shared-state and stdin traps); making a slow or flaky check
  Required invites admin-override habits.
- **Why a server-side backstop at all:** the push gate is a local PreToolUse
  hook, so it cannot see a merge performed through the GitHub web UI (PR #178
  was merged that way), and it has documented human bypasses. Separately,
  routing-governance is scoped to `skills/|config/|hooks/` — a `tests/`-only PR
  that weakens a coverage gate itself never triggers the clean-verdict
  requirement. CI runs regardless of touched paths and has no bypass.

## Non-gates (folklore corrections)

- `role: required` in triggers is routing emphasis, NOT merge-blocking.
- `max_iterations` caps only `domain`/`required` roles (hardcoded allowlist).
- Evidence artifacts live in `~/.claude/` and are NOT CI-visible; CI's
  backstop is the test suite, not milestone artifacts.
