# Do frontier models make our process layer net negative? — evidence audit & ablation plan

**Date:** 2026-10-03
**Status:** DESIGN persisted; recommends a measurement programme + a small set of low-risk demotions.
No implementation started.
**Question (owner):** have Opus 5.x / Fable 5 overshadowed obra/superpowers-style skills and flows so that
they are now net negative; should auto-claude-skills shed skills or rethink its approach?
**Method:** (a) internal evidence audit of every measurement this repo holds (subagent sweep of
CHANGELOG, `docs/plans/`, `tests/baselines/`, eval READMEs, probes, `.claude/knowledge/`, openspec
changes, PR descriptions; key claims spot-checked); (b) external evidence (web research; **Anthropic model
guidance read on the primary pages**; superpowers `RELEASE-NOTES.md` read locally at `8ca22db`; academic
results reached only at abstract level because the proxy blocked arxiv); (c) audit of our injected text.

## Answer in one paragraph

**Unknown for this plugin, and that is the main finding.** The repo has no measurement of any skill,
hint, directive or gate against a no-plugin control with Opus 5.x or Fable 5 as the working model. The
evidence we do have measures *uptake* (did the model follow the instruction / emit the format), mostly at
n≤5 on Opus 4.8, Sonnet aliases or Haiku 4.5. Every *outcome* comparison we ran found zero or negative
benefit. Meanwhile Anthropic's own guidance for these models says, in so many words, that verification
instructions, verify-with-a-subagent steps and skills written for earlier models can now **cost tokens
or degrade quality**. So the burden of proof should flip: from "remove only with evidence of harm" (the
PR #45 stance) to **"every per-prompt injection must show benefit over a no-plugin control on the models
people actually run."** We should not shed wholesale on vendor guidance alone; we should run the
ablation below, demote the handful of components that are already clearly dead weight, and re-centre
the plugin on what models cannot supply themselves: deterministic enforcement, evidence, and context.

## External evidence

### Primary — Anthropic model guidance (read 2026-10-03)
- **Opus 5** (`prompting-claude-opus-5`, "Task scope and over-verification"): *"Claude Opus 5 verifies
  its own work without being told to. If your prompt contains explicit verification instructions
  ("include a final verification step…", "use a subagent to verify"), remove them: instructions like
  these cause over-verification … removing them reduces wasted tokens with no loss in quality. The same
  applies to legacy harness scaffolding that adds separate verification steps."* Also: *"do not use
  subagents to verify or double-check your own work"*; review prompts saying "only report high-severity"
  are followed literally and under-report; Opus 5 tends to **widen** task scope.
- **Fable 5** ("Recommended scaffolding changes"): *"Skills developed for prior models are often too
  prescriptive for Claude Fable 5 and can degrade output quality. Review and consider removing older
  instructions if default performance is better."* But it **keeps**: *"Separate, fresh-context verifier
  subagents tend to outperform self-critique"* for long runs, and *"audit each claim against a tool
  result from this session"* (nearly eliminated fabricated status reports). Warns about overplanning on
  ambiguous tasks and about prompts asking the model to reproduce its reasoning (`reasoning_extraction`
  refusals).
- **All current models** (`claude-prompting-best-practices`): newer models are more responsive to the
  system prompt and may **overtrigger**; dial back "CRITICAL: You MUST…"; "If in doubt, use [tool]"
  causes overtriggering; dial back anti-laziness prompting.
- Sonnet 5.5 at `low` effort is the counter-case reported by the research agent: a "run a real check
  before reporting done" paragraph helps there. (Agent-reported; not re-read by me.)

### superpowers' own trajectory (RELEASE-NOTES.md, local)
The upstream author is cutting ceremony, not adding it: dropped the subagent plan-review loop (doubled
time, no measured gain, v5.0.6); one reviewer per task instead of two stages ("roughly twice as fast …
almost 50% fewer tokens", v6.0.0); **"`executing-plans` was a 64-line stub that measured the same as
running with no plugin at all"** → rebuilt as Native mode for mid-tier models (v6.4.1); **"frontier
models, including Opus 5.5, could get overzealous during plan writing"** → plans record decisions not
code, ~¼ the time and ~⅓ the tokens, 9/9 planted-defect probes on Sonnet 5 (v6.4.2). Self-reported,
small n, but directionally unambiguous.

### Academic (abstract-level only — treat as directional)
- Gloaguen et al., *Evaluating AGENTS.md* (arXiv 2602.11988): LLM-generated context files −3% success,
  +20% cost; human-written minimal files ~+4%.
- SkillsBench (2602.12670): curated skills +16pp overall but **only +4.5pp for software engineering**;
  self-generated skills ≈0; focused beats comprehensive.
- SWE-Skills-Bench (2603.15401): 39/49 public SE skills gave zero pass-rate gain; token overhead up to
  +451% at unchanged pass rate; the few winners were specialised.
- *The Regression Tax* (2607.22520, office tasks): skills broke 324 conditions the bare agent solved vs
  553 newly solved; names **"skill-description osmosis"** — behaviour shifts from mere presence in
  context.
- *Agent Skills Can Be Harmful* (2608.11888): largest efficiency drain is "excessive verification and
  heavy implementation pipelines".
- TDAD (2603.17973, small Qwen models): generic TDD procedure **raised** regressions; telling the agent
  *which tests to run* cut them sharply — context beat procedure.
- Mostly 4.5/4.6-era or small models; nothing peer-reviewed tests superpowers-style flows on 5.x.

## Internal evidence (what this repo has measured)

**Positive, but uptake not outcome, n≤5:** intent-convergence directive 0/5→5/5 (Opus 4.8); discovery
check as CURRENT step 5/5 (Opus 4.8; old hint's 0/5 not re-run); executing-plans precondition 3/5 vs
1/5 (`sonnet` alias); authorial-judgment no-fabrication 3/3→0/3 fabrications; assumption audit 0/5→4/5
on an output contract (PR #102: "the base model's judgment was already at ceiling — the gap is
structural"). Strongest, consistent lesson: **step-text in the composition chain is followed; advisory
"consider X" hints are not** (0/5, identical with the hint removed).

**Ceiling / no effect:** composition-uptake 16/16 on Fable 5 **with no directive-removed arm** — cannot
distinguish "the directive works" from "the model does this anyway" (`tests/baselines/composition-uptake.baseline.json`);
correction-ergonomics rewrites (ceiling); DB review gate parked — plain REVIEW already caught 0.95 of
seeded defects; design-seed pilot: 2/3 pairs favoured **no seed**, 0 favoured the seed
(`openspec/changes/design-seed-replication-instrument/proposal.md`); Serena banner: 441 transcripts,
7 Serena calls, zero reference queries; `agent-team-execution` zero real invocations
(`.claude/knowledge/check-usage-evidence-before-hardening-skill-path.md`).

**Costs and harms measured:** first-prompt injection mean ~4.2 KB, ~6-7 KB on DESIGN/REVIEW prompts
(`tests/test-injection-budget.sh`); 11/11 live `panel` routings false (older plugin version; PR #258
fixed 6); held-out consultation routing recall 12/30; contradictory save-path instructions vs upstream
superpowers (F2 in the sibling sweep doc); third-party skills hijacking routing (F1); 44 `when` fields
that no hook reads; gate friction (5/26 live denies were non-pushing Codex calls; #51, #131); shadow
corpus accruing at ~9% of plan, so the IMPLEMENT enforcement decision has no horizon; CI behavioral
evals that cannot detect a regression at n=3 and never deliver plugin injection to the subject.

**Never measured on any model:** all eleven superpowers process skills as skill-vs-none; fourteen owned
skills; ten composition hints (DESIGN→PLAN CONTRACT, PERSIST DESIGN, EVAL STRATEGY, CARRY SCENARIOS,
VERTICAL SLICES, SCOPE MANIFEST, ADVERSARIAL REVIEW, LEARN REMINDER, CAPTURE KNOWLEDGE, DEBUG ESCALATION);
all twenty `methodology_hints`; the true-catch rate of every gate.

## Component triage against the evidence

Legend — **Keep**: model cannot self-supply it. **Measure**: plausible either way; ablate first.
**Demote now**: low-risk change justified by existing evidence (opt-in or manual, not deleted).

| Component | Why | Call |
|---|---|---|
| Push/ship gates, verification **records**, suite-completion sentinel, openspec artifacts | Deterministic accountability; Anthropic's own advice is "use hooks for anything that must always happen"; Opus assessment: "deterministic enforcement exists at all" is our main advantage | **Keep**; add a gate ledger (true catch vs false block, minutes lost) |
| Context injection: Jira/Confluence, `.claude/knowledge/`, org hub, unified-context-stack, project-verification commands | Context the model lacks is where external evidence finds benefit (SkillsBench domain gains, TDAD) | **Keep**, and grow toward "which tests cover this" |
| Domain skills with playbooks: incident-analysis, alert-hygiene, supply-chain-investigation, security-scanner (deterministic) | Specialised knowledge; matches the skills that helped in SWE-Skills-Bench | **Keep**; add with/without runs |
| product-discovery assumption audit, authorial-judgment no-fabrication gate | Measured structural/format gains | **Keep** |
| `verification-before-completion` auto-injected as SHIP workflow | Directly contradicts Opus 5 guidance; our deterministic `verify-and-record.sh` evidence path already covers the accountability part | **Measure first (top priority)**; candidate to replace with the Fable-style one-liner "audit each claim against a tool result" |
| Mandatory TDD parallel hint in IMPLEMENT/DEBUG | Generic procedure; TDAD and SWE-Skills-Bench point to neutral/negative; context ("these tests cover the area") did better | **Measure**; candidate to swap procedure for test-selection context |
| `brainstorming` auto-fire on DESIGN-ish prompts; writing-plans for small changes | Overplanning risk named by Anthropic and by superpowers v6.4.2; Claude Code docs: skip the plan when the diff fits in a sentence | **Measure**; candidate size/ambiguity gate |
| `requesting-code-review` dispatching a reviewer subagent | Opus 5: don't verify own work with subagents; Fable 5: fresh-context verifiers outperform self-critique on long runs; native `/code-review` exists | **Measure** by diff size (small vs multi-file) |
| `using-superpowers` routing entry | A router-on-router; upstream already injects it at session start; "1% chance → MUST invoke" is exactly the overtriggering wording Anthropic warns about | **Demote now** (stop routing to it) |
| `dispatching-parallel-agents`, `agent-team-execution` | Opus/Fable 5 delegate readily (Anthropic says *cap* delegation); agent-team-execution has 0 real invocations | **Demote now** to manual-only |
| `using-git-worktrees` as `required` | Harness-native worktrees; upstream itself defers to them | **Demote now** to non-required |
| Advisory `methodology_hints` with no measured uptake (0/5 channel) | Measured ineffective channel; per-prompt bytes | **Measure** via leave-one-out; drop any non-inferior when removed |
| Consultation skills (panel, design-debate, second-opinion, synthesize), prototype-lab | Over-trigger record; opt-in value is real when asked | **Keep, narrow triggers** (existing probes) |
| "MUST INVOKE" / "HALT" step text | Our only measured-effective channel (16/16) — but no control arm; Anthropic warns imperative wording overtriggers | **Measure**: imperative vs plain wording vs absent |

## Rethink — what changes in the overall approach

1. **From process prescriber to accountability + context layer.** The plugin's durable value is what a
   stronger model makes *more* valuable, not less: deterministic gates and evidence records, routing as a
   thin index, and org/project context. Generic "how to do engineering" prose is what models absorb
   first and is the most likely to be redundant.
2. **Model- and effort-aware profiles, using the existing preset mechanism** (`config/presets/*.json`,
   resolved in `session-start-hook.sh` Step 6b). Add a `frontier-lean` preset (routing + gates + context;
   generic process directives off, verification mandates replaced by the claim-audit line) and keep
   `standard` for mid-tier / low-effort use, where Anthropic still reports verification nudges help. The
   default flips only if the ablation says so.
3. **Ceremony proportional to task size.** Gate brainstorm/plan/review fan-out on change size and
   ambiguity instead of on phase keywords alone.
4. **Inversion of the PR #45 asymmetry.** Additions *and* retentions must clear the same bar: benefit
   over a no-plugin control on current models, measured on outcomes (tests passing, planted bugs found,
   diff scope, tokens, wall time), not on uptake.
5. **Upstream drift as a standing risk.** superpowers is a hard dependency (6 of 8 phase drivers per the
   Opus assessment) and it is changing fast in the *lean* direction; our descriptions must track it
   (F2 in the sweep doc), or we re-inject the ceremony upstream removed.

## Ablation programme

### Phase 0 — free, deterministic, this week
- **Usage census** from local transcripts with the existing `tests/probes/real-prompt-replay/` tooling
  (privacy rules apply): per skill and hint, how often it fired and how often the model actually invoked
  the skill. Anything that fires and is never invoked is a pure token cost.
- **Injection census**: per-phase bytes from `tests/test-injection-budget.sh`, plus session-start
  output (currently unmeasured).
- **Gate ledger**: label the existing deny records (`push-gate-capture`, skill-gate capture) as true
  catch / false block, with minutes lost.

### Phase 1 — whole-plugin ablation (the decisive experiment)
- **Instrument:** the hook-delivered A/B harness (T1 in `2026-10-03-external-skill-repos-adoption-design.md`),
  extended from single prompts to multi-turn tasks in a scratch repo. Arms implemented as presets, so the
  hook code is identical across arms:
  - **A0** plugin off (superpowers also off)
  - **A1** superpowers only (their SessionStart bootstrap, no ACS)
  - **A2** ACS routing + gates + context, generic process directives off (`frontier-lean`)
  - **A3** current default (`standard`)
- **Task suite:** ~20 realistic tasks drawn from this repo's history and two external repos, each with a
  deterministic outcome check: hidden tests, planted bugs a review must find, a scope reference diff.
  Mix: 6 small fixes (one-sentence diffs), 8 multi-file features, 3 debugging tasks, 3 review tasks.
- **Models:** Opus 5.5 and Fable 5 first (the question's subject); Sonnet 5.5 at `low` as the expected
  counter-case. Model + CLI version pinned; provenance mismatch is a hard skip.
- **Design:** **paired** — every task runs in every arm, so analysis is per-task differences
  (sign/McNemar), which is far more sensitive per dollar than independent arms. 2 reps per task-arm gives
  40 paired observations per arm per model.
- **Outcome metrics:** task success (hidden tests), regressions introduced, planted-bug recall and false
  positives, diff size against the reference (scope creep), tokens, wall time, number of questions asked
  of the user.
- **Pre-registered decision rule** (per model):
  - **Net negative:** A0 or A1 success is non-inferior to A3 (A3 wins at most 2 more tasks of 20) **and**
    A3 costs ≥15% more tokens or wall time → flip the default to `frontier-lean` for that model and open
    Phase 2 on everything A3 adds over A2.
  - **Net positive:** A3 beats A0 by ≥3 tasks of 20 on success or planted-bug recall, with no rise in
    regressions → keep, and run Phase 2 to trim components that cost more than they add.
  - **Inconclusive:** neither of the above → keep the default, adopt `frontier-lean` as an opt-in
    preset, and extend the suite rather than re-running the same 20 tasks.

### Phase 2 — leave-one-out on what Phase 1 implicates
Priority order: verification-before-completion; TDD parallel hint; brainstorming auto-fire;
requesting-code-review subagent (small vs multi-file); imperative vs plain step wording; methodology hints
(batched, then bisected). Each run: remove one, keep the rest, paired on the same suite. Drop a component
when removing it is non-inferior on success and reduces cost; keep one only with a positive paired
difference. Replace composition-uptake's ceiling result with a run that includes a directive-removed arm.

### Cost and honesty constraints
- Budget-capped and explicitly invoked like `tests/probes/native-contracts/conformance.py`; never in the
  default suite.
- At 20 tasks, only large effects show up (about 3+ tasks of 20). That is acceptable for a
  keep/demote decision but must be reported as such, with no claims about small effects.
- `.claude/knowledge/hook-ab-needs-real-checkout.md` and `behavioral-eval-subject-read-contamination.md`
  apply: real checkout, and a subject that cannot read this repo's CLAUDE.md priming (the
  composition-uptake threat to validity).

## Demote-now set (low risk, reversible, separate small PR)
1. Stop routing to `using-superpowers` (upstream injects it at SessionStart anyway).
2. `dispatching-parallel-agents` and `agent-team-execution`: manual-only (no auto-routing).
3. `using-git-worktrees`: `required` → normal, deferring to harness worktrees.
4. Fix the superpowers description drift and the save-path contradiction (F2 in the sweep doc), so we
   stop re-injecting ceremony upstream already removed.

Each is a registry/config edit with routing fixtures updated. None needs Phase 1 to justify it, because
each rests on zero measured use, duplication of native behaviour, or a contradiction.

## Decisions requested
1. Approve Phase 0 (free) and the demote-now PR.
2. Approve the Phase 1 budget and model list (Opus 5.5, Fable 5, Sonnet 5.5 low).
3. Agree the inverted bar (retention must also show benefit) as policy going forward.
