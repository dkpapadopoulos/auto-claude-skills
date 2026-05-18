# Tasks: Serena v1.3.0 Alignment

## Completed

- [x] 1.1 Drop subagent-propagation line from session-start banner; add v1.3.0 tool names (commit `97739e2`)
- [x] 1.2 Invert `test-session-start-banner.sh` assertions to lock the new contract (commit `97739e2`)
- [x] 2.1 Add `find_declaration` / `find_implementations` to tier doc and 4 phase docs per asymmetric placement (commit `6d695dd`)
- [x] 3.1 Restructure Tier 0 into 3-tier strict fallback; add diagnostics fallback in testing-and-debug + code-review (commit `6644c46`)
- [x] 4.1 Expose `serena-hooks auto-approve` as opt-in in `commands/setup.md` (commit `4b93aa8`)
- [x] 5.1 Add "Troubleshooting Serena" subsection to `commands/setup.md` (system-prompt override + `MCP_TIMEOUT`) (commit `1c3c6ac`)
- [x] 6.1 Remove stale `base_modes:` block from `.serena/project.yml`; add note pointing to `added_modes` (commit `4debb7b`)
- [x] 7.1 Create `tests/test-serena-v1-3-0-skill-references.sh` regression test (14 assertions) (commit `64d3d72`)
- [x] 8.1 Bump version `3.32.2` → `3.33.0`; add CHANGELOG entries under existing `[Unreleased]` (commits `64fce34`/`c7886f1`)
- [x] R1 Tighten CHANGELOG `find_implementations` coverage claim; add `get_diagnostics_for_symbol` optionality caveat (Codex review, commit `e35461d`)
- [x] R2 Spell out `mcp__serena__get_diagnostics_for_symbol` (drop `_for_symbol` shorthand) in testing-and-debug.md (bot review iteration 1, commit `f5face8`)
- [x] R3 Add symbol-scoped diagnostics variant to code-review.md (bot review iteration 2, commit `188f320`)
- [x] R4 Add "complementary to diagnostics bullets above" note in code-review.md to disambiguate guard-chain bullets (bot review iteration 3, commit `7171a6c`)
- [x] R5 Merge PR #34 (squash, branch deleted, merge commit `b000844` on main)
