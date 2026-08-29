# Design: State Scripts + Injection Cut

## Architecture

### `scripts/persist-state.sh` (new)

A thin dispatcher mirroring `verify-and-record.sh`'s posture (Bash 3.2, plugin-root from env-or-`$0`, token resolved internally, nothing for the model to author):

```
persist-state.sh <op> [args...]
  set-intent "<confirmed intent> :: out-of-scope: <...>"
  upsert-change "<slug>" "<title>" "<why>" "<capability-slug>" "<status>"
  set-discovery-path "<path>"
  set-hypotheses "<json-or-text>"
```

- Sources `hooks/lib/session-token.sh` and resolves the token via
  `SKILL_SESSION_TOKEN` → `resolve_own_session_token` → singleton fallback —
  the SAME order `verify-and-record.sh` uses, single-sourced so no surface
  re-derives it. Degrades (non-zero, message) when the lib or jq is absent.
- Sources `hooks/lib/openspec-state.sh` and calls the matching
  `openspec_state_*` function with the resolved token as the first argument.
- Unknown op → non-zero + usage. Never partial-writes.

### Call-site conversion

Each of the 7 incantation surfaces replaces the inline
`PR=…; TOKEN="$(… resolve_own_session_token || cat …)"; . openspec-state.sh; openspec_state_X "$TOKEN" …`
with `bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}/scripts/persist-state.sh" <op> <args>`.
The model authors only the op arguments (intent text, slug) — never token logic.

### Test replacement

`test-openspec-state-token-symmetry.sh` pinned that all copies were identical.
With one copy (the script), that test is obsolete. It is REPLACED, never bare-deleted (this is the repo's #1 recurring bug class), by:
- `test-persist-state.sh` — unit tests: token resolves payload-first; `SKILL_SESSION_TOKEN` override honored; singleton fallback when lib absent; each op writes the same state the old incantation did (assert via `openspec_state_read`); unknown op errors; no-jq degrades.
- a call-site assertion (extend the existing content-coverage style): every writer surface calls `persist-state.sh` and NO surface still contains `resolve_own_session_token || cat` (the incantation is gone, not merely duplicated).

## Trade-offs

- A script call replaces an inline block, so a surface that previously worked with the lib present but the script somehow absent would degrade — but the script ships with the plugin (same root as the libs it already sources), so its absence is the same failure class as a missing lib.
- The INTENT EXTRACTION method cut is a behavioral-injection change; it is guarded by keeping the outcome contract (the convergence block + persist call) verbatim and only removing the "how to converge" prose.

## Dissenting views

- Bundling all of item 4 risks a large diff. Mitigation: land it in safe increments — dead markers (done), then the script + call sites, then the INTENT cut — each independently green.

## Decisions

- One dispatcher script, not one script per op (fewer files; the op is an argument).
- Token resolution is single-sourced in the script; surfaces never re-derive it. This is the whole point — the fix is structural, not another synced copy.
- `test-openspec-state-token-symmetry.sh` is replaced with stronger coverage, never bare-deleted.
