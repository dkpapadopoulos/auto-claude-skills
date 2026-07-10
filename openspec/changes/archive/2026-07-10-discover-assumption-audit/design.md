# Design: DISCOVER Assumption Audit

Full design trail (adoption triage of the 21-skill pack, loop-taxonomy framing,
Codex adversarial critique + verified verdicts):
`docs/plans/2026-07-10-discover-assess-ledger-design.md` (v3, session-local).
This file records the committed architecture and decisions.

## Architecture

Four independent pieces, no shared runtime state:

1. **Skill layer** — `skills/product-discovery/SKILL.md` gains an "Assumption
   Audit" stage between context gathering and user validation (~20 lines),
   delegating rubric/schema/worked example to
   `skills/product-discovery/references/assumption-audit.md`. The stage writes
   an `## Assumption Ledger` section into the discovery doc
   (`docs/plans/YYYY-MM-DD-<slug>-discovery.md`). No new session-state writers:
   the discovery doc is the single source of truth in v1; hypotheses continue
   through the existing `openspec_state_set_hypotheses` path unchanged.
2. **Checker** — `scripts/assumption-audit-check.sh <discovery-doc>` parses the
   ledger deterministically (Bash 3.2, jq-free, fail-open on missing file /
   unreadable doc; exit 1 only on parsed violations). The skill instructs
   running it before presenting the brief; it is also directly testable.
3. **Routing companion** — one `methodology_hints` entry (phases: DESIGN) in
   `config/default-triggers.json` mirrored to `config/fallback-registry.json`.
4. **Evals** — deterministic red fixtures for the checker (planted
   grade-inflation ledger MUST fail before the checker is trusted) + one opt-in
   behavioral scenario (D-grade pushback).

## Decisions

- **Name**: "Assumption Audit", NOT "ASSESS" — collides with the hook's
  "ASSESS PHASE" routing vocabulary (`hooks/skill-activation-hook.sh:1008`,
  asserted by tests).
- **Home**: inside `product-discovery`, not a new skill (a second DISCOVER
  process skill fights the max-1-process role cap) and not a hint (hints are
  unenforceable appended context). Routing gap for "build X" prompts that
  never hit DISCOVER is covered by the DESIGN-hint companion.
- **Grade-inflation control is structural, not prose**: the evidence-ceiling
  rule binds `claimed_grade` to machine-checkable `evidence_kind` + greppable
  `source_ref`. Repo doctrine: self-rated confidence is advisory only.
- **Two-step validation** doubles as the anti-weight-backfill mechanism:
  criteria/weights are user-confirmed before scores exist in the conversation.
- **Checker is local, not CI**: `docs/plans/` is gitignored (`.gitignore:4`).
  Spec-driven repos can later echo the ledger into committed openspec docs.

## Trade-offs

- Presence-not-quality bar for the ledger (an earnest-but-shallow ledger
  passes): consistent with the repo's other done-gates; quality stays human.
- Two-step validation adds a turn of friction; mitigated by proportionality
  (model-judged skip for declared-small work) and the dogfood kill criterion.
- Checker parses a markdown table by convention — brittle to creative
  formatting; mitigated by the references/ template being the single format
  the skill emits.

## Implementation note (post-review annotation)

- R2's "surfaced against user push" scenario is met by model-native behavior
  plus the Step-4 fragile-assumption quadrant; no dedicated anti-sycophancy
  prose was added — the writing-skills control arm was already at ceiling on
  that behavior (Iron Law stop rule), so a red-first eval cannot show lift.
  The spec's MUST stands as written.

## Dissenting views

- Codex argued the strongest case against in-skill placement (routing reach);
  accepted as real, mitigated via the DESIGN hint rather than relocation.
- Autonomy-assumptions-in-ledger (loop-article extension) was cut as scope
  creep — no current reader; DESIGN autonomy hint + agent-safety-review Step
  2b already cover the principle. Revive only when a consumer exists.

## Out-of-Scope

- Session-state ledger persistence (non-atomic RMW helpers; known race
  history).
- Decision-drift agent judge (deferred behind the artifact existing and being
  used in anger).
- LEARN-phase baselines for hold/kill outcomes.
- CI enforcement of the ledger.
- Any engagement-lift measurement claims.

## Capabilities Affected

- `pdlc-closed-loop` (discovery brief structure, validation interaction).

## Acceptance Scenarios

See `specs/pdlc-closed-loop/spec.md` in this change.
