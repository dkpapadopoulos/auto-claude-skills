## Why

In a hook carrying `trap 'exit 0' ERR`, a bare `. lib` is a silent early exit: if the lib fails part-way through sourcing, the trap fires and the hook exits 0. In `hooks/openspec-guard.sh` that source sits **above** every deny check, so the failure mode is a silent **allow** — the dangerous direction for a safety gate.

The class had already bitten twice during push-gate-branch-ledger work, and the convention that prevents it ("every sourced lib needs a guard") lived only in auto-memory. Nothing in the repo enforced it: `bash -n` cannot see this (it is a runtime status, not a parse error), and the session-start canary SOURCE-probes only the five `_GATE_ENFORCE_LIBS`, never the call sites that source them.

Measured at HEAD `108a293`: **7 unguarded source lines across 4 ERR-trap hooks**, none covered by any test.

The bypass is not theoretical. Reproduced end-to-end against the real guard before any fix: with `hooks/lib/session-token.sh` returning 1 mid-source, a `git push` payload produced **empty stdout — no `permissionDecision` at all**, which the harness cannot distinguish from an allow.

## What Changes

- **Deterministic lint** (`tests/test-hook-source-guards.sh`): enumerates `hooks/*.sh` carrying an ERR trap, classifies each `.`/`source` line, and fails on any unguarded one outside an explicit allowlist. A source that is a non-final operand of an `&&`/`||` list cannot trip the trap and is treated as guarded.
- **Committed red/green fixtures** (`tests/fixtures/hook-source-guards/`): a hook copy with an unguarded source of a lib that `return 1`s mid-source, and the same hook with the source guarded. The lint must flag the first and not the second; executed, the red one must fail to reach its deny decision and the green one must reach it.
- **Two gate-critical lines fixed** in `hooks/openspec-guard.sh` (the session-token source above the deny checks, and the consol-marker source below them). The other five pre-existing violations are allowlisted with reasons.

## Capabilities

### Modified Capabilities

- `pdlc-safety`: the push-gate hook must not fall open when a sourced lib fails, and the repo must deterministically reject any new unguarded source in a fail-open hook.

## Impact

- `hooks/openspec-guard.sh` — two source sites converted to the guarded form. No change to any decision path, message, or gate ordering; the only behavioural difference is on a failing source, where the hook now proceeds to its fallback instead of exiting 0.
- `tests/test-hook-source-guards.sh`, `tests/fixtures/hook-source-guards/` — new.
- `CHANGELOG.md`, `CLAUDE.md`.
- No change to `_GATE_ENFORCE_LIBS`, the canary manifest, or the drift manifest — this adds a test, not a gate-enforcement lib.

Verified: the eight gate-adjacent suites (`test-push-gate-*`, `test-skill-gate`, `test-session-token-race`, `test-evaluator-surface`) stay green at 262 assertions, and the new test is red against the pre-fix tree.
