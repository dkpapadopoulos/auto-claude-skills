# Design: Forgetful Integration Tightening

## Architecture

Three changes converged on the same capability surface (`unified-context-stack`), shipped as one PR:

### Change 1 — Banner + tier doc mechanics

The session-start banner emit block (`hooks/session-start-hook.sh:1154-1158`) prints a `Forgetful:` hint when `.forgetful_memory == true`. The previous copy named only `discover_forgetful_tools` and `execute_forgetful_tool`, forcing Claude to round-trip discovery every phase. The new copy specifies the full three-step API:

```
mcp__forgetful__discover_forgetful_tools   (no args, entry point — fetch operation list)
mcp__forgetful__execute_forgetful_tool     (per call — read/write)
mcp__forgetful__how_to_use_forgetful_tool(tool_name)   (per-operation docs when needed)
```

Codex review of PR #37 caught an inverted ordering in the initial implementation (`how_to_use` listed first). The corrected ordering above matches the actual `forgetful-ai 0.4.1` server contract (`meta_tools.py:280-283, 409-447`): `how_to_use_forgetful_tool` takes a required `tool_name: str` argument and returns docs for that one operation — it is not a zero-argument session-start API discovery call.

Phase anchors are embedded in the banner string: read in `DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW`; write in `SHIP`. The same mechanics are mirrored in `skills/unified-context-stack/tiers/historical-truth.md` so the tier doc is the canonical reference; the banner is the at-session reminder.

### Change 2 — `forgetful_connected` capability probe

Parallels the existing `serena_connected` probe (added in PR #35). Three sites in `hooks/session-start-hook.sh`:

1. `_CANONICAL_CAP_KEYS` (line 766) gains `"forgetful_connected"`.
2. Initial `CONTEXT_CAPS` jq object (line 781) gains `forgetful_connected: false`.
3. New probe block (lines 817-827) runs after the existing `serena_connected` block, gated on `FORGETFUL_CONNECTION_CHECK=1` and `command -v claude`. Parses `claude mcp list` output with `grep '^forgetful: ' | grep -qF '✓ Connected'`. Locale-safety follows the same gotcha as PR #36 (`grep -F` for the Unicode `✓ Connected` literal under C/POSIX locale). Fail-open on any error.

Registration-based `.forgetful_memory` (already detected via `~/.claude.json` MCP entries) remains the routing gate. `.forgetful_connected` is a stricter "callable" hint — it distinguishes "MCP configured but not responding" from "MCP available and answering."

`config/fallback-registry.json` gains `"forgetful_connected": false` in the default `context_capabilities` block so downstream consumers always see the key.

### Change 3 — Memory backend boundary

A new "Memory backend boundary" section in `tiers/historical-truth.md` and a matching one-line note in `CLAUDE.md` Gotchas formalize the distinction between Forgetful (cross-session architectural memory, opt-in MCP) and Claude Code auto-memory (per-project conversation memory, built-in, slug-indexed). Policy: no dual-write — pick one per learning based on scope.

## Dependencies

No new packages. No new MCP servers. Reuses:
- Existing `claude mcp list` CLI (already used by `serena_connected` probe)
- Existing jq fallback pattern
- Existing `_CANONICAL_CAP_KEYS` synchronization between hook and fallback registry

## Decisions & Trade-offs

**Decisions:**

1. **Three changes, one PR.** The architect proposed a broader snapshot-and-inject redesign; rejected because (a) shell hooks can't directly invoke MCP tools, and (b) proactive reads create banner blindness. Settled on the smallest coherent ship.
2. **`forgetful_connected` off by default.** Mirrors `serena_connected`. The probe costs a `claude mcp list` fork; running it on every session-start would erode the 200ms hook budget for users who don't want connection diagnostics.
3. **Document the boundary, don't bridge it.** 3 of 4 debate lenses rejected auto-memory reconciliation as wrong-shaped: auto-memory is platform-owned, not plugin territory.
4. **`how_to_use_forgetful_tool` is now actually used.** It was registered in `config/default-triggers.json:1067` but never surfaced in any banner or doc — declared-but-not-used dead code. The banner now instructs Claude to call it once per session.

**Trade-offs accepted:**

- Auto-memory and Forgetful remain unreconciled; if users hit confusion, the boundary sentence is the revival trigger.
- No proactive DESIGN-phase read. Phase docs still rely on Claude proactively querying based on guidance — same model as today, sharper instructions.
- No full nudge telemetry. Only the `forgetful_connected` gate flag ships; data-driven decisions on deferred gaps wait for at least one connected-session signal.
- `how_to_use_forgetful_tool` adds one extra MCP call at first read. Trade: tighter mechanics beats round-tripping discovery every phase.

## Dissenting Views

- **Architect (medium confidence)** wanted session-start snapshot caching + proactive injection via a new `forgetful-design-guard.sh`. Rejected on correctness (shell can't call MCP) and banner-blindness grounds.
- **Critic (high confidence)** wanted to fix only gap #2 (`how_to_use_forgetful_tool` not surfaced) and pre-commit revival triggers for everything else. Over-rotated: Codex flagged gaps #1 and the connection-check asymmetry as real correctness issues, not speculative polish.
- **Pragmatist (high confidence)** wanted gaps #1 + #2 only. Closest to final synthesis; the only addition is Codex's connection-check.
- **Codex (independent, repo-grounded)** caught the `serena_connected` vs Forgetful asymmetry, the missing nudge telemetry parity, and the factual error that there are 6 phase files, not 5. Verified.

## Deferred with Revival Triggers

Persisted to project memory (`project_forgetful_integration_tightening.md`):

- **Proactive DESIGN-phase memory read** — revive when a user reports "I had relevant memory but Claude didn't surface it during design" OR `forgetful_connected=true` accumulates ≥5 sessions with zero `execute_forgetful_tool` calls during DESIGN.
- **Consolidation type taxonomy** — revive if a user pastes a Forgetful consolidation output and asks "what shape?"
- **Full Serena-style nudge telemetry** — revive when one of the above gaps has a named requester.

## Pre-committed Kill Criterion

If, 30 days after `forgetful_connected` lands, <5% of measurable installs report `forgetful_connected=true`, remove Forgetful from the default registry. Pattern matches `[[gitnexus-decision]]` and `[[cross-llm-context-decision]]`.
