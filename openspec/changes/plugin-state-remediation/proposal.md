## Why

Measured on 2026-10-12 over the week after PR #334 (102 sessions, 366 typed human turns): 55 human prompts received a routing block averaging 5.5 KB (304 KB, about 76k tokens, in the week); 23 `MUST INVOKE` mandates were shown and the model obeyed 0 in the turn and 1 of 18 ever in the session, while it invoked the two gating skills 11 times without being routed to them. Of the block's bytes, 39% are composition-chain markers and 30% are per-phase hint prose; the skill routing lines are 4%. The activation hook takes 151 to 197 ms per prompt against a stated budget of about 50 ms, and session-start takes about 2.8 s with twelve plugins against a stated 200 ms, because it forks 621 external processes. Separately, `tests/test-injection-budget.sh` is red on a clean main checkout at 24,988 bytes against a pinned 24,855: the hook's PHASE REALITY rule reads the checkout's own git state (commits ahead of `origin/main`, dirty tree) and renders a 133-byte line only on a clean tree, so the ratchet silently measured whoever ran it. Red on clean main means the local push gate denies every routing push while CI stays green. Two gate defects remain open: an unmet gating milestone renders as a progress marker with no warning that it will deny the push (#297), and a discovered `SKILL.md` from an external plugin can rewrite a config-owned skill's role, phase and chain (#304). The post-compaction prompt carrier's premise comment says `SessionStart(compact)` no longer fires for auto compaction; the local event log shows it pairing in 20 of 21 cases.

Codex (independent mode, conclusions withheld) ranked the same four areas: smaller selective routing output, verifier-produced VERIFY evidence, the flaky push blocker, and hook work reduction with latency as the constraint.

## What Changes

- **Ratchet made deterministic.** The test hands the hook a fixture git repository (one commit, `origin/main` at HEAD, clean tree) through `GIT_DIR`/`GIT_WORK_TREE`, so PHASE REALITY always renders and its cost is in the baseline; a control cell dirties the fixture and asserts the line disappears, proving the redirection binds. Baseline 24,988; lowered again by the block cut.
- **Per-phase hints point at the owning skill.** The EVAL STRATEGY, AUTONOMY CHECK and ADVERSARIAL REVIEW procedures move into `runtime-validation`, `agent-safety-review` and `agent-team-review`; each hint becomes a condition plus `Skill(...)`. The INTENT EXTRACTION directive shrinks to its convergence block and persist command. Content-only: no scorer, chain-walk or state-write change.
- **Unmet gating milestones say so.** `requesting-code-review` and `verification-before-completion` carry a suffix stating the push is denied until invoked, when unmet. Render-only.
- **Session-start forks once over LSP manifests** and drops `basename`/`dirname` pairs and the `ls | grep | sort` semver pick; a fork-count ratchet pins it.
- **External plugins cannot rewrite a config-owned skill's topology.** `role`, `phase`, `precedes`, `requires` from the external-marketplace tier are discarded for config-owned names; `triggers` and `priority` still merge; bundled and user tiers keep their overrides.
- **Compaction carrier premise corrected**, with `scripts/compaction-pairing.sh` reading the event log so the carrier's retirement can be decided on evidence.

## Capabilities

### Modified Capabilities

- `skill-routing`: smaller hint prose with progressive invocation retained; gate-consequence marker; external-tier topology refusal at registry build; session-start fork budget.
- `compact-recovery`: carrier documented as a measured backstop; pairing reader added.

## Impact

- `hooks/skill-activation-hook.sh` (INTENT EXTRACTION text; marker suffix), `hooks/session-start-hook.sh` (LSP loop, semver pick, frontmatter tiers, path expansion), `hooks/compact-recovery-prompt-hook.sh`, `hooks/pre-compact-hook.sh` (comments).
- `config/default-triggers.json`, `config/fallback-registry.json` (hint texts).
- `skills/runtime-validation/SKILL.md`, `skills/agent-safety-review/SKILL.md`, `skills/agent-team-review/SKILL.md` (receive the procedures).
- `scripts/compaction-pairing.sh` (new). `tests/test-injection-budget.sh` (baseline), `tests/test-session-start-fork-budget.sh`, `tests/test-phase-hint-brevity.sh`, `tests/test-compaction-pairing.sh` (new), `tests/test-activation-progress-truth.sh`, `tests/test-adversarial-governance.sh` (cells).
- Shipped as six PRs in the order above; each is independently revertable.
