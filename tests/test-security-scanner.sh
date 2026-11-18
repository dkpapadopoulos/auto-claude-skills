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
  local output home
  # The hook writes under ~/.claude, so it gets a HOME of its own, never the one
  # this file was started with (#372). Regression: tests/test-suite-isolation.sh
  home="$(mktemp -d "${TMPDIR:-/tmp}/acs-secscan.XXXXXX")" || return 1
  output="$(HOME="${home}" bash hooks/session-start-hook.sh < /dev/null 2>/dev/null)" || true
  rm -rf "${home}"
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
  # The security lens prompt lives in references/ (re-attach budget split).
  review_md="$(awk '/^[[:space:]]*name: "security-reviewer"/{f=1;next} f && /^[[:space:]]*name: "/{exit} f' \
    skills/agent-team-review/references/reviewer-prompts.md)"
  assert_contains "security lens names provenance" "provenance" "$review_md"
  assert_contains "security lens names slopsquatting" "slopsquatting" "$review_md"
}

# ── Test: the documented gitleaks command reports a planted secret ──
# Without --report-path, gitleaks v8 writes no JSON to stdout, so the jq in
# Step 4 got no input and printed nothing: a repo full of secrets read as
# clean. `--report-path -` means stdout only from gitleaks 8.22, so the skill
# writes the report to a temp file it then reads. Runs the command exactly as
# SKILL.md documents it, against a scratch repo, so the assertion is on the
# real producer's bytes.
test_gitleaks_command_reports_planted_secret() {
  echo "--- test_gitleaks_command_reports_planted_secret ---"
  local cmd n skill_md
  skill_md="$(cat skills/security-scanner/SKILL.md)"
  # The command line, not prose that names it, starts with the report variable.
  n="$(grep -cE '^GL_REPORT=.*gitleaks detect --source' skills/security-scanner/SKILL.md)"
  assert_contains "SKILL.md documents exactly one gitleaks detect command" "count=1;" "count=${n};"
  cmd="$(grep -E '^GL_REPORT=.*gitleaks detect --source' skills/security-scanner/SKILL.md | head -1)"
  assert_contains "gitleaks command writes its report to a file it reads" '--report-path "$GL_REPORT"' "$cmd"
  assert_contains "gitleaks command reads that report" 'jq' "$cmd"
  assert_contains "gitleaks command redacts secret values" "--redact" "$cmd"
  # gitleaks' stderr is its "N commits scanned" and ERR lines and never a
  # secret; discarding it turns a scan of zero commits into a clean count: 0.
  assert_not_contains "gitleaks command keeps its scan summary visible" "2>/dev/null" "$cmd"
  # Uncommitted work is scanned with protect; committing first would put an
  # unfound secret into history.
  assert_contains "SKILL.md scans uncommitted changes with gitleaks protect" "gitleaks protect --staged" "$skill_md"
  assert_not_contains "SKILL.md never says to commit before scanning" "commit before this step" "$skill_md"
  # protect logs "0 commits scanned" on every run, so detect's pass rule would
  # make every clean uncommitted-work scan read as could-not-check.
  assert_contains "SKILL.md gives protect its own pass rule" "For \`protect\`, which always logs \`0 commits scanned\`" "$skill_md"

  if ! command -v gitleaks >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    echo "  SKIP: gitleaks or jq not installed; behavioural check not run"
    return 0
  fi
  local tmp out count key secret built
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/acs-gitleaks.XXXXXX")" || return 1
  # Assembled at runtime so this file carries no key-shaped literal.
  key="AKIA""Z4XQ7NWPR2BTK5MD"
  secret="wJalrXUtnFEMI/K7MDENG/""bPxRfiCYzQ8vN2kLp4"
  printf 'aws_access_key_id = %s\naws_secret_access_key = %s\n' "$key" "$secret" > "${tmp}/creds.txt"
  # The user's git and gitleaks config stay out: a global pre-commit hook (a
  # secret scanner, likely where gitleaks is installed), commit signing, an
  # inherited GIT_DIR, or a GITLEAKS_CONFIG without the AWS rules would
  # otherwise turn a fixture failure into a false skill defect.
  out="$(
    unset GIT_DIR GIT_WORK_TREE GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
    export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
    cd "$tmp" || exit 1
    git init -q && git add creds.txt \
      && git -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --no-verify -m planted \
      || { echo "FIXTURE-NOT-BUILT"; exit 0; }
    eval "$cmd" 2>/dev/null
  )" || true
  rm -rf "$tmp"
  case "$out" in
    *FIXTURE-NOT-BUILT*)
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: could not build the gitleaks fixture repo (git init/add/commit failed); the skill was not tested"
      return 0 ;;
  esac
  count="$(printf '%s' "$out" | jq -r '.count' 2>/dev/null)"
  case "$count" in
    ''|null|0|*[!0-9]*)
      FAIL=$((FAIL + 1))
      ERRORS="${ERRORS}\n  FAIL: documented gitleaks command reports the planted secret\n    got count: '${count}' output: $(printf '%s' "$out" | head -c 200)" ;;
    *) PASS=$((PASS + 1)) ;;
  esac
  # The jq projection, not --redact, is what keeps these out of the parsed
  # output; --redact is pinned by the flag assertion above.
  assert_not_contains "parsed gitleaks output carries no key value" "$key" "$out"
  assert_not_contains "parsed gitleaks output carries no secret value" "$secret" "$out"
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
test_gitleaks_command_reports_planted_secret

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
if [ -n "$ERRORS" ]; then
  printf '%b\n' "$ERRORS"
  exit 1
fi
exit 0
