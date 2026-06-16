---
name: deploy-gate
description: Use when preparing to ship or release — before pushing to production, promoting a build, or finalizing a branch — to confirm CI is green, no WIP commits remain, and version and design artifacts are in order
role: domain
phase: SHIP
priority: 19
triggers:
  - "(deploy|release|promote|launch|go.live|readiness|pre.?deploy|ship.*prod)"
precedes:
  - openspec-ship
requires:
  - verification-before-completion
---

# Deploy Gate v0.1

A thin checklist-runner that verifies deployment readiness before shipping. This skill checks preconditions — it does NOT execute deployments, manage rollbacks, or monitor rollouts.

## When This Activates

- Part of the SHIP phase composition chain
- Runs after `verification-before-completion` confirms code correctness
- Runs before `openspec-ship` generates documentation
- Can also be triggered explicitly: "check deployment readiness", "run deploy gate"

## Checklist

Run each check. Report pass/fail with evidence. Do not block on warnings — report them and let the human decide.

### Required Checks (must pass)

1. **CI Status** (fail-closed: absent ≠ green)
   ```bash
   _concl="$(gh pr checks --fail-fast >/dev/null 2>&1 && echo PASS \
             || gh run list --limit 1 --json conclusion -q '.[0].conclusion')"
   if [ -z "$_concl" ]; then
     echo "GATE FAIL: no CI checks reported — absent ≠ green. Treating as FAIL."
   else
     echo "CI conclusion: $_concl"
   fi
   ```
   Gate: distinguish three states — **green** (`$_concl` = PASS/success), **red** (any failure conclusion), **absent-or-broken** (empty `$_concl`, or a run that concluded with zero completed steps). Absent-or-broken is a **FAIL**, never a pass. Do not read an empty `statusCheckRollup` as "nothing blocking → ship". If `gh pr checks` itself reports failing checks, that is **red** regardless of what `gh run list` returns — do not let a stale prior run's `success` conclusion mask currently-red PR checks.

   **Local verification of record:** when hosted CI is absent, you MAY accept a fresh `~/.claude/.skill-project-verified-<token>` evidence file with an empty `failed` list as verification performed on substrate `local` — but still surface that hosted CI was absent rather than claiming hosted-CI green. This evidence is advisory provenance, not a non-bypassable gate.

2. **No WIP Commits**
   ```bash
   git log --oneline origin/main..HEAD | grep -iE '(wip|fixup|squash|todo|hack|tmp)'
   ```
   Gate: No WIP-pattern commits on the branch.

3. **Version/Changelog Updated** (if applicable)
   Check if `CHANGELOG.md`, `package.json`, or version file was modified in this branch.
   Gate: Soft — warn if no version change detected.

4. **Design Intent Exists** (if DESIGN phase was executed)
   Check session state for `design_path`. If set, verify the file exists at `docs/plans/`.
   Gate: Soft — warn if design_path is set but file is missing.

### Advisory Checks (warn only)

5. **Branch Protection**
   ```bash
   gh api repos/{owner}/{repo}/branches/main/protection 2>/dev/null | jq '.required_status_checks'
   ```
   Report whether branch protection is configured.

6. **Dependent Services Notified**
   Prompt: "Does this change affect any downstream services or consumers? If yes, have they been notified?"
   This is a human checkpoint, not an automated check.

7. **Feature Flags**
   Prompt: "Is this change behind a feature flag? If yes, confirm the flag default is OFF."

## Project-Local Override

If `.deploy-checklist.yml` exists in the repo root, read it and use its checklist instead of the defaults above. Format:

```yaml
required:
  - name: CI green
    command: gh pr checks --fail-fast
    gate: exit_code_zero
  - name: No WIP commits
    command: git log --oneline origin/main..HEAD | grep -iE '(wip|fixup|squash)'
    gate: exit_code_nonzero  # grep returns 1 when no match = good
advisory:
  - name: Migration reviewed
    prompt: "Have database migrations been reviewed by the DBA?"
```

## Output

Report as a structured checklist:

```markdown
## Deploy Gate Results

| # | Check | Status | Evidence |
|---|-------|--------|----------|
| 1 | CI Status | PASS | Last run: success (run 12345) |
| 2 | No WIP commits | PASS | 0 WIP-pattern commits found |
| 3 | Version updated | WARN | No version change detected |
| 4 | Design intent | PASS | docs/plans/2026-04-15-feature-design.md exists |
| 5 | Branch protection | INFO | Required status checks: [ci/build] |
| 6 | Dependent services | HUMAN | User confirmed: no downstream impact |
| 7 | Feature flags | SKIP | No feature flags in this change |

**Result: PASS** (2 warnings, 0 failures)
```

If any required check FAILS, report the failure clearly and stop. Do not proceed to openspec-ship.
