# Plan: adopt-doubt-discipline

Spec: openspec/changes/adopt-doubt-discipline/ (proposal, design, 2 delta specs — validated)

## Tasks

- [x] 1. TDD red: add 4 content assertions to tests/test-adversarial-governance.sh (claim-withheld dispatch, doubt-theater, cross-model offer, sensitive-path override); create tests/test-skill-scaffold-content.sh with description-rule assertions. Run — all new assertions must FAIL. (8+2 failed as expected)
- [x] 2. TDD green: edit skills/agent-team-review/SKILL.md — rule block in §2 Spawn Reviewers; Red Flags section (doubt theater); cross-model offer in §5 Verdict Routing; sensitive-path row in Sizing Rule. (commit 9e687e0)
- [x] 3. TDD green: edit skills/skill-scaffold/SKILL.md — description authoring rule in Step 2 + Step 3. (commit 9e687e0)
- [x] 4. Run new tests (green) + full suite (54 files, no regressions).
- [x] 5. REVIEW: requesting-code-review — verdict "with fixes"; both Important findings (stale 5-file statements, missing routing-entry test pin) + Minor §6 scoping applied in commit 1a61498. Full suite re-run 54/54.
  - Cross-model offer (per new §6 rule): Codex dispatch attempted, FAILED on provider session limit (resets 12:10pm). Recorded, not silently skipped. Mitigation: external repo facts ground-truthed directly via gh api during triage; design.md project-history claims verified by Claude reviewer.
- [ ] 6. SHIP: verification-before-completion → openspec-ship (sync existing change, CHANGELOG [Unreleased]) → finishing-a-development-branch.
