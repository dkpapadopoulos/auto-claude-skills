# Serena v1.3.0 Alignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align auto-claude-skills with Serena v1.3.0 — fix the misleading subagent-propagation banner, surface the new retrieval tools (`find_declaration`, `find_implementations`) and diagnostics tools (`get_diagnostics_for_file/_for_symbol`) in skill phase docs, and close two small gaps in `commands/setup.md` (auto-approve hook as opt-in, troubleshooting tips). Also strip the now-stale `base_modes:` block from `.serena/project.yml`.

**Architecture:** Doc-and-config-only changes. No new hooks, no new bash logic, no new dependencies. Each task touches a small, well-bounded set of files. Test-suite changes are limited to inverting two assertions in `tests/test-session-start-banner.sh` (Task 1) and adding three new grep-based assertions to lock in the new content (Task 7).

**Tech Stack:** Bash 3.2 hooks, Markdown skill files, YAML config, jq, the existing test harness in `tests/test-helpers.sh`.

**Note on plan location:** `docs/plans/` is gitignored per CLAUDE.md. This plan stays local. If you want it in git history, use `git add -f docs/plans/2026-05-15-serena-1-3-0-alignment.md`.

---

## File Structure

| File | Owner | Touched in |
|---|---|---|
| `hooks/session-start-hook.sh` | Banner emitter (Serena hint block) | Task 1 |
| `tests/test-session-start-banner.sh` | Banner content assertions | Task 1, Task 7 |
| `skills/unified-context-stack/tiers/internal-truth.md` | Tier 0 + Tier 1 doc | Task 2, Task 3 |
| `skills/unified-context-stack/phases/code-review.md` | REVIEW phase | Task 2, Task 3 |
| `skills/unified-context-stack/phases/implementation.md` | IMPLEMENT phase | Task 2 |
| `skills/unified-context-stack/phases/testing-and-debug.md` | DEBUG phase | Task 2, Task 3 |
| `skills/unified-context-stack/phases/triage-and-plan.md` | TRIAGE/PLAN phase | Task 2 |
| `commands/setup.md` | Setup runbook (Serena section) | Task 4, Task 5 |
| `.serena/project.yml` | Project-level Serena config | Task 6 |

---

### Task 1: Drop the misleading subagent-propagation line from the session-start banner

**Why:** Serena's own client docs (https://oraios.github.io/serena/02-usage/030_clients.html) state that "subagent tool runs may not use MCP servers." The current banner tells the parent agent to inject `Serena available — prefer find_symbol over Grep` into every Task subagent prompt — but most subagents can't act on it. The line ships in every session, every turn. Drop it; keep only the parent-agent guidance.

**Files:**
- Modify: `hooks/session-start-hook.sh:1102-1106`
- Modify: `tests/test-session-start-banner.sh:25-27`

- [ ] **Step 1: Read the current banner block to confirm exact lines**

Run: `sed -n '1100,1115p' hooks/session-start-hook.sh`

Expected output (current):
```
# Emit Serena usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.serena == true' >/dev/null 2>&1; then
    cat <<'EOF'
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping. When spawning subagents via the Task tool for code work, include 'Serena available — prefer find_symbol over Grep for symbol lookups' in their prompt so they inherit this guidance.
EOF
```

- [ ] **Step 2: Update the banner via Edit tool**

Replace the banner heredoc content. Use the `Edit` tool with:

`old_string`:
```
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping. When spawning subagents via the Task tool for code work, include 'Serena available — prefer find_symbol over Grep for symbol lookups' in their prompt so they inherit this guidance.
```

`new_string`:
```
Serena: When navigating code, prefer mcp__serena__ tools (find_symbol, find_declaration, find_implementations, find_referencing_symbols, get_symbols_overview) over Grep/Read for symbol lookups and dependency mapping.
```

(Note: this also folds in the v1.3.0 tool names so the parent agent learns about them at session start. The diagnostics tools `get_diagnostics_for_file/_for_symbol` are intentionally excluded from the banner — they live in the phase docs per Task 3, and the existing test `assert_not_contains "get_diagnostics_for_file"` on line 29 was a deliberate "keep banner succinct" choice that we preserve.)

- [ ] **Step 3: Update `tests/test-session-start-banner.sh` to reflect the new banner content**

Use the `Edit` tool with:

`old_string`:
```
assert_contains "Serena banner mentions mcp__serena__ tools" "mcp__serena__" "${SRC}"
assert_contains "Serena banner mentions Task tool propagation" "Task tool" "${SRC}"
assert_contains "Serena banner names the propagated guidance string" "Serena available" "${SRC}"
assert_contains "LSP banner still names mcp__ide__getDiagnostics" "mcp__ide__getDiagnostics" "${SRC}"
assert_not_contains "banner does NOT mention get_diagnostics_for_file" "get_diagnostics_for_file" "${SRC}"
```

`new_string`:
```
assert_contains "Serena banner mentions mcp__serena__ tools" "mcp__serena__" "${SRC}"
assert_contains "Serena banner names find_declaration (v1.3.0)" "find_declaration" "${SRC}"
assert_contains "Serena banner names find_implementations (v1.3.0)" "find_implementations" "${SRC}"
assert_not_contains "Serena banner does NOT propagate to subagents (Serena MCP often unavailable in subagents)" "Task tool" "${SRC}"
assert_not_contains "Serena banner does NOT use 'Serena available' propagation phrase" "Serena available" "${SRC}"
assert_contains "LSP banner still names mcp__ide__getDiagnostics" "mcp__ide__getDiagnostics" "${SRC}"
assert_not_contains "banner does NOT mention get_diagnostics_for_file (kept in phase docs)" "get_diagnostics_for_file" "${SRC}"
```

Also update the file-header comment (lines 2-4):

`old_string`:
```
# test-session-start-banner.sh — Verify the SessionStart banner contains the
# subagent-propagation line when serena=true and does NOT mention the third-pole
# diagnostics tool get_diagnostics_for_file.
```

`new_string`:
```
# test-session-start-banner.sh — Verify the SessionStart banner names the v1.3.0
# Serena retrieval tools (find_declaration, find_implementations) when serena=true,
# does NOT propagate guidance to subagents (Serena MCP usually unavailable in
# subagents), and does NOT mention the diagnostics tool get_diagnostics_for_file
# (which lives in the unified-context-stack phase docs instead, to keep the
# always-on banner succinct).
```

- [ ] **Step 4: Run the test to verify the new assertions pass**

Run: `bash tests/test-session-start-banner.sh`
Expected: `PASSED: 7 / 7` (was 5; we added 2 net new assertions and inverted 2)

- [ ] **Step 5: Run the full test suite to confirm nothing else regressed**

Run: `bash tests/run-tests.sh`
Expected: All previously-passing suites still pass. (test-serena-* suites should be unaffected — they exercise the nudge hook and registry, not the banner.)

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-session-start-banner.sh
git commit -m "fix: drop subagent propagation from Serena banner; surface v1.3.0 retrieval tools"
```

---

### Task 2: Add `find_declaration` and `find_implementations` to unified-context-stack skill files

**Why:** v1.3.0 ships two new retrieval tools that map cleanly onto questions the existing skill docs already pose ("Where is X defined?", "Who implements interface Y?"). The current docs only mention `find_symbol` / `find_referencing_symbols`. Surfacing the new tool names lets the model reach for the more precise option.

**Files:**
- Modify: `skills/unified-context-stack/tiers/internal-truth.md:14-19, 38-46`
- Modify: `skills/unified-context-stack/phases/triage-and-plan.md:29`
- Modify: `skills/unified-context-stack/phases/implementation.md:15`
- Modify: `skills/unified-context-stack/phases/testing-and-debug.md:23`
- Modify: `skills/unified-context-stack/phases/code-review.md:26`

- [ ] **Step 1: Update `tiers/internal-truth.md` Tier 1 section**

Use `Edit` with:

`old_string`:
```
## Tier 1: Serena Symbol Navigation

**Condition:** `serena = true`

- Use `find_symbol` to locate definitions
- Use `find_referencing_symbols` to map which files depend on a symbol (blast-radius)
- Use `insert_after_symbol` / `replace_symbol_body` / `rename_symbol` for safe AST-level edits without breaking formatting
```

`new_string`:
```
## Tier 1: Serena Symbol Navigation

**Condition:** `serena = true`

- Use `find_symbol` to locate symbols by name (broad, name-match-based)
- Use `find_declaration` (Serena v1.3.0+) for the precise *definition* of a symbol — preferred over `find_symbol` when you know the symbol exists and want its declaration site
- Use `find_implementations` (Serena v1.3.0+) to enumerate concrete implementations of an interface or abstract method
- Use `find_referencing_symbols` to map which files depend on a symbol (blast-radius)
- Use `insert_after_symbol` / `replace_symbol_body` / `rename_symbol` for safe AST-level edits without breaking formatting
```

- [ ] **Step 2: Update `tiers/internal-truth.md` question-mapping table**

Use `Edit` with:

`old_string`:
```
| "Where is this function defined?" | Tier 1 (Serena) if available, else Tier 2 Grep |
| "Who calls this function?" | Tier 1 (Serena `find_referencing_symbols`) |
| "Rename X to Y across the codebase" | Tier 1 (Serena `rename_symbol`) |
```

`new_string`:
```
| "Where is this function defined?" | Tier 1 (Serena `find_declaration`, falls back to `find_symbol`) — else Tier 2 Grep |
| "Who implements this interface?" | Tier 1 (Serena `find_implementations`) — else Tier 2 Grep with extra caution |
| "Who calls this function?" | Tier 1 (Serena `find_referencing_symbols`) |
| "Rename X to Y across the codebase" | Tier 1 (Serena `rename_symbol`) |
```

- [ ] **Step 3: Update `phases/triage-and-plan.md:29`**

Use `Edit` with:

`old_string`:
```
- **serena=true**: Use `find_symbol` / `find_referencing_symbols` to map all dependent files
```

`new_string`:
```
- **serena=true**: Use `find_symbol` / `find_declaration` / `find_implementations` / `find_referencing_symbols` to map all dependent files. Prefer `find_declaration` over `find_symbol` when you know the exact symbol name.
```

- [ ] **Step 4: Update `phases/implementation.md:15`**

Use `Edit` with:

`old_string`:
```
- **serena=true**: Use `find_symbol` / `find_referencing_symbols` for dependency mapping, `insert_after_symbol` for safe AST edits
```

`new_string`:
```
- **serena=true**: Use `find_symbol` / `find_declaration` / `find_referencing_symbols` for dependency mapping (prefer `find_declaration` for exact-name lookups), `insert_after_symbol` for safe AST edits
```

- [ ] **Step 5: Update `phases/testing-and-debug.md:23`**

Use `Edit` with:

`old_string`:
```
- **serena=true**: Use `find_symbol` to locate the failing function, `find_referencing_symbols` to trace callers and dependencies
```

`new_string`:
```
- **serena=true**: Use `find_declaration` to jump straight to the failing function's definition (or `find_symbol` if the name is partial), `find_referencing_symbols` to trace callers and dependencies, and `find_implementations` if the failure involves an interface dispatch
```

- [ ] **Step 6: Update `phases/code-review.md:26`**

Use `Edit` with:

`old_string`:
```
- **serena=true**: Use `find_referencing_symbols` to map all downstream dependencies before implementing
```

`new_string`:
```
- **serena=true**: Use `find_referencing_symbols` to map all downstream dependencies before implementing; use `find_declaration` to verify the reviewer is referring to the same symbol you are
```

- [ ] **Step 7: Confirm test suite still passes (no test changes expected here — covered by Task 7)**

Run: `bash tests/run-tests.sh`
Expected: All suites pass.

- [ ] **Step 8: Commit**

```bash
git add skills/unified-context-stack/tiers/internal-truth.md skills/unified-context-stack/phases/triage-and-plan.md skills/unified-context-stack/phases/implementation.md skills/unified-context-stack/phases/testing-and-debug.md skills/unified-context-stack/phases/code-review.md
git commit -m "docs: surface Serena v1.3.0 find_declaration and find_implementations in unified-context-stack"
```

---

### Task 3: Add Serena diagnostics as Tier 0 fallback when `lsp=false`

**Why:** Serena v1.3.0 ships `get_diagnostics_for_file` and `get_diagnostics_for_symbol`. The unified-context-stack Tier 0 currently uses `mcp__ide__getDiagnostics` exclusively (gated on `lsp=true`). Users with Serena but no IDE LSP plugin currently get no Tier 0 guidance. Add a fallback: LSP first, then Serena, then grep. Banner stays succinct (deliberate choice — see Task 1).

**Files:**
- Modify: `skills/unified-context-stack/tiers/internal-truth.md:5-12` (Tier 0 section)
- Modify: `skills/unified-context-stack/phases/testing-and-debug.md:21-25`
- Modify: `skills/unified-context-stack/phases/code-review.md:23-28`

- [ ] **Step 1: Update `tiers/internal-truth.md` Tier 0 to add the fallback**

Use `Edit` with:

`old_string`:
```
## Tier 0: LSP Diagnostics

**Condition:** `lsp = true`

- Use `mcp__ide__getDiagnostics` for compile errors, type errors, and linter warnings
- Authoritative for compiler truth — Tier 1 and Tier 2 tools cannot produce this
- Prefer this over grepping for error strings when the question is "what is broken"
```

`new_string`:
```
## Tier 0: Diagnostics

Strict fallback order:

**0a — `lsp = true`:** Use `mcp__ide__getDiagnostics` for compile errors, type errors, and linter warnings. Authoritative for compiler truth.

**0b — `lsp = false` and `serena = true`:** Use `mcp__serena__get_diagnostics_for_file` (file-scoped) or `mcp__serena__get_diagnostics_for_symbol` (symbol-scoped) — Serena v1.3.0+. These run against Serena's bundled language server, less integrated than the IDE's own LSP but still authoritative for the languages Serena supports.

**0c — neither available:** Skip Tier 0 — there is no authoritative diagnostics source. Drop to Tier 1 (Serena symbol nav) or Tier 2 (grep) and verify by running the build/test commands.

In all cases, prefer Tier 0 over grepping for error strings when the question is "what is broken".
```

- [ ] **Step 2: Update `phases/testing-and-debug.md:21-25` Internal Truth section**

Use `Edit` with:

`old_string`:
```
### 3. Internal Truth (Dependency Tracing)
If the error involves internal code or unclear call chains:
- **lsp=true** (compile/type errors): Use `mcp__ide__getDiagnostics` FIRST — authoritative compiler output beats grepping for error substrings
- **serena=true**: Use `find_symbol` to locate the failing function, `find_referencing_symbols` to trace callers and dependencies
- **serena=false and lsp=false**: Use Grep to search for the function name and trace references manually
```

`new_string`:
```
### 3. Internal Truth (Dependency Tracing)
If the error involves internal code or unclear call chains:
- **lsp=true** (compile/type errors): Use `mcp__ide__getDiagnostics` FIRST — authoritative compiler output beats grepping for error substrings
- **lsp=false and serena=true** (compile/type errors): Use `mcp__serena__get_diagnostics_for_file` or `_for_symbol` — Serena v1.3.0+ — as a fallback authoritative source
- **serena=true** (call-chain tracing): Use `find_declaration` to locate the failing function, `find_referencing_symbols` to trace callers and dependencies, `find_implementations` if the failure crosses an interface
- **serena=false and lsp=false**: Use Grep to search for the function name and trace references manually
```

(Note: Step 6 of Task 2 also touched `code-review.md:26`; this Task touches lines 23-28 — distinct edits, no conflict.)

- [ ] **Step 3: Update `phases/code-review.md:23-28` Internal Truth section**

Use `Edit` with:

`old_string`:
```
### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change or claims an error exists:
- **lsp=true** (reviewer claims type/compile error): Use `mcp__ide__getDiagnostics` to verify before responding — authoritative output either confirms the reviewer or refutes the claim
- **serena=true**: Use `find_referencing_symbols` to map all downstream dependencies before implementing; use `find_declaration` to verify the reviewer is referring to the same symbol you are
- **serena=false and lsp=false**: Use Grep to find all references, Read to verify each usage. Extra caution on complex hierarchies.
- Flag any files that would break silently from the proposed change
```

`new_string`:
```
### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change or claims an error exists:
- **lsp=true** (reviewer claims type/compile error): Use `mcp__ide__getDiagnostics` to verify before responding — authoritative output either confirms the reviewer or refutes the claim
- **lsp=false and serena=true** (reviewer claims type/compile error): Use `mcp__serena__get_diagnostics_for_file` (Serena v1.3.0+) as the authoritative fallback before responding
- **serena=true**: Use `find_referencing_symbols` to map all downstream dependencies before implementing; use `find_declaration` to verify the reviewer is referring to the same symbol you are
- **serena=false and lsp=false**: Use Grep to find all references, Read to verify each usage. Extra caution on complex hierarchies.
- Flag any files that would break silently from the proposed change
```

- [ ] **Step 4: Run the full test suite to confirm nothing regressed**

Run: `bash tests/run-tests.sh`
Expected: All suites pass. (Banner test in particular: `assert_not_contains "get_diagnostics_for_file"` should still hold because we only put diagnostics in skill files, not the banner.)

- [ ] **Step 5: Commit**

```bash
git add skills/unified-context-stack/tiers/internal-truth.md skills/unified-context-stack/phases/testing-and-debug.md skills/unified-context-stack/phases/code-review.md
git commit -m "docs: add Serena v1.3.0 diagnostics as Tier 0 fallback when lsp=false"
```

---

### Task 4: Make `serena-hooks auto-approve` an opt-in choice in setup.md

**Why:** `commands/setup.md:280` currently says: *"Do NOT add the `serena-hooks auto-approve` hook — auto-approval is a user preference."* This silently denies a meaningful UX win to users who *would* prefer it. The right framing is: don't enable by default, but expose it as an opt-in. The other two exclusions in that line (`activate` is replaced by auto-claude-skills' own session-start; `cleanup` is already documented) stay as-is.

**Files:**
- Modify: `commands/setup.md:245-281` (the "Optional: Serena official hooks" subsection)

- [ ] **Step 1: Re-read the current section to confirm exact content**

Run: `sed -n '245,281p' commands/setup.md`

- [ ] **Step 2: Replace the exclusion paragraph with an opt-in question**

Use `Edit` with:

`old_string`:
```
Note: Do NOT add the `serena-hooks activate` SessionStart hook — the auto-claude-skills session-start hook already handles Serena detection and context setup. Do NOT add the `serena-hooks auto-approve` hook — auto-approval is a user preference. The `remind` hook fires on every tool call (broader than our built-in Grep-only nudge) and the `cleanup` hook prevents session data leaks.
```

`new_string`:
```
Note: Do NOT add the `serena-hooks activate` SessionStart hook — the auto-claude-skills session-start hook already handles Serena detection and context setup. The `remind` hook fires on every tool call (broader than our built-in Grep-only nudge) and the `cleanup` hook prevents session data leaks.

**Optional: auto-approve hook.** Serena v1.3.0 also ships `serena-hooks auto-approve`, which auto-approves Serena tool calls when Claude Code is in `acceptEdits` or `auto` permission mode. Skips the per-tool approval prompt entirely. **Ask the user:** "Do you want Serena tool calls to be auto-approved when you're in `acceptEdits` or `auto` mode? (Recommended for users who run long autonomous sessions; skip if you prefer to approve each call.)"

If the user agrees, merge this into the `PreToolUse` array of `.claude/settings.json` (alongside the `remind` entry — do not replace it):

```json
{
  "matcher": "mcp__serena__.*",
  "hooks": [
    {
      "type": "command",
      "command": "serena-hooks auto-approve --client=claude-code"
    }
  ]
}
```
```

- [ ] **Step 3: Verify the file is still valid markdown (no broken JSON code fences)**

Run: `awk '/^```/{c++} END{print c, "fence markers (should be even)"}' commands/setup.md`
Expected: An even number.

- [ ] **Step 4: Commit**

```bash
git add commands/setup.md
git commit -m "docs: expose serena-hooks auto-approve as opt-in in /setup"
```

---

### Task 5: Add Serena troubleshooting tips to setup.md

**Why:** Serena's client docs flag two real friction points users hit in the wild. Neither is in our setup runbook today.

1. Anthropic recommends `claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"` to fix Opus tool-adherence drift toward Serena tools.
2. Slow MCP startup is fixed with `export MCP_TIMEOUT=60000`.

**Files:**
- Modify: `commands/setup.md` — append a "Troubleshooting Serena" subsection after the upgrade block (after the `uv tool upgrade serena-agent` block, before the "Optional: Serena official hooks" block)

- [ ] **Step 1: Read the area around line 240-247 to find the right insertion point**

Run: `sed -n '238,250p' commands/setup.md`

You should see the `uv tool upgrade` block ending at line 243, then a blank line, then `**Optional: Serena official hooks (recommended for heavy Serena usage)**` at line 245.

- [ ] **Step 2: Insert the troubleshooting block before the Optional section**

Use `Edit` with:

`old_string`:
```
To upgrade an existing PyPI-based install to the latest version:
```bash
uv tool upgrade serena-agent --prerelease=allow
```

**Optional: Serena official hooks (recommended for heavy Serena usage)**
```

`new_string`:
```
To upgrade an existing PyPI-based install to the latest version:
```bash
uv tool upgrade serena-agent --prerelease=allow
```

**Troubleshooting Serena:**

- *Model ignoring Serena tools.* Recent Opus releases occasionally bias toward built-in tools over Serena. Anthropic's recommended workaround is to start Claude with a Serena-aware system prompt:
  ```bash
  claude --system-prompt="$(serena prompts print-cc-system-prompt-override)"
  ```
  This is a one-time per-session flag — not a permanent install — and is only needed if you observe the model preferring Grep/Read over `mcp__serena__` tools.

- *Slow MCP startup or timeout errors.* Set a higher MCP timeout before launching Claude:
  ```bash
  export MCP_TIMEOUT=60000
  ```

**Optional: Serena official hooks (recommended for heavy Serena usage)**
```

- [ ] **Step 3: Verify markdown is still well-formed**

Run: `awk '/^```/{c++} END{print c, "fence markers (should be even)"}' commands/setup.md`
Expected: An even number.

- [ ] **Step 4: Commit**

```bash
git add commands/setup.md
git commit -m "docs: add Serena troubleshooting (system-prompt override, MCP_TIMEOUT) to /setup"
```

---

### Task 6: Strip the stale `base_modes:` block from `.serena/project.yml`

**Why:** Serena v1.3.0 removed the ability to override `base_modes` from `project.yml` — only `added_modes` works at project scope now. The current `base_modes:` block (lines 78-84) is empty and the comment incorrectly claims "this setting overrides the global configuration." Cosmetic but misleading; remove the block entirely. The `added_modes:` field (line 127) is the v1.3.0-correct replacement and is already present.

**Files:**
- Modify: `.serena/project.yml:78-84`

- [ ] **Step 1: Re-read the current block**

Run: `sed -n '76,86p' .serena/project.yml`

- [ ] **Step 2: Remove the block**

Use `Edit` with:

`old_string`:
```
# list of mode names to that are always to be included in the set of active modes
# The full set of modes to be activated is base_modes + default_modes.
# If the setting is undefined, the base_modes from the global configuration (serena_config.yml) apply.
# Otherwise, this setting overrides the global configuration.
# Set this to [] to disable base modes for this project.
# Set this to a list of mode names to always include the respective modes for this project.
base_modes:

# list of mode names that are to be activated by default, overriding the setting in the global configuration.
```

`new_string`:
```
# Note: as of Serena v1.3.0, base_modes can no longer be overridden at the project level — it is global only.
# Use `added_modes` (below) to add per-project modes on top of the global base.

# list of mode names that are to be activated by default, overriding the setting in the global configuration.
```

- [ ] **Step 3: Verify the YAML still parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.serena/project.yml'))" && echo OK`
Expected: `OK` (no traceback).

- [ ] **Step 4: Verify Serena (if installed) still accepts the project**

If `serena` is on PATH, run a no-op project load:
```bash
command -v serena && serena project status 2>&1 | head -5 || echo "(serena not installed locally, skip)"
```
Expected: Either no errors / project loads, or the "(serena not installed locally, skip)" message. Either way, no YAML parse errors.

- [ ] **Step 5: Commit**

```bash
git add .serena/project.yml
git commit -m "chore: strip stale base_modes from .serena/project.yml (Serena v1.3.0 removed project override)"
```

---

### Task 7: Add grep-based regression assertions for the new content

**Why:** Tasks 2-3 are pure doc edits — without targeted assertions, a future edit could silently revert the v1.3.0 references. Add a small new test that greps the skill files for the v1.3.0 tool names. Match the existing `test-helpers.sh` style.

**Files:**
- Create: `tests/test-serena-v1-3-0-skill-references.sh`

- [ ] **Step 1: Write the test file**

Use `Write` to create `tests/test-serena-v1-3-0-skill-references.sh`:

```bash
#!/usr/bin/env bash
# test-serena-v1-3-0-skill-references.sh — Lock in Serena v1.3.0 tool name
# references in unified-context-stack so future edits don't silently regress.
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_DIR="${REPO_ROOT}/skills/unified-context-stack"

# shellcheck source=tests/test-helpers.sh
source "${SCRIPT_DIR}/test-helpers.sh"

setup_test_env

# --- Tier doc: internal-truth must mention all v1.3.0 tools ---
TIER_DOC="${SKILL_DIR}/tiers/internal-truth.md"
assert_file_exists "internal-truth.md exists" "${TIER_DOC}"

TIER_SRC="$(cat "${TIER_DOC}")"
assert_contains "Tier doc names find_declaration" "find_declaration" "${TIER_SRC}"
assert_contains "Tier doc names find_implementations" "find_implementations" "${TIER_SRC}"
assert_contains "Tier doc names get_diagnostics_for_file" "get_diagnostics_for_file" "${TIER_SRC}"

# --- Phase docs: each phase that does dependency tracing must mention at least one v1.3.0 tool ---
for PHASE_FILE in "phases/triage-and-plan.md" "phases/implementation.md" "phases/testing-and-debug.md" "phases/code-review.md"; do
    FULL="${SKILL_DIR}/${PHASE_FILE}"
    assert_file_exists "${PHASE_FILE} exists" "${FULL}"
    PHASE_SRC="$(cat "${FULL}")"
    assert_contains "${PHASE_FILE} names find_declaration" "find_declaration" "${PHASE_SRC}"
done

# --- Diagnostics fallback must appear in testing-and-debug and code-review only ---
DEBUG_SRC="$(cat "${SKILL_DIR}/phases/testing-and-debug.md")"
REVIEW_SRC="$(cat "${SKILL_DIR}/phases/code-review.md")"
assert_contains "testing-and-debug names Serena diagnostics fallback" "get_diagnostics_for_file" "${DEBUG_SRC}"
assert_contains "code-review names Serena diagnostics fallback" "get_diagnostics_for_file" "${REVIEW_SRC}"

teardown_test_env

if [ "${TESTS_FAILED}" -gt 0 ]; then
    printf "\nFAILED: %d / %d\n" "${TESTS_FAILED}" "${TESTS_RUN}"
    exit 1
fi
printf "\nPASSED: %d / %d\n" "${TESTS_PASSED}" "${TESTS_RUN}"
exit 0
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x tests/test-serena-v1-3-0-skill-references.sh`

- [ ] **Step 3: Run the new test on its own**

Run: `bash tests/test-serena-v1-3-0-skill-references.sh`
Expected: `PASSED: 11 / 11` (3 tier-doc assertions + 4 phase-existence + 4 phase-find_declaration + 2 diagnostics — counting may vary by helper; the important thing is `FAILED: 0`).

- [ ] **Step 4: Verify it gets picked up by `tests/run-tests.sh`**

Run: `bash tests/run-tests.sh 2>&1 | grep -i "serena-v1-3-0"`
Expected: A line referencing the new test (the run-tests.sh harness should auto-discover any `test-*.sh` file).

If it isn't auto-discovered, inspect `tests/run-tests.sh` to see how tests are listed and add the new file the same way other suites are added.

- [ ] **Step 5: Run the full suite**

Run: `bash tests/run-tests.sh`
Expected: All suites pass, including the new one.

- [ ] **Step 6: Commit**

```bash
git add tests/test-serena-v1-3-0-skill-references.sh
# If you had to modify run-tests.sh to register the new suite:
# git add tests/run-tests.sh
git commit -m "test: add regression assertions for Serena v1.3.0 tool references in unified-context-stack"
```

---

### Task 8: Final verification & changelog entry

**Why:** Belt-and-suspenders. Confirm the full plan landed cleanly, update CHANGELOG.md so users see what changed, and bump the version per the repo's existing convention (chore commits like `chore: bump version to 3.32.2 [skip ci]` show this is a releasable surface).

**Files:**
- Modify: `CHANGELOG.md`
- Modify: version file (check `package.json` / `plugin.json` / wherever version lives)

- [ ] **Step 1: Run the full test suite one more time**

Run: `bash tests/run-tests.sh`
Expected: All suites pass.

- [ ] **Step 2: Find the version source of truth**

Run: `grep -l '"version"' plugin.json package.json 2>/dev/null; cat plugin.json 2>/dev/null | head -5`
Identify which file holds the version string. (The recent commits show `chore: bump version to 3.32.2` — find where that number lives.)

- [ ] **Step 3: Add a CHANGELOG entry**

Read the top of `CHANGELOG.md` and add a new entry following the existing format. Suggested copy:

```markdown
## 3.33.0

### Changed
- Serena v1.3.0 alignment in unified-context-stack: surfaced `find_declaration`, `find_implementations`, and `get_diagnostics_for_file/_for_symbol` as fallback when `lsp=false`.
- Session-start banner: dropped the subagent-propagation sentence (subagent MCP runs are usually disabled per Serena's own client docs); banner now also names `find_declaration` / `find_implementations`.
- `commands/setup.md`: added Serena troubleshooting (system-prompt override, `MCP_TIMEOUT`) and exposed `serena-hooks auto-approve` as an opt-in.
- `.serena/project.yml`: removed the now-obsolete `base_modes:` override block (Serena v1.3.0 made `base_modes` global-only); use `added_modes` for per-project additions.

### Added
- `tests/test-serena-v1-3-0-skill-references.sh` — regression assertions locking in v1.3.0 tool names across the skill docs.
```

(Adjust the version number to match the repo's bumping convention — minor bump because new optional setup behavior was added.)

- [ ] **Step 4: Bump the version**

Update the version-of-truth file identified in Step 2 (likely `plugin.json`) to the new version.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md plugin.json
git commit -m "chore: release 3.33.0 — Serena v1.3.0 alignment"
```

- [ ] **Step 6: Final sanity scan**

Run: `bash tests/run-tests.sh && git log --oneline -10`
Expected: All tests pass; the last 7-8 commits should reflect Tasks 1-8 in order.

---

## Self-Review

**Spec coverage:** All 6 items from the agreed scope are accounted for:
- Item 1 (subagent fix) → Task 1
- Item 2 (serena-hooks: only `auto-approve` was a real gap) → Task 4
- Item 3 (`find_declaration` / `find_implementations`) → Task 2
- Item 4 (Serena diagnostics as Tier 0 fallback) → Task 3
- Item 5 (system-prompt override + `MCP_TIMEOUT`) → Task 5
- Item 6 (stale `base_modes:` in project.yml) → Task 6

Plus regression coverage (Task 7) and release plumbing (Task 8) — both add little risk and prevent silent revert.

**Placeholder scan:** All steps contain the actual `Edit`/`Write` content needed. No "TBD", no "similar to Task N", no "add appropriate validation."

**Type / name consistency:** Tool names used consistently across all tasks: `find_declaration`, `find_implementations`, `find_referencing_symbols`, `find_symbol`, `get_diagnostics_for_file`, `get_diagnostics_for_symbol`, `mcp__serena__*`, `mcp__ide__getDiagnostics`. The capability flag names match the canonical set in `hooks/session-start-hook.sh:766` (`context7, context_hub_cli, context_hub_available, serena, forgetful_memory, openspec, posthog, lsp`).

**Risk notes for the executor:**
1. Task 1 inverts existing test assertions — this is intentional. Don't be alarmed when those two `assert_contains` calls flip to `assert_not_contains`.
2. Task 7 step 4 may require a tiny edit to `tests/run-tests.sh` if it doesn't auto-discover `test-*.sh` files. Check first; only edit if needed.
3. Task 6 is config-only and YAML-validated; if Serena is installed locally, the optional `serena project status` check provides extra confidence.
4. Task 8's version bump must match the repo's actual versioning convention — check `git log --oneline | grep "bump version"` to confirm whether minor (3.33.0) or patch (3.32.3) is right; this plan suggests minor because new opt-in setup behavior is added.
