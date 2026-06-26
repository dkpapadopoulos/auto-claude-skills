# External Truth — API Documentation Retrieval

Capability: Fetch accurate, up-to-date API documentation for third-party libraries.

## Tier 1 (High Trust): Context Hub via Context7

**Condition:** `context_hub_available = true`

**Note:** This flag indicates Context Hub is reachable via Context7, not that it has docs for your specific library. If `resolve-library-id` returns no match, fall through to Tier 2 immediately.

Use the Context7 MCP tools with the curated Context Hub repository:

1. Call `resolve-library-id` to confirm the library exists in Context Hub
2. Call `get-library-docs` with `libraryId="/andrewyng/context-hub"`

**Query guidance:** Your `query` parameter should describe the specific API you need (e.g., "Stripe payment intents API", "React Router v7 route configuration"). Do NOT query for "Context Hub" — the `libraryId` handles targeting; the `query` handles specificity.

**Trust level:** Curated, human-reviewed. Trust fully.

## Tier 2 (Medium Trust): Broad Context7

**Condition:** `context7 = true` AND Tier 1 returned no results

Use Context7 MCP with a broad query — no library constraint. Let `resolve-library-id` find the best match.

**Trust level:** Web-scraped. Verify method signatures and parameter names before implementing.

## Tier 3 (Low Trust): chub CLI

**Condition:** `context_hub_cli = true` AND Tiers 1+2 unavailable or empty

Execute in terminal:
```
chub search "<library>" --json
chub get <id> --lang <lang>
```

**Trust level:** Curated but requires shell access. Verify version matches project.

## Tier 4 (Base): Web Search

**Condition:** None of the above are available

Use WebSearch / WebFetch to find official documentation.

**Trust level:** High skepticism. Cross-reference multiple sources. Verify all API signatures.

## Consuming Retrieved Docs

Retrieval is half the job; how you *use* what came back is the other half. The tier
you pulled from sets how much you trust it — carry that trust level into the work.

- **CITE what you used.** When a doc shaped a decision or an API call, name the
  source and tier (e.g. "per Context Hub `/andrewyng/context-hub`" or "per
  web-scraped Context7"). A reviewer must be able to trace a claim back to where it
  came from; an uncited API signature is unverifiable.
- **Mark UNVERIFIED facts.** Anything not from the curated, human-reviewed Tier 1
  (Tier 2 web-scraped, Tier 3 chub until its version is checked, Tier 4 web search)
  is UNVERIFIED until you confirm it against the actual installed library — method
  signatures, parameter names, version. Label it `UNVERIFIED` in notes and code
  comments until checked. Do not let a web-scraped signature harden into an assumed
  fact.
- **Plan inline before acting on docs.** Once you have the docs, write the two or
  three steps you'll take *before* editing — which call, which params, what you
  expect back. This catches a misread doc before it becomes a wrong implementation.
- **Treat confusion as a signal, not noise.** If retrieved docs contradict each
  other, contradict the code, or contradict what you expected — stop. Confusion
  means the retrieval is wrong, the version is wrong, or your mental model is wrong.
  Resolve which before proceeding; do not paper over it by picking the convenient
  source.
