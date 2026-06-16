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
  "failed": ["types"],
  "command": "ruff check . && pyright && uv run pytest -m \"not slow\"",
  "output_excerpt": "pyright: 2 errors in core/engine.py …",
  "ts": "<UTC ISO-8601>"
}
```

`passed`/`failed` are the command *names*. Then print a short human summary table (name, command, PASS/FAIL, excerpt) so the result is visible in-session. This evidence is advisory; `deploy-gate` may read it as local verification of record when hosted CI is absent.

## Output

A `## Project Verification Results` table plus the written evidence file path. If no gate was discovered, say so plainly and ask the user to add `.verify.yml`.
