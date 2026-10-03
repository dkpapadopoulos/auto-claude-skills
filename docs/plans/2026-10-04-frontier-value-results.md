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

**Uptake of `MUST INVOKE`.** Unit: the first time a session's routing told the model it MUST INVOKE a
given skill, on a human prompt (183 cases; 157 on Opus 5, 13 on Fable 5, 12 on Opus 5.5).

| Outcome | n | share |
|---|---|---|
| invoked in the same turn | 22 | 12% |
| invoked later in the session | 28 | 15% |
| already loaded earlier in the session | 8 | 4% |
| **never invoked** | **125** | **68%** |

96 of the 125 "never" sessions had four or more further human turns, so early termination does not
explain it. This contradicts the lab figure of 16/16 uptake (`tests/baselines/composition-uptake.baseline.json`),
which was measured with the block pasted into a prompt written to call for the skill.

**Was the routing right?** Two blind LLM labellers (Opus 5.5 and Sonnet 5.5, shown only the prompt and
the routed skill, never the outcome) judged whether the prompt, on its face, called for that skill.
Agreement 0.87, Cohen's kappa 0.76.

| Consensus label | n | model invoked it (same turn or later) | already loaded | never |
|---|---|---|---|---|
| appropriate (both) | 14 | 8 | 2 | 4 |
| not appropriate (both) | 100 | 20 | 2 | 78 |
| context-dependent or disagreement | 69 | 22 | 4 | 43 |

- **Routing precision is the problem, not model obedience.** By consensus, 8% of `MUST INVOKE`
  routings were clearly right and 55% clearly wrong. Counting every undecidable case as right gives an
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

**Limits.** One owner, mostly this repo (64 of the never cases) and one other (47): meta-work about
routing is over-represented. Labels are LLM judgements on prompt text alone. The sample is conditional
on having been routed, so it measures precision, not recall.

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

The census also shows these four were the wrong targets on volume alone: the skills in the old
demote-now set were routed 7, 3 and 1 times in five weeks. The volume is in `requesting-code-review`
(231 routing events), `brainstorming` (144), `verification-before-completion` (122) and
`executing-plans` (99).

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
run on a fully specified task.

## 4. Outcome ablation pilot

PENDING

## 5. What this adds up to

PENDING
