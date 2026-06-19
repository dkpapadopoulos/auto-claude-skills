# Trifecta DESIGN/REVIEW Directive — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface `agent-safety-review` via an always-on model-asks DESIGN directive (and a strengthened REVIEW adversarial hint) so the lethal trifecta is caught even when its narrow regex misses the data-flow phrasing.

**Architecture:** Config-only change to `config/default-triggers.json` `phase_compositions` hints, mirrored into `config/fallback-registry.json` (regenerated verbatim from pristine default-triggers by session-start, line 111). The model performs the trifecta classification; the hook just injects advisory text. Deterministic hint-presence tests guard the config source of truth.

**Tech Stack:** Bash 3.2, jq, the existing `tests/test-routing.sh` harness.

## Global Constraints

- Bash 3.2 compatible; no `set -e` in routing paths.
- Field/hint edits MUST touch BOTH `config/default-triggers.json` (canonical) AND `config/fallback-registry.json` (regenerated mirror). The Fallback Registry Sync Gate enforces this.
- Preserve existing JSON — targeted edits only, never full-file rewrite.
- `when:"always"` on non-plugin hints is documentary (hook emits unconditionally); set it for consistency.
- Hint text MUST contain the literal `Skill(auto-claude-skills:agent-safety-review)`.
- DESIGN hint timing copy MUST say "after brainstorming has a candidate design and before transitioning to PLAN" (respects brainstorming HARD-GATE).
- `≥2`-fields invocation floor (incl. Unknown could-reach-2). Matches `agent-safety-review` SKILL.md Step 2 risk table.

---

### Task 1: Failing tests for trifecta directive presence/absence

**Files:**
- Modify: `tests/test-routing.sh` (append new test fns near the other phase-hint tests, ~after `test_capture_knowledge_routes` at L6254)

**Interfaces:**
- Consumes: existing harness helpers `setup_test_env`, `teardown_test_env`, `install_registry_v4`, `run_hook`, `extract_context`, `assert_contains`, `assert_not_contains`, and the global `PROJECT_ROOT`.
- Produces: test fns `test_trifecta_hint_present_at_design`, `test_trifecta_hint_absent_at_ship`, `test_review_adversarial_references_safety_review`, `test_agent_safety_review_fastpath_still_fires`; helper `install_registry_v4_with_real_phase_hints`.

- [ ] **Step 1: Write the failing tests + helper**

Append to `tests/test-routing.sh`:

```bash
# ---------------------------------------------------------------------------
# Helper: v4 registry with phase_compositions hints loaded from the REAL
# config/default-triggers.json, so these tests fail when a hint is absent
# from the actual source of truth (not the harness's embedded copy).
# ---------------------------------------------------------------------------
install_registry_v4_with_real_phase_hints() {
    install_registry_v4
    local cache_file="${HOME}/.claude/.skill-registry-cache.json"
    local tmp_file; tmp_file="$(mktemp)"
    jq --slurpfile cfg "${PROJECT_ROOT}/config/default-triggers.json" '
      .phase_compositions = ($cfg[0].phase_compositions // {})
    ' "${cache_file}" > "${tmp_file}" && mv "${tmp_file}" "${cache_file}"
}

# TRIFECTA CHECK present at DESIGN with the agent-safety-review invocation
test_trifecta_hint_present_at_design() {
    echo "-- test: TRIFECTA CHECK hint present at DESIGN --"
    setup_test_env
    install_registry_v4_with_real_phase_hints

    local ctx
    ctx="$(extract_context "$(run_hook "build something that reads customer support emails and posts replies to Slack")")"
    assert_contains "DESIGN carries TRIFECTA CHECK" "TRIFECTA CHECK" "${ctx}"
    assert_contains "TRIFECTA CHECK names agent-safety-review" "Skill(auto-claude-skills:agent-safety-review)" "${ctx}"

    teardown_test_env
}
test_trifecta_hint_present_at_design

# TRIFECTA CHECK absent outside its gate phases (SHIP)
test_trifecta_hint_absent_at_ship() {
    echo "-- test: TRIFECTA CHECK hint absent at SHIP --"
    setup_test_env
    install_registry_v4_with_real_phase_hints

    local ctx
    ctx="$(extract_context "$(run_hook "ship the release and merge to main")")"
    assert_not_contains "SHIP omits TRIFECTA CHECK" "TRIFECTA CHECK" "${ctx}"

    teardown_test_env
}
test_trifecta_hint_absent_at_ship

# REVIEW adversarial hint references agent-safety-review for trifecta flows
test_review_adversarial_references_safety_review() {
    echo "-- test: REVIEW adversarial hint references agent-safety-review --"
    setup_test_env
    install_registry_v4_with_real_phase_hints

    local ctx
    ctx="$(extract_context "$(run_hook "review my changes before merge")")"
    assert_contains "REVIEW adversarial routes to agent-safety-review" "Skill(auto-claude-skills:agent-safety-review)" "${ctx}"

    teardown_test_env
}
test_review_adversarial_references_safety_review

# Existing keyword fast-path for agent-safety-review still fires by triggers
test_agent_safety_review_fastpath_still_fires() {
    echo "-- test: agent-safety-review keyword fast-path still fires --"
    setup_test_env
    install_registry

    local ctx
    ctx="$(extract_context "$(run_hook "design an overnight unattended email agent that runs yolo")")"
    assert_contains "fast-path keeps routing agent-safety-review" "agent-safety-review" "${ctx}"

    teardown_test_env
}
test_agent_safety_review_fastpath_still_fires
```

- [ ] **Step 2: Run the new tests and confirm they fail**

Run: `bash tests/test-routing.sh 2>&1 | grep -iE "TRIFECTA|adversarial hint references|fast-path|FAIL" | head -30`
Expected: the three new TRIFECTA/adversarial tests FAIL (hint not yet in config). `test_agent_safety_review_fastpath_still_fires` may already PASS (it exercises the pre-existing regex) — that is fine; it is a guard against regression in Task 2.

- [ ] **Step 3: Commit the failing tests**

```bash
git add tests/test-routing.sh
git commit -m "test: failing tests for trifecta DESIGN/REVIEW directive"
```

---

### Task 2: Add DESIGN hint + reword REVIEW hint; regenerate fallback

**Files:**
- Modify: `config/default-triggers.json` — `phase_compositions.DESIGN.hints[]` (add entry after the EVAL STRATEGY entry, ~L1283) and `phase_compositions.REVIEW.hints[]` (reword ADVERSARIAL REVIEW entry, ~L1395)
- Modify (regenerated): `config/fallback-registry.json` — mirror of both (DESIGN ~L1160, REVIEW ~L1274)

**Interfaces:**
- Consumes: the test names from Task 1.
- Produces: the literal hint text the tests assert (`TRIFECTA CHECK`, `Skill(auto-claude-skills:agent-safety-review)`).

- [ ] **Step 1: Add the DESIGN hint** to `config/default-triggers.json`, immediately after the `EVAL STRATEGY` hint object in `phase_compositions.DESIGN.hints` (insert a new object; keep the array valid):

```json
        {
          "text": "TRIFECTA CHECK: During DESIGN, classify private_data (secrets/PII/private repos/tokens), untrusted_input (external content: emails, web pages, uploads, third-party API responses, webhooks), and outbound_action (acts outside the sandbox: email, Slack, git push, API calls, PRs) from the proposed data flow as Present/Absent/Unknown. If 2 or more are Present, or Unknowns could make the count >=2, invoke Skill(auto-claude-skills:agent-safety-review) after brainstorming has a candidate design and before transitioning to PLAN. Judge from the actual data flow — do not wait for a keyword trigger.",
          "when": "always"
        }
```

- [ ] **Step 2: Reword the REVIEW ADVERSARIAL REVIEW hint** in `config/default-triggers.json` `phase_compositions.REVIEW.hints` — append this sentence to the existing `text` value (before the closing `"`), do not change checks (1)-(6):

```
 (7) Does the resulting change have >=2 lethal-trifecta fields (private_data, untrusted_input, outbound_action), or add a missing leg to an existing >=2-field flow? If so, invoke Skill(auto-claude-skills:agent-safety-review) and treat unresolved lethal-trifecta mitigation as a blocking governance finding.
```

- [ ] **Step 3: Validate JSON**

Run: `jq -e '.phase_compositions.DESIGN.hints, .phase_compositions.REVIEW.hints' config/default-triggers.json >/dev/null && echo OK`
Expected: `OK`

- [ ] **Step 4: Regenerate the fallback registry from pristine config**

Run:
```bash
CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/session-start-hook.sh >/dev/null 2>&1 || true
git diff --stat config/fallback-registry.json
```
Expected: `config/fallback-registry.json` shows the two mirrored hint changes. If session-start does not write in this env, hand-mirror both edits into `config/fallback-registry.json` (DESIGN ~L1160 and REVIEW ~L1274) so the two files match.

- [ ] **Step 5: Guard the trailing-newline footgun**

Run: `tail -c1 config/fallback-registry.json | xxd | grep -q '0a' && echo "newline OK" || printf '\n' >> config/fallback-registry.json`
Expected: `newline OK` (or newline restored). Confirm `git diff` shows only intended hint changes, no whitespace churn.

- [ ] **Step 6: Run the new tests — now pass**

Run: `bash tests/test-routing.sh 2>&1 | grep -iE "TRIFECTA|adversarial hint references|fast-path" `
Expected: all four PASS.

- [ ] **Step 7: Commit**

```bash
git add config/default-triggers.json config/fallback-registry.json
git commit -m "feat: always-on trifecta DESIGN hint + REVIEW adversarial route to agent-safety-review"
```

---

### Task 3: Full verification + OpenSpec validate

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `bash tests/run-tests.sh 2>&1 | tail -25`
Expected: all suites pass (routing, registry incl. Fallback Registry Sync Gate, context).

- [ ] **Step 2: Syntax-check any touched hooks (none expected, but verify clean)**

Run: `for h in hooks/*.sh; do /bin/bash -n "$h" || echo "SYNTAX FAIL: $h"; done; echo done`
Expected: `done` with no SYNTAX FAIL.

- [ ] **Step 3: Empirically confirm the original gap is closed**

Run:
```bash
jq -n --arg p "I want to build an agent that reads my customer support emails and sends Slack replies automatically" '{"prompt":$p}' \
 | CLAUDE_PLUGIN_ROOT="$PWD" bash hooks/skill-activation-hook.sh 2>/dev/null \
 | jq -r '.hookSpecificOutput.additionalContext' | grep -i "trifecta"
```
Expected: the TRIFECTA CHECK line is present (the model is now told to classify + invoke agent-safety-review).

- [ ] **Step 4: Validate the OpenSpec change**

Run: `openspec validate trifecta-design-directive --strict 2>&1 | tail -3`
Expected: `Change 'trifecta-design-directive' is valid`

- [ ] **Step 5: Commit any remaining artifacts (if not already)**

```bash
git status -s
```
Expected: clean (design + tests + config already committed).

---

## Self-Review

- **Spec coverage:** Scenario 1 (DESIGN present w/o keywords) → Task 1 `test_trifecta_hint_present_at_design`. Scenario 2 (present on generic build) → same test (generic build prompt routes DESIGN). Scenario 3 (absent at SHIP) → `test_trifecta_hint_absent_at_ship`. Scenario 4 (REVIEW adversarial references skill) → `test_review_adversarial_references_safety_review`. Scenario 5 (fast-path intact) → `test_agent_safety_review_fastpath_still_fires`. All covered.
- **Placeholder scan:** none — all hint text and test code is literal.
- **Type/string consistency:** the literal needles `TRIFECTA CHECK` and `Skill(auto-claude-skills:agent-safety-review)` are identical across plan, tests, and config edits.
- **Dual-source rule:** Task 2 Steps 4-5 handle the fallback mirror + newline footgun; Task 3 Step 1 runs the sync gate.
