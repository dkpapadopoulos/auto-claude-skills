# Enforcement map

One page, anti-folklore: the places where this plugin can BLOCK an action,
plus what only warns. In scope: every registered hook that denies a tool call
or exits 2, the one script that refuses to send, and CI. Out of scope: Claude
Code's own permission prompts and anything another plugin does. Run
`bash scripts/gate-status.sh` for a live replay of the push-gate checks against
your current branch (`--help` prints the compact version of that part of the
map; the two are pinned together by `tests/test-gate-status.sh`).

**How far to trust the list.** That test derives the blocking hooks from
`hooks/` and fails when one is not named here, and does the same for the push
gate's deny labels. It matches text, so it cannot see a deny assembled from a variable or a
helper, a new deny branch inside a hook already listed (outside the push
gate), or a refusal added to a script. Those three depend on whoever adds
one updating this page.

## Hard blocks (permissionDecision: deny)

Four hooks can deny. The push gate is the one most sessions meet; the other
three are listed under "Hard blocks outside the push gate" below. All of them
see only agent tool calls: a human terminal is outside the hooks by
construction.

### The push gate

These live in `hooks/openspec-guard.sh` (PreToolUse:Bash), evaluated in ORDER —
the first failing gate wins. The label is what the deny is recorded under
(`deny:<label>`).

| # | Gate | Label | Denies when | Remedy |
|---|------|-------|-------------|--------|
| 1 | compound mutate-then-push | `mutate-then-push` | one command commits/merges/rebases/cherry-picks/reverts/ams AND pushes (evidence is pre-exec; the inline mutation can't be covered) | run the mutation first, then `git push` as a separate command |
| 2 | chain REVIEW gate | `chain-review` | `requesting-code-review` is in the active composition chain but not completed (.completed ∪ branch ledger ∪ a returned allowlisted reviewer whose sha covers the push) | invoke Skill(superpowers:requesting-code-review) |
| 3 | chain VERIFY gate | `chain-verify` | `verification-before-completion` in chain, not completed | invoke Skill(superpowers:verification-before-completion) |
| 4 | verify-hardening | `verify-hardening` | the verification verdict AT HEAD (sha must equal HEAD, not ancestor) reports failing gates | fix failures, re-run Skill(auto-claude-skills:project-verification) |
| 5 | global fail-closed gate | `global-failclosed` | ANY agent push is missing either a REVIEW record or a VERIFY signal for this branch; it needs both (ledger, .completed, or clean verdict covering HEAD; for REVIEW also a returned allowlisted reviewer whose sha covers the push) | run the missing Skill(s); this fires even with no composition chain |
| 6 | routing governance | `routing-governance` | push touches `skills/`, `config/`, or `hooks/` in a routing repo without a clean verdict covering the routing changes (clean at HEAD, or clean ancestor with routing unchanged since) | Skill(auto-claude-skills:project-verification) until clean at HEAD |

**One more leg in the same hook can deny, and does not by default.** Between gates 5 and 6
sits the DESIGN/PLAN outbound leg (label `phase-enforcement`): a push or merge
of chain-covered work (an active chain containing `brainstorming`, or a branch
ledger holding DESIGN/PLAN records) with no evidence for `brainstorming` or
`writing-plans`. Its default mode is `warn`, which only records telemetry; it denies only when
`phase_enforcement.outbound` is `"deny"` in `~/.claude/skill-config.json`
(`"off"` silences it). Remedy: invoke the missing skill, or record a skip
with `phase_attest` as the deny text spells out. `gate-status.sh` does not
replay this leg, which is why it has no number.

`gh pr merge` and `gh api` merge endpoints traverse the same gates 2–5
(audit F2). `gh pr create` is deliberately ungated — creation starts review.
Gates fall OPEN (never deny) on infrastructure absence: missing jq, missing
lib, unresolvable diff base. `PUSH-GATE CANARY` at session start warns when a
gate component is missing/unsourceable.

**Human-only bypasses (push gate only):** push from your own terminal, or
launch Claude Code with `ACSM_SKIP_PUSH_GATE=1` in its environment. The agent
cannot set either. That variable does nothing for the three hooks below.

### Hard blocks outside the push gate

`gate-status.sh` replays none of these. Each deny carries its own remedy text.

| Hook | Runs on | Denies when | Default | Remedy |
|------|---------|-------------|---------|--------|
| `hooks/skill-gate.sh` | PreToolUse:Skill | a skill in the active composition chain is invoked while an earlier step has no evidence (invocation record, branch ledger, attestation, or for REVIEW a returned allowlisted reviewer; `.completed` does not count) | deny only in this plugin's own source repo; a warning everywhere else. `phase_enforcement.skill_sequencing` in `~/.claude/skill-config.json` sets `deny`, `warn` or `off`. Any infrastructure failure (no jq, no token, no state, missing lib) allows with no output | invoke the missing step, or record a skip with `phase_attest` (the deny prints the command; REVIEW and VERIFY accept only real invocations), or run the action yourself |
| `hooks/publish-guard.sh` | PreToolUse:Bash | a `gh` command that publishes text (issue, PR, comment and similar bodies) reproduces text from the local memory corpus verbatim (#174) | deny on a match, always. When it cannot check (no corpus, no jq, missing lib) it allows and says so | rewrite the body to cite `memory/<file>.md:<line>` instead of quoting it |
| `hooks/egress-consent-ask-hook.sh` | PreToolUse:AskUserQuestion | a question marked `[egress-consent:<digest>]` arrives pre-answered, comes from a subagent, does not fit the required shape, shows a preview that does not hash to the prepared package, or reuses a tool-use id | deny for marked questions; unmarked questions pass untouched. When it cannot check (no jq, unloadable lib, unparseable payload) it allows and says so, and records no ask, so nothing can be approved from that question | ask again from the main conversation, exactly as `scripts/consult-dispatch.sh prepare` printed it |

## Stops that are not a deny

- `hooks/teammate-idle-guard.sh` (TeammateIdle) exits 2 when an agent-team
  teammate goes idle while owning in-progress tasks, which sends it back to
  work with the task names. At most once per 120 seconds per teammate.
- `scripts/consult-dispatch.sh send` refuses to send a package to another
  vendor without a fresh user approval of that exact package (exit 3 cannot
  verify, 4 not approved, 6 secret-scan findings; exit 2 is a usage error
  or a missing `codex`, and also sends nothing). Exit 5
  is different: the send failed midway, content may have left the machine and
  the approval is spent, so do not retry blindly. It is a script, not a hook.
  `consultation.egress_consent: "warn"` in `~/.claude/skill-config.json`
  turns the approval check off, and the script announces that on every send;
  the secret scan still runs when gitleaks is installed. Without gitleaks the
  script says so and sends unscanned, in either mode.

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
- VERIFY measured verdict (#301) — `verification-before-completion` is
  credited, but no verdict MEASURED by `scripts/verify-and-record.sh`
  (`discovery_source` `verify-yml` or `explicit`) covers the pushed commit.
  Push only, chain leg only, and not in a repo whose `.verify.yml` declares a
  non-local substrate. Each event is recorded to
  `~/.claude/.push-verify-shadow.jsonl`; `scripts/verify-shadow-adjudicate.sh`
  (`--status`, `--next`, `--adjudicate`) takes a human label per would-block
  episode and reads the corpus against the decision rule registered in
  `openspec/changes/verify-measured-verdict/design.md`. The deny-flip is a
  separate change. Regression: `tests/test-verify-measured-verdict.sh`.
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
