## Why

Serena v1.3.0 (May 12, 2026) shipped four new MCP tools — `find_declaration`, `find_implementations`, `get_diagnostics_for_file`, `get_diagnostics_for_symbol` — and made breaking changes to project-level config (`base_modes` is now global-only; use `added_modes`). Serena's client docs also clarified that subagent tool runs typically cannot use MCP servers, making the existing session-start banner's subagent-propagation guidance wasted tokens.

The plugin's `unified-context-stack` skill, session-start banner, `/setup` runbook, and `.serena/project.yml` template all carried stale guidance against this new tool surface and config schema.

## What Changes

Retrospective documentation for PR #34 (merged `b000844`, released as 3.33.0). Four surfaces were aligned with Serena v1.3.0:

1. **Banner (`hooks/session-start-hook.sh:1105`):** Drops the subagent-propagation sentence; adds `find_declaration` / `find_implementations` to parent-agent guidance. Diagnostics tools intentionally stay out of the banner.
2. **Skill docs (`skills/unified-context-stack/`):** Tier doc and four phase docs (triage-and-plan, implementation, testing-and-debug, code-review) gain `find_declaration` across all four; `find_implementations` is added only where interface-dispatch is the natural question (triage-and-plan, testing-and-debug). Tier 0 restructured into a 3-tier strict fallback (`0a lsp` → `0b serena diagnostics` → `0c skip`).
3. **Setup runbook (`commands/setup.md`):** Adds Serena troubleshooting (system-prompt override + `MCP_TIMEOUT`). Reframes `serena-hooks auto-approve` from a silent exclusion into an explicit opt-in question.
4. **Project config (`.serena/project.yml`):** Removes the now-obsolete `base_modes:` block (Serena v1.3.0 made it global-only). Adds a note pointing users at `added_modes` (already present).

Regression coverage added: `tests/test-serena-v1-3-0-skill-references.sh` (14 assertions) locks the v1.3.0 tool name references in the skill docs against silent regression. `tests/test-session-start-banner.sh` assertions inverted to lock the new banner contract.

## Capabilities

### Modified Capabilities

- `unified-context-stack`: Tier 0 diagnostics now follows a 3-tier fallback (LSP → Serena diagnostics → skip); Tier 1 Serena navigation surface expanded with `find_declaration` and `find_implementations`; phase docs updated across all four SDLC phases.

## Impact

- **Affected code:** `hooks/session-start-hook.sh` (banner string only — no logic), `skills/unified-context-stack/{tiers,phases}/*.md`, `commands/setup.md`, `.serena/project.yml`, `tests/test-session-start-banner.sh`.
- **New files:** `tests/test-serena-v1-3-0-skill-references.sh` (regression lock).
- **Version:** 3.32.2 → 3.33.0 (minor — new opt-in `auto-approve` setup behavior).
- **Behavior change:** Banner is shorter; subagents spawned via Task no longer receive injected Serena guidance via the banner. This matches Serena's own client doc statement that subagent MCP runs typically can't use MCP servers, so the dropped guidance was wasted tokens.
- **No runtime regression risk:** All changes are documentation/string/config edits. No new bash logic, no new dependencies, no hook control-flow changes. Full test suite 45/45 across every iteration.
