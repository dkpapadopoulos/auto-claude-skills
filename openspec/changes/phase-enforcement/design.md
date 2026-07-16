# Design: phase-enforcement

## Architecture

Two deny boundaries, one attestation escape, one measurement instrument:

```
UserPromptSubmit  (skill-activation-hook.sh)   — unchanged: renders chain,
                                                 advances non-gating prefix
PreToolUse ^Skill$ (skill-gate.sh, NEW)        — C1 sequencing deny at
                                                 invocation time
PreToolUse Bash    (openspec-guard.sh, EXT)    — C2 DESIGN/PLAN evidence joins
                                                 REVIEW/VERIFY at push/merge
PostToolUse ^Skill$ (skill-completion-hook.sh) — unchanged: writes the
                                                 invocation evidence gates trust
```

C1 decision procedure (deny only on positive violation evidence):
1. Resolve token payload-first; read `.skill-composition-state-<token>`.
   No state / malformed / empty chain → ALLOW (exit 0, no output).
2. `tool_input.skill` (bare name, strip plugin prefix — same normalization as
   the completion hook) not in `.chain` → ALLOW.
3. Skill at chain index i: for each required predecessor j<i, satisfied if in
   `.completed` OR `branch_ledger_has` OR attested in
   `.skill-phase-attest-<token>`. First unsatisfied predecessor → DENY with
   remedy: "PHASE GATE — Step <j> (<skill>) has no invocation evidence. Do
   now: invoke Skill(<skill>), or record an explicit skip:
   `phase_attest <step> "<reason>"` (logged and surfaced at REVIEW). Human
   bypass: run the command yourself with the ! prefix."
4. Re-invocation of an already-completed or the current step → ALLOW.
5. Every decision appends one line to `~/.claude/.phase-gate-events.log`:
   `<ts> gate=skill-seq decision=<deny|allow|attest-satisfied> skill=<s> missing=<j>`.

C2: inside the existing chain-scoped push checks, after REVIEW/VERIFY:
`brainstorming` and `writing-plans` checked against the same three evidence
sources; deny message mirrors the push-gate remedy shape. Mode resolved from
config (`deny|warn|off`); the deny mode may ship only after the backtest
clears it (below).

Attestation (`hooks/lib/phase-attest.sh`): `phase_attest <step> <reason>`
writes/merges `~/.claude/.skill-phase-attest-<token>` (jq map, tmp+mv atomic
write). HARD EXCLUSION list (`requesting-code-review`,
`verification-before-completion`) is a hardcoded invariant in BOTH the helper
(refuses to write) and the consumers (refuse to read) — two independent locks,
mirroring the max_iterations role-allowlist precedent. The gate-status block
and the REVIEW-phase output render active attestations verbatim so a skipped
step is always visible to the human and the review lens.

Backtest (`scripts/phase-gate-backtest.sh`): walks
`~/.claude/projects/<slug>/*.jsonl` transcripts, extracts Skill tool_use
events in order, replays chain state per session, evaluates each candidate
predicate, emits a table: would-have-denied, of which true-catch (a real
skip: later evidence shows the step never ran) vs false-block (step ran
later in-turn, or work was legitimately non-chain). Pre-registered
thresholds (discovery brief): deny ships <10% FB; 10–20% narrow; >20% advisory.

## Trade-offs

- **Deny-on-positive-evidence vs fail-closed (push-gate style):** early-phase
  state is noisier than outbound state; a fail-closed C1 would deny on every
  malformed/missing state file and burn trust. The push gate keeps its
  fail-closed posture; C1 inverts deliberately. Accepted residual: a wiped
  state file lets a skip through C1 — it is still caught at C2/push.
- **Attestation vs pure hard-deny:** "new initiative?" and "trifecta ≥2?" are
  model-judged predicates; a pure deny on them either false-blocks mechanical
  work or forces the model to fake a chain. Attestation keeps the deny
  deterministic while converting silent skips into logged, review-surfaced
  decisions. Risk — attestation spam — is bounded by logging, REVIEW
  surfacing, and the gating-milestone exclusion; dogfood telemetry measures it.
- **PreToolUse ^Skill$ vs Edit/Write gate:** the Skill boundary is precise and
  rare (a few calls/session) with near-zero false-block surface; Edit/Write
  fires constantly and its analogue backtested at 56–94% false-block. O3
  stays unbuilt behind the double threshold (<10% FB AND ≥1 true catch).
- **Config default warn for external consumers:** their chains/workflows are
  unmeasured; shipping deny-by-default externally repeats the mistake the
  A2 backtest exists to prevent.

## Dissenting views

- Prior repo doctrine (design-plan-guard v2, PR #114 backtest) argued against
  early-phase hard denies wholesale. This design narrows the deny to the
  Skill-invocation boundary where the false-block surface is structurally
  small, keeps the doctrine's instrument (backtest + probation + kill
  criterion) for everything wider, and is driven by an explicit user
  directive that supersedes the default posture.
- Codex sparring is scheduled at design review; a two-sided architecture
  split did not materialize during discovery (options scored 4.25 vs 4.10
  with the same instrument).

## Decisions

- Evidence sources for "step done" are exactly the push gate's:
  `.completed` ∪ branch ledger, plus the new attestation map — one shared
  predicate helper (`hooks/lib/phase-evidence.sh`) consumed by C1 and C2 so
  the two boundaries cannot drift.
- Skill-name normalization reuses the completion hook's bare-name rule
  (strip `plugin:` prefix) — same skill, same name, both directions.
- Review-embedding skills (subagent-driven-development,
  agent-team-execution) already credit `requesting-code-review`; C1 treats
  them as valid REVIEW-step evidence identically (no new mapping).
- 4-week dogfood on this repo with `deny`; kill criterion >10% user-judged
  false-blocks per predicate → demote that predicate to `warn`.
- H2 uptake eval (step-text promotion) is red-first with a pinned judge,
  reusing the behavioral-eval runner.

### Sparring amendments (codex adversarial pass, 2026-07-16)

- **Provenance split (codex #2, Critical):** the gates MUST NOT trust the
  walker-maintained `.completed` — the walker back-fills non-gating steps on
  trigger matches (anchoring ≠ invocation; a "continue implementing" prompt
  would fabricate DESIGN/PLAN evidence). The completion hook gains an
  append-only invocation record (`.skill-invocation-evidence-<token>`,
  written only on successful Skill returns) and records ALL chain-step
  returns to the branch ledger (previously gating milestones only — this
  also fixes re-anchor erasure of legitimate prior evidence, codex #4).
  Evidence = invocation record ∪ ledger ∪ attestation.
- **Implementation-slot aliases (codex #3, Critical):** `executing-plans`,
  `subagent-driven-development`, `agent-team-execution` are one canonical
  slot in membership and evidence checks — invoking a sibling of the
  chain's rendered implementation skill cannot bypass sequencing.
- **C2 warn is telemetry-only (codex #1 / independent convergence):** the
  guard emits at most one JSON object per run; warn mode logs to the events
  file (+ SKILL_EXPLAIN stderr) and never writes stdout. A combined
  regression pins C2-warn + routing-governance-deny emitting exactly one
  deny object.
- **Attestation surfacing (codex #5):** the activation hook renders active
  attestations under the composition block on every prompt — not just in
  logs. Reason-quality policing stays human (REVIEW) — rejected the
  "reason must name evidence" extension as YAGNI.
- **Chain-covered predicate (codex #6):** C2 scope = active chain includes
  `brainstorming` OR the branch ledger carries `brainstorming`/
  `writing-plans` records (covers comp-state resets between sessions).
- **Dogfood identity (codex #8):** default-deny keys on the plugin
  manifest name (`.claude-plugin/plugin.json` name == `auto-claude-skills`),
  not on a generic path that external repos may legitimately have.
- **Backtest labeled advisory-only (codex #7, partial):** replay error is
  bidirectional (errored Skill returns counted as evidence; ledger and
  attestation state invisible); output is labeled accordingly and every
  DENY line is human-classified — full state replay rejected as
  disproportionate for a one-shot calibration instrument.

## Out-of-Scope

- Edit/Write PreToolUse deny (O3) — revival: backtest <10% FB AND ≥1 true catch.
- Enforcing non-chain sessions, DEBUG detours, or mechanical edits.
- Artifact-quality judgment (review's job), cross-repo branch-binding,
  new skill authoring, changes to walker scoring/routing.

## Capabilities Affected

- `pdlc-safety` (modified): phase-transition enforcement joins push-gate
  milestone integrity.

## Acceptance Scenarios

See `specs/pdlc-safety/spec.md` (4 scenarios: sequencing deny + remedy,
attestation path, gating-milestone exclusion, scoping/fail-open).
