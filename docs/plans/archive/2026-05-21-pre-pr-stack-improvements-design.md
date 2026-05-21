# Pre-PR Stack Improvements — Design

**Date:** 2026-05-21
**Slug:** pre-pr-stack-improvements
**Mode:** solo (`docs/plans/`-first)

## Problem

The pre-PR review stack is already heavy (code-reviewer + agent-team-review specialists + security-scanner + runtime-validation + drift-check + adversarial-reviewer + verification-before-completion + openspec-ship). A 3-perspective debate (architect/critic/pragmatist) plus an independent Codex assessment converged on two findings:

1. The marginal value of *adding more lenses* is near zero. Documented bot-asymptote pain on PR #34 iteration 3 (memory: `feedback_bot_review_asymptote`) shows that repeated advisory review produces churn and even contradicts deliberate decisions.
2. Two small documented pain points remain unaddressed: (a) silent drift between `default-triggers.json` and `fallback-registry.json` for jq-less setups (memory: `feedback_default_triggers_source_of_truth`); (b) lack of mechanical iteration cap on advisory lenses despite a documented 2-3 iteration policy the dev admits to having blown past.

This change addresses only those two pain points, plus a passive telemetry substrate to make future trim decisions defensible rather than speculative.

## Capabilities Affected

- `auto-claude-skills` — registry-sync test added to `tests/test-registry.sh`; passive telemetry hook appended to `hooks/skill-completion-hook.sh`.
- `skill-routing` — per-trigger `max_iterations` field in `default-triggers.json`; activation hook (`hooks/skill-activation-hook.sh`) reads composition state to enforce cap, gated by role-allowlist.
- Telemetry surface — new file `~/.claude/.advisory-lens-log.jsonl` (append-only, hashed session token, fail-open writes).

## Out-of-Scope

- **Labeled yield logging** — the labeling step requires counterfactual knowledge (would another lens have caught this?) that a solo dev cannot honestly produce. Passive shape only. Revival criterion for labeled variant: dev finds themselves wanting to query "which lens caught what" more than twice in the next 30 days.
- **PR-comment scraping for fatigue corpus** — over-engineered for solo workflow; the mechanical cap is the whole value.
- **LLM-based diff-claim parsing (C5)** — dropped. Revival trigger: ≥2 CHANGELOG overclaim incidents in 90 days.
- **Pre-commit scope-sanity check (C6)** — duplicates `design-plan-guard` + `writing-plans` + `implementation-drift-check`. Critic withdrew the proposal in Round 2.
- **Trimming the security specialist (C3)** — parked. Revival trigger: if plugin ever ingests user-supplied repos or runs untrusted prompts in a shared service.
- **Global iteration cap flag** — per-trigger only, so each lens's cap is visible at the trigger site.
- **Dashboards / log rotation for C1** — re-evaluate after 30 days of passive data; v1 is `wc -l` on demand.
- **Modifying `hooks/openspec-guard.sh` or any push-gate logic** — C2 caps advisory lenses, not phase gates. Push enforcement remains untouched.

## Approach

### C4 — trigger-sync gate (ship first, ~30min)

Add a test block to `tests/test-registry.sh` that:

1. Regenerates `fallback-registry.json` content from `config/default-triggers.json` using the same jq pipeline session-start uses, written to a tempfile.
2. Diffs the tempfile against the committed `config/fallback-registry.json`.
3. Fails with the unified diff on any non-empty result.
4. Skips (does not fail the run) if jq is absent — matches existing hook idiom.

Test-only side effect; the committed file is never overwritten by the test.

### C2 — iteration cap with role-allowlist (ship second, ~1hr)

**Schema change.** Add an optional `max_iterations: N` field to trigger blocks in `config/default-triggers.json`. Default unset = unlimited.

**Activation-hook enforcement (`hooks/skill-activation-hook.sh`).** When scoring triggers:

1. Read composition state at `~/.claude/.skill-composition-state-<token>`; count prior invocations of the same skill in `.completed` for this conversation.
2. If `max_iterations` is set AND prior count ≥ cap → skip the trigger and emit `[max-iter] skipping <skill> (<count> of <cap>)` to stderr under `SKILL_EXPLAIN=1`.
3. **Role-allowlist guard:** the cap is only honored when the trigger's `role` is `domain` OR `required`. Process and workflow roles ignore `max_iterations` even if the config sets it. This invariant is hardcoded in the hook, not config-driven, protecting `verification-before-completion`, `openspec-ship`, `finishing-a-development-branch`, `requesting-code-review`, `receiving-code-review`, etc.
4. Fail-open on state read errors, missing files, malformed JSON, or jq absence — never block activation.

**Apply caps to (registry-skill scope; subagent caps out of scope):**
- `agent-team-review` (role: `required`) → `max_iterations: 1`

**Note on subagents.** `code-reviewer`, `silent-failure-hunter`, `adversarial-reviewer`, `code-simplifier` are subagents spawned via the Task tool, not skills in the registry. They cannot be capped via this mechanism. If subagent-loop pain recurs after `agent-team-review` is capped, a future C2-v2 could add a Task-tool wrapper hook. Out of scope for v1.

**Regression test in `tests/test-routing.sh`** — set `max_iterations: 1` on a `role: process` trigger and assert it is ignored (the process skill is never skipped by the iteration counter).

### C1 — passive telemetry (ship third, ~30min)

Append one line to `hooks/skill-completion-hook.sh` that, on every Skill PostToolUse, writes:

```jsonl
{"ts": "<iso8601>", "skill": "<skill_name>", "finding_count_estimate": <int>, "session_token_hashed": "<sha256-first-12>"}
```

to `~/.claude/.advisory-lens-log.jsonl`. Hashed token matches the existing pattern from PR #36 (memory: `project_serena_pnp_and_measurement`). Write failures are silently dropped; never propagate.

No rotation, no labels, no aggregation tooling. The file grows; future investigation is `jq`/`awk` on demand.

### Cross-cutting best practices

- All hooks fail-open on errors. Telemetry/cap failures never block activation or push.
- No new runtime dependencies. Bash 3.2 + jq-optional.
- Document the role-allowlist invariant in `CLAUDE.md` under "Gotchas".
- Post-ship memory entry `project_advisory_iteration_cap.md` capturing the role-allowlist invariant and push-gate independence (answers the "did C2 weaken a gate?" question mechanically).

## Acceptance Scenarios

1. **GIVEN** a contributor edits `config/default-triggers.json` adding a new trigger block and forgets to regenerate `config/fallback-registry.json`, **WHEN** `bash tests/test-registry.sh` runs, **THEN** the test fails with a unified diff showing the missing trigger in the committed fallback.

2. **GIVEN** the `adversarial-reviewer` skill has already fired once on the current conversation, **WHEN** a subsequent prompt would re-trigger it, **THEN** the activation hook skips it, emits `[max-iter] skipping adversarial-reviewer (1 of 1)` to stderr under `SKILL_EXPLAIN=1`, and the composition chain continues with remaining process/workflow skills uncapped.

3. **GIVEN** `max_iterations: 1` is misconfigured on a `role: process` trigger (e.g., `verification-before-completion`), **WHEN** `tests/test-routing.sh` runs the regression assertion, **THEN** the cap is shown to have no effect — process skills are never skipped by the iteration counter regardless of config.

4. **GIVEN** any composition-routed Skill returns from `PostToolUse`, **WHEN** `hooks/skill-completion-hook.sh` fires, **THEN** exactly one JSONL line containing `{ts, skill, finding_count_estimate, session_token_hashed}` is appended to `~/.claude/.advisory-lens-log.jsonl`; a write failure does not propagate to the hook exit code.

## Dissenting Views (from design debate)

- **C5 (diff-anchored CHANGELOG claim check):** Architect ranked it #2 in revised ranking with a weak file-path regex MVP. Critic and Pragmatist killed it 2-1 on n=1 incident + false-positive-desensitization risk. **Outcome:** drop with revival trigger (≥2 overclaim incidents in 90 days).
- **C3 sequencing (Pragmatist):** Preferred "defer 30 days behind C1 telemetry" rather than outright drop. Critic and Architect concurred on drop given this repo's absence of auth surface (Bash hooks, JSON registries, no IDOR/session/endpoint). Functionally equivalent outcome.

## Trade-offs Accepted

- **C1 passive without labels** lets us detect *dead* lenses (`finding_count_estimate == 0` always) but cannot measure "caught only here" without manual investigation. Acceptable; labeled variant requires honest counterfactuals a solo dev cannot produce.
- **C2 cap of 1** may occasionally suppress a legitimate re-raise where new evidence exists. Mitigation: SKILL_EXPLAIN breadcrumb makes the cap visible; dev can reset session state to allow re-fire when needed.
- **C4** sits green most of the time. Acceptable insurance at 30min cost; the alternative (regenerate-on-commit hook) would add an active-write side effect outside test scope.

## Decision

Approved. Build C4 → C2 → C1 on a single feature branch (`feature/pre-pr-stack-improvements`) with the role-allowlist hardening for C2 included from day one. Single PR. Memory entry `project_advisory_iteration_cap.md` written post-ship. No openspec-ship retrofit (per `feedback_openspec_ship_skip` — small infra change, not a feature requiring a spec).

## Divergences (auto-generated at ship time, 2026-05-21)

**Acceptance Scenarios:**
- [x] AS-1 (drift detection on default-triggers.json edit) — implemented as designed; locked by `test_fallback_registry_in_sync_with_default_triggers`.
- [x] AS-2 (cap fires + breadcrumb under SKILL_EXPLAIN) — implemented as designed; verified via the half of `test_max_iterations_role_allowlist` that asserts the domain skill is capped.
- [x] AS-3 (role-allowlist invariant — process skills never capped) — implemented as designed; verified via the other half of `test_max_iterations_role_allowlist`.
- [x] AS-4 (JSONL telemetry line with 4 required fields) — implemented as designed; smoke-tested during IMPLEMENT with a synthetic PostToolUse payload that produced one valid JSONL line.

**Scope changes:**
- Modified: Cap targets narrowed from 3 (`code-reviewer`, `agent-team-review`, `adversarial-reviewer`) to 1 (`agent-team-review` only). Reason: `code-reviewer` and `adversarial-reviewer` are subagents spawned via the Task tool, not registry skills, so they cannot be capped through the trigger-block mechanism. Design doc was updated mid-implementation to reflect this constraint and to add a "Note on subagents" section. The role-allowlist guard remains the load-bearing architectural decision — narrowing the v1 cap targets does not weaken the invariant.
- Modified: Role-allowlist widened from `domain` only (initial design) to `domain` OR `required`. Reason: the actual cap target (`agent-team-review`) has `role: required` per the registry shape, so a `domain`-only allowlist would have applied to nothing. The widened allowlist still preserves the invariant — process and workflow are excluded.
- Unchanged: Out-of-scope items (labeled yield logging, PR-comment scraping, scope gates, security-specialist trim, global cap flag, dashboards, openspec-guard modifications) all stayed out of scope.

**Design decision changes:**
- Telemetry capability assignment consolidated to `skill-routing` rather than splitting between `auto-claude-skills` and `skill-routing` per "Capabilities Affected" in the design. Reason: the OpenSpec capability-taxonomy heuristic biases toward fewer/coarser capabilities (`feedback_default_triggers_source_of_truth` corollary). Both hooks live in `hooks/` and are routing infrastructure; the registry-sync test exercises routing's fallback path. Single capability is the cleaner taxonomy.
- No openspec-ship retrofit deferral. Design proposed skipping openspec-ship for "small infra change"; memory `feedback_openspec_ship_skip` overrode that — Superpowers plan was executed, so the skill is mandatory. As-built docs generated and archived.
