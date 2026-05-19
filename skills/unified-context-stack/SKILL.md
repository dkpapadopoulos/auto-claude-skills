---
name: unified-context-stack
description: Tiered context retrieval across External Truth (docs), Internal Truth (dependencies), Historical Truth (memory), and Intent Truth (feature specs) with graceful degradation based on installed tools.
---

# Unified Context Stack

An infrastructure-level skill that provides tiered context retrieval for every SDLC phase. Reads your session's `Context Stack:` capabilities line to determine which tools are available, then follows strict fallback tiers.

## How to Use

1. Check the `Context Stack:` line from your session start for capability flags
2. Read the relevant **phase document** for your current SDLC phase
3. For each capability dimension needed, follow the **tier document** in strict order

## Capability Flags

These are injected by the session-start hook as: `Context Stack: context7=true, context_hub_cli=false, ...`

| Flag | Tool | What it enables |
|------|------|----------------|
| `context7` | Context7 MCP | Broad library doc retrieval |
| `context_hub_available` | Context Hub via Context7 | High-trust curated docs — flag means Hub is *reachable*, not that it has docs for your library (query `/andrewyng/context-hub`) |
| `context_hub_cli` | `chub` CLI | Local curated doc retrieval and annotations |
| `serena` | Serena MCP | LSP-powered dependency mapping and AST edits |
| `serena_connected` | Serena MCP | MCP server is connected (not just registered); set only when `SERENA_CONNECTION_CHECK=1` |
| `forgetful_memory` | Forgetful Memory | Persistent cross-session architectural knowledge |
| `forgetful_connected` | Forgetful Memory | MCP server is connected (not just registered); set only when `FORGETFUL_CONNECTION_CHECK=1` |
| `openspec` | OpenSpec CLI | Whether the `openspec` binary is available. See the separate `OpenSpec:` capability line for detailed surface/command info. Intent Truth retrieval does NOT require this flag — it checks artifact presence directly. |

## Tier Documents

- [External Truth](tiers/external-truth.md) — API documentation retrieval
- [Internal Truth](tiers/internal-truth.md) — Blast-radius mapping and safe code edits
- [Historical Truth](tiers/historical-truth.md) — Institutional memory retrieval and storage
- [Intent Truth](tiers/intent-truth.md) — Feature specification and design rationale retrieval

**Note:** Intent Truth checks for artifact presence in the workspace (`openspec/specs/`, `openspec/changes/`, `docs/plans/`, `docs/plans/archive/`, `docs/superpowers/specs/` [legacy]). The `OpenSpec:` capability line from session-start indicates CLI availability for write operations (used by `openspec-ship`), but Intent Truth retrieval works regardless of CLI installation — it reads local files.

## Phase Documents

- [Design](phases/design.md) — Intent and historical context before proposing approaches
- [Triage & Plan](phases/triage-and-plan.md) — Context gathering before writing plans
- [Implementation](phases/implementation.md) — Mid-flight lookups during execution
- [Testing & Debug](phases/testing-and-debug.md) — Error resolution and live issue discovery
- [Code Review](phases/code-review.md) — Claim verification and dependency checks
- [Ship & Learn](phases/ship-and-learn.md) — Memory consolidation before session close
