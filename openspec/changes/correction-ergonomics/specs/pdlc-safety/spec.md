## ADDED Requirements

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
