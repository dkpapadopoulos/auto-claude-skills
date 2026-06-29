#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-project-verification.sh ==="

SKILL="${PROJECT_ROOT}/skills/project-verification/SKILL.md"
REF="${PROJECT_ROOT}/skills/project-verification/references/discovery-ladder.md"

assert_file_exists "SKILL.md exists" "${SKILL}"
assert_file_exists "discovery-ladder ref exists" "${REF}"

skill="$(cat "${SKILL}" 2>/dev/null)"
assert_contains "frontmatter phase REVIEW"     "phase: REVIEW"            "${skill}"
assert_contains "frontmatter role domain"      "role: domain"             "${skill}"
assert_contains "substrate is local in v1"     "local"                    "${skill}"
assert_contains "evidence path documented"     ".skill-project-verified-" "${skill}"
assert_contains "deterministic-first ladder"   "deterministic"            "${skill}"
assert_contains "evidence is advisory only"    "not a trust boundary"     "${skill}"

ref="$(cat "${REF}" 2>/dev/null)"
assert_contains "ladder rung .verify.yml"      ".verify.yml"              "${ref}"
assert_contains "ladder rung manifests"        "pyproject.toml"           "${ref}"
assert_contains "ladder rung CLAUDE.md table"  "## Commands"              "${ref}"
assert_contains "ambiguity prompts user"       "prompt"                   "${ref}"

# --- gate-gaming-check.sh deterministic behavior ---
GGC="${PROJECT_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"
assert_file_exists "gate-gaming-check.sh exists" "${GGC}"

# removed assertion line => suspect
out_removed="$(printf '%s\n' '-    assert result == expected' '+    pass' | bash "${GGC}" 2>/dev/null)"
assert_contains "removed assertion is suspect" "suspect" "${out_removed}"

# removed assertion with NO leading whitespace => suspect (header pre-filter must not eat content)
out_removed_noindent="$(printf '%s\n' '-assert x == y' | bash "${GGC}" 2>/dev/null)"
assert_contains "removed assertion (no indent) is suspect" "suspect" "${out_removed_noindent}"

# added pytest skip => suspect
out_skip="$(printf '%s\n' '+@pytest.mark.skip(reason="flaky")' | bash "${GGC}" 2>/dev/null)"
assert_contains "added skip marker is suspect" "suspect" "${out_skip}"

# added JS .skip( => suspect
out_jsskip="$(printf '%s\n' '+  it.skip("does thing", () => {' | bash "${GGC}" 2>/dev/null)"
assert_contains "added it.skip is suspect" "suspect" "${out_jsskip}"

# clean diff (added assertion, no markers) => clean
out_clean="$(printf '%s\n' '+    assert result == expected' '+    return value' | bash "${GGC}" 2>/dev/null)"
assert_contains "clean diff is clean" "clean" "${out_clean}"

# empty input => clean (fail-open, never errors)
out_empty="$(printf '' | bash "${GGC}" 2>/dev/null)"
assert_contains "empty input is clean" "clean" "${out_empty}"

# diff header lines (--- a/path +++ b/path) with keyword in path must NOT be suspect
out_header="$(printf '%s\n' '--- a/tests/assert.py' '+++ b/tests/assert.py' | bash "${GGC}" 2>/dev/null)"
assert_contains "diff header path is not suspect" "clean" "${out_header}"

# +++ header whose path contains a skip-marker substring => clean (added-skip pre-filter symmetry)
out_addhdr="$(printf '%s\n' '+++ b/tests/weird.skip(x).py' | bash "${GGC}" 2>/dev/null)"
assert_contains "added-skip header path is not suspect" "clean" "${out_addhdr}"

# Node require.<property> boilerplate (require.resolve / require.main) is NOT an assertion => clean
out_reqresolve="$(printf '%s\n' '-const p = require.resolve("./fixtures");' | bash "${GGC}" 2>/dev/null)"
assert_contains "require.resolve deletion is not suspect" "clean" "${out_reqresolve}"
out_reqmain="$(printf '%s\n' '-if (require.main === module) run();' | bash "${GGC}" 2>/dev/null)"
assert_contains "require.main deletion is not suspect" "clean" "${out_reqmain}"

# "expect" as prose (no call paren) is NOT an assertion => clean; a real expect(...) call => suspect
out_expectprose="$(printf '%s\n' '-    # we expect the server to return 200' | bash "${GGC}" 2>/dev/null)"
assert_contains "prose 'expect' (no paren) is not suspect" "clean" "${out_expectprose}"
out_expectcall="$(printf '%s\n' '-    expect(add(2,2)).toBe(4)' | bash "${GGC}" 2>/dev/null)"
assert_contains "real expect(...) deletion is suspect" "suspect" "${out_expectcall}"

assert_contains "documents gate-gaming check"   "gate-gaming-check.sh"   "${skill}"
assert_contains "documents empty-GG as unverified" "unverified"          "${skill}"
assert_contains "documents could_not_verify"    "could_not_verify"       "${skill}"
assert_contains "documents gate_gaming_status"  "gate_gaming_status"     "${skill}"
assert_contains "documents suspect verdict"     "suspect"                "${skill}"
assert_contains "evidence accepted only when exactly clean" "exactly"     "${skill}"

print_summary
exit $?
