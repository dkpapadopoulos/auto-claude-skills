# Tasks: Forgetful Integration Tightening

## Completed

- [x] 1.1 Add failing banner-content assertions for new three-tool ordering (`tests/test-session-start-banner.sh`)
- [x] 1.2 Update banner copy in `hooks/session-start-hook.sh` to specify `how_to_use_forgetful_tool` → `discover_forgetful_tools` → `execute_forgetful_tool` with phase anchors
- [x] 1.3 Rewrite Tier 1 sections in `skills/unified-context-stack/tiers/historical-truth.md` with concrete tool mechanics and add "Memory backend boundary" section
- [x] 2.1 Add failing `forgetful_connected` capability assertions (`tests/test-context.sh`)
- [x] 2.2 Add `forgetful_connected` to `_CANONICAL_CAP_KEYS` and initial `CONTEXT_CAPS` jq object in `hooks/session-start-hook.sh`
- [x] 2.3 Insert fail-open probe block parallel to `serena_connected` (gated on `FORGETFUL_CONNECTION_CHECK=1`)
- [x] 2.4 Add `forgetful_connected: false` to `config/fallback-registry.json` defaults
- [x] 3.1 Add Forgetful-vs-auto-memory boundary note to `CLAUDE.md` Gotchas
- [x] 4.1 Update `CHANGELOG.md` `[Unreleased]` Added/Changed sections
- [x] 4.2 Persist project memory entry with deferred-item revival triggers + <5%/30-day kill criterion
- [x] 4.3 Tighten banner phase-anchor assertions per code-review feedback (one-line precision fix)
