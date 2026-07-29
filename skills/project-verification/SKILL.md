---
name: project-verification
description: Use when you need to run the repo's own declared test/lint/type gate locally and emit pass/fail evidence — during REVIEW, before requesting code review, or on a request to run the tests or verify the build — discovering the gate from CLAUDE.md, Makefile, pyproject, or .verify.yml
role: domain
phase: REVIEW
priority: 16
triggers:
  - "(run.*(the )?tests?|run.*(lint|typecheck|type.?check)|project.*(gate|checks?)|verify.*(locally|the build)|does.*(it )?build|declared.*(gate|commands?))"
---

# Project Verification

Discover the repository's own declared test/lint/type gate, run it **locally**, and emit structured evidence. This is the project-native counterpart to `runtime-validation` (which covers browser/API/CLI E2E). Use during REVIEW, before requesting code review, or on explicit request ("run the tests", "verify the build", "run the gate").

## Scope

- This skill RUNS the gate and REPORTS structured evidence. It does NOT enforce — the evidence is advisory audit data, **not a trust boundary** (a session-written file is forgeable and may race across concurrent sessions). Hard enforcement keys on external CI (`deploy-gate`).
- Discovery and execution happen ONLY here (a model-invoked skill). No hook discovers gates or runs the suite.

## Step 1: Discover the gate (deterministic-first)

Walk the ladder in `references/discovery-ladder.md` top-down, first-match-wins. Prefer the deterministic rungs (`.verify.yml`, manifest-standard targets, a clearly-labelled "run all tests" row) before any prose reasoning. On a genuine tie in the CLAUDE.md `## Commands` table (0 or ≥2 surviving candidates), STOP, show the candidates, ask which command(s) are the gate, and offer to write `.verify.yml` so the next run is deterministic. Record which rung produced the gate as `discovery_source`.

## Preferred path: deterministic writer (when `.verify.yml` exists)

When Step 1 landed on `.verify.yml` (`substrate: local`), do NOT perform
Steps 2–3 by hand. Run:

```bash
bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}/scripts/verify-and-record.sh"
```

It runs the declared commands (stdin nulled), runs the gate-gaming check, and
writes the evidence file from its OWN measured exit codes — the model never
authors the verdict JSON. This is measured provenance (and avoids the
auto-mode classifier's self-approval denial on model-authored verdict
writes); it is NOT a trust boundary — the artifact stays forgeable and
external CI remains the enforcement layer, unchanged. Exit 0 means a verdict
was RECORDED (a failing verdict is still exit 0 — read the printed summary,
never treat exit 0 as "gates passed"; non-zero means it could not measure or
write). Then print the human summary table from its output and continue at
the Verification checklist — the human should still eyeball that summary
before any downstream push relies on it. If there is no `.verify.yml`, offer
to write one (per Step 1) — the manual Steps 2–3 below remain the fallback
and may require per-instance user approval for the evidence write.

## Step 2: Run locally (fallback — no `.verify.yml`)

**BEFORE the first gate command**, record the commit under test (issue #181) — a suite can run for many minutes, and reading HEAD afterwards silently binds the verdict to any commit made meanwhile, i.e. to a tree no gate ever ran against:

```bash
git rev-parse HEAD 2>/dev/null || echo unknown                     # pre-gate sha — the commit actually measured
git status --porcelain --untracked-files=no 2>/dev/null | head -1  # non-empty => worktree_dirty: true
```

Read both values out of this output when writing the verdict in Step 3 — Bash tool calls do NOT share shell state, so a variable set here is gone by then.

Run each discovered command in the working tree. Capture each command's exit code and the last ~4 KB of combined stdout/stderr (replace newlines with the two-character sequence \n so the excerpt is valid inside JSON; truncate to ~4 KB). Substrate is the literal `local` in this version; a `.verify.yml` declaring any other `substrate` value is an ERROR — report it, do not silently run locally.

After running the gates, capture the diff under verification and classify gate-gaming deterministically:

```bash
GGC="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/skills/project-verification/scripts/gate-gaming-check.sh"
# BASE: upstream merge-base → main merge-base → HEAD~1. The HEAD~1 last resort (no upstream and
# no detectable main fork point) scopes the check to the most recent commit only, so it may miss
# earlier changes on a long-lived branch — widen BASE manually if reviewing more than the last commit.
BASE="$(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)"
GG="$(git -c diff.mnemonicPrefix=false -c diff.noprefix=false diff "$BASE"...HEAD -- '*test*' '*spec*' '.verify.yml' 2>/dev/null | bash "$GGC" 2>/dev/null)"
```

`GG` is `clean`, or `suspect` followed by the offending diff lines. A `suspect` result means the gate may be passing because the test was weakened (deleted assertions, added skip/xfail/disabled markers), not because the code is correct. If `GG` is **empty** (the script was not found, or the pipe failed), the gate-gaming check **could not run** — treat that as *unverified*: record `gate_gaming_status: "unverified"` (NOT `clean`, and never omit the field) AND add `"gate-gaming-check"` to `could_not_verify`, so `deploy-gate` rejects the evidence rather than accepting an unchecked diff. Surface that the check did not run.

**Limits — calibrate trust, `clean` is not proof.** `gate-gaming-check.sh` is a coarse line-diff tripwire for the *blatant, common* forms only. Measured on a labeled corpus + two blind held-out sets, a line-grep detector lands around F1 0.44–0.70 on diverse real diffs — it is an advisory signal, not a guarantee. It **cannot see** structural gaming that line-diffs don't reveal: stubbing the subject-under-test to return the expected constant, early-return / `if False` guards before the assertions, block-comment- or docstring-muted assertions, and uncommon per-language skip dialects (e.g. NUnit `[Ignore]`, RSpec `xit '...'`). It can also **false-alarm** on benign moves, variable renames, and reorders. So: a `clean` result MUST NOT be read as "no gaming"; a human reviewer still owns assertion integrity. (Attempts to close these gaps with more regex did not generalize across blind held-out sets — the robust fix is a different primitive: per-change coverage-delta or an LLM-judge over the test diff. Tracked as future work, not shipped here.)

## Step 3: Emit evidence

Write `~/.claude/.skill-project-verified-<token>` (same namespace as `runtime-validation`'s marker). Resolve `<token>` **own-session-first** — `~/.claude/.skill-session-token` is a shared last-writer-wins singleton, so under concurrent sessions it names a *different* conversation and the verdict lands where the push gate will never look (issue #156):

```bash
TOKEN="${SKILL_SESSION_TOKEN:-}"                       # explicit override wins (#122)
# resolve_own_session_token derives this conversation's own token from
# CLAUDE_CODE_SESSION_ID (which IS the transcript basename the gate derives
# its token from), trusting it only when that transcript exists — stale,
# foreign, injected, and path-unsafe ids fall through to the singleton. Do NOT
# re-derive `session-<id>` by hand here: session-token.sh owns that format.
STL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/hooks/lib/session-token.sh"
if [ -z "$TOKEN" ] && [ -f "$STL" ]; then
    . "$STL" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token)"
fi
[ -n "$TOKEN" ] || TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)"
git rev-parse HEAD 2>/dev/null || echo unknown   # post-gate sha — compare with the pre-gate one from Step 2
# write the JSON below to ~/.claude/.skill-project-verified-${TOKEN}, using the
# PRE-gate sha from Step 2 as "sha" (NOT this one)
```

Print the resolved `${TOKEN}` alongside the artifact path — a scattered write is then visible in-session instead of surfacing later as an unexplained push deny.

```json
{
  "substrate": "local",
  "discovery_source": "claude-md-commands",
  "passed": ["lint", "tests"],
  "failed": [],
  "could_not_verify": ["types"],
  "gate_gaming_status": "clean",
  "worktree_dirty": false,
  "sha": "<PRE-gate sha from Step 2 — the commit the gate actually ran against>",
  "command": "ruff check . && pyright && uv run pytest -m \"not slow\"",
  "output_excerpt": "pyright: command not found …",
  "ts": "<UTC ISO-8601>"
}
```

The example above is a **field-shape illustration**, not an accepted-evidence sample: because its `could_not_verify` is non-empty (the `types` gate could not run), `deploy-gate` correctly does **not** accept it as local verification of record. A fully-accepted evidence file has `failed` and `could_not_verify` both empty and `gate_gaming_status: "clean"`.

`sha` records the HEAD the gate actually **ran against** — the pre-gate value captured in Step 2, never a post-run `git rev-parse HEAD`; the push gate honors a verdict only when this `sha` covers the pushed HEAD (equal, or an ancestor on the branch), so a stale or cross-branch verdict is ignored rather than causing a false block.

**Limit:** if a repo's declared gate itself commits (auto-format-and-commit, a release check that runs `npm version`), every run straddles by construction and the verdict is permanently unclean — honest, since such a gate never measures one tree, but it means `deploy-gate` and routing-governance will not accept local evidence there. Split the committing step out of the declared gate.

If the pre- and post-gate shas **differ**, a commit landed while the gate ran: the verdict covers no single commit, so keep the pre-gate `sha` AND add `"gate-run-straddled-commit"` to `could_not_verify` (issue #181). Never pick the post-gate sha — it names a tree nothing was measured against, and the gate's ancestor acceptance would treat it as covered. Also record `"worktree_dirty": true|false` from Step 2; it is advisory only (verifying uncommitted work and committing after is a supported workflow) and must NOT be added to `could_not_verify`.

`passed`/`failed` are the command *names*. A command that could not execute (missing tool, runner error — distinct from a test failure) goes in `could_not_verify`, never silently omitted. `gate_gaming_status` is one of `clean` | `suspect` | `unverified` (the check could not run); if `suspect`, the verdict is SUSPECT, not PASS; if `unverified`, the gate-gaming check is also added to `could_not_verify`. The field is always written — `deploy-gate` accepts local evidence only when it is exactly `clean`. Then print a short human summary table (name, command, PASS/FAIL, excerpt) so the result is visible in-session. This evidence is advisory; `deploy-gate` may read it as local verification of record when hosted CI is absent.

**`coverage_adequacy_status`** — a second deterministic tripwire
(`scripts/coverage-adequacy-check.sh`) complements gate-gaming: gate-gaming catches
tests getting *weaker*; adequacy catches *new code shipping untested*. Pipe the review
diff on stdin with `COVERAGE_ADEQUACY_LCOV` pointing at the runner's coverage artifact
(`lcov.info` or `coverage.xml`); it prints `clean` | `suspect` (+ uncovered `path:line`) |
`unverified`. Empty output or no artifact = `unverified` (fail-open — never blocks).
Evidence is accepted-as-adequate only when the status is **exactly clean**; `suspect` and
`unverified` are surfaced, not swallowed.

Limits: coverage is not effectiveness — a line can be executed by a test that asserts
nothing, so `clean` here means "exercised," not "meaningfully tested." Only two artifact
formats are parsed (lcov, cobertura); everything else degrades to `unverified`. Phase 1
checks changed-line coverage only — coverage regression against the base ref (did overall
coverage drop even though the new lines are covered) is a disclosed Phase-2 deferral, not
implemented here. This is an advisory tripwire, not a trust boundary; it is however
CONSUMED by `deploy-gate` (parity with `gate_gaming_status`) — a `suspect` result there
blocks acceptance of local verification evidence, so it is not advisory-prose-only.

## Verification

Before emitting a PASS verdict, confirm -- do not infer:

- The gate command(s) actually ran this session via a Bash tool call -- not assumed from a prior run or read from config.
- Each command's exit code was captured; PASS is keyed to exit 0, FAIL to non-zero.
- The evidence file was written to `~/.claude/.skill-project-verified-${TOKEN}` and the in-session summary table is shown.
- If no gate was discovered, the verdict is "no gate found" -- never a silent PASS.
- A command that errored to run is in `could_not_verify` (verdict `could-not-verify`), not absent and not in `passed`. Absence MUST NOT read as pass.
- `gate-gaming-check.sh` was run over the diff; a `suspect` result downgrades the verdict to SUSPECT (reported, with offending lines shown) and is never emitted as PASS. This is advisory — it does not hard-block. An **empty** result (script not found or pipe failed) means the check could not run — report it as *unverified*, never assume `clean`.

## Output

A `## Project Verification Results` table plus the written evidence file path. If no gate was discovered, say so plainly and ask the user to add `.verify.yml`.
