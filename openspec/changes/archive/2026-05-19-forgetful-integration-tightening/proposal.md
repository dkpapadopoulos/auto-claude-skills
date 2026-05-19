## Why

The Forgetful Memory MCP server was wired into the plugin but with vague mechanics, no connection-vs-configuration distinction, and no documented boundary against Claude Code's built-in auto-memory. A 4-perspective design debate (architect/critic/pragmatist + Codex) identified three coherent issues worth shipping now and three deferrable items with revival triggers.

## What Changes

1. **Banner + tier doc mechanics:** the Forgetful banner in `hooks/session-start-hook.sh` and Tier 1 in `skills/unified-context-stack/tiers/historical-truth.md` now specify the explicit three-step ordering `mcp__forgetful__discover_forgetful_tools` (no args, entry point) → `mcp__forgetful__execute_forgetful_tool` (act) → `mcp__forgetful__how_to_use_forgetful_tool(tool_name)` (per-operation docs when needed), with phase anchors (read in DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW; write in SHIP). Ordering verified against `forgetful-ai 0.4.1` server source via Codex review (PR #37 — the initial implementation had `how_to_use` first; corrected before merge).
2. **`forgetful_connected` capability flag:** a new context-capability key parallel to `serena_connected`, off by default, gated on `FORGETFUL_CONNECTION_CHECK=1`. When enabled, the session-start hook parses `claude mcp list` output for the `✓ Connected` marker on the `forgetful` entry. Registration-based `.forgetful_memory` remains the routing gate; `.forgetful_connected` is a downstream hint.
3. **Memory backend boundary:** a new "Memory backend boundary" section in `tiers/historical-truth.md` and matching note in `CLAUDE.md` Gotchas document Forgetful (cross-session architectural memory) and Claude Code auto-memory (per-project conversation memory) as orthogonal — no dual-write policy.

## Capabilities

### Modified Capabilities
- `unified-context-stack`: extends the Historical Truth tier with explicit three-step Forgetful mechanics, adds a Memory backend boundary section, and adds a new `forgetful_connected` session capability flag (parallel to the existing `serena_connected` flag from PR #35).

## Impact

- `hooks/session-start-hook.sh` — banner copy updated, canonical capability key list extended, new fail-open `claude mcp list` probe block gated on `FORGETFUL_CONNECTION_CHECK=1`
- `skills/unified-context-stack/tiers/historical-truth.md` — Tier 1 reading/writing sections rewritten with explicit tool ordering and phase anchors; new "Memory backend boundary" section added
- `CLAUDE.md` — Gotchas section gains a Forgetful-vs-auto-memory boundary note
- `config/fallback-registry.json` — `forgetful_connected: false` added to default `context_capabilities` block
- `tests/test-context.sh` + `tests/test-session-start-banner.sh` — new assertions covering ordering, phase anchors, capability key presence, and configured-vs-callable distinction
- `tests/test-registry.sh` — keycount bump (9 → 10) reflects the new canonical key

Deferred behind revival triggers (persisted in project memory):
- Proactive DESIGN-phase memory read
- Consolidation type taxonomy
- Full Serena-style nudge telemetry

Pre-committed kill criterion: if <5% of measurable installs report `forgetful_connected=true` 30 days post-ship, remove Forgetful from the default registry.
