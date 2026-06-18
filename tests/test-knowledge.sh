#!/usr/bin/env bash
# test-knowledge.sh — Tests for knowledge rebuild index
# Bash 3.2 compatible. Sources test-helpers.sh for setup/teardown and assertions.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-knowledge.sh ==="

test_rebuild_index_regenerates_from_frontmatter() {
    local tmp; tmp="$(mktemp -d)"
    cp "${PROJECT_ROOT}/tests/fixtures/knowledge/valid/sample-decision.md" "${tmp}/"
    : > "${tmp}/index.md"   # clobber
    bash "${PROJECT_ROOT}/scripts/knowledge-rebuild-index.sh" "${tmp}"
    local out; out="$(cat "${tmp}/index.md")"
    assert_contains "index has schema_version" "schema_version: okf-0.1" "${out}"
    assert_contains "index lists the fact" "[Sample decision](sample-decision.md)" "${out}"
    rm -rf "${tmp}"
}
test_rebuild_index_regenerates_from_frontmatter

test_rebuild_index_sorts_by_slug_not_title() {
    local tmp; tmp="$(mktemp -d)"
    # a-zebra.md has title "Zebra" — slug-first but title-last
    cat > "${tmp}/a-zebra.md" <<'EOF'
---
type: decision
title: Zebra
description: Fact with slug-first but title-last ordering.
source: tests/fixtures/knowledge/valid/a-zebra.md
timestamp: 2026-06-18T00:00:00Z
---
Body.
EOF
    # z-alpha.md has title "Alpha" — slug-last but title-first
    cat > "${tmp}/z-alpha.md" <<'EOF'
---
type: decision
title: Alpha
description: Fact with slug-last but title-first ordering.
source: tests/fixtures/knowledge/valid/z-alpha.md
timestamp: 2026-06-18T00:00:00Z
---
Body.
EOF
    bash "${PROJECT_ROOT}/scripts/knowledge-rebuild-index.sh" "${tmp}"
    local out; out="$(cat "${tmp}/index.md")"
    # Confirm both entries appear
    assert_contains "index lists a-zebra.md" "(a-zebra.md)" "${out}"
    assert_contains "index lists z-alpha.md" "(z-alpha.md)" "${out}"
    # Slug order: a-zebra.md line must come before z-alpha.md line
    local line_zebra line_alpha
    line_zebra="$(printf '%s\n' "${out}" | grep -n '(a-zebra\.md)' | head -1 | cut -d: -f1)"
    line_alpha="$(printf '%s\n' "${out}" | grep -n '(z-alpha\.md)' | head -1 | cut -d: -f1)"
    if [ -n "${line_zebra}" ] && [ -n "${line_alpha}" ] && [ "${line_zebra}" -lt "${line_alpha}" ]; then
        _record_pass "index is ordered by slug (a-zebra before z-alpha)"
    else
        _record_fail "index is ordered by slug (a-zebra before z-alpha)" \
            "a-zebra on line ${line_zebra:-?}, z-alpha on line ${line_alpha:-?}"
    fi
    rm -rf "${tmp}"
}
test_rebuild_index_sorts_by_slug_not_title

test_validate_passes_on_valid_fixture() {
    if bash "${PROJECT_ROOT}/scripts/knowledge-validate.sh" tests/fixtures/knowledge/valid >/dev/null 2>&1; then
        _record_pass "validate passes on valid fixture"
    else
        _record_fail "validate passes on valid fixture" "exit 0" "non-zero"
    fi
}
test_validate_flags_dangling_link() {
    local out rc
    out="$(bash "${PROJECT_ROOT}/scripts/knowledge-validate.sh" tests/fixtures/knowledge/dangling 2>&1)"; rc=$?
    assert_contains "dangling reported" "does-not-exist" "${out}"
    assert_equals "dangling exits non-zero" "1" "${rc}"
}
test_validate_noop_when_absent() {
    if bash "${PROJECT_ROOT}/scripts/knowledge-validate.sh" /no/such/dir >/dev/null 2>&1; then
        _record_pass "validate no-ops when dir absent"
    else
        _record_fail "validate no-ops when dir absent" "exit 0" "non-zero"
    fi
}
test_validate_passes_on_valid_fixture
test_validate_flags_dangling_link
test_validate_noop_when_absent

test_forgetful_map_roundtrip() {
    local tmp; tmp="$(mktemp -d)"; local m="${tmp}/map.tsv"; : > "${m}"
    bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" put "${m}" my-slug 42 abc123
    local id; id="$(bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" get "${m}" my-slug)"
    assert_equals "map returns stored memory_id" "42" "${id}"
    rm -rf "${tmp}"
}
test_forgetful_map_roundtrip

test_forgetful_map_multi_slug_no_clobber() {
    local tmp; tmp="$(mktemp -d)"; local m="${tmp}/map.tsv"
    # put two different slugs
    bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" put "${m}" slug-a 1 hash-a
    bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" put "${m}" slug-b 2 hash-b
    local id_a id_b
    id_a="$(bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" get "${m}" slug-a)"
    id_b="$(bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" get "${m}" slug-b)"
    assert_equals "slug-a not clobbered by slug-b put" "1" "${id_a}"
    assert_equals "slug-b stored correctly" "2" "${id_b}"
    # update slug-a in place; slug-b must remain
    bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" put "${m}" slug-a 9 hash-a2
    id_a="$(bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" get "${m}" slug-a)"
    id_b="$(bash "${PROJECT_ROOT}/scripts/knowledge-forgetful-map.sh" get "${m}" slug-b)"
    assert_equals "slug-a updated to new id" "9" "${id_a}"
    assert_equals "slug-b unchanged after slug-a update" "2" "${id_b}"
    rm -rf "${tmp}"
}
test_forgetful_map_multi_slug_no_clobber

test_ci_entry_validates_repo_bundle() {
    if bash "${PROJECT_ROOT}/scripts/validate-knowledge-bundle.sh" >/dev/null 2>&1; then
        _record_pass "CI entry validates repo bundle (.claude/knowledge present and valid)"
    else
        _record_fail "CI entry validates repo bundle" "exit 0" "non-zero"
    fi
}
test_ci_entry_validates_repo_bundle

print_summary
