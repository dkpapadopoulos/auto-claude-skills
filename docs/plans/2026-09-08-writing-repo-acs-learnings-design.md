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
