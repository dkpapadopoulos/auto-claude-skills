# Phase 2: Implementation

During file-by-file plan execution, use context as needed.

## Steps

### 0. Historical Truth (Workaround Check)
Before implementing each file, check for known patterns:
- **forgetful_memory=true**: Query Forgetful for known workarounds, gotchas, or implementation patterns related to the current file or module
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for relevant notes
- If a known workaround exists, apply it directly rather than rediscovering it

### 1. Internal Truth (Primary)
For each file modification, verify current symbol locations:
- **serena=true**: Use `find_symbol` / `find_declaration` / `find_referencing_symbols` for dependency mapping (prefer `find_declaration` for exact-name lookups), `insert_after_symbol` for safe AST edits
- **serena=false**: Use Grep to find references, Read to verify context. Extra caution on large files (>500 lines) and symbol renames — grep may miss dynamic references. Always verify changes compile after editing.

### 2. External Truth (On-Demand)
If you encounter a library or API not covered in the original plan:
- **context_hub_available=true**: Query Context Hub via Context7 first for curated docs
- **context7=true** (no Hub match): Use broad Context7, verify method signatures before implementing
- **neither available**: Use WebSearch, treat with high skepticism
- Do not guess API signatures — look them up

### 3. Intent Truth (On-Demand)
IF you encounter a design ambiguity not covered in the plan:
- **IF `openspec/specs/<capability>/spec.md` or `openspec/changes/<feature>/` exists:** Check for the specific edge case or requirement. Do NOT re-read the full spec — query only for the specific ambiguity.
- **IF no artifacts found:** Rely on the plan from Phase 1, or ask the user.
