# Forgetful Integration Tightening — Design

## Problem

The Forgetful Memory MCP server is wired into the auto-claude-skills plugin but suboptimally. An audit identified six gaps; a 4-perspective design debate (architect / critic / pragmatist / Codex second opinion) ran on the right shape of the fix.

Six gaps:

1. **Vague per-phase tool calls.** Phase docs say "Query Forgetful for X" and delegate mechanics to `skills/unified-context-stack/tiers/historical-truth.md:9-15`, which only sketches `discover_forgetful_tools` → `execute_forgetful_tool`. Claude does the discover-then-execute round trip at every phase.
2. **`how_to_use_forgetful_tool` declared but not surfaced.** `config/default-triggers.json:1067` registers it; nothing tells Claude to call it. The tool exists (visible in MCP surface) — it's an unused capability, not dead code.
3. **Two parallel memory systems.** Claude Code's built-in auto-memory at `~/.claude/projects/<project>/memory/MEMORY.md` (typed slug files) coexists with Forgetful MCP. No reconciliation; risk of dual-write.
4. **Read side is reactive.** Phase docs nudge "query Forgetful"; no hook fires reads at DESIGN/PLAN start.
5. **Consolidation guidance is flat.** `hooks/consolidation-stop.sh:61` says "store architectural learnings" with no type taxonomy hint.
6. **No adoption telemetry.** Serena has a v1.3.0 adoption metric (single boolean assertion in behavioral test); Forgetful has nothing. Codex caught a related asymmetry: `hooks/session-start-hook.sh:804-813` adds a `serena_connected` *connection* check; Forgetful only has *configuration* detection.

## Capabilities Affected

- `unified-context-stack` (banner guidance, Historical Truth tier, all 6 phase docs)
- Session-start hook (`hooks/session-start-hook.sh`)
- Default registry (`config/default-triggers.json`)
- Behavioral evaluation (`behavioral-evaluation` capability, test harness)
- Documentation (`CLAUDE.md`, `tiers/historical-truth.md`)

## Out-of-Scope

- **Auto-memory reconciliation / dual-write.** 3 of 4 debate lenses rejected this as wrong-shaped: Claude Code auto-memory is platform-owned, not plugin territory. Document the boundary; do not bridge it.
- **Proactive DESIGN-phase read hook.** Critic flagged banner blindness from unconditional reads; Codex noted shell hooks can't directly invoke MCP tools. Deferred behind a revival trigger.
- **Consolidation type taxonomy.** Speculative without a user requesting it. Deferred.
- **Full adoption telemetry pipeline.** Only the `forgetful_connected` boolean ships now (the *gate*, not the full nudge metric).
- **Architect's "snapshot at session start + proactive injection" architecture.** Rejected by 3 of 4 lenses on grounds of speculative scaffolding, banner blindness, and shell-can't-call-MCP correctness.
- **Removing Forgetful from default registry.** Pre-committed kill criterion only — fires if telemetry shows <5% connected after 30 days.

## Approach

Three changes, one PR:

### Change 1 — Tighten guidance (closes gaps #1 + #2)

**`hooks/session-start-hook.sh:1142-1144`:** Replace the current banner string with three-step ordering:
> *"Forgetful: call `how_to_use_forgetful_tool` once to learn the API, then `discover_forgetful_tools` for the operation list, then `execute_forgetful_tool` for reads/writes. Query memory before DESIGN; store after SHIP."*

**`skills/unified-context-stack/tiers/historical-truth.md:9-15`:** Match the same three-step ordering with phase anchors (read in DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW; write in SHIP).

**Test:** Add a banner content assertion mirroring `tests/test-session-start-banner.sh:19-42`.

### Change 2 — Close the connection-check asymmetry (closes the live half of gap #6)

**`hooks/session-start-hook.sh`:** Add a `forgetful_connected` detection block mirroring the `serena_connected` block at `:804-813`. Single boolean. Probes whether the MCP responds, not just whether it's configured.

**Capability key:** Append `forgetful_connected` to `_CANONICAL_CAP_KEYS` at `:766` alongside `serena_connected`.

**Test:** Add a context assertion parallel to existing Serena connection assertions in `tests/test-context.sh`.

### Change 3 — Document the boundary (closes gap #3)

**`skills/unified-context-stack/tiers/historical-truth.md`** and **`CLAUDE.md`**: one sentence each:
> *"Forgetful = cross-session architectural memory (opt-in MCP). Claude Code's auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in). Don't dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory)."*

### Deferred with revival triggers (write to memory, do not build)

- **Gap #4 proactive DESIGN read.** Revive when (a) a user reports "I had relevant memory but Claude didn't surface it during design" OR (b) `forgetful_connected=true` accumulates ≥5 sessions with zero `execute_forgetful_tool` calls during DESIGN.
- **Gap #5 type taxonomy in consolidation.** Revive if a user pastes a Forgetful consolidation output and asks "what shape?"
- **Gap #6 full nudge telemetry.** Revive when gap #4 or #5 has a named requester. The `forgetful_connected` flag from Change 2 is the gate.

### Pre-committed kill criterion

If, 30 days after `forgetful_connected` lands, fewer than 5% of measurable installs report `forgetful_connected=true`, remove Forgetful from the default registry. Matches the [[gitnexus-decision]] / [[cross-llm-context-decision]] pattern.

## Dissenting Views

- **Architect (medium confidence) wanted broader redesign:** session-start snapshot caching, proactive DESIGN-phase context injection via a new `forgetful-design-guard.sh`, treat auto-memory as canonical and Forgetful as cross-project mirror. Rejected because the snapshot hook can't directly invoke MCP tools from Bash, and the proactive read creates banner blindness.
- **Critic (high confidence) wanted to fix only gap #2** and pre-commit a revival trigger for everything else. Over-rotated: Codex independently called out gap #1 (doc mechanics) and the `forgetful_connected` asymmetry as real correctness issues, not speculative polish.
- **Pragmatist (high confidence) wanted gaps #1 + #2 only** and explicitly *ignore* gap #3 reconciliation. The pragmatist's stance is closest to the final synthesis; the only addition is Codex's connection-check.
- **Codex (independent, repo-grounded)** caught the `serena_connected` vs Forgetful asymmetry, the missing nudge telemetry parity, and the factual error that there are 6 phase files not 5. Verified.

## Trade-offs Accepted

- **Auto-memory and Forgetful remain unreconciled.** Documented as orthogonal. If users hit confusion, the boundary sentence is the trigger to revisit.
- **No proactive read at DESIGN.** Phase docs still rely on Claude proactively querying based on guidance — same model as today, with sharper instructions.
- **No full telemetry pipeline yet.** Only the gate flag (`forgetful_connected`) ships. Means we can't make data-driven decisions on the deferred gaps until at least one connected-session signal exists.
- **`how_to_use_forgetful_tool` call adds one extra MCP call at first read.** Trade: tighter mechanics doc beats round-tripping discovery every phase.

## Acceptance Scenarios

**Scenario 1 — Banner guidance is concrete**
GIVEN a session starts with Forgetful MCP available
WHEN the session-start hook fires
THEN the system context contains a `Forgetful:` line naming `how_to_use_forgetful_tool` first, then `discover_forgetful_tools`, then `execute_forgetful_tool` in that order
AND the line specifies "Query before DESIGN; store after SHIP"

**Scenario 2 — Connection probe distinguishes configured vs callable**
GIVEN Forgetful MCP is configured but not responding
WHEN the session-start hook fires
THEN `forgetful_memory=true` AND `forgetful_connected=false` appear in the Context Stack line
AND the existing test suite passes without modification of `forgetful_memory` semantics

**Scenario 3 — Boundary documented**
GIVEN a developer reads `tiers/historical-truth.md` or `CLAUDE.md`
WHEN they look for guidance on memory write target
THEN they find a single sentence distinguishing Forgetful (cross-session) from Claude Code auto-memory (per-project)
AND no instruction asks them to dual-write

**Scenario 4 — Test parity**
GIVEN the existing Serena nudge/connection assertions in the test suite
WHEN the suite runs after this change
THEN at least one new assertion exists for `forgetful_connected` parallel to a `serena_connected` assertion
AND a banner content test asserts the new three-tool ordering

## Decision

Proceed with the three-change PR as scoped. Defer gaps #4, #5, and the full telemetry pipeline behind the revival triggers above. Pre-commit the <5%/30-day kill criterion for Forgetful in the default registry.

## Divergences (auto-generated at ship time)

**Acceptance Scenarios:**
- [x] Scenario 1 — Banner guidance is concrete: implemented as designed (banner names `how_to_use_forgetful_tool` first, then `discover_forgetful_tools`, then `execute_forgetful_tool`; phase anchors `DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW` and `store after SHIP` present)
- [x] Scenario 2 — Connection probe distinguishes configured vs callable: implemented as designed (`forgetful_memory=true ∧ forgetful_connected=false` verified by `test_forgetful_connected_default_false`)
- [x] Scenario 3 — Boundary documented: implemented as designed (new section in `tiers/historical-truth.md` + matching note in `CLAUDE.md` Gotchas)
- [x] Scenario 4 — Test parity: implemented as designed (3 `forgetful_connected` assertions + 6 banner-content assertions added)

**Scope changes:**
- None. All three changes shipped as scoped; all deferred items persisted to project memory with revival triggers.

**Design decision changes:**
- Probe block at `hooks/session-start-hook.sh:817-827` is structurally byte-for-byte parallel to the existing `serena_connected` block (env-gate + `command -v claude` + `grep -F` for the Unicode `✓ Connected` literal + fail-open jq update). Code-review feedback (1 minor: phase-anchor assertion precision) applied as a follow-up commit (3fa9767).

## Post-ship correction (PR #37, Codex factual review)

After the initial ship, Codex reviewed external-surface factual claims and caught an inverted banner ordering:

- **Initial implementation:** `how_to_use_forgetful_tool` → `discover_forgetful_tools` → `execute_forgetful_tool`. Banner instructed Claude to "call `how_to_use_forgetful_tool` once at session start to learn the API."
- **Actual `forgetful-ai 0.4.1` server contract** (`meta_tools.py:280-283, 409-447`): `how_to_use_forgetful_tool` takes a required `tool_name: str` argument and returns docs for that one operation. The zero-argument entry point is `discover_forgetful_tools`.
- **Corrected ordering** (applied before merge): `discover_forgetful_tools` (no args, entry point) → `execute_forgetful_tool` (act) → `how_to_use_forgetful_tool(tool_name)` (per-operation docs when needed).

Files corrected: `hooks/session-start-hook.sh` banner, `skills/unified-context-stack/tiers/historical-truth.md` Tier 1 Bootstrap section, `tests/test-session-start-banner.sh` ordering assertion, `CHANGELOG.md`, `openspec/changes/archive/2026-05-19-forgetful-integration-tightening/{proposal.md,design.md,specs/.../spec.md}`, `openspec/specs/unified-context-stack/spec.md` (canonical), `~/.claude/projects/.../memory/project_forgetful_integration_tightening.md`.

Lesson reinforced (`[[codex-for-factual-claims]]`): Claude reviewers cross-check prose-against-prose; Codex inspects installed package source. For PRs that name specific tool surfaces, dispatch Codex for external-fact verification before merge.
