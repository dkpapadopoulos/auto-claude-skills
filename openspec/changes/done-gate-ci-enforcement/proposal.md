# Proposal: give the owned done-gates a real CI backstop

## Why

Two independent documents asserted a CI enforcement that did not exist.

- `CLAUDE.md` — "Both are CI-blocking via `.verify.yml`."
- `docs/enforcement-map.md` — the document whose stated purpose is *anti-folklore*,
  "everything that can BLOCK an action" — "`tests/run-tests.sh` via `.verify.yml` …
  (both CI-blocking)."

Measured: `.verify.yml` declares `substrate: local`. It is read by
`hooks/lib/verdict.sh`, the `project-verification` skill, and tests. **No file under
`.github/workflows/` reads it, and none invokes `tests/run-tests.sh`.** The two owned
done-gates were enforced only by the local PreToolUse push gate.

That matters for three reasons, not one:

1. **The push gate cannot see a web-UI merge.** It is a local hook, so a merge performed
   through the GitHub button is outside it by construction. PR #178 was merged exactly
   that way — an observed path, not a hypothetical.
2. **It has documented human bypasses** (`!` prefix, `ACSM_SKIP_PUSH_GATE=1`). CI has none.
3. **A `tests/`-only PR evades the strongest local leg.** routing-governance is scoped to
   `skills/|config/|hooks/` (`hooks/openspec-guard.sh:639`). A PR that weakens
   `test-fixture-coverage.sh` itself, or deletes a routing fixture without touching
   `skills/`, never triggers the clean-verdict requirement. That is precisely the
   self-tampering shape the repo already worries about via its EVALUATOR SURFACE advisory.

The repo's own doctrine (`skills/project-verification/SKILL.md`) says the local verdict is
"advisory audit data, **not a trust boundary**" and that "hard enforcement keys on external
CI". Correcting only the wording would leave a gate the repo calls **enforceable** — and
explicitly contrasts against layers it calls "not merge preconditions" — with no
merge-blocking enforcement at all. Honest, but hollow.

## What changes

1. **Add `.github/workflows/done-gates.yml`** running the two owned done-gates
   (`tests/test-fixture-coverage.sh`, `tests/test-skill-content-coverage.sh`) on every PR
   and on pushes to main.
2. **Correct both documents** to describe the actual state.
3. **Add `tests/test-done-gate-ci.sh`**, which pins the workflow's existence and contents
   so the claim cannot silently rot again — the same discipline as the phantom-citation
   fix shipped under #169.

## Scope is deliberately narrow

Only the two gates the documents actually claimed. Both are pure content-grep tests — no
`~/.claude` state, no subprocess hooks, no network — so they are fast and near-flake-free.

The **full suite is deliberately not wired in**: 116 files, 10+ minutes, with known
shared-state traps and a documented stdin-hang. Making a slow or flaky check Required
invites admin-override habits, which would weaken the gate rather than strengthen it. That
is a separate decision needing its own burn-in.

Follows the repo's existing two-step pattern (`openspec-validate.yml`): land the workflow
visible-but-not-required; promoting it to Required in branch protection is a manual
maintainer step documented in `docs/CI.md`.

## Out of scope

- Wiring `tests/run-tests.sh` into CI.
- Flipping branch protection (a repo-settings action, not a code change).
- Widening routing-governance to cover `tests/` — a gate-behaviour change that needs its
  own false-block analysis.

## Impact

- Capability: `pdlc-safety`
- Adds `.github/workflows/done-gates.yml`, `tests/test-done-gate-ci.sh`
- Corrects `CLAUDE.md`, `docs/enforcement-map.md`
