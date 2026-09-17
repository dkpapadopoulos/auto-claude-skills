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

print_summary
