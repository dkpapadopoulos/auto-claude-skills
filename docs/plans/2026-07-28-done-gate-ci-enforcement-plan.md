# Done-gate CI enforcement — plan

**Goal:** Make the repo's claim that its two owned done-gates are CI-blocking true, at the narrowest scope that achieves it, and stop the claim from silently rotting again.

**Why now:** Two independent docs assert CI enforcement that does not exist, and the local
substitute has a hole.

- `CLAUDE.md:31` — "Both are CI-blocking via `.verify.yml`."
- `docs/enforcement-map.md:49-50` — the *anti-folklore* doc — "`tests/run-tests.sh` via
  `.verify.yml` … (both CI-blocking)."
- Measured: no `.github/workflows/*.yml` reads `.verify.yml`, and none invokes
  `tests/run-tests.sh`. `.verify.yml` is `substrate: local`, consumed only by
  `hooks/lib/verdict.sh`, the `project-verification` skill, and tests.
- Local enforcement has a hole: routing-governance is scoped to `skills/|config/|hooks/`
  (`hooks/openspec-guard.sh:639`); `tests/` is absent. A PR that weakens
  `test-fixture-coverage.sh` itself, or deletes a routing fixture without touching
  `skills/`, never triggers the clean-verdict requirement.
- The push gate cannot see a merge performed through the GitHub web UI. PR #178 was
  merged exactly that way, so this is an observed path, not a hypothetical one.

**Scope decision (narrow, deliberately):** wire ONLY the two gates the docs actually claim —
`tests/test-fixture-coverage.sh` and `tests/test-skill-content-coverage.sh`. Both are pure
content-grep tests: no `~/.claude` state, no subprocess hooks, seconds to run, near-zero
flake surface. The full 116-file suite is NOT wired in here — it is 10+ minutes and carries
known shared-state and stdin-hang traps, and making a slow/flaky check *required* invites
admin-override habits. Follow the repo's existing two-step pattern (`openspec-validate.yml`):
land the workflow visible-but-not-required, promote to Required in branch protection by hand.

## Tasks

- [ ] **1. Red: pin the claim to reality.** Add `tests/test-done-gate-ci.sh` asserting a
  workflow exists that runs BOTH coverage-gate scripts and triggers on `pull_request`.
  Run it, confirm it FAILS (no such workflow).
- [ ] **2. Green: add `.github/workflows/done-gates.yml`.** Runs the two scripts on
  `pull_request` + `push` to main. Must use `< /dev/null` on every test invocation (the
  documented stdin-hang trap). Add a comment warning against adding a
  `git diff --exit-code` cleanliness step: `tests/test-registry.sh` mutates a git-tracked
  file at runtime, which is harmless in an ephemeral checkout but would break such a check.
- [ ] **3. Correct both docs** to describe the actual state: the two gates run in CI via
  `done-gates.yml`; the FULL suite is local-only via `.verify.yml` and the push gate.
  `docs/enforcement-map.md` must stop claiming `run-tests.sh` runs in CI.
- [ ] **4. Record the local hole** in `docs/enforcement-map.md`: routing-governance does not
  cover `tests/`-only diffs — that is precisely what the CI check now backstops.
- [ ] **5. Verify:** new test green; both coverage gates pass locally; `bash -n` on changed
  shell; openspec validate clean.

## Out of scope

- Wiring the full suite into CI (separate decision, needs a burn-in period).
- Marking the check Required in branch protection — a repo-settings action for the maintainer.
- Widening routing-governance to include `tests/` — a gate-behaviour change needing its own
  false-block analysis.
