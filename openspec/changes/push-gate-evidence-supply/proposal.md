# Proposal: supply the evidence the push gate demands, and stop logging bypasses as allows

## Why

The push gate denies ~46% of gated commands (97 of 210 recorded invocations) and
the work ships anyway. Investigation found no gate bug — **97 of 97 denies replay
as `deny` against the on-disk guard** — but three defects that are not in the
guard's decision logic at all.

**1. ACS's own SHIP composition never asks for the artifact its own gate requires.**
`project-verification` is the only skill that writes the sha-bound verification
verdict that `routing-governance` and `verify-hardening` read. It appears in
**zero** `phase_compositions` (jq-verified). It exists only as a REVIEW-phase
`role: domain` skill behind a narrow regex trigger. The SHIP sequence is
`deploy-gate → runtime-validation → implementation-drift-check → openspec-ship →
/commit → finishing-a-development-branch → write-learn-baseline` — the verdict
producer is absent. The chain and the gate disagree about what SHIP owes.

This was initially misdiagnosed as an ACS/Superpowers integration gap. It is not:
`hooks/skill-completion-hook.sh:46` strips the plugin prefix (`_BARE="${_RAW##*:}"`)
and `:153` records it, so `Skill(superpowers:requesting-code-review)` already writes
the exact branch-ledger record the gate reads. The bridge works. The omission is
inside ACS's own config.

**2. The env bypass is logged as an ordinary allow.** `_PUSHGATE_SKIP=true` is set
at `hooks/openspec-guard.sh:512`, `_DECISION="allow"` at `:527`, and the capture
EXIT trap is armed at `:552` — after both. So an `ACSM_SKIP_PUSH_GATE=1` push
already writes a capture record, labelled `allow` and indistinguishable from a
genuine one. Every conversion figure computed from that log is therefore unsound,
including the ~50% measured during this investigation.

**3. The REVIEW leg's evidence is structurally unobtainable.** This repository has
exactly one collaborator (`dkpapadopoulos`) and GitHub forbids approving your own
pull request, so `reviewDecision: APPROVED` is unreachable — not merely absent.
All 7 sampled bypassed-and-merged PRs (#236, #227, #233, #221, #196, #222, #214)
carried **zero** reviews. The gate was accurate about a condition that cannot be
remedied through the channel it names.

## What Changes

Ordered. Item 1 ships alone, because items 2-4 rest on numbers it corrects.

1. **Relabel the env bypass** — set `_DECISION="bypass:env"` when `_PUSHGATE_SKIP`
   is true, so a bypass stops masquerading as an allow. One line plus one assertion.
   This is a mislabel correction, not new instrumentation: the record already exists.
2. **Add `project-verification` as the first step of the SHIP sequence** in
   `config/default-triggers.json` and `config/fallback-registry.json`. Data only —
   sequence entries render through an existing jq path; no hook code, no new predicate.
3. **Enable branch protection on `main`** with Done Gates required, leaving the
   `review` check optional.
4. **Record a default-demote date** for the gate: 2026-10-07.

Also: correct the stale comment at `scripts/verify-and-record.sh:53`, which claims
"this repo's suite runs ~3 minutes" for a suite measured at **943 seconds**.

## Capabilities

- **MODIFIED** `pdlc-safety` — push-gate telemetry distinguishes a bypass from an allow.
- **MODIFIED** `skill-routing` — the SHIP composition requests the verification verdict.

## Impact

- `hooks/openspec-guard.sh` — one assignment after `:527`. No change to any deny
  predicate, deny site, or evidence read. The decision logic is untouched.
- `config/default-triggers.json`, `config/fallback-registry.json` — one SHIP
  sequence entry each.
- `scripts/verify-and-record.sh` — comment only.
- `tests/test-push-gate-capture.sh`, `tests/test-context.sh`, `tests/test-routing.sh` —
  assertions.
- GitHub branch-protection settings (not a code change).

No new skill, so the repo's two done-gates (`test-fixture-coverage.sh`,
`test-skill-content-coverage.sh`) bind on nothing new. No `predicate_version` bump,
so the IMPLEMENT shadow corpus is not reset for a fourth time.
