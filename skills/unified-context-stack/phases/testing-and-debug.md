# Phase 3: Testing & Debug

When tests fail or errors occur, use context to resolve efficiently.

## Steps

### 1. Historical Truth (First Check)
Before investigating from scratch:
- **forgetful_memory=true**: Query Forgetful for this exact error message or pattern (see `tiers/historical-truth.md` for tool mechanics)
- **forgetful_memory=false**: Check CLAUDE.md and docs/learnings.md for known environmental quirks
- Check if this is a known workaround with a documented fix

### 2. External Truth (Library Issues)
If the error involves a third-party library:
- **context_hub_available=true**: Check Context Hub via Context7 for known issues or breaking changes
- **context7=true** (no Hub match): Use broad Context7 for library-specific error documentation
- **neither available**: Use WebSearch for the specific error message in the library's docs
- For API errors (4xx/5xx), check for known outages or recently discovered bugs

### 3. Internal Truth (Dependency Tracing)
If the error involves internal code or unclear call chains:
- **lsp=true** (compile/type errors): Use `mcp__ide__getDiagnostics` FIRST — authoritative compiler output beats grepping for error substrings
- **lsp=false and serena=true** (compile/type errors): Use `mcp__serena__get_diagnostics_for_file` or `_for_symbol` — Serena v1.3.0+ — as a fallback authoritative source
- **serena=true** (call-chain tracing): Use `find_declaration` to locate the failing function, `find_referencing_symbols` to trace callers and dependencies, `find_implementations` if the failure crosses an interface
- **serena=false and lsp=false**: Use Grep to search for the function name and trace references manually

### 4. Observability Truth (Production State)
If the error may be production/staging related:
- **Tier 1** (MCP observability tools available): Use `list_log_entries` with scoped LQL filter (service + severity + time window <= 60 min)
- **Tier 2** (gcloud available): Use temp-file pattern for LQL queries via `gcloud logging read --format=json`
- **Tier 3** (neither): Guide developer to Cloud Console Logs Explorer
- ALWAYS scope: service + environment + narrow time window
- NEVER dump unbounded log results into context
