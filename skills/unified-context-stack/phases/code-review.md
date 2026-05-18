# Phase 4: Code Review

When processing reviewer feedback, verify claims before accepting changes.

## Steps

### 0. Intent Truth (Requirement Verification)
IF reviewing changes to a specified capability:
- **IF `openspec/changes/<feature>/specs/` exists:** Read delta specs for the active change. These are the most current intent during development. Verify the implementation matches the specified scenarios.
- **ELSE IF `docs/plans/` has a matching design/plan/spec artifact:** Read it for current design intent
- **ELSE IF `openspec/specs/<capability>/spec.md` exists:** Read the canonical spec. Verify the implementation satisfies all acceptance scenarios. Flag any specified requirement that is missing from the implementation or tests.
- **ELSE IF `docs/superpowers/specs/` has a matching design spec (legacy):** Read it, but note it may be stale
- **IF no artifacts found:** Review based on code quality and internal consistency only.
- **IF the PR intentionally diverges from spec:** Note this as a spec update candidate — the spec should be revised to match the new intent after shipping.

### 1. External Truth (Claim Verification)
If a reviewer claims incorrect API usage:
- **context_hub_available=true**: Look up the specific parameter/method in Context Hub curated docs
- **context7=true** (no Hub match): Use broad Context7, verify against web-scraped docs
- **neither available**: Use WebSearch for official API reference
- If the reviewer is wrong, cite the documentation source in your response

### 2. Internal Truth (Dependency Safety)
If a reviewer suggests an architectural change or claims an error exists:
- **lsp=true** (reviewer claims type/compile error): Use `mcp__ide__getDiagnostics` to verify before responding — authoritative output either confirms the reviewer or refutes the claim
- **lsp=false and serena=true** (reviewer claims type/compile error): Use `mcp__serena__get_diagnostics_for_file` or `mcp__serena__get_diagnostics_for_symbol` (symbol-scoped, optional) — Serena v1.3.0+ — as the authoritative fallback before responding
- **serena=true** (complementary to the diagnostics bullets above — apply *in addition*, not instead): Use `find_referencing_symbols` to map all downstream dependencies before implementing; use `find_declaration` to verify the reviewer is referring to the same symbol you are
- **serena=false and lsp=false**: Use Grep to find all references, Read to verify each usage. Extra caution on complex hierarchies.
- Flag any files that would break silently from the proposed change

### 3. Historical Truth (Convention Check)
Before accepting architectural changes:
- **forgetful_memory=true**: Query Forgetful for prior architectural conventions or decisions related to the affected area
- **forgetful_memory=false**: Check CLAUDE.md for documented conventions
- If a reviewer's suggestion contradicts a documented convention, flag the conflict rather than silently applying the change
