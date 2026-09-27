# Design

## Architecture

Four surfaces may co-fire on a UI prompt, each owning one responsibility. The design
deliberately does NOT add a fifth:

| Surface | Role | Owns |
|---|---|---|
| `brainstorming` | process | intent, approval gate, the `precondition` (product-discovery + trifecta) |
| `frontend-design` | domain | aesthetic direction: palette, typography, layout |
| `design-seed` | methodology hint | mechanism: role-token indirection, hard states, token-lint, browser verification |
| `prototype-lab` | domain, opt-in | 3-variant comparison, ONLY on an explicit comparison ask |

### Restoring the lost precondition

`_walk_composition_chain` resolves `_CHAIN_ANCHOR` from `PROCESS_SKILL`, then from a
selected `workflow` skill carrying `precedes`/`requires`. A `domain` skill can never
anchor. When no process trigger matches, the chain block disappears and with it the
driver's `precondition`, which renders only under the `CURRENT` marker.

The fix renders **the driver's `precondition` alone**, under a one-line attribution naming
the driver's `Skill()` invocation so the precondition has an antecedent (its text says
"then return to brainstorming", which does not parse with nothing before it). It does NOT
establish a chain.

**Why not anchor the chain on `driver` instead.** That was the recommendation of both
consultations, and it is rejected on a measured consequence neither raised. `_full_chain`
and `_current_idx` are set inside the `_CHAIN_ANCHOR` block, and the composition-state
write is gated on exactly those two. So a driver-anchored chain writes `.chain` — and the
chain anchored at `brainstorming` contains BOTH push-gate milestones
(`requesting-code-review`, `verification-before-completion`). `openspec-guard.sh:1127`
reads `.chain | index("requesting-code-review")` and denies `chain-review`; `:1222` does
the same for `chain-verify`. A session that merely asked "what's our token convention?"
would then need a dispatched review and a verification run before it could push anything.
A fix for a missing advisory would have manufactured a new deny.

Two further points, recorded so the rejected option is not re-proposed without them:

- `.completed` itself would NOT have been fabricated: `_progress_idx` stays `-1` when
  `_current_idx` is 0, so the driver is never credited on its own turn. And
  `current_index` is not a push-gate input — the hook states at `:1506` that "the push
  gate keys off `.completed` only." The danger was `.chain` alone.
- `COMPOSITION_DIRECTIVE` ("after completing X, invoke Y; do not stop at the current
  step") renders unconditionally whenever a next step exists. On a driver-derived anchor it
  would push a full SDLC sequence off a phase default rather than off matched intent.

The narrow render reaches neither mechanism: it never sets `_full_chain`/`_current_idx`, so
no state write occurs, and it never enters the directive path. It therefore needs **zero**
suppressions on a shared code path, which is the deciding argument — a shared path
carrying a condition someone must remember is the failure shape this repo has repeatedly
paid for.

### Aesthetic authority

`assets/design-seed/tokens.css` is `preset: quiet-dense` with ~30 concrete literals. It
ships a look **on purpose**: `design.md:28` of the archived seed change says a generated
token set "has no taste floor — it is exactly the invented-defaults failure the capability
exists to prevent." So the framing "the seed ships no look" is false of the artifact.

The accurate framing is **taste floor, not house style**. `ADOPT.md` already says this
under "Then make it yours" — but after the numbered steps a model stops at. The defect is
therefore in the hint string, which co-fires with `frontend-design` in the same context
window and today carries no floor/override framing.

## Trade-offs

- **Editing a third-party skill's ACS-side trigger.** Accepted: the `frontend-design`
  entry is a 100% ACS-authored heuristic with no coupling to upstream's own
  description-based matching. Every third-party entry in this registry already carries the
  same hand-maintained staleness exposure; this fix adds no new cost.
- **Phase-driver resolution can amplify a wrong phase.** If `PRIMARY_PHASE` is wrongly
  `DESIGN`, the DESIGN driver's precondition now renders on a prompt that isn't DESIGN work
  — not a full chain (the shipped render is deliberately display-only; see "Restoring the
  lost precondition"). Mitigated by validating the driver exists in the registry,
  preserving consultation suppression, and surfacing that the anchor was phase-derived in
  `SKILL_EXPLAIN`.
- **Plural fix raises `frontend-design`'s match rate.** That is the point, but it must be
  measured, not estimated — see Verification.

## Dissenting views

- **A shipped default industrialises one house style across every consumer, which is worse
  than per-project drift.** Recorded as unresolved in the archived seed change and NOT
  settled here. This change reduces its force by making the default an explicit floor, but
  does not remove the shipped preset.
- **Codex proposed settling aesthetic authority empirically** (20 briefs x 3 repetitions
  per arm). Declined: that is a pilot replication, and issue #298 scopes the
  instrument-sensitivity problem that makes such a run produce a result which looks like
  evidence and is not. The prior pilot's rubric excludes tokens and resemblance by
  necessity. The fork is decided on coherence instead: two contradictory instructions in
  one context window is a defect regardless of which look scores better.
- **Both consultations recommended anchoring the full chain on `driver`** (reuse the
  tested render path; a parallel branch was argued to be more code). Rejected on the
  `.chain` push-gate consequence above, which neither had measured. Their strongest
  counter-argument survives and is recorded: a one-line attribution plus a precondition is
  itself a fragment of the chain, so the saving is smaller than it looks. The deciding
  factor is not code size but that the narrow form requires no suppressions.
- **A four-surface co-fire could be context flooding.** Judged not to be the live risk:
  `RED_FLAGS`, phase hints, skill lines and the chain already stack on every DESIGN-phase
  prompt. The measured risk runs the other way — a domain-only match loses the one
  load-bearing item.

## Decisions

- **D1: Read the driver from `phase_compositions[PRIMARY_PHASE].driver`, and render its
  precondition WITHOUT establishing a chain.** `driver` already models "the process skill
  this phase defers to regardless of what fired", and reading it sidesteps the
  domain-anchor restriction rather than widening anchor-role semantics for every phase.
  `precedes`/`requires` on a domain skill stays dead config. The chain is deliberately not
  rendered: see "Restoring the lost precondition" for the `.chain` push-gate consequence
  and the unconditional directive, either of which would have to be suppressed on a shared
  path if the chain were reused.
- **D2: Aesthetic authority sits with `frontend-design`; the seed supplies mechanism and a
  floor.** Rejected alternatives: seed-leads (inverts the seed change's own stated
  rationale and takes the side of a dissent it recorded as live), and
  mutually-exclusive-by-project-state (already partly implemented by the hint's `design/`
  branch, and it withholds the token-indirection mechanism exactly where new UI is
  invented). The two are complementary; the `design/` branch is kept.
- **D3: `prototype-lab` is not widened to UI vocabulary.** Measured: +6 false dispatches on
  the 224-prompt negative corpus and 43 -> 258 matches on 2451 real prompts (human 3 -> 12)
  with 0 correct human matches. The seed method invokes it on demand instead.
- **D4: Plural morphology only; no vocabulary import.** `theming`, `design.tokens?` and
  `style.guides?` are design-seed-owned concepts; `style`/`css` already cover that ground,
  and importing them raises false-positive surface for no measured recall gain.
- **D5: The `side.by.side` narrowing is a proximity form, not a deletion.** Deletion was
  measured: it fixes all 6 false dispatches but loses all 5 legitimate cases.

## Verification

Baseline first, in every case; never estimate a starting number.

**Plural trigger fix.** Reuse the existing instruments: `tests/probes/negative-corpus/`
(224 prompts) and the real-prompt replay (2451 prompts, 714 `human`). Pre-registered bar:
`frontend-design`'s match count on the real corpus increases; and no new hits appear in the
224-prompt negative corpus **other than the one accepted 2026-09-27** (the `screens?`
restore fires on "the collapsible panel on the settings screen needs a scrollbar" —
accepted as in remit, see `specs/skill-routing/spec.md` R4 S2). The
"**verbatim from the real corpus**" bar for `tests/fixtures/routing/frontend-design.txt`'s
plural MATCH case was NOT met as shipped: the real-prompt corpus contains zero
plural-dependent `frontend-design` prompts (measured), so the fixture's plural line is
CONSTRUCTED to exercise the morphology directly, documented as such in the fixture's own
comment (`tests/fixtures/routing/frontend-design.txt:8-13`).

**Driver precondition render.** A mechanism change needs golden-output assertions, not a
rate. In `tests/test-context.sh` (phase composition's home). The set below exists because
an adversarial pass constructed wrong implementations that satisfied an earlier, smaller
set — each item names the wrong implementation it excludes:

1. Positive: a domain-only DESIGN prompt renders the driver's `Skill()` line and its
   `precondition`, including the trifecta instruction, and renders no step markers.
2. **Driver read from config, not hardcoded.** A fixture whose `driver` is edited to name a
   different skill must render that skill. Excludes `_CHAIN_ANCHOR="brainstorming"`, which
   passes every other assertion because DESIGN's real driver IS brainstorming.
3. **No composition state write**, asserted as a whole-file byte comparison against
   non-trivial prior content. Excludes an implementation that suppresses the driver from
   `.completed` while still writing `.chain`.
4. **Two-turn non-creditability.** Turn 1 renders the fallback; turn 2 genuinely selects a
   downstream chain member; recorded progress must equal what turn 2 alone produces.
   Excludes a leak visible only across turns.
5. **No `COMPOSITION_DIRECTIVE`** on a driver-derived render, with a matched-process control
   that still receives it. Excludes shipping the false-progress push untested.
6. **Inert on a process-anchored prompt** (byte-identical) AND **inert on a
   workflow-anchored prompt** (byte-identical). One control cannot pin a three-way
   priority order. The second is measured (`tests/test-context.sh`'s own commentary on
   `test_driver_render_inert_when_workflow_anchored`) against the guard that suppresses a
   driver render once a workflow anchor has already resolved a chain — it does NOT pin a
   literal reordering of the two resolution steps, which is a narrower claim than "excludes
   resolving the driver before the workflow scan."
7. **Driver-absent and infrastructure-absent are distinct conditions**, proven by repairing
   the infrastructure and showing the same prompt then renders. Excludes a blanket
   `|| _CHAIN_ANCHOR=""` that swallows real faults.

Items 3, 4 and 6 are the ones that must fail if the fix is built too broadly.

**Non-discriminating assertions, deliberately removed.** Three earlier scenarios were true
both before and after the change and so pinned nothing: "genuine comparison requests are
retained" (today's over-broad `side.by.side` retains them precisely because it is too
broad — measured, all 5 legitimate cases already match), and two design-foundations
scenarios restating the lint's existing behaviour. The comparison scenario is replaced by a
**paired** form in which two prompts differ only by the variant-shaped noun, so the
proximity rule itself is what decides. The unchanged-adoption scenario is retained but
re-aimed at a risk this change introduces: a floor-framed hint must not read as an
obligation to diverge.

## Measurements behind this change

All measured 2026-09-26 against the real hook at `a7da7ec`.

- Negative corpus instrument health: 10/10 committed consultation lines reproduced.
- `prototype-lab` today: 6 false dispatches / 224 negatives (all from `side.by.side`);
  43 matches / 2451 real prompts, 3 `human`, all 3 self-referential meta, 0 correct.
- `prototype-lab` widened to UI vocabulary: 6 -> 12 negatives, 43 -> 258 real, human
  3 -> 12, still 0 correct.
- `side.by.side` proximity narrowing: 6/6 false dispatches fixed, 5/5 legitimate retained.
- `frontend-design` plural gap: 4 of 6 probed UI prompts no-match.
- Domain-only match loses `PRECONDITION` and `TRIFECTA` and the chain; retains
  `DESIGN->PLAN CONTRACT` and `AUTONOMY CHECK`.
- `driver` populated for all 8 phases, read nowhere in `hooks/` or `scripts/`.
- Trap: bash 3.2 on macOS silently does not support `\b` in `[[ =~ ]]`; a first candidate
  trigger using it measured byte-identical to control, i.e. a false clean.
- The `brainstorming` chain contains both push-gate milestones, so writing `.chain` on a
  domain-only prompt would arm `deny:chain-review` and `deny:chain-verify`.
- `_progress_idx` stays `-1` at anchor index 0, and `current_index` is not a push-gate
  input (`hooks/skill-activation-hook.sh:1506`) — the risk was `.chain`, not `.completed`.
