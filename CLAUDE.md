# auto-claude-skills

Claude Code plugin for automatic skill routing based on prompt intent and SDLC phase.

## Commands

| Command | Description |
|---------|-------------|
| `bash tests/run-tests.sh` | Run all test suites |
| `bash scripts/assert-suite-complete.sh [--min-files N] <log>` | Decide whether a suite LOG represents a run that finished (0 complete+pass, 1 not-a-pass, 2 complete+failed, 3 cannot-check) |
| `bash tests/test-routing.sh` | Test skill routing engine |
| `bash tests/test-registry.sh` | Test registry building and merging |
| `bash tests/test-context.sh` | Test context formatting and phase composition |
| `bash -n hooks/<name>.sh` | Syntax-check a hook (no execution) |
| `SKILL_EXPLAIN=1 bash hooks/skill-activation-hook.sh` | Debug routing with explanation output |

## Architecture

- **Two main hooks**: `session-start-hook.sh` builds the skill registry at session start; `skill-activation-hook.sh` scores and routes on every prompt.
- **Registry**: Cached at `~/.claude/.skill-registry-cache.json`. Merged from `config/default-triggers.json` + plugin discoveries + `~/.claude/skill-config.json` overrides.
- **Scoring**: Regex trigger match → base score + priority + name bonus + composition bonus → role-cap selection (max 1 process, 2 domain, 1 workflow).
- **Output**: JSON via `hookSpecificOutput` on stdout. Hooks fail-open (exit 0 on error).

## Skill-creation flow

Three-stage division of labor for building new skills:

1. **`writing-skills`** (DESIGN phase, `role=required`, always fires) — enforces discipline, anatomy completeness, and a failing pressure-test before a line of implementation is written.
2. **`skill-scaffold`** — emits seed files including the routing fixture stub (`tests/fixtures/routing/<name>.txt`) and an evals stub; provides the mechanical skeleton for the next two stages.
3. **`skill-creator`** (REVIEW phase, advisory) — validates triggering on a held-out prompt set before merge; catches over/under-matching that unit tests miss.

The **enforceable done-gate** is owned and deterministic, and now covers **two** artifacts per owned, trigger-routed skill: (1) a routing fixture `tests/fixtures/routing/<name>.txt` with >=1 `MATCH` line and >=1 verbatim-borrowed `NO_MATCH` decoy (`tests/test-fixture-coverage.sh`); and (2) a content-assertion test — some `tests/*.sh` must reference `skills/<name>/` (`tests/test-skill-content-coverage.sh`, content-based/naming-agnostic). Both run in CI on every PR via `.github/workflows/done-gates.yml` (hard-blocking only once marked Required in branch protection — see `docs/CI.md`); regression `tests/test-done-gate-ci.sh` pins that workflow so the claim cannot rot. **`.verify.yml` is the LOCAL gate** (`substrate: local`) — read by the push gate and `project-verification`, by no workflow — so the full `tests/run-tests.sh` suite is NOT a CI check. The external skills (`writing-skills`, `skill-creator`) are recommended quality layers — they are not merge preconditions.

## Doc locations

Six canonical homes for project context. Read this before guessing where docs live.

- `CLAUDE.md` (repo root) — project instructions, always auto-loaded into every session.
- `docs/plans/` — design docs (`*-design.md`) and task plans (`*-plan.md`). Gitignored; per-session scratch. Default mode persists design intent here.
- `openspec/changes/` — committed proposals/specs visible to teammates. Only used in `spec-driven` preset (see Spec Persistence Modes).
- `~/.claude/projects/<project>/memory/MEMORY.md` + sibling memory files — auto-memory across sessions (typed frontmatter, slug-indexed). Project-local conversation memory.
- `.claude/knowledge/` — committed, human-gated team facts (OKF/auto-memory shaped; one markdown file per fact with YAML frontmatter). Read at session-start as the base tier (index.md injected, capped at 8192 bytes, fail-open). Optionally mirrored to each user's local Forgetful for semantic retrieval via `scripts/knowledge-forgetful-map.sh`. Validated by `scripts/knowledge-validate.sh`. Note: repos that gitignore `.claude/` wholesale must un-ignore this dir with `!.claude/knowledge/` or committed facts will not travel with the repo.
- `.claude/` — plugin runtime state, hooks, settings, and worktrees.

## Style

- Bash 3.2 compatible (macOS `/bin/bash`). No associative arrays.
- 200ms session-start hook budget. Activation hook is faster (~50ms). Minimize jq forks — batch into single calls.
- Field separator: `\x1f` (US). Intra-field delimiter: `\x01` (SOH). Never `\n` inside fields.
- Commit messages: `<type>: <description>` (fix, feat, docs, test, refactor).
- When editing files, never replace full content if only a section needs changing. Preserve existing data in YAML/JSON files. Use targeted edits, not full-file rewrites.

## Gotchas

- `CLAUDE_PLUGIN_ROOT` from env; fallback: `$(cd "$(dirname "$0")/.." && pwd)`.
- `docs/plans/` is gitignored — use `git add -f` for design docs.
- When user says "proceed", continue with the next logical step. Do not ask "what would you like to proceed with?" — infer from context.
- `skills/incident-analysis/SKILL.md` has a word-count **ratchet**, not a fixed ceiling — `INCIDENT_SKILL_WORD_BASELINE` in `tests/test-incident-analysis-content.sh` is pinned to the file's exact current size, so headroom is deliberately ZERO and growth in either direction fails until the constant is edited. That visibility is the control; the number is not sacred. Growing it: extract tables, YAML schemas (>15 lines), URL templates and rationale to `references/` FIRST, then raise the constant in the same commit and say why in the message. Shrinking it: lower the constant in the same commit, or a staleness leg fails and the reduction is banked as new slack. This replaced a fixed 11,500 ceiling that had drifted to 66 words of headroom while never once forcing a reduction — do not restate that number as the limit, because it permitted regrowth up to the cap, which is a ratchet in the wrong direction.
- Memory backends are orthogonal: Forgetful MCP = cross-session architectural memory (opt-in), Claude Code auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Do not dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory). See `skills/unified-context-stack/tiers/historical-truth.md` "Memory backend boundary".
- `.claude/knowledge/` writes are human-gated AND PR-gated (memory-poisoning / lethal-trifecta surface) — never auto-write; the session-start injection is framed as untrusted reference data; `scripts/knowledge-validate.sh` is the consistency gate (type present, no dangling `[[links]]`, index↔files match, source resolves).

### Path-scoped rule files

The rest of this section lives in `.claude/rules/*.md`, each scoped with `paths:`
frontmatter so it loads when you touch the files it governs rather than every
session. The prose is verbatim — nothing was summarised in the move. **If you are
reasoning about one of these surfaces without opening a file that triggers the
rule, read the file directly**; a path-scoped rule does not load on reasoning
alone, and does not come back after `/compact` until a matching file is read.

| Rule file | Governs | Read it before |
|---|---|---|
| `push-gate-enforcement.md` | `openspec-guard.sh`, `skill-gate.sh`, the gate libs (`verdict`, `git-command`, `branch-ledger`, `phase-*`), `gate-status.sh` | touching any deny leg, subject resolution, command parsing, deny text, or fail-open announcement |
| `remedy-reachability.md` | the `config/*.json` preconditions, `skill-activation-hook.sh` rendering, `phase-attest.sh`, `assets/design-seed/` | changing any text that tells an agent how to fix a block, or any path a rendered hint names |
| `push-gate-telemetry.md` | `implement-shadow.sh`, `review-shadow.sh`, `shadow-corpus.sh`, `pr-diff.sh`, `shadow-adjudicate.sh`, `push-gate-capture.sh` | touching a shadow corpus, a `predicate_version`/`schema_version`, or any pre-registered rate |
| `outbound-guards.md` | `publish-guard.sh`, the egress-consent hooks, `consult-dispatch.sh`, `reviewer-evidence-hook.sh` | changing what may leave the machine, or how reviewer dispatch is credited |
| `test-suite.md` | `tests/**`, `.github/workflows/**`, `.verify.yml` | adding or changing a test, a fixture gate, or a CI workflow |
| `shell-portability.md` | every `*.sh` under `hooks/`, `scripts/`, `tests/`, `skills/` | writing shell that a hook, a test, or the model's own Bash turn will run |
| `routing-state.md` | `skill-activation-hook.sh`, `session-start-hook.sh`, `config/*.json`, `persist-state.sh` | changing routing, scoring, session tokens, or composition state |

`docs/enforcement-map.md` is the one-page map of everything that can block, in
check order; `bash scripts/gate-status.sh` replays those checks against the
current branch. Start there for "why was this denied", not with the rule files.

## Spec Persistence Modes

Two modes for where design intent is persisted:

**Default (`docs/plans/`-first):** Design docs, plans, and specs go to `docs/plans/*.md` (gitignored). Low-ceremony, session-scoped. Best for solo dev or exploratory work. `openspec-ship` creates retrospective `openspec/changes/` at SHIP time.

**Spec-driven mode (`openspec/changes/`-first):** Set `{"preset": "spec-driven"}` in `~/.claude/skill-config.json`. Design intent is committed to `openspec/changes/<feature>/proposal.md + design.md + specs/<cap>/spec.md` during DESIGN phase. Teammates see in-progress specs via `git pull`. `openspec-ship` syncs the existing change at SHIP time instead of creating from scratch.

**When to use spec-driven:**
- ≥2 active developers on the repo
- Long-lived codebase where decision traceability matters
- Teams with concurrent work on overlapping capabilities
- Repos planning to add `openspec validate` to CI

**When to stay default:**
- Solo development
- Short-lived repos / prototypes
- Exploratory phases where designs frequently get rejected
- Repos without an established capability taxonomy

**Task plans stay local in both modes.** `docs/plans/*-plan.md` (task breakdowns, checkbox progress) is unchanged by the mode flag — those are the dev's execution scratch.

**Switching modes:** Change the preset at any time; existing artifacts are not migrated. New features use the new location.

**CI enforcement:** Spec-driven mode pairs with the `OpenSpec Validate` GitHub Actions workflow (`.github/workflows/openspec-validate.yml`). The workflow runs `scripts/validate-active-openspec-changes.sh` on every PR. For true hard-block enforcement, the check must be marked **Required** in GitHub Branch Protection — see `docs/CI.md` for setup steps.

**Per-capability review routing:** Pair spec-driven + CI with `.github/CODEOWNERS` to auto-route reviews per capability. Copy `.github/CODEOWNERS.template` into your repo and replace the `@your-*-team` placeholders with real teams. Full guide in `docs/CI.md`.
