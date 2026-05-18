# Design: Serena v1.3.0 Alignment

## Architecture

Four surfaces, each touched independently:

```
Serena v1.3.0
    │
    ├─ New tools (find_declaration, find_implementations,
    │    get_diagnostics_for_file/_for_symbol)
    │           │
    │           ├─ session-start banner (parent-agent guidance only)
    │           ├─ unified-context-stack tier doc (canonical tool list)
    │           └─ unified-context-stack 4 phase docs (per-SDLC-phase guidance)
    │
    ├─ Subagent MCP unavailability (per client docs)
    │           │
    │           └─ Banner drops subagent-propagation sentence
    │
    ├─ base_modes now global-only
    │           │
    │           └─ .serena/project.yml removes stale override block
    │
    └─ Anthropic system-prompt override + MCP_TIMEOUT troubleshooting
                │
                └─ commands/setup.md gains "Troubleshooting Serena" subsection
                    + exposes serena-hooks auto-approve as opt-in
```

## Dependencies

No new code dependencies. References Serena v1.3.0 tool names in docs.

## Decisions & Trade-offs

### D1: Drop the subagent-propagation banner sentence rather than reword it

Considered:
- (A) **Drop entirely.** Chosen.
- (B) Keep but qualify with "only if subagent has MCP enabled."
- (C) Replace with a recipe for detecting MCP availability inside the subagent.

Rationale: Serena's own client docs state that subagent tool runs typically can't use MCP servers. The banner ships to every session, every turn — keeping a caveat adds per-session token cost for a vanishingly small subset of subagent invocations that actually have MCP. The parent-agent's "prefer mcp__serena__" guidance is preserved; subagents that DO have MCP enabled discover those tools from their own tool list anyway.

### D2: Add Serena diagnostics as Tier 0 fallback only in skill phase docs, not in the banner

Considered:
- (A) **Phase docs only.** Chosen.
- (B) Add to banner too.

Rationale: The banner is intentionally succinct — diagnostics route through skill docs at the appropriate SDLC phase. A pre-existing test (`test-session-start-banner.sh`) explicitly asserted `assert_not_contains "get_diagnostics_for_file"` as a deliberate "keep banner short" choice; the new contract preserves that.

### D3: Asymmetric `find_implementations` placement across phase docs

`find_declaration` was added to all 4 phase docs (triage-and-plan, implementation, testing-and-debug, code-review) because "Where is X defined?" is a question every phase asks.

`find_implementations` was added only to triage-and-plan and testing-and-debug because "Who implements interface Y?" is naturally a planning question (blast-radius mapping) or a debugging question (interface-dispatch failures). It does not fit implementation.md (mid-flight dependency mapping) or code-review.md (downstream blast-radius for a specific symbol).

Initially the CHANGELOG overclaimed coverage; a Codex review caught this and the claim was tightened in `e35461d` to match the asymmetric reality.

### D4: Reframe `auto-approve` from silent exclusion to opt-in

The pre-existing `commands/setup.md` said *"Do NOT add the serena-hooks auto-approve hook — auto-approval is a user preference."* This denied user agency. The new copy keeps the default (don't auto-add) but presents the hook as a clear opt-in question for users running long autonomous sessions in `acceptEdits`/`auto` mode.

The other two excluded hooks (`activate`, `cleanup`) stay excluded: `activate` is replaced by the plugin's own session-start hook, and `cleanup` is already documented in the same section.

### D5: CHANGELOG entries appended under existing `[Unreleased]`, not promoted to `[3.33.0]`

Matches the convention established by the previous 3.32.0/3.32.1/3.32.2 bumps, all of which left `[Unreleased]` intact. A future "release cleanup" commit will likely promote the whole accumulated block when the maintainer decides to draw a clean version line.

### D6: Iteration cap at 3 bot-review rounds

The Claude Plugin Review bot operates as a per-push linter without commit-history context, so it can always find advisory-level nits. Iterations 1 and 2 fixed substantive issues (Codex `find_implementations` coverage + symbol-scoped variant in code-review.md). Iteration 3 added one final clarification (complementary bullets). After iteration 3, decision was to merge regardless of additional advisory findings to avoid asymptotic churn.

## Implementation Notes (synced at ship time)

The original plan called for 8 tasks. In practice 11 commits landed:
- Tasks 1-8 from the plan (8 commits) — all per per-task spec + quality reviews approved.
- Iteration 1: Codex-flagged CHANGELOG overclaim + `get_diagnostics_for_symbol` optionality (commit `e35461d`).
- Iteration 2: Bot-flagged `_for_symbol` shorthand → spelled out fully (commit `f5face8`).
- Iteration 3a: Bot-flagged missing symbol-scoped variant in code-review.md → added (commit `188f320`).
- Iteration 3b: Bot-flagged either/or ambiguity in code-review.md bullets → clarified as complementary (commit `7171a6c`).
- Squash-merged as `b000844` on `main`.
