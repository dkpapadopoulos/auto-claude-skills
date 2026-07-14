## Purpose

Domain skills that enforce safety disciplines in DESIGN. Scaffolding for new skills, prototype variation for design decisions, and lethal-trifecta review for agent designs — co-selected alongside the superpowers process drivers without displacing them.
## Requirements
### Requirement: starter-template domain skill
The plugin MUST provide a `starter-template` domain skill in DESIGN phase that emits repo-native seed files when creating new skills, commands, plugins, hooks, or modules.

#### Scenario: New skill creation
- **WHEN** the user prompts with "create a new skill" or matching trigger patterns
- **THEN** starter-template MUST co-select alongside brainstorming as a domain skill
- **AND** brainstorming MUST remain the process driver

#### Scenario: Process skill restriction
- **WHEN** the user requests a process skill for a superpowers-owned phase (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG)
- **THEN** the skill MUST emit a warning about the superpowers phase driver contract

### Requirement: prototype-lab domain skill
The plugin MUST provide a `prototype-lab` domain skill in DESIGN phase that produces exactly 3 thin comparable variants with a comparison artifact and mandatory Human Validation Plan.

#### Scenario: Multi-variant design
- **WHEN** the user prompts with "prototype" or "compare options" or matching trigger patterns
- **THEN** prototype-lab MUST co-select alongside brainstorming as a domain skill
- **AND** brainstorming MUST remain the process driver
- **AND** prototype-lab MUST NOT appear as a process skill

#### Scenario: Human Validation Plan
- **WHEN** prototype-lab produces a comparison artifact
- **THEN** the artifact MUST include a Human Validation Plan section
- **AND** AI-simulated user testing MUST NOT replace the Human Validation Plan

### Requirement: agent-safety-review domain skill
The plugin MUST provide an `agent-safety-review` domain skill in DESIGN phase that evaluates designs for the lethal trifecta pattern.

#### Scenario: Lethal trifecta detection
- **WHEN** a design involves private_data AND untrusted_input AND outbound_action
- **THEN** agent-safety-review MUST classify the design as high risk
- **AND** MUST recommend blast-radius mitigation (cutting at least one leg)
- **AND** MUST NOT claim that improved detection scores solve the problem

#### Scenario: Autonomy trigger matching
- **WHEN** the user prompts with autonomy-related language (autonomous loop, overnight, YOLO, skip permissions, etc.)
- **THEN** agent-safety-review MUST fire as a domain skill

### Requirement: Driver invariant protection
Wave 1 additions MUST NOT alter the superpowers driver invariants.

#### Scenario: Driver invariants unchanged
- **WHEN** any Wave 1 skill fires
- **THEN** the phase_compositions drivers MUST remain: DESIGN=brainstorming, PLAN=writing-plans, IMPLEMENT=executing-plans, REVIEW=requesting-code-review, SHIP=verification-before-completion, DEBUG=systematic-debugging

### Requirement: Scenario-eval test suite
The plugin MUST include a suite-level behavioral evaluation that validates routing judgment.

#### Scenario: Scenario coverage
- **WHEN** `bash tests/test-scenario-evals.sh` is run
- **THEN** it MUST test PDLC scenarios (prototype-lab, starter-template co-selection), safety scenarios (lethal trifecta, overnight, YOLO), guardrail scenarios (SHIP phase routing, composition chain), and driver-invariant scenarios (new skills never as process drivers)

### Requirement: eval-strategy classification at DESIGN
The DESIGN phase composition MUST emit an always-on advisory hint instructing the model to classify how the feature is verified — asking the user when unclear — and branch the guidance: probabilistic/AI/LLM/agent behavior plans an eval set (smoke + adversarial/safety subsets, pinned judge model+version, never-delete cases, pre-registered safety-stop) with the safety subset authored failing (red) before implementation; deterministic work uses test-driven-development plus the mandated acceptance scenarios. The hint MUST be advisory and fail-open, and MUST be mirrored into the fallback registry. Safety dimensions MUST be treated as hard pass/fail gates, never averaged into a quality blend.

#### Scenario: AI/LLM feature classification
- **WHEN** a builder is in DESIGN for a feature whose outputs cannot be exact-matched (LLM/agent/probabilistic)
- **THEN** the EVAL STRATEGY hint MUST direct planning an eval set with adversarial/safety subsets and a safety subset authored red before implementation
- **AND** it MUST NOT rely on an automatic AI-feature detector — the model classifies, asking the user when unclear

#### Scenario: Deterministic feature classification
- **WHEN** the feature is deterministic
- **THEN** the EVAL STRATEGY hint MUST direct standard test-driven-development plus the acceptance scenarios already required by the DESIGN→PLAN contract
- **AND** it MUST NOT impose eval-set ceremony (judges, adversarial subsets) on deterministic work

#### Scenario: Advisory and fail-open
- **WHEN** the hint is emitted
- **THEN** it MUST be advisory only and MUST NOT block or alter routing scores
- **AND** it MUST be present in both `config/default-triggers.json` and `config/fallback-registry.json`

### Requirement: safety eval cases red before code
The `agent-safety-review` skill MUST require that, for AI/LLM or agent features, the safety eval cases (injection, escalation, refusal, safety-routing-suppression) are authored and failing (red) before the behavior is implemented, composing with `test-driven-development`. Detection added after the behavior exists MUST NOT be treated as a substitute.

#### Scenario: Red-before-code for an agent feature
- **WHEN** agent-safety-review evaluates an AI/LLM or agent design
- **THEN** it MUST state that safety eval cases are authored and failing before the behavior is implemented
- **AND** it MUST reference composition with test-driven-development

### Requirement: safety-relevant runtime paths exercised and eval scenarios append-only
The `runtime-validation` skill MUST require that changes touching authentication/authorization, data deletion, money/payments, or destructive or externally-visible side effects exercise and report those paths (pass/fail with evidence) rather than deferring them to manual checks. Eval-pack safety scenarios MUST be append-only: a scenario MUST NOT be deleted to make the bar pass; an obsolete scenario MUST be marked deprecated with a dated rationale.

#### Scenario: Safety-relevant path must be exercised
- **WHEN** a change alters a safety-relevant path (auth, data deletion, money, destructive side effects)
- **THEN** runtime-validation MUST require that path be exercised and reported with evidence
- **AND** a green happy-path result MUST NOT be treated as clearing an unexercised safety-relevant path

#### Scenario: Eval scenarios are append-only
- **WHEN** an eval-pack safety scenario becomes inconvenient or obsolete
- **THEN** it MUST NOT be deleted to make the bar pass
- **AND** it MUST be marked deprecated with a dated rationale instead

### Requirement: Owned gate messages use expected-actual-imperative remediation

Hard-gate and could-not-verify / iterative-fix-loop messages in files this plugin owns SHALL
be phrased as expected state, then actual observed state, then an imperative remediation the
reader can execute. This applies to the `hooks/openspec-guard.sh` PUSH GATE deny strings, the
`skills/agent-team-review/SKILL.md` blocking-verdict guidance, the
`skills/runtime-validation/SKILL.md` fix-loop terminal and coverage-gap / manual-check
hand-offs, and the `hooks/consolidation-stop.sh` session-end consolidation reminder. A rewritten
message whose action is not always warranted (e.g. the consolidation reminder, when nothing
durable emerged) MUST preserve an explicit honest opt-out so the imperative does not become
theater. Genuinely-advisory
messages that offer an explicit opt-out (e.g. the SHIP-phase `…or proceed if not needed`
warnings) MUST remain advisory and MUST NOT be rewritten into imperative form. The rewrite
MUST NOT change any gate block/allow decision, verdict routing, or fix-loop iteration count —
only message wording. The rewrite ships on clarity / actionability merit — because the gate
LOGIC is unchanged there is no gate-logic regression — and MUST NOT be justified by a
claimed behavioral self-correction lift unless such a lift is actually measured (see the
red-first probe requirement below).

#### Scenario: Hard-gate message names expected, actual, and an imperative next action
- **WHEN** a push is blocked by openspec-guard because a required chain step has not run
- **THEN** the deny message MUST state the expected completed step, the actual missing step, and an imperative "do now" remediation (invoke the named Skill, then re-run the push)

#### Scenario: Could-not-verify terminal hands off explicit actions
- **WHEN** the runtime-validation fix-rescan loop exhausts its iterations with failures remaining
- **THEN** the message MUST hand off each remaining failure as an explicit action (scenario, observed failure, and the specific fix or decision the human must make) rather than a passive "requires human review" note

#### Scenario: Imperative rewrite preserves an honest opt-out where the action is conditional
- **WHEN** the session-end consolidation reminder fires and no durable, team-relevant learning emerged this session
- **THEN** the imperative reminder MUST still offer an explicit opt-out ("if nothing durable emerged, say so and stop") so it does not force consolidation theater

#### Scenario: Opt-out advisories stay advisory
- **WHEN** an openspec-guard SHIP-phase warning offers an explicit opt-out ("…or proceed if not needed")
- **THEN** it MUST retain the opt-out and MUST NOT be rewritten into an imperative mandate (no imperative theater)

### Requirement: Correction-ergonomics lift is probed red-first and the result recorded honestly

A behavioral A/B lift claim SHALL be probed red-first before it may be asserted, using an opt-in
pack (`tests/fixtures/correction-ergonomics/evals/behavioral.json`) run via
`tests/run-behavioral-evals.sh --directive-file` with a pinned inner `claude -p --model`. The
baseline arm injects the prior passive wording; the treatment arm injects the imperative wording;
a deterministic `text` / `tool_call` assertion measures the corrective action. If the baseline is
already green (no red→green headroom), a self-correction lift MUST NOT be claimed and the rewrite
MUST NOT be tightened into measuring structural echo of the treatment wording. The probe's result —
including a negative result — MUST be recorded in the pack README with the pinned model(s) and run
date. The pack is retained as a recorded experiment; scenarios are append-only and MUST be
deprecated with a dated rationale rather than deleted.

#### Scenario: Red-first probe with no headroom yields a recorded negative, not a forced green
- **WHEN** the A/B pack runs a scenario with passive (baseline) then imperative (treatment) wording under a pinned model and the baseline already passes the corrective-action assertion
- **THEN** no self-correction lift may be claimed, the assertions MUST NOT be tightened to force baseline-red, and the negative result MUST be recorded in the pack README with the pinned model(s) and date

#### Scenario: Rewrite ships on clarity merit when no lift is measured
- **WHEN** the red-first probe records no measurable lift but the rewrites are clearer/more actionable and leave gate logic unchanged
- **THEN** the rewrites MAY ship on clarity / actionability merit, and the change MUST NOT cite a behavioral lift as justification

### Requirement: Gating milestones enter composition state only through invocation evidence

The composition walker's computed done-prefix MUST NOT contain
`requesting-code-review` or `verification-before-completion`, regardless of
whether the prefix derives from the chain-anchor index or the last-invoked
index. These two names MUST enter the `.completed` array only via (i) the
PostToolUse completion hook recording an actual successful Skill return, or
(ii) preservation of already-recorded on-disk entries through the monotonic
union. All other chain steps MUST continue to be back-filled into the computed
prefix exactly as before. The filter MUST be fail-open: if it cannot be
applied, the walker MUST degrade without aborting the hook, and the two names
MUST NOT be emitted into the computed prefix.

#### Scenario: A late-anchor prompt does not fabricate gate evidence

- **GIVEN** fresh composition state (no `.completed` on disk, no branch-ledger
  milestones for the current branch) and the standard
  DESIGN→PLAN→IMPLEMENT→REVIEW→SHIP chain
- **WHEN** a prompt trigger-matches a late chain anchor (e.g. `openspec-ship`,
  step 6) and the walker writes composition state
- **THEN** `.completed` MUST NOT contain `requesting-code-review` or
  `verification-before-completion`, and a subsequent agent `git push` MUST be
  denied by the push gate for the missing milestones

#### Scenario: Invocation-recorded milestones survive re-anchoring

- **GIVEN** `.completed` on disk contains `requesting-code-review`, recorded by
  the completion hook after the Skill actually returned successfully
- **WHEN** a later prompt re-anchors anywhere in the same chain and the walker
  rewrites composition state
- **THEN** `requesting-code-review` MUST remain in `.completed` (monotonic
  union preserved; the filter applies only to the computed prefix)

#### Scenario: Non-gating back-fill is preserved (chore false-block guard)

- **GIVEN** fresh composition state and a prompt that anchors at
  `requesting-code-review` (step 4)
- **WHEN** the walker writes composition state
- **THEN** `.completed` MUST contain the non-gating predecessors
  (`brainstorming`, `writing-plans`, `executing-plans`) and MUST NOT contain
  either gating milestone

#### Scenario: The last-invoked signal cannot leak the other gating milestone

- **GIVEN** `verification-before-completion` was actually invoked (recorded by
  the completion hook) but `requesting-code-review` never ran
- **WHEN** a subsequent prompt causes the walker to compute its prefix from the
  last-invoked index (which lies beyond `requesting-code-review` in the chain)
- **THEN** `.completed` MUST contain `verification-before-completion` (real
  evidence) and MUST NOT contain `requesting-code-review`

### Requirement: Remote merges via gh are gated on the same milestones as push

An agent Bash command that actually invokes a PR merge MUST pass the same
REVIEW and VERIFY evidence gates as `git push` (composition checks,
verify-hardening, global fail-closed gate). This covers `gh pr merge` in any
flag order (including `--auto` and `-R/--repo`) and `gh api` naming the REST
pull-merge path or GraphQL `mergePullRequest`. `gh pr create` MUST NOT be gated. Detection MUST be
invocation-based (segment-aware), not phrase-based: a command that merely
mentions the words MUST NOT trigger the gate. All denies MUST honor the
human-only bypass and fail open on infrastructure errors (missing jq, missing
libs). Routing-governance remains push-scoped.

#### Scenario: gh pr merge without milestones is denied

- **GIVEN** a branch with no REVIEW/VERIFY evidence (empty ledger, empty
  `.completed`, no verdict)
- **WHEN** the agent runs `gh pr merge 123 --auto` through the Bash tool
- **THEN** the guard MUST deny, naming the missing milestone(s)

#### Scenario: gh pr merge with full evidence is allowed

- **GIVEN** a branch whose ledger carries both milestones and a clean verdict
  covering HEAD
- **WHEN** the agent runs `gh pr merge 123`
- **THEN** the guard MUST NOT deny

#### Scenario: gh pr create and phrase mentions stay ungated

- **GIVEN** any evidence state
- **WHEN** the agent runs `gh pr create --title "gh pr merge fix"` or a
  command that only mentions "gh pr merge" as data (e.g. `echo "gh pr merge"`)
- **THEN** the guard MUST NOT deny

### Requirement: Compound mutate-then-push commands are denied

A single Bash command MUST be denied when a content-mutating git subcommand
(`commit`, `merge`, `cherry-pick`, `rebase`, `revert`, `am`) is invoked in a
segment ordered before a `git push` segment, regardless of evidence state (the gate evaluates pre-exec state, so no evidence can cover the
not-yet-created commit), with a remedy instructing the agent to run the push
as a separate command. The deny MUST honor the human-only bypass. `git pull
&& git push` and a plain `git push` MUST NOT match.

#### Scenario: commit-and-push in one command is denied even with clean evidence

- **GIVEN** a branch with both milestones recorded and a clean verdict at HEAD
- **WHEN** the agent runs `git commit -m "fix" && git push origin HEAD`
- **THEN** the guard MUST deny with the separate-command remedy

#### Scenario: push as its own command is unaffected

- **GIVEN** the same evidence state
- **WHEN** the agent runs `git push origin HEAD` alone
- **THEN** the compound rule MUST NOT fire (other gates evaluate as usual)

