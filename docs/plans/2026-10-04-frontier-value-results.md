# Do the process skills and our routing still earn their keep? — measured results

**Date:** 2026-10-04
**Status:** results of the measurement programme proposed in
`2026-10-03-frontier-model-value-audit-design.md`. Supersedes specific claims in that document and in
`2026-10-03-external-skill-repos-adoption-design.md` where marked **CORRECTION** below.
**Sparring partner:** Codex (codex-cli 0.154.0), used three ways — adversarial methods review of the
pre-registration, independent verification of the two design documents against the tree, and
authorship of the task fixtures so the experimenter is not also the fixture authority.

Everything in sections 1–3 is measured on the owner's machine. Section 4 is the pre-registered pilot
(`2026-10-04-frontier-ablation-prereg.md`, frozen at R2 before any run).

## 1. Field census — what routing actually did over five weeks (exploratory, not pre-registered)

Source: local top-level transcripts, 2026-08-26 → 2026-10-03. Instrument: scripts in the session
scratchpad built on `tests/probes/real-prompt-replay/` helpers; counts only, no prompt text leaves
the machine or enters this repo.

**Volume.** 1,530 routing blocks were injected; 784 followed a human-typed prompt (429 followed task
notifications — none since 2026-09-25, the PR #258 fix holds; 275 were SDK runs). On human prompts
the block averaged 4.9 KB (median 4.9 KB, p90 7.2 KB). Accumulated per session: median ≈ 0.45k
tokens, p90 ≈ 17k tokens, maximum ≈ 98k tokens of routing blocks in one session.

**Uptake of `MUST INVOKE`.** Unit: a *case* = the first time, in one session, that routing told the
model it MUST INVOKE a given skill on a human prompt. There are 183 such session-and-skill cases (157 on
Opus 5, 13 on a Fable model, 12 on Opus 5.5, 1 on Opus 4), drawn from 399 `MUST INVOKE` routings in all.
Every percentage below is of the 183 cases, not of all routings.

| Outcome | n | share |
|---|---|---|
| invoked in the same turn | 22 | 12% |
| invoked later in the session | 28 | 15% |
| already loaded earlier in the session | 8 | 4% |
| **never invoked** | **125** | **68%** |

96 of the 125 "never" cases were followed by four or more further human turns in the session, so early termination does not
explain it. This contradicts the lab figure of 16/16 uptake (`tests/baselines/composition-uptake.baseline.json`),
which was measured with the block pasted into a prompt written to call for the skill.

**Was the routing right?** Two blind LLM labellers (one subagent on the session's default model, one on the
Sonnet alias; each shown only the prompt and the routed skill, never the outcome) judged whether the prompt, on its face, called for that skill.
Agreement 0.87, Cohen's kappa 0.76.

| Consensus label | n | model invoked it (same turn or later) | already loaded | never |
|---|---|---|---|---|
| appropriate (both) | 14 | 8 | 2 | 4 |
| not appropriate (both) | 100 | 20 | 2 | 78 |
| context-dependent or disagreement | 69 | 22 | 4 | 43 |

- **Routing precision is the problem, not model obedience.** By consensus, 8% of the 183 cases
  were clearly right and 55% clearly wrong. Counting every undecidable case as right gives an
  upper bound of 45%.
- **The model is already acting as the filter.** It declined 78 of 100 wrong routings. It still obeyed
  20 of them — twenty skill invocations a correct router would not have asked for.
- Per skill, clearly-wrong share: product-discovery 18/19, brainstorming 29/50, systematic-debugging
  11/19, requesting-code-review 17/37, executing-plans 20/46. Half the routed prompts were ≤ 40
  characters (continuations such as approvals), which a regex cannot place in a phase.

**Does the current build still do it?** The 183 prompts were replayed through the installed hook
(3.93.1), each in a fresh HOME with a copy of the real registry, with a positive and a negative
control. The same `MUST INVOKE` recurred for 70 of the 100 clearly-wrong prompts and 12 of the 14
clearly-right ones. (Fresh state per prompt; the field prompts were mid-session, so this is a lower
bound on fidelity, not an exact replay.)

**Live instance, this session (observed, not in the evidence bundle).** Ten consecutive subagent hand-back messages (fixture authors and
reviewers reporting PASS/ACCEPT results) each received a routing block with `systematic-debugging MUST
INVOKE`, plus assorted domain suggestions (`incident-analysis`, `deploy-gate`, `design-debate`, a GKE
hint). None was a debugging request; the words "fails" and "wrong fix" in a report were enough. The
census shows the same `peer` source still routing after 2026-09-25 (18 events). Two automated notices
(a goal check-in and a security-review notice) were also routed, to `brainstorming MUST INVOKE` with the
full seven-step chain — so the 2026-09-25 fix covers task notifications as the census labels them, not
every automated message.

**Limits.** One owner, mostly this repo (64 of the never cases) and one other project (47): meta-work
about routing is over-represented. 157 of the 183 cases ran on Opus 5, which is not one of the pilot's
models. Labels are LLM judgements on prompt text alone. The sample is conditional on having been routed,
so it measures precision, not recall. The per-session accumulation figures, the date split, the
further-turns count and the project split were computed in the session and are not in the bundle; the
replay counts in `data/labels.json` are transcribed from script output.

## 2. Tier-0 defects, re-verified

- **F1 reproduced on HEAD** in an isolated HOME: a user skill with `triggers:` followed by
  `allowed-tools:` registers as `triggers: ["be careful","safety mode","Bash","Read"]`, `priority: 200`.
  Codex traced the awk independently and **narrowed** it: the mis-attachment needs a list-valued key
  directly before the hyphenated key; a scalar in between resets `cur_key`.
  **CORRECTION:** "hijacks routing" overstated it — a discovered skill still needs a trigger, keyword
  or name match to score, and process skills hold a reserved slot. The parser fix is a correctness
  fix; lowering the default priority is a *policy* choice and should be argued separately. Accepting
  hyphenated keys does not by itself honour `disable-model-invocation`; discovery builds enabled
  entries without reading it (`hooks/session-start-hook.sh:731`).
- **F2 confirmed** on our side (Codex cannot see upstream; upstream lines were read by me at `8ca22db`).
  Missed surface: `config/fallback-registry.json:118` carries the same stale text.
- **F3 is a missing curated route, not a defect.** "Why didn't the skill fire" may be about ACS itself,
  so routing it to an upstream diagnostic could misdirect; if added, the trigger must be narrow.
- **New, Linux-only, not reproduced on this Mac:** in the cloud container the session-start hook died
  with `File: unbound variable` at the token-reuse arithmetic. Mechanism by reading
  `session-start-hook.sh:127-131`: `stat -f %m FILE` is the BSD form; under GNU stat it prints
  filesystem info and exits non-zero, the `||` fallback then appends the real mtime, and the combined
  string reaches `$(( ))`. Needs a Linux run to confirm before fixing.
- **New:** every ACS session starts a `cozempic guard` daemon that outlives a headless session — four
  were left behind by four plumbing runs.
- **New:** the session-start hook's "MANDATORY: Before any other output, report the skill system
  status" line made Haiku 4.5 answer a one-word prompt with the banner instead (n=1, observed).
- **New, and the most serious defect found: one tracked binary file disables the publish guard.**
  `scripts/memory-leak-check.sh:147-159` builds its public-content exemption with
  `git ls-files -z | xargs -0 awk …` over every tracked file. On macOS, awk aborts on bytes that are
  not valid in the locale (`awk: towc: multibyte conversion failure`, exit 2); the engine then exits 3
  ("cannot classify") and `publish-guard.sh` fails open and announces instead of denying. Found because
  this branch briefly tracked a `.tar.gz` and the suite's own control cell went red
  (`tests/test-publish-guard-hardening.sh`: "a confirmed leak denies (control)"). Isolated with a
  flipping pair in a detached worktree at the base commit, everything else fixed: no added file 7/7;
  one added tracked *text* file 7/7; one added tracked *gzip* file 4/7. This repo tracks no binaries,
  which is why it never showed; an installer repo that tracks an image or an archive gets a publish
  guard that can never deny a confirmed leak. Not fixed here: pinning `LC_ALL=C` on that awk alone
  would make the exemption normalise non-ASCII text differently from the body and memory shingling and
  could turn public text into false LEAK denials, so the fix has to change all three together and be
  tested in both directions. The pair above is the red test.
- **New, a false block caused by a mis-route:** an automated security-review notice was routed to
  `brainstorming MUST INVOKE`, which started a DESIGN→…→SHIP composition chain for this session. When a
  code review was then requested, the skill gate refused it twice — "Step 'brainstorming' has no
  invocation evidence", then the same for `executing-plans` — until each was recorded as an explicit skip
  with `phase_attest`. The gate worked as designed; the chain it enforced was never requested by anyone.
- **New:** `~/.claude/.skill-registry-cache.json` is machine-global but holds per-session facts
  (`serena_connected`, cwd-dependent warnings). A session started in another directory rewrote it
  while this one was live (checksum changed; `serena_connected` flipped to false).

## 3. What Codex's review of the two design documents changed

**CORRECTIONS to `2026-10-03-frontier-model-value-audit-design.md` ("demote-now set"):**
1. *Stop routing to `using-superpowers`* — **void.** The entry has no triggers or keywords
   (`config/default-triggers.json:563`); it is not routed on ordinary prompts, and removing it would not
   touch upstream's own SessionStart bootstrap. The census agrees: it never appears among routed skills.
2. *`using-git-worktrees` `required` → normal* — **does not do what was claimed.** `required` is routing
   emphasis, not a gate (`docs/enforcement-map.md:106`), and the IMPLEMENT composition separately says
   "REQUIRED before implementation" (`config/default-triggers.json:1484`). A role-only edit leaves that.
3. *`agent-team-execution` manual-only* — **incomplete.** The phase guide still tells the model to offer
   it (`config/default-triggers.json:865`), and its implementation-evidence alias must be preserved
   (`hooks/lib/phase-evidence.sh:15`).
4. *Replace `verification-before-completion` with the evidence record* — **not a prose change.** The push
   gate deliberately refuses a clean measured verdict as a substitute for the invocation
   (`hooks/openspec-guard.sh:1264-1275`, issue #254); the measured-verdict leg is still advisory (#301).
   Any change here goes through that pre-registered corpus, first read due 2026-10-12.

The census also shows three of the four were the wrong targets on volume alone: `using-git-worktrees`,
`dispatching-parallel-agents` and `agent-team-execution` were routed 7, 3 and 1 times in five weeks. The
volume is in `requesting-code-review` (231 routing events), `brainstorming` (144),
`verification-before-completion` (122 — the fourth target, high-volume but not removable by a prose
change, per item 4) and `executing-plans` (99).

**CORRECTIONS to `2026-10-03-external-skill-repos-adoption-design.md` (portfolio):**
- **G5 (Fix-First: anything needing a regression test → ASK)** — dropped; it penalises exactly the
  fixes that come with verification.
- **T2 (premature-action scoring)** — dropped as a pass/fail assertion; reading code before invoking a
  skill can be correct. Keep only as a descriptive count.
- **T3 (abstain on off-mission prompts)** — reshaped: label the *intended* skill per case; a marketing
  or legal prompt can legitimately need `authorial-judgment` or consultation.
- **T1's acceptance rule** ("deleting the hint must reduce uptake, else the instrument is blind") —
  dropped; equal arms can be a correct instrument measuring redundancy.
- **T4b / E4 / G8** — demoted to optional; a generated eval stub does not make a done-gate behavioural.
- **Ordering.** "Instruments before interventions" stands for new per-prompt mandates, but bundling
  T1–T5 first was procrastination. The smallest real-hook outcome comparison (section 4) replaces it;
  the F1 parser fix and the stale-description fixes proceed independently.

**Methods review of the pre-registration** — seven findings, all adopted in R2 (listed there). The
decisive one: the first draft's "±3 of 16" rule would have declared a spurious quality effect about
half the time across its three comparisons.

**An unplanned observation.** Three of four Codex authoring sessions, given an explicit "work
autonomously" instruction, produced a design table and stopped: "This gate prevents me from following
your autonomous-execution request yet. No files have been created." Codex has superpowers 6.4.2
installed, and its brainstorming skill's approval gate overrode the instruction. The sessions ran only
after the prompt stated that approval was already given. This is a different model family, n=3, and
not part of any pre-registered measure — but it is a clean instance of a process skill costing a whole
run on a fully specified task. (Codex on this machine also loads this plugin: its sessions printed the
"49 skills active across 12 plugins" banner, and one wrote an `openspec/changes/…/plan.md` for a
fixture-authoring job.)


## 4. Outcome ablation pilot (pre-registered)

Design as frozen in `2026-10-04-frontier-ablation-prereg.md`: 16 fixtures with hidden tests, three arms
(A0 bare, A1 superpowers 6.4.2, A2 superpowers + auto-claude-skills 3.93.1), one run per task-arm, real
headless sessions in isolated HOMEs, two models. 96 runs; all ran after the freeze commit (`a3c45b35`,
01:54:59; first run log 01:55:41). 0 harness failures, 0 timeouts, 0 retries; the most expensive run cost
USD 1.77 against the USD 4 cap. Notional cost of the pilot: USD 63.
Evidence bundle: `2026-10-04-frontier-ablation/` (per-task table in `data/analysis-<model>.txt`).

**Manipulation check — one disclosed deviation.** The pre-registration says each session's `init` lists
"exactly the intended plugins". Every run, the bare arm included, also lists Claude Code's built-in
`cc-plugin-*` entries, so the check as implemented tests only the presence or absence of the two plugins
under test and of the superpowers bootstrap. On that test all 96 runs pass, and the data show each arm
carried the hook output it should: A0 none, A1 3.6 KB at session start, A2 6.0 KB at session start plus a
routing block on every first prompt (16 of 16 per model).

### Result

| | Opus 5.5 | Fable 5.1 |
|---|---|---|
| Hidden suite fully passed, A0 / A1 / A2 | 16 / 16 / 16 | 16 / 16 / 16 |
| **Quality, primary (A2 vs A0)** — mean ΔQ, exact p | 0.0, p = 1.0 → **inconclusive** | 0.0, p = 1.0 → **inconclusive** |
| Quality, A1 vs A0 and A2 vs A1 | inconclusive | inconclusive |
| Qbin discordant pairs, any comparison (McNemar p) | 0 / 0 (p = 1.0) | 0 / 0 (p = 1.0) |
| **Cost, primary (A2 vs A0)** — median token ratio [range], more/less, exact sign p | 1.39× [0.76–2.34], 12/4, p = 0.077 → **inconclusive** | 1.71× [0.89–3.07], 15/1, p = 0.0005 → **overhead shown** |
| Cost, A1 vs A0 | 1.37× [1.06–2.18], 16/0, p < 0.0001 → **overhead shown** | 1.60× [1.13–3.08], 16/0, p < 0.0001 → **overhead shown** |
| Cost, A2 vs A1 | 0.86× [0.55–1.60], 6/10, p = 0.45 → inconclusive | 1.04× [0.67–1.55], 10/6, p = 0.45 → inconclusive |
| Notional USD, A0 / A1 / A2 | 3.85 / 5.02 / 5.34 | 13.36 / 16.90 / 18.67 |
| Wall minutes, A0 / A1 / A2 | 12.2 / 14.5 / 14.2 | 25.2 / 29.4 / 31.3 |
| Turns, A0 / A1 / A2 | 64 / 100 / 73 | 181 / 258 / 250 |
| Subagents dispatched; runs that edited a file; original visible tests passing | 0; 48/48; 48/48 | 0; 48/48; 48/48 |

The A1-vs-A0 overhead survives a Holm adjustment across the two secondary comparisons; A2 vs A1 is
inconclusive on both models.

**By fixture author** (promised in amendment A1). Every run passes in both subsets. Median token ratios,
with tasks costing more/less:

| | Codex-authored (n = 9) | Claude-authored (n = 7) |
|---|---|---|
| Opus 5.5, A1 vs A0 | 1.48× | 1.18× |
| Opus 5.5, A2 vs A0 | 1.39×, 8/1 | 1.00×, 4/3 |
| Opus 5.5, A2 vs A1 | 0.87×, 3/6 | 0.86×, 3/4 |
| Fable 5.1, A1 vs A0 | 1.91× | 1.42× |
| Fable 5.1, A2 vs A0 | 1.71×, 8/1 | 1.71×, 7/0 |
| Fable 5.1, A2 vs A1 | 0.90×, 4/5 | 1.05×, 6/1 |

The subsets agree on quality and on the direction of the superpowers overhead. They do **not** agree on
the primary cost comparison for Opus 5.5: the overhead of A2 over A0 appears on the Codex-authored
fixtures and not on the Claude-authored ones.

**Reading it, within the pre-registered vocabulary.** Threat 2 happened: every arm solved every task, so
quality is *inconclusive* — uninformative in either direction, not evidence of equivalence. On cost:
superpowers alone shows overhead on both models (median 37% and 60% more tokens, every task). The
primary comparison — superpowers plus this plugin against bare — shows overhead on Fable 5.1 and is
inconclusive on the primary model, Opus 5.5. Adding this plugin to superpowers is inconclusive on both.
No composite verdict is computed.

### What the plugin arms did (descriptive, not pre-registered; `data/run-observations.json`)

- **Superpowers alone (A1):** the model invoked a process skill in 10 of 16 runs on Opus 5.5 and 13 of 16
  on Fable 5.1 — `systematic-debugging` (7, 10) and `test-driven-development` (3, 3).
- **With this plugin added (A2):** the first-prompt routing block was 3.3–9.7 KB, mean 7.8 KB (125 KB over
  16 prompts). It said `systematic-debugging MUST INVOKE` on 3 tasks (a4, c2, d2) and `brainstorming MUST
  INVOKE`, under the header "Build New", on the other 13: the 4 feature tasks, where that is the right
  phase, and 9 of the 12 bug-fix, debugging and release-review tasks, where it is not. Neither model
  invoked brainstorming in any run. Opus 5.5 invoked `systematic-debugging` on exactly the 3 routed tasks;
  Fable 5.1 on those 3 plus 3 debugging tasks where the block had said brainstorming (c1, c3, c4). Runs
  with any skill invoked: 10 → 3 on Opus 5.5 and 13 → 6 on Fable 5.1, comparing A1 with A2. Whether
  invoking a skill was *better* is not something this pilot can say — every run passed.
  **CORRECTION, 2026-10-05: the "Build New" classification was caused by the experiment's own prompt
  suffix, not by the task text.** The fixed line appended to every task ("You are authorized to implement
  this directly; no design or plan approval is needed … Make reasonable assumptions …") contains
  `implement`, `design` and `make`, which hit both of brainstorming's triggers. Replaying the 16 task
  texts *without* that line: 7 of the 8 bug-fix and debugging tasks route to `systematic-debugging`,
  3 of the 4 release-review tasks to `requesting-code-review`, and all 4 feature tasks to
  `systematic-debugging` (their specs mention errors). So the observation above is real for the prompts
  as sent, but it is not evidence that the router misreads bug reports; it is evidence that incidental
  vocabulary decides the phase. An earlier version of this paragraph said the classification was
  independent of the suffix. That was wrong.
- **Unrequested writes:** in all 32 A2 runs the session-start guard wrote `.claude/settings.json`
  (77 lines of hook configuration) and a lock file into the project directory; none of the 64 A0 and A1
  runs has a `.claude` directory.
- **Lines added** A0 / A1 / A2, excluding those guard files: 1,058 / 1,703 / 1,268 on Opus 5.5 and
  2,193 / 2,563 / 2,645 on Fable 5.1 (raw A2 figures 2,500 and 3,877). Lines removed are flat (92–116).

## 5. What this adds up to

Two kinds of statement follow, kept apart: what was **measured**, and the **policy reading** I would
draw from it. The policy reading is a recommendation, not a finding.

### Measured

1. *Pre-registered pilot, 16 small stdlib-Python fixtures, autonomous and pre-authorised.* Quality:
   inconclusive (ceiling). Cost of superpowers over bare: overhead shown on Opus 5.5 and Fable 5.1.
   Cost of superpowers plus this plugin over bare: overhead shown on Fable 5.1, inconclusive on Opus 5.5.
   This plugin over superpowers: inconclusive.
2. *Exploratory field census, one owner, five weeks, mostly Opus 5.* Of 183 first `MUST INVOKE` cases,
   the skill was never invoked in 125. Two blind labellers judged 14 cases clearly appropriate and 100
   clearly not; the model declined 78 of those 100 and obeyed 20. The installed build repeats the same
   `MUST INVOKE` for 70 of the 100. On these cases the router was wrong more often than right (55%
   clearly wrong against at most 45% right).
3. *Descriptive, from the pilot.* The routing block said `brainstorming MUST INVOKE` on 9 of 12
   bug/debug/release-review tasks; no model followed it. (Corrected 2026-10-05: that classification was
   induced by the experiment's own prompt suffix — see §4.) The block is 4.9 KB on average in the field
   (p90 7.2 KB) and 7.8 KB on the pilot's first prompts.
4. *Side effects observed.* Guard files written into every project; a guard daemon left per headless
   session; a machine-global registry holding per-session facts; routing blocks on subagent hand-backs
   and on two automated notices in this session.

### What the measurements cannot say

- Whether process skills help on **hard, long, ambiguous or interactive** work. The pilot hit the
  ceiling and removed the human — the conditions under which those skills claim their value.
- Whether anything has **changed** with frontier models. No older-model arm was run, so this is a
  statement about Opus 5.5 and Fable 5.1 today, not about a trend.
- Whether the plugin's routing costs or helps in outcome terms. The pre-registered A2-vs-A1 comparison
  is inconclusive; the case against the routing rests on the exploratory census and the descriptive
  observations above, with their limits.
- Anything about the gates. They were not exercised.

### Policy reading (the owner's call)

- **On "net negative".** The honest form of the answer is narrower than yes or no: on the one class of
  work measured, superpowers showed cost and no observable benefit, and benefit *could not* have been
  observed because nothing failed. Under the inverted burden of proof proposed in the audit — a
  per-prompt mandate must show benefit to stay mandatory — that is enough to stop *mandating* process
  skills on routine work. It is not enough to remove them, and it does not overturn the standing
  decision that superpowers is the phasing backbone.
- **On shedding.** Do not delete skills. Change what the plugin does with them:
  1. **Routing precision first.** It is the best-evidenced defect and it is ours. Each change needs its
     own red-first test: no `MUST INVOKE` on continuations, approvals, subagent or peer hand-backs, or
     automated notices; the process skill offered as a suggestion unless the match is strong; a smaller
     first-prompt block. ("Classify bugs as DEBUG, not Build New" was listed here and is withdrawn: its
     evidence was the suffix artefact corrected in §4.)
     Acceptance instrument: a freshly drawn and freshly labelled sample (the census scripts regenerate
     one; this session's labelled sample is not kept and its labels have been read in aggregate, so it
     could only ever be development data), scored on the share of `MUST INVOKE` cases labelled
     appropriate, plus the 16 task prompts as a small fixed check.
  2. **A `frontier-lean` preset** — routing as suggestion, gates and context kept — measured with the same
     harness against A1 and A2 before any default changes.
  3. **Fix the side effects** in item 4 above, the F1 parser bug, the stale superpowers descriptions,
     and, once reproduced on Linux, the `stat` crash.
  4. **Leave the gates alone for now.** The verification leg has its own pre-registered corpus, first
     read 2026-10-12.
- **On rethinking the approach.** The plugin assumes the model must be told which process to follow.
  The evidence here does not prove the opposite, but it does show the telling is frequently wrong and
  frequently ignored, and that models choose a debugging or TDD skill unprompted when the skills are
  merely available. That is a reason to shift weight toward what a model cannot supply for itself —
  deterministic gates, evidence records, project and organisation context — and to make routing earn its
  place by measured precision.

### The experiment that would settle the open half

Quality on tasks hard enough that a bare session fails some of them. The next task set must keep the
trapped requirement out of the task text and in the repo's own documentation, be large enough that
reading before changing matters, include multi-turn tasks with a scripted user so approval and
elicitation skills can show their value, and add an older-model arm if "has this changed" is still the
question. It needs a new pre-registration; these 16 fixtures are spent.

### Adoption portfolio, re-ranked

Routing precision first; then the F1 parser fix and the stale-description fixes; then the
zero-per-prompt-cost grafts that survived review (provenance tags only with a tool result, the review
coverage line, quote-or-demote, the `authorial-judgment` additions, schema-backed adversarial data from
`break-ui`). Every proposed *new per-prompt directive* (Review Focus, debug scope lock, redesign
invariants) is on hold until routing precision is measured and fixed.

## 6. Open items the owner should know about

- **Published through the gate, not around it.** The gate refused the first attempt (no code-review or
  verification record), so the pre-registration could not get a remote timestamp before the runs; its
  pre-data freeze rests on local commit times and hashes. The branch `ccr-72351171-l8ph21` went to the
  remote at `a54b7127` only after a dispatched code review and a full-suite verification (181 of 181
  files, completion sentinel present). Two advisories stand and are accurate: the review was recorded two
  commits earlier (the later commits are the fixes it asked for plus the tarball change), and the
  verification verdict reads "not clean" because the gate-gaming check flags the string
  `@unittest.skip` — which appears in the grader's own test as the input proving a skipped test is not
  counted as a pass. No test in the suite is skipped.
- **The harness is not a sandbox.** The 96 runs were headless sessions with unrestricted Bash as the
  owner's user, confined only by a throwaway HOME and a scratch working copy. See the bundle README.
- Codex's usage limit cut fixture authoring short; seven of sixteen fixtures are Claude-authored, and
  category c entirely so.
- The Linux `stat` crash is diagnosed by reading, not reproduced.
- The labelled prompt sample and the per-run working copies live in the session scratchpad and are not
  kept; the bundle holds counts and per-run scores only. The bundled `run.py` differs from the one that
  ran by path rewrites and a comment.
- **The first verification run of this branch failed, correctly** (180 of 181 test files; the publish-guard
  control above). The cause was the tracked tarball; it is now a base64 text file and the suite was re-run.
- **A code review of the harness found the grader's stated guarantees were false** — a skipped test
  counted as a pass, an unimportable test module did not score zero, and failing sub-tests could push a
  score below zero. None of this touched the reported results: all 96 runs were re-graded with the fixed
  grader and every hidden and visible verdict is identical, and the 16 untouched starting repos all
  fail. The fix is pinned by ten mutation-checked tests in the bundle. The harness as it ran must not
  be reused on a task set that does not hit the ceiling; the bundled version carries the fixes.
- An independent fact-check of this document against the bundle found the result tables exact and
  several conclusions overstated; sections 4 and 5 were rewritten in response, and its list of what the
  bundle cannot verify is reflected in the limits stated above.
