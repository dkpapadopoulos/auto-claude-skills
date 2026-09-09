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
