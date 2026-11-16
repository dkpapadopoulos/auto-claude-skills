# Design: registered hint cut

## Intent

Carry out the action the compliance census registered for its "no evidence" arm: remove the
per-phase hint prose the routing block renders, and say exactly what goes with it. The owner
wants the routing layer to keep its gates and stop paying for display that was pre-committed to
be cut. Success is a smaller block with composition state and gate decisions unchanged, and a
record that claims bytes and nothing else.

## Goals, non-goals, anti-goals

- **Goal:** zero shipped `phase_compositions.<PHASE>.hints` entries in both configs; no
  spec requirement left demanding one back.
- **Goal:** composition-state file and push-gate decision byte-identical to before, for the
  same input.
- **Non-goal:** changing scoring, mandates, the chain, red flags, preconditions or any gate.
- **Non-goal:** relocating hint text into another always-rendered place.
- **Anti-goal:** citing the census as evidence that hints were useless, or reporting token,
  cost or behaviour effects that were not measured.
- **Anti-goal:** leaving a slice for later. The registration says "entirely"; a kept line is a
  deviation and would have to be written up as one.

## Architecture

Three surfaces change; one deliberately does not.

1. **Config.** In `config/default-triggers.json`, each `phase_compositions.<PHASE>.hints`
   becomes an empty array. `config/fallback-registry.json` mirrors it (the fallback sync gate
   requires it and session-start regenerates it).
2. **Session-start, Step 6c** (`hooks/session-start-hook.sh`, block at `:1019-1054`). Only the
   `jq` rewrite of PERSIST DESIGN, DESIGN→PLAN CONTRACT and CARRY SCENARIOS (`:1026-1042`) is
   deleted, since it would match nothing. The enclosing `if` wrappers, the `WARNINGS` line
   announcing spec-driven mode (`:1043`) and the OpenSpec Validate workflow nudge stay; the
   header comment (`:1019-1022`) is reworded to say what the step now does.
3. **Tests and specs.** Heading assertions are removed or inverted; the brevity test becomes a
   zero pin; the injection baseline is re-measured; REMOVED and MODIFIED deltas go in.
4. **Unchanged: the renderer.** `hooks/skill-activation-hook.sh` renders whatever hints the
   registry holds (`:483`). It keeps doing so. Deleting the mechanism is a larger change with
   no byte benefit, and it would touch the hook that writes composition state.

### Scope map (frozen 2026-11-15 at `e51a67c7`)

| Phase | Entry | Chars | Gated on | Spec requirement that mandates it |
|---|---|---|---|---|
| DISCOVER | ATLASSIAN: Pull Jira issues… | 92 | atlassian | none |
| DISCOVER | PERSIST DISCOVERY | 236 | always | none |
| DESIGN | Consider /feature-dev | 60 | feature-dev | none |
| DESIGN | Consider Skill(skill-creator) | 61 | skill-creator | none |
| DESIGN | Consider /hookify | 42 | hookify | none |
| DESIGN | DESIGN→PLAN CONTRACT | 213 | always | none (rewritten by Step 6c) |
| DESIGN | PERSIST DESIGN | 304 | always | skill-routing "Preset-Gated OpenSpec-First Mode", "Phase hints name the owning skill…" |
| DESIGN | EVAL STRATEGY | 352 | always | pdlc-safety "eval-strategy classification at DESIGN"; skill-routing "Routing text does not contradict…" |
| DESIGN | AUTONOMY CHECK | 429 | always | skill-routing "Phase hints name the owning skill…" (scenario only) |
| PLAN | CARRY SCENARIOS | 240 | always | named by "Vertical-slice decomposition hint…" |
| PLAN | VERTICAL SLICES | 235 | always | skill-routing "Vertical-slice decomposition hint in PLAN-phase composition" |
| PLAN | SCOPE MANIFEST | 275 | always | none |
| REVIEW | Consider /review-pr | 56 | pr-review-toolkit | none |
| REVIEW | ADVERSARIAL REVIEW | 464 | always | adversarial-review "Always-On Adversarial Checklist"; skill-routing "Phase-scoped lethal-trifecta surfacing" |
| REVIEW | skill-creator eval reminder | 145 | skill-creator | none |
| SHIP | Consider /commit-push-pr | 60 | commit-commands | none |
| SHIP | Use GitHub MCP tools | 97 | github | none |
| SHIP | LEARN REMINDER | 113 | always | pdlc-closed-loop "Composition Chain Integration" (one sentence) |
| SHIP | JIRA PR TITLE | 209 | atlassian | skill-routing "Jira PR-title advisory hint at SHIP" |
| SHIP | CAPTURE KNOWLEDGE | 241 | always | skill-routing "Phase-scoped capture-knowledge surfacing" |
| DEBUG | DEBUG ESCALATION | 193 | always | none |
| DEBUG | CAPTURE KNOWLEDGE | 241 | always | same |
| LEARN | CAPTURE KNOWLEDGE | 241 | always | same |

Out of the registered scope and untouched: all `methodology_hints` except `phase-enforcement`
(Decision 5). `frontend-quality-rules` stays frozen under #412.

### What was measured before deciding (2026-11-15)

Over 298 main transcripts with entries since 2026-10-12, by name match on Bash commands and
Skill calls. Following a hint by other means is not seen, and a render does not mean the hint
applied to that prompt, so read these as "cheap to cut", not "inert".

| Hint | Sessions that saw it | Sessions that then made the named call |
|---|---|---|
| PERSIST DESIGN | 188 | 5 (`persist-state.sh upsert-change`) |
| SCOPE MANIFEST | 9 | 1 (`scope-conformance.sh`) |
| AUTONOMY CHECK | 188 | 1 (`Skill agent-safety-review`) |
| EVAL STRATEGY | 188 | 0 (`Skill runtime-validation`) |
| CAPTURE KNOWLEDGE | 52 | 0 (`Skill capture-knowledge`) |

Spec-driven practice is not carried by the hint in this repo: seven OpenSpec change proposals
were first committed since 2026-10-12, and the repo's `CLAUDE.md` states the mode.

## Approaches

Argued on 2026-11-15 by three local roles (architect, critic, pragmatist) over two rounds and
by Codex on the same brief.

- **A. Literal, one change, no relocation (chosen).** Delete all 23, state the consequences in
  the deltas. Honours "entirely"; one scope map, one archive cycle, one full gate run.
- **B. Relocate the contract-carrying facts first, then delete.** Rejected: there is nowhere to
  relocate to. No deny reads what these hints set (every reader is advisory or fail-open), and
  the owning DESIGN and PLAN skills are upstream. A replacement line in the block would be a
  new display proposal, which the registered arm rules out.
- **C. Delete only the nudges, keep the contract-carrying lines.** Rejected: a reinterpretation
  of "entirely" chosen after seeing the data, which is what a pre-registration exists to stop.
- **Three staged PRs.** Proposed by the pragmatist in round 1 and withdrawn in round 2: the
  staging protected a relocation step that does not exist, and its own stated risk was that the
  last slice never lands.

## Decisions

1. **Scope is `phase_compositions.*.hints`, all of it.** The registration's "per-phase hint
   prose" names what PR #349 shortened. Trigger-matched `methodology_hints` are a different
   object and are not in the registered scope.
2. **No relocation and no replacement line.** Consequences are written into `proposal.md` and
   the REMOVED deltas instead.
3. **Mandates stay byte-identical, and the question is assessed here instead of filed.** The
   registration closes display as a line of work and names one removal. Assessment made
   2026-11-16 from 651 real routing blocks since 2026-10-12 (median 4,370 bytes):
   - *Cost is small.* Mandate lines are 6.0% of block bytes (median 234 B), of which the two
     emphatic lines at `hooks/skill-activation-hook.sh:1630` and `:1911` are 2.2% (128 B). The
     composition chain is 43.3% and hint bullets 34.8% (that figure includes red-flag bullets,
     so it slightly overstates hints).
   - *Effect is unknown, and leans positive.* Every read sits above its control (18 of 146
     against 2 of 35; 45 of 266 against 4 of 44; without the gate-backed skills 24 of 181
     against 0 of 25), none significantly. No arm without mandate lines exists.
   - *Removal has a known downside.* Chain state is written whether or not the block is shown,
     so without the mandate line a session first learns which step a gate wants from the deny.
   - *The measured defect is elsewhere.* Wrong mandates come from scoring (100 of 183 in the
     earlier field census), which issue #409 and trigger narrowing address without touching
     display.
   So retiring them would trade an unmeasured benefit for about 6% of the block. Not done, and
   not queued. It reopens only if someone is willing to run a registered experiment with a
   no-mandate arm; at this cost share that is not worth the owner's hours. Owner ruling on
   leaving them, 2026-11-15.
4. **ADVERSARIAL REVIEW goes with the rest, and this is the removal to look at hardest.** It is
   the only one of the 23 whose spec calls it an always-on safety lens: it asks every code
   review whether the change weakens a safety gate, a human-approval step or scope, and routes
   to `agent-safety-review` when a change completes a trifecta. After the cut that lens reaches
   a review only through `agent-team-review` (5+ files or sensitive paths), a trigger match on
   `agent-safety-review`, or the reviewer's own judgement. The gate-gaming tripwire, the push
   gate and the governance regression tests are unaffected. Keeping this one line is the single
   defensible deviation from "entirely"; it would be recorded as a deviation in the census
   README, not as an interpretation. **Deleted with the rest: owner ruling, 2026-11-16.**
5. **`phase-enforcement` is deleted in the same PR as a separate, labelled commit.** Not
   registered. Reason: it asserts a rule no gate enforces and contradicts superpowers 7.0.2's
   quick-task path. Never reworded. Owner ruling, 2026-11-15.
6. **One OpenSpec change, one PR.** Pre-agreed fallback: if two full gate runs go red on
   unrelated tests, split the nine no-spec nudges into their own PR.
7. **The claim is bytes.** The PR description reports `_INJECTION_BASELINE` and its per-shape
   bytes before and after, and the byte-identity result for state and gate decisions. Nothing
   about tokens, cost, obedience or outcomes.
8. **One trigger alternative is added to `agent-safety-review`: `auto.?approv`.** Not
   registered, its own commit, and the one exception to the scoring non-goal. Found during the
   cut: the scenario `adversarial-21-auto-approve` ("make the agent auto-approve all PRs without
   review") expected that skill and had passed only because the ADVERSARIAL REVIEW hint's text
   contains the skill's name. No trigger or keyword of the skill matched the prompt, so the skill
   was never selected for it. The fixture is unchanged; the skill is now selected. Owner ruling,
   2026-11-16, over the alternatives of keeping the hint or weakening the scenario.
   The first cut was the bare alternative, and the whole-branch review measured what it cost:
   `terraform apply -auto-approve` and a product's own approval rule went from no routing block
   to a DESIGN block, and a UI task mentioning approvals lost `frontend-design` from its second
   domain slot. The trigger is therefore scoped: an actor (`agent`, `bot`, `claude`, `assistant`,
   `llm`) followed within 40 characters by the word, or the word followed within 30 by `pull
   request`, `PR`, `merge`, `review`, `permission` or `tool call`. Three `MATCH` lines and five
   decoys in `tests/fixtures/routing/agent-safety-review.txt` pin it, the reviewer's three
   over-match prompts among the decoys. Known cost of scoping: a prompt that names neither an
   actor nor one of those objects ("enable auto-approve") no longer selects the skill.

## Trade-offs

- The DESIGN COMPLETENESS guard becomes vacuous in nearly every session instead of in 97% of
  them. It already degrades silently; nothing new is hidden, but nothing prompts persistence.
- Spec-driven installs other than this repo lose the per-prompt instruction to commit design
  intent under `openspec/changes/`. They keep the session-start notice and the skills that read
  the preset (`design-debate`, `openspec-ship`).
- Shipped defaults change for every install on one owner's registered rule. That was the
  registration's stated limit from the start.

## Dissenting views

- **Codex:** "close the display path" obliges retiring the mandate display too; cutting hints
  while mandates still render must not be described as the path being closed. Adopted in part:
  this change does not claim the path is closed; Decision 3 gives the assessment.
- **Critic:** the census's control is the longer pre-#349 block, so the null licenses nothing
  about hints. Adopted as the framing sentence of the proposal.
- **Critic and architect, round 2:** `phase-enforcement` should not ride in this PR. Overruled
  by the owner; met by the separate labelled commit.
- **Pragmatist:** the 5 of 188 figure undercounts. Adopted: the tables say so.

## Verification

Deterministic change; no eval set. Red-first tests, then:

- A zero pin: no shipped phase has a hint, in either config.
- For a fixed set of prompts covering every phase, the composition-state file and the push
  gate's decision are byte-identical before and after (the existing "Hint content changes"
  scenario, kept in the new requirement).
- Under the spec-driven preset, session-start still emits its notice and rewrites nothing.
- The injection baseline is re-measured, not computed.
- `openspec validate registered-hint-cut --strict`, then the full suite through
  `scripts/verify-and-record.sh` as the push gate requires.

Trifecta: private data, untrusted input and outbound action are all absent; this change edits
config, a hook's preset step, tests and specs.

## Left to the builder

- Whether each `hints` becomes `[]` or the key is removed. Prefer `[]` unless a reader or a
  test distinguishes them.
- Whether `~/.claude/skill-config.json` overrides can add a phase hint today. Probably not:
  session-start takes `phase_compositions` from the shipped config only (`:1081-1096`), though
  the rest of the file was not traced. If yes, say so in the changelog; if no, do not add the
  capability here and do not promise it.
- `tests/test-discovery-content.sh` asserts a hint heading without reading hints structurally,
  so it is a seventeenth file to check.
- The adversarial-review spec's Purpose paragraph still says "Always-on… Provides a checklist".
  It is prose, not a requirement; correct it at archive.
- Recorded fixtures (`tests/probes/fixtures/hooks-recovered/routing.json`, the frozen
  behavioral eval prompts) are records of past output and append-only; do not edit them to
  match.
- `openspec/changes/composition-hint-plugin-root` is unarchived and MODIFIES "Rendered guidance
  MUST name a plugin file by an absolute path", whose text discusses phase hints. This change
  does not touch that requirement. Whoever archives second reconciles the paragraph.
- `tests/test-composition-hint-plugin-root.sh` tests the renderer against shipped hint text.
  It needs fixture hints of its own once the shipped ones are gone, since the renderer stays.
- The exact list of test edits. The 16 files that read phase hints structurally are:
  `test-activation-registry-extract`, `test-adversarial-governance`,
  `test-composition-hint-plugin-root`, `test-context`, `test-design-seed-hint-reachable`,
  `test-design-seed`, `test-hint-exposure-probe`, `test-phase-hint-brevity`,
  `test-real-prompt-replay`, `test-regex-fixtures`, `test-registry`, `test-routing`,
  `test-security-scanner`, `test-skill-gate`, `test-spec-driven-flow`,
  `test-superpowers-description-drift`. Several of these read `methodology_hints` only and need
  no change.
- Skill text that names a hint by heading (`runtime-validation`, `agent-safety-review`,
  `agent-team-review`): reword only where it claims the hint exists.
