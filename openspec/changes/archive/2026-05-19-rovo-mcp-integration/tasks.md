# Tasks: Atlassian Rovo MCP Integration

## Completed

- [x] 1.1 Update `skills/product-discovery/SKILL.md` Tier 1 to lead with Rovo cross-system `search(cloudId, query)`, then deep-read top hits, then JQL/CQL refinement (commit `757d71b`)
- [x] 1.2 Update `skills/outcome-review/SKILL.md` Step 6 to use `search` for original-ticket lookup with `searchJiraIssuesUsingJql` fallback (commit `3f981f9`)
- [x] 1.3 Update `config/fallback-registry.json` and `config/default-triggers.json` hint copy on `atlassian-jira` and `atlassian-confluence` triggers (commit `0cf3bc8`)
- [x] 1.4 Add `search` to `atlassian` capability `mcp_tools` and rewrite `description` in `config/fallback-registry.json` (commit `ba88ee5`)
- [x] 1.5 Align `tests/test-routing.sh` inline `atlassian-jira` fixture hint with new canonical copy (commit `4692804`)
- [x] 1.6 Add new "Atlassian Rovo MCP" walkthrough section to `commands/setup.md` with detection, three-case branching, and copy-paste defaults block; renumber subsequent steps and update Execution footer (commit `fd53046`)
- [x] 1.7 Terminology refresh in `README.md` (with `(formerly Atlassian MCP)` continuity hint), `hooks/session-start-hook.sh` (MCP-plugins comment block), and `hooks/skill-activation-hook.sh` (DISCOVER + LEARN RED_FLAGS strings) (commit `fc680b3`)
- [x] 1.8 Fix backtick command-substitution trap in DISCOVER RED_FLAGS — switched literal backticks around `search` to single quotes to prevent runtime `search: command not found` and word-stripping (commit `d1f68a8`)
- [x] 1.9 Mirror `atlassian` capability update into `config/default-triggers.json` to keep `config/fallback-registry.json` stable under session-start hook regeneration (commit `cc3a0c7`)
- [x] 1.10 Append `[Unreleased]` entry to `CHANGELOG.md` under `### Changed` (commit `9f893b2`)
- [x] 1.11 Full test suite green (46/46 files passing)
- [x] 1.12 Final whole-implementation code review by `pr-review-toolkit:code-reviewer` (APPROVED post-rebase onto current main)
