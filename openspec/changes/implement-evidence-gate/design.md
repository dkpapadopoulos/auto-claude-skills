# Design — IMPLEMENT-evidence gate + precondition + test-delta

## Context

Enforcement today is layered: the **walker** (`skill-activation-hook.sh`) advances `.completed` on trigger matches (display/recovery state, forgeable — never a trust boundary); the **completion hook** writes append-only invocation-evidence + branch-ledger on a real Skill return; **`skill-gate.sh`** denies out-of-order Skill invocations; **`openspec-guard.sh`** denies push/merge without REVIEW+VERIFY evidence. Quality-of-work is already enforced deterministically: `verify-and-record.sh` writes an honest-by-construction verdict (`failed[]`, `could_not_verify[]`, `gate_gaming_status`, HEAD `sha`); push-gate verify-hardening denies a push when the verdict *at HEAD* reports a test failure.

The gap: IMPLEMENT is unenforced at the boundary, and "tests exist for the change" is unmeasured.

## Architecture

Three independent units, each shippable and testable alone:

### Unit A — IMPLEMENT-evidence leg (push/merge gate)
A new check in `openspec-guard.sh`, structurally identical to Check-1/Check-2 (REVIEW/VERIFY). Predicate: `_impl_in_chain` (any implementation-slot alias present in `.chain`) AND material-source diff AND NOT `_impl_completed`. Evidence resolution reuses `_ledger_has` / `_invoc_ok` / `_bridge_has` over the alias set (`_phase_alias_candidates executing-plans`), **plus attestation** (`phase_attested`). Two deliberate departures from REVIEW/VERIFY:
- **Accepts attestation.** IMPLEMENT is not a gating milestone; `phase_attest executing-plans "<reason>"` satisfies it. Rationale: converts a silent bypass into an auditable, review-surfaced one, and is the escape valve for legitimate no-implementation pushes (docs, pure refactor, hotfix). Cost: attestation proves a decision was recorded, not that TDD happened — the honest ceiling.
- **Material-source-scoped.** Fires only when the diff touches non-docs source. Reuses the guard's src-vs-docs classification (docs = `docs/**`, `openspec/**`, `*.md`; src = everything else). A docs-only push never triggers it.
- **Warn-first.** Emits `additionalContext` + a `phase_gate_log` telemetry line; NO `permissionDecision:deny`. Flips to deny in this repo only after backtest clears <10% false-block.

### Unit B — `executing-plans` precondition (config)
A `precondition` string on the `executing-plans` composition entry in both config files. The activation hook already renders `precondition` into the CURRENT-step block. No hook code. Text instructs: invoke an implementation-slot skill BEFORE editing code; if deliberately skipping, `phase_attest executing-plans "<reason>"`.

### Unit C — `test_delta` verdict dimension
`verify-and-record.sh` computes, for the change under verification (diff vs merge-base or a provided range), whether material source edits are accompanied by test-file edits (test globs from the declared gate; `tests/*.sh` here). Records `test_delta: covered | missing | n/a`. `verdict.sh` gains a reader (`verdict_test_delta`). Advisory in v1 — surfaced in the report and stored in the verdict; not deny-wired.

## Trade-offs

- **Boundary vs edit-time enforcement.** We gate at push/merge, NOT at Write/Edit. A Write/Edit gate cannot distinguish a failing test from production code from a review-fix from a doc edit (false-block regime), and one token Skill invocation defeats it. Cost: the bypass stays open until push — accepted, because the Stop-hook alarm (future) and the precondition catch it earlier behaviorally.
- **Attestation escape.** Keeps false-blocks near zero at the cost of not proving TDD. Accepted: auditable-bypass >> silent-bypass, and TDD-proof is behavioral regardless.
- **Warn-first delay.** The hole stays open during the measurement window. Accepted: shipping an unmeasured deny is precisely the failure mode (56–94% false-block) this repo has already paid for.

## Dissenting views

- **Codex (sparring):** ranked the Write/Edit gate a hard no (false-block regime, trivially defeated) and cautioned that making `executing-plans` a push milestone "closes the hole or moves it" — attestation moves silent→auditable but does not prove compliance. Adopted: attestation-accepting, warn-first, boundary-only.
- **Alternative rejected:** gating all 7 chain steps. `finishing-a-development-branch` is UX, `openspec-ship` is conditional (docs/spec mode), and DESIGN/PLAN stay warn-only until separately backtested. Gating them would be theater.

## Decisions

1. Gate at the push/merge boundary, not Write/Edit. (D-1)
2. IMPLEMENT accepts attestation; REVIEW/VERIFY never do. (D-2)
3. Warn-first; deny only after the forward shadow corpus meets the pre-registered rule in `implement-shadow-event/design.md` (Pre-registration), this-repo-only. Originally named `phase-gate-backtest.sh` — corrected per issue #160; that script measures the skill-sequencing gate. (D-3)
4. `test_delta` advisory in v1; deny-wiring is a separate future change behind its own backtest. (D-4)
5. Reuse the existing implementation-slot alias set and evidence helpers; add no parallel machinery; `.completed` stays untrusted. (D-5)

## Verification strategy (deterministic + one behavioral A/B)

- **Units A & C are deterministic** → TDD + the acceptance scenarios in the delta spec. Red tests first.
- **Unit B is behavioral** → control-vs-treatment A/B eval: metric = fraction of implementation-phase prompts where the model invokes an implementation-slot skill before the first source edit; ship only if treatment materially beats control with no safety regression (#104 precedent: 0/5 → 5/5).
- **Unit A deny-flip is evidence-gated** → the forward shadow corpus (`~/.claude/.push-implement-shadow.jsonl`), human-adjudicated per the Pre-registration in `implement-shadow-event/design.md`; flip only when that rule is met. Originally specified as a `phase-gate-backtest.sh` run — corrected per issue #160 (wrong gate), and a *retrospective* replay is separately infeasible: the leg's predicate needs evidence state as it stood at each historical push, and the ledger is overwritten in place rather than appended.
- **Unit C fire-rate** measured on the same backtest corpus before any future deny-wiring.

## Autonomy / governance

The artifact is a deny-gate (execute-reversible: denies tool calls, fully reversible, human-configurable mode, attestation escape). Proportional oversight: warn-first + backtest + attestation. It **strengthens** a safety gate and touches `hooks/` + `config/`, so REVIEW MUST run `agent-team-review` (adversarial-governance lens). No lethal-trifecta (no private-data/untrusted-input/outbound-action).
