# Behavioural acceptance for the composition fixes

For reviewers of `fix/composition-defects`. Derived from the audit's fix plan
(`docs/research/2026-09-11-sdlc-composition/fix-plan-acs-defects.md` at audit commit
`8c027b9`, on the unmerged `codex/sdlc-composition-audit` branch).

## Acceptance is behavioural, and separate from the probes

The ported probes are frozen observations and non-regression detectors. They are not
the acceptance criterion, and their skill-name assertions must not be promoted into
one — a correct one-participant panel would fail `expect_absent: panel`, and a correct
new composed-flow skill would fail an assertion on the name `synthesize`.

Each defect is accepted on observable behaviour, with the forbidden behaviour and the
controls that must not move stated alongside. **Held-out paraphrases are required for
every row**: the thirteen prompts in `intent-routing/cases.json` are development data
now, because the fix is written while looking at them.

| Defect | Must be observable | Must NOT happen | Controls that must not move |
|---|---|---|---|
| **D1** one-model consultation has no route | a one-model request reaches a one-participant consultation, with the prior answer EXCLUDED; an explicit critique request INCLUDES it | many-model dispatch for a one-model request; the paraphrase set falling through to no route | plain questions still consult nothing; a genuine panel request still reaches panel |
| **D2** consultation methods co-select on ordinary design vocabulary | an independent-consultation request and an interactive-debate request select differently | ordinary design vocabulary selecting three skills | a development request still selects its development skills |
| **D3** phase chains injected into phase-agnostic consultations | a consultation-only request receives no development chain | chain suppression on a MIXED request, or on an in-progress workflow | continuation after a consultation detour still resumes its chain |
| **D4** composed planning reaches `synthesize` and is refused | an authorized composed flow completes a merge whose inputs are real, complete, attributable to this request, and from distinct participants | a merge synthesised from perspectives never gathered | standalone `synthesize` remains model-uninvocable |

## Two mechanisms, not one

D1 has two independent causes and a fix must address both. Verified against
`config/default-triggers.json`:

1. **Routing.** No second-opinion skill exists among the 43 in the registry, and
   `panel` claims part of the intent in its trigger — a clause fragile enough that
   `"a second opinion from one other model"` does not match it and routes to
   `brainstorming` instead.
2. **Model choice.** Natively the model invoked `panel` anyway, having *not* been
   routed there. It picked panel from the roster because panel is the only
   consultation-shaped option visible to it.

Changing triggers addresses (1) only. A fix that leaves panel as the sole
consultation-shaped skill will keep producing (2).

D2 and D3 share a root cause. The `Composition:` chain is built by
`_walk_composition_chain` (`hooks/skill-activation-hook.sh`), which anchors on
`PROCESS_SKILL` and walks `precedes`/`requires` — so the chain appears because
`brainstorming` co-selected and supplied the anchor, **not** because `panel` declares
`phase: PLAN`. A phase-agnostic registry value is a worthwhile representation fix and
is *not* sufficient for D3.

## The regression the probes do not cover

The routing probe uses fresh temporary homes and never exercises an active chain, a
short consultation request, then "continue". **Suppressing legitimate development
routing during a consultation detour is the likeliest way this change set breaks
something nothing measured.** Positive development controls belong alongside the
consultation negatives: continuation, cancellation, mixed intent, presets, overrides,
unavailable skills, and the fallback registry.

## Repository gates this change must clear

- **routing-governance denies any push touching `skills/`, `config/` or `hooks/`**
  without a clean `project-verification` verdict covering HEAD, and the applicable
  push-gate path also needs REVIEW evidence.
- **`.verify.yml` is the whole suite** — one unrelated red test blocks every routing
  push repo-wide.
- **`config/fallback-registry.json` must stay in sync** with `default-triggers.json`,
  and phase-contract tests reject null/empty phases — relevant before choosing `null`
  versus `"ANY"` for the phase-agnostic value.
- **Composition-state and push-gate regressions**, not only regex fixtures: the hook
  persists chain progress, so a selection change can strand or switch an in-progress
  chain and affect later gate evidence.
- **A new skill needs two artifacts or CI fails**: a routing fixture
  `tests/fixtures/routing/<name>.txt` with at least one MATCH and one
  verbatim-borrowed NO_MATCH decoy, and some `tests/*.sh` referencing
  `skills/<name>/`.
- **Bash 3.2** for hook edits, and `/bin/bash -n` is not sufficient — the model's Bash
  tool is zsh, so exercise hook changes under real bash.
