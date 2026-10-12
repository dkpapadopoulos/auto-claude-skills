# Plugin state: measured 2026-10-12, with Codex independent read

All numbers measured on this machine by the lead; Codex was asked in INDEPENDENT mode (my
conclusions withheld) and its ranking compared afterwards. Scratch answer path printed by the
dispatcher: consult-run.L2tBbz/answer.md.

## Routing display (transcripts 2026-10-05..10-11, after PR #334)
- 102 sessions, 366 typed human turns, 55 human routing blocks (15% of turns), 9 on peer input.
- 57 skills routed; 3 invoked in the same turn. 23 MUST INVOKE mandates; 0 obeyed in-window.
- Session level (census2): first mandate per session never invoked in 17 of 18 (brainstorming 7/7,
  product-discovery 5/5, systematic-debugging 3/3, executing-plans 2/2; requesting-code-review 1 later).
- Gating skills invoked UNROUTED: verification-before-completion 7, requesting-code-review 4.
- Block bytes per human block: median 5,121, mean 5,526, p90 8,138; 304 KB/week ~ 76k tokens.
- Block composition (87 blocks): composition chain 39%, per-phase hints 30%, HALT list 7%, phase
  guide 5%, intent extraction 5% (20 of 87), evaluate line 4%, skill routing lines 4%.
- Per-phase hint text in config: DESIGN 2,581 B (7), REVIEW 1,307 (3), PLAN 1,118 (3), SHIP 895 (5).
  Largest are when=always; `when` is read by no hook (knowledge item), only `.plugin` gates.
- Session-start injection: median 6,341 B, p90 10,559 (27 sessions).

## Hook timing (isolated HOME; writes never touch the live session)
- Activation, real registry (49 skills), 20 runs on one prompt: min 158, median 172, p95 184, max 187 ms.
  Stated ~50 ms. Four prompt shapes: 151-197 ms, emitting 1,000-6,870 B.
- Session-start, plugins symlinked in (12 plugins discovered), cache warm: 2,814 / 2,832 / 2,820 ms;
  cold 2,938; first run 4,867. Stated 200 ms. Isolated with no plugins: ~1,000 ms.
- Fork census (bash -x, line-numbered): 621 forks. jq 157 (108 from the LSP plugin.json loop at
  hooks/session-start-hook.sh:1185), ls/grep/sort 38 each from the semver resolver at :504,
  basename+dirname ~240 across the discovery loops (:542 :558 :612 :623 :1096).
  Measured fork cost: true 3.0 ms, basename 3.8, jq 6.6, grep 5.2, sort 5.1, git rev-parse 10.4.
  621 forks x ~4.5 ms ~ 2.8 s: the fork count IS the budget miss. `claude mcp list` (7 s here)
  is gated off by default and is NOT the cause.

## Gates
- Push gate all-time: 553 allow / 166 deny (chain-review 57, chain-verify 32, mutate-then-push 30,
  global-failclosed 24, routing-governance 21, verify-hardening 2). Since 2026-10-01: 29 / 11.
  166/166 live denies match on-disk replay (reproducibility, not correctness).
- Skill gate: 115 allow / 25 deny; 20 denies on requesting-code-review; 25/25 replay as deny.
- #343 VERIFY shadow: 15 would-block episodes, 15 unresolved, 1.9/day; first read due 2026-10-12.
- Compaction log: Sep 11 auto / 11 recoveries; Oct 9 auto + 1 manual / 8 SessionStart recoveries +
  1 prompt-carrier. The unpaired one: 2026-10-01 20:08 auto compaction got no SessionStart event;
  the carrier recovered it at the next prompt 78 min later. So the carrier is a 1-in-20 backstop,
  not dead code; its premise comment ("auto no longer emits") is wrong as stated.

## Suite and repo
- 198 test files, 61k lines; hooks 15k lines; SKILL.md 59k words; CLAUDE.md 25.6 KB + rules 164 KB.
- Since 2026-09-01: tests +37,459/-1,421; hooks+skills+config+scripts +12,734/-1,623; CLAUDE.md+rules +324/-49.
- CI (30 runs): 0 failures. The full suite is NOT a CI check (CLAUDE.md), so:
- **MAIN IS RED LOCALLY**: tests/test-injection-budget.sh "injection ratchet" fails at HEAD,
  24,988 B vs pinned 24,855 (+133). Reproduces standalone AND in a scratch worktree at the very
  commit that pinned the constant (12735ff0). Invariant to: HOME contents (empty / plugins /
  skill-config), PATH (system+jq+git only), locale (C / en_US.UTF-8 / unset), git branch name
  (detached / 'x' / 60-char), fallback-registry regeneration. The pinned value could not be
  reproduced on this machine. Consequence: every routing push is denied by .verify.yml until the
  constant is corrected or the dependency found; CI stays green throughout.
- test-attestation-measurement.sh (memory: flaky 1 in 3 in-suite): 38/38 standalone in 1 s;
  suite run 1 result recorded below.
- run-tests.sh exits 1 on failure at HEAD (memory note saying it exits 0 is stale).

## Codex independent ranking (verbatim headings)
1. Replace the large mandatory routing block with a small, selective recommendation.
2. Make VERIFY depend on evidence produced by the verifier; finish the provenance experiment (label #343).
3. Fix the known flaky push blocker before redesigning the test suite.
4. Reduce hook work and retire redundant mechanisms, with latency as the constraint.
Misreadings it flagged: replay agreement != correctness; 0/23 obedience is not itself the defect
(most mandates are wrong); unrouted gating invocations are not causal proof; sticky-repeat has no
eligible observations; zero CI failures does not refute a local flake; growth is a maintenance
signal not proof of waste; best-of-3 is not tail latency.
My provisional ranking (written before reading Codex): block cost, labelling, hook latency,
compaction canary, #297/#304. Same four areas; Codex ranked the suite blocker higher and the
measured facts above say it was right to.

## Suite run 1 (2026-10-12, HEAD 653a107d, main worktree, stdin guarded)
Files run 191, passed 190, failed 1 (test-injection-budget.sh: injection ratchet). Runner exit 1.
assert-suite-complete: COMPLETE BUT FAILED (exit 2). test-attestation-measurement.sh: 38/38 in-suite.
The run dirtied config/fallback-registry.json (restored with a named checkout). Run 2 launched for a
second flake sample; result appended when available. (Archive note: run 2's result was never appended;
the RESOLVED section below superseded it, and the union-suite run before the merges was 195/195.)

## RESOLVED 2026-10-12 (same day): the 133 bytes are the PHASE REALITY line
The activation hook renders "No committed work on this branch (0 commits ahead of origin/main, clean tree)" only when the checkout is 0 ahead AND clean (hooks/skill-activation-hook.sh rule B, git run against SKILL_PROJECT_ROOT). 24,988 = clean tree, 24,855 = dirty tree, same commit. Found by diffing the normalised "ship it" dump from a clean scratch worktree against a dirty one. Fix: tests/test-injection-budget.sh passes GIT_DIR/GIT_WORK_TREE for a fixed fixture repo on every probe, with a dirty-fixture control cell (PR 1 of plugin-state-remediation). The "invariant to seven variables" paragraph above is correct as far as it goes; git state was the eighth.
