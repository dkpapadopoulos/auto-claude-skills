# Internal Truth — Blast-Radius Mapping & Safe Edits

Capability: Understand local file dependencies, inject code safely, and surface compiler/type errors authoritatively.

## Tier 0: Diagnostics

Strict fallback order:

**0a — `lsp = true`:** Use `mcp__ide__getDiagnostics` for compile errors, type errors, and linter warnings. Authoritative for compiler truth.

**0b — `lsp = false` and `serena = true`:** Use `mcp__serena__get_diagnostics_for_file` (file-scoped) or `mcp__serena__get_diagnostics_for_symbol` (symbol-scoped, optional tool — availability depends on Serena's `included_optional_tools` config) — Serena v1.3.0+. These run against Serena's bundled language server, less integrated than the IDE's own LSP but still authoritative for the languages Serena supports.

**0c — neither available:** Skip Tier 0 — there is no authoritative diagnostics source. Drop to Tier 1 (Serena symbol nav) or Tier 2 (grep) and verify by running the build/test commands.

In all cases, prefer Tier 0 over grepping for error strings when the question is "what is broken".

## Tier 1: Serena Symbol Navigation

**Condition:** `serena = true`

- **Skeleton first.** Use `get_symbols_overview` to read a file's symbol skeleton (top-level classes, methods, signatures) *without* pulling full implementation bodies. Do this before `Read`-ing a whole file: locate the right symbol from the outline, then read only the one body you need. Reading entire files inflates the context window and pushes the worker toward the "dumb zone" — pass the skeleton, fetch the body on demand.
- Use `find_symbol` to locate symbols by name (broad, name-match-based)
- Use `find_declaration` (Serena v1.3.0+) for the precise *definition* of a symbol — preferred over `find_symbol` when you know the symbol exists and want its declaration site
- Use `find_implementations` (Serena v1.3.0+) to enumerate concrete implementations of an interface or abstract method
- Use `find_referencing_symbols` to map which files depend on a symbol (blast-radius)
- Use `insert_after_symbol` / `replace_symbol_body` / `rename_symbol` for safe AST-level edits without breaking formatting

## Tier 2: Standard Tools (Fallback)

**Condition:** `serena = false` and `lsp = false`, or for non-code content (logs, YAML values, config strings, free text)

- Use `Grep` to find references across the codebase
- Use `Read` to examine file contents
- Use `Edit` for modifications

**WARNING:** Without Serena's AST awareness, proceed with extra caution on:
- Large files (>500 lines) — higher risk of formatting/indentation errors
- Complex class hierarchies — manual dependency tracing may miss references
- Refactors that rename symbols — grep may miss dynamic references

Always verify changes compile/pass after editing without Serena.

## When to use which

| Question | Preferred tier |
|---|---|
| "What's in this file / where's the right symbol?" | Tier 1 (Serena `get_symbols_overview`) — skeleton first, read the body on demand |
| "What type/compile errors exist?" | Tier 0 (LSP) — authoritative |
| "Where is this function defined?" | Tier 1 (Serena `find_declaration`, falls back to `find_symbol`) — else Tier 2 Grep |
| "Who implements this interface?" | Tier 1 (Serena `find_implementations`) — else Tier 2 Grep with extra caution |
| "Who calls this function?" | Tier 1 (Serena `find_referencing_symbols`) |
| "Rename X to Y across the codebase" | Tier 1 (Serena `rename_symbol`) |
| "Find this log message / YAML key / config string" | Tier 2 (Grep) — not a symbol |
| "Read this specific file" | Tier 2 (Read) — direct access |

LSP and Serena are complementary, not alternatives. When both are present, use LSP for diagnostics and Serena for navigation and edits.
