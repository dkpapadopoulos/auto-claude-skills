#!/usr/bin/env bash
# tests/test-security-scanner.sh — Tests for security scanner integration
set -u
PASS=0; FAIL=0; ERRORS=""

# Note: grep -qF -- "$needle" prevents needles starting with '--' (e.g., '--format=json') from being interpreted as grep flags
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected to contain: ${needle}\n    got: $(printf '%s' "$haystack" | head -c 200)"
  fi
}

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  if printf '%s' "$haystack" | grep -qF -- "$needle"; then
    FAIL=$((FAIL + 1))
    ERRORS="${ERRORS}\n  FAIL: ${label}\n    expected NOT to contain: ${needle}"
  else
    PASS=$((PASS + 1))
  fi
}

# ── Test: security_capabilities appears in session-start output ──
test_security_capabilities_in_output() {
  echo "--- test_security_capabilities_in_output ---"
  local output
  output="$(bash hooks/session-start-hook.sh 2>/dev/null)" || true
  assert_contains "session-start emits security tools" "Security tools:" "$output"
  assert_contains "session-start emits semgrep capability" "semgrep=" "$output"
  assert_contains "session-start emits trivy capability" "trivy=" "$output"
  assert_contains "session-start emits osv_scanner capability" "osv_scanner=" "$output"
}

# ── Test: security-scanner removed from missing external skills ──
test_security_scanner_not_in_external_check() {
  echo "--- test_security_scanner_not_in_external_check ---"
  local hook_source
  hook_source="$(cat hooks/session-start-hook.sh)"
  assert_not_contains "security-scanner not in external skills loop" \
    "doc-coauthoring webapp-testing security-scanner" "$hook_source"
}

# ── Test: methodology hint exists in registry with correct triggers ──
test_methodology_hint_in_registry() {
  echo "--- test_methodology_hint_in_registry ---"
  local registry
  registry="$(cat config/default-triggers.json)"
  assert_contains "registry has deterministic-security-scan hint" \
    "deterministic-security-scan" "$registry"
  assert_contains "hint triggers include security keyword" \
    "security|vulnerabilit" "$registry"
  assert_not_contains "hint triggers exclude plain review" \
    '"(review|security' "$registry"
}

# ── Test: methodology hint fires in all phases ──
test_methodology_hint_phase_scoped() {
  echo "--- test_methodology_hint_phase_scoped ---"
  local hint_block
  hint_block="$(jq '.methodology_hints[] | select(.name == "deterministic-security-scan")' config/default-triggers.json 2>/dev/null)" || true
  assert_contains "hint fires in all phases" '"*"' "$hint_block"
  assert_contains "hint references bundled skill" "auto-claude-skills:security-scanner" "$hint_block"
}

# ── Test: REVIEW composition has updated invoke path ──
test_review_composition_invoke_path() {
  echo "--- test_review_composition_invoke_path ---"
  local registry
  registry="$(cat config/default-triggers.json)"
  assert_contains "REVIEW composition uses bundled invoke path" \
    "Skill(auto-claude-skills:security-scanner)" "$registry"
  assert_not_contains "REVIEW composition has no stale external path" \
    '"Skill(security-scanner)"' "$registry"
}

# ── Test: fallback registry has updated invoke path ──
test_fallback_registry_parity() {
  echo "--- test_fallback_registry_parity ---"
  local fallback
  fallback="$(cat config/fallback-registry.json)"
  assert_contains "fallback has new invoke path" "auto-claude-skills:security-scanner" "$fallback"
  assert_not_contains "fallback has no stale invoke path" '"Skill(security-scanner)"' "$fallback"
}

# ── Test: SKILL.md documents OSV-Scanner step ──
test_skill_md_documents_osv_scanner_step() {
  echo "--- test_skill_md_documents_osv_scanner_step ---"
  local skill_md
  skill_md="$(cat skills/security-scanner/SKILL.md)"
  assert_contains "SKILL.md mentions OSV-Scanner step" "OSV-Scanner" "$skill_md"
  assert_contains "SKILL.md documents osv-scanner scan command" "osv-scanner scan" "$skill_md"
  assert_contains "SKILL.md mentions GHSA/registry-native advisories" "registry-native" "$skill_md"
  assert_contains "SKILL.md documents JSON output flag" "--format=json" "$skill_md"
  assert_contains "SKILL.md mentions install fallback" "github.com/google/osv-scanner" "$skill_md"
}

# ── Test: SKILL.md documents dependency-provenance (slopsquat) step ──
test_skill_md_documents_dependency_provenance() {
  echo "--- test_skill_md_documents_dependency_provenance ---"
  local skill_md
  skill_md="$(cat skills/security-scanner/SKILL.md)"
  assert_contains "SKILL.md has a Dependency Provenance step" "Dependency Provenance" "$skill_md"
  assert_contains "SKILL.md names the slopsquatting threat" "Slopsquatting" "$skill_md"
  assert_contains "SKILL.md distinguishes the typosquat case" "typosquat" "$skill_md"
  assert_contains "SKILL.md mandates registry resolution, not memory" "resolve" "$skill_md"
  assert_contains "SKILL.md gives an npm resolver command" "npm view" "$skill_md"
  assert_contains "SKILL.md gives a pip resolver command" "pip index versions" "$skill_md"
  # The check must target NEWLY-ADDED deps in the diff, not a full re-scan
  assert_contains "SKILL.md scopes the check to added dependencies" "newly-added" "$skill_md"
}

# ── Test: agent-team-review security lens checks dependency provenance ──
test_review_security_lens_checks_provenance() {
  echo "--- test_review_security_lens_checks_provenance ---"
  local review_md
  review_md="$(cat skills/agent-team-review/SKILL.md)"
  assert_contains "security lens names provenance" "provenance" "$review_md"
  assert_contains "security lens names slopsquatting" "slopsquatting" "$review_md"
}

# ══════════════════════════════════════════════════════════════════
# Run tests
# ══════════════════════════════════════════════════════════════════
test_security_capabilities_in_output
test_security_scanner_not_in_external_check
test_methodology_hint_in_registry
test_methodology_hint_phase_scoped
test_review_composition_invoke_path
test_fallback_registry_parity
test_skill_md_documents_osv_scanner_step
test_skill_md_documents_dependency_provenance
test_review_security_lens_checks_provenance

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ -n "$ERRORS" ]; then
  printf '%b\n' "$ERRORS"
  exit 1
fi
exit 0
