# Push-Gate Verdict Split (Phase B)

## Why

The push gate treats **"the skill returned"** as **"the milestone passed."** `hooks/skill-completion-hook.sh` records a per-(repo+branch) milestone via `branch-ledger.sh` whenever `requesting-code-review` or `verification-before-completion` returns without `is_error`, and `hooks/openspec-guard.sh` opens the `git push` gate on that milestone (ledger OR composition `.completed`). So a review that surfaced blocking findings, or a verification whose tests actually **failed**, still returns non-error → milestone recorded → gate opens with no evidence the work passed. This is the OpenTrajectory/TrueCall gap: `done ≠ passed`.

The fix must **not** re-introduce the push-gate false-blocks that PR #81 (branch-ledger) eliminated — genuinely reviewed+verified work must never be denied.

## What Changes

Split **status** (skill returned) from **verdict** (it passed), gating push/SHIP on owned verdict evidence for the gating milestones — without ever denying on absent/stale/cross-branch evidence.

- **Keep** `.completed` and the branch-ledger as the STATUS layer, unchanged (preserves the PR #81 false-block fix).
- **Add a SHA-freshness field** (`sha` = HEAD at verify time) to the owned verdict artifact `~/.claude/.skill-project-verified-<token>` written by `project-verification`. This is the lynchpin: a verdict is honored only when its SHA covers the pushed HEAD, closing cross-branch bleed and stale-FAIL false-blocks.
- **Verify-verdict hardening (fail-open):** the push gate reads the verdict artifact live at push time; if it covers HEAD **and is not clean** (`failed[]` non-empty, or `could_not_verify[]` non-empty, or `gate_gaming_status != clean`) → DENY with the specific failing gate, even if the status ledger says completed. Absent/SHA-mismatch → today's status behavior (no new denial).
- **Routing-governance gate (fail-closed, scoped):** when the pushed diff touches routing paths (`skills/`, `config/`, `hooks/`) **in a skill-routing plugin repo** (detected by the presence of `config/default-triggers.json`), REQUIRE a clean verdict covering the branch; absent/unrelated-SHA → DENY with the exact `project-verification` remedy; stale-but-clean ancestor → advisory warning (allow). This gate fires independent of an active composition chain, because routing changes are high-risk by nature, not by phase.
- **Review milestone stays status-only.** We own no deterministic "review passed" signal; parsing the external skill's return text is gameable and phrasing-variance would cause false-blocks. The gap is documented with a revival trigger.

Verdict is read **live at push time** (no new ledger) — `project-verification` runs parallel to the chain, so snapshotting at Skill-return time would race an artifact that may not exist yet.

## Capabilities

### Modified: `skill-routing`
- Push-gate readiness now distinguishes status (milestone reached) from verdict (milestone passed) for `verification-before-completion`.
- New routing-governance push gate scoped to skill-routing plugin repos.
- Verdict artifact gains a HEAD `sha` field for freshness/coverage checks.

## Impact

- **Files:** `skills/project-verification/SKILL.md` (artifact `sha` field), `hooks/lib/verdict.sh` (new, fail-open), `hooks/openspec-guard.sh` (gate logic), `tests/test-push-gate-verdict.sh` (new), `CLAUDE.md` gotcha, `CHANGELOG.md`.
- **Governance:** strictly strengthens gates — no HITL/approval/guardrail weakened, no autonomous scope expanded, no bypass patterns added. Introduces no lethal-trifecta leg.
- **Backward compatibility:** verdict artifacts written by older `project-verification` (no `sha`) are treated as SHA-mismatch → fall back to status behavior → no false-block.
- **Deterministic** change → TDD + regression fixtures; full suite runs in CI via `.verify.yml`.
