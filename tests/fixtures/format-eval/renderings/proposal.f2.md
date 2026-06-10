---
type: proposal
status: shipped
date: 2026-05-28
change_slug: context-economy-defaults
capabilities: [context-economy, auto-claude-skills, unified-context-stack]
---

# Proposal: Context-Economy Defaults

## Why

The Oviva-published Confluence guide *"Getting more out of Claude Code: a context & token guide"* enumerates 25 ranked techniques for reducing token spend and improving output quality. A four-perspective design debate (architect, critic, pragmatist, Codex external) plus Context7 source verification identified four high-leverage items that ACSM is currently under-serving:

1. **Output truncation is unbounded.** ACSM's `incident-analysis` and `gcp-observability` flows routinely pipe 25k+ tokens of MCP/Bash output verbatim into the context window. Anthropic ships configurable caps (`BASH_MAX_OUTPUT_LENGTH`, `MAX_MCP_OUTPUT_TOKENS`) but ACSM never writes defaults.
2. **No observability for cost decisions.** ACSM has shipped multiple defaults waves (security scanners, alert hygiene, incident-analysis playbooks) without measurable cost data. The "prove observability before abstraction" memory entry mandates that observability primitives ship before further optimization layers.
3. **No `.claudeignore` scaffolding.** Auto-discovery scans `node_modules/`, `dist/`, generated artefacts unless deliberately blocked. No template ships with ACSM today.
4. **No model-routing presets.** `CLAUDE_CODE_SUBAGENT_MODEL` and `CLAUDE_CODE_EFFORT_LEVEL` are documented levers (verified via Context7 against Anthropic docs); 22 of 27 installed plugin subagents use `inherit` semantics and would be affected by these env vars.

Codex external review confirmed: the model-routing change must NOT default-on because the env var overrides hard-pinned Opus reviewers in `pr-review-toolkit` AND Anthropic recommends `high` effort as the default for agentic work. Default-off + telemetry-gated probation is the defensible path.

## What Changes

Ship a four-item "context-economy" wave via the existing `/setup` surface:

- **A — Truncation defaults**: managed `.claude/settings.json` writes `BASH_MAX_OUTPUT_LENGTH=20000` and `MAX_MCP_OUTPUT_TOKENS=10000`. Value 10000 (not the Confluence-suggested 8000) respects Anthropic's documented warning threshold. Race-tested against a real noisy `incident-analysis` GCP-log session before commit.
- **B — Observability preset** (opt-in): `/setup --observability` writes OTEL env block (`CLAUDE_CODE_ENABLE_TELEMETRY=1`, `OTEL_METRICS_EXPORTER=otlp`, exporter endpoint placeholder) plus a `docs/observability.md` reading guide for `/usage` and `ccusage`. Replaces the dropped cozempic-doctor `/context`-parsing proposal — `/context` has no machine-readable schema per Anthropic docs.
- **C — Context-hygiene preset** (opt-in): `/setup --context-hygiene` ships a conservative `.claudeignore` template, detects monorepo subdir launch, and adds a `cozempic doctor` warning when launched from above a package directory.
- **D — Model-routing preset** (opt-in, default-OFF + probation): `/setup --model-routing` writes `CLAUDE_CODE_SUBAGENT_MODEL=haiku` and `CLAUDE_CODE_EFFORT_LEVEL=medium` to managed settings. Probation criteria: default-on only after B has captured ≥2 weeks of telemetry showing no review-quality regressions.

## Capabilities

### Added
- **`context-economy`** (NEW CAPABILITY) — governs context production budgets via managed `settings.json` defaults, observability scaffolding, ignore-file templates, and opt-in model/effort presets. Owns the precedence contract for env-var defaults written by ACSM.

### Modified
- **`auto-claude-skills`** — `/setup` command gains `--observability`, `--context-hygiene`, `--model-routing` subcommands and a baseline truncation-defaults write.
- **`unified-context-stack`** — references new `context-economy` capability for production budgets (complement to existing retrieval tiers).

## Impact

**Files added:**
- `commands/setup.md` — extended with subcommand flags
- `scripts/setup-managed-settings.sh` — idempotent jq merge into `.claude/settings.json` `env` block
- `scripts/setup-claudeignore.sh` — template emitter with monorepo detection
- `templates/claudeignore.template` — conservative ignore list
- `docs/observability.md` — `/usage` + ccusage + OTEL reading guide
- `tests/test-context-economy.sh` — Bash 3.2 idempotency + precedence tests
- `tests/race-truncation-defaults.sh` — A/B harness for incident-analysis fixture

**Files modified:**
- `skills/cozempic/SKILL.md` — adds `doctor` warning for above-package-dir launch
- `CHANGELOG.md` — accumulator entry under `[Unreleased]`

**APIs / settings keys touched** (verified via Context7 against `/websites/code_claude`):
- `env.BASH_MAX_OUTPUT_LENGTH` (env var, restart required)
- `env.MAX_MCP_OUTPUT_TOKENS` (env var, restart required; default 25000, warns below 10000)
- `env.CLAUDE_CODE_SUBAGENT_MODEL` (env var, overrides per-invocation + frontmatter `model`)
- `env.CLAUDE_CODE_EFFORT_LEVEL` (env var, overrides `/effort` + frontmatter)
- `env.CLAUDE_CODE_ENABLE_TELEMETRY` + `env.OTEL_*` (opt-in observability)

**Dependencies:**
- Bash 3.2 + jq-optional (existing ACSM constraints)
- No new runtime dependencies
- No new plugins required

## Out of Scope

- Cache-invalidation hook on mid-session `/model` swap — slash commands bypass PreToolUse per Anthropic docs; unimplementable as specified.
- Phase-boundary `/clear` nudge — Anthropic ships an idle-75min `/clear` nudge upstream; redundant.
- CLAUDE.md 500-token assertion — empirical survey showed every installed plugin's CLAUDE.md (including Anthropic's own examples) at ~1900 tokens; threshold is ecosystem-wrong.
- `/context` output parsing — no machine-readable schema per Anthropic docs.
- Cozempic doctor docs-pivot — superseded by B (telemetry beats interpretation).
