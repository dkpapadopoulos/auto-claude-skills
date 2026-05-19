# Forgetful Integration Tightening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tighten Forgetful Memory MCP integration in three coherent changes: (1) make banner + tier-doc mechanics concrete via `how_to_use → discover → execute` ordering, (2) add a `forgetful_connected` connection probe mirroring `serena_connected`, (3) document the boundary between Forgetful and Claude Code auto-memory.

**Architecture:** Banner-content surface change in `hooks/session-start-hook.sh` and `tiers/historical-truth.md`. New `forgetful_connected` capability flag added alongside `serena_connected` using the same `claude mcp list` grep pattern, gated on `FORGETFUL_CONNECTION_CHECK=1`. One-sentence boundary note in two docs. TDD throughout — banner-content tests via grep mirroring `tests/test-session-start-banner.sh`, capability tests mirroring `tests/test-context.sh:868-900`.

**Tech Stack:** Bash 3.2 (macOS-compatible, no associative arrays), jq, shell-based testing harness, no new dependencies.

**Design doc:** `docs/plans/2026-05-19-forgetful-integration-tightening-design.md`

**Acceptance scenarios (from design doc — verification criteria):**
1. Banner contains `how_to_use_forgetful_tool`, `discover_forgetful_tools`, `execute_forgetful_tool` in that order with phase anchors
2. Connection probe distinguishes configured vs callable: `forgetful_memory=true` AND `forgetful_connected=false` when MCP configured but not responding
3. Boundary documented in `tiers/historical-truth.md` and `CLAUDE.md` — single sentence distinguishing Forgetful from auto-memory
4. Test parity with Serena — at least one `forgetful_connected` assertion and one banner-content test for the new three-tool ordering

---

## File Structure

**Modify:**
- `hooks/session-start-hook.sh` — 3 sites: canonical keys (line 766), initial CONTEXT_CAPS jq (line 781), banner emit block (lines 1141-1145). Add new connection-probe block after line 815.
- `skills/unified-context-stack/tiers/historical-truth.md` — replace lines 9-15 with concrete three-tool ordering; add boundary sentence after Tier 2 section.
- `CLAUDE.md` — add boundary sentence under a new short "Memory backends" subsection or append to "Gotchas".
- `tests/test-context.sh` — add `test_forgetful_connected_detection` after line 900.
- `tests/test-session-start-banner.sh` — add Forgetful banner-content assertions.

**Do NOT modify (intentionally):**
- `config/default-triggers.json` — `how_to_use_forgetful_tool` stays declared; it's now actually used per the new guidance.
- `hooks/consolidation-stop.sh` — gap #5 (type taxonomy) is deferred.
- Phase docs other than `historical-truth.md` — they delegate mechanics to the tier doc, so updating the tier doc cascades automatically.

---

## Task 1: Banner-content test for new Forgetful three-tool ordering (RED)

**Files:**
- Modify: `tests/test-session-start-banner.sh`

- [ ] **Step 1: Add failing assertions to existing banner test**

Append before the `teardown_test_env` call (around line 44):

```bash
# Forgetful banner content (gaps #1 + #2 fix)
assert_contains "Forgetful banner names how_to_use_forgetful_tool first" "how_to_use_forgetful_tool" "${SRC}"
assert_contains "Forgetful banner names discover_forgetful_tools" "discover_forgetful_tools" "${SRC}"
assert_contains "Forgetful banner names execute_forgetful_tool" "execute_forgetful_tool" "${SRC}"
# Ordering: how_to_use must appear before discover, which must appear before execute
HOW_LINE=$(grep -n 'how_to_use_forgetful_tool' "${HOOK_FILE}" | head -1 | cut -d: -f1)
DISCOVER_LINE=$(grep -n 'discover_forgetful_tools' "${HOOK_FILE}" | head -1 | cut -d: -f1)
EXECUTE_LINE=$(grep -n 'execute_forgetful_tool' "${HOOK_FILE}" | head -1 | cut -d: -f1)
if [ -n "${HOW_LINE}" ] && [ -n "${DISCOVER_LINE}" ] && [ -n "${EXECUTE_LINE}" ] && \
   [ "${HOW_LINE}" -lt "${DISCOVER_LINE}" ] && [ "${DISCOVER_LINE}" -lt "${EXECUTE_LINE}" ]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "PASS: Forgetful banner orders how_to_use → discover → execute"
else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TESTS_RUN=$((TESTS_RUN + 1))
    echo "FAIL: Forgetful banner ordering (how=${HOW_LINE} disc=${DISCOVER_LINE} exec=${EXECUTE_LINE})"
fi
assert_contains "Forgetful banner references DESIGN phase" "DESIGN" "${SRC}"
assert_contains "Forgetful banner references SHIP phase" "SHIP" "${SRC}"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-session-start-banner.sh`
Expected: FAIL with assertions about `how_to_use_forgetful_tool` not found, ordering check fails, and missing DESIGN/SHIP references in banner.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test-session-start-banner.sh
git commit -m "test: add failing assertions for Forgetful banner content"
```

---

## Task 2: Update banner copy (GREEN for Task 1)

**Files:**
- Modify: `hooks/session-start-hook.sh:1141-1145`

- [ ] **Step 1: Replace the banner emit block**

Current block at lines 1141-1145:

```bash
# Emit Forgetful usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.forgetful_memory == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Forgetful: Use discover_forgetful_tools to list available memory operations, then execute_forgetful_tool to query or store architectural knowledge across sessions."
fi
```

Replace with:

```bash
# Emit Forgetful usage hint when available
if printf '%s' "${CONTEXT_CAPS}" | jq -e '.forgetful_memory == true' >/dev/null 2>&1; then
    CONTEXT="${CONTEXT}
Forgetful: call mcp__forgetful__how_to_use_forgetful_tool once at session start to learn the API, then mcp__forgetful__discover_forgetful_tools for the operation list, then mcp__forgetful__execute_forgetful_tool for reads/writes. Query memory before DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW; store after SHIP. Forgetful = cross-session architectural memory; do not dual-write with Claude Code per-project auto-memory."
fi
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/test-session-start-banner.sh`
Expected: PASS — all new assertions including ordering check succeed.

- [ ] **Step 3: Run full test suite to verify no regression**

Run: `bash tests/run-tests.sh`
Expected: All existing tests pass.

- [ ] **Step 4: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: tighten Forgetful banner with how_to_use → discover → execute ordering"
```

---

## Task 3: Update tier doc mechanics

**Files:**
- Modify: `skills/unified-context-stack/tiers/historical-truth.md`

- [ ] **Step 1: Replace Tier 1 reading/writing sections**

Current lines 9-15:

```markdown
### Reading (all phases)
- Use `discover_forgetful_tools` to list available memory operations, then `execute_forgetful_tool` to query past architectural decisions
- Browse related context by executing the exploration tool discovered above

### Writing (Phase 5: Ship & Learn)
- Use `execute_forgetful_tool` to permanently store new architectural rules discovered during this session
```

Replace with:

```markdown
### Bootstrap (once per session, before first use)
- Call `mcp__forgetful__how_to_use_forgetful_tool` once to learn the API contract — the operations exposed by `execute_forgetful_tool`, their argument shapes, and dedup semantics
- Call `mcp__forgetful__discover_forgetful_tools` once to retrieve the concrete operation list available in this session

### Reading (DESIGN, PLAN, IMPLEMENT, DEBUG, REVIEW)
- Call `mcp__forgetful__execute_forgetful_tool` with a recall/query operation, keyed by current repo basename + active topic, to surface prior architectural decisions, known constraints, or workaround notes
- Use the returned context before proposing approaches (DESIGN), writing plans (PLAN), modifying code (IMPLEMENT), debugging (DEBUG), or reviewing diffs (REVIEW)

### Writing (Phase 5: Ship & Learn)
- Call `mcp__forgetful__execute_forgetful_tool` with a store/write operation to permanently persist new architectural rules, conventions, or workarounds discovered during this session
- Store only insights that are cross-session valuable — per-conversation context belongs in Claude Code auto-memory (see "Memory backend boundary" below), not here

### Memory backend boundary

Forgetful and Claude Code auto-memory are orthogonal, not redundant:

- **Forgetful** = cross-session architectural memory (opt-in MCP). Use for: rules that apply across many sessions, decisions with rationale, named constraints, workarounds tied to specific libraries/APIs.
- **Claude Code auto-memory** at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Use for: user preferences, feedback corrections, project-specific facts, reference pointers.

Do not dual-write. Pick one per learning based on scope: cross-project → Forgetful; project-local → auto-memory.
```

- [ ] **Step 2: Verify with grep**

Run: `grep -c "how_to_use_forgetful_tool\|discover_forgetful_tools\|execute_forgetful_tool\|Memory backend boundary" skills/unified-context-stack/tiers/historical-truth.md`
Expected: At least `4` (one of each tool name + the boundary heading).

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 4: Commit**

```bash
git add skills/unified-context-stack/tiers/historical-truth.md
git commit -m "docs: concrete Forgetful mechanics in historical-truth tier doc"
```

---

## Task 4: Connection-probe capability test (RED)

**Files:**
- Modify: `tests/test-context.sh`

- [ ] **Step 1: Add failing test for forgetful_connected detection**

Append after line 900 (after `test_mcp_fallback_detection`):

```bash
test_forgetful_connected_default_false() {
    echo "-- test: forgetful_connected defaults to false when probe disabled --"
    setup_test_env

    local proj_root
    proj_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
    python3 -c "
import json
d = {}
try:
    d = json.load(open('${HOME}/.claude.json'))
except: pass
d.setdefault('mcpServers', {})['forgetful'] = {'type':'stdio','command':'echo'}
json.dump(d, open('${HOME}/.claude.json', 'w'))
"

    # Run hook with connection probe OFF (default)
    CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" 2>/dev/null >/dev/null

    local cache="${HOME}/.claude/.skill-registry-cache.json"
    local fm fc
    fm="$(jq -r '.context_capabilities.forgetful_memory // false' "${cache}" 2>/dev/null)"
    fc="$(jq -r '.context_capabilities.forgetful_connected // false' "${cache}" 2>/dev/null)"

    assert_equals "forgetful_memory true via MCP config" "true" "${fm}"
    assert_equals "forgetful_connected false when probe disabled" "false" "${fc}"
    echo "   PASS"
}
test_forgetful_connected_default_false

test_forgetful_connected_in_canonical_keys() {
    echo "-- test: forgetful_connected appears in canonical capability keys --"
    local hook="${PROJECT_ROOT}/hooks/session-start-hook.sh"
    assert_contains "canonical keys include forgetful_connected" "forgetful_connected" "$(cat "${hook}")"
    echo "   PASS"
}
test_forgetful_connected_in_canonical_keys
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-context.sh`
Expected: FAIL — `forgetful_connected` key not in canonical keys, and `forgetful_connected` field missing from cache (jq returns `false` via `// false` default, but the `canonical keys include forgetful_connected` assertion fails on hook source).

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test-context.sh
git commit -m "test: add failing assertions for forgetful_connected capability"
```

---

## Task 5: Add `forgetful_connected` capability (GREEN for Task 4)

**Files:**
- Modify: `hooks/session-start-hook.sh:766` (canonical keys)
- Modify: `hooks/session-start-hook.sh:781` (initial jq object)
- Modify: `hooks/session-start-hook.sh:815` (insert probe block)

- [ ] **Step 1: Add `forgetful_connected` to canonical keys**

At line 766, current:

```bash
_CANONICAL_CAP_KEYS='["context7","context_hub_cli","context_hub_available","serena","serena_connected","forgetful_memory","openspec","posthog","lsp"]'
```

Replace with:

```bash
_CANONICAL_CAP_KEYS='["context7","context_hub_cli","context_hub_available","serena","serena_connected","forgetful_memory","forgetful_connected","openspec","posthog","lsp"]'
```

- [ ] **Step 2: Add `forgetful_connected:false` to the initial CONTEXT_CAPS object**

At line 781, current:

```bash
{context7:$c7, context_hub_cli:$chub, context_hub_available:$c7, serena:$ser, serena_connected:false, forgetful_memory:$fm, openspec:$openspec, posthog:$ph, lsp:$lsp}'
```

Replace with:

```bash
{context7:$c7, context_hub_cli:$chub, context_hub_available:$c7, serena:$ser, serena_connected:false, forgetful_memory:$fm, forgetful_connected:false, openspec:$openspec, posthog:$ph, lsp:$lsp}'
```

- [ ] **Step 3: Insert the forgetful_connected probe block after the serena_connected block**

After line 815 (after the existing `serena_connected` block ends, before the LSP note comment), insert:

```bash
# Refine `forgetful_connected` by parsing `claude mcp list` output for the
# "✓ Connected" marker on the forgetful entry. Gated on FORGETFUL_CONNECTION_CHECK=1
# (off by default — registration remains the routing gate). Fail-open: any
# error leaves forgetful_connected=false.
if [ "${FORGETFUL_CONNECTION_CHECK:-0}" = "1" ] && command -v claude >/dev/null 2>&1; then
    # Use grep -F for the literal Unicode ✓ to avoid locale-collation issues
    # under C/POSIX locale (where multi-byte regex matching may silently fail).
    if claude mcp list 2>/dev/null | grep '^forgetful: ' | grep -qF '✓ Connected'; then
        CONTEXT_CAPS="$(printf '%s' "${CONTEXT_CAPS}" | jq '.forgetful_connected = true' 2>/dev/null || printf '%s' "${CONTEXT_CAPS}")"
    fi
fi
```

- [ ] **Step 4: Run Task 4 test to verify it now passes**

Run: `bash tests/test-context.sh`
Expected: PASS — both `test_forgetful_connected_default_false` and `test_forgetful_connected_in_canonical_keys` succeed.

- [ ] **Step 5: Run full test suite for regression**

Run: `bash tests/run-tests.sh`
Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start-hook.sh
git commit -m "feat: add forgetful_connected capability probe parallel to serena_connected"
```

---

## Task 6: Document boundary in CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Add boundary note to Gotchas section**

Open `CLAUDE.md`. Find the Gotchas section. Append a new bullet at the end of the Gotchas list (just before the `## Spec Persistence Modes` heading):

```markdown
- Memory backends are orthogonal: Forgetful MCP = cross-session architectural memory (opt-in), Claude Code auto-memory at `~/.claude/projects/<project>/memory/` = per-project conversation memory (built-in, slug-indexed with typed frontmatter). Do not dual-write — pick one per learning based on whether it's cross-project (Forgetful) or project-local (auto-memory). See `skills/unified-context-stack/tiers/historical-truth.md` "Memory backend boundary".
```

- [ ] **Step 2: Verify the addition**

Run: `grep -c "Memory backends are orthogonal" CLAUDE.md`
Expected: `1`

- [ ] **Step 3: Run full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (no test depends on CLAUDE.md content).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: document Forgetful vs auto-memory boundary in CLAUDE.md"
```

---

## Task 7: Update CHANGELOG

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Append to [Unreleased] section**

Find the `## [Unreleased]` section in `CHANGELOG.md`. Append under it (or under existing subsections like `### Added`, `### Changed`):

```markdown
### Added
- `forgetful_connected` capability flag with gated `claude mcp list` probe (parallel to `serena_connected`). Off by default; set `FORGETFUL_CONNECTION_CHECK=1` to enable.

### Changed
- Forgetful banner now specifies `how_to_use_forgetful_tool` → `discover_forgetful_tools` → `execute_forgetful_tool` ordering with phase anchors (DESIGN/PLAN/IMPLEMENT/DEBUG/REVIEW for reads, SHIP for writes).
- `skills/unified-context-stack/tiers/historical-truth.md` now documents concrete tool mechanics and the Forgetful-vs-auto-memory boundary.

### Documentation
- Added "Memory backend boundary" section to `tiers/historical-truth.md` and Gotchas note in `CLAUDE.md` clarifying Forgetful (cross-session) vs Claude Code auto-memory (per-project) — no dual-write policy.
```

If sections like `### Added` already exist under `[Unreleased]`, merge into them rather than duplicating.

- [ ] **Step 2: Verify**

Run: `grep -n "forgetful_connected" CHANGELOG.md`
Expected: At least one match referencing the new capability.

- [ ] **Step 3: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog entries for Forgetful integration tightening"
```

---

## Task 8: Persist deferred items to memory with revival triggers

**Files:**
- Create: `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/project_forgetful_integration_tightening.md`
- Modify: `/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/MEMORY.md`

- [ ] **Step 1: Write the project memory file**

Write to `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/project_forgetful_integration_tightening.md`:

```markdown
---
name: forgetful-integration-tightening
description: Forgetful Memory MCP integration tightened in 3 changes (2026-05-19); deferred items have explicit revival triggers
metadata:
  type: project
---

Shipped 2026-05-19 (see [[gitnexus-decision]], [[cross-llm-context-decision]] pattern):
- Banner + tier doc specify `how_to_use_forgetful_tool` → `discover_forgetful_tools` → `execute_forgetful_tool` ordering with phase anchors
- `forgetful_connected` capability flag mirrors `serena_connected` (gated on `FORGETFUL_CONNECTION_CHECK=1`)
- Forgetful vs Claude Code auto-memory boundary documented in `tiers/historical-truth.md` + `CLAUDE.md` — orthogonal, no dual-write

**Why:** 4-perspective design debate (architect/critic/pragmatist + Codex) converged on smallest coherent ship. Codex caught the `serena_connected` vs Forgetful detection asymmetry that the 3 lenses missed.

**How to apply:**
- Proactive DESIGN-phase memory read — revive when a user reports "I had relevant memory but Claude didn't surface it during design" OR `forgetful_connected=true` accumulates ≥5 sessions with zero `execute_forgetful_tool` calls during DESIGN
- Consolidation type taxonomy — revive if a user pastes a Forgetful consolidation and asks "what shape?"
- Full nudge telemetry (Serena-style) — revive when proactive-read or taxonomy gap has a named requester
- Kill criterion: <5% of measurable installs report `forgetful_connected=true` after 30 days → remove Forgetful from default registry
```

- [ ] **Step 2: Update MEMORY.md index**

Open `~/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/MEMORY.md`. Under the `## Project` section, append:

```markdown
- [Forgetful integration tightening](project_forgetful_integration_tightening.md) — Shipped 2026-05-19: banner ordering, forgetful_connected probe, auto-memory boundary. Deferred items have revival triggers + <5%/30d kill criterion.
```

- [ ] **Step 3: Verify entries exist**

Run: `ls -la "/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/project_forgetful_integration_tightening.md"`
Expected: File exists, non-zero size.

Run: `grep -c "Forgetful integration tightening" "/Users/damian.papadopoulos/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory/MEMORY.md"`
Expected: `1`

- [ ] **Step 4: No commit needed** (memory directory is outside the repo)

---

## Task 9: Final verification + consolidation marker

**Files:**
- Touched (via helper): `~/.claude/.context-stack-consolidated-<hash>`

- [ ] **Step 1: Run full test suite once more**

Run: `bash tests/run-tests.sh`
Expected: All tests pass (zero failures).

- [ ] **Step 2: Verify all acceptance scenarios manually**

Run each check and confirm:

```bash
# Scenario 1: Banner ordering
grep -n 'how_to_use_forgetful_tool\|discover_forgetful_tools\|execute_forgetful_tool' hooks/session-start-hook.sh

# Scenario 2: forgetful_connected default false
grep -n 'forgetful_connected' hooks/session-start-hook.sh

# Scenario 3: Boundary documented
grep -l 'Memory backend\|Memory backends are orthogonal' skills/unified-context-stack/tiers/historical-truth.md CLAUDE.md

# Scenario 4: Test parity
grep -n 'forgetful_connected\|forgetful banner\|how_to_use_forgetful_tool' tests/test-context.sh tests/test-session-start-banner.sh
```

All four checks should produce non-empty output.

- [ ] **Step 3: Write the consolidation marker**

Run:

```bash
. "${CLAUDE_PLUGIN_ROOT:-$(pwd)}/hooks/lib/consol-marker.sh" && touch "$(consol_marker_path)"
```

- [ ] **Step 4: Verify the git history is clean and the working tree is clean**

Run: `git status && git log --oneline -10`
Expected: Clean working tree; 6 new commits on top of `d3c3a63` (one each for Tasks 1, 2, 3, 4, 5, 6, 7 — Task 8 has no commit since it's outside the repo).

- [ ] **Step 5: Print summary for handoff to code-review**

```bash
echo "Implementation complete. Commits:"
git log --oneline d3c3a63..HEAD
echo ""
echo "Modified files:"
git diff --name-only d3c3a63..HEAD
echo ""
echo "Next step: superpowers:requesting-code-review with diff range d3c3a63..HEAD and plan reference docs/plans/2026-05-19-forgetful-integration-tightening-plan.md"
```

---

## Self-Review Checklist (run after writing — done by author)

1. **Spec coverage:**
   - Gap #1 (vague calls) → Task 2 + Task 3 ✓
   - Gap #2 (`how_to_use` surfaced) → Task 2 + Task 3 ✓
   - Gap #3 (boundary documented) → Task 3 + Task 6 ✓
   - Codex catch (connection probe) → Tasks 4 + 5 ✓
   - Deferred items recorded → Task 8 ✓
   - CHANGELOG updated → Task 7 ✓
   - Tests for all changes → Tasks 1, 4 ✓
2. **No placeholders:** All code blocks contain actual content. No "TODO" or "similar to Task N" without showing the code.
3. **Type/name consistency:** `forgetful_connected` used consistently. Tool names `mcp__forgetful__how_to_use_forgetful_tool` etc. match the MCP surface visible in the deferred tools list.
4. **TDD order:** Tasks 1→2 (test before banner change), Tasks 4→5 (test before capability addition). Task 3 is doc-only so no failing-test pair needed. Task 6 is doc-only.
5. **Bash 3.2:** No associative arrays, no `mapfile`. All new shell code uses `[ ]` not `[[ ]]` for portability where needed.
6. **Fail-open:** New probe block at Task 5 Step 3 follows the existing serena_connected pattern — silent fallback on any error.
