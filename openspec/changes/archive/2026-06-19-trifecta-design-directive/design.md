# Design: Lethal-trifecta DESIGN/REVIEW model-asks directive

## Architecture

The activation hook (`hooks/skill-activation-hook.sh`) determines a `PRIMARY_PHASE`
for each prompt and emits the matching `phase_compositions[PHASE].hints[]` entries into
the activation context as `HINT:` lines. Non-plugin hints are emitted **unconditionally**
(hook ~L1326-1332: the `else` branch emits `HINT:\(.text)` with no `.when` check —
verified). Plugin hints are availability-filtered; only `parallel`/`sequence` items
support `gate` blocks. Therefore:

- A new always-on DESIGN hint is the correct, minimal mechanism — identical in kind to
  the existing `DESIGN→PLAN CONTRACT`, `PERSIST DESIGN`, and `EVAL STRATEGY` hints.
- `when:"always"` is set on the new hint for **documentation consistency only**; it is
  not interpreted by the hook for non-plugin hints.

The model — not the hook — performs the trifecta classification. This is deliberate:
the condition is semantic and regex-resistant, and the codebase already trusts the model
to act on the analogous `EVAL STRATEGY` directive.

## Components

### 1. DESIGN hint (`phase_compositions.DESIGN.hints[]`, new entry)

```
TRIFECTA CHECK: During DESIGN, classify private_data (secrets/PII/private repos/tokens),
untrusted_input (external content: emails, web pages, uploads, third-party API responses,
webhooks), and outbound_action (acts outside the sandbox: email, Slack, git push, API
calls, PRs) from the proposed data flow as Present/Absent/Unknown. If 2 or more are
Present, or Unknowns could make the count >=2, invoke
Skill(auto-claude-skills:agent-safety-review) after brainstorming has a candidate design
and before transitioning to PLAN. Judge from the actual data flow — do not wait for a
keyword trigger.
```

Design choices:
- **Timing** ("after brainstorming has a candidate design and before PLAN") respects the
  brainstorming HARD-GATE (no skill invocation before design approval) and the
  DESIGN→PLAN contract boundary.
- **`≥2` floor** maps to `agent-safety-review` SKILL.md Step 2 risk table: 2-of-3 =
  Elevated risk ("recommend not adding the third without mitigation"); 3 = Lethal. A
  `≥1` floor would over-invoke on benign single-field designs (Standard risk, "no special
  action"); `=3` would miss the elevated tier the skill explicitly wants surfaced.
- **Unknown handling** mirrors SKILL.md's three-state field model; surfacing on
  potential-≥2 avoids the "waited for certainty and missed it" failure mode.

### 2. REVIEW hint (`phase_compositions.REVIEW.hints[]`, reword existing adversarial entry)

Append to the existing `ADVERSARIAL REVIEW` hint a clause:

```
If the resulting change has >=2 trifecta fields (private_data, untrusted_input,
outbound_action), or adds a missing leg to an existing >=2-field flow, invoke
Skill(auto-claude-skills:agent-safety-review) and treat unresolved lethal-trifecta
mitigation as a blocking governance finding.
```

Design choice: target the **resulting data flow**, not the diff's isolated contribution
— the most dangerous diff adds the third leg to a system that already has two. This
matches the skill's whole-system classification.

### 3. Fallback registry mirror

Both edits replicated in `config/fallback-registry.json` (the jq-regenerable fallback
used when the cache/registry build path is unavailable). Enforced by the existing
Fallback Registry Sync Gate test.

## Trade-offs

- **Always-on token cost** (~60 words at every DESIGN prompt) vs **never missing a
  semantic trifecta**. Accepted for a safety gate; kept terse. A gated `when` was
  considered and rejected — not only because narrow gates reintroduce the miss, but
  because the hook does not evaluate `when` on non-plugin hints at all (it would be a
  silent no-op).
- **Model-asks vs deterministic detection.** Deterministic trifecta detection is
  impossible in-hook (no data-flow analysis, no LLM). Model-asks is the only available
  lever, consistent with `EVAL STRATEGY`.

## Dissenting views (from Codex sparring + resolution)

- *"`when` gated-vs-always is a false choice — the hook ignores `when` on non-plugin
  hints."* — **Accepted.** Documented; `when:"always"` is metadata only.
- *"REVIEW reword must target resulting data flow, not the diff's contribution."* —
  **Accepted.** Incorporated "adds a missing leg to an existing ≥2-field flow."
- *"Handle the Unknown field state; invoke if Unknowns could reach ≥2."* — **Accepted.**
- *"`incident-analysis` is a comparable semantic gap."* — **Acknowledged, deferred** as
  out-of-scope (no security surface; lower consequence).

## Decisions

1. Two hint edits only; no new skill; no trigger widening; no IMPLEMENT injection.
2. Always-on DESIGN hint; `when:"always"` documentary.
3. `≥2` (incl. potential-≥2 via Unknown) invocation floor.
4. Deterministic hint-presence tests are the verification bar (the directive's presence
   is deterministic; acting on it is the same model trust as `EVAL STRATEGY`). No
   behavioral/LLM eval pack required.

## Testing

- `tests/test-context.sh` (or `test-routing.sh`): DESIGN-phase activation context MUST
  contain `TRIFECTA CHECK` and the literal `Skill(auto-claude-skills:agent-safety-review)`;
  SHIP-phase context MUST NOT contain `TRIFECTA CHECK`; REVIEW adversarial hint MUST
  reference `agent-safety-review`.
- `bash -n` on any touched hook (none expected — config-only).
- Existing Fallback Registry Sync Gate guards the dual-source mirror.

## Implementation Notes (synced at ship time)

- **As-built matches the design.** Two config edits (DESIGN `TRIFECTA CHECK` hint +
  REVIEW `ADVERSARIAL REVIEW` check (7)) in `config/default-triggers.json`, mirrored to
  `config/fallback-registry.json`; four deterministic tests in `tests/test-routing.sh`.
  Full suite 60/60; `openspec validate --strict` passes.
- **Deviation (code-review refinement):** the REVIEW check (7) wording was softened from
  "treat unresolved lethal-trifecta mitigation as a blocking governance finding" to
  "treat **unmitigated and unacknowledged** lethal-trifecta risk as a blocking governance
  finding (**the user may still explicitly accept the risk**)". This resolves a tension
  flagged in review with `agent-safety-review` SKILL.md ("architectural review, not a
  pass/fail gate; the user decides"). Spec text is unaffected (it pins behavior, not
  exact wording).
- **Test deviation from plan:** the fast-path regression test uses
  `install_registry_with_wave1` (the registry that actually contains
  `agent-safety-review`) rather than the plan's `install_registry`; this makes the
  assertion meaningful. A dedicated generic-prompt test
  (`test_trifecta_hint_present_on_generic_design`) was added so the always-on guarantee
  (spec Scenario 2) is directly guarded, not just transitively.
- **Codex sparring** corrected a load-bearing premise: `when` clauses on non-plugin hints
  are documentary (the hook emits them unconditionally), so `when:"always"` is metadata
  only — the directive fires regardless.
