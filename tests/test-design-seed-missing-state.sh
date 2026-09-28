#!/usr/bin/env bash
# test-design-seed-missing-state.sh — #299: the reason a value is missing must be VISIBLE,
# in the same unit as the value it explains, in the styleguide AND in the reference page.
#
# The v1 seed taught the opposite. styleguide.md prescribed "a title attribute saying
# why", and reference.html demonstrated it on three cells under a caption reading "a
# reason on hover". A seeded pilot arm followed that and lost the dimension, so the
# defect was the guidance, not the reader.
#
# Six lints, split by what each can SEE. Each states its population as a claim, and
# each has a red control that calls the SAME function the lint calls -- over the real v1
# bytes in tests/fixtures/design-seed/v1-missing-state/ (copied verbatim from V1_SHA,
# never hand-written), or over a mutated copy of the live file.
#
# The first cut of this file was reviewed by feeding each lint inputs that violate its
# intent. Those inputs are cells here: a lint held only by reverting the author's own
# edit is held against one spelling of the fault.
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

# Every control below writes here. An empty SCRATCH would aim those writes at "/", and
# `cmp` on a file that was never written exits 2, which a bare `! cmp -s` reads as
# "differs" -- so a failed mktemp would make the mutation checks PASS.
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/seedmissing.XXXXXX" 2>/dev/null)"
if [ -z "${SCRATCH}" ] || [ ! -d "${SCRATCH}" ]; then
    _record_fail "scratch directory created" "mktemp failed; no cell below could be trusted"
    print_summary
    exit 1
fi
trap 'rm -rf "${SCRATCH}"' EXIT

# _changed <original> <mutated> -- true only when both exist and differ (cmp exit 1).
_changed() { cmp -s "$1" "$2"; [ $? -eq 1 ]; }
_count() { printf '%s' "$1" | grep -c . | tr -d ' '; }
_pass_if() {  # _pass_if <description> <detail-on-fail> <command...>
    local _d="$1" _detail="$2"; shift 2
    if "$@"; then _record_pass "${_d}"; else _record_fail "${_d}" "${_detail}"; fi
}
_fail_if() {
    local _d="$1" _detail="$2"; shift 2
    if "$@"; then _record_fail "${_d}" "${_detail}"; else _record_pass "${_d}"; fi
}
# _replace <from> <to> <in> <out> [first] -- literal replace, every occurrence in the
# file unless "first". Literal on purpose: the strings are HTML and JSON, full of
# characters a sed pattern would read as syntax.
_replace() {
    awk -v from="$1" -v to="$2" -v only="${5:-all}" '
        { out = ""; rest = $0
          while (!(only == "first" && done) && (i = index(rest, from)) > 0) {
              out = out substr(rest, 1, i - 1) to
              rest = substr(rest, i + length(from))
              done = 1
          }
          print out rest }' "$3" > "$4"
}

# A class attribute carrying the token, in any quoting: "missing", 'num missing', missing.
_Q="[\"']"
_NQ="[^\"']"
_TAG_REST="([[:space:]\"'][^>]*)?>"
_MISSING_TAG="class[[:space:]]*=[[:space:]]*(${_Q}${_NQ}*[[:space:]]|${_Q}?)missing${_TAG_REST}"
_PILL_TAG="class[[:space:]]*=[[:space:]]*(${_Q}${_NQ}*[[:space:]]|${_Q}?)pill${_TAG_REST}"

# One table row per line, from its <tr to its </tr> -- or to the next <tr, because a
# closing </tr> is optional in HTML.
_rows() {
    tr '\n\t' '  ' < "$1" \
        | awk '{ gsub(/<[tT][rR][ >]/, "\n&"); gsub(/<\/[tT][rR]>/, "&\n"); print }' \
        | grep -i -E '^<tr[ >]'
}
_missing_rows() { _rows "$1" | grep -i -E "${_MISSING_TAG}"; }
_missing_cells() {
    _missing_rows "$1" | tr '<' '\n' | grep -i -E "^[a-z][a-z0-9-]*[[:space:]][^>]*${_MISSING_TAG}"
}

# --- the fixtures are the real v1 bytes ---------------------------------------------
# A hand-written "before" only proves the lints agree with this file's idea of v1.
for f in styleguide.md reference.html; do
    assert_file_exists "v1 fixture exists: ${f}" "${V1}/${f}"
    if git -C "${PROJECT_ROOT}" cat-file -e "${V1_SHA}:assets/design-seed/${f}" 2>/dev/null; then
        git -C "${PROJECT_ROOT}" show "${V1_SHA}:assets/design-seed/${f}" > "${SCRATCH}/v1-${f}"
        _pass_if "v1 fixture ${f} is byte-identical to ${V1_SHA}" "fixture was edited by hand" \
            cmp -s "${SCRATCH}/v1-${f}" "${V1}/${f}"
    else
        # A shallow clone or a tarball install has no history. Say so rather than pass.
        echo "  SKIP: cannot check v1 fixture ${f} against ${V1_SHA} (commit not in this clone)"
    fi
done

# =====================================================================================
# LINT 1 -- no row that holds a missing value hides anything in a title attribute.
# POPULATION: table rows containing a cell whose class carries the token `missing`.
# SEES: a `title` attribute on ANY tag in such a row -- the row, the cell, a descendant,
#       a custom element -- in either case and either quoting.
# CANNOT TELL a reason from other detail, so a title on a shown value in that row is
#       reported too. That is the safe direction for a page whose job is to be imitated.
# DOES NOT SEE: aria-label, CSS generated content, a script-driven tooltip, a missing
#       value outside a table, or a tag with `<` or `>` inside an attribute value --
#       the page is split on those two characters, not parsed.
# =====================================================================================
_hidden_reasons() {
    _missing_rows "$1" | tr '<' '\n' \
        | grep -i -E "^[a-z][a-z0-9-]*([[:space:]][^>]*)?[[:space:]\"']title[[:space:]]*="
}

# Floor: with no missing cell on the page the lint below holds vacuously.
_n_cells="$(_count "$(_missing_cells "${SEED}/reference.html")")"
_pass_if "reference: the page still demonstrates a missing cell (floor, found ${_n_cells})" \
    "no element carries the class missing" [ "${_n_cells}" -ge 1 ]
assert_equals "reference: no row holding a missing value carries a title attribute" "0" \
    "$(_count "$(_hidden_reasons "${SEED}/reference.html")")"
# Red control, same function. The named fault is THREE hidden reasons, not merely "some".
assert_equals "control: the v1 reference hides exactly three reasons" "3" \
    "$(_count "$(_hidden_reasons "${V1}/reference.html")")"

# Each spelling below passed the first cut of this lint. One mutated cell each, on a
# copy of the live page; the expected count is 1 unless stated.
_cell='<td class="missing">—</td>'
_n_spellings=0
while IFS='|' read -r _name _expect _replacement; do
    [ -n "${_name}" ] || continue
    _n_spellings=$((_n_spellings + 1))
    _replace "${_cell}" "${_replacement}" "${SEED}/reference.html" "${SCRATCH}/spell.html" first
    if _changed "${SEED}/reference.html" "${SCRATCH}/spell.html"; then
        assert_equals "lint 1 sees: ${_name}" "${_expect}" \
            "$(_count "$(_hidden_reasons "${SCRATCH}/spell.html")")"
    else
        _record_fail "lint 1 sees: ${_name}" "the mutation changed nothing; the cell is vacuous"
    fi
done <<'SPELLINGS'
an uppercase TITLE|1|<td class="missing" TITLE="no price">—</td>
a single-quoted title|1|<td class="missing" title='no price'>—</td>
no space before title|1|<td class="missing"title="no price">—</td>
title before class|1|<td title="no price" class="missing">—</td>
a single-quoted class|1|<td class='missing' title="no price">—</td>
an unquoted class|1|<td class=missing title="no price">—</td>
a second class token|1|<td class="num missing" title="no price">—</td>
a title on a descendant|1|<td class="missing"><abbr title="no price">—</abbr></td>
a title on a custom element|1|<td class="missing"><x-tip title="no price">—</x-tip></td>
visible text that mentions a title|0|<td class="missing">— no title = unknown</td>
a data-title attribute|0|<td class="missing" data-title="x">—</td>
SPELLINGS
assert_equals "lint 1: every spelling cell ran (floor)" "11" "${_n_spellings}"

# The three class cells above change ONE cell of three, so the other two keep the row in
# the population and the quoting is never what decides it: reverting the class pattern to
# double quotes only left all of them green. Here EVERY cell carries the quoting, so the
# row is in the population only if that quoting is recognised.
_n_quotings=0
while IFS='|' read -r _name _plain _titled; do
    [ -n "${_name}" ] || continue
    _n_quotings=$((_n_quotings + 1))
    _replace "${_cell}" "${_plain}" "${SEED}/reference.html" "${SCRATCH}/quote-all.html"
    _replace "${_plain}" "${_titled}" "${SCRATCH}/quote-all.html" "${SCRATCH}/quote.html" first
    if _changed "${SEED}/reference.html" "${SCRATCH}/quote-all.html" \
        && _changed "${SCRATCH}/quote-all.html" "${SCRATCH}/quote.html"; then
        assert_equals "lint 1 population holds: ${_name}" "3" \
            "$(_count "$(_missing_cells "${SCRATCH}/quote.html")")"
        assert_equals "lint 1 sees a title behind: ${_name}" "1" \
            "$(_count "$(_hidden_reasons "${SCRATCH}/quote.html")")"
    else
        _record_fail "lint 1 population holds: ${_name}" "a mutation changed nothing; the cell is vacuous"
    fi
done <<'QUOTINGS'
a single-quoted class on every cell|<td class='missing'>—</td>|<td class='missing' title="no price">—</td>
an unquoted class on every cell|<td class=missing>—</td>|<td class=missing title="no price">—</td>
a second class token on every cell|<td class="num missing">—</td>|<td class="num missing" title="no price">—</td>
QUOTINGS
assert_equals "lint 1: every quoting cell ran (floor)" "3" "${_n_quotings}"

sed 's#<tr><td>Delta Health</td>#<tr title="no price"><td>Delta Health</td>#' \
    "${SEED}/reference.html" > "${SCRATCH}/rowtitle.html"
if _changed "${SEED}/reference.html" "${SCRATCH}/rowtitle.html"; then
    assert_equals "lint 1 sees: a title on the row itself" "1" \
        "$(_count "$(_hidden_reasons "${SCRATCH}/rowtitle.html")")"
else
    _record_fail "lint 1 sees: a title on the row itself" "the mutation changed nothing"
fi

# =====================================================================================
# LINT 2 -- the reference page's own prose does not teach a hidden channel.
# POPULATION: the whole file, flattened, so a phrase split across lines is still seen.
# SEES: the words hover, tooltip, mouseover. A page can show the right thing and still
#       describe the wrong one; the caption is what a reader quotes.
# ALSO FIRES on a CSS :hover rule. The page has none; that is the safe direction.
# =====================================================================================
_ref_teaches_hidden() { tr '\n\t' '  ' < "$1" | grep -q -i -E 'hover|tooltip|mouseover'; }

_fail_if "reference: the prose does not describe a hidden channel" \
    "$(grep -n -i -E 'hover|tooltip|mouseover' "${SEED}/reference.html" | head -3)" \
    _ref_teaches_hidden "${SEED}/reference.html"
_pass_if "control: the v1 reference prose does teach hover" "lint cannot see the v1 fault" \
    _ref_teaches_hidden "${V1}/reference.html"
# v1 says only "hover", so it holds one word of three. Each word gets its own page.
_n_words=0
while IFS= read -r _word; do
    [ -n "${_word}" ] || continue
    _n_words=$((_n_words + 1))
    _replace "the status says why" "a ${_word} says why" \
        "${SEED}/reference.html" "${SCRATCH}/word.html" first
    if _changed "${SEED}/reference.html" "${SCRATCH}/word.html"; then
        _pass_if "lint 2 sees: ${_word}" "the page teaches ${_word} and the lint passed it" \
            _ref_teaches_hidden "${SCRATCH}/word.html"
    else
        _record_fail "lint 2 sees: ${_word}" "the mutation changed nothing; the cell is vacuous"
    fi
done <<'WORDS'
hover
tooltip
mouseover
WORDS
assert_equals "lint 2: every word cell ran (floor)" "3" "${_n_words}"

# =====================================================================================
# LINT 3 -- a row with a missing value says why, in words, in that row.
# POPULATION: the same rows as lint 1.
# SEES: two letters together in a status pill in the row, or inside the missing cell.
#       Entities are removed first, so `&mdash;` is a glyph and not a word.
# DOES NOT SEE: whether the words are a good reason (`NaN` counts); whether the element
#       holding them is shown (a pill carrying `hidden` or display:none counts); a
#       missing value in a card outside any table; or a `<` or `>` inside an attribute
#       value, which makes attribute text read as element text.
# v1 PASSES this lint (its row already had the pill), so the v1 fixture is no control
# here; the controls are mutated copies of the live page.
# =====================================================================================
_rows_missing_without_words() {
    _missing_rows "$1" | sed -E 's/&[A-Za-z0-9#]+;//g' \
        | grep -v -i -E "${_PILL_TAG}[^<]*[A-Za-z]{2}" \
        | grep -v -i -E "${_MISSING_TAG}[^<]*[A-Za-z]{2}"
}
assert_equals "reference: every row with a missing value carries words in that row" "0" \
    "$(_count "$(_rows_missing_without_words "${SEED}/reference.html")")"

_PILL='<span class="pill warn">Stale price</span>'
# _lint3_control <name> <expected rows> <sed script>
_lint3_control() {
    sed "$3" "${SEED}/reference.html" > "${SCRATCH}/lint3.html"
    if _changed "${SEED}/reference.html" "${SCRATCH}/lint3.html"; then
        _l3="$(_rows_missing_without_words "${SCRATCH}/lint3.html")"
        assert_equals "control: $1" "$2" "$(_count "${_l3}")"
    else
        _l3=""
        _record_fail "control: $1" "sed changed nothing; the control is vacuous"
    fi
}
_lint3_control "a row stripped of its words is reported, and only that row" "1" \
    "s#${_PILL}##"
assert_contains "control: the reported row is the one that was mutated" "Delta Health" "${_l3}"
# Holds the in-cell branch: with the pill gone, words in the cell are the only reason.
_lint3_control "words inside the missing cell count as the reason" "0" \
    "s#${_PILL}##; s#<td class=\"missing\">—</td>#<td class=\"missing\">— no price</td>#"
# An entity name is letters, and is not a word.
_lint3_control "a glyph written as an entity is not words" "1" \
    "s#${_PILL}##; s#<td class=\"missing\">—</td>#<td class=\"missing\">\\&mdash;</td>#"

# =====================================================================================
# LINT 4 -- the styleguide prescribes a visible reason and states the placement rule.
# POPULATION: the `| **Missing** |` row of the states table, and the rule paragraph
#       (from its bold lead to the next blank line, flattened).
# SEES: the row's positive phrase; hidden or distant channels and negations named in
#       the row (`note` also covers footnote); and each clause of the rule, so the body
#       cannot be deleted or inverted behind an intact lead sentence.
# DOES NOT SEE: meaning. A rewording that keeps every pinned phrase and names no listed
#       word passes -- "once the cell has focus" does.
# =====================================================================================
_sg_missing_row() { grep -E '^\|[[:space:]]*\*\*Missing\*\*' "$1"; }
_sg_row_names_hidden() {
    _sg_missing_row "$1" | grep -q -i -E 'title|tooltip|hover|note|legend|invisible|not visible|never'
}
_sg_row_says_visible_in_unit() {
    _sg_missing_row "$1" | grep -q -i -E '(^|[^a-z])visible in the same row, card or field'
}
_sg_rule() {
    awk '/^\*\*A state is only treated where the reader meets the value\.\*\*/ { on = 1 }
         on && /^[ \t]*$/ { exit }
         on { printf "%s ", $0 }' "$1"
}
_sg_rule_has() { _sg_rule "$1" | grep -q -F -- "$2"; }

assert_equals "styleguide: the states table has exactly one Missing row (floor)" "1" \
    "$(_count "$(_sg_missing_row "${SEED}/styleguide.md")")"
_fail_if "styleguide: the Missing treatment names no hidden channel" \
    "$(_sg_missing_row "${SEED}/styleguide.md")" _sg_row_names_hidden "${SEED}/styleguide.md"
_pass_if "styleguide: the Missing treatment is visible in the same row, card or field" \
    "$(_sg_missing_row "${SEED}/styleguide.md")" _sg_row_says_visible_in_unit "${SEED}/styleguide.md"
_pass_if "control: the v1 styleguide names a hidden channel" "lint cannot see the v1 fault" \
    _sg_row_names_hidden "${V1}/styleguide.md"
_fail_if "control: the v1 styleguide does not say visible in the unit" "lint passes on v1" \
    _sg_row_says_visible_in_unit "${V1}/styleguide.md"

# Rows that must be rejected. Each replaces the live row's treatment in a copy.
# `by` says which check has to do the rejecting. A row that also LACKS the positive
# phrase is rejected for that alone, so it never consults the word list: the first cut
# of these cells passed with the list cut to two words. Rows marked `words` therefore
# KEEP the positive phrase, and only the word list can reject them.
_n_rows=0
while IFS='|' read -r _name _by _treatment; do
    [ -n "${_name}" ] || continue
    _n_rows=$((_n_rows + 1))
    awk -v t="${_treatment}" '/^\|[ \t]*\*\*Missing\*\*/ { n = split($0, c, "|")
            print "|" c[2] "|" c[3] "| " t " |"; next } { print }' \
        "${SEED}/styleguide.md" > "${SCRATCH}/row.md"
    if ! _changed "${SEED}/styleguide.md" "${SCRATCH}/row.md"; then
        _record_fail "lint 4 rejects a row saying: ${_name}" "the mutation changed nothing"
        continue
    fi
    case "${_by}" in
        words)
            _pass_if "lint 4 row still carries the positive phrase: ${_name}" \
                "the row lost the phrase, so the word list is not what is tested" \
                _sg_row_says_visible_in_unit "${SCRATCH}/row.md"
            _pass_if "lint 4 rejects, by its word list, a row saying: ${_name}" \
                "$(_sg_missing_row "${SCRATCH}/row.md")" _sg_row_names_hidden "${SCRATCH}/row.md"
            ;;
        phrase)
            _fail_if "lint 4 rejects, by its positive phrase, a row saying: ${_name}" \
                "$(_sg_missing_row "${SCRATCH}/row.md")" _sg_row_says_visible_in_unit "${SCRATCH}/row.md"
            ;;
        *)  _record_fail "lint 4 rejects a row saying: ${_name}" "unknown check '${_by}'" ;;
    esac
done <<'ROWS'
invisible|phrase|the reason may stay invisible in the same row, card or field
the v1 prescription|phrase|`—` in `--value-missing`, with a title attribute saying why
a title|words|the reason in words, visible in the same row, card or field, or in a `title`
a tooltip|words|the reason in words, visible in the same row, card or field, or in a tooltip
hover|words|the reason in words, visible in the same row, card or field, or on hover
a footnote|words|the reason in words, visible in the same row, card or field, or in a footnote
a note below the table|words|the reason in words, visible in the same row, card or field, or in a note below the table
a legend|words|the reason in words, visible in the same row, card or field, or in a legend
not visible|words|the reason in words, visible in the same row, card or field when not visible elsewhere
never visible|words|the reason in words, never visible in the same row, card or field
ROWS
assert_equals "lint 4: every row cell ran (floor)" "10" "${_n_rows}"

_n_clauses=0
while IFS= read -r _clause; do
    [ -n "${_clause}" ] || continue
    _n_clauses=$((_n_clauses + 1))
    _pass_if "styleguide: the placement rule says: ${_clause}" "clause absent from the rule paragraph" \
        _sg_rule_has "${SEED}/styleguide.md" "${_clause}"
    _fail_if "control: the v1 styleguide has no rule saying: ${_clause}" "lint passes on v1" \
        _sg_rule_has "${V1}/styleguide.md" "${_clause}"
done <<'CLAUSES'
A state is only treated where the reader meets the value
the smallest unit that holds the value
the row of a table, the card, the field
`title` attribute
footnote
legend
none of them treats the state
CLAUSES
assert_equals "lint 4: every clause cell ran (floor)" "7" "${_n_clauses}"

# =====================================================================================
# LINT 5 -- every statement of the preset version agrees, and it is not v1.
# POPULATION: every file under the seed. Keyed on the SPELLING of a version statement,
# not on a list of files: the first enumeration found five sites and there were six.
# SEES: `version: N`, `"version": N`, `version:N`, `preset vN`.
# DOES NOT SEE: other spellings -- `Version: N`, `version = N`, `Preset version N`.
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
_pass_if "version: at least five sites state the preset version (floor, found ${_n_sites})" \
    "${_sites}" [ "${_n_sites}" -ge 5 ]
assert_equals "version: every site states the same version" "1" "$(_count "$(_seed_versions "${SEED}")")"
_ver="$(_seed_versions "${SEED}" | head -1)"
assert_equals "version: the sites agree with tokens.json" \
    "$(jq -r '.version' "${SEED}/tokens.json")" "${_ver}"
case "${_ver}" in
    ''|*[!0-9]*|0*) _record_fail "version: the amended guidance is not labelled v1" "not a version: '${_ver}'" ;;
    1) _record_fail "version: the amended guidance is not labelled v1" "the seed still says 1" ;;
    *) _record_pass "version: the amended guidance is not labelled v1" ;;
esac

# Red control, same function: revert ONE site in a copy and the disagreement is reported.
cp -R "${SEED}" "${SCRATCH}/seed-drift"
sed -E 's/preset v[0-9]+/preset v1/' "${SEED}/styleguide.md" > "${SCRATCH}/seed-drift/styleguide.md"
if _changed "${SEED}/styleguide.md" "${SCRATCH}/seed-drift/styleguide.md"; then
    _record_pass "control: the mutation reverted one version site"
    assert_equals "control: one drifted site yields two distinct versions" "2" \
        "$(_count "$(_seed_versions "${SCRATCH}/seed-drift")")"
else
    _record_fail "control: the mutation reverted one version site" "sed changed nothing; the control is vacuous"
fi

# =====================================================================================
# LINT 6 -- regenerating tokens.json keeps the version the ADOPTER holds.
# Adoption deletes the adopter's copy of ADOPT.md, so whoever regenerates reads the
# plugin's CURRENT file. A version written into that snippet is therefore stamped onto
# every earlier adopter: measured, a v1 adopter's tokens.json came out as version 2.
# POPULATION: the ```bash fence in ADOPT.md that regenerates tokens.json, run whole, in
#       each shell a reader might paste it into.
# SEES: the version and preset written, the token maps, and what a failure leaves behind.
# =====================================================================================
# _adopt_fence <file> <needle> -- the body of the first ```bash fence containing needle.
_adopt_fence() {
    awk -v needle="$2" '
        /^```bash[ \t]*$/ { infence = 1; body = ""; next }
        infence && /^```[ \t]*$/ { if (index(body, needle)) { printf "%s", body; exit }
                                   infence = 0; next }
        infence { body = body $0 "\n" }' "$1"
}
# _make_adopter <dir> <version> [preset] -- a project holding the seed at that version.
# The adopted.json line is lifted from ADOPT.md, the file that writes it, not retyped.
# The adopter has EDITED tokens.css and not yet tokens.json, which is the state the
# fence exists for. When the two started out equal, a fence that wrote nothing passed
# every positive cell: with its `mv` deleted, only the controls failed.
_EDIT_FROM='--space-1: 4px;'
_EDIT_TO='--space-1: 5px;'
_make_adopter() {
    rm -rf "$1"; mkdir -p "$1/design"
    _replace "${_EDIT_FROM}" "${_EDIT_TO}" "${SEED}/tokens.css" "$1/design/tokens.css" first
    sed -E "s/\"version\": [0-9]+/\"version\": $2/" "${SEED}/tokens.json" > "$1/design/tokens.json"
    grep -E '^\{"preset": ' "${SEED}/ADOPT.md" | head -1 \
        | sed -E "s/\"version\": [0-9]+/\"version\": $2/; s/\\\$\(date[^)]*\)/2026-09-20/" \
        | sed -E "s/\"preset\": \"[^\"]*\"/\"preset\": \"${3:-quiet-dense}\"/" \
        > "$1/design/adopted.json"
}
# What tokens.json must hold after a regeneration: the shipped maps, with the edit.
_expected_maps() { jq -S -c '{light, dark} | .light["--space-1"] = "5px"' "${SEED}/tokens.json"; }
_maps() { jq -S -c '{light, dark}' "$1" 2>/dev/null; }
# _regen <adopt.md> <adopter dir> <shell> -- run the fence; print the version it wrote.
# The exit code goes to a FILE: callers read the version through $( ), which is a
# subshell, so a variable set here would never reach them. stdin is /dev/null because
# some callers sit inside a heredoc-fed loop, and a child that read stdin would eat
# the loop's remaining lines.
_regen() {
    # $4, when given, is one line run before the fence: the reader's own shell options.
    printf '%s\n' "${4:-:}" > "${SCRATCH}/regen.sh"
    _adopt_fence "$1" 'design/tokens.json' >> "${SCRATCH}/regen.sh"
    ( cd "$2" && "$3" "${SCRATCH}/regen.sh" ) > "${SCRATCH}/regen.out" 2>&1 < /dev/null
    echo "$?" > "${SCRATCH}/regen.rc"
    jq -r '.version' "$2/design/tokens.json" 2>/dev/null
}
_regen_rc() { cat "${SCRATCH}/regen.rc" 2>/dev/null; }
# _assert_refuses <shell> <adopter dir> <what> -- the fence must exit non-zero AND leave
# tokens.json byte-identical. Two cells, because each alone is satisfiable by a fault:
# a fence that fails after writing, or one that writes nothing and reports success.
_assert_refuses() {
    cp "$2/design/tokens.json" "${SCRATCH}/before.json"
    _regen "${SEED}/ADOPT.md" "$2" "$1" >/dev/null
    _rc="$(_regen_rc)"
    case "${_rc}" in
        ''|*[!0-9]*) _record_fail "regen ($1): $3: the fence fails" "no exit code was recorded" ;;
        0) _record_fail "regen ($1): $3: the fence fails" \
               "rc=0, wrote $(jq -c '{preset, version}' "$2/design/tokens.json" 2>/dev/null)" ;;
        *) _record_pass "regen ($1): $3: the fence fails" ;;
    esac
    _pass_if "regen ($1): $3: tokens.json is left byte-identical" "tokens.json was rewritten" \
        cmp -s "${SCRATCH}/before.json" "$2/design/tokens.json"
}
# _bad_record_cells <shell> -- a record that EXISTS and cannot be used. `jq --slurpfile`
# reads an empty file as zero documents, so the first cut exited 0 on every one of these
# and wrote null into the two fields the fence exists to protect.
_bad_record_cells() {
    local _n=0 _name _content
    while IFS='|' read -r _name _content; do
        [ -n "${_name}" ] || continue
        _n=$((_n + 1))
        _make_adopter "${SCRATCH}/bad" 1
        case "${_content}" in
            @EMPTY)  : > "${SCRATCH}/bad/design/adopted.json" ;;
            @SPACES) printf '  \n' > "${SCRATCH}/bad/design/adopted.json" ;;
            *)       printf '%s\n' "${_content}" > "${SCRATCH}/bad/design/adopted.json" ;;
        esac
        _assert_refuses "$1" "${SCRATCH}/bad" "adopted.json is ${_name}"
    done <<'RECORDS'
empty|@EMPTY
whitespace only|@SPACES
an empty object|{}
missing its version|{"preset":"loud-airy","notes":"mine"}
missing its preset|{"version":1}
carrying a null version|{"preset":"quiet-dense","version":null}
carrying a string version|{"preset":"quiet-dense","version":"1"}
an array|[{"preset":"quiet-dense","version":1}]
two records|{"preset":"quiet-dense","version":1} {"preset":"quiet-dense","version":2}
not JSON|preset: quiet-dense
RECORDS
    assert_equals "regen ($1): every bad-record cell ran (floor)" "10" "${_n}"
}

_regen_src="$(_adopt_fence "${SEED}/ADOPT.md" 'design/tokens.json')"
assert_contains "regen: the fence extracted is the one that regenerates tokens.json" "jq -Rn" "${_regen_src}"
assert_not_contains "regen: the fence extracted is not the adoption block" "cp -Rn" "${_regen_src}"
_make_adopter "${SCRATCH}/probe" 1 loud-airy
assert_json_valid "regen: the simulated adopted.json is valid JSON" "${SCRATCH}/probe/design/adopted.json"
assert_equals "regen: the simulated adopted.json records what was asked for" \
    '{"preset":"loud-airy","version":1}' \
    "$(jq -c '{preset, version}' "${SCRATCH}/probe/design/adopted.json" 2>/dev/null)"
_pass_if "regen: the simulated adopter has edited tokens.css" "the edit changed nothing" \
    _changed "${SEED}/tokens.css" "${SCRATCH}/probe/design/tokens.css"
_fail_if "regen: the simulated adopter's tokens.json is stale" "it already holds the edit" \
    [ "$(_maps "${SCRATCH}/probe/design/tokens.json")" = "$(_expected_maps)" ]

_n_shells=0
for _sh in bash zsh; do
    if ! command -v "${_sh}" >/dev/null 2>&1; then
        echo "  SKIP: ${_sh} is not installed; the regenerate fence was not run under it"
        continue
    fi
    _n_shells=$((_n_shells + 1))

    # The preset is NOT the shipped one, so a fence that states a preset of its own fails.
    _make_adopter "${SCRATCH}/a1" 1 loud-airy
    _got="$(_regen "${SEED}/ADOPT.md" "${SCRATCH}/a1" "${_sh}")"
    assert_equals "regen (${_sh}): the fence exits 0" "0" "$(_regen_rc)"
    assert_equals "regen (${_sh}): a v1 adopter keeps version 1" "1" "${_got}"
    assert_equals "regen (${_sh}): the adopter's preset name is kept" "loud-airy" \
        "$(jq -r '.preset' "${SCRATCH}/a1/design/tokens.json" 2>/dev/null)"
    assert_not_empty "regen (${_sh}): the token maps were written" "$(_maps "${SCRATCH}/a1/design/tokens.json")"
    assert_equals "regen (${_sh}): the token maps follow the edited tokens.css" \
        "$(_expected_maps)" "$(_maps "${SCRATCH}/a1/design/tokens.json")"
    _fail_if "regen (${_sh}): a successful run leaves no temporary file" "tokens.json.new remains" \
        [ -e "${SCRATCH}/a1/design/tokens.json.new" ]

    _make_adopter "${SCRATCH}/a2" 2
    assert_equals "regen (${_sh}): a v2 adopter keeps version 2" "2" \
        "$(_regen "${SEED}/ADOPT.md" "${SCRATCH}/a2" "${_sh}")"

    # A refused run leaves tokens.json.new behind. Under noclobber a plain `>` then
    # refuses to overwrite it, and every later run fails until the reader deletes it.
    _make_adopter "${SCRATCH}/a7" 1
    : > "${SCRATCH}/a7/design/tokens.json.new"
    _got="$(_regen "${SEED}/ADOPT.md" "${SCRATCH}/a7" "${_sh}" 'set -o noclobber')"
    assert_equals "regen (${_sh}): a leftover temporary file does not block a run under noclobber" \
        "0" "$(_regen_rc)"
    assert_equals "regen (${_sh}): that run wrote the edited tokens" \
        "$(_expected_maps)" "$(_maps "${SCRATCH}/a7/design/tokens.json")"

    _make_adopter "${SCRATCH}/a3" 1
    rm -f "${SCRATCH}/a3/design/adopted.json"
    _assert_refuses "${_sh}" "${SCRATCH}/a3" "adopted.json is absent"

    _bad_record_cells "${_sh}"

    # No tokens.css: awk fails, but a pipeline reports only its LAST command, so jq
    # must notice for itself that it read nothing.
    _make_adopter "${SCRATCH}/a5" 1
    rm -f "${SCRATCH}/a5/design/tokens.css"
    _assert_refuses "${_sh}" "${SCRATCH}/a5" "tokens.css is absent"

    # ONE theme empty. With both absent, a guard written `and` refuses just as well.
    _make_adopter "${SCRATCH}/a6" 1
    cp "${SCRATCH}/a6/design/tokens.css" "${SCRATCH}/a6-full.css"
    awk '/^:root\[data-theme="dark"\] \{/ { skip = 1 }
         !skip { print }
         skip && /^\}/ { skip = 0 }' "${SCRATCH}/a6-full.css" > "${SCRATCH}/a6/design/tokens.css"
    if _changed "${SCRATCH}/a6-full.css" "${SCRATCH}/a6/design/tokens.css"; then
        _assert_refuses "${_sh}" "${SCRATCH}/a6" "tokens.css has no dark block"
    else
        _record_fail "regen (${_sh}): tokens.css has no dark block: the fence fails" \
            "the dark block was not removed; the cell is vacuous"
    fi

    # Red control, same function: restore the hardcoded version in a copy of ADOPT.md.
    sed -E 's/version:[^,]*,/version:2,/' "${SEED}/ADOPT.md" > "${SCRATCH}/ADOPT-hardcoded.md"
    if _changed "${SEED}/ADOPT.md" "${SCRATCH}/ADOPT-hardcoded.md"; then
        _make_adopter "${SCRATCH}/a4" 1
        assert_equals "control (${_sh}): a hardcoded version restamps a v1 adopter as 2" "2" \
            "$(_regen "${SCRATCH}/ADOPT-hardcoded.md" "${SCRATCH}/a4" "${_sh}")"
    else
        _record_fail "control (${_sh}): a hardcoded version restamps a v1 adopter as 2" \
            "sed changed nothing; the control is vacuous"
    fi
done
_pass_if "regen: the fence ran under at least one shell (floor, ran ${_n_shells})" \
    "no shell was available" [ "${_n_shells}" -ge 1 ]

print_summary
