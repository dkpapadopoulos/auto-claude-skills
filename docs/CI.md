# CI & Branch Protection

This repo ships a GitHub Actions workflow that validates every active OpenSpec
change on every pull request. The workflow alone produces a **check**;
promoting it to a **hard block** requires a one-time GitHub Settings change.

## OpenSpec Validate workflow

**File:** `.github/workflows/openspec-validate.yml`
**Job name:** `openspec-validate`
**Check name (used for branch protection):** `OpenSpec Validate`

**What it does:**

1. Runs on every `pull_request` (opened, synchronize, reopened, ready_for_review).
2. Installs the OpenSpec CLI at a pinned version (`@fission-ai/openspec@1.3.0`).
3. Runs `scripts/validate-active-openspec-changes.sh`, which:
   - Discovers all top-level directories under `openspec/changes/`, excluding `archive/`.
   - Runs `openspec validate <slug>` on each.
   - Aggregates failures across every active change (does not fail-fast).
   - Exits `1` if any validation fails, `0` if all pass or there are no active changes.

**Failure modes:**

- `openspec` CLI missing → loud failure (not silent skip).
- Any active change invalid → workflow red.
- No `openspec/changes/` directory → exits 0, no-op (default-mode repos).
- Only `openspec/changes/archive/` exists → exits 0, no-op.

## Done Gates workflow

`.github/workflows/done-gates.yml` runs the repo's two **owned done-gates** on
every PR and on pushes to `main`:

- `tests/test-fixture-coverage.sh` — every owned, trigger-routed skill has a
  routing fixture with a MATCH line and a verbatim-borrowed NO_MATCH decoy.
- `tests/test-skill-content-coverage.sh` — every such skill is referenced by some
  `tests/*.sh` content assertion.

**Why it exists.** These gates were previously described as "CI-blocking via
`.verify.yml`" in both `CLAUDE.md` and `docs/enforcement-map.md`. That was false:
`.verify.yml` is `substrate: local` and no workflow reads it. Enforcement lived
only in the local push gate, which cannot see a merge performed through the GitHub
web UI, has documented human bypasses, and whose routing-governance leg is scoped
to `skills/|config/|hooks/` — so a `tests/`-only PR weakening a coverage gate
evaded it entirely. `tests/test-done-gate-ci.sh` pins this workflow so the claim
cannot rot again.

**Scope note.** Only those two gates run here. The full `tests/run-tests.sh` suite
(116 files, 10+ minutes, with known shared-state and stdin-hang traps) is
deliberately **not** wired into CI: making a slow or flaky check Required invites
admin-override habits, which weakens the gate rather than strengthening it.

To make it hard-blocking, follow the steps below and type **`Done Gates`** in the
status-check search box (step 6). It is independent of `OpenSpec Validate` — you
can require either, both, or neither.

## Making the gate a required check (hard block)

Applies to **both** workflows — `OpenSpec Validate` and `Done Gates`. Each produces
a check that **must be manually required** in branch protection rules for it to
actually block merges. Without this step, PRs can merge even when the check is red.

In step 6 below, add the check you want: `OpenSpec Validate`, `Done Gates`, or both.

1. Go to **Settings → Branches** in the GitHub repo.
2. Under **Branch protection rules**, click **Add rule** (or edit the existing rule for `main`).
3. **Branch name pattern:** `main`.
4. Check **Require status checks to pass before merging**.
5. Check **Require branches to be up to date before merging** (recommended).
6. In the status-check search box, type `OpenSpec Validate` and select it.
7. Click **Create** (or **Save changes**).

After this one-time setup, any PR with an invalid active OpenSpec change is
blocked from merging until the spec is fixed.

## Emergency: turning off the gate

If a false positive blocks legitimate work:

- **Short-term:** In Branch Protection, temporarily uncheck `OpenSpec Validate` from the required checks list. Fix and re-enable.
- **Medium-term:** Fix the script at `scripts/validate-active-openspec-changes.sh` and re-enable.
- **Never:** Do not use `git push --no-verify` or admin-override as a habit; those bypass the signal the gate is designed to surface.

## Pinning the OpenSpec CLI version

The workflow pins `@fission-ai/openspec@1.3.0`. To upgrade:

1. Open a PR that updates the version string in `.github/workflows/openspec-validate.yml`.
2. Verify the workflow still passes on the PR itself.
3. Merge.

Do not use `@latest` in CI: a breaking OpenSpec release would silently break
every subsequent PR until someone noticed.

## Local validation

Run the same checks locally before pushing:

```bash
bash scripts/validate-active-openspec-changes.sh
```

Exits 0 (green) or 1 (red) with aggregated output per change.

## Per-capability review routing (CODEOWNERS)

Once your repo has a stable capability taxonomy under `openspec/specs/`, layer
in GitHub's CODEOWNERS mechanism so each capability's spec auto-routes review
requests to its owner.

The plugin ships a template at `.github/CODEOWNERS.template`. To use it:

1. Copy the template into your own repo as `.github/CODEOWNERS`:
   ```bash
   cp .github/CODEOWNERS.template .github/CODEOWNERS
   ```
2. Replace every `@your-*-team` placeholder with real GitHub teams or users.
3. Commit and push.
4. GitHub will auto-request reviews from the matching owner(s) on every PR
   that touches a capability's spec or an in-flight change folder.

**Why it pairs with the OpenSpec Validate gate:** the gate enforces *spec
validity*; CODEOWNERS enforces *spec-author review*. Together they make
capability contracts genuinely multi-user: an auth-team change can't land
without auth-team approval AND without a valid spec.

**Common patterns in the template:**
- `openspec/specs/<capability>/` → capability owner team
- `openspec/changes/` → platform/architecture team reviews all in-flight specs
- `config/`, `hooks/`, `.github/workflows/` → platform team (workflow-affecting changes)

**Do not copy this repo's CODEOWNERS.template verbatim.** The `@your-*-team`
handles are placeholders; GitHub will ignore non-existent teams, which
silently breaks the review-routing guarantee.

## Relationship to `spec-driven` preset

The `spec-driven` preset (see CLAUDE.md "Spec Persistence Modes") is designed
to be paired with this gate. Repos that set `{"preset": "spec-driven"}`
commit `openspec/changes/<feature>/` upfront during DESIGN phase; the gate
then enforces that every committed change is valid before merging.

Default-mode repos (no preset) typically have zero active changes except
during a ship window, so the gate is a cheap no-op for them.
