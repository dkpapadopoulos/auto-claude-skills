# Pre-PR Stack Improvements Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close two documented pain points (`fallback-registry.json` drift + advisory-lens iteration asymptote) and add a passive telemetry substrate so future trim decisions are evidence-based.

**Architecture:** Three small, independent additions to existing hooks/tests/config — no new files, no new dependencies. A test-only diff gate in `tests/test-registry.sh`; a per-trigger `max_iterations` field plus an activation-hook counter guarded by a role-allowlist; one-line JSONL append in the completion hook.

**Tech Stack:** Bash 3.2 + jq + existing session-state JSON files (`~/.claude/.skill-composition-state-<token>`).

**Design doc:** `docs/plans/2026-05-21-pre-pr-stack-improvements-design.md`

---

## File Structure

| File | Change | Why |
|------|--------|-----|
| `tests/test-registry.sh` | Append one test function | C4 trigger-sync gate |
| `tests/test-routing.sh` | Append one test function | C2 role-allowlist regression guard |
| `config/default-triggers.json` | Add `max_iterations: 1` to `agent-team-review` block | C2 cap target |
| `config/fallback-registry.json` | Regenerate to match | C2 sync (also exercises C4) |
| `hooks/skill-activation-hook.sh` | Insert iteration-cap check inside `_score_skills` | C2 enforcement |
| `hooks/skill-completion-hook.sh` | Append one telemetry write block | C1 passive logging |
| `CLAUDE.md` | Add one Gotcha entry on role-allowlist invariant | C2 documentation |

Single feature branch: `feature/pre-pr-stack-improvements`. Single PR.

---

## Task 1: C4 — Trigger-sync gate

**Files:**
- Modify: `tests/test-registry.sh` (append a test function before the final test-runner block)

The new test regenerates `fallback-registry.json` from `default-triggers.json` using the same jq pipeline session-start uses (lines 986-1001), diffs against the committed file, and fails on non-empty diff. Skips if jq is missing.

- [ ] **Step 1.1: Write the failing test**

Locate the end of the existing test functions in `tests/test-registry.sh` (search for the last `test_*` function definition, then before the test-runner invocation block). Append:

```bash
# ---------------------------------------------------------------------------
# Fallback registry must remain in sync with default-triggers.json
# Closes drift class documented in memory: feedback_default_triggers_source_of_truth
# ---------------------------------------------------------------------------
test_fallback_registry_in_sync_with_default_triggers() {
    echo "-- test: fallback-registry.json matches regenerated content from default-triggers.json --"

    # Skip if jq missing (matches existing fail-open idiom)
    if ! command -v jq >/dev/null 2>&1; then
        echo "  SKIP: jq not available"
        return 0
    fi

    local triggers_file="${PROJECT_ROOT}/config/default-triggers.json"
    local fallback_file="${PROJECT_ROOT}/config/fallback-registry.json"

    if [ ! -f "$triggers_file" ] || [ ! -f "$fallback_file" ]; then
        echo "  SKIP: required config files missing"
        return 0
    fi

    # Canonical context_capabilities key set (must match session-start-hook.sh _CANONICAL_CAP_KEYS).
    # If keys change there, update here in lockstep.
    local cap_keys='["context7","context_hub_cli","context_hub_available","serena","serena_connected","forgetful","forgetful_connected","openspec","posthog","lsp"]'

    local default_json
    default_json="$(cat "$triggers_file")"

    local regenerated
    regenerated="$(printf '%s' "$default_json" | jq \
        --argjson cap_keys "$cap_keys" \
        '. as $d |
        {
            version: ($d.version // "4.0.0-fallback"),
            frontmatter_schema_version: 1,
            skills: [($d.skills // [])[] | . + {available: false, enabled: (.enabled // true)}],
            plugins: [($d.plugins // [])[] | . + {available: false}],
            context_capabilities: ($cap_keys | map({(.): false}) | add),
            openspec_capabilities: {binary: false, commands: [], surface: "none", warnings: []},
            phase_compositions: ($d.phase_compositions // {}),
            phase_guide: ($d.phase_guide // {}),
            methodology_hints: ($d.methodology_hints // []),
            warnings: []
        }
    ' 2>/dev/null)"

    if [ -z "$regenerated" ]; then
        echo "  FAIL: jq pipeline produced empty output (default-triggers.json may be malformed)"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
        return 1
    fi

    local committed
    committed="$(cat "$fallback_file")"

    # Compare via diff so the failure message shows exactly what drifted
    local diff_output
    diff_output="$(diff <(printf '%s\n' "$regenerated") <(printf '%s\n' "$committed") 2>&1)"

    if [ -z "$diff_output" ]; then
        echo "  PASS: fallback-registry.json is in sync"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    else
        echo "  FAIL: fallback-registry.json drifted from default-triggers.json"
        echo "  Run: bash hooks/session-start-hook.sh to regenerate (or apply the diff below)"
        echo "  --- diff (regenerated vs committed) ---"
        printf '%s\n' "$diff_output" | head -50
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
        return 1
    fi
}
```

Also add the test to the test runner block at the end of `tests/test-registry.sh`. Locate the existing list of `test_*` calls (e.g., `test_fallback_registry_skill_coverage`) and append `test_fallback_registry_in_sync_with_default_triggers` to it.

- [ ] **Step 1.2: Run the test to verify it passes (or fails with a real drift)**

Run: `bash tests/test-registry.sh 2>&1 | grep -A2 'fallback-registry.json matches'`

Expected: PASS if no drift exists today; otherwise the diff is shown, and Step 1.3 resolves it.

- [ ] **Step 1.3: If the test fails, regenerate fallback-registry.json**

Run the session-start hook in non-test mode so it writes the fallback:

```bash
DEFAULT_JSON_PRISTINE_SOURCE="$(cat config/default-triggers.json)" \
    bash hooks/session-start-hook.sh < /dev/null >/dev/null 2>&1
```

If the hook does not write `config/fallback-registry.json` (it only writes when `DEFAULT_JSON_PRISTINE` is set internally), regenerate manually using the same jq pipeline from the test:

```bash
jq --argjson cap_keys '["context7","context_hub_cli","context_hub_available","serena","serena_connected","forgetful","forgetful_connected","openspec","posthog","lsp"]' '
  . as $d |
  {
    version: ($d.version // "4.0.0-fallback"),
    frontmatter_schema_version: 1,
    skills: [($d.skills // [])[] | . + {available: false, enabled: (.enabled // true)}],
    plugins: [($d.plugins // [])[] | . + {available: false}],
    context_capabilities: ($cap_keys | map({(.): false}) | add),
    openspec_capabilities: {binary: false, commands: [], surface: "none", warnings: []},
    phase_compositions: ($d.phase_compositions // {}),
    phase_guide: ($d.phase_guide // {}),
    methodology_hints: ($d.methodology_hints // []),
    warnings: []
  }
' config/default-triggers.json > config/fallback-registry.json.tmp && \
    mv config/fallback-registry.json.tmp config/fallback-registry.json
```

Then re-run the test in Step 1.2.

- [ ] **Step 1.4: Run the full registry test suite**

Run: `bash tests/test-registry.sh`
Expected: All tests pass (including the new one).

- [ ] **Step 1.5: Commit**

```bash
git add tests/test-registry.sh config/fallback-registry.json
git commit -m "test: add fallback-registry drift gate

Regression test that fails if config/fallback-registry.json drifts
from config/default-triggers.json (the no-jq fallback path).
Closes the drift class documented in feedback_default_triggers_source_of_truth."
```

---

## Task 2: C2 — Iteration cap with role-allowlist

This task has three sub-changes: schema (default-triggers.json), enforcement (activation hook), regression test (test-routing.sh). Plus a CLAUDE.md gotcha entry. We TDD it: write the regression test first to lock in the role-allowlist invariant, then add the enforcement code.

**Files:**
- Modify: `config/default-triggers.json` — add `max_iterations: 1` to the `agent-team-review` skill block.
- Modify: `config/fallback-registry.json` — regenerate.
- Modify: `hooks/skill-activation-hook.sh` — insert iteration-cap check inside `_score_skills` (after the trigger-match block; before pushing to RESULTS).
- Modify: `tests/test-routing.sh` — add `test_max_iterations_role_allowlist`.
- Modify: `CLAUDE.md` — add Gotcha entry.

- [ ] **Step 2.1: Add the failing regression test (role-allowlist invariant)**

Append to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# C2: max_iterations is honored only for domain/required roles.
# Process and workflow skills must never be capped regardless of config.
# Invariant locks in the role-allowlist guard.
# ---------------------------------------------------------------------------
test_max_iterations_role_allowlist() {
    echo "-- test: max_iterations honored only for domain/required roles --"
    setup_test_env

    if ! command -v jq >/dev/null 2>&1; then
        echo "  SKIP: jq not available"
        return 0
    fi

    # Synthesize a minimal registry with one process skill that has max_iterations: 1
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    mkdir -p "$(dirname "$cache_file")"
    cat > "$cache_file" <<'EOF'
{
  "version": "4.0",
  "skills": [
    {
      "name": "test-process-skill",
      "role": "process",
      "phase": "REVIEW",
      "priority": 50,
      "max_iterations": 1,
      "available": true,
      "enabled": true,
      "invoke": "Skill(test-process-skill)",
      "triggers": ["test.process.skill.trigger"],
      "keywords": []
    },
    {
      "name": "test-domain-skill",
      "role": "domain",
      "phase": "REVIEW",
      "priority": 10,
      "max_iterations": 1,
      "available": true,
      "enabled": true,
      "invoke": "Skill(test-domain-skill)",
      "triggers": ["test.domain.skill.trigger"],
      "keywords": []
    }
  ],
  "context_capabilities": {},
  "phase_compositions": {},
  "phase_guide": {}
}
EOF

    # Synthesize a session token + composition state that already shows BOTH skills as completed once.
    local token="iter-cap-test-$$"
    echo "$token" > "${HOME}/.claude/.skill-session-token"
    cat > "${HOME}/.claude/.skill-composition-state-${token}" <<EOF
{
  "chain": ["test-process-skill","test-domain-skill"],
  "completed": ["test-process-skill","test-domain-skill"],
  "current_index": 0,
  "updated_at": "2026-05-21T00:00:00Z"
}
EOF

    # Invoke activation hook with a prompt that triggers BOTH skills.
    local input='{"prompt":"test.process.skill.trigger and test.domain.skill.trigger"}'
    local output
    output="$(printf '%s' "$input" | bash "${PROJECT_ROOT}/hooks/skill-activation-hook.sh" 2>/dev/null)"

    # Process skill MUST appear in output (cap ignored for process role).
    if printf '%s' "$output" | grep -q "test-process-skill"; then
        echo "  PASS: process skill not capped (role-allowlist invariant holds)"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    else
        echo "  FAIL: process skill was capped despite role-allowlist guard"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    fi

    # Domain skill MUST NOT appear (cap honored for domain role).
    if printf '%s' "$output" | grep -q "test-domain-skill"; then
        echo "  FAIL: domain skill not capped despite max_iterations: 1"
        echo "  Output: $output"
        TESTS_FAILED=$((${TESTS_FAILED:-0} + 1))
    else
        echo "  PASS: domain skill capped at iteration 1"
        TESTS_PASSED=$((${TESTS_PASSED:-0} + 1))
    fi

    teardown_test_env
}
```

Also register the test in the runner block of `tests/test-routing.sh` (locate the existing `test_*` invocations near the bottom).

- [ ] **Step 2.2: Run the test — it must fail (no enforcement yet)**

Run: `bash tests/test-routing.sh 2>&1 | grep -A3 'max_iterations honored'`
Expected: FAIL on "domain skill capped at iteration 1" — the hook does not yet honor `max_iterations`.

- [ ] **Step 2.3: Add `max_iterations: 1` to agent-team-review in default-triggers.json**

Use jq to add the field without disturbing the rest of the file. Run:

```bash
jq '(.skills[] | select(.name == "agent-team-review")) |= (. + {max_iterations: 1})' \
    config/default-triggers.json > config/default-triggers.json.tmp && \
    mv config/default-triggers.json.tmp config/default-triggers.json
```

Verify:

```bash
jq '.skills[] | select(.name == "agent-team-review") | .max_iterations' config/default-triggers.json
```
Expected: `1`

- [ ] **Step 2.4: Regenerate fallback-registry.json**

Run the same jq pipeline used in Task 1, Step 1.3 to keep the fallback in sync. Then run `bash tests/test-registry.sh` and confirm the trigger-sync gate passes.

- [ ] **Step 2.5: Add iteration-cap enforcement to skill-activation-hook.sh**

The cap check goes inside `_score_skills`, after the per-skill trigger/keyword/name-boost scoring block but before the `RESULTS=...` accumulator line. The hook already reads composition state via `_comp_active`; we add a per-skill iteration counter that uses the same file.

Locate the line in `hooks/skill-activation-hook.sh` near `_score_skills` where matched skills are added to `RESULTS` (around line 244-246, the `if [[ "$trigger_score" -gt 0 ]] || [[ "$name_boost" -gt 0 ]] || [[ "$keyword_score" -gt 0 ]]; then` block). Just BEFORE the `final_score=...` line inside that block, insert:

```bash
    # ---- C2: per-skill iteration cap (role-allowlist: domain + required only) ----
    # max_iterations is read by _hydrate_skill_data via SKILL_DATA. To keep the
    # field-separated record stable, we look it up from the registry directly
    # here (one jq fork per matched skill — bounded by RESULTS cardinality).
    # Role-allowlist hardcoded: process/workflow are NEVER capped, regardless
    # of config. Fail-open on any error.
    if [[ "$skill_role" == "domain" || "$skill_role" == "required" ]] && [[ -n "${_SESSION_TOKEN}" ]]; then
        _max_iter="$(printf '%s' "$REGISTRY" | jq -r --arg n "$skill_name" \
            '.skills[] | select(.name == $n) | .max_iterations // empty' 2>/dev/null)"
        if [[ "$_max_iter" =~ ^[0-9]+$ ]] && [[ "$_max_iter" -ge 1 ]]; then
            _comp_file="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
            if [[ -f "$_comp_file" ]]; then
                _iter_count="$(jq -r --arg n "$skill_name" \
                    '[.completed // [] | .[] | select(. == $n)] | length' \
                    "$_comp_file" 2>/dev/null)"
                if [[ "$_iter_count" =~ ^[0-9]+$ ]] && [[ "$_iter_count" -ge "$_max_iter" ]]; then
                    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
                        printf '[skill-hook] [max-iter] skipping %s (%s of %s)\n' \
                        "$skill_name" "$_iter_count" "$_max_iter" >&2
                    continue
                fi
            fi
        fi
    fi
    # ---- end C2 ----
```

Note: `continue` here continues the outer `while ... read` loop reading `SKILL_DATA`, skipping the `RESULTS` append for this skill.

- [ ] **Step 2.6: Run the routing tests to verify the regression test now passes**

Run: `bash tests/test-routing.sh 2>&1 | grep -A3 'max_iterations honored'`
Expected: BOTH lines PASS — process skill not capped, domain skill capped.

- [ ] **Step 2.7: Run the full test suite**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. No regressions in routing, registry, or context-formatting suites.

- [ ] **Step 2.8: Syntax-check the hook**

Run: `bash -n hooks/skill-activation-hook.sh`
Expected: Exit 0, no output.

- [ ] **Step 2.9: Add Gotcha entry to CLAUDE.md**

Locate the `## Gotchas` section in `CLAUDE.md` and append:

```markdown
- **`max_iterations` is role-gated**: the cap in `config/default-triggers.json` is only honored for skills with `role: domain` or `role: required`. Process and workflow skills (e.g., `verification-before-completion`, `openspec-ship`, `finishing-a-development-branch`, `requesting-code-review`) are NEVER capped — this is a hardcoded invariant in `hooks/skill-activation-hook.sh::_score_skills`, not config-driven. Protects SDLC phase gates from accidental misconfiguration. Regression covered by `tests/test-routing.sh::test_max_iterations_role_allowlist`.
```

- [ ] **Step 2.10: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json \
        hooks/skill-activation-hook.sh tests/test-routing.sh CLAUDE.md
git commit -m "feat: cap agent-team-review at 1 iteration with role-allowlist guard

Adds per-trigger max_iterations field honored only for domain/required
roles. Process and workflow skills are never capped — invariant
hardcoded in the activation hook and locked by test-routing regression.

Closes the bot-review asymptote class documented in
feedback_bot_review_asymptote. Push-gate enforcement
(openspec-guard.sh) is untouched."
```

---

## Task 3: C1 — Passive telemetry

**Files:**
- Modify: `hooks/skill-completion-hook.sh` — append one telemetry-write block before the final `exit 0`.

The hook already fires on PostToolUse for Skill returns and already reads the session token. We extend it with a hashed-token JSONL write. Fail-open: write failures are silently dropped.

- [ ] **Step 3.1: Add the telemetry write to skill-completion-hook.sh**

In `hooks/skill-completion-hook.sh`, locate the section just before the final `exit 0` (after the existing SKILL_EXPLAIN breadcrumb on line 53-54). Insert:

```bash
# ---- C1: passive advisory-lens telemetry ----
# Append one JSONL line per Skill completion. Fail-open: any error is
# silently dropped. Schema is intentionally minimal — no labels, no
# counterfactual claims. Substrate for future trim debates only.
_TELEMETRY_LOG="${HOME}/.claude/.advisory-lens-log.jsonl"
_TELEMETRY_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
# Hashed token: sha256 of session token, first 12 hex chars. Matches the
# pattern from PR #36 (project_serena_pnp_and_measurement memory).
_TELEMETRY_HASH=""
if command -v shasum >/dev/null 2>&1; then
    _TELEMETRY_HASH="$(printf '%s' "${_SESSION_TOKEN}" | shasum -a 256 2>/dev/null | cut -c1-12)"
elif command -v sha256sum >/dev/null 2>&1; then
    _TELEMETRY_HASH="$(printf '%s' "${_SESSION_TOKEN}" | sha256sum 2>/dev/null | cut -c1-12)"
fi

# finding_count_estimate: best-effort line count of tool_response.content.
# Reviewer skills produce structured output; raw line count is a coarse
# proxy that distinguishes "no findings" (0-5 lines) from "many findings"
# (50+ lines). Not a precise metric.
_TELEMETRY_LINES="$(printf '%s' "${_INPUT}" | jq -r '
    .tool_response.content // .tool_response.output // ""
' 2>/dev/null | wc -l 2>/dev/null | tr -d '[:space:]')"
[ -z "${_TELEMETRY_LINES}" ] && _TELEMETRY_LINES="0"

# Build and append the JSONL line. jq -c keeps it on one line.
jq -nc \
    --arg ts "${_TELEMETRY_TS}" \
    --arg skill "${_BARE}" \
    --argjson count "${_TELEMETRY_LINES}" \
    --arg hash "${_TELEMETRY_HASH}" \
    '{ts: $ts, skill: $skill, finding_count_estimate: $count, session_token_hashed: $hash}' \
    >> "${_TELEMETRY_LOG}" 2>/dev/null || true
# ---- end C1 ----
```

- [ ] **Step 3.2: Syntax-check the hook**

Run: `bash -n hooks/skill-completion-hook.sh`
Expected: Exit 0, no output.

- [ ] **Step 3.3: Smoke-test the hook by piping a synthetic Skill PostToolUse payload**

```bash
echo "test-session-token-c1" > ~/.claude/.skill-session-token
mkdir -p ~/.claude
cat > ~/.claude/.skill-composition-state-test-session-token-c1 <<'EOF'
{"chain":["smoke-test-skill"],"completed":[],"current_index":0,"updated_at":"2026-05-21T00:00:00Z"}
EOF
rm -f ~/.claude/.advisory-lens-log.jsonl

printf '%s' '{"tool_input":{"name":"smoke-test-skill"},"tool_response":{"content":"line1\nline2\nline3"}}' \
    | bash hooks/skill-completion-hook.sh

# Verify a JSONL line was appended
cat ~/.claude/.advisory-lens-log.jsonl
```

Expected output: one JSON line with fields `ts`, `skill: "smoke-test-skill"`, `finding_count_estimate` (integer), `session_token_hashed` (12 hex chars or empty if no shasum).

- [ ] **Step 3.4: Clean up smoke-test artifacts**

```bash
rm -f ~/.claude/.skill-composition-state-test-session-token-c1
rm -f ~/.claude/.advisory-lens-log.jsonl
# Leave ~/.claude/.skill-session-token alone — restore if it held a real token before the test
```

- [ ] **Step 3.5: Run the full test suite to confirm no regression**

Run: `bash tests/run-tests.sh`
Expected: All tests pass. Skill-completion-hook has no dedicated test suite; the smoke test in Step 3.3 verifies the new path.

- [ ] **Step 3.6: Commit**

```bash
git add hooks/skill-completion-hook.sh
git commit -m "feat: passive advisory-lens telemetry (substrate only, no labels)

Appends one JSONL line per Skill completion to
~/.claude/.advisory-lens-log.jsonl with hashed session token and
line-count proxy for finding count. No labels, no aggregation tooling.
Substrate for evidence-based trim decisions in 30+ days.
Fail-open writes; never propagates errors."
```

---

## Task 4: Final verification and PR

- [ ] **Step 4.1: Run all tests**

Run: `bash tests/run-tests.sh`
Expected: All test suites pass.

- [ ] **Step 4.2: Syntax-check all touched hooks**

```bash
bash -n hooks/skill-activation-hook.sh
bash -n hooks/skill-completion-hook.sh
```
Expected: Exit 0 for both.

- [ ] **Step 4.3: Verify the three commits are on the feature branch**

Run: `git log --oneline main..HEAD`
Expected: Three commits (Task 1, Task 2, Task 3) ordered C4 → C2 → C1.

- [ ] **Step 4.4: Hand off to REVIEW phase**

Per the SDLC chain, REVIEW is mandatory next. Dispatch `superpowers:requesting-code-review` with BASE_SHA = `main` and HEAD_SHA = the C1 commit. For substantial changes (this touches 5+ files including hooks + config + tests), also dispatch `auto-claude-skills:agent-team-review`.

---

## Self-Review Checklist

**Spec coverage:** Each of the four acceptance scenarios in the design doc maps to a task:
- AS-1 (drift detection) → Task 1
- AS-2 (cap on adversarial/agent-team-review) → Task 2 (Steps 2.3, 2.5)
- AS-3 (role-allowlist regression) → Task 2 (Steps 2.1, 2.6)
- AS-4 (passive telemetry write) → Task 3 (Steps 3.1, 3.3)

**Placeholder scan:** All code blocks contain complete, copy-pasteable content. No TBD/TODO/"similar to" markers.

**Type consistency:** `_SESSION_TOKEN`, `REGISTRY`, `SKILL_EXPLAIN`, `TESTS_FAILED`/`TESTS_PASSED` are referenced consistently with existing hook conventions. `_BARE` in the completion hook is the existing variable from line 35.

**Risk callouts:**
- The `cap_keys` array in Task 1 Step 1.1 must mirror `_CANONICAL_CAP_KEYS` in `hooks/session-start-hook.sh`. If new capabilities are ever added, both must update — same as the existing memory entry `feedback_default_triggers_source_of_truth` covers. Worth flagging in Task 1 commit message.
- The `continue` in Task 2 Step 2.5 must be inside the correct outer loop (the `while ... read ... done <<EOF ${SKILL_DATA} EOF` in `_score_skills`). Visual review during implementation is essential.
- Telemetry log can grow unbounded. No rotation in v1 (per design out-of-scope); revisit at 30 days.
