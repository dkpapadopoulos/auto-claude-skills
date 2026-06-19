# Proposal: Lethal-trifecta DESIGN/REVIEW model-asks directive

## Why

`agent-safety-review` is the plugin's lethal-trifecta gate (private_data ×
untrusted_input × outbound_action). It is routed by **narrow lexical regex**
(`email.?agent`, `auto.?reply`, `send.on.behalf`, … — `config/default-triggers.json`
trigger block for `agent-safety-review`). The lethal trifecta is a **semantic property
of a design's data flow**, not a keyword — so natural agent-building language describes
it without ever matching those tokens.

Empirically verified: the prompt *"I want to build an agent that reads my customer
support emails and sends Slack replies automatically"* — a textbook trifecta
(untrusted_input + private_data + outbound_action) — routes **only** `brainstorming`.
`agent-safety-review` does not fire. Re-running through the activation hook with
`SKILL_EXPLAIN=1` confirmed the skill is absent from the activation context.

Enumerating more regex tokens is the brittle-grep trap (it never catches the long tail
of phrasings). The proven fix in this codebase is **model-asks classification**: an
always-on phase directive that has the model judge the semantic condition — exactly how
the existing `EVAL STRATEGY` DESIGN hint handles "is this feature probabilistic?". This
change applies the same lever to the trifecta.

An SDLC-wide audit of every `skills[].triggers` and `phase_compositions[].hints`
confirmed the trifecta is the one **high-consequence semantic condition with no
backstop at DESIGN**. Other semantic conditions are already covered: eval-set need
(`EVAL STRATEGY` hint), guardrail weakening + autonomous-scope expansion (REVIEW
`ADVERSARIAL REVIEW` hint), security-sensitive change (`security-scanner` REVIEW
composition), large/sensitive diffs (`agent-team-review`, `role: required`).

## What Changes

Two edits to the advisory `phase_compositions[].hints` mechanism (no new skill, no
change to `agent-safety-review`'s own regex fast-path):

1. **New always-on `DESIGN` hint — `TRIFECTA CHECK`.** Instructs the model to classify
   each trifecta field as Present/Absent/Unknown from the proposed data flow and, if
   **≥2 are Present (or Unknowns could make it ≥2)**, invoke
   `Skill(auto-claude-skills:agent-safety-review)` **after brainstorming has a candidate
   design and before transitioning to PLAN** (respecting the brainstorming-first gate).
   The `≥2` floor matches the skill's own risk table (2-of-3 = Elevated risk).

2. **Reworded `REVIEW` `ADVERSARIAL REVIEW` hint.** Add a clause routing to
   `agent-safety-review` when the **resulting data flow** has ≥2 trifecta fields **or
   the diff adds a missing leg to an existing ≥2-field flow** (not only when a change
   weakens an existing gate). Near-zero token cost (editing existing hint text).

Both edits are mirrored in `config/fallback-registry.json` per the Fallback Registry
Sync Gate.

## Capabilities

### Modified

- **skill-routing** — adds a phase-scoped, model-assessed surfacing of
  `agent-safety-review` at DESIGN and strengthens the REVIEW adversarial governance hint
  to cover trifecta introduction. Implemented via `phase_compositions[].hints`, not by
  widening triggers.

## Impact

- `config/default-triggers.json` — `phase_compositions.DESIGN.hints` (+1 entry),
  `phase_compositions.REVIEW.hints` (reword existing adversarial entry).
- `config/fallback-registry.json` — mirror both (sync gate).
- `tests/` — deterministic hint-presence assertions (DESIGN contains `TRIFECTA CHECK`;
  SHIP does not; REVIEW adversarial hint references `agent-safety-review`).
- No runtime behavior change beyond injected advisory text; hints are advisory and
  fail-open. `agent-safety-review`'s existing keyword fast-path is unchanged.

## Out of Scope

- No new skill; no change to `agent-safety-review` SKILL.md or its triggers.
- No IMPLEMENT-phase injection (DESIGN + REVIEW are the gate points).
- No widening of `security-scanner` / `agent-team-review`.
- The comparable `incident-analysis` DEBUG symptom-regex semantic gap is **deferred**
  to a future wave (lower consequence, no security surface).
- `when` clauses on non-plugin hints are documentary only (the hook emits non-plugin
  hints unconditionally); this change does not add `when`-evaluation logic.
