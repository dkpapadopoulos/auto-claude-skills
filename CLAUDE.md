# auto-claude-skills

Claude Code plugin for automatic skill routing based on prompt intent and SDLC phase.

## Commands

| Command | Description |
|---------|-------------|
| `bash tests/run-tests.sh` | Run all test suites |
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

## Doc locations

Five canonical homes for project context. Read this before guessing where docs live.

- `CLAUDE.md` (repo root) — project instructions, always auto-loaded into every session.
- `docs/plans/` — design docs (`*-design.md`) and task plans (`*-plan.md`). Gitignored; per-session scratch. Default mode persists design intent here.
- `openspec/changes/` — committed proposals/specs visible to teammates. Only used in `spec-driven` preset (see Spec Persistence Modes).
- `~/.claude/projects/<project>/memory/MEMORY.md` + sibling memory files — auto-memory across sessions (typed frontmatter, slug-indexed). Project-local conversation memory.
- `.claude/` — plugin runtime state, hooks, settings, and worktrees.

## Style

- Bash 3.2 compatible (macOS `/bin/bash`). No associative arrays.
- 200ms session-start hook budget. Activation hook is faster (~50ms). Minimize jq forks — batch into single calls.
- Field separator: `\x1f` (US). Intra-field delimiter: `\x01` (SOH). Never `\n` inside fields.
- Commit messages: `<type>: <description>` (fix, feat, docs, test, refactor).
- When editing files, never replace full content if only a section needs changing. Preserve existing data in YAML/JSON files. Use targeted edits, not full-file rewrites.

## Gotchas

- `[[ $P =~ $trigger ]]` returns exit 1 on regex non-match — never use `set -e` in routing hooks.
- Grepping runtime text output (CLI/log streams, not source — Serena/LSP don't apply): use `grep -F` (or `\[ERROR\]`) when matching literals containing regex metacharacters. `grep "[ERROR]"` is a character class matching any of `E,R,O` and silently returns wrong lines; `grep "v1.9.0"` matches `v1X9Y0` because `.` is a wildcard. Bites `incident-analysis` (log-level greps), `behavioral-evaluation` (version-string assertions), and any future runtime-output parser.
- jq is optional at runtime; session-start falls back to `config/fallback-registry.json`.
- Concurrent sessions share `~/.claude/` — session-token scoping prevents counter races.
- `CLAUDE_PLUGIN_ROOT` from env; fallback: `$(cd "$(dirname "$0")/.." && pwd)`.
- `docs/plans/` is gitignored — use `git add -f` for design docs.
- When user says "proceed", continue with the next logical step. Do not ask "what would you like to proceed with?" — infer from context.
- `skills/incident-analysis/SKILL.md` has an 11,500-word test guard. Extract tables, YAML schemas (>15 lines), and URL templates to `references/` instead of inlining.
- PLAN-phase activation reads `design_path` from `~/.claude/.skill-openspec-state-<token>` and grep-checks the file for `## Capabilities Affected`, `## Out-of-Scope`, and `## Acceptance Scenarios`. All failures (missing token, missing state, missing keys, unreadable file, grep errors) fail-open — never block the hook. `SKILL_EXPLAIN=1` emits a `[design-guard]` breadcrumb to stderr.
- Composition state (`~/.claude/.skill-composition-state-<token>`) has two writers: (1) the `UserPromptSubmit` walker in `hooks/skill-activation-hook.sh` (advances `.completed` on trigger matches, primary writer), and (2) the `PostToolUse` `^Skill$` hook in `hooks/skill-completion-hook.sh` (advances `.completed` when a chain-member Skill tool returns successfully, fills the walker's in-turn blind spot). Both use the same idempotent jq-merge shape. Malformed state, non-chain skills, errored tool returns, missing jq, and missing session token all degrade silently.
- Memory backends are orthogonal: Forgetful MCP = cross-session architectural memory (opt-in), Claude Code auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Do not dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory). See `skills/unified-context-stack/tiers/historical-truth.md` "Memory backend boundary".
- `max_iterations` is role-gated: the cap in `config/default-triggers.json` is only honored for skills with `role: domain` or `role: required`. Process and workflow skills (e.g., `verification-before-completion`, `openspec-ship`, `finishing-a-development-branch`, `requesting-code-review`) are NEVER capped — this is a hardcoded invariant in `hooks/skill-activation-hook.sh::_score_skills`, not config-driven. Protects SDLC phase gates from accidental misconfiguration. Push-gate (`hooks/openspec-guard.sh`) is independent of this mechanism. Regression: `tests/test-routing.sh::test_max_iterations_role_allowlist`.

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
