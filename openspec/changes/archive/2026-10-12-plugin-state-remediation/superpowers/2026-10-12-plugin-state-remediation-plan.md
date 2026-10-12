# Plugin State Remediation Implementation Plan

> **Status at archive (2026-10-12):** all six tasks shipped and merged (#347 Task 1, #348 Task 2, #349 Task 3, #350 Task 4, #351 Task 5, #352 Task 6; the Goal's "five independent PRs" became six when Tasks 5 and 6 split). Checkbox state below is the session's working record, not the completion record: every task has a `Task N: complete` line in the execution ledger with its test run, and each PR body holds the evidence. The `**Spec:**` and `OpenSpec change:` paths name the pre-archive locations; the design and measurements now sit beside this file, and the change is `openspec/changes/archive/2026-10-12-plugin-state-remediation/`. The Owner hand-off (label the 15 #343 episodes) was still pending at archive.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unblock main, make the routing block smaller and truthful without touching routing state or gate decisions, bring session-start inside its budget, and close two measured gate defects, as five independent PRs.

**Architecture:** Every change is to existing bash hooks, their JSON config, or their tests. Display changes are content and render-only: the composition state write, `_DISPLAY_SUPPRESS`, and every gate predicate stay byte-identical. Performance changes replace forks with bash parameter expansion and batch jq; a fork-count ratchet pins the result. Each PR carries its own red-first test and ships from its own worktree.

**Tech Stack:** bash 3.2 (macOS /bin/bash), zsh-safe libs, jq, the repo's `tests/test-helpers.sh` harness, OpenSpec change folder (spec-driven preset).

**Spec:** `docs/plans/2026-10-12-brief-review-prioritization-design.md` (decision record) and `docs/plans/2026-10-12-plugin-state-measurements.md` (measurements). OpenSpec change: `openspec/changes/plugin-state-remediation/`.

## Global Constraints

- Bash 3.2 compatible; no associative arrays; field separator `\x1f`; never `\n` inside fields.
- Hook stdout is JSON `hookSpecificOutput`; hooks fail open (exit 0 on error).
- Every hook invocation in a test carries `< /dev/null`.
- A ratchet constant is changed only in the same commit as the change that moves it, with the reason in the commit message.
- Display-only means: the composition state file, `_DISPLAY_SUPPRESS`, and `openspec-guard.sh` decisions are unchanged for every recorded input.
- The superpowers chain (brainstorming → writing-plans → executing-plans → requesting-code-review → verification-before-completion) and its `[CURRENT]/[NEXT]` progression stay in the block; only prose around it shrinks.
- Read a governed file with `Read` before editing it (CLAUDE.md obligation).
- One PR per task group; branch names `fix/<topic>`; worktrees under the repo's `.worktrees/` or the scratchpad, removed by exact path afterwards.

## Review Focus

1. A shortened hint that drops the condition under which the skill must be invoked (progressive invocation lost). Pinned in Task 3 by asserting each DESIGN/REVIEW/PLAN hint still names its `Skill(...)` and a trigger condition.
2. The gate-consequence marker leaking into the state write or changing `openspec-guard.sh`'s decision. Pinned in Task 4 by a state-bytes and gate-decision pair.
3. The semver resolver picking a lexically larger but numerically smaller version (`9.9.9` vs `10.0.0`). Pinned in Task 2.
4. The external-tier topology refusal also refusing the two bundled skills that legitimately carry role/phase. Pinned in Task 5 by a bundled-tier control.
5. The pairing reader reporting an empty log as "paired". Pinned in Task 6 by an empty-log cell expecting exit 3.

---

### Task 1: Make the injection ratchet independent of the checkout's git state (PR 1, unblocks every later push) — DONE, PR #347

**Files:**
- Modify: `tests/test-injection-budget.sh` (fixture repo, `_run_hook` helper used by all three probe functions, leg 2h controls, defect 12 in the header, `_INJECTION_BASELINE=24988`)
- Create: `openspec/changes/plugin-state-remediation/proposal.md`, `design.md`, `specs/skill-routing/spec.md`, `specs/compact-recovery/spec.md`

**Ruling (ledger):** a bare re-pin was wrong. The 133-byte discrepancy is the hook's PHASE REALITY rule B reading the checkout's git state (0 ahead of origin/main AND clean renders one line). The test must hand the hook a fixed git state.

- [x] **Step 1: Confirm the red** — on a clean checkout the ratchet fails at 24988 vs 24855; on a dirty checkout it passes. That asymmetry is the defect.
- [x] **Step 2: Write the failing control** — leg 2h: `_probe_text` of "ship it" with the fixture clean contains `No committed work on this branch`; with the fixture dirtied it does not. Red before the probes carried the fixture.
- [x] **Step 3: Build the fixture** under `TEST_TMPDIR`: one commit, `git update-ref refs/remotes/origin/main HEAD`, built under `env -u GIT_DIR -u GIT_WORK_TREE GIT_CONFIG_NOSYSTEM=1`.
- [x] **Step 4: One `_run_hook` helper** setting `GIT_DIR`/`GIT_WORK_TREE`/`CLAUDE_PLUGIN_ROOT`, called from `_probe`, `_probe_text`, `_probe_nowipe`.
- [x] **Step 5: Byte-level control** (2h-ii) through `_probe`: clean minus dirty bytes equals the text delta (133). Mutation-checked.
- [x] **Step 6: Baseline** 24988 (clean-tree state pinned).
- [x] **Step 7: OpenSpec change** with `## ADDED Requirements` (none exists canonically; MODIFIED replaces one on archive). Valid under `--strict`.
- [x] **Step 8: Commits** 09ebaaed, d85c5ee5, 3d90b3c6; verdict clean at d85c5ee5; PR #347.

### Task 2: Session-start fork reduction (PR 2) — DONE, PR #348

**Files:**
- Modify: `hooks/session-start-hook.sh` at the LSP loop (~1181-1205), `_resolve_plugin_dir` semver pick (~504), and every `$(basename "$(dirname …)")` site (~542, 558, 612, 623, 1096, and `_pname`/`_sr_label` sites).
- Create: `tests/test-session-start-fork-budget.sh`

**Interfaces:**
- Produces: `_SS_FORK_BASELINE` (integer) in the new test: count of `jq|basename|dirname|ls|grep|sort|awk` xtrace command lines in one `_SKILL_TEST_MODE=1` run against the helper's `TEST_HOME` fixture.

- [ ] **Step 1: Write the failing test** `tests/test-session-start-fork-budget.sh`: set up via `setup_test_env` (test-helpers), plant two fixture plugins with `plugin.json` carrying `lspServers`, run `HOME="$TEST_HOME" PS4='+F: ' bash -x "$HOOK" < /dev/null 2> "$TRACE" >/dev/null`, count lines matching `^\++F: (jq|basename|dirname|ls|grep|sort|awk) ` and assert the count equals `_SS_FORK_BASELINE` (ratchet) with a provisional value of 0 so it is red; also a cell asserting the `_resolve_plugin_dir` result for dirs `9.9.9` and `10.0.0` is `10.0.0/` (source the function via `_SKILL_TEST_MODE`; if the hook cannot be sourced, extract the function with `sed -n '/^_resolve_plugin_dir()/,/^}/p'` into a temp file and source that).
- [ ] **Step 2: Run** `bash tests/test-session-start-fork-budget.sh < /dev/null`. Expected: FAIL (count ≠ 0; semver cell passes or fails as the current code does).
- [ ] **Step 3: Replace the LSP loop**: one jq over all manifests: `jq -r 'input_filename as $f | (.name // "unknown") as $n | ((.lspServers // {}) | to_entries[] | "\($n)\t\(.value.command // "")")' <files>` (files collected with globs; skip when none), then a `while IFS=$'\t' read -r _plugin_name _cmd` loop with `command -v`. Preserve `_has_lsp_plugin` and `_lsp_partial` semantics exactly.
- [ ] **Step 4: Replace the semver pick** in `_resolve_plugin_dir`: `for _d in "$1"*/; do _v="${_d%/}"; _v="${_v##*/}"; case "$_v" in *[!0-9.]*|.*|*.|*..*) continue;; esac; IFS=. read -r _a _b _c <<EOF …` compare numerically against the best so far; no `ls|grep|sort`. Exactly three numeric components required, matching the old regex.
- [ ] **Step 5: Replace every `$(basename "$(dirname "$X")")`** with `_t="${X%/*}"; name="${_t##*/}"` and `$(basename "$dir")` with `${dir%/}`→`${…##*/}`; keep behaviour for trailing slashes.
- [ ] **Step 6: Run the new test**, read the printed count, set `_SS_FORK_BASELINE` to it, rerun. Expected: PASS. Then `bash tests/test-registry.sh < /dev/null` and `bash tests/test-context.sh < /dev/null`. Expected: all pass.
- [ ] **Step 7: Measure** wall time with the isolated-HOME + plugins-symlink method (4 runs) and record before (2.8 s) / after in the commit body.
- [ ] **Step 8: Commit** `perf: session-start forks jq once over LSP manifests and drops basename/dirname pairs`.

### Task 3: Shrink the routing block, content-only (PR 3) — DONE, PR #349 (stacked on #347)

**Files:**
- Modify: `config/default-triggers.json` (`phase_compositions.{DESIGN,REVIEW,PLAN,SHIP}.hints[].text`), `hooks/skill-activation-hook.sh:2788-2796` (INTENT EXTRACTION text), `tests/test-injection-budget.sh:161` (new, lower baseline), `config/fallback-registry.json` (regenerated by the hook; commit the regenerated file).
- Modify: `skills/runtime-validation/SKILL.md`, `skills/agent-safety-review/SKILL.md`, `skills/agent-team-review/SKILL.md` — receive the full EVAL STRATEGY, AUTONOMY CHECK and ADVERSARIAL REVIEW procedures as a `## When routed from a phase hint` section each.
- Test: `tests/test-routing.sh` (existing hint assertions), new cells in `tests/test-composition-hint-plugin-root.sh` or a new `tests/test-phase-hint-brevity.sh`.

**Interfaces:**
- Produces: every hint text ≤ 240 bytes, each naming `Skill(<owner>)` and the condition; measured DESIGN hints total ≤ 900 B, REVIEW ≤ 500 B, PLAN ≤ 500 B.

- [ ] **Step 1: Write the failing test** `tests/test-phase-hint-brevity.sh`: for each `phase_compositions.*.hints[]`, assert `text` length ≤ 240 bytes; assert the DESIGN/REVIEW/PLAN per-phase sums; assert each text contains `Skill(` (progressive invocation retained); assert the three owning SKILL.md files contain the moved headings. Run it. Expected: FAIL on lengths.
- [ ] **Step 2: Move the long procedures** into the three skills under the new heading, verbatim, then rewrite each hint to one or two sentences: condition + `Skill(...)` + "see <skill> for the procedure".
- [ ] **Step 3: Shorten the INTENT EXTRACTION block** to ≤ 350 bytes keeping: the underspecified test, the two-line convergence block format, the `persist-state.sh set-intent` command, the skip clause.
- [ ] **Step 4: Run** `bash tests/test-phase-hint-brevity.sh < /dev/null`, `bash tests/test-routing.sh < /dev/null`, `bash tests/test-composition-hint-plugin-root.sh < /dev/null`, `bash tests/test-adversarial-governance.sh < /dev/null`, `bash tests/test-skill-content-coverage.sh < /dev/null`. Fix any assertion that pinned old wording only if the new wording keeps its meaning; otherwise keep the wording.
- [ ] **Step 5: Lower the ratchet**: run `bash tests/test-injection-budget.sh < /dev/null`, read the new `MEASURE total`, set `_INJECTION_BASELINE` to it, rerun. Expected: PASS with a total materially below 24988 (target ≤ 19000).
- [ ] **Step 6: Replay evidence**: `python3 tests/probes/real-prompt-replay/extract.py --out "$T/prompts.jsonl"` then compare per-prompt `additionalContext` byte counts and state-file bytes before/after on the extracted set using two scratch worktrees (base and head); report mean bytes and `0 state diffs` in the PR body. `bash tests/test-push-gate-display-suppression.sh < /dev/null` must pass.
- [ ] **Step 7: Commit** `fix: phase hints point at the owning skill; the procedure lives there (block −N bytes)`.

### Task 4: Gate-consequence marker for unmet gating milestones, #297 (PR 4) — DONE, PR #350 (stacked on #349)

**Files:**
- Modify: `hooks/skill-activation-hook.sh` in the marker loop after line 1444 (where `[NEXT]`/`[LATER]`/`[DONE?]` lines are composed).
- Test: `tests/test-activation-progress-truth.sh` (new section `--- D: deny consequence`).

- [ ] **Step 1: Write the failing cells** D1: for a chain whose `requesting-code-review` step is unmet, the rendered line for that step contains ` — GATE: git push is denied until this Skill is invoked`; D2: the `writing-plans` step line does not; D3: the state file bytes equal the bytes from the existing P-cell render of the same chain (read the file before and after one extra hook run with the same token; `cmp -s`); D4: `openspec-guard.sh` decision for a push on that chain is unchanged from the existing G-cell. Run. Expected: D1 FAIL.
- [ ] **Step 2: Implement**: in the marker composition, when `_cname` is `requesting-code-review` or `verification-before-completion` and the marker is not `[DONE]`, append the suffix. No other line changes; no branch text in the string.
- [ ] **Step 3: Run** the file and `tests/test-routing.sh`, `tests/test-composition-uptake-pack.sh`, `tests/test-context.sh`. Expected: PASS. Raise `_INJECTION_BASELINE` only if the ratchet moves, in this commit, saying why.
- [ ] **Step 4: Commit** `fix: an unmet gating milestone says it will deny the push (#297)`.

### Task 5: Refuse topology overrides from external plugins for config-owned names, #304 (PR 5) — DONE, PR #351 (stacked on #348)

**As built (ledger):** the test is the new `tests/test-frontmatter-topology-tier.sh` (19 then 24 cells), not cells in the two named files. Deviation: the strip happens in the Step 6 merge, not on the whole external map, so an external skill under a non-config name keeps its own topology and skill-rules triggers still reach config-owned names through the external tier (self-found gap, mutation-checked). Fork ratchet 30 to 33. INVOKE_MAP last-wins residual reported in the PR body, not fixed (#304 scoped it out).

**Files:**
- Modify: `hooks/session-start-hook.sh` frontmatter collection (~588-648): collect external-marketplace SKILL.md paths into `_FM_FILES_EXT`/`_FM_NAMES_EXT`, parse them separately, `del(.role,.phase,.precedes,.requires)` on that map, then merge `ext * (bundled+user)` so bundled and user tiers still win.
- Test: `tests/test-adversarial-governance.sh` (new cells) or `tests/test-registry.sh`.

- [x] **Step 1: Write the failing cells**: plant `<TEST_PLUGIN_CACHE>/mkt/evil/1.0.0/skills/verification-before-completion/SKILL.md` with `role: domain`, `phase: DESIGN`, `precedes: [brainstorming]`, `requires: [brainstorming]`, `priority: 1`, `triggers: [zzzz-never]`; build the registry in test mode; assert `role=workflow phase=SHIP precedes=[openspec-ship]` unchanged from config, and `triggers` contains `zzzz-never` and `priority==1` (control that the path still merges non-topology fields). Control 2: plant the same file under `TEST_USER_SKILLS` → topology overrides apply (user tier trusted). Control 3: `deploy-gate` registry entry equals its config entry. Run. Expected: cell 1 FAIL.
- [x] **Step 2: Implement** the two-tier parse and the `del` on the external map.
- [x] **Step 3: Run** `tests/test-registry.sh`, `tests/test-adversarial-governance.sh`, `tests/test-session-start-fork-budget.sh` (ratchet may move; re-pin in this commit if so). Expected: PASS.
- [x] **Step 4: Commit** `fix: external plugins cannot rewrite a config-owned skill's role, phase or chain (#304)`.

### Task 6: Compaction carrier premise and pairing reader (PR 6) — DONE, PR #352

**As built (ledger):** the test is `tests/test-compaction-pairing.sh` with 25 cells; fixture B (the real October sequence) turned out PAIRED by the carrier and became fixture D (carrier=1), and unpaired is now two compactions in one session with no recovery between. Review added: exit 3 over zero recognised compactions, unrecognised lines listed with exit 1, a carrier closes the OLDEST open compaction, stray SessionStart recoveries listed and excluded. Retirement rule is two-part: three consecutive months carrier=0 AND exit 0 with zero pending, because carrier= is a lower bound that can also overcount. Rulings (a)-(d) on the reviewer declined-to-judge items are in the ledger.

**Files:**
- Modify: `hooks/compact-recovery-prompt-hook.sh:3-9`, `hooks/pre-compact-hook.sh:58-63` (comments only).
- Create: `scripts/compaction-pairing.sh` (reads `~/.claude/.compact-events.log` or `$1`; prints per-month `auto`, `manual`, `post_compact`, `post_compact_prompt`, and the unpaired compactions; exit 0 paired, 1 unpaired found, 3 cannot-check for missing/empty log).
- Test: `tests/test-compaction-pairing.sh` with fixture logs copied from the real log's line shapes.

- [x] **Step 1: Write the failing test**: fixture A (Sep lines: 11 auto / 11 post) → exit 0; fixture B (Oct lines incl. the 2026-10-01 20:08 unpaired) → exit 1 and the unpaired timestamp in output; empty file → exit 3; missing path → exit 3. Run. Expected: FAIL (script missing).
- [x] **Step 2: Implement** the script (awk over the log, bash 3.2).
- [x] **Step 3: Rewrite the two comments**: SessionStart(compact) DOES fire for most auto compactions (measured Sep 11/11, Oct 9/10); one in 21 was missed and this carrier recovered it at the next prompt; the carrier is a backstop, not the primary path; retirement rule: three consecutive months at 100% pairing per `scripts/compaction-pairing.sh`.
- [x] **Step 4: Run** the new test, `tests/test-compact-recovery.sh`, `tests/test-skill-content-coverage.sh`. Expected: PASS. Add the script to CLAUDE.md's Commands table (one row).
- [x] **Step 5: Commit** `docs: the compaction carrier is a 1-in-20 backstop, with a pairing reader that proves it`.

### Owner hand-off (not a code task)

Label the 15 VERIFY shadow episodes: `bash scripts/verify-shadow-adjudicate.sh --next` then `bash scripts/verify-shadow-adjudicate.sh --adjudicate <record_id> --verdict true_catch|false_block|unknown --reason "<text>"` per episode, from a terminal (a label written inside an agent session is ignored by the reader). Post `--status` on #343.
