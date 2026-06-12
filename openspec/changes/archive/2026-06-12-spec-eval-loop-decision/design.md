# Design: spec→eval loop decision

## The question

Make OpenSpec acceptance scenarios (GIVEN/WHEN/THEN, RFC 2119, in `openspec/specs/<cap>/spec.md`) act as a test oracle, instead of being write-only? Today the PLAN-phase design-guard only greps scenarios for *existence*; `tests/run-behavioral-evals.sh` runs hand-authored `kind:text` (ERE regex over `claude -p` output) / `kind:tool_call` (count) assertions that reference no spec.

## Measurement (the empirical anchor — and a correction)

The loop only adds value a deterministic bash test can't already provide where a scenario describes **probabilistic skill-execution behavior** (only observable by running the SKILL.md via `claude -p`) AND has no backing eval-pack case.

Verified facts:
- **387** `#### Scenario:` blocks across 14 canonical specs. **539** `THEN`/`AND` lines.
- The structural majority (routing selection "X MUST be selected over Y", hook-output strings, jq state, file creation) is already covered deterministically by `tests/test-routing.sh` (369 cases), `test-openspec-state.sh` (62), `test-regex-fixtures.sh`, `test-context.sh` — **no LLM**.
- Existing behavioral packs (top-level JSON arrays): `incident-analysis` **16** cases (11 behavioral + 5 routing), `alert-hygiene` **9**, `supply-chain-investigation` **4**, `format-eval` **6**, `serena`, `model-routing`. **None reference `openspec/specs`** — the two corpora are fully disconnected.

**Correction recorded (Codex caught this; the lead's first measurement was wrong):** The lead's Round-1/early-Round-2 figure of "~3–5 genuinely-uncovered behavioral scenarios" was a significant **undercount**. It counted only capabilities with *zero* packs and used too narrow a verb filter. The corrected count: **68 of 539 `THEN`/`AND` lines use probabilistic free-text model-judgment verbs** (falls back / recommends / explains / classifies / attributes / prioritizes / summarizes …). Netting out pack-covered and deterministically-assertable clauses, the genuinely-uncovered probabilistic surface is realistically **~20–40 scenarios**, not 3–5 — concentrated in:
- `security-scanner` — 19 scenarios, **0** packs.
- `incident-trend-analyzer` — 16 scenarios, **0** packs.
- `incident-analysis` — 61 scenarios vs 16 pack cases (partial, drifted coverage).

This correction reverses the in-house Round-2 convergence, which had moved to "pure defer" *on the strength of the 3–5 figure*. With the true surface ~20–40 and two whole skill-execution capabilities untested, the surface is no longer hand-enumerable and it demonstrably drifts (incident-analysis scenarios outran its pack).

## Decision

- **Reject B and C.** Unaffected by the recount; the 62/272 parse rate and the repo's auto-regex scar tissue are dispositive, and both would weaken the deterministic CI gate. This is the only unanimous, unconditional outcome.
- **Recommend A** (advisory, fail-open, CI-only coverage report) — *rehabilitated* by the corrected measurement. It is the deterministic, low-ceremony tool the repo's own idiom supports (same family as the existing advisory design-guard greps), and it measures linkage, not assertion content, so it sidesteps the NL→assertion problem that kills B/C.
- **Recommend two pack backfills** (`security-scanner`, `incident-trend-analyzer`) regardless of A — these are concrete, currently-untested probabilistic behaviors (e.g. security-scanner's tool-absent LLM-only fallback would pass all 369 routing tests if a SKILL.md edit silently dropped it).

## Dissenting views

- **Critic (held to the end):** even at ~20–40, there is **no logged pain** — no spec/behavior drift has ever caused a recorded miss (verified across CHANGELOG + memory; every drift entry is hook-state, caught by bash tests). Argues the ship-time habit (write a skill's pack when you ship the skill) already plugs the leak, and the ~20–40 is a historical backlog, not an ongoing one. Concludes: write the two missing packs opportunistically, skip the report.
- **Tension to resolve:** A's value is "make the drift visible and prevent the backlog growing." The critic's value is "don't build standing machinery for unlogged pain." The corrected measurement tips this toward A more than the in-house debate concluded, but does not make A unconditional — it is a judgment call the user should make.

## Recommended approach (lead synthesis, post-Codex)

1. **Reject B/C** — final.
2. **Backfill `security-scanner` + `incident-trend-analyzer` behavioral packs** — concrete, bounded (~2–3 cases each on the existing `behavioral.json` schema), closes the two real zero-coverage gaps. Highest value-per-effort; do this regardless.
3. **Build A as an advisory coverage report** — recommended, because the corrected surface is large/drifting enough to justify passive tracking. If the user prefers to wait, defer A behind a pre-committed revival trigger: *uncovered probabilistic surface exceeds ~40, OR a real regression ships from an untested behavioral scenario.*

## Out-of-scope

- Auto-generating assertions (B), constraining scenario format (C), any LLM-judged CI gate, retro-annotating all 387 scenarios.

## Acceptance scenarios (apply only if A + backfills are approved)

#### Scenario: Coverage report surfaces an uncovered behavioral scenario
- **GIVEN** `security-scanner/spec.md` contains a probabilistic `THEN` ("falls back to LLM-only review") with no backing eval-pack case
- **WHEN** the advisory coverage report runs under `BEHAVIORAL_EVALS=1`
- **THEN** the report lists that scenario as uncovered
- **AND** it exits 0 (advisory, never blocks)

#### Scenario: Backfilled pack closes the gap
- **GIVEN** a hand-authored `tests/fixtures/security-scanner/evals/behavioral.json` with a case asserting the tool-absent fallback behavior
- **WHEN** the coverage report runs
- **THEN** that scenario is no longer listed as uncovered

#### Scenario: Report never enters the blocking path
- **GIVEN** the coverage report errors for any reason (missing jq, malformed spec)
- **WHEN** it runs in CI
- **THEN** it fails open (exit 0) and the default `tests/run-tests.sh` suite is unaffected
