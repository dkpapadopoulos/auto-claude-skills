# Design: Pre-PR Stack Improvements

## Architecture

Three independent additions to existing files. No new modules, no new dependencies.

**Iteration cap (skill-activation-hook).** When `_score_skills` evaluates a matched trigger, it now consults composition state (`~/.claude/.skill-composition-state-<token>`) and counts prior occurrences of the same skill name in `.completed`. If the registry sets `max_iterations: N` on the skill and the count is ≥ N, the skill is skipped (no entry appended to RESULTS, `[max-iter] skipping <skill> (<count> of <cap>)` emitted to stderr under `SKILL_EXPLAIN=1`). The cap check is gated behind two conditions: (1) skill `role` is `domain` or `required` — process and workflow roles bypass the check entirely; (2) `_SESSION_TOKEN` is non-empty — sessionless invocations (tests, dry runs) never cap.

**Passive telemetry (skill-completion-hook).** After the existing state-mutation block succeeds, the hook now appends one JSONL line to `~/.claude/.advisory-lens-log.jsonl`. The line carries `ts` (UTC ISO-8601), `skill` (the bare skill name already computed at line 35), `finding_count_estimate` (line count of `tool_response.content` or `tool_response.output`, a coarse proxy), and `session_token_hashed` (sha256 of the session token, first 12 hex chars — matches the pattern shipped in PR #36). Write failures are routed through `2>/dev/null || true`, with `trap 'exit 0' ERR` already in place as a second guard.

**Fallback-registry drift gate (tests/test-registry.sh).** New test regenerates the fallback JSON from `default-triggers.json` using a copy of the same jq pipeline session-start uses (`hooks/session-start-hook.sh:986-1001`) and diffs against the committed `config/fallback-registry.json`. Failure prints a head-50 diff and an instruction to regenerate. Skips fail-open if jq is missing.

## Dependencies

None added. The change uses only Bash 3.2 + jq (both already required), and the `shasum`/`sha256sum` binaries present on macOS/Linux respectively.

## Decisions & Trade-offs

**Role-allowlist as hardcoded invariant, not config-driven.** A config-driven allowlist could be silently widened by a misguided overrides file. The hardcoded check in `_score_skills` is the boundary — config changes cannot bypass it. The CLAUDE.md gotcha makes the invariant discoverable, and `test_max_iterations_role_allowlist` locks it.

**Passive telemetry without labels.** The labeled variant (accepted/rejected/false-positive/caught-only-here) requires counterfactual knowledge a solo dev cannot honestly produce ("would another lens have caught this?"). The critic in the design debate stuck on this attack. The passive shape — fired-once, line-count-estimate — is the minimum substrate that still answers "is this lens dead?" without requiring discipline that will erode.

**`finding_count_estimate` is line-based, not structural.** Reviewer skills produce free-form output; parsing for structured findings would require per-skill knowledge. Raw line count distinguishes "no output" (0-5 lines) from "many findings" (50+ lines) — coarse but useful for the dead-lens question.

**Hashed session token, not raw.** Privacy hygiene; matches the precedent set in PR #36 (`project_serena_pnp_and_measurement`).

**Cap target is `agent-team-review` only in v1.** `code-reviewer`, `silent-failure-hunter`, `adversarial-reviewer` are subagents spawned via the Task tool, not skills in the registry — they cannot be capped via this mechanism. Subagent-loop capping is out of scope for v1.

## Rejected Alternatives

- **C5 (diff-anchored CHANGELOG claim check):** killed 2-1 in design debate on n=1 incident + false-positive desensitization risk. Revival trigger: ≥2 overclaim incidents in 90 days.
- **C6 (pre-commit scope-sanity gate):** withdrawn by the critic who proposed it after duplication confirmed with `design-plan-guard` + `writing-plans` + `implementation-drift-check`.
- **Trim security specialist:** parked. No auth surface in this repo (Bash hooks + JSON registries). Revival trigger: if plugin ingests user-supplied repos or runs untrusted prompts.
- **PR-comment scraping for fatigue corpus:** over-engineered for solo workflow; the mechanical cap is the whole value.
- **Global iteration cap flag:** per-trigger only, so each lens's cap is visible at the trigger site.
