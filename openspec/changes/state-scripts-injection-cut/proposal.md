# Proposal: Extract the Session-State Incantation into Scripts; Cut Dead Injection

## Why

The session-token resolution incantation — ~150 words the model must retype to write openspec-state — is distributed as prose across 7+ surfaces (both trigger configs, both main hooks, and three SKILL.md bodies), kept in sync only by `tests/test-openspec-state-token-symmetry.sh`. Correctness depends on the model re-deriving the resolution logic correctly every time, in every surface. This is the root cause of the repo's longest-running bug class (writer/reader token symmetry: #51, #97, #122, #131, #133, #151, #156, #157): two skills (`runtime-validation`, `implementation-drift-check`) even hand-rolled the *wrong* copy (the forbidden singleton read) and wrote marker files nothing reads.

The precedent already exists in this repo: `project-verification/SKILL.md` calls `scripts/verify-and-record.sh`, which resolves the token internally and hands the model nothing to retype. Applying the same shape to the openspec-state writes converts an unenforceable instruction into a structural guarantee and removes ~2×150 words from the per-prompt DESIGN injection.

Every installer benefits: the prompt tax and the bug class are in the shipped plugin, not just this repo.

## What Changes

1. **(done)** Delete the two dead session-marker writes (`runtime-validation`, `implementation-drift-check`) — zero readers, wrong-token incantation, false "checked by the SHIP phase gate" claim.
2. Add `scripts/persist-state.sh` — a single dispatcher (`set-intent`, `upsert-change`, `set-discovery-path`, …) that resolves the token internally (`SKILL_SESSION_TOKEN` → `resolve_own_session_token` → singleton fallback, exactly as `verify-and-record.sh`) and calls the matching `openspec_state_*` function.
3. Replace the retyped incantation at every writer surface (both configs, both hooks' injected directives, the three SKILL.md bodies) with a call to that script.
4. Replace `test-openspec-state-token-symmetry.sh` with EQUAL-STRENGTH coverage: unit tests on `persist-state.sh` (token resolution, each op) + a call-site test that every surface invokes the script and none re-derives the incantation.
5. Trim the INTENT EXTRACTION injection: keep the outcome contract (verbatim confirmed-intent block, human-confirmed, persisted, read back at PLAN) and the persist call; cut the method-prescription prose ("one question at a time", "track your confidence").

## Capabilities

- **Modified**: `pdlc-safety` — how DESIGN/PLAN intent is persisted (script-owned token resolution) and how the DESIGN→PLAN completeness breadcrumb is produced.

## Impact

- New `scripts/persist-state.sh`; edits to `config/default-triggers.json`, `config/fallback-registry.json`, `hooks/skill-activation-hook.sh`, `hooks/session-start-hook.sh`, `skills/{openspec-ship,agent-team-review,product-discovery}/SKILL.md`; `skills/{runtime-validation,implementation-drift-check}/SKILL.md` (markers, done). Test: retire `test-openspec-state-token-symmetry.sh`, add `test-persist-state.sh` + a call-site assertion.
- No change to `openspec-state.sh` lib semantics or the reader (PLAN design guard). Behavior-preserving for the state that gets written; the change is WHERE the resolution logic lives.
