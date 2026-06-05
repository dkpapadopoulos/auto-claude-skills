# Design: Incident-Analysis Rigor

## Architecture

Two independent, prompt-only behavioral contracts added to the existing `incident-analysis` skill. Neither introduces runtime code, dependencies, or new executables. Both are designed to be **deterministically assertable** by the `behavioral-evaluation` runner (regex / `tool_call`), which is what lets them ship as *enforced* behavior rather than prompt-hope.

### A — Action-Item Phase Classification (POSTMORTEM stage)

- Location: `references/postmortem-template.md` Action Items section (an uncapped reference file).
- Contract: every action item row carries a `Type` field ∈ `{Detect, Prevent, Mitigate}`.
  - `Detect` — improves time-to-detection (alerts, SLOs, monitoring) for this failure class.
  - `Prevent` — stops the root cause from recurring (validation, CI gates, guardrails).
  - `Mitigate` — reduces blast radius / speeds recovery when it recurs (runbooks, automation, capacity).
- The template's built-in schema path and the project-template path both reference the field, so behavior is identical whether or not a repo-local template exists.
- Rationale: surfaces the "all Prevent, no Detect" anti-pattern at authoring time and gives `incident-trend-analyzer` a new aggregation axis (Detect-vs-Prevent ratio across the corpus).

### B — Per-Command Risk Label for Destructive Actions (EXECUTE / HITL stage)

- Location: risk-label format + scoping rule in a reference file (new `references/command-risk.md` **or** appended to `references/query-patterns.md` — decided at implementation by which keeps cohesion); a single pointer line in `SKILL.md` at the HITL gate, offset by an equivalent trim.
- Contract: immediately before presenting a destructive/mutating command, emit one ASCII line:
  - `RISK: HIGH — <reason>` for irreversible / data-loss / wide-blast-radius actions (delete, drain, destroy).
  - `RISK: MEDIUM — <reason>` for temporary-disruption / reversible actions (restart, rollout, resize).
- Scope: destructive/mutating commands ONLY. Read-only investigation queries MUST NOT carry a risk label (avoids alert-fatigue; consistent with `alert-hygiene`).
- Token form: leading ASCII token `RISK:` (uppercase) so `grep -F` / regex assertions match reliably; an emoji MAY follow the token for human readability but MUST NOT be the sole marker (prior macOS Unicode-grep breakage).
- Composition: complements — does not replace — the existing HITL gate and `requires_pre_execution_evidence` capture. The label is what the *user reads at the decision point*; the evidence bundle is the *audit record*.

## Trade-offs

- **Accepting** a small standing prose cost in reference files and one offset line in SKILL.md. Justified because both items are outcome-changing and deterministically testable.
- **Accepting** that the `Type` classification is author-judgment (the model assigns it); the runner can assert the field's *presence* and *valid value*, not semantic correctness.
- **Accepting** that destructive-command detection relies on the existing `destructive_action` playbook flag + the agent's mutation recognition at the HITL gate; we do not build a command parser.

## Dissenting views

- **Critic:** challenged whether #2 adds anything over existing HITL gating, and warned the full 4-level taxonomy would be alert-fatigue. Resolved by scoping to destructive-only + a 2-level (HIGH/MEDIUM) label — the label adds a *legible risk statement at the decision point* that the gate alone does not provide.
- **Critic:** argued #7 (Exhibit/dated-folder) is redundant/regressive; **accepted** — cut from scope. Codex independently confirmed the evidence system "is already strong for typed verification links and bundle storage."
- **Pragmatist:** flagged the 1-word SKILL.md headroom as the binding constraint; design honors it by landing prose in reference files + an offset trim for the single SKILL.md pointer line.
- **Architect:** ranked #2 above #8; the synthesis inverts this (#8 first) because #8 is the only candidate that changes *what gets fixed*, and both ship together regardless of order.

## Decisions & Trade-offs (rejected alternatives)

- **Unicode sparklines (#1):** deferred, not built — unmeasured value, survivorship bias from a vendor demo repo, would add the first maintained executable. Revival trigger recorded in proposal.
- **sklearn anomaly stack (#4):** rejected — dependency weight + nondeterminism vs deterministic threshold signals, zero logged pain. Biggest trap.
- **safe_gcloud wrappers (#5):** rejected — infra ceremony, not load-bearing even in the source repo's real investigations.
- **EVAL.md (#6):** rejected — `behavioral-evaluation` runner is strictly more rigorous.
- **matplotlib graphs (#3 PNG half):** rejected — terminal-first harness; integrity rules (never-fabricate, UTC axes) already enforced.

## Implementation Notes (synced at ship time)

- Built as designed; no scope changes. All five acceptance scenarios implemented.
- **Code review found one deviation, fixed before ship:** the `Type` field was initially added only to the built-in `references/postmortem-template.md`. The `SKILL.md` POSTMORTEM generation step (`SKILL.md:919`) — which also governs the project-template path (the built-in template is bypassed when a repo-local template is discovered, per `SKILL.md:944`) — did not carry the field, so a repo with its own postmortem template would have emitted untyped action items, violating the spec's "both paths" clause and AC-1's "every". Fixed by adding `type (Detect/Prevent/Mitigate)` to the generation instruction (+2 words; word guard holds at 11499) plus a regression assertion (`test-incident-analysis-content.sh`: "SKILL.md: action items carry phase type") covering the SKILL.md path the original `test-postmortem-shape.sh` assertion missed.
- Word-guard offsets: the destructive-command HITL pointer was offset by trimming redundant phrasing in the EXECUTE section ("with a fingerprint safety check" → "after a fingerprint recheck"; "at the HITL gate" removed; kubectl-install line reworded) and dropping the decorative "copilot, not an autopilot" aphorism — all semantically neutral per review.
