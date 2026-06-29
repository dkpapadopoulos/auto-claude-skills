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

## Step 2: Run locally

Run each discovered command in the working tree. Capture each command's exit code and the last ~4 KB of combined stdout/stderr (replace newlines with the two-character sequence \n so the excerpt is valid inside JSON; truncate to ~4 KB). Substrate is the literal `local` in this version; a `.verify.yml` declaring any other `substrate` value is an ERROR — report it, do not silently run locally.

After running the gates, capture the diff under verification and classify gate-gaming deterministically:

```bash
GGC="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/skills/project-verification/scripts/gate-gaming-check.sh"
# BASE: upstream merge-base → main merge-base → HEAD~1. The HEAD~1 last resort (no upstream and
# no detectable main fork point) scopes the check to the most recent commit only, so it may miss
# earlier changes on a long-lived branch — widen BASE manually if reviewing more than the last commit.
BASE="$(git merge-base HEAD @{u} 2>/dev/null || git merge-base HEAD main 2>/dev/null || echo HEAD~1)"
GG="$(git diff "$BASE"...HEAD -- '*test*' '*spec*' 2>/dev/null | bash "$GGC" 2>/dev/null)"
```

`GG` is `clean`, or `suspect` followed by the offending diff lines. A `suspect` result means the gate may be passing because the test was weakened (deleted assertions, added skip/xfail/disabled markers), not because the code is correct. If `GG` is **empty** (the script was not found, or the pipe failed), the gate-gaming check **could not run** — treat that as *unverified*: record `gate_gaming_status: "unverified"` (NOT `clean`, and never omit the field) AND add `"gate-gaming-check"` to `could_not_verify`, so `deploy-gate` rejects the evidence rather than accepting an unchecked diff. Surface that the check did not run.

## Step 3: Emit evidence

Write `~/.claude/.skill-project-verified-<token>` (resolve `<token>` from `~/.claude/.skill-session-token`, same namespace as `runtime-validation`'s marker):

```bash
TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)"
# write the JSON below to ~/.claude/.skill-project-verified-${TOKEN}
```

```json
{
  "substrate": "local",
  "discovery_source": "claude-md-commands",
  "passed": ["lint", "tests"],
  "failed": [],
  "could_not_verify": ["types"],
  "gate_gaming_status": "clean",
  "command": "ruff check . && pyright && uv run pytest -m \"not slow\"",
  "output_excerpt": "pyright: command not found …",
  "ts": "<UTC ISO-8601>"
}
```

`passed`/`failed` are the command *names*. A command that could not execute (missing tool, runner error — distinct from a test failure) goes in `could_not_verify`, never silently omitted. `gate_gaming_status` is one of `clean` | `suspect` | `unverified` (the check could not run); if `suspect`, the verdict is SUSPECT, not PASS; if `unverified`, the gate-gaming check is also added to `could_not_verify`. The field is always written — `deploy-gate` accepts local evidence only when it is exactly `clean`. Then print a short human summary table (name, command, PASS/FAIL, excerpt) so the result is visible in-session. This evidence is advisory; `deploy-gate` may read it as local verification of record when hosted CI is absent.

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
