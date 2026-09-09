# Independent assessment (fresh context, different model)

Provenance: produced 2026-09-08 by a fresh-context agent on a different Claude model (Opus), reading only a worktree at origin/main plus clones of patforna/writing, auto-task, core-skills. It had no access to the session's own assessment. This is NOT a Codex run: the Codex CLI, credentials, and api.openai.com are all unavailable in this remote environment (proxy answers 403 to CONNECT). The prompt is in 2026-09-08-codex-cold-assessment-prompt.md; run it locally with Codex for the cross-family view. Word count of CLAUDE.md quoted below (14,167) was measured by the agent; re-measured on origin/main at 5032905 it is 13,877. Other counts re-verified: 19/30 gotchas name a test, 36/68 openspec dirs, README line 117 '18 skills', 6/8 superpowers drivers.

# Independent assessment: what ACS should learn from `writing`, `auto-task`, and `core-skills`

Scope: files on disk only. No git history read. All counts measured with `wc`/`ls`/`jq`/`python3` at the paths cited.

---

## A. What ACS is, and how it actually enforces its SDLC

- **It is a router plus a set of shell gates, not a pipeline.** `hooks/hooks.json` wires 9 lifecycle events to 22 hook scripts; `hooks/*.sh` + `hooks/lib/*.sh` total **10,923 lines of bash**. The three largest are `hooks/openspec-guard.sh` (1,695 lines / 111 KB), `hooks/skill-activation-hook.sh` (1,842 lines), `hooks/session-start-hook.sh` (1,682 lines), plus `hooks/lib/git-command.sh` (1,630 lines).

- **Routing is scored, not invoked.** `UserPromptSubmit` → `skill-activation-hook.sh` scores the prompt against regex triggers, adds priority/name/composition bonuses, then applies role caps (max 1 process, 2 domain, 1 workflow). `config/default-triggers.json` (66 KB, 1,618 lines) registers **41 skills**: 21 `domain`, 9 `process`, 8 `workflow`, 3 `required`. Nothing needs the user to name a skill.

- **Phase composition is data.** `config/default-triggers.json → phase_compositions` defines 8 phases (DISCOVER…LEARN), each with a `driver`, a `parallel` list gated on `when: installed`, `hints`, and for IMPLEMENT/SHIP a `sequence`. SHIP's sequence is 10 steps, from `project-verification` through `write-learn-baseline`.

- **Hard enforcement is one hook.** `hooks/openspec-guard.sh` is a `PreToolUse:Bash` gate with **7 named deny sites** (`grep -n '_DECISION="deny'`): `mutate-then-push`, `chain-review`, `chain-verify`, `verify-hardening`, `global-failclosed`, `phase-enforcement`, `routing-governance`. `hooks/skill-gate.sh` is the inverse posture — it denies out-of-sequence `Skill` calls but its header states "ANY infrastructure failure allows (exit 0, no output)".

- **Evidence, not assertion, is the currency.** A push is allowed when a gating milestone has a real `Skill` return (`skill-completion-hook.sh`), a branch-ledger record keyed on `(origin URL, branch)`, or a cross-token bridge bound to exact HEAD; and — for `verify-hardening`/`routing-governance` — a `~/.claude/.skill-project-verified-<token>` verdict whose `sha` covers HEAD. `scripts/verify-and-record.sh` writes that verdict from its own measured exit codes so the model never authors it.

- **It measures before it enforces.** `hooks/lib/implement-shadow.sh` logs would-block records for the not-yet-enforcing IMPLEMENT leg; `scripts/shadow-adjudicate.sh` computes an exact Clopper–Pearson band against a pre-registered n=29 / <10% rule. Nothing in `auto-task` or `core-skills` has an analogue.

- **Tests: 137 files, 38,284 lines** (`tests/*.sh`). But `.verify.yml` (`substrate: local`, `run: bash tests/run-tests.sh`) is read by the push gate, not by CI. `.github/workflows/done-gates.yml` runs **4** of those 137 files. So the suite gates *pushes from an ACS session*, not PRs.

- **Behavioral evals exist and are versioned.** `tests/run-behavioral-evals.sh`, `tests/test-run-behavioral-evals-variance.sh`, three files in `tests/baselines/`, and `.github/workflows/behavioral-evals.yml` pinning `@anthropic-ai/claude-code@2.1.198` and refusing comparison when run provenance differs from the baseline's.

- **The number that drives most of section E: `CLAUDE.md` is 14,167 words / 98,504 bytes.** `## Gotchas` alone is **13,316 words — 94%** of the file, in 30 bullets. The longest single bullet is **3,284 words**. **19 of those 30 bullets already name a `tests/test-*.sh` regression, and those 19 bullets are 12,881 words** — 97% of the Gotchas text is prose restating something a test already pins. This file loads into every session before the user's first word.

- **Skill bodies are also long.** 23 skill directories, 50,703 words of `SKILL.md`. Largest: `skills/incident-analysis/SKILL.md` 11,223 words, `skills/alert-hygiene/SKILL.md` 8,341, `skills/agent-team-review/SKILL.md` 5,489. Exactly one word cap exists anywhere — `tests/test-incident-analysis-content.sh:727` asserts `-le 11500`, and the file currently sits at 11,223 (97.6% of the ceiling).

For contrast: `auto-task/CLAUDE.md` is **252 words**, `core-skills/CLAUDE.md` is **113 words**, and auto-task's largest skill (`skills/auto-task/SKILL.md`) is 2,865 words.

---

## B. What the essay and the two plugins do that ACS does not

| Practice | Evidence in source | Verdict | Where it lands in ACS | Why |
|---|---|---|---|---|
| **Rules live as mechanical tests; CLAUDE.md shrinks to what can't be encoded** | `writing/README.md`: "instead of adding more rules, I started to enforce design rules, conventions, and gotchas mechanically as automated tests whenever I could… Over time, CLAUDE.md shrank down to primarily process stuff or gotchas that were hard to encode". `auto-task/CLAUDE.md` = 252 words | **Adopt** | `CLAUDE.md` § Gotchas → `docs/gotchas/<test-name>.md` | ACS has already *done* the encoding — 12,881 of 13,316 gotcha words sit in bullets naming their own regression test — and then pays for it a second time in every session's context |
| **A task-quality gate before planning: "would two reasonable agents build the same thing?"** | `auto-task/skills/clarify-task/SKILL.md` § Goal, verbatim; plus a cold-read subagent (Step 5 Verify, cap 3 rounds) and `create-task` Step 5 "Tighten" which cuts every line "a capable agent wouldn't need" | **Adopt** | DESIGN→PLAN, where `skill-activation-hook.sh:1691-1708` already runs the design-guard | ACS's guard greps for three headings and counts GIVEN/WHEN/THEN. Presence is not adequacy; a well-formatted ambiguous design passes |
| **Explicit do-NOT-flag list applied by the reviewer, before findings exist** | `auto-task/skills/review-code/SKILL.md`: six named drop categories (pre-existing, tool-owned, correct-but-unusual, framework-handled, speculative, judgement-bound trivia). `docs/research/2026-07-03-consolidated-synthesis.md`: "The explicit do-NOT-flag list is the highest-leverage prompt element" | **Adopt** | `skills/agent-team-review/SKILL.md` §2 reviewer dispatch | ACS's severity floor (§4) runs in the *lead*, after the finding arrives and before the expensive §4a adjudication. Dropping earlier is strictly cheaper |
| **Autofix lane, orthogonal to severity, with a routing token** | `review-code/SKILL.md`: "**Autofix** is whether the fix is mechanically certain and non-behavioural — orthogonal to severity"; `Autofix:` is "the routing token"; Minor/Nit only, never bypasses the human gate for Critical/Major | **Adapt** | `agent-team-review` finding contract + a triage step | ACS has no path between "drop it" and "adjudicate it with a paired control". A one-character typo currently costs a §4a experiment or gets floored away |
| **Preflight on the tool roster before a long run** | `auto-task/skills/auto-task/SKILL.md` Step 0.4: "so a run that would die twenty minutes in stops now, not later" — checks second model, verification command, design-review server; outcomes `degraded` / `stop-and-fix` | **Adopt** | `session-start-hook.sh`, or a SHIP precheck | ACS's canaries check *its own* gate libs and plugin drift. Nothing checks the tools the 10-step SHIP sequence will need |
| **Cross-family model panel for planning and review** | `core-skills/skills/panel/SKILL.md` (Claude + Codex, fresh context each, single round, no cross-talk) + `synthesize/SKILL.md` (merge rubric, "Do not force consensus"). `auto-task/README.md` FAQ: cross-family review "is the part of this workflow that has most reliably caught real bugs" | **Adapt, not adopt** | `agent-team-review` §2 (one lens slot); PLAN phase | ACS's four reviewers are one model in one harness — correlated errors. But the author's *own* synthesis downgrades the claim: "context isolation is the load-bearing part", cross-model is "a secondary diversity lever". ACS already has isolation and claim-withheld dispatch, so the marginal gain is real but smaller than the README asserts |
| **Anti-sycophancy block appended to every independent-opinion prompt** | `core-skills/skills/panel/SKILL.md` Step 2 and `sop/SKILL.md` Step 3, verbatim identical block | **Adopt** | Reviewer dispatch brief | One line. ACS withholds the implementer's claims but never instructs the reviewer against agreement |
| **A persistent, numbered work artifact with a status lifecycle** | `auto-task/README.md`: "Tasks are the central artefact… They span the entire workflow, accumulating and preserving state across agent sessions"; `create-task/SKILL.md`: `new → ready-for-dev → in-dev → ready-for-signoff → done`, off-ramps `rejected`/`later` | **Adapt** | `openspec/changes/*/proposal.md` frontmatter | ACS's cross-session carrier is `~/.claude/.skill-*-<token>` files that `session-start-hook.sh` GCs at 7 days. `docs/plans/` is gitignored. `openspec/changes/` is durable but carries no state field — measured: **36 active vs 68 archived** change dirs |
| **A condensed synthesis layer over a research/decision corpus, with an explicit precedence rule** | `auto-task/docs/research/2026-07-03-consolidated-synthesis.md` (1,097 words over a 102,759-word corpus): "when they disagree with this file, this file wins"; "**mechanisms are live, numbers are dead**"; a § Supersessions and Resolved Contradictions | **Adopt** | `openspec/` root, over the 104 change dirs | This is the structural fix for ACS's CLAUDE.md problem: not deletion, a tier |
| **Scheduled holistic health sweep, capped, with "already captured ≠ fresh finding"** | `core-skills/skills/kaizen/SKILL.md`: 8 dimensions incl. task hygiene ("stale tasks… status lies… bloat (>20 drafts)"), "Cap at 5 findings total", anti-pattern list | **Adopt** | New skill, or extend `improvement-miner` | ACS has per-change review but nothing that looks at the whole. Its own 36 open changes is precisely a task-hygiene finding |
| **Design review that measures rather than eyeballs, incl. source-level token fidelity** | `auto-task/skills/review-design/SKILL.md` Step 2: "Read DOM geometry / computed styles… Computed styles collapse the token name, so this is a source-level check"; real key/click events, not synthetic dispatch | **Adapt (low priority)** | `skills/runtime-validation/SKILL.md` | ACS covers browser E2E and a11y; the token-fidelity and real-input points are genuinely sharper. But ACS is not a frontend plugin |
| **Vendoring with a named source of truth** | `auto-task/CLAUDE.md` § "Vendored Skills — Do Not Edit Here"; `scripts/vendor.sh` | **Skip** | — | ACS discovers installed plugins at runtime, which is the better answer to the same problem |

---

## C. What ACS already does better

1. **Deterministic enforcement exists at all.** `auto-task` and `core-skills` ship **zero hooks** (no `hooks.json`; the only `.sh` files are `scripts/vendor.sh`, `skills/create-task/scripts/alloc-task.sh`, and two demo scripts). Every rule in auto-task is prose the model may decline to follow — including `auto-task/SKILL.md`'s "Aim to complete all the steps… with full autonomy". ACS's 7 deny sites survive a model that decides otherwise.

2. **Tests.** ACS: 137 files / 38,284 lines, several mutation-verified. auto-task: **none**. Its own `tasks/001-at-config-slice-1.md` says so — "Repo has no machine parser or test harness — keep `/at:config` markdown-readable" — and verifies its acceptance criteria by "**Behavioural simulation** (Step 10, applying the skill's § Resolve + grammar + § Inspect): … Pass." That is the model asserting its own instructions would work.

3. **Evals.** The essay names this as an open failure: "Evals for open-ended work… My own pipeline has none, vibes only, which is a problem." ACS has `tests/run-behavioral-evals.sh`, variance analysis, three checked-in baselines, and a CI workflow that pins the CLI version and refuses a comparison when provenance drifts. ACS is ahead of the essay here, not behind.

4. **No invocation required.** `/at:auto-task` must be typed. ACS scores every prompt and produces no output when nothing matches.

5. **Adjudication rigor.** `agent-team-review` §4a demands a pair that *could* disagree, a named oracle before the run, a comparable positive control before any rejection, and a `could-not-reproduce` disposition that constrains the verdict. auto-task's triage (`auto-task/SKILL.md` §6.1) requires "a one-line cited reason" and nothing more.

6. **Claim-withheld dispatch.** `agent-team-review` §2 forbids passing the implementer's self-summary to a reviewer. auto-task's authorship guard covers *who* reviews, not *what they are told the author concluded*.

7. **Self-diagnosis of its own degradation.** `_DEGRADED_MSG`, the session-start push-gate canary, the plugin drift canary. auto-task's preflight checks external tools once; nothing tells you the workflow itself fell open.

8. **A publication trust boundary.** `hooks/publish-guard.sh` + `scripts/memory-leak-check.sh` + `skills/agent-safety-review/`. Nothing comparable in either repo.

---

## D. Where the two approaches genuinely conflict

**1. Long CLAUDE.md vs mechanical encoding. Take the essay's side, with one correction.**
The essay's claim is causal, not aesthetic: "it was hit and miss and **got worse as I added more rules**." ACS is the extreme case — 14,167 words, of which 12,881 restate things `tests/*.sh` already assert. But "delete it" is wrong: the gotchas carry *rationale* ("do not simplify this to X, because bash 3.2 bracket-class substitution is O(n^2.7)") that a passing assertion cannot carry, and deleting it invites the exact re-introduction the test was written for. The correct move is relocation, not deletion: assertion → test (done), rationale → a comment at the assertion site or `docs/gotchas/<test>.md`, CLAUDE.md → a one-line index. The cost of not moving is ~18k tokens of every context window, spent before the user says anything.

**2. Autonomy boundary. Take ACS's side.**
`auto-task/skills/auto-task/SKILL.md` Step 9: with `--ship` and no Critical/Major open, it runs `/at:ship-task` — squash-merge to main and `git push origin main` — with no human approval. `auto-task/README.md` defends it: "by ship time the change has been reviewed harder than most PRs ever are." ACS's push gate denies until REVIEW and VERIFY milestones carry real invocation evidence, and `routing-governance` denies unverified routing pushes outright. These cannot both be right. auto-task's position is defensible **for its author** — solo, trunk-based, present at the gate, "cruise control, not Full Self-Driving" — but it is a personal risk setting, not a property others inherit. The asymmetry that decides it: auto-task's autonomy is bounded by a human who is there; ACS's gate exists for the case where nobody is.

**3. Where the human gate sits. Both are wrong; the author's own research says so.**
`docs/research/2026-07-03-consolidated-synthesis.md`: "Plan review is the highest-leverage checkpoint (~30:1 payback). Auto-task deliberately trades this human gate for autonomy, moving the human gate to ship." ACS also has no human gate on the plan — its DESIGN→PLAN check is a heading grep. So both systems spend their scarce human attention at the *end*, on output, rather than at the *front*, on intent — which is exactly what the essay identifies as the real bottleneck ("Creating well-defined tasks is hard, time-consuming and high-leverage. I spend a good chunk of my time here"). ACS's fix is cheap because the guard already fires at that transition (recommendation 3).

**4. Prose specificity vs overprompting. Mostly the essay's side, but not uniformly.**
The essay: "Assume the model is very competent and beware of over-constraining." `create-task/SKILL.md`: "Don't spell out what a capable agent infers from the repo… Test per line: would two reasonable agents build the same thing without it?" Applied honestly to ACS, most gotcha prose fails that test *because the test already enforces it*. But `agent-team-review` §4a (~1,400 words on adjudicating one finding) **passes** it: it exists because of a dated, documented failure (2026-08-12) where a real finding read as refuted, and it instructs behaviour the model provably did not produce unprompted. So the cut criterion is evidence-of-need, not length. ACS should apply the essay's test literally, bullet by bullet — not adopt a global word budget.

**5. Self-containment vs runtime composition. Split.**
`auto-task/CLAUDE.md`: "This plugin is self-contained: its skills invoke each other via the `/at:` namespace… The only external reference is the `codex` plugin, which is **optional** — skills must degrade gracefully (documented fallback)." ACS's compositions invoke `Skill(superpowers:…)` for **6 of 8 phase drivers** (DESIGN, PLAN, IMPLEMENT, REVIEW, SHIP, DEBUG) and for both push-gate milestones (`requesting-code-review`, `verification-before-completion`), while `README.md:144` files superpowers under *Optional Integrations* and states "The plugin works without every companion integration." auto-task is right that a hard dependency must be declared and must have a documented fallback; ACS is right that runtime discovery beats vendoring. ACS should declare the dependency, not vendor it.

---

## E. Top 5 recommendations, ranked by payoff per unit of effort

**1. Relocate the Gotchas out of `CLAUDE.md`.**
*First change:* take the 19 bullets that already name a `tests/test-*.sh` (12,881 words) and move each to `docs/gotchas/<test-basename>.md`, verbatim. Replace each with a one-line index entry: `- <one-sentence claim> — pinned by tests/test-X.sh, rationale in docs/gotchas/test-X.md`. Add a `tests/test-claude-md-budget.sh` asserting `wc -w CLAUDE.md` under a ceiling you set *below* today's value (the `incident-analysis` cap at 11,500 against an 11,223 file is a ratchet, not a constraint — don't repeat that shape). Pure relocation, no logic change, and it returns roughly 17k tokens per session.

**2. Put the do-not-flag list and the anti-sycophancy line in the reviewer dispatch brief.**
*First change:* copy the six drop categories from `auto-task/skills/review-code/SKILL.md` § The Do-Not-Flag List into `skills/agent-team-review/SKILL.md` §2's reviewer prompt, plus `core-skills/skills/panel/SKILL.md` Step 2's block verbatim. Keep the §4 severity floor — this is a cheaper first filter, not a replacement. ~25 lines; `tests/test-reviewer-dispatch-brief.sh` already exists and is CI-run, so the assertion has a home.

**3. Make the DESIGN→PLAN guard check adequacy, not headings.**
*First change:* in the DESIGN composition's `hints` (`config/default-triggers.json → phase_compositions.DESIGN`), add a step that spawns one cold-context subagent with only the design doc and the repo, asking `clarify-task`'s question verbatim: would two reasonable agents build meaningfully different things, or disagree on whether it is done? Route gaps back as numbered questions with a recommended answer. Leave `skill-activation-hook.sh`'s heading grep as the deterministic floor beneath it. This is the highest-leverage change in the whole comparison and the one both systems currently skip.

**4. Add a synthesis tier over `openspec/`, and a capped health sweep.**
*First change:* write `openspec/SYNTHESIS.md` following `auto-task/docs/research/2026-07-03-consolidated-synthesis.md`'s shape — per-area actionable claims, an explicit "when this disagrees with a change doc, this file wins", and a § Supersessions. Then run one `kaizen`-style pass over the **36 active** change dirs against 68 archived, capped at 5 findings, to decide what is live, superseded, or abandoned. The synthesis is also where relocated gotcha rationale that outgrew a single test should land.

**5. Add a cross-family reviewer slot and a run preflight.**
*First change:* in `skills/agent-team-review/SKILL.md` §2, when the codex plugin is present, run the `adversarial-reviewer` lens through it read-only/sandboxed (§6 already specifies the sandboxing rationale) instead of offering a second opinion after the verdict; keep today's §6 offer as the no-codex fallback. Pair it with an `auto-task` Step 0.4-style preflight before the SHIP sequence: resolve the gate command, check the reviewer model is reachable, report `degraded` vs `stop-and-fix`. Ranked last because it adds an external dependency and, per the author's own synthesis, buys less than his README claims.

---

## F. Wrong or overclaimed, on both sides

**ACS**

1. **`README.md`: "This plugin ships 18 skills."** The bundled-skills table has 18 rows; `skills/` has **23** directories and `config/default-triggers.json` registers **22** entries invoking `auto-claude-skills:`. `authorial-judgment`, `capture-knowledge`, `improvement-miner`, `supply-chain-investigation` and `project-verification` are shipped, registered, and absent from the table.

2. **`README.md:144` files superpowers under "Optional Integrations" and claims "The plugin works without every companion integration."** Measured: 6 of 8 `phase_compositions` drivers are `Skill(superpowers:…)`, and both push-gate gating milestones (`requesting-code-review`, `verification-before-completion`) are superpowers skills. The enhancer claim is true; applied to superpowers it is not.

3. **The README's enforcement framing is looser than the code.** README: "Guardrails that support agentic work… most enforcement is in-session guidance, not blocking" — accurate. But the README never says the 137-file suite is not a CI check. `CLAUDE.md` states it correctly (".verify.yml is the LOCAL gate… the full tests/run-tests.sh suite is NOT a CI check"); `.github/workflows/done-gates.yml` runs 4 files. A reader of the README alone will overestimate what a PR is checked against.

4. **The IMPLEMENT deny-flip is described as gated on a corpus that has never been allowed to accumulate.** `CLAUDE.md` pre-registers n=29 episodes with a horizon of ~2026-09-08 (today). It also records that v2 produced 0.0625 episodes/day against a pre-registered 0.697, and that `IMPLEMENT_SHADOW_PREDICATE_VERSION` has since gone 2→3 (#219) and 3→4 (#229), each bump making prior records unpoolable and resetting n to 0. Both bumps are individually correct. The aggregate is that the instrument resets every time it collects data, and at the observed rate n=29 is years out. The text insists "the BAR does not [move]… not open," which is intellectually honest about the threshold and silent about the fact that the measurement can no longer terminate. Say that plainly, or change the design so a predicate bump migrates rather than discards.

5. **`tests/test-incident-analysis-content.sh:727` caps `incident-analysis/SKILL.md` at 11,500 words; it is 11,223.** A ceiling set 2.5% above the current value constrains nothing.

**Essay / auto-task / core-skills**

6. **"In the two months following auto-task, I shipped about twice as many tasks per month as I averaged in the four months before"** (`writing/README.md`). The disclaimer covers n=1 and solo, but not this specific confound: auto-task landed simultaneously with the rebuilt strategy, with the frontend work (which the same essay says LLMs are unusually good at: "boilerplate-to-logic ratio is high"), and after 8 months of codebase conventions accumulating — which he elsewhere credits directly for better output. Tasks/month also holds nothing constant about task size.

7. **`auto-task/README.md`: "It's the discipline you'd apply if you were building without AI, enforced on every run."** Nothing enforces it. The plugin ships zero hooks and zero tests; every step of the pipeline is prose in a `SKILL.md` that the model may skip, and `auto-task/SKILL.md`'s own § Guidance opens with "**(DO NOT IGNORE!)**" — an instruction you only write when you expect it to be ignored. "Instructed on every run" is the accurate word.

8. **The cross-family claim outruns the author's own evidence, and his own synthesis says so.** The essay concedes the confound ("Switching model family meant switching harnesses, so some of what I put down to perspective may just be scaffolding") and reports "sample size was single digit". `docs/research/2026-07-03-consolidated-synthesis.md` then downgrades it explicitly: "'must be different foundation models' **softens** to 'inject diversity via model, seed, or context'… **context isolation is the load-bearing part**", and "same-model critique in a fresh context recovers most of the benefit". Yet `auto-task/README.md` still calls same-family fallback "materially worse in practice" and the FAQ calls cross-family "the part of this workflow that has most reliably caught real bugs". The README and the research file disagree; the research file is the better-evidenced one.

9. **`review-code/SKILL.md` ships uncalibrated numeric thresholds that its own research log flags.** "Attach confidence 0–100: surface at ~80+; collect 50–79… drop below 50." The synthesis: "the 80-confidence gate is **inherited and uncalibrated** (still true of review-code as implemented)." This is the corpus's own "numbers are dead" rule being violated inside the same repository. ACS's `agent-team-review` explicitly rejects confidence-weighted gating ("Confidence is advisory only… not a filter or demotion input") and is right to.

10. **`/at:config`'s single-source claim is 2/9 complete while the README presents 9/9.** `config/SKILL.md` § Scope: only Task Store and Feedback Snapshots resolve; "The other seven headings are **recognised**… but their values still live in the skills that consume them." `README.md` § Configuration lists all nine as "Configurable per project". The consequence is measurable duplication of exactly the kind the skill was created to remove — the verification-discovery default appears verbatim in three places (`skills/auto-task/SKILL.md:76`, `skills/ship-task/SKILL.md:67`, `examples/auto-task.config.md:17`), against `auto-task.config.defaults.md`'s own rule: "To change a default, edit it here — nowhere else."


---

# Sparring transcript

## Round 1 challenges (from the session)

Seven challenges: (1) task-hygiene finding rests on a count; (2) E1 word ceiling contradicts D4 evidence-of-need; (3) F4 predicate migration is infeasible per the withdrawn backtest; (4) E3 cold-read check is prose enforcement, gate on artifact existence instead; (5) cross-family ranked last though `when: installed` is free; (6) confidence bands vs agent-team-review line 215; (7) four omissions.

## Round 1 replies

# Sparring round 1 — replies

Re-measured in the same directories. Summary: **I concede 1, 3, 4, 5 and all four of 7; I resolve 2 by replacing my own proposal with a better one; I hold 6 with one concession.**

---

## 1. Task-hygiene finding — **withdrawn.** The count was doing work the evidence could not support.

First, a measurement note that cuts against both of us: **mtime is uninformative in this checkout.** Every one of the 580 `*.md` files in `acs-main` — active changes, archived changes, skills, tests — carries mtime `2026-09-08`:

```
find . -name "*.md" -not -path "./.git/*" -printf "%TY-%Tm-%Td\n" | sort | uniq -c
    580 2026-09-08
```

The tree was stamped when it was placed in the scratchpad. So "every active dir was last modified 2026-08-25" is not derivable from disk here, and I can neither confirm nor refute it from the permitted sources. I flag that rather than accept it as measured.

But the challenge lands anyway, on better evidence than mtime. I looked for an on-disk signal that *does* discriminate and found one — outbound references to each change's slug from outside `openspec/`:

| signal | result |
|---|---|
| active change dirs referenced ≥1x outside `openspec/` | **27 of 36** |
| top referenced | `gate-status` (18), `verify-and-record` (15), `review-verdict` (10), `implement-shadow-event` (6) |
| active dirs carrying a `tasks.md` at all | **1 of 36** (`checkpoint-stamping`, 4/4 boxes ticked) |

`scripts/verify-and-record.sh` and `scripts/gate-status.sh` both exist and ship. So a large share of the 36 describe work that is **done and merged but not archived** — archival lag, not abandonment. And with only one `tasks.md` in the whole active set, there is no completion signal to read even if I wanted one.

**What I would have needed before calling it a finding:** a per-dir disposition sampled and checked, not a count — for each dir, does the thing it specifies exist in the code, and is it referenced by a live test. That is the discipline `core-skills/skills/kaizen/SKILL.md` states outright: *"Quantify: 'N of M sampled files follow the convention' is more useful than 'some files don't follow it.'"* I reported M and never sampled N. By `auto-task/skills/review-code/SKILL.md`'s own do-not-flag list — the one I recommended ACS adopt in E2 — my row was **Speculative**: "anything you cannot pin to a `file:line` with a concrete failure mechanism." I flagged a number, not a mechanism.

**Does E4 survive?** Split verdict:

- The **synthesis half survives untouched.** It never rested on staleness. 104 change directories and no condensed tier is a structural claim about the corpus's shape, not its freshness.
- The **sweep half is re-founded, and lands somewhere better.** What the measurement actually shows is that `openspec/changes/` gives you **no way, from disk, to tell in-flight from shipped-not-archived from abandoned** — because there is no status field. That is not an independent hygiene finding; it is *the same finding as B row 8* (persistent artifact with a status lifecycle), arriving from a second direction. So the honest move is to collapse it: B row 8 goes up in importance, E4's sweep clause becomes "add `status:` frontmatter to `proposal.md` and let the archive decision read it", and the kaizen sweep drops from a recommendation to a thing worth doing *after* there is a field for it to read. My own bad inference is the argument for the fix.

---

## 2. The contradiction is real. I resolve it by discarding my E1 assertion and replacing it with a structural one.

You are right that as written they conflict. E1 asserts a global word ceiling; D4 says the criterion is evidence-of-need, not length. A word budget cannot tell you *which* words go, and if it is the only guard it will be satisfied by cutting the wrong ones.

The measurement resolves it cleanly:

| Gotcha bullets | count | words | largest single bullet |
|---|---|---|---|
| **cite a `tests/test-*.sh`** | 19 | **12,881** | **3,284** |
| **cite no test** | 11 | **405** | **125** |

The bullets that genuinely cannot be encoded — the ones D4 protects — are *already* short and disciplined: 11 bullets, 405 words, none over 125. **All the bloat is in bullets that already have a test.** So D4's per-bullet evidence test and E1's relocation select the identical 19 bullets. There is no disagreement about *what* to cut; there was only a bad choice of guard.

**What a ceiling is for, given D4:** it is not a quality criterion, it is a **ratchet against re-accretion**. Relocation is worthless if the 12,881 words return one bullet at a time. But it should assert the *structural invariant*, not an aggregate budget:

> A `## Gotchas` bullet that names a `tests/test-*.sh` MUST be an index line (≤ N words). A bullet naming no test is unconstrained.

That is mechanically checkable, it is exactly D4's rule expressed as an assertion, and it leaves the 11 hard-to-encode bullets free — which is the whole point of D4. It also fails loudly in the right place: the way to satisfy it is to write the test, which is the behaviour the essay is recommending. I withdraw `test-claude-md-budget.sh` as specified and substitute this.

---

## 3. **Conceded.** My phrasing was wrong; the feasible version is narrower and forward-only; your alternative disposition is the primary one.

"Change the design so a predicate bump migrates rather than discards" is infeasible as written, for precisely the reasons you name. Re-evaluating v3 records under v4's predicate requires knowing whether each recorded push was deletion-only — which requires the command text, which `hooks/lib/implement-shadow.sh` deliberately never writes (CLAUDE.md: "Raw command text is never written"), because shell text cannot be robustly de-secreted. And CLAUDE.md already records the general form of this as **withdrawn as infeasible** (2026-07-28): overwritten ledger snapshots, mutated-in-place state, squash-merged branches with no recoverable merge-base. My recommendation was re-proposing a thing the repo had already investigated and killed. I withdraw it.

**Is there a feasible version?** A narrow one, and it is forward-only:

> Record the *discriminators* a future predicate would filter on, not the command that produced them. v3→v4 was a **narrowing** bump: it removed deletion-only pushes from the population. Had each record carried a `deletion_only` boolean — computable at write time by the same `command_push_is_all_deletions` the guard already runs, and carrying no command text — v3 records could have been re-classified by filter rather than discarded.

That works for narrowing bumps and not for widening ones, and it rescues **nothing already recorded**. So it is a cheap hedge against the *next* bump, not a repair.

**Your disposition is the right primary one.** The honest statement is: *at the observed v2 rate (0.0625 episodes/day against a pre-registered 0.697), with n reset to 0 twice by correct predicate bumps, this measurement does not terminate on any horizon the design contemplates* — and that should be written down as a fact about the instrument, not left as an implication a reader has to assemble from three separate bullets. F4's actual claim was always that the text is silent on non-termination while insisting the bar is "not open"; that claim stands and is untouched by the feasibility of any fix. I over-reached by attaching a remedy to it.

---

## 4. **Conceded, and your version is better than mine.** The mechanism already exists in the same code path.

You have caught a real inconsistency: C1 credits ACS for not relying on prose, then E3 proposes a hint. A hint is a "DO NOT IGNORE" line with extra steps.

Your proposal works, and ACS already does this exact thing three ways:

- `skill-activation-hook.sh:1691-1708` **already reads `design_path` from session state and greps the file** for `## Capabilities Affected` / `## Out-of-Scope` / `## Acceptance Scenarios`, and already counts GIVEN/WHEN/THEN occurrences. Adding one more grepped section is a change in the same function.
- The REVIEW composition already has the pattern declared as data: `"gate": "artifact-presence"` with an `artifacts` list.
- `project-verification` is the full template: **the model runs the check, a script writes the verdict, a hook reads it.** The model judges; the hook enforces only that judging happened.

So E3 becomes: the cold-read subagent writes its verdict to the design doc as a `## Clarification` section (or a `clarify_verdict` key via `scripts/persist-state.sh`, which already exists and self-resolves the token); the design-guard greps for it exactly as it greps for the other three. The hook enforces **that the check ran**; it never evaluates the answer.

**Honest limit, which I should state rather than let the upgrade oversell it:** the artifact's contents are model-authored, so this is forgeable — a model that wants to skip can write an empty verdict. That is the same posture `skills/project-verification/SKILL.md` already declares about itself ("the evidence is advisory audit data, **not a trust boundary** — a session-written file is forgeable"). What it buys is raising the cost of skipping from *zero and invisible* to *an affirmative false artifact*, which is the bar every other evidence artifact in ACS sets. That is a real improvement over a hint and I should have proposed it that way. E3 is revised accordingly and keeps its #1-by-leverage position, now with an enforcement story that matches C1.

---

## 5. **Ranking conceded. The objection was to the claim, and I let it contaminate the ranking.**

Two separable things, and I collapsed them:

- **The claim** — `auto-task/README.md`'s "materially worse in practice" and "the part of this workflow that has most reliably caught real bugs", against the same author's synthesis saying "context isolation is the load-bearing part" and cross-model is "a secondary diversity lever". **F8 stands unchanged.** The README overclaims relative to the repo's own research file.
- **The mechanism** — a `parallel` entry gated `when: installed`. I ranked E5 last "because it adds an external dependency", and that reason is simply wrong: `when: installed` **is** how ACS already handles all eleven optional plugins in the `plugins` block, and its cost when Codex is absent is zero. I applied a hard-dependency penalty to something ACS's architecture treats as free.

**Revised ranking: E5's composition half moves up to #2**, behind the CLAUDE.md relocation and ahead of the reviewer-brief change, on cost-per-unit grounds — it is a data edit to `phase_compositions`, not a code change. The `agent-team-review` §2 half (swapping the adversarial lens onto Codex) stays lower, because that one *does* change review semantics and should follow the do-not-flag change rather than precede it.

One thing I hold: a secondary diversity lever is still worth having *when free*, but the expected gain should be stated as the synthesis states it, not as the README does. Adopting the mechanism while inheriting the claim is how an overclaim propagates.

---

## 6. **Held, with one concession — and the concession is the part worth taking.**

**Steelman, stated at its strongest:** `review-code/SKILL.md` says `below_threshold` "is calibration only — no caller routes it." If genuinely nothing routes it, it is not a filter and not a demotion input, so `agent-team-review:215` is not violated on its face. And the bucket has a real use: it is the only way to detect a reviewer that is systematically mis-calibrated, because you cannot audit a threshold whose rejects you never see.

**Why it still does not survive.** Three reasons, in increasing order of force:

1. **Bucketing is routing.** To populate `below_threshold` you assign a number and compare it to 80. A finding printed under a heading called "below threshold" is presented as less real, and a lead under time pressure treats it that way. That is demotion by presentation, which is what line 215 forbids in substance even if not in the letter.
2. **ACS already has a better discriminator on a non-self-rated axis.** The Evidence rule — blocking requires an *observable failure path* — is external: it is a property of the claim, checkable by someone other than its author. Confidence is the model grading its own output, which is the self-preferential-bias signal line 215 names explicitly.
3. **The decisive one: two rankings that can disagree, and the weaker is free to produce.** Add a self-rated bucket alongside an evidence-rated floor and you get findings that are high-evidence/low-confidence and low-evidence/high-confidence. Nothing adjudicates between them, and the axis that requires no work (emit a number) will win against the axis that requires tracing a call path. That is not a neutral addition; it is a cheaper competing gate.

So the bucket is a demotion input by another name. **F9 stands.**

**The concession, and it matters more than the disputed part:** I under-weighted what is actually load-bearing in that skill. It is not the numbers — it is **§ Verify Before Post**: *"Second pass over your own candidates before surfacing anything. Drop each unless it has a concrete `file:line` and a causal chain (input → mechanism → wrong outcome) you have **traced, not assumed**."* That is ACS's Evidence rule, applied **at the reviewer** rather than at the lead — one round earlier, before the finding costs the lead anything. ACS's evidence floor runs in §4 synthesis, after four reviewers have already emitted. Moving the same standard upstream is free and strictly reduces load. **This belongs in E2 alongside the do-not-flag list**, and I should have had it there; it is the better half of what I was pointing at when I cited the drop list.

---

## 7. Omissions — **three genuine misses, one partial. All four conceded.**

| # | Item | Missed or deliberate | Verdict + landing |
|---|---|---|---|
| a | **`git add <paths>`, never `-A`/`.`** (`impl-task/SKILL.md`: "guards against sweeping in unrelated changes (e.g. from parallel sessions sharing a checkout)") | **Missed**, and it is the worst of the four to have missed | **Adopt** → IMPLEMENT composition hint now, `PreToolUse:Bash` pattern later. ACS documents this exact hazard at length (concurrent sessions share `~/.claude/`; #219's live deny was a shared checkout a concurrent session had parked on its own branch) and has **no** control on the staging side. `git add -A` happens *before* the push, so the push gate cannot see it — the gate measures a commit that already swept in a neighbour's work |
| b | **`## Implementation Notes` at end of implementation** — deviations from plan, surprises, implicit assumptions, non-obvious follow-ups | **Missed** | **Adopt** → IMPLEMENT sequence, as input to `implementation-drift-check`. ACS captures as-built at SHIP (`openspec-ship`) and durable facts via `capture-knowledge`, but nothing records *deviation at the moment of deviation*. Drift-check currently has to reconstruct intent-vs-outcome from the diff; this hands it the delta directly, written by the only agent that knew why |
| c | **review-loop's conjunctive convergence** — no-new-feedback AND no-drift AND under-cap; early exit on a clean round 1; "score-only convergence" named as an anti-pattern | **Partial** — I judged it covered by verdict routing and was half wrong | **Adapt** → `agent-team-review` §5. Its loop (`blocking_issues` → fix → re-review) has **no round cap and no drift clause**. "Meaningful improvement concentrates in rounds 1-2; after round 3 models entrench" is a mechanism, not a preference. Take the cap and the drift-rejection; skip the scoring apparatus, per point 6 |
| d | **SCOPE MANIFEST vs "no names for new files"** | **Missed, and it is a real contradiction** | **Adapt ACS's hint.** The PLAN hint demands "exact backticked repo-relative paths" incl. `Create:` entries; `plan-task/SKILL.md` says "no names for new files/classes/functions … no details that will go stale quickly". Both are right about different things: ACS's manifest is a **scope** device (`scripts/scope-conformance.sh` flags undeclared touched files), auto-task's rule is about not pre-committing **design**. Naming a file that does not yet exist is a design decision smuggled in as a scope declaration, and it is the entry most likely to go stale. Resolution is free: `scope-conformance.sh:12` already documents that "Matching is exact path or bash case-glob; case-glob `*` crosses `/`", so `Create:` entries can be directory globs while `Modify:`/`Delete:` stay exact — those paths exist and are knowable. No script change; one sentence in the hint |

---

## Net effect on the assessment

- **B row 10 / E4 sweep:** withdrawn as an independent finding; absorbed into B row 8 (status field), which is now better supported than when I wrote it.
- **E1:** ceiling replaced with a per-bullet structural invariant; D4 unchanged and now consistent with it.
- **E3:** unchanged in rank, upgraded from hint to artifact-existence gate on the existing design-guard path, with the forgeability limit stated.
- **E5:** composition half moves to #2; SKILL.md half stays low. F8 unchanged.
- **E2:** gains `review-code` § Verify Before Post, which is the stronger borrow.
- **F4:** remedy withdrawn; the non-termination statement becomes the recommendation.
- **F9:** held.
- **New rows:** 7a, 7b, 7d as adopt/adapt; 7c as adapt.

Two of these — 1 and 4 — are cases where the challenge was better than my original, and one (7d) is a contradiction inside ACS that I read past twice.


## Round 2 challenges

(A) home for relocated rationale should be `.claude/knowledge/`, not a seventh doc home; (B) a `status:` field is only as good as its writer, propose an archive-lag check instead; (C) `git add -A` deny is unjustified under the false-block discipline.

## Round 2 replies

# Sparring round 2 — replies

**A conceded outright. B conceded in shape, but your predicate is unvalidated and mine is measurably dead — so the first move is not a script. C conceded: advisory permanently, with a cheap firing condition.**

---

## A. **Conceded, and the repo has already done it once — with the duplication still live.**

`.claude/knowledge/` is the right home and I should not have invented a seventh. It is the exact shape (12 files, 4,691 words total, ~390 each), it is typed, `scripts/knowledge-validate.sh` enforces `type` presence and link/index integrity, and the 8192-byte index cap means bodies never load — which is precisely the property I was buying with a `docs/` tree. It does not even need a new type: the vocabulary in use is already `type: gotcha` (7 files) and `type: convention` (4). Decisive measurement — **the relocation has already been performed on one bullet, and both copies are still live**: `.claude/knowledge/bash32-arithmetic-quoting.md` carries `title: Bash 3.2 rejects quoted operands in arithmetic` and, in its frontmatter, **`source: CLAUDE.md:Gotchas`** — while the full bullet remains in `CLAUDE.md` (grep for `rejects **quoted operands` → 1 hit). So the pattern is proven in-repo, the `source:` field already points back at the origin, and the only thing missing is deleting the CLAUDE.md copy. That reframes E1 from "build a tree" to "finish a migration someone started" — much cheaper, and it kills my seventh home. On human-gating: I see no reason the gotcha corpus should be exempt, and one reason it should not be. The gating exists because `.claude/knowledge/` is a memory-poisoning surface injected at session start; a gotcha bullet is *more* load-bearing than a typical fact, not less — several of ACS's encode security-gate invariants. A PR gate on that text is a feature. The one real cost is friction on the author's own fast loop, and the answer to that is the same as everywhere else in this repo: the test is the enforcement, the knowledge file is the rationale, and rationale can afford to land a commit later than the fix.

---

## B. **Your check beats a status field — but neither predicate is validated, and I nearly repeated my round-1 error proposing a third.**

You are right about the writer, and the argument is stronger than you put it: a status field is not merely skippable, it is skippable *by the identical path that already failed*. `openspec-ship` is the writer for both the archive move and any `status:` field, so a run that skips it leaves the field at `in-flight` — converting a silent gap into an affirmative false statement, which is worse than no field. Concede. But I then tried to sharpen your predicate and found the sharpening dead, which is the useful part of this reply. Your predicate ("named scripts/tests/skills all exist") false-positives on any change that *modifies* an existing file — the artifact predates the change, so existence proves nothing. I looked for something that can only be true after shipping, and openspec supplies one by design: spec deltas fold into the canonical `openspec/specs/<cap>/spec.md` at archive (22 capability dirs exist). Measured on six active changes, matching each change's first `### Requirement` heading against its canonical spec:

```
verify-and-record/project-verification : not folded
gate-status/pdlc-safety                : not folded
review-verdict/pdlc-safety             : not folded
partial-push-subjects/pdlc-safety      : not folded
hook-source-guard-lint/pdlc-safety     : not folded
done-gate-ci-enforcement/pdlc-safety   : not folded
```

Zero of six, including `verify-and-record` and `gate-status` whose scripts demonstrably ship. So the fold either is not run or does not preserve requirement text, and my predicate discriminates nothing. **Verdict: your shape is right and mine is dead, but shipping either predicate now is how I get round 1 wrong a second time — I would be asserting a mechanism I have not tested against labelled cases.** The correct first change is not the script: hand-label ~10 active dirs shipped/in-flight from the code, then test candidate predicates against those labels and keep one that separates them. That is the `kaizen` "N of M" discipline applied to the instrument rather than to the corpus — and if no predicate separates the labels, the honest finding is that the archive decision is irreducibly human, which is itself worth knowing before building a checker for it.

---

## C. **Conceded: advisory permanently. A deny is unjustifiable, and the real control is the one ACS already has.**

An eventual deny is not justified and I should not have written "later". Three reasons, and the third is decisive. First, ACS's own posture forbids it: a new deny requires a shadow corpus, and CLAUDE.md's false-block discipline is explicit — proposing a deny with no corpus, in the same assessment where I criticise the IMPLEMENT leg for having waited months on exactly that requirement, is inconsistent. Second, the base rate is against it: `git add -A` in a fresh worktree with no neighbour is safe and is the common case, so a blanket deny is a false block by construction on most invocations. Third and decisive — **this is not a staging problem, it is a worktree-compliance problem, and ACS already gates that**: the IMPLEMENT composition's `sequence` carries `using-git-worktrees` with purpose *"REQUIRED before implementation: set up isolated worktree. Do not implement directly on main."* If worktree isolation holds, `git add -A` cannot sweep in a neighbour's work — there is no neighbour in the tree. Denying the staging command treats the symptom of a violated isolation step, and would let the real failure (implementing in a shared checkout) keep passing. So: **advisory, permanently, with a cheap firing condition** — emit the note only when a neighbour could actually exist, i.e. `git worktree list` reports more than one entry, or `git status --porcelain` shows tracked modifications the current task did not touch. One git call, silent in the solo-worktree case that constitutes the false-block risk, and it fires exactly in the configuration where the hazard is real. If someone later wants a deny, the predicate would have to be "staged paths fall outside the plan's `Files:` manifest" — which `scripts/scope-conformance.sh` already computes — and that is a scope gate reusing existing machinery, not a staging-command gate. It would still need its own shadow corpus first.
