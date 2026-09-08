# Learnings for ACS from patforna/writing

Source: https://github.com/patforna/writing — "Getting Out of the Loop: 8 Months
Solo-Building with AI" (Patric Fornasier, Sept 2026). The repo is a single
essay; its concrete practices live in two linked plugins, `patforna/auto-task`
(task pipeline: create → clarify → worktree → plan → impl → review → triage →
fix → verify → ship) and `patforna/core-skills` (panel, synthesize, sop,
research, kaizen, tdd, design-handoff skills). All three were read for this
note. The author's own disclaimer applies throughout: n=1, solo, quant domain,
mostly anecdotal.

## What the essay claims, in one table

| # | Practice | Author's evidence | ACS today |
|---|----------|-------------------|-----------|
| 1 | Shrink CLAUDE.md; encode rules as mechanical tests | "hit and miss and got worse as I added more rules"; CLAUDE.md ended up process-only | CLAUDE.md is 13,159 words; 30 gotcha bullets, 5 of them 700–2,553 words; 16/30 cite a regression test. auto-task's CLAUDE.md is 252 words. |
| 2 | Cross-family panel (Claude + Codex) for PLANNING and review; single round, fresh contexts, synthesis without forced consensus | Single-digit sample, LLM-judge scored, harness confound acknowledged; "the part that most reliably caught real bugs" | `design-debate` is same-family personas; `agent-team-review` offers Codex only after a clean verdict and only for external-fact claims. Nothing in PLAN. |
| 3 | Review: explicit do-not-flag list, severity x autofix as independent axes, triage as a router, never auto-reject Critical/Major, authorship guard | Distilled from a code-review literature pass (May 2026) | `agent-team-review` has severity, §4a pairing, doubt-theater detection. No do-not-flag list, no autofix lane, no authorship guard. |
| 4 | Periodic holistic health sweep (`kaizen`) plus a daily review of changes that bypassed the pipeline | Noise was the failure mode; fixed with severity gating + autofix lane | `improvement-miner` mines instruments (eval baselines, gate status, memory), not the codebase. Has a kill criterion for the same noise problem. |
| 5 | Research skill: pre-committed resolution criteria, cite-or-flag, echo-vs-independent agreement, pre-mortem, every revision round needs new external signal | Written after "cognitive surrender" cost weeks of building on a confident wrong answer | No research skill. `product-discovery` and `unified-context-stack` external-truth tier cite sources but pre-commit nothing. |
| 6 | Task file as the handoff unit; "would two reasonable agents build the same thing without this line?"; throw away bad output and re-run from an improved task | 60+ tasks shipped; 2x throughput after auto-task | `docs/plans/` + openspec; design-guard grep-checks three headings. Same idea, different container. |
| 7 | Skills rewritten by hand to remove AI slop and regain ownership | Author "felt I was losing ownership" of AI-evolved skills | Largest SKILL.md files: 11.2k, 8.3k, 5.5k words vs auto-task's largest at 2.9k. |
| 8 | Preflight: "degraded" (proceed, record it) vs "stop-and-fix" (would die 20 min in) | — | Session-start canaries are warning-only; accepted degradations are not carried into the final report. |
| 9 | Evals for open-ended work: "my own pipeline has none, vibes only" | Named as an open problem | ACS is ahead: pre-registered shadow corpus, Clopper–Pearson bands, backtest scripts, eval-instrument design. |
| 10 | No PRs, squash to main; enforcement is prompt discipline (no hooks at all in auto-task) | Solo trunk-based | ACS enforces in PreToolUse hooks with fail-open announcement. Divergence, not a gap. |

## Learnings worth acting on, ranked

### 1. Put CLAUDE.md on a diet (highest leverage)

This is the essay's central engineering learning and ACS's own numbers make
the case. Every session auto-loads 13k words, most of it narrative incident
reports about one hook (`openspec-guard.sh`). The five longest bullets are
design docs, not instructions. The essay's rule of thumb: once a rule is
enforced by a test, CLAUDE.md keeps only the one-line rule and a pointer.

ACS already has the test half (137 test files, 49 of them grep-the-source
architecture tests, exactly the shape the essay shows). What is missing is the
second half of the move: deleting the prose after the test lands.

Proposal:
- For each gotcha bullet that names a `Regression:` test, cut it to rule +
  test path + issue number (1–3 lines). Move the narrative to
  `.claude/knowledge/` (one fact per file, already the designated home for
  this shape) or leave it in the PR/issue it came from.
- Add a size guard, the same mechanism `incident-analysis` already has at
  11,500 words: pin CLAUDE.md at a ceiling and per-bullet at ~150 words.
  "Three strikes → encode a rule" is the author's threshold; CLAUDE.md is far
  past it.
- Target: under ~3k words. The "Overprompting" learning is the reason this is
  not cosmetic: the author found more rules made compliance worse, not better.

### 2. Cross-family panel as an optional PLAN/DESIGN enhancer

The two skills are tiny (`panel` 326 words, `synthesize` 154 words). The
mechanics worth copying exactly: same prompt to each panelist in a fresh
context, no cross-talk, one round, an anti-sycophancy block appended, fail
loudly if a panelist is unavailable (never substitute silently), and a merge
rubric that keeps disagreements as signal.

Caveats to carry with it:
- The author's follow-up research (arXiv 2603.12123, per his synthesis)
  found context isolation is the main mechanism and cross-model is a
  secondary lever. ACS's reviewer-subagent crediting (#241) already buys the
  isolation half, so the marginal gain is smaller than the essay's framing.
- `design-debate` uses persona prompting (architect/critic/pragmatist). The
  author's research note says persona prompting does not improve accuracy
  (Mollick et al.) and his skills forbid it. Worth a re-check of that skill.
- In `agent-team-review`, move the Codex pass from "offer after clean, facts
  only" to a parallel perspective feeding the synthesis when Codex is
  installed, with a recorded degradation when it is not. Keep the existing
  read-only/sandboxed invocation rule.

### 3. Borrow three review-skill rules into `agent-team-review`

- A do-not-flag list (pre-existing, tool-owned, correct-but-unusual,
  framework-handled, speculative, judgement-bound trivia). The author's
  literature pass calls this the highest-leverage prompt element.
- Severity and autofix as independent axes, with `Autofix:` as a per-finding
  routing token that survives synthesis, and a bar that is explicitly higher
  than the surface threshold. Minor/Nit only; Critical/Major never bypass the
  human gate.
- An authorship guard: if the reviewer authored the diff in this context,
  downgrade to convention-checking only and say so. ACS enforces dispatch of a
  reviewer subagent, but the SKILL.md does not state why.

### 4. Research discipline into `product-discovery`

No new skill needed. Three rules transfer directly: pre-commit what a strong
answer looks like and what evidence would change it before searching; cite or
flag (never fabricate a source); classify agreement as independent vs echo.
The fourth rule, "every revision round must bring new external signal, self-
refinement without it degrades output", applies to `agent-team-review`'s
round structure as well and is adjacent to its doubt-theater detector.

### 5. Skill slop pass

Same failure mode as #1, one level down. The three largest SKILL.md files are
2–4x auto-task's largest. The existing 11,500-word guard permits the current
state. A hand rewrite of the top three, in the author's sense (reduce to the
essence, move tables and schemas to `references/`), is the concrete action.

### 6. Defer: a `kaizen`-style codebase sweep

The dimension list is good (domain-correctness drift, convention drift,
architecture DAG, test-suite health, doc-code drift, dead artifacts) and the
"already settled" filter (skip anything captured in the task pipeline or a
decisions doc with an unfired revisit trigger) is a clean anti-noise rule that
maps onto `improvement-miner`'s parked revival criteria. But the essay reports
these sweeps were "very noisy and always produced some findings", which is
exactly the outcome `improvement-miner`'s kill criterion exists to measure.
Do not add a second proposal generator until the first one's approve-rate
data says the channel works.

## Where ACS is ahead

Worth stating so the comparison is not one-directional:
- Evals. The essay names this as the field's open problem and admits the
  author's pipeline has none. ACS has a pre-registered decision rule, an
  exact-CDF band computation, and a corpus with episode denominators.
- Enforcement. auto-task has no hooks; every gate is prompt discipline. The
  essay's own principle ("enforce mechanically, not in prose") argues for
  ACS's hook-based gates at the SDLC level.
- Fail-open announcement (#198) is the same idea as auto-task's
  degraded/stop-and-fix preflight, and ACS applies it at every gate.

## Design values the essay confirms

Not actions, but alignment worth noting for future decisions:
- "Cruise control, not Full Self-Driving" matches ACS's warn-first posture and
  the shadow-corpus-before-deny-flip discipline.
- Human attention is the bottleneck; routing that produces no output on
  non-matches is the right default.
- "Whenever I had to intervene, I changed the system so I wouldn't have to
  next time" is ACS's gotcha-plus-regression habit. The missing step is the
  deletion afterwards (#1).

---

# Part 2 — auto-task and core-skills: adopt / adapt / skip catalogue

Scope of this pass: every SKILL.md in both plugins read in full (auto-task:
auto-task, create-task, clarify-task, plan-task, impl-task, review-code,
review-task, review-design, ship-task, config, tdd; core-skills: panel,
synthesize, sop, research, kaizen, review-loop, create-design-brief,
ingest-design, plus the four book-lens skills by heading), the config
defaults, `vendor.sh`, the research-corpus README and consolidated synthesis.

Verdict key. **Adopt**: take as-is into an ACS surface. **Adapt**: the idea
transfers, the mechanism does not. **Skip**: deliberate non-goal for ACS, with
the reason. **Parity**: ACS already has it; listed so the comparison is not
read as one-directional.

## Structural difference that shapes every mapping

auto-task is an **orchestrator with no hooks**: one skill drives a fixed
pipeline, each step is a fresh-context subagent, and state lives in a task
file. ACS is a **router with hooks**: it injects skills and hints per phase,
gates a few transitions mechanically, and leaves orchestration to the model.
So most auto-task steps land in ACS as either (a) text in an owned SKILL.md,
(b) a phase hint in `config/default-triggers.json`, or (c) a companion-plugin
entry (`when: installed`), the same mechanism ACS already uses for
`pr-review-toolkit`, `feature-dev`, and `design-debate`. Vendoring is the
wrong tool for almost all of it.

## A. Intent stage (create-task, clarify-task)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **The two-agents test** as the definition of "clear": would two reasonable agents, given only the artifact and the repo, build the same thing and agree when it is done? | Adopt | DESIGN and PLAN hints. The design-guard checks that three headings exist; it cannot check they pass this test, but the hint can state it as the bar. |
| **AC properties**: behaviour-focused, specific, testable, boundary-aware, non-redundant; with the three exceptions (structure IS the deliverable, formula defines correctness, migration needs cleanup). | Adopt | The `Acceptance Scenarios` guidance for `docs/plans/*-design.md`; `product-discovery` Step 3 brief. |
| **Tighten pass**: a subagent reads the artifact as the implementer would and proposes cuts; keep a line only if you can name the decision two agents would otherwise make differently. "Useful context" is not a reason. Run once, never loop. | Adopt | Two uses. (1) A PLAN hint after the plan is written. (2) The METHOD for the CLAUDE.md diet in Part 1: run this pass over the gotchas with the test "which regression does a hook author get wrong without this sentence?" |
| **Sizing rule of thumb**: 0.5–3 human-days per task; below, one-shot; above, split. Decomposition seams: walking skeleton, fidelity increments, sequential ordering, business rule, workflow step, data variation, functional then non-functional. | Adapt | The PLAN `VERTICAL SLICES` hint already says "decompose by behaviour"; the seams list is richer and should replace its second sentence. |
| **Exemplar calibration**: read an exemplar of comparable complexity before writing, to set length and register. | Adapt | `skill-scaffold` / `writing-skills`: point at an exemplar SKILL.md of the target length (auto-task's are 150–900 words; ACS's median is far above). |
| Task status lifecycle (`new → ready-for-dev → in-dev → ready-for-signoff → done`; off-ramps `rejected`, `later`). | Skip | ACS tracks phase in composition state and the branch ledger, not in the artifact. Adding a third state carrier would conflict with the "six canonical homes" rule. The `later`-with-revisit-trigger semantics already exist as `improvement-miner`'s parked revival criteria. |
| In-repo task store, epics, attachments. | Skip | Same reason. `docs/plans/` + openspec are the containers. |
| Clarify runs Steps 1–2 in a **fresh subagent so the task is read cold**, then asks on the main thread. | Adopt | `product-discovery` and any owned skill that validates an artifact it just wrote. Cold-read is the same mechanism as reviewer context isolation. |

## B. Plan stage (plan-task, panel, synthesize)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **"What would you be nervous about if the agent had only the task and codebase?" Address those and only those.** | Adopt | PLAN hint, verbatim. It is the best one-line definition of what a plan is for in either repo. |
| **Lock cross-boundary contracts; leave internals to the implementer**: no pseudocode, no names for new files/classes/functions, no line numbers, nothing that goes stale. No universal truths ("write tests"). No generic verification steps. | Adopt, with one tension | PLAN hint. **Tension**: ACS's `SCOPE MANIFEST` hint demands exact paths per task, including `Create:` entries, and `scripts/scope-conformance.sh` checks them. The manifest is a mechanically-checked scope fence, which is real value auto-task lacks. Resolution: keep `Modify/Test/Delete` exact (existing files), make `Create:` a directory or glob. |
| **Anti-Patterns section = real failures observed in past plans**, curated as they occur. | Adopt | Every owned SKILL.md that emits an artifact. ACS's `Red Flags` sections are the same idea; the discipline worth copying is "observed, not imagined". |
| **One self-audit pass, then stop** (research note: further self-reflection without external signal degrades). | Adopt | PLAN hint; also the argument for capping `agent-team-review` rounds (see D). |
| **Cross-family panel at PLAN**, synthesised without forced consensus. Mechanics: same prompt, fresh contexts, no cross-talk, one round, anti-sycophancy block, fail loudly if a panelist is unavailable, present raw responses by path. | Adopt via companion plugin | Add `core-skills` as a companion in the PLAN composition: `parallel` entry `use: /core-skills:panel + /core-skills:synthesize`, `when: installed AND codex available AND change is not lite`. Do not vendor: the pair is 480 words and lives upstream. |
| **`--lite` auto-downshift** when ALL hold: single package, no cross-boundary contract change, ≤3 ACs, no epic; when in doubt stay in full mode; announce the downshift. | Adapt | The threshold for the panel entry above, and a candidate replacement for `agent-team-review`'s "5+ files" trigger (see D). |
| Repo orientation line in the panel prompt because non-Claude panelists cold-start blind. | Adopt | Part of the PLAN panel hint. |

## C. Implement stage (impl-task, tdd)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **`git add <paths>`, never `-A` or `.`** — guards against sweeping in a parallel session's changes in a shared checkout. | Adopt | IMPLEMENT hint. ACS has documented exactly this hazard (#219, shared checkouts under concurrent sessions). Announce only; do not widen the push gate. |
| **Three red attempts → revert to last green, smaller step. Unexpected green → suspect the test** (AI-written tests mirror the code). | Adopt | IMPLEMENT hint alongside the external TDD skill. The three-strategies table (Fake It / Triangulate / Obvious) and "unexpected green" are the additive parts; the cycle itself is parity. |
| **Implementation Notes at end of impl**: deviations, surprises, learnings worth codifying, implicit assumptions, uncaptured follow-ups. | Adopt | Append to `docs/plans/*-plan.md` at the `finishing-a-development-branch` step. `openspec-ship` gathers as-built at SHIP; the delta is capturing while the context that knows the surprise still exists. `implementation-drift-check` should read it. |
| **Unrelated build failure → flag, never fix silently** (it may be another session's WIP). | Adopt | IMPLEMENT hint. Same concurrent-session rationale. |
| Formatter before final verification so formatting never surfaces as a verification failure. | Skip | Project-specific; belongs in the consuming repo's CLAUDE.md. |
| Predictable sibling worktree path, dead-leftover rule (0 commits ahead AND only untracked ⇒ safe to delete, else refuse). | Adapt | ACS uses the external `using-git-worktrees`. Record the leftover rule as a `.claude/knowledge/` convention; nothing else until a problem appears. |
| Re-read the plan before each step. Commit early and often. | Parity | Already in the external plan-execution skill. |

## D. Review stage (review-code, review-task, review-design, review-loop)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **Do-not-flag list** (pre-existing, tool-owned, correct-but-unusual, framework-handled, speculative, judgement-bound trivia) with the "trivial is not drop" rule. | Adopt | `agent-team-review` SKILL.md, new section before the lenses. REVIEW hint for the external `requesting-code-review`. |
| **Severity × autofix as independent axes**; `Autofix:` per-finding routing token; eligibility = single exact transformation, certain, diff-local, non-behavioural; Minor/Nit only. | Adopt the classification, skip the lane | `agent-team-review` finding format. The auto-apply lane needs an orchestrator step that ACS does not have; emit the token and let the in-session model apply. |
| **Authorship guard**: same-context self-review is structurally unreliable; if you wrote the diff in this context, downgrade to convention-checking and say so. | Adopt | `agent-team-review` and a REVIEW hint. ACS *enforces* reviewer dispatch via the completion hook (#241) but never states the reason; stating it prevents the "I'll just review it myself" shortcut in sessions where the gate is advisory. |
| **Cover every changed file or state why skipped. Verify by tracing call sites, not speculating.** Confidence 0–100: surface ≥80, `below_threshold` 50–79, drop <50. Machine-readable tally at the end. **No findings is a valid review; never invent findings.** | Adopt | `agent-team-review` output contract. The tally makes the review parseable by the verdict recorder. |
| **Triage as a router**: seven disposition categories, each with a cited reason; **never auto-reject Critical/Major** (surface for a human call). Recurrent autofix class ⇒ fix at the root. | Adopt | `agent-team-review` §finding disposition. ACS's §4a pairing rule is *stricter* for causal findings and stays; this adds the routing for everything else. |
| **Review-task evidence standard**: an AC passes only with specific evidence (a test, observed behaviour, output); "looks like it would work" is not evidence. Verify the *why*, not just the ACs. Flag, never fix. | Adopt | `implementation-drift-check` (it compares against Intent Truth; add the evidence bar) and a SHIP hint for `verification-before-completion`. `runtime-validation` is already the evidence engine. |
| **Convergence rule** (review-loop): stop only when no new substantive feedback AND no drift from the anchor AND under the cap; early exit on a clean round 1; hard cap 3–5; **every round must introduce external signal**. Reject categories: drift / evidence / disproportionate. Record dispositions in a table. | Adopt | `agent-team-review` round structure. The existing doubt-theater detector says when NOT to stop; this is the complementary rule for when TO stop. |
| **Review the merge-base range**, not `main..HEAD`, when main has advanced. | Adapt | REVIEW hint. The hooks already use merge-base (`_routing_base`); the model-side reviewer does not. |
| **Lens reviewers by risk, not by default** (research: naive fan-out of the same prompt loses to one strong pass + verify; the carve-out is disjoint-scope specialists for known high-risk domains). | Adapt | `agent-team-review` triggers on "5+ files OR auth/secrets/hooks/CI". The second clause is the research-backed one; consider making file count alone route to single-pass + verify, and lens fan-out only on the risk-domain clause. Re-look, not a change. |
| **Design review**: measure DOM geometry, check token fidelity in source, real input events, save frames per state×theme, no autofix lane. | Adapt | `runtime-validation` reference note for UI changes with a design artifact. Low priority. |
| No persona prompting in reviewers (task instructions only). | Adopt | `design-debate` uses architect/critic/pragmatist personas. Re-check against the cited result; the lenses in `agent-team-review` are task-scoped and fine. |

## E. Ship stage (ship-task)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **Verify the integrated tree after merge, before push**: a green branch is not enough, a parallel change can break it with zero textual conflict. | Parity, stronger in ACS | ACS's verdict is sha-bound; a rebase or squash produces a new sha, so the push gate already demands fresh coverage (#181, #219). Worth citing as validation of the sha-binding design. |
| `-D` not `-d` after a squash-merge; resolve `$primary` via `git worktree list --porcelain`; re-install deps in the primary when a manifest changed. | Adopt as knowledge facts | `.claude/knowledge/` (type: convention). Mechanics that bite once per repo. |
| Squash straight to main, no PRs; push authorised by invoking ship. | Skip | ACS is PR + branch protection + Claude Approvals by design. |

## F. Orchestration and resilience (auto-task's Guidance section)

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **Preflight: degraded vs stop-and-fix.** Missing optional component ⇒ degraded, proceed and RECORD it in the final report; present-but-broken component ⇒ stop now rather than die 20 minutes in. | Adopt the recording half | ACS canaries already warn at session start. The delta: carry accepted degradations into the verdict (`degradations[]`, advisory) so a SHIP report can say what was skipped. |
| **Parallel-session hygiene**: never `pkill -f <name>`; scope kills to the worktree path or `lsof -ti :<port>`; suspect a busy neighbour before a debugging rabbit hole. | Adopt | `.claude/knowledge/` convention + `runtime-validation` (it starts servers). |
| **Re-output the decision-relevant core of subagent output in the main agent**; reference long artifacts by path. | Adopt | `agent-team-review` / `agent-team-execution` lead instructions. Matches the harness fact that subagent reports never reach the user. |
| Subagent stall policy: rely on completion notifications, one long safety-net timer, kill and restart after 10 min of no progress, never skip a step. | Adopt | `agent-team-execution`. |
| Unattended posture (`--ship`): record open questions in the artifact, proceed on the best reading, list them in the report. | Adapt | Only for Routine-fired sessions. Interactive ACS should keep asking. |
| Use raw `git worktree add` at a predictable path, not the harness worktree tool, so the path survives handoff to an editor. | Adapt | Note in `agent-team-execution`; ACS's remote sessions do not hand off to an editor. |

## G. Skills design and meta

| Practice | Verdict | ACS landing spot |
|---|---|---|
| **Research corpus with a consolidated synthesis** that records which claims were re-validated, where the skills deliberately diverge, and a header saying "model names and benchmarks assumed expired, mechanisms hold". | Adopt the shape | This is where ACS's gotcha narratives belong. A `docs/research/` (or per-topic `docs/`) home for the push-gate design history, with CLAUDE.md keeping one-line pointers, is the concrete form of the Part 1 diet. |
| **"Guidance (DO NOT IGNORE!) — curate as we go along"** block at the top of each skill, 5–10 bullets, observed. | Adopt | Owned SKILL.md files over 3k words are the candidates: distil to a Guidance block plus references. |
| Never paste a default's text into a consumer; single-source it; PAIRED update lists. | Parity | ACS already does this (`persist-state.sh`, PAIRED notes). |
| **Three-layer markdown config** (defaults ← project ← local), per-leaf merge, provenance tag on every resolved leaf, unrecognised-heading lint. | Adapt the layering, keep JSON | ACS has user config + presets, no committed project layer. A `.claude/skill-config.json` project layer (thresholds, preset, companion roster) would let teams commit their routing posture. Keep JSON: auto-task's "nothing parses it, an agent reads it" rationale does not hold for ACS, whose hooks parse config with jq under Bash 3.2. Real feature; design doc first. |
| Vendoring script + CLAUDE.md invariant for cross-plugin skills. | Skip | ACS composes external skills by name with `when: installed`; that is the better mechanism for optional dependencies and is what this doc proposes for core-skills. |
| Skill namespacing for self-containment (`/at:*`). | Parity | `Skill(auto-claude-skills:...)`. |
| Book-lens skills (clean-code, ddd, goos, software-design red flags) used as review lenses by kaizen and review. | Adapt via companion | Out of ACS's routing scope to own. Add as a REVIEW `parallel` entry `when: core-skills installed` for design-quality lensing; `software-design`'s red-flags checklist is the one most worth pointing at. |
| Research skill (pre-committed resolution criteria, cite-or-flag, echo vs independent agreement, pre-mortem, new signal per round). | Adopt via companion + rules | DISCOVER `parallel` entry `when: core-skills installed`; the three rules go into `product-discovery` regardless (Part 1 §4). |
| Kaizen sweep. | Defer | Part 1 §6 stands: wait for `improvement-miner`'s approve-rate data. If it clears, kaizen's "already settled" filter and 3–5 cap are the design. |
| Manual release with version tag. | Skip | ACS auto-bumps on merge. |

## Tensions worth deciding explicitly

1. **Scope manifest vs "never name new files in a plan".** Both are defensible; ACS's is mechanically checked. Proposed resolution above (exact for existing files, glob for new). Decide before adding the plan-task hints or they contradict the existing one.
2. **Lens fan-out by size vs by risk.** The literature auto-task cites puts fan-out in the carve-out, not the default. ACS's file-count trigger may be over-firing. Needs a measurement, not an opinion: the review-verdict ledger can tell how often multi-lens review on a 5+-file diff produced a finding the single reviewer missed.
3. **Companion plugin vs owned copy for panel/synthesize.** Companion keeps ACS thin and upstream-tracked but adds an install prerequisite; owned copy is 480 words and would need a fixture, a content test, and a trigger. Recommendation: companion first; own it only if usage data says people hit the "not installed" note repeatedly.

## Suggested order of PRs, each small

1. **Hints only, no new skills**: PLAN (nervous-about, contracts-not-internals, seams, one self-audit), IMPLEMENT (explicit `git add`, three-red rule, unrelated-failure rule, Implementation Notes), REVIEW (merge-base range, authorship guard, evidence standard). Pure config text; the render check in `tests/test-attestation-measurement.sh` is the pattern for testing it.
2. **`agent-team-review` review contract**: do-not-flag list, severity × autofix classification, confidence bands, tally, disposition categories, convergence rule. One owned file plus its content test.
3. **Companion-plugin entries** for `core-skills`: PLAN panel (gated on codex + not-lite), DISCOVER research, REVIEW software-design lens, all `when: installed`.
4. **Knowledge facts**: squash-merge `-D`, `$primary` resolution, dep re-install, parallel-session process hygiene, worktree leftover rule. Five files via `capture-knowledge`.
5. **CLAUDE.md diet** (Part 1 §1), using the tighten-pass method from §A and the `docs/research/` shape from §G. Largest payoff, most review-sensitive, so last.
6. **Design doc, not code**: project-level config layer.
