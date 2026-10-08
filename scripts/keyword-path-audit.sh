#!/bin/bash
# keyword-path-audit.sh — what the routing hook's KEYWORD path admits (#310).
#
# hooks/skill-activation-hook.sh admits a skill by its trigger regexes OR by a plain
# substring match against its `keywords`. The two paths are independent, so a precision
# constraint written into a trigger is absent from the keyword path, and a keyword has no
# word boundary and no case folding of its own. This script measures both, by running the
# real hook; it never evaluates a regex or a substring itself.
#
# Check 1, classes. For every keyword of every skill, with the prompt being the bare
# keyword and the skill renamed so its name cannot admit it:
#   covered       the triggers admit the skill without the keyword
#   keyword-only  the keyword admits it and the triggers do not
#   inert         the keyword does not admit it even alone (it can never fire)
# Every keyword-only and inert keyword needs a row in the decisions ledger, and every row
# must still describe what is measured. So narrowing a trigger until a keyword is left
# admitting on its own fails here until someone decides whether that is wanted.
#
# Check 2, fixture lines. Every line of a keyword-carrying skill's routing fixture goes
# through the hook with the skill's shipped entry. tests/test-regex-fixtures.sh checks
# those lines against the regex only. A NO_MATCH line the hook selects is listed in the
# known-selections file or it fails: this is the check that sees a keyword matching inside
# a longer word, which check 1 cannot (the bare keyword is covered there). A MATCH line
# the hook does not select fails too, so a deleted keyword that was a MATCH prompt's only
# way in is noticed.
#
# LIMITS. Check 1 measures the bare keyword: "covered" says nothing about a prompt in
# which the keyword appears inside another word or after text the trigger forbids. Only
# a fixture decoy shows that, and only for the prompts somebody wrote down. Both checks
# use a registry holding one skill, so they see ADMISSION and nothing else: the 20 points
# a keyword adds can decide which of several admitted skills keeps a slot, and no line
# here changes when it does.
#
# Usage: keyword-path-audit.sh [--skill NAME] [--config FILE] [--hook FILE]
#                              [--fixtures DIR] [--ledger FILE] [--known FILE] [--jobs N]
# Output: tab-separated ROW / DECOY / MATCHLINE / FINDING / DEBT / SUMMARY lines on stdout.
# A skill that carries keywords must have a routing fixture with a MATCH line the hook
# selects; without one its decoys cannot be read and the run exits 3.
# Exit: 0 measured, and both files agree with it
#       1 measured, with findings
#       3 could not measure (never read as clean)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${ROOT}/config/default-triggers.json"
HOOK="${ROOT}/hooks/skill-activation-hook.sh"
FIXTURES="${ROOT}/tests/fixtures/routing"
LEDGER="${ROOT}/tests/fixtures/keyword-path/decisions.tsv"
KNOWN="${ROOT}/tests/fixtures/keyword-path/known-decoy-selections.tsv"
ONLY=""
JOBS=4
SENTINEL="kwprobe-subject"
NONSENSE="zzzz qqqq vvvv"
# What follows a keyword when the bare keyword is a prompt the hook does not score. More
# than twenty characters: the hook's greeting rule still leaves early when twenty or fewer
# follow the greeting.
CARRIER="zzzz qqqq vvvv wwww xxxx"

_cannot() {
    printf 'keyword-path-audit: cannot check: %s\n' "$1" >&2
    exit 3
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --skill|--config|--hook|--fixtures|--ledger|--known|--jobs)
            [ "$#" -ge 2 ] || _cannot "$1 needs a value"
            case "$1" in
                --skill) ONLY="$2" ;;
                --config) CONFIG="$2" ;;
                --hook) HOOK="$2" ;;
                --fixtures) FIXTURES="$2" ;;
                --ledger) LEDGER="$2" ;;
                --known) KNOWN="$2" ;;
                --jobs) JOBS="$2" ;;
            esac
            shift 2 ;;
        *) _cannot "unknown argument: $1" ;;
    esac
done

command -v jq >/dev/null 2>&1 || _cannot "jq is not installed"
# awk reads an operand shaped name=value as an assignment and never opens it.
case "${LEDGER}" in /*) ;; *) LEDGER="./${LEDGER}" ;; esac
case "${KNOWN}" in /*) ;; *) KNOWN="./${KNOWN}" ;; esac
for _f in "${CONFIG}" "${HOOK}" "${LEDGER}" "${KNOWN}"; do
    [ -f "${_f}" ] && [ -r "${_f}" ] || _cannot "not a readable file: ${_f}"
done
# The hook is executed, not handed to whichever bash is first on PATH: its own shebang
# picks the interpreter, as it does when Claude Code runs it.
[ -x "${HOOK}" ] || _cannot "the hook is not executable: ${HOOK}"
[ -d "${FIXTURES}" ] || _cannot "not a directory: ${FIXTURES}"
case "${JOBS}" in ''|*[!0-9]*|0*) _cannot "--jobs needs a positive whole number" ;; esac
[ "${#JOBS}" -le 3 ] || _cannot "--jobs needs a positive whole number"
PLUGIN_ROOT="$(cd "$(dirname "${HOOK}")/.." && pwd)" || _cannot "no directory above the hook"

SKILLS="$(jq -r --arg only "${ONLY}" '
    .skills[] | select((.keywords // []) | length > 0)
    | select($only == "" or .name == $only) | .name' "${CONFIG}" 2>/dev/null)" \
    || _cannot "the config is not readable JSON: ${CONFIG}"
[ -n "${SKILLS}" ] || _cannot "no skill with keywords to measure${ONLY:+ (asked for: ${ONLY})}"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/keyword-path-audit.XXXXXXXX")" || _cannot "no scratch directory"
trap 'rm -rf "${WORK}"' EXIT

# _run <work> <needle> <prompt> <jq filter over the entry> [jq args...]
# Prints 1 when the hook's output names <needle>, 0 when it does not, x when the
# registry or the payload could not be built. Each run gets an empty home.
#
# The payload is a FILE the hook reads from. Piped from jq, a payload that arrived more
# than two seconds late was read by the hook as no prompt at all, and "the hook was given
# nothing" came back as 0, the same answer as "not selected".
_run() {
    local work="$1" needle="$2" prompt="$3" filter="$4" out
    shift 4
    rm -rf "${work:?}/home"
    mkdir -p "${work}/home/.claude"
    if ! jq "$@" --arg sentinel "${SENTINEL}" \
        "{version: \"keyword-path-audit\", skills: [(. | ${filter}) | .available = true | .enabled = true], methodology_hints: [], phase_compositions: {}}" \
        "${work}/entry.json" > "${work}/home/.claude/.skill-registry-cache.json" 2>/dev/null; then
        printf x
        return 0
    fi
    if ! jq -n --arg p "${prompt}" '{prompt: $p}' > "${work}/payload.json" 2>/dev/null || [ ! -s "${work}/payload.json" ]; then
        printf x
        return 0
    fi
    out="$(HOME="${work}/home" CLAUDE_PLUGIN_ROOT="${PLUGIN_ROOT}" "${HOOK}" < "${work}/payload.json" 2>/dev/null)"
    case "${out}" in *"${needle}"*) printf 1 ;; *) printf 0 ;; esac
}

# _audit_skill <skill> <work>: every measurement for one skill, then a DONE line. A job
# that dies leaves no DONE line, and the reader below refuses the whole run.
_audit_skill() {
    local skill="$1" work="$2" fixture keyword alone trig cls prompt sel via tab
    tab="$(printf '\t')"
    mkdir -p "${work}"
    if ! jq -c --arg n "${skill}" '[.skills[] | select(.name == $n)] | if length == 1 then .[0] else error("not exactly one entry") end' \
        "${CONFIG}" > "${work}/entry.json" 2>/dev/null; then
        printf 'BROKEN\t%s\tnot exactly one config entry\n' "${skill}"
        printf 'DONE\t%s\n' "${skill}"
        return 0
    fi
    if ! jq -e '[.keywords[] | select(type != "string" or . == "" or (explode | any(. < 32)))] | length == 0' \
        "${work}/entry.json" >/dev/null 2>&1; then
        printf 'BROKEN\t%s\ta keyword that is not a one-line string, or is empty\n' "${skill}"
        printf 'DONE\t%s\n' "${skill}"
        return 0
    fi

    # The harness has to be able to give both answers for this skill before any of its
    # answers is evidence: a dead hook reads as "nothing is ever selected".
    printf 'CONTROL\t%s\t%s\t%s\t%s\n' "${skill}" \
        "$(_run "${work}" "${SENTINEL}" "${NONSENSE}" '.name = $sentinel')" \
        "$(_run "${work}" "${SENTINEL}" "${SENTINEL}" '.name = $sentinel')" \
        "$(_run "${work}" "${skill}" "${NONSENSE}" '.')"

    jq -r '.keywords[]' "${work}/entry.json" > "${work}/keywords"
    while IFS= read -r keyword; do
        alone="$(_run "${work}" "${SENTINEL}" "${keyword}" '.name = $sentinel | .triggers = [] | .keywords = [$k]' --arg k "${keyword}")"
        trig="$(_run "${work}" "${SENTINEL}" "${keyword}" '.name = $sentinel | .keywords = []')"
        case "${alone}${trig}" in
            0[01]) cls=inert ;;
            11) cls=covered ;;
            10) cls=keyword-only ;;
            *) cls=unmeasured ;;
        esac
        # "Does not admit" has to mean the keyword, not the prompt. The hook leaves early
        # on some prompts (a greeting, under five characters, a leading slash) whatever
        # the registry holds, and a keyword shaped like one would read inert while firing
        # inside a longer prompt. So an inert answer stands only where a trigger that
        # matches anything IS selected: on the bare keyword, or failing that on the
        # keyword followed by nonsense words, where it must still not admit.
        if [ "${cls}" = inert ] && [ "$(_run "${work}" "${SENTINEL}" "${keyword}" '.name = $sentinel | .triggers = [".+"] | .keywords = []')" != 1 ]; then
            if [ "$(_run "${work}" "${SENTINEL}" "${keyword} ${CARRIER}" '.name = $sentinel | .triggers = [".+"] | .keywords = []')" != 1 ] \
                || [ "$(_run "${work}" "${SENTINEL}" "${keyword} ${CARRIER}" '.name = $sentinel | .triggers = [] | .keywords = [$k]' --arg k "${keyword}")" != 0 ]; then
                cls=unmeasured
            fi
        fi
        printf 'ROW\t%s\t%s\t%s\n' "${skill}" "${keyword}" "${cls}"
    done < "${work}/keywords"

    fixture="${FIXTURES}/${skill}.txt"
    if [ ! -f "${fixture}" ]; then
        printf 'BROKEN\t%s\tno routing fixture, so no line of it can be read through the hook\n' "${skill}"
        printf 'DONE\t%s\n' "${skill}"
        return 0
    fi
    sed -n -e 's/^[[:space:]]*MATCH:[[:space:]]*//p' "${fixture}" > "${work}/matches"
    sed -n -e 's/^[[:space:]]*NO_MATCH:[[:space:]]*//p' "${fixture}" > "${work}/decoys"
    if grep -q "${tab}" "${work}/matches" "${work}/decoys"; then
        # Inside a prompt, that is. The lines printed below are tab-separated.
        printf 'BROKEN\t%s\ta fixture prompt holds a tab\n' "${skill}"
        printf 'DONE\t%s\n' "${skill}"
        return 0
    fi
    while IFS= read -r prompt || [ -n "${prompt}" ]; do
        [ -n "${prompt}" ] || continue
        printf 'MATCHLINE\t%s\t%s\t%s\n' "${skill}" "$(_run "${work}" "${skill}" "${prompt}" '.')" "${prompt}"
    done < "${work}/matches"
    while IFS= read -r prompt || [ -n "${prompt}" ]; do
        [ -n "${prompt}" ] || continue
        sel="$(_run "${work}" "${skill}" "${prompt}" '.')"
        via=-
        if [ "${sel}" = 1 ]; then
            # Selected with the keywords removed too: then it is not the keyword path.
            case "$(_run "${work}" "${skill}" "${prompt}" '.keywords = []')" in
                0) via=keywords ;;
                1) via=other ;;
                *) sel=x ;;
            esac
        fi
        printf 'DECOY\t%s\t%s\t%s\t%s\n' "${skill}" "${sel}" "${via}" "${prompt}"
    done < "${work}/decoys"
    # Printed whether or not a MATCH line was found, so a fixture without one is seen.
    printf 'FIXTURE\t%s\n' "${skill}"
    printf 'DONE\t%s\n' "${skill}"
}

_n=0
_running=0
while IFS= read -r _skill; do
    [ -n "${_skill}" ] || continue
    _n=$((_n + 1))
    _audit_skill "${_skill}" "${WORK}/${_n}" > "${WORK}/${_n}.rows" 2>/dev/null &
    _running=$((_running + 1))
    if [ "${_running}" -ge "${JOBS}" ]; then wait; _running=0; fi
done <<EOF
${SKILLS}
EOF
wait

MEASURED="${WORK}/measured.tsv"
: > "${MEASURED}"
_i=0
while IFS= read -r _skill; do
    [ -n "${_skill}" ] || continue
    _i=$((_i + 1))
    [ "$(tail -n 1 "${WORK}/${_i}.rows" 2>/dev/null)" = "DONE	${_skill}" ] \
        || _cannot "the measurement of ${_skill} did not finish"
    cat "${WORK}/${_i}.rows" >> "${MEASURED}"
done <<EOF
${SKILLS}
EOF

# Anything below reads MEASURED only. Refuse before comparing: a measurement that
# could not tell selected from unselected must not be compared with anything.
_bad="$(awk -F'\t' '
    $1 == "BROKEN" { print $2 ": " $3 }
    $1 == "CONTROL" && ($3 != "0" || $4 != "1" || $5 != "0") {
        print $2 ": controls failed (nonsense prompt selected=" $3 ", own name selected=" $4 ", nonsense prompt under the real name=" $5 "; wanted 0, 1, 0)" }
    $1 == "FIXTURE" { fixture[$2] = 1 }
    $1 == "MATCHLINE" { if ($3 == "1") hit[$2] = 1; else if ($3 != "0") print $2 ": a MATCH line could not be measured: " $4 }
    $1 == "DECOY" && $3 != "0" && $3 != "1" { print $2 ": a NO_MATCH line could not be measured: " $5 }
    $1 == "ROW" && $4 == "unmeasured" { print $2 ": keyword \"" $3 "\" could not be measured (no registry, or the hook leaves before scoring on the bare keyword)" }
    END { for (s in fixture) if (!(s in hit)) print s ": no MATCH line of its fixture is selected, so an unselected decoy proves nothing" }
' "${MEASURED}")"
[ -z "${_bad}" ] || _cannot "$(printf '%s' "${_bad}" | head -5 | tr '\n' ';')"

grep -E '^(ROW|DECOY|MATCHLINE)	' "${MEASURED}"

FINDINGS="${WORK}/findings.tsv"
KPA_ONLY="${ONLY}" awk -F'\t' '
    function finding(kind, skill, what, detail) { print "FINDING\t" kind "\t" skill "\t" what "\t" detail }
    BEGIN { only = ENVIRON["KPA_ONLY"] }
    FILENAME == ARGV[1] {
        if ($0 ~ /^[[:space:]]*(#|$)/) next
        if (NF != 5 || $1 == "" || $2 == "" || $5 == "") { finding("ledger-malformed", "-", "-", "line " FNR ": want skill, keyword, class, decision, reason"); next }
        if (only != "" && $1 != only) next
        key = $1 SUBSEP $2
        if (key in lclass) { finding("ledger-malformed", $1, $2, "line " FNR ": a second row for one keyword"); next }
        if ($3 != "keyword-only" && $3 != "inert") { finding("ledger-malformed", $1, $2, "line " FNR ": class must be keyword-only or inert"); next }
        if ($4 != "recall" && $4 != "gap" && $4 != "open") { finding("ledger-malformed", $1, $2, "line " FNR ": decision must be recall, gap or open"); next }
        if ($3 == "inert" && $4 == "recall") { finding("ledger-malformed", $1, $2, "line " FNR ": a keyword that never fires recalls nothing"); next }
        lclass[key] = $3; debt[$4]++
        next
    }
    $1 == "ROW" {
        key = $2 SUBSEP $3; seen[key] = 1; n[$4]++; total++
        if ($4 == "covered") {
            if (key in lclass) finding("ledger-stale", $2, $3, "recorded as " lclass[key] ", measured covered: remove the row")
        } else if (!(key in lclass)) {
            finding("unrecorded", $2, $3, "measured " $4 ": decide and add a row to the decisions ledger")
        } else if (lclass[key] != $4) {
            finding("class-changed", $2, $3, "recorded as " lclass[key] ", measured " $4)
        }
    }
    END {
        for (key in lclass) if (!(key in seen)) { split(key, p, SUBSEP); finding("ledger-stale", p[1], p[2], "no such keyword in the config: remove the row") }
        print "DEBT\trecall\t" (debt["recall"] + 0)
        print "DEBT\tgap\t" (debt["gap"] + 0)
        print "DEBT\topen\t" (debt["open"] + 0)
        print "COUNTS\t" (total + 0) "\t" (n["covered"] + 0) "\t" (n["keyword-only"] + 0) "\t" (n["inert"] + 0)
    }
' "${LEDGER}" "${MEASURED}" > "${FINDINGS}" || _cannot "the ledger comparison did not run"

KPA_ONLY="${ONLY}" awk -F'\t' '
    function finding(kind, skill, what, detail) { print "FINDING\t" kind "\t" skill "\t" what "\t" detail }
    BEGIN { only = ENVIRON["KPA_ONLY"] }
    FILENAME == ARGV[1] {
        if ($0 ~ /^[[:space:]]*(#|$)/) next
        if (NF != 3 || $1 == "" || $2 == "" || $3 == "") { finding("known-malformed", "-", "-", "line " FNR ": want skill, prompt, reason"); next }
        if (only != "" && $1 != only) next
        known[$1 SUBSEP $2] = 1
        next
    }
    $1 == "DECOY" {
        key = $2 SUBSEP $5; seen[key] = 1; decoys++
        if ($3 == "1") {
            selected++
            if (!(key in known)) finding("decoy-selected", $2, $5, "a NO_MATCH line of its own fixture is selected (via " $4 ")")
        } else if (key in known) {
            finding("known-stale", $2, $5, "no longer selected: remove the row")
        }
    }
    $1 == "MATCHLINE" {
        matches++
        if ($3 != "1") finding("match-unselected", $2, $4, "a MATCH line of its own fixture is not selected")
    }
    END {
        for (key in known) if (!(key in seen)) { split(key, p, SUBSEP); finding("known-stale", p[1], p[2], "no such NO_MATCH line in the fixture: remove the row") }
        print "DECOYS\t" (decoys + 0) "\t" (selected + 0) "\t" (matches + 0)
    }
' "${KNOWN}" "${MEASURED}" >> "${FINDINGS}" || _cannot "the decoy comparison did not run"

grep -E '^FINDING	' "${FINDINGS}" | LC_ALL=C sort
grep -E '^DEBT	' "${FINDINGS}"
_counts="$(grep -E '^COUNTS	' "${FINDINGS}")"
_decoys="$(grep -E '^DECOYS	' "${FINDINGS}")"
[ -n "${_counts}" ] && [ -n "${_decoys}" ] || _cannot "a comparison produced no totals"
_nfind="$(grep -c -E '^FINDING	' "${FINDINGS}")"
printf 'SUMMARY\tkeywords=%s\tcovered=%s\tkeyword-only=%s\tinert=%s\tdecoys=%s\tdecoys-selected=%s\tmatches=%s\tfindings=%s\n' \
    "$(printf '%s' "${_counts}" | cut -f2)" "$(printf '%s' "${_counts}" | cut -f3)" \
    "$(printf '%s' "${_counts}" | cut -f4)" "$(printf '%s' "${_counts}" | cut -f5)" \
    "$(printf '%s' "${_decoys}" | cut -f2)" "$(printf '%s' "${_decoys}" | cut -f3)" \
    "$(printf '%s' "${_decoys}" | cut -f4)" "${_nfind}"

[ "${_nfind}" -eq 0 ] || exit 1
exit 0
