#!/usr/bin/env bash
# test-design-seed-missing-state.sh — #299: the reason a value is missing must be VISIBLE,
# beside the value it explains, in the styleguide AND in the reference page.
#
# The v1 seed taught the opposite. styleguide.md prescribed "a title attribute saying
# why", and reference.html demonstrated it on three cells under a caption reading "a
# reason on hover". A seeded pilot arm followed that and lost the dimension, so the
# defect was the guidance, not the reader.
#
# Four lints, split by what each can SEE. Each states its population as a claim, and
# each has a red control that calls the SAME function the lint calls -- over the real v1
# bytes in tests/fixtures/design-seed/v1-missing-state/ (copied verbatim from V1_SHA,
# never hand-written), or over a mutated copy of the live file.
#
# What none of this can see: whether a reader FOLLOWS the guidance. That is a question
# about generated screens, not about this repo, and it is issue #298.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-design-seed-missing-state.sh ==="

SEED="${PROJECT_ROOT}/assets/design-seed"
V1="${PROJECT_ROOT}/tests/fixtures/design-seed/v1-missing-state"
V1_SHA="07cb5910eeb9ff44e0349c294d16a0ddd636c1b1"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seedmissing.XXXXXX")"
trap 'rm -rf "${SCRATCH}"' EXIT

_CLASS_MISSING='class="([^"]* )?missing( [^"]*)?"'
_CLASS_PILL='class="([^"]* )?pill( [^"]*)?"'

# --- the fixtures are the real v1 bytes ---------------------------------------------
# A hand-written "before" only proves the lints agree with this file's idea of v1.
for f in styleguide.md reference.html; do
    assert_file_exists "v1 fixture exists: ${f}" "${V1}/${f}"
    if git -C "${PROJECT_ROOT}" cat-file -e "${V1_SHA}:assets/design-seed/${f}" 2>/dev/null; then
        git -C "${PROJECT_ROOT}" show "${V1_SHA}:assets/design-seed/${f}" > "${SCRATCH}/v1-${f}"
        if cmp -s "${SCRATCH}/v1-${f}" "${V1}/${f}"; then
            _record_pass "v1 fixture ${f} is byte-identical to ${V1_SHA}"
        else
            _record_fail "v1 fixture ${f} is byte-identical to ${V1_SHA}" "fixture was edited by hand"
        fi
    else
        # A shallow clone or a tarball install has no history. Say so rather than pass.
        echo "  SKIP: cannot check v1 fixture ${f} against ${V1_SHA} (commit not in this clone)"
    fi
done

# =====================================================================================
# LINT 1 -- the reference page hides no reason in an attribute.
# POPULATION: opening tags carrying the class token `missing`.
# SEES: a reason spelled as a `title` attribute on that tag.
# DOES NOT SEE: aria-label, CSS generated content, or a script-driven tooltip.
# =====================================================================================
_missing_tags() {
    tr '\n' ' ' < "$1" | tr '<' '\n' \
        | grep -E "^[A-Za-z][A-Za-z0-9]*[[:space:]][^>]*${_CLASS_MISSING}"
}
_missing_tags_hiding_reason() {
    _missing_tags "$1" | grep -E '[[:space:]]title[[:space:]]*='
}
_count() { printf '%s' "$1" | grep -c . | tr -d ' '; }

# Floor: with no missing cell on the page the lint below holds vacuously.
assert_equals "reference: the page still demonstrates missing cells (floor)" "3" \
    "$(_count "$(_missing_tags "${SEED}/reference.html")")"
assert_equals "reference: no missing cell carries its reason in a title attribute" "0" \
    "$(_count "$(_missing_tags_hiding_reason "${SEED}/reference.html")")"
# Red control, same function. The named fault is THREE hidden reasons, not merely "some".
assert_equals "control: the v1 reference hides exactly three reasons" "3" \
    "$(_count "$(_missing_tags_hiding_reason "${V1}/reference.html")")"

# =====================================================================================
# LINT 2 -- the reference page's own prose does not teach hover.
# POPULATION: the whole file. SEES: the phrase "on hover". A page can show the right
# thing and still describe the wrong one; the caption is what a reader quotes.
# =====================================================================================
_ref_teaches_hover() { grep -q -i -E 'on hover' "$1"; }

if _ref_teaches_hover "${SEED}/reference.html"; then
    _record_fail "reference: the prose does not describe a reason on hover" \
        "$(grep -n -i 'on hover' "${SEED}/reference.html" | head -3)"
else
    _record_pass "reference: the prose does not describe a reason on hover"
fi
if _ref_teaches_hover "${V1}/reference.html"; then
    _record_pass "control: the v1 reference prose does teach hover"
else
    _record_fail "control: the v1 reference prose does teach hover" "lint cannot see the v1 fault"
fi

# =====================================================================================
# LINT 3 -- a row with a missing value says why, in words, in that row.
# POPULATION: table rows (text up to each </tr>) containing a `missing` cell.
# SEES: words in a status pill in the row, or words inside the missing cell itself.
# DOES NOT SEE: whether the words are a good reason -- only that the row has some.
# v1 PASSES this lint (its row already had the pill), so the v1 fixture is no control
# here; the control is a mutated copy of the live page.
# =====================================================================================
_rows_missing_without_words() {
    tr '\n' ' ' < "$1" | awk '{ gsub(/<\/tr>/, "\n"); print }' \
        | grep -E "${_CLASS_MISSING}" \
        | grep -v -E "${_CLASS_PILL}[^>]*>[^<]*[A-Za-z]" \
        | grep -v -E "${_CLASS_MISSING}[^>]*>[^<]*[A-Za-z]"
}
assert_equals "reference: every row with a missing value carries words in that row" "0" \
    "$(_count "$(_rows_missing_without_words "${SEED}/reference.html")")"

sed 's#<span class="pill warn">Stale price</span>##' "${SEED}/reference.html" > "${SCRATCH}/nopill.html"
if cmp -s "${SEED}/reference.html" "${SCRATCH}/nopill.html"; then
    _record_fail "control: the mutation removed the row's words" "sed matched nothing; the control is vacuous"
else
    _record_pass "control: the mutation removed the row's words"
    _bare="$(_rows_missing_without_words "${SCRATCH}/nopill.html")"
    assert_equals "control: a row stripped of its words is reported, and only that row" "1" \
        "$(_count "${_bare}")"
    assert_contains "control: the reported row is the one that was mutated" "Delta Health" "${_bare}"
fi

# =====================================================================================
# LINT 4 -- the styleguide prescribes a visible reason and states the placement rule.
# POPULATION: the `| **Missing** |` row of the states table, and the file for the rule.
# SEES: the row naming a hidden channel as the treatment; the rule's lead sentence.
# =====================================================================================
_sg_missing_row() { grep -E '^\|[[:space:]]*\*\*Missing\*\*' "$1"; }
_sg_row_prescribes_hidden() { _sg_missing_row "$1" | grep -q -i -E 'title attribute|tooltip|hover'; }
_sg_row_says_visible() { _sg_missing_row "$1" | grep -q -i 'visible'; }
_sg_states_placement_rule() {
    grep -q -F 'A state is only treated where the reader meets the value' "$1"
}

assert_equals "styleguide: the states table has exactly one Missing row (floor)" "1" \
    "$(_count "$(_sg_missing_row "${SEED}/styleguide.md")")"
if _sg_row_prescribes_hidden "${SEED}/styleguide.md"; then
    _record_fail "styleguide: the Missing treatment is not a hidden channel" \
        "$(_sg_missing_row "${SEED}/styleguide.md")"
else
    _record_pass "styleguide: the Missing treatment is not a hidden channel"
fi
if _sg_row_says_visible "${SEED}/styleguide.md"; then
    _record_pass "styleguide: the Missing treatment says the reason is visible"
else
    _record_fail "styleguide: the Missing treatment says the reason is visible" \
        "$(_sg_missing_row "${SEED}/styleguide.md")"
fi
if _sg_states_placement_rule "${SEED}/styleguide.md"; then
    _record_pass "styleguide: states that a state is treated where the reader meets the value"
else
    _record_fail "styleguide: states that a state is treated where the reader meets the value" \
        "the placement rule is absent"
fi
# Red controls, same functions, real v1 bytes.
if _sg_row_prescribes_hidden "${V1}/styleguide.md"; then
    _record_pass "control: the v1 styleguide prescribes a hidden channel"
else
    _record_fail "control: the v1 styleguide prescribes a hidden channel" "lint cannot see the v1 fault"
fi
if _sg_row_says_visible "${V1}/styleguide.md"; then
    _record_fail "control: the v1 styleguide does not say visible" "lint passes on v1"
else
    _record_pass "control: the v1 styleguide does not say visible"
fi
if _sg_states_placement_rule "${V1}/styleguide.md"; then
    _record_fail "control: the v1 styleguide has no placement rule" "lint passes on v1"
else
    _record_pass "control: the v1 styleguide has no placement rule"
fi

# =====================================================================================
# LINT 5 -- every statement of the preset version agrees, and it is not v1.
# POPULATION: every file under the seed. Keyed on the SPELLING of a version statement,
# not on a list of files: the first enumeration found five sites and there were six.
# SEES: `version: N`, `"version": N`, `version:N`, `preset vN`.
# WHY IT MATTERS: adopted.json records this number and a copied seed is never upgraded,
# so it is the only thing that tells the guidance an adopter holds from this one.
# =====================================================================================
_seed_version_sites() {
    grep -r -n -o -E '("version"|version)[[:space:]]*:[[:space:]]*[0-9]+|preset v[0-9]+' "$1" \
        | sed -E 's/^(.*[^0-9])([0-9]+)$/\2 \1/'
}
_seed_versions() { _seed_version_sites "$1" | cut -d' ' -f1 | sort -u; }

_sites="$(_seed_version_sites "${SEED}")"
_n_sites="$(_count "${_sites}")"
if [ "${_n_sites}" -ge 6 ]; then
    _record_pass "version: at least six sites state the preset version (floor, found ${_n_sites})"
else
    _record_fail "version: at least six sites state the preset version (floor, found ${_n_sites})" "${_sites}"
fi
assert_equals "version: every site states the same version" "1" "$(_count "$(_seed_versions "${SEED}")")"
assert_equals "version: the sites agree with tokens.json" \
    "$(jq -r '.version' "${SEED}/tokens.json")" "$(_seed_versions "${SEED}" | head -1)"
assert_equals "version: the amended guidance is not labelled v1" "2" "$(_seed_versions "${SEED}" | head -1)"

# Red control, same function: revert ONE site in a copy and the disagreement is reported.
cp -R "${SEED}" "${SCRATCH}/seed-drift"
sed -E 's/preset v[0-9]+/preset v1/' "${SEED}/styleguide.md" > "${SCRATCH}/seed-drift/styleguide.md"
if cmp -s "${SEED}/styleguide.md" "${SCRATCH}/seed-drift/styleguide.md"; then
    _record_fail "control: the mutation reverted one version site" "sed changed nothing; the control is vacuous"
else
    _record_pass "control: the mutation reverted one version site"
    assert_equals "control: one drifted site yields two distinct versions" "2" \
        "$(_count "$(_seed_versions "${SCRATCH}/seed-drift")")"
fi

print_summary
