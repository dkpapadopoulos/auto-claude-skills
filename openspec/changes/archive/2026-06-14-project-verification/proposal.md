# Proposal: Project-Native Verification Primitive

## Why

GitHub issue #58 (filed from a real downstream Python session — DuckDB + Typer CLI quant engine, `uv`/`ruff`/`pyright`/`pytest`, no frontend) surfaces a **mechanism/substrate gap**, not a policy gap. Process discipline is strong; the substrate underneath it is missing in four ways. A four-perspective design debate (architect, critic, pragmatist) plus a Codex cross-model verification pass graded each premise against actual repo state. Findings:

1. **No project-native test-execution mechanism.** `verification-before-completion` (a Superpowers skill we do NOT own) enforces the *policy* "show test output before claiming done"; `runtime-validation` covers browser/API/CLI **E2E**. Nothing **discovers and runs the repo's own declared gate** (e.g. `uv run pytest -m "not slow"` + `ruff` + `pyright`) and emits structured pass/fail evidence. VERIFIED against the repo.

2. **`deploy-gate` is fail-OPEN on absent CI.** `skills/deploy-gate/SKILL.md:32` runs `gh pr checks --fail-fast 2>/dev/null || gh run list --limit 1 --json conclusion -q '.[0].conclusion'`. On a repo/branch with zero CI runs the fallback emits an empty string, which the gate text ("Last CI run passed or PR checks are green") treats as not-a-failure → effectively green. "CI absent ≠ CI passing" is unhandled. PARTIALLY-TRUE (the executable shape is fail-open; a careful model could still read empty as fail — so the fix must harden the command, not just the prose).

3. **`frontend-playwright` keyword trigger mis-fires on backend repos.** The trigger (`config/default-triggers.json:868`) is unanchored — `page`/`form`/`tab`/`card`/`style`/`ui` match inside `pagination`/`transform`/`tabulate`/`onboarding`. Codex pinpointed the root cause the in-house agents missed: the hint matcher at `hooks/skill-activation-hook.sh:1270` uses raw `[[ "$P" =~ $htrigger ]]` and is **NOT protected by the scorer's word-boundary post-filter** (lines 195-228). So the anchoring must live in the regex itself. VERIFIED empirically under `/bin/bash 3.2.57`.

4. **No ground-truth phase anchoring** (issue Gap 3). The composition tracker advances on conversational classification and asserted `[DONE] IMPLEMENT/REVIEW/SHIP` while no code existed. This is a composition-state-machine concern orthogonal to the verification primitive — carved out to its own debate to avoid scope creep (see Out-of-Scope).

The issue's own premise "no per-project config" is **partially false**: every robust discovery path either reuses a convention file or requires in-skill (LLM) disambiguation — and a *hook* can do neither. This split (a model-invoked skill can reason and ask; a hook cannot) is the load-bearing architectural fact that shapes the whole design.

## What Changes

Ship ONE well-scoped verification primitive plus two cheap, model-independent refinements — as a single coherent PR with the low-risk fixes sequenced first.

- **A — `project-verification` skill (NEW, phase REVIEW).** Discovers the repo's declared test/lint/type gate via a **deterministic-first** ladder, runs it **locally**, and emits structured `{substrate, passed, failed, command, output_excerpt}` evidence. Substrate is the literal string `"local"` in v1 (enum deferred). The evidence is **convenience/audit, never a trust boundary** — any session-written marker is forgeable by the gated agent (confirmed at `skill-activation-hook.sh:1350`) and the shared-`~/.claude/` token race makes singleton markers unreliable.

- **B — `frontend-playwright` regex hardening (Gap 4).** Replace the unanchored alternation with **bracket-class anchors** `(^|[^a-z])…([^a-z]|$)` — NOT `\b`, which silently fails under Bash 3.2 (empirically confirmed: `[[ "a ui change" =~ \b(ui)\b ]]` → exit 1). Drop the weakest backend-colliding fragments. Regression-tested under `/bin/bash`.

- **C — `deploy-gate` fail-CLOSED on absent CI (Gap 2).** Make CI check #1 treat empty `statusCheckRollup` / zero-step jobs as **NOT a pass**, and surface green / red / absent-or-broken as distinct states. This is the only **model-independent** hard signal in the design and is the real fail-closed boundary; it ships regardless of the skill.

**Enforcement stance (best practice, explicit):** the hard fail-closed gate keys on **external CI conclusion** (item C). A future v2 `openspec-guard` marker-read is documented as **skip-friction only**, not a trust boundary. An **opt-in repo-local `.git/hooks/pre-push`** installer (runs the discovered gate outside the Claude session) is offered as the local hard-gate option, honestly noting its `--no-verify` escape. No in-hook test execution — ever (latency + fail-open contract).

## Capabilities

### Added
- **`project-verification`** (NEW CAPABILITY) — discovers a repo's declared test/lint/type gate with deterministic-first precedence, runs it on a recorded substrate (v1: local), and emits structured pass/fail evidence consumed by `deploy-gate` and (advisorily) the push surface. Owns the `.verify.yml` convention and the evidence schema.

### Modified
- **`skill-routing`** — `frontend-playwright` trigger gains bracket-class anchoring so it stops mis-firing on backend prompts; encodes the rule that hint-path triggers are not covered by the scorer post-filter and must self-anchor.
- **`pdlc-closed-loop`** — `deploy-gate` CI check becomes fail-closed on absent/zero-step CI and learns to accept a fresh local verification result as the verification of record.

## Impact

**Files added:**
- `skills/project-verification/SKILL.md` — discovery ladder, in-skill disambiguation, local run, evidence emission
- `skills/project-verification/references/discovery-ladder.md` — the ordered ladder + `.verify.yml` schema (kept out of SKILL.md per the word-count-guard precedent)
- `tests/fixtures/project-verification/evals/behavioral.json` — behavioral pack (matches the repo's `tests/fixtures/<cap>/evals/behavioral.json` convention; `scripts/scenario-coverage.sh` tracks it once the spec is archived to `openspec/specs/` at SHIP)
- `tests/test-project-verification.sh` — discovery-ladder + evidence-shape unit tests
- `.verify.yml` (this repo, dogfood) — `bash tests/run-tests.sh`

**Files modified:**
- `config/default-triggers.json` + `config/fallback-registry.json` — new `project-verification` routing entry (REVIEW, role domain) + anchored `frontend-playwright` regex (both files, per the canonical-source rule)
- `skills/deploy-gate/SKILL.md` — fail-closed CI check; accept local verification evidence
- `tests/test-routing.sh` — anchored-regex positive/negative fixtures (run under `/bin/bash`); `project-verification` scores into REVIEW
- `CHANGELOG.md` — `[Unreleased]` accumulator entry

**Out-of-scope (this change):** Gap 3 phase-reconciliation (separate composition-state debate); substrate enum; any project-profile subsystem; any hook that executes tests.
