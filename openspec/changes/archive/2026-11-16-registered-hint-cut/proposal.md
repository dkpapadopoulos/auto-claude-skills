# Registered hint cut

## Why

The in-turn compliance census (`tests/probes/compliance-census/README.md`) was registered on
2026-10-12 with a rule fixed before the data: if displaying a mandate does not measurably move
behaviour, close the display path as a cost-saving only, make no further display proposals, and
"the next cut removes per-phase hint prose entirely (with the #356 REMOVED delta)".

The read was made on 2026-11-15, with amendment A2's sensitivity read at the same sitting:

| Read | Obeyed in-turn | Control | p |
|---|---|---|---|
| Registered (A1) | 18 of 146 | 2 of 35 | 0.2111 |
| Over pruned history (A2, `--include-bak`) | 45 of 266 | 4 of 44 | 0.1345 |

Both are p >= 0.05, so A2's "both no evidence" row applies and A1's "no evidence" arm applies in
full. This change is that registered action.

**This is a pre-committed cost decision, not a finding that hints do nothing.** The census
compared a longer block with a shorter one and measured mandates, not hints; its README says a
null is "no evidence", never "no effect". The only claim this change makes is bytes removed.

## What Changes

- The 23 shipped `phase_compositions.<PHASE>.hints` entries (4,599 characters across seven
  phases) are deleted from `config/default-triggers.json` and `config/fallback-registry.json`.
  The scope map is in `design.md`.
- The spec-driven preset's rewrite of three of those hints (`hooks/session-start-hook.sh`,
  Step 6c) is deleted. The once-per-session notice "spec-driven mode active: design intent
  persisted to openspec/changes/ (committed)" stays.
- The hint **rendering mechanism** in `hooks/skill-activation-hook.sh` is not touched.
- Composition state, mandates (`MUST INVOKE` lines), the composition chain, red flags,
  preconditions and every gate are not touched. Scoring is not touched except for one trigger
  trigger (auto-approve, scoped to an actor or an object, on `agent-safety-review`), carried as its own commits: a scenario
  expecting that skill had passed only because a removed hint's text named it (`design.md`,
  Decision 8).
- One further deletion, **not registered** and carried as its own commit with its own reason:
  the `phase-enforcement` entry in `methodology_hints` ("Small changes still require the full
  flow"). The owner approved it on 2026-11-15 because it contradicts superpowers 7.0.2's
  quick-task path and no gate enforces it. The census is not cited for it.
- The census README's amendment log records the read.

## Capabilities

- **Modified: `skill-routing`** — five hint-mandating requirements removed, three modified, two
  added (shipped phase compositions carry no hint prose; the skills and procedures the hints
  pointed at stay reachable and in place).
- **Modified: `pdlc-safety`** — the always-on EVAL STRATEGY hint requirement removed; its
  content obligations kept as a requirement on `runtime-validation`.
- **Modified: `pdlc-closed-loop`** — the sentence requiring a LEARN reminder hint at SHIP
  dropped from "Composition Chain Integration".
- **Modified: `adversarial-review`** — the always-on ADVERSARIAL REVIEW checklist hint
  requirement removed. This is the removal with the largest consequence; see `design.md`,
  Decision 4.

No new capability.

## Impact

- **Rendered bytes:** every routed prompt in a phase with hints loses that phase's hint lines
  (DESIGN 1,461 characters, PLAN 750, SHIP 720, REVIEW 665, DEBUG 434, DISCOVER 328, LEARN 241,
  before plugin gating). `_INJECTION_BASELINE` in `tests/test-injection-budget.sh` (22,225) is
  re-measured and lowered in the same commit.
- **Behaviour that goes with the text**, stated so nobody rediscovers it:
  - Nothing tells the model to run `persist-state.sh upsert-change`, so the PLAN-phase DESIGN
    COMPLETENESS guard (advisory, fail-open) will find no `design_path` in almost every session.
    Measured before the cut: 5 of 188 sessions that saw PERSIST DESIGN ran it.
  - The same missing `design_path` has three more readers, found by the whole-branch review.
    Each already did nothing whenever the state was absent, and now that is nearly always:
    `openspec-ship` generates no Divergences report (Step 7c) and does not move the design doc
    to `docs/plans/archive/` (Step 7b); `deploy-gate`'s "Design Intent Exists" check has nothing
    to read; and the post-compaction "Active OpenSpec changes" line lists a change before SHIP
    only if discovery ran. Not repaired here: a fallback in `openspec-ship` that finds the
    design doc without the state is a skill change of its own.
  - `tests/fixtures/evals/routing-validation.json` expected the AUTONOMY CHECK hint; that
    scenario is marked `deprecated`, not deleted.
  - Five rules lived in hint text alone and have no other carrier in any skill, command or
    hook: VERTICAL SLICES, JIRA PR TITLE, DEBUG ESCALATION, CARRY SCENARIOS and, outside
    `design-debate`, the DESIGN→PLAN contract. "Procedures stay in the owning skills" holds
    only for the adversarial checklist, the autonomy levels, the eval strategy and the
    discovery persist step. Checked by searching `skills/`, `commands/`, the activation hook
    and the config for each rule's wording, 2026-11-16.
  - The EVAL STRATEGY hint carried a corrected timing its skill section did not. The section
    (`runtime-validation` § Eval strategy at DESIGN) is corrected in this change and pinned.
  - Ordinary `requesting-code-review` no longer receives the adversarial governance checklist.
    `agent-team-review` keeps its adversarial-reviewer specialist.
  - The EVAL STRATEGY, AUTONOMY CHECK and CAPTURE KNOWLEDGE prompts stop; their procedures stay
    in `runtime-validation`, `agent-safety-review` and `capture-knowledge`, reachable by trigger
    or by name.
- **Other installs:** shipped defaults change for everyone on the next plugin update. A user
  cannot add a phase hint back through `~/.claude/skill-config.json`: session-start takes
  `phase_compositions` from the shipped config only (confirmed by the whole-branch review).
- **Tests:** 16 test files read phase hints structurally; seven assert hint headings.
  `tests/test-phase-hint-brevity.sh` changes from per-phase ceilings to a zero pin.
- **Not in this change:** issue #409 (paste stripping), any change to mandate wording or the
  two emphatic lines at `hooks/skill-activation-hook.sh:1630` and `:1911`, the remaining 19
  `methodology_hints`, and the frozen `frontend-quality-rules` hint (#412).
