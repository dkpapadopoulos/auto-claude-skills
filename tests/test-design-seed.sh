#!/usr/bin/env bash
# test-design-seed.sh — the shipped design seed (assets/design-seed/) and its routing hint.
#
# Every cell here pins an acceptance scenario from
# openspec/changes/design-seed-capability/specs/design-foundations/spec.md.
#
# The load-bearing one is TL-1-on-a-matching-literal: a raw value that EQUALS a token's
# value must still fail, because a literal does not follow a theme change. If that cell
# ever passes-by-accident the lint has been reduced to a value checker, which enforces
# nothing.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-design-seed.sh ==="

SEED="${PROJECT_ROOT}/assets/design-seed"
FIX="${PROJECT_ROOT}/tests/fixtures/design-seed/sample-project"
LINT="${SEED}/checks/token-lint.sh"

# --- files exist -------------------------------------------------------------------
for f in tokens.css tokens.json styleguide.md reference.html ADOPT.md checks/token-lint.sh; do
    assert_file_exists "seed ships ${f}" "${SEED}/${f}"
done
assert_file_exists "method doc exists" "${PROJECT_ROOT}/docs/design-seed-method.md"
assert_file_exists "lint fixture: clean" "${FIX}/clean.css"
assert_file_exists "lint fixture: violation" "${FIX}/violation.css"

# --- Scenario: the lint never reports clean when it could not read its own work files --
# Found 2026-10-01 running the lint under a sandbox profile that let it WRITE its work
# directory but not READ it: `done < "${_LIST}"` failed to open, the loop ran zero
# times, and the lint printed "clean" and exited 0 over a file holding a literal. The
# header promises the opposite. Reproduced here with the same mechanism; skipped where
# there is no sandbox-exec, with a reason, never passed.
if [ -x /usr/bin/sandbox-exec ]; then
    _wd="$(mktemp -d "${TMPDIR:-/tmp}/tl-unreadable.XXXXXX")"
    _wd="$(cd "${_wd}" && pwd -P)"
    _work="${_wd}/work"; mkdir -p "${_work}"
    _deny="(version 1)(allow default)(deny file-read-data (subpath \"${_work}\"))"
    _out="$(cd "${FIX}" && TMPDIR="${_work}" /usr/bin/sandbox-exec -p "${_deny}" /bin/bash "${LINT}" violation.css 2>&1)"; _rc=$?
    assert_equals "lint exits 3 when its work files cannot be read back" "3" "${_rc}"
    assert_not_contains "lint does not say clean when it could not look" "token-lint: clean" "${_out}"
    assert_contains "lint says the scan was not run" "NOT run" "${_out}"
    _out="$(cd "${FIX}" && TMPDIR="${_work}" /usr/bin/sandbox-exec -p "(version 1)(allow default)" /bin/bash "${LINT}" violation.css 2>&1)"; _rc=$?
    assert_equals "control: the same run with reads allowed finds the violation" "1" "${_rc}"
    # The per-file declarations list is read back too, behind the first guard: deny
    # that file alone, and the scan must say INCOMPLETE rather than clean.
    _deny_lines="(version 1)(allow default)(deny file-read-data (regex #\"/lines$\"))"
    _out="$(cd "${FIX}" && TMPDIR="${_work}" /usr/bin/sandbox-exec -p "${_deny_lines}" /bin/bash "${LINT}" violation.css 2>&1)"; _rc=$?
    assert_equals "lint exits 3 when a file's declarations cannot be read back" "3" "${_rc}"
    assert_contains "lint says that scan was incomplete" "INCOMPLETE" "${_out}"
    assert_not_contains "lint does not say clean over unread declarations" "token-lint: clean" "${_out}"
    rm -rf "${_wd}"
else
    echo "SKIP: no /usr/bin/sandbox-exec; the unreadable work directory was not exercised"
fi

# --- Scenario: token definitions cannot drift between formats ----------------------
# Derive the CSS side the same way ADOPT.md documents, then compare to the JSON side.
_css_tokens() {
    awk '
      /^:root \{/                      { b="light"; next }
      /^:root\[data-theme="dark"\] \{/  { b="dark";  next }
      /^\}/                            { b=""; next }
      b != "" && /^[ \t]*--/ {
        l=$0; sub(/^[ \t]*/,"",l); i=index(l,":")
        n=substr(l,1,i-1); v=substr(l,i+1); sub(/;[ \t]*$/,"",v)
        gsub(/^[ \t]+|[ \t]+$/,"",v)
        printf "%s|%s|%s\n", b, n, v }' "${SEED}/tokens.css" | sort
}
_json_tokens() {
    jq -r '(.light | to_entries[] | "light|\(.key)|\(.value)"),
           (.dark  | to_entries[] | "dark|\(.key)|\(.value)")' "${SEED}/tokens.json" | sort
}
assert_equals "tokens.css and tokens.json hold identical names and values" \
    "" "$(diff <(_css_tokens) <(_json_tokens) | head -20)"
assert_not_empty "the token set is not empty (a vacuous parity pass)" "$(_css_tokens)"
# Roles, not only scales — the distinction the styleguide rests on.
for role in --text-numeric --value-missing --status-block-fg --status-hold-fg --surface-page; do
    assert_contains "tokens define role ${role}" "${role}" "$(cat "${SEED}/tokens.css")"
done

# --- Scenario: seed carries no framework dependency ---------------------------------
_dep_files="$(find "${SEED}" -maxdepth 2 \( -name 'package.json' -o -name '*.lock' \
    -o -name 'package-lock.json' -o -name 'yarn.lock' -o -name 'vite.config.*' \
    -o -name 'tailwind.config.*' \) 2>/dev/null)"
assert_equals "no package manifest, lockfile or build config in the seed" "" "${_dep_files}"
assert_not_contains "reference page loads nothing remote" "http" "$(grep -E 'src=|href=' "${SEED}/reference.html")"

# --- Scenario: reference page shows the states that are hard to get right -----------
_ref="$(cat "${SEED}/reference.html")"
assert_contains "reference: dense numerics use tabular figures" "tabular-nums" "${_ref}"
assert_contains "reference: missing value has its own role token" "--value-missing" "${_ref}"
assert_contains "reference: an empty state is a sentence, not a blank box" "empty" "${_ref}"
for st in status-ok status-warn status-block status-hold status-neutral; do
    assert_contains "reference: shows ${st}" "${st}" "${_ref}"
done
assert_contains "reference: exercises the dark theme" 'data-theme' "${_ref}"
# A literal in the reference page would teach exactly the wrong thing.
assert_equals "reference page contains no raw hex colour" "0" \
    "$(grep -c -E '#[0-9a-fA-F]{3,8}[;, )]' "${SEED}/reference.html" | tr -d ' ')"

# --- Scenario: every token has a reader (#361) ----------------------------------------
# The method doc says an unreferenced token is a maintenance cost with no reader, so the
# reference page uses every token but one. --row-comfortable is the alternative density
# (styleguide: pick ONE row height per surface), so using it beside --row-compact on the
# same page would teach the mix the styleguide forbids. The exemption is held to that
# reason: the token must still exist and the styleguide must still name it. Using it in
# the page makes this cell fail, which is the prompt to drop the exemption.
# Comments are stripped first: a token named in a comment has no reader.
_tok_names="$(_css_tokens | cut -d'|' -f2 | sort -u)"
_ref_code="$(perl -0777 -pe 's{/\*.*?\*/}{}gs; s{<!--.*?-->}{}gs' "${SEED}/reference.html")"
assert_contains "control: comment stripping keeps the page's declarations" \
    "var(--surface-page)" "${_ref_code}"
assert_not_contains "control: comment stripping removes the page's comments" \
    "Dependency-free on purpose" "${_ref_code}"
_unref=""
for _n in ${_tok_names}; do
    printf '%s' "${_ref_code}" | grep -qF "var(${_n})" || _unref="${_unref}${_unref:+ }${_n}"
done
assert_equals "every token but the alternative density is referenced by reference.html" \
    "--row-comfortable" "${_unref}"
assert_equals "the token population is not vacuous (>=40 names)" "yes" \
    "$([ "$(printf '%s\n' "${_tok_names}" | grep -c -- '^--')" -ge 40 ] && echo yes || echo no)"
assert_contains "the exempt density is a documented choice in the styleguide" \
    "--row-comfortable" "$(cat "${SEED}/styleguide.md")"

# --- Scenario: the default colours meet the usual WCAG 2 contrast floors (#361) -------
# Contrast is outside token-lint.sh's scope for an adopter's CSS (styleguide.md), but the
# seed's OWN defaults are fixed values this file can measure. A role must work on every
# surface, so each is measured on all three: --value-missing is text (4.5:1) and
# --border-strong is a control boundary (3:1). Values come from tokens.css, the source of
# truth, not from its mirror.
#
# _contrast <fg> <bg> <floor> prints "<ratio to 4 places> <yes|no>". The decision is made
# on the UNROUNDED ratio: WCAG does not round, and comparing a printed 4.50 passed a
# 4.496:1 pair (found in review).
_contrast() {
    awk -v a="$1" -v b="$2" -v f="$3" '
      function hx(s, i) { return index("0123456789abcdef", tolower(substr(s, i, 1))) - 1 }
      function ch(s, i,  c) { c = (hx(s, i) * 16 + hx(s, i + 1)) / 255
                              return c <= 0.04045 ? c / 12.92 : exp(2.4 * log((c + 0.055) / 1.055)) }
      function lum(s) { return 0.2126 * ch(s, 2) + 0.7152 * ch(s, 4) + 0.0722 * ch(s, 6) }
      BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }
              r = (x + 0.05) / (y + 0.05); printf "%.4f %s", r, (r >= f + 0) ? "yes" : "no" }'
}
# _tok_val <theme> <name> prints the value. A dark-theme token absent from the dark block
# inherits its light value, as in CSS, and then prints "<value> inherited" so the cell can
# say so: a deleted dark override is an honest pass, but it should not be a silent one.
_tok_val() {
    _v="$(_css_tokens | awk -F'|' -v t="$1" -v n="$2" '$1 == t && $2 == n { print $3 }')"
    if [ -z "${_v}" ]; then
        _v="$(_css_tokens | awk -F'|' -v n="$2" '$1 == "light" && $2 == n { print $3 }')"
        [ -n "${_v}" ] && [ "$1" != light ] && _v="${_v} inherited"
    fi
    printf '%s' "${_v}"
}
# One hex colour on one line; a token defined twice comes back as two lines.
_is_hex() { [ "$(printf '%s\n' "$1" | wc -l | tr -d ' ')" = 1 ] && printf '%s' "$1" | grep -qE '^#[0-9a-fA-F]{6}$'; }
# The seed has no duplicate token, so without these nothing would notice the line count
# going: grep -q alone accepts a two-line value when either line matches (found in review).
assert_equals "hex control: one colour on one line is measurable" "yes" \
    "$(_is_hex '#aaaaaa' && echo yes || echo no)"
assert_equals "hex control: a token defined twice (two hex lines) is not" "no" \
    "$(_is_hex "$(printf '#aaaaaa\n#bbbbbb')" && echo yes || echo no)"
# Controls, independently computed: two that must pass, two just under 4.5 that must
# fail (the second prints as 4.50 when rounded to two places), and one whose channel is
# in sRGB's linear segment, which every token channel lies above.
assert_equals "contrast control: black on white" "21.0000 yes" "$(_contrast '#000000' '#ffffff' 4.5)"
assert_equals "contrast control: #757575 on white passes 4.5" "4.6075 yes" "$(_contrast '#757575' '#ffffff' 4.5)"
assert_equals "contrast control: #777777 on white fails 4.5" "4.4781 no" "$(_contrast '#777777' '#ffffff' 4.5)"
assert_equals "contrast control: #767776 on white (4.496) fails 4.5" "4.4962 no" "$(_contrast '#767776' '#ffffff' 4.5)"
assert_equals "contrast control: linear segment, #050505 on black" "1.0304 yes" "$(_contrast '#050505' '#000000' 1)"
for _theme in light dark; do
    for _pair in "--value-missing 4.5" "--border-strong 3"; do
        set -- ${_pair}
        for _bgn in --surface-page --surface-raised --surface-sunken; do
            _fg="$(_tok_val "${_theme}" "$1")"; _bg="$(_tok_val "${_theme}" "${_bgn}")"
            _note=""
            case "${_fg} ${_bg}" in *" inherited"*) _note=", a value inherited from light" ;; esac
            _fg="${_fg% inherited}"; _bg="${_bg% inherited}"
            if _is_hex "${_fg}" && _is_hex "${_bg}"; then
                _res="$(_contrast "${_fg}" "${_bg}" "$2")"
            else
                _res="unmeasurable ($(printf '%s' "${_fg:-absent}" | tr '\n' ',') on $(printf '%s' "${_bg:-absent}" | tr '\n' ',')) no"
            fi
            assert_equals "${_theme}: $1 on ${_bgn} meets $2:1 (measured ${_res% *}${_note})" "yes" "${_res##* }"
        done
    done
done

# --- Scenario: a literal matching a token value is still a violation ----------------
_tok_primary="$(jq -r '.light["--text-primary"]' "${SEED}/tokens.json")"
assert_contains "the violation fixture uses a literal equal to --text-primary" \
    "${_tok_primary}" "$(cat "${FIX}/violation.css")"
_out="$(bash "${LINT}" "${FIX}/violation.css" 2>&1)"; _rc=$?
assert_equals "lint fails on a literal that equals a token value" "1" "${_rc}"
assert_contains "lint names a TL- class" "TL-1" "${_out}"
assert_contains "lint names the file and line" "violation.css:4" "${_out}"
assert_contains "lint also catches a typography literal" "TL-2" "${_out}"

# --- Scenario: declared exceptions do not fire --------------------------------------
_out="$(bash "${LINT}" "${FIX}/clean.css" 2>&1)"; _rc=$?
assert_equals "lint passes a file whose covered declarations all reference tokens" "0" "${_rc}"
assert_contains "lint says it was clean" "clean" "${_out}"
# tokens.css defines the literals, so it must never be scanned.
_out="$(bash "${LINT}" "${SEED}/tokens.css" 2>&1)"; _rc=$?
assert_equals "lint never scans tokens.css itself" "0" "${_rc}"
# Scope is declared, not implied.
_help="$(bash "${LINT}" --help 2>&1)"
assert_contains "--help declares the covered properties" "Properties covered" "${_help}"
assert_contains "--help declares what is NOT covered" "Not covered" "${_help}"
assert_contains "--help states the exit codes" "Exit:" "${_help}"
assert_contains "--help documents the cannot-check exit" "3" "${_help}"
assert_contains "--help refuses to report clean when it could not look" "NEVER REPORTS CLEAN" "${_help}"
# --- Comment stripping -------------------------------------------------------------
# The awk state machine is the most intricate code here and was entirely uncovered until
# a reviewer mutation-proved it: replacing it with a passthrough left the suite green.
# These cells fail under that mutation.
_out="$(bash "${LINT}" "${FIX}/comments.css" 2>&1)"; _rc=$?
assert_equals "a real declaration after a closed comment still fires" "1" "${_rc}"
assert_contains "the firing line is the code one" "comments.css:6" "${_out}"
assert_not_contains "a literal INSIDE a multi-line comment does not fire" "comments.css:2" "${_out}"
assert_not_contains "a commented-out font-size does not fire" "comments.css:3" "${_out}"
assert_not_contains "an unterminated comment swallows the rest of the file" "comments.css:9" "${_out}"

# --- Several declarations on one line (all minified CSS) ----------------------------
_out="$(bash "${LINT}" "${FIX}/minified.css" 2>&1)"; _rc=$?
assert_equals "a one-line rule is scanned, not skipped" "1" "${_rc}"
assert_contains "minified: the colour literal is caught" "TL-1" "${_out}"
assert_contains "minified: the later font-size on the same line is caught too" "TL-2" "${_out}"
assert_not_contains "minified: the var() declaration between them is not flagged" "surface-raised" "${_out}"

# --- Declarations, not lines --------------------------------------------------------
# Three measured false results, all from the scanner being line-oriented while CSS is
# not. Each reported CLEAN (or a permanent false positive) before the emitter was
# rewritten to yield one declaration per record.
_probe3="$(mktemp -d "${TMPDIR:-/tmp}/lintdecl.XXXXXX")"
# A minified file is ONE line, so a per-line at-rule skip exempted the whole file.
printf '.a{color:#ff0000}@media(min-width:900px){.b{color:#00ff00}}\n' > "${_probe3}/minmedia.css"
_out="$(bash "${LINT}" "${_probe3}/minmedia.css" 2>&1)"; _rc=$?
assert_equals "minified file containing an at-rule is still scanned" "1" "${_rc}"
assert_equals "both literals are found, inside and outside the at-rule" "2" \
    "$(printf '%s' "${_out}" | grep -c 'TL-1')"
# The at-rule skip must key on a real at-rule, not on the text appearing in a string.
printf '.a::after { content: "@import"; color: #ff0000; }\n' > "${_probe3}/strat.css"
_rc=0; bash "${LINT}" "${_probe3}/strat.css" >/dev/null 2>&1 || _rc=$?
assert_equals "an at-rule name inside a string does not exempt the rule" "1" "${_rc}"
# A declaration split across lines used to be invisible from both halves.
printf '.a {\n  color:\n    #ff0000;\n}\n' > "${_probe3}/multi.css"
_out="$(bash "${LINT}" "${_probe3}/multi.css" 2>&1)"; _rc=$?
assert_equals "a declaration split across lines is caught" "1" "${_rc}"
assert_contains "it is reported at the line the declaration started on" "multi.css:2" "${_out}"
# A data URI's internal ";" must not split the declaration (was a permanent false positive).
printf '.a { background: url("data:image/svg+xml;charset=utf8,%%3Csvg%%3E") no-repeat; }\n' > "${_probe3}/data.css"
_rc=0; bash "${LINT}" "${_probe3}/data.css" >/dev/null 2>&1 || _rc=$?
assert_equals "a data URI in a covered property is not a violation" "0" "${_rc}"
# Shorthands carry non-colour values legitimately, so they fire only on colour-shaped
# ones. Both directions pinned: without the negative cell the lint is unusable in a real
# project; without the positive one the shorthand is simply unchecked.
printf '.a { background: url(/i.png) no-repeat center / cover; border: 1px solid var(--b); }\n' > "${_probe3}/sh.css"
_rc=0; bash "${LINT}" "${_probe3}/sh.css" >/dev/null 2>&1 || _rc=$?
assert_equals "shorthand with no colour in it is not a violation" "0" "${_rc}"
printf '.a { background: #ff0000; border: 1px solid #00ff00; }\n' > "${_probe3}/shbad.css"
_out="$(bash "${LINT}" "${_probe3}/shbad.css" 2>&1)"; _rc=$?
assert_equals "shorthand carrying a colour literal still fires" "1" "${_rc}"
assert_equals "both shorthand literals are reported" "2" "$(printf '%s' "${_out}" | grep -c 'TL-1')"
# @font-face bodies are exempt: font-family there is the point, not a violation.
printf '@font-face { font-family: "Custom"; src: url(/f.woff2); }\n.b { color: var(--x); }\n' > "${_probe3}/ff.css"
_rc=0; bash "${LINT}" "${_probe3}/ff.css" >/dev/null 2>&1 || _rc=$?
assert_equals "@font-face body is exempt" "0" "${_rc}"
# ...but only its own block: a literal after it must still fire.
printf '@font-face { font-family: "Custom"; }\n.b { color: #ff0000; }\n' > "${_probe3}/ff2.css"
_rc=0; bash "${LINT}" "${_probe3}/ff2.css" >/dev/null 2>&1 || _rc=$?
assert_equals "the @font-face exemption ends with its block" "1" "${_rc}"
rm -rf "${_probe3}"

# --- False negatives and false positives a reviewer measured ------------------------
_probe2="$(mktemp -d "${TMPDIR:-/tmp}/lintfp.XXXXXX")"
# A "/*" inside a CSS string used to open a comment and swallow the REST OF THE FILE.
printf '.a::before { content: "/*"; }\n.b { color: #ff0000; }\n' > "${_probe2}/str.css"
_out="$(bash "${LINT}" "${_probe2}/str.css" 2>&1)"; _rc=$?
assert_equals "a comment marker inside a string does not blind the rest of the file" "1" "${_rc}"
assert_contains "the declaration after the string is still scanned" "str.css:2" "${_out}"
# url(...) is an asset reference, not a colour literal.
printf '.a { background: url(/img/hero.png); color: currentcolor; }\n' > "${_probe2}/url.css"
_rc=0; bash "${LINT}" "${_probe2}/url.css" >/dev/null 2>&1 || _rc=$?
assert_equals "url() and lowercase currentcolor are not violations" "0" "${_rc}"
# ...but a literal alongside a url() still fires.
printf '.a { background: url(/img/hero.png) #ffffff; }\n' > "${_probe2}/urlmix.css"
_rc=0; bash "${LINT}" "${_probe2}/urlmix.css" >/dev/null 2>&1 || _rc=$?
assert_equals "a literal next to a url() still fires" "1" "${_rc}"
# Keywords are case-insensitive in CSS.
printf '.a { color: TRANSPARENT; border-color: Inherit; }\n' > "${_probe2}/case.css"
_rc=0; bash "${LINT}" "${_probe2}/case.css" >/dev/null 2>&1 || _rc=$?
assert_equals "keyword exceptions are case-insensitive" "0" "${_rc}"
# Ordinary hand-written one-liners are scanned (they were silently skipped).
printf '.a { color: #ff0000; }\n' > "${_probe2}/oneline.css"
_rc=0; bash "${LINT}" "${_probe2}/oneline.css" >/dev/null 2>&1 || _rc=$?
assert_equals "a single-line rule is scanned" "1" "${_rc}"
rm -rf "${_probe2}"

# --help must print documentation, not the script's own shell source.
assert_not_contains "--help does not leak shell source" "set -u" "${_help}"
assert_not_contains "--help does not leak the usage function" "_SELF_DIR" "${_help}"
assert_contains "--help lists @font-face among ignored at-rules" "@font-face" "${_help}"

# --- Never reports clean when it could not look (exit 3) ----------------------------
# A checker whose failure mode is "clean" passes CI while enforcing nothing. Each cell
# below was a measured silent success before the fix.
_probe="$(mktemp -d "${TMPDIR:-/tmp}/lintprobe.XXXXXX")"
printf '.a { color: #ff0000; }\n' > "${_probe}/plain.css"
cp "${_probe}/plain.css" "${_probe}/noread.css"; chmod 000 "${_probe}/noread.css"
_rc=0; bash "${LINT}" "${_probe}/noread.css" >/dev/null 2>&1 || _rc=$?
assert_equals "an unreadable file exits 3, not 0" "3" "${_rc}"
mkdir -p "${_probe}/ro"; chmod 555 "${_probe}/ro"
_rc=0; TMPDIR="${_probe}/ro" bash "${LINT}" "${_probe}/plain.css" >/dev/null 2>&1 || _rc=$?
assert_equals "an unwritable TMPDIR exits 3, not 0" "3" "${_rc}"
mkdir -p "${_probe}/sub"; cp "${_probe}/plain.css" "${_probe}/sub/"; chmod 000 "${_probe}/sub"
_rc=0; ( cd "${_probe}" && bash "${LINT}" >/dev/null 2>&1 ) || _rc=$?
assert_equals "a failed directory walk exits 3, not 0" "3" "${_rc}"
chmod 755 "${_probe}/sub" 2>/dev/null; chmod 644 "${_probe}/noread.css" 2>/dev/null
# A filename containing a newline must be scanned, not split into two missing files.
_weird="${_probe}/we$(printf '\n')ird.css"
printf '.a { color: #ff0000; }\n' > "${_weird}"
_rc=0; bash "${LINT}" "${_weird}" >/dev/null 2>&1 || _rc=$?
assert_equals "a filename containing a newline is scanned (exit 1, not a silent 0)" "1" "${_rc}"
rm -rf "${_probe}"

# --- Scenario: adopting the default unchanged is a supported outcome ----------------
# The reversed decision: there is NO identity check, and nothing may fail on an
# unmodified seed. Pinned as an absence so re-adding one is a deliberate act.
assert_equals "no identity-pass check ships" "" \
    "$(find "${SEED}/checks" -name 'identity*' 2>/dev/null)"
_adopt="$(cat "${SEED}/ADOPT.md")"
assert_contains "adoption records provenance" "adopted.json" "${_adopt}"
assert_contains "adoption records the preset name" "quiet-dense" "${_adopt}"
assert_contains "adoption points the project's agent instructions at the guide" "AGENTS.md" "${_adopt}"
assert_contains "adoption tells the agent to run the lint" "token-lint.sh" "${_adopt}"
assert_contains "using the default unchanged is stated as supported" "supported outcome" "${_adopt}"
# ADOPT.md states the size of the type scale in words; hold the word to the file (#361).
_nsizes="$(grep -cE '^[[:space:]]*--text-[a-z]+:[[:space:]]*[0-9]+px;' "${SEED}/tokens.css")"
case "${_nsizes}" in
    4) _nword=four ;; 5) _nword=five ;; 6) _nword=six ;; 7) _nword=seven ;; *) _nword="(${_nsizes} sizes: extend this table)" ;;
esac
assert_contains "ADOPT.md's type-scale count matches tokens.css (${_nsizes} sizes)" \
    "the scale is ${_nword} sizes" "${_adopt}"

# --- Scenario: DESIGN hint renders without adding a routed skill --------------------
for cfg in config/default-triggers.json config/fallback-registry.json; do
    _hint="$(jq -r '.methodology_hints[] | select(.name == "design-seed")' "${PROJECT_ROOT}/${cfg}")"
    assert_not_empty "${cfg}: design-seed hint present" "${_hint}"
    assert_contains "${cfg}: hint is scoped to DESIGN" "DESIGN" \
        "$(printf '%s' "${_hint}" | jq -r '.phases | join(",")')"
    assert_contains "${cfg}: hint points at the method" "design-seed-method" \
        "$(printf '%s' "${_hint}" | jq -r '.hint')"
    # Plurals: the singular-only form missed most real UI prompts (measured).
    _tr="$(printf '%s' "${_hint}" | jq -r '.triggers[0]')"
    for _p in "build the react components" "design the screens" "update our design tokens" \
              "polish the dashboards" "add wireframes" "build a styleguide"; do
        if [[ "${_p}" =~ ${_tr} ]]; then _m=yes; else _m=no; fi
        assert_equals "${cfg}: hint fires on '${_p}'" "yes" "${_m}"
    done
    for _p in "fix the failing test" "rename the helper function"; do
        if [[ "${_p}" =~ ${_tr} ]]; then _m=yes; else _m=no; fi
        assert_equals "${cfg}: hint stays quiet on '${_p}'" "no" "${_m}"
    done
    # The whole point of D1: reach without a new routed skill, so no skill entry appears.
    assert_equals "${cfg}: no design-seed SKILL was added (no role-cap competitor)" "0" \
        "$(jq '[.skills[] | select(.name == "design-seed" or .name == "design-system" or .name == "styleguide-foundations")] | length' "${PROJECT_ROOT}/${cfg}")"
done

# --- Styleguide holds only what the lint cannot decide -------------------------------
_sg="$(cat "${SEED}/styleguide.md")"
assert_contains "styleguide covers missing vs empty vs zero" "Missing is not empty" "${_sg}"
assert_contains "styleguide covers numeric display" "tabular-nums" "${_sg}"
assert_contains "styleguide declares what the lint does NOT cover" "so you know what it doesn't" "${_sg}"
# Motion is not tokenised until a screen needs it, but the first motion role must bring its
# reduced-motion block with it, so no screen has to remember to.
assert_contains "styleguide ties the first motion role to a reduced-motion block" \
    'When you add the first one, add a
`prefers-reduced-motion: reduce` block' "${_sg}"
# The tokens.json regeneration and _css_tokens read any column-0 ":root {" as light, so a
# reduced-motion block with an unindented :root would overwrite light values (review M4).
assert_contains "styleguide says to indent :root inside the reduced-motion block" \
    "Nest \`:root\` inside that block and indent it" "${_sg}"

# --- Method: adoption is optional, and moving screens are verified both ways ----------
# D13 (2026-10-27) refused mandatory seed adoption and the pilot did not favour seeded
# builds; step 0 once read "Adopt the seed. Do not start designing screens...".
_md="$(cat "${PROJECT_ROOT}/docs/design-seed-method.md")"
assert_contains "method says adopting the seed is a choice, not a prerequisite" \
    "adopting it is a choice, not a
prerequisite" "${_md}"
assert_contains "method allows skipping the seed only when the project has its own system" \
    "skip it when the project already has its own tokens and styleguide" "${_md}"
assert_not_contains "method no longer mandates the seed" "Adopt the seed" "${_md}"
assert_contains "method verifies moving interactions with reduced motion on and off" \
    "reduced motion on and off" "${_md}"

print_summary
