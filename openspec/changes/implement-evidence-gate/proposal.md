## Why

The composition chain enforces REVIEW and VERIFY at the push/merge boundary (`openspec-guard.sh`), but **IMPLEMENT has no evidence requirement**. A session proved the gap: the model chose "inline execution," did the entire implement→review→verify work with raw Write/Edit/Bash tools plus a review subagent, and invoked NONE of the process skills. Consequences: (a) `skill-gate.sh` only fires when a *later* skill is invoked, so a fully-manual workflow never trips it; (b) nothing required evidence the IMPLEMENT phase ran; (c) the push gate held only because REVIEW/VERIFY were missing — had those been present, the methodology (TDD) would have been silently skipped with a clean ship.

Separately, the verdict proves tests **pass** at HEAD but not that tests **exist** for the change — a source change with zero new tests and a green suite is invisible to the current gate.

This change closes the IMPLEMENT hole at the boundary that already works, reinforces the behavioral first line so the gate rarely needs to fire, and adds a deterministic test-delta signal — each shipped **warn-first and proven before deny**, per this repo's backtest discipline (deny variants that shipped without a backtest ran 56–94% false-block and were disabled).

## What Changes

1. **IMPLEMENT-evidence leg on the push/merge gate** (`hooks/openspec-guard.sh`). Mirrors the REVIEW/VERIFY checks: when an implementation-slot skill (`executing-plans` / `subagent-driven-development` / `agent-team-execution`) is in the active chain and the push's diff touches material source (`hooks/`, `config/`, `scripts/`, `skills/`, code files — not docs-only), the gate requires IMPLEMENT evidence: a real invocation record, branch-ledger, bridge, **or an explicit `phase_attest executing-plans` attestation** (auditable escape valve). **Ships warn-first** (advisory + telemetry, no deny); flips to deny in this repo only after the forward shadow corpus satisfies the pre-registered rule in `openspec/changes/implement-shadow-event/design.md` (Pre-registration). **Corrected 2026-07-28 (issue #160):** this originally named `scripts/phase-gate-backtest.sh`, which replays the skill-sequencing gate, not this leg — it cannot produce the evidence this gate requires.

2. **`executing-plans` hint → CURRENT-step PRECONDITION** (`config/default-triggers.json` + `config/fallback-registry.json`). Adds a `precondition` to the `executing-plans` composition entry instructing invocation of an implementation-slot skill BEFORE editing code, with the attestation escape. Config-only (the activation hook already renders `precondition`). Uptake proven via a control-vs-treatment behavioral A/B eval (the #104 hint→precondition playbook) before the config lands.

3. **Deterministic `test_delta` verdict dimension** (`scripts/verify-and-record.sh` + `hooks/lib/verdict.sh` reader). Records `test_delta: covered | missing | n/a` — whether a material source change is accompanied by a test change. Advisory in v1 (recorded in the verdict, surfaced in the report; NOT deny-wired). Rides the verdict's existing sha-binding and tamper-detection.

## Capabilities

### Modified Capabilities
- `pdlc-safety`: extends phase-transition enforcement with an IMPLEMENT-evidence leg on the outbound push/merge gate (warn-first, attestation-accepting, material-source-scoped), an `executing-plans` CURRENT-step precondition, and a deterministic `test_delta` verdict dimension.

## Impact

- `hooks/openspec-guard.sh` — new IMPLEMENT leg (warn-first) alongside the REVIEW/VERIFY checks; reuses `_ledger_has`/`_invoc_ok`/`_bridge_has` + attestation; material-source diff classification.
- `hooks/lib/phase-evidence.sh` — implementation-slot alias set already exists (`_phase_alias_candidates`); reused, not duplicated.
- `config/default-triggers.json` + `config/fallback-registry.json` — `precondition` on `executing-plans` (paired edit; source-of-truth rule).
- `scripts/verify-and-record.sh` + `hooks/lib/verdict.sh` — `test_delta` dimension (writer + reader).
- Tests: `tests/test-push-gate-*.sh` (IMPLEMENT leg), `tests/test-registry.sh` (precondition present + triggers compile), `tests/test-verdict-lib.sh` / verify-and-record coverage (`test_delta`).
- `CLAUDE.md` gotcha + `CHANGELOG.md`.
- Validation artifacts: A/B eval pack for the precondition; backtest run for the IMPLEMENT leg + test-delta.
