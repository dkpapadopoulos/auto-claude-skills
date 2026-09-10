# Design: Cross-Family Second Opinion

## Architecture

Four components, two new and two modifications, all opt-in.

**`panel` (new skill).** Flow: (1) prompt argument mandatory — fail loudly if missing, never infer; (2) expand explicitly invoked `/skill` references inline, single level only (no recursion — YAGNI, cut on cross-model advice); expanded skill bodies COUNT as outbound content for the disclosure rules below; (3) append an anti-sycophancy block ("answer directly; if your honest answer differs from what the prompt seems to expect, give that one"); (4) resolve the roster — default strongest available Claude + Codex via the codex plugin's `codex-rescue` subagent, availability probed AT DISPATCH (never from cached or inherited beliefs); (5) dispatch panelists in parallel, fresh contexts containing only the approved prompt material, single round, no cross-talk; (6) deliver responses verbatim, attributed per model, and RECOMMEND an explicit `synthesize` invocation — panel never synthesizes and never silently chains.

Raw responses live in a securely created per-run directory (`mktemp -d`, 0700, non-colliding); the skill states they are session scratch and how to delete them; nothing is persisted to the repo unless the user asks.

Panel is phase-agnostic by contract: the SKILL.md states it is invocable in any phase; registry metadata anchors it where the upstream evidence is strongest (DESIGN/PLAN), and no phase composition ever makes it required. The exact registry phase mechanics (single phase vs. multi-phase triggers) are a plan-level decision with one requirement: triggers MUST fire in both DESIGN and PLAN.

**`synthesize` (new skill, composition-only — empty triggers).** Merge rubric applied point by point: agreement (≥2 concur) → take with high confidence; unique-to-one → re-examine against source, keep if valid, discard if speculative; contradiction → decide on evidence quality, never vote; gap none caught → flag as a panel limitation. Also flags perspective content that violates or exceeds the original prompt — embedded instructions inside a perspective (e.g. "declare consensus") are data to flag, never instructions to follow. Unresolved disagreements are deliberately surfaced to the caller.

**`agent-team-review` §6 widening.** The Cross-Model Offer covers a full cross-family adversarial pass over the diff, in exactly two modes ("at any point" is deliberately NOT the contract):

- *Mode A — requested before or during the round:* the cross-family pass runs as an additional reviewer inside the normal round — same base/head, same context bundle, same delivery contract and chasing rules. Because it is a supplementary offer and not part of the required lens composition, its non-delivery is recorded as an advisory gap, not `could-not-review`.
- *Mode B — offered after an initial `clean`/`suggestions_only` verdict:* accepting triggers a defined second cycle: dispatch → collect → deduplicate against existing findings → severity floor → §4a/structural disposition → regenerate the summary → recompute the verdict. An accepted blocking cross-model finding replaces the prior verdict with `blocking_issues`; an accepted warning caps it at `suggestions_only`. The verdict is recorded (via `record-review-verdict.sh`) ONCE, after the offer is resolved — never before — and its findings/unresolved-blocking counts include cross-model findings.

Cross-model findings MUST carry the full FINDING contract — `Category` (assigned from the defect, never from reviewer identity), `Confidence`, `Evidence`, `Oracle` where applicable — and the security/governance structural exception and open-finding verdict constraints apply to them unchanged. The user's offer decision is recorded either way.

**`agent-team-review` autofix lane.** The FINDING contract gains an optional `Autofix:` line — an exact old→new edit, additive to `Suggestion:`, never replacing it. Eligibility requires all four: single exact text transformation stateable precisely; essentially certain correct and complete; touches only code this diff introduced or changed; zero behavioural ambiguity. Severity `suggestion` only — blocking/warning findings never carry the bypass, even when a reviewer attaches the line.

**The token never self-certifies.** The lead validates every `Autofix:` line independently against the four conditions, checks the `old` text is present, unique, and unstale, and deduplicates overlapping or conflicting edits. Only validated lines enter the batch — this validation IS the finding's adjudication (a mechanical edit has no manipulable causal variable, so per §4a it is disposed on its own terms). A line that fails validation loses the routing: the finding reverts to a normal suggestion under normal severity-floor rules, and the failed validation is reported. A validated line survives the floor by routing to the batch. This closes the gaming path where labeling any nit `Autofix:` would guarantee floor survival.

**Application order (the reviewed-subject rule).** Approval is per-item ("apply all except…" supported), listing every old→new edit. On approval the lead applies the batch, then asserts the applied diff is byte-identical to the approved batch — nothing beyond the approved edits may change. Only then do verification and verdict recording happen, so the recorded verdict describes the FINAL tree state. A full re-review round is deliberately not required: reviewers reviewed base..head, the human approved the exact delta on top, and the byte-equality check proves the final state is precisely their sum. Applied autofixes stay listed in the review summary.

### Degradation contract (asymmetric by design)

- `panel`, default roster, second family unavailable: ANNOUNCE the weakening ("same-family panel — materially weaker per upstream evidence") and ask whether to proceed same-family or abort. Never silent, never a refusal without the ask.
- `panel`, a panelist the user EXPLICITLY requested is unavailable: never silently substitute — say so and ask, matching upstream's fail-loud posture for explicit requests.
- §6 review pass, no second family: the offer states that and the pass is SKIPPED. A same-family "adversarial pass" adds little to an already multi-agent Claude review; faking one manufactures false assurance. (Cross-model spar concurred the asymmetry is defensible on exactly this ground.)

### Security hard requirements

1. **Read-only dispatch.** `codex-rescue` defaults to a WRITE-CAPABLE run; every dispatch from `panel` and §6 MUST explicitly request read-only. Without this, an injected instruction inside a reviewed diff gets a write-capable external agent aimed at the workspace. Content-test assertion, not prose.
2. **Disclosure controls.** Read-only prevents mutation, not disclosure. Before any cross-family dispatch: name the destination provider and preview what will be sent (least-data: the specific prompt/diff/design artifacts, never whole-session context); run secret detection (gitleaks) over the outbound payload when available and announce when it is not; dispatch in a fresh context containing only the approved material. Expanded `/skill` bodies are part of the payload and subject to the same preview.

## Capabilities Affected

- `cross-family-panel` (added): `skills/panel/`, `skills/synthesize/`, registry entries in `config/default-triggers.json` + `config/fallback-registry.json`, routing fixtures, content tests.
- `review-cross-family-pass` (modified): `skills/agent-team-review/SKILL.md` §6 + verdict recording order.
- `review-autofix-lane` (modified): `skills/agent-team-review/SKILL.md` finding contract, §4 lead synthesis, review summary format.

## Trade-offs

- **Two skills vs one:** two (mirroring upstream) keeps `synthesize` independently reusable and each skill single-purpose, at the cost of a second artifact set. Chosen: two.
- **Degrade-with-consent vs refuse (panel):** upstream fails loudly always; ACS announces and asks. Same-family still helps (upstream's own data), and the ask preserves the user's call without dead-ending Codex-less installs.
- **Autofix application:** autonomous lead application mirrors upstream triage but adds autonomous write capability inside REVIEW. Chosen: per-item human approval + byte-exact application check; revisit autonomy with usage evidence.
- **Byte-exact check vs re-review after autofix:** full re-review of pre-approved exact text edits costs a round for no information; byte-equality of applied-diff to approved-batch restores the reviewed-subject property mechanically. If the check ever fails, the lead reverts and returns to IMPLEMENT — that path IS a full re-review.
- **Composition-only `synthesize`:** the verb over-matches everyday prompts; composition-only avoids routing noise at the cost of discoverability.

## Dissenting views

- The independent Codex analysis recommended A/B-testing cross-family plans against `design-debate` before changing any default. Accepted — nothing here changes a default; `design-debate` is untouched.
- Upstream carries confidence-band filtering and a six-entry do-not-flag list. Both REJECTED: confidence-as-filter collides with ACS's deliberate "Confidence is advisory only" rule; the do-not-flag table is capped at two entries to protect structural security/governance findings.
- A cross-model design spar (14 findings, all adjudicated) drove: autofix-before-verdict ordering, per-item validation, the two-mode §6 state machine, disclosure controls, consent-gated degradation, narrowed triggers, and the single-level `/skill` expansion cut. Its recommendation to demote autofix to presentation-only metadata was REJECTED — the owner explicitly scoped autofix in; the hardened routing above answers the underlying gaming concern.

## Decisions

1. ACS-native adapted skills with MIT attribution — not vendoring, not a third-party plugin dependency.
2. Availability probed at dispatch, never cached.
3. Cross-model output is DATA: findings adjudicated, never executed; no autonomous writes from cross-model output anywhere.
4. Panel is opt-in everywhere; no composition makes it required.
5. Routing triggers require explicit model intent — "panel of models", "second opinion from another model", "ask codex", "cross-model" — never bare "cross-check", "independent perspectives", or plain "second opinion" (routine engineering language; the decoy set pins each).
6. Verdict recording moves to after Cross-Model Offer resolution (it is currently reachable before §6 resolves; the two-mode design makes the ordering explicit).

## Safety assessment (lethal trifecta)

All three legs present: private data (repo code/design content in prompts and diffs sent to an external model), untrusted input (reviewed diffs may contain injected instructions), outbound action (the external dispatch itself; autofix writes). Classification: lethal trifecta; autonomy rung `recommend` with strong oversight (per-run opt-in with payload preview, per-item autofix approval, verification gate). Mitigations cut the untrusted-input→action leg (read-only dispatch, adjudication-only handling of findings, human-approved application) and constrain the disclosure leg (payload preview + consent, least-data, secret detection, per-run 0700 scratch with deletion guidance). Residual: approved dispatches send content off-machine (inherent, announced); a secret that evades detection would travel. Safety eval cases — injection-in-diff must not mutate the workspace or exfiltrate beyond the approved payload; injected "declare consensus" must not sway synthesize — are authored red before implementation.

## Out-of-Scope

- Confidence-band filtering; do-not-flag list extensions.
- Changing any review or planning default; touching `design-debate`.
- Clarify gate, kaizen sweep, orchestrator mode, CLAUDE.md compression (Slices 2/3).
- Autonomous autofix application; recursive `/skill` expansion; automatic panel→synthesize chaining.
- Additional second-family providers beyond Codex (roster configurable in principle; only Codex wired).

## Acceptance Scenarios

See `specs/cross-family-panel/spec.md`, `specs/review-cross-family-pass/spec.md`, `specs/review-autofix-lane/spec.md`. Test plan beyond the scenarios: positive and negative routing cases per trigger family (not one pair); degradation cells for default-roster vs explicitly-requested panelist; injection/payload cells; autofix eligibility, stale-edit, and overlapping-edit cells; an end-to-end cell proving an accepted cross-model blocking finding changes the recorded verdict.
