#!/usr/bin/env bash
# Holds the CLAUDE.md / .claude/rules split that PR "split CLAUDE.md Gotchas into
# path-scoped .claude/rules files" introduced.
#
# WHAT THIS DOES NOT ENFORCE, stated first so nobody mistakes it for more than it is:
# it CANNOT decide whether a new bullet is session-wide. That judgement is semantic —
# the zsh bullet names `.sh` files and is *about* `.sh` files, structurally identical
# to the bash-3.2-arithmetic bullet one line above it, which is correctly path-scoped.
# The distinguisher is whether the imperative binds on an action taken with no file
# open, and no grep sees that. A phrase blocklist ("zsh", "Bash tool", "/dev/null")
# was considered and REJECTED: this repo's record is that enumerations of command
# shapes and phrases fail repeatedly, and one here would both miss new wordings and
# fire on legitimate citations.
#
# What it DOES enforce: the four misfilings found in review stay fixed (leg 5), and
# three structural properties whose failure modes are all SILENT (legs 2-4).
#
# The silent modes are the reason this file exists:
#   - a rule whose frontmatter does not parse loads UNCONDITIONALLY with no error,
#     restoring the full always-loaded cost while looking correct (leg 2)
#   - a glob matching nothing is a coverage hole that no session will ever report (leg 3)
#   - a bullet in a rule whose globs never match the files it governs is guidance
#     that can never load when it is needed (leg 4)
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-claude-md-rule-split.sh ==="

CLAUDE_MD="${PROJECT_ROOT}/CLAUDE.md"
RULES_DIR="${PROJECT_ROOT}/.claude/rules"
assert_file_exists "CLAUDE.md exists" "${CLAUDE_MD}"

# Claude Code glob semantics: `**` crosses directories, `*` and `?` do not.
_glob_to_ere() {
    local p="$1" out="" i=0 c
    while [ "$i" -lt "${#p}" ]; do
        if [ "${p:$i:3}" = "**/" ]; then out="${out}([^/]+/)*"; i=$((i+3)); continue; fi
        if [ "${p:$i:2}" = "**"  ]; then out="${out}.*";        i=$((i+2)); continue; fi
        c="${p:$i:1}"
        case "$c" in
            '*') out="${out}[^/]*" ;;
            '?') out="${out}[^/]"  ;;
            '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'\') out="${out}\\${c}" ;;
            *)   out="${out}${c}"  ;;
        esac
        i=$((i+1))
    done
    printf '%s' "^${out}$"
}

# ---------------------------------------------------------------------------
# LEG 1 — POSITIVE CONTROL for the matcher itself.
#
# Load-bearing, not ceremony. While writing this file the same check was written
# twice and broken twice, and BOTH broken versions produced plausible-looking
# findings: under zsh `case "$x" in $g)` does not pattern-expand a quoted variable
# (it needs ${~g}), and under macOS bash 3.2 there is no `mapfile`, so the glob
# array was silently empty. Both reported hooks/openspec-guard.sh as not matched by
# the rule whose FIRST glob names it. Without these cells a broken matcher makes
# legs 3 and 4 pass vacuously.
# ---------------------------------------------------------------------------
_ctl_fail=0
_ctl_n=0
while IFS='|' read -r _g _p _want; do
    [ -z "${_g}" ] && continue
    _ctl_n=$((_ctl_n+1))
    _re="$(_glob_to_ere "${_g}")"
    _got=0
    [[ ${_p} =~ ${_re} ]] && _got=1
    [ "${_got}" = "${_want}" ] || { _ctl_fail=$((_ctl_fail+1)); echo "    control miss: '${_g}' vs '${_p}' want=${_want} got=${_got}"; }
done <<'CTL'
hooks/openspec-guard.sh|hooks/openspec-guard.sh|1
hooks/egress-consent-*.sh|hooks/egress-consent-ask-hook.sh|1
hooks/**/*.sh|hooks/lib/verdict.sh|1
hooks/**/*.sh|hooks/openspec-guard.sh|1
tests/**|tests/fixtures/x/y.txt|1
config/*.json|config/presets/a.json|0
hooks/*.sh|hooks/lib/verdict.sh|0
CTL
assert_equals "glob matcher control: * does not cross /, ** does" "0" "${_ctl_fail}"
assert_equals "glob matcher control ran all its cells" "7" "${_ctl_n}"

# ---------------------------------------------------------------------------
# LEG 2 — frontmatter. Deliberately STRICTER than YAML: `---`, `paths:`, then only
# `  - "<glob>"` lines, then `---`. A strict form that matches is necessarily valid
# YAML, and uniformity is what makes legs 3 and 4 checkable at all.
# ---------------------------------------------------------------------------
_rule_n=0
_fm_bad=0
for _f in "${RULES_DIR}"/*.md; do
    [ -e "${_f}" ] || continue
    _rule_n=$((_rule_n+1))
    _b="$(basename "${_f}")"
    if [ "$(sed -n '1p' "${_f}")" != "---" ] || [ "$(sed -n '2p' "${_f}")" != "paths:" ]; then
        _fm_bad=$((_fm_bad+1)); echo "    ${_b}: does not open with '---' then 'paths:'"; continue
    fi
    # every line between line 3 and the closing --- must be a quoted glob entry
    _stray="$(sed -n '3,${/^---$/q;p;}' "${_f}" | grep -cv '^  - ".*"$' || true)"
    [ "${_stray}" = "0" ] || { _fm_bad=$((_fm_bad+1)); echo "    ${_b}: ${_stray} malformed paths entr(y|ies)"; }
    grep -q '^---$' <(sed -n '3,$p' "${_f}") || { _fm_bad=$((_fm_bad+1)); echo "    ${_b}: frontmatter never closes"; }
done
assert_equals "every rule file has strict, parseable paths: frontmatter" "0" "${_fm_bad}"
# Floor: a broken RULES_DIR path would make legs 2-4 pass having checked nothing.
if [ "${_rule_n}" -ge 5 ]; then
    _record_pass "rule-file floor (found ${_rule_n}, expected >= 5)"
else
    _record_fail "rule-file floor" "found only ${_rule_n} rule files in ${RULES_DIR} — legs 2-4 checked almost nothing"
fi

# ---------------------------------------------------------------------------
# LEG 3 — every glob must match at least one TRACKED file. An unmatched glob is a
# coverage hole that never announces itself.
# ---------------------------------------------------------------------------
_tracked="$(cd "${PROJECT_ROOT}" && git ls-files 2>/dev/null)"
assert_not_empty "git ls-files produced a file list to match globs against" "${_tracked}"
_glob_n=0
_dead=0
for _f in "${RULES_DIR}"/*.md; do
    [ -e "${_f}" ] || continue
    while IFS= read -r _g; do
        [ -z "${_g}" ] && continue
        _glob_n=$((_glob_n+1))
        _re="$(_glob_to_ere "${_g}")"
        _hit=0
        while IFS= read -r _t; do
            if [[ ${_t} =~ ${_re} ]]; then _hit=1; break; fi
        done <<< "${_tracked}"
        [ "${_hit}" = "0" ] && { _dead=$((_dead+1)); echo "    dead glob in $(basename "${_f}"): ${_g}"; }
    done <<< "$(sed -n '/^paths:/,/^---$/p' "${_f}" | sed -n 's/^  - "\(.*\)"$/\1/p')"
done
assert_equals "no rule glob matches zero tracked files" "0" "${_dead}"
if [ "${_glob_n}" -ge 50 ]; then
    _record_pass "glob floor (checked ${_glob_n}, expected >= 50)"
else
    _record_fail "glob floor" "only ${_glob_n} globs checked — the extractor probably stopped matching"
fi

# ---------------------------------------------------------------------------
# LEG 4 — a bullet that names real repo files must have at least ONE of them globbed
# by its own rule. Otherwise the guidance can never load when it is needed.
#
# Scoped to "at least one" on purpose: bullets legitimately cite neighbouring files
# in passing, and `push-gate-enforcement.md` deliberately does NOT glob config/*.json
# (those are remedy-reachability.md's subject; re-adding them would pull 62k into the
# ~85% of commits that touch config). Bullets naming NO repo file are not checked —
# four such bullets are correctly filed today, so requiring a named file would flag
# correct work.
# ---------------------------------------------------------------------------
_bul_n=0
_orphan=0
for _f in "${RULES_DIR}"/*.md; do
    [ -e "${_f}" ] || continue
    _globs="$(sed -n '/^paths:/,/^---$/p' "${_f}" | sed -n 's/^  - "\(.*\)"$/\1/p')"
    while IFS= read -r _line; do
        case "${_line}" in '- '*) ;; *) continue ;; esac
        _bul_n=$((_bul_n+1))
        _named=0; _cov=0
        for _p in $(printf '%s' "${_line}" | grep -oE '(hooks|scripts|skills|config|tests|docs|assets)/[A-Za-z0-9_./*-]+\.(sh|md|json|mjs|yml|css)' | sort -u); do
            [ -e "${PROJECT_ROOT}/${_p}" ] || continue
            _named=$((_named+1))
            while IFS= read -r _g; do
                [ -z "${_g}" ] && continue
                _re="$(_glob_to_ere "${_g}")"
                if [[ ${_p} =~ ${_re} ]]; then _cov=1; break; fi
            done <<< "${_globs}"
            [ "${_cov}" = "1" ] && break
        done
        if [ "${_named}" -gt 0 ] && [ "${_cov}" = "0" ]; then
            _orphan=$((_orphan+1)); echo "    $(basename "${_f}"): bullet governs files its own rule never globs: ${_line:2:60}"
        fi
    done < "${_f}"
done
assert_equals "every file-naming bullet is globbed onto at least one file it governs" "0" "${_orphan}"
if [ "${_bul_n}" -ge 20 ]; then
    _record_pass "bullet floor (checked ${_bul_n}, expected >= 20)"
else
    _record_fail "bullet floor" "only ${_bul_n} bullets checked — the '- ' extractor probably broke"
fi

# ---------------------------------------------------------------------------
# LEG 5 — REGRESSION PIN on the four bullets review found misfiled. This is a pin on
# four known incidents, in the same spirit as the `ratchet` grep in
# tests/test-incident-analysis-content.sh — NOT a general criterion check.
#
# Anchored on each bullet's OPENING, never on a substring: push-gate-enforcement.md
# legitimately QUOTES the phrase "Bash tool is NOT bash" as a cross-reference, so a
# substring form would fail on correct prose. A citation is never at a bullet's start.
# ---------------------------------------------------------------------------
_pin_n=0
_pin_bad=0
while IFS='|' read -r _label _anchor; do
    [ -z "${_label}" ] && continue
    _pin_n=$((_pin_n+1))
    _in_claude="$(grep -c "${_anchor}" "${CLAUDE_MD}" || true)"
    _in_rules=0
    for _f in "${RULES_DIR}"/*.md; do
        [ -e "${_f}" ] || continue
        _in_rules=$(( _in_rules + $(grep -c "${_anchor}" "${_f}" || true) ))
    done
    if [ "${_in_claude}" != "1" ]; then
        _pin_bad=$((_pin_bad+1))
        echo "    ${_label}: expected exactly 1 occurrence in CLAUDE.md, found ${_in_claude}"
    fi
    if [ "${_in_rules}" != "0" ]; then
        _pin_bad=$((_pin_bad+1))
        echo "    ${_label}: must not be a bullet in a path-scoped rule (found ${_in_rules})"
    fi
done <<'PINS'
zsh is the model's shell|^- \*\*The model's Bash tool is NOT bash
grep -F on runtime output|^- Grepping runtime text output
#142 stdin guard|^- \*\*`tests/run-tests.sh` self-guards stdin
#263 suite sentinel|^- \*\*A suite log is COMPLETE only if it says so
PINS
assert_equals "the 4 agent-behaviour rules live in CLAUDE.md, not in a rule file" "0" "${_pin_bad}"
assert_equals "all 4 regression pins were evaluated" "4" "${_pin_n}"

# ---------------------------------------------------------------------------
# LEG 6 — each bullet has exactly ONE home. A bullet in both CLAUDE.md and a rule
# file is loaded twice and drifts, which is the paired-sites failure this split was
# careful to avoid.
# ---------------------------------------------------------------------------
_dupes="$( { awk '/^## Gotchas/{g=1;next} /^### Path-scoped/{g=0} g' "${CLAUDE_MD}" | grep '^- '
            cat "${RULES_DIR}"/*.md 2>/dev/null | grep '^- '; } | sort | uniq -d | wc -l | tr -d ' ')"
assert_equals "no bullet appears in two places" "0" "${_dupes}"

# ---------------------------------------------------------------------------
# LEG 7 — SIZE, measured against the limit that actually exists.
#
# HISTORY FIRST, because the first cut of this leg got the mechanism wrong and
# the wrong version reads as more plausible than the right one. If you are
# editing this leg, read this block before you touch a constant.
#
# The real constraint is a TOTAL across instruction files, NOT a per-file cap.
# The product's own warning string, quoted verbatim in anthropics/claude-code#96506:
#
#   9 instruction files add up to 192.2k chars, over the 150.0k-char total
#   limit - largest: .claude/rules/08-work-execution.md (59.2k) -
#   /memory to free up context
#
# Three things that says, and each one kills a claim the first cut made:
#   - the budget is COMBINED. A per-file budget is the wrong SHAPE, not merely
#     the wrong number: 130,000 across today's 8 files permits 1,040,000
#     chars, 6.9x the real limit, and reports green the whole way.
#   - it is a CONTEXT-COST warning, NOT truncation. Its own remedy is "free up
#     context". Nothing is cut off: code.claude.com/docs/en/memory says a
#     CLAUDE.md "loads ... up to 4 MiB in full and skips a larger file", and
#     that the 200-line/25KB truncation-from-the-end there "applies only to
#     MEMORY.md". The first cut asserted the tail of a 155k CLAUDE.md "was
#     reaching nobody"; it loaded in full.
#   - rules files COUNT toward the total. The warning's own list is mostly
#     .claude/rules/*.md, so splitting CLAUDE.md into rules does not reduce it.
#
# What the docs actually quantify is very little: "target under 200 lines per
# CLAUDE.md file" and the 4 MiB skip. Both are asserted below. The combined
# limit's EXISTENCE is documented -- "you also see a warning when files that
# are each within that length add up past a combined limit at session start"
# -- but its VALUE is not; 150,000 comes only from the warning string above.
# A per-file warning at 40.0k chars appears in anthropics/claude-code#22364,
# but that issue reports a MISCOUNT bug and was closed stale, so 40.0k is
# REPORTED below and never asserted on.
#
# MEASURED, and it is why this is a ratchet and not a limit: the repo has been
# over 150,000 since before the split, and the split moved it the WRONG WAY.
#   63564586  1 file   154,492 chars  102%   <- the "breach"
#   089701b8  8 files  162,378 chars  108%   <- the split. Redistributed it.
#   e42255b4  8 files  167,353 chars  111%
# Asserting 150,000 today goes red immediately, and .verify.yml declares the
# whole suite as the push gate, so that would deny every routing push in the
# repo, for every session, until ~20k chars come out. Owner's decision
# (2026-09-30): ratchet at today's total, report the true percentage on every
# run so the overage is never hidden, and trim under 150,000 as separate work
# where the ratchet banks the reduction.
#
# BYTES, not chars, for the ratchet. The limit is in chars, but `wc -m`
# reports BYTES under LC_ALL=C, and a constant pinned to an exact value must
# not change meaning with the locale -- that would flip the ratchet between a
# laptop and CI. Bytes >= chars for UTF-8, so a byte baseline is a
# conservative stand-in (today: 170038 bytes vs 168992 chars, 0.6% apart)
# and the reported percentage is a slight OVER-estimate, deliberately.
# ---------------------------------------------------------------------------
# SESSION-START vs WORST-CASE. Getting this backwards is how the first two cuts
# of this leg went wrong, in opposite directions.
#
# The 150,000 warning fires "at session start" (docs). A rule file WITH `paths:`
# frontmatter loads on demand -- "when Claude reads files matching the pattern",
# not at launch -- so it is NOT in the session-start total. Every rule file in
# this repo is path-scoped, and there is no unscoped rule, no ~/.claude/rules/
# and no user CLAUDE.md, so the session-start load is CLAUDE.md alone.
#
# That REVERSES a claim an earlier cut of this leg made. The split WORKED for
# the thing the warning measures:
#   63564586   154,492 chars at session start (one unscoped file)  -> 102%, OVER
#   089701b8    23,083 at session start                            ->  15%
#   today       25140 at session start                            ->  17%
# What grew is the WORST CASE -- a session that reads files matching all seven
# rules -- which is real (this suite's own session loaded two) but is a context
# cost paid on demand, not a startup breach. #96506's 192.2k across 9 files is
# consistent with UNSCOPED rules, which do load at launch.
#
# So the session-start total is ASSERTED against the real limit: at 17% there is
# no blocking risk, and a real assertion beats a ratchet. The worst-case total
# is RATCHETED, because it is already past 150,000 and asserting it would deny
# every routing push in the repo.
_LINE_TARGET=200                 # docs: "target under 200 lines per CLAUDE.md file"
_HARD_SKIP=4194304               # docs: loads "up to 4 MiB in full", skips a LARGER file
_COMBINED_REAL_LIMIT=150000      # the product's warning threshold (total, all files)
_COMBINED_BASELINE=170038  # RATCHET: today's exact total. Not a ceiling.
_PERFILE_ADVISORY_BYTES=40000    # #22364 states 40.0k CHARS; compared in bytes, so
                                 # approximate by ~0.6% here. Reported, never asserted.

# Predicates. Every control calls THESE, never a copy: a control that
# re-derives the rule tests its own copy and stays green while the real one is
# mutated. Unmeasurable always counts as a VIOLATION -- a checker that reports
# clean when it could not read its input is worse than no checker.
# Return 0 = violates (bad), 1 = ok.
_num_ok() { case "$1" in ''|*[!0-9]*) return 1 ;; esac; [ "${#1}" -le 18 ]; }

# Sum the byte sizes of a SET of files. Prints an exact total, or the literal
# UNMEASURABLE if ANY member could not be measured.
#
# A function returning a VALUE, rather than a sentinel smuggled through the
# running arithmetic, because the first cut did the latter and it did not work.
# It set the total to -1 on an unmeasurable file and then KEPT ADDING, so one
# such file discarded the sum so far and the result came out wrong, positive
# and plausible. That is worse than a wrong number: a total landing under the
# baseline routed to the `shrank` arm, whose remedy says "now lower
# _COMBINED_BASELINE to <that bogus value>" -- a cannot-measure condition
# emitting a confident instruction to bank a corrupted baseline. Controls
# A6/A7 pin both halves, including the bad path in the MIDDLE of the set,
# which is the case the inline version could not even express.
# 0 = this rule file loads at SESSION START, i.e. it has no `paths:` frontmatter.
# Leg 2 already pins that frontmatter to `---` then `paths:` on line 2, so
# reading line 2 is sufficient here rather than parsing YAML.
_loads_at_session_start() {
    [ "$(sed -n '2p' "$1" 2>/dev/null)" != "paths:" ]
}

_sum_bytes() {
    local _t=0 _n _p
    for _p in "$@"; do
        _n="$( { wc -c < "${_p}"; } 2>/dev/null | tr -d ' ')"
        _num_ok "${_n}" || { printf 'UNMEASURABLE'; return; }
        _t=$((_t + _n))
    done
    printf '%s' "${_t}"
}

_over_line_target() {
    local _n
    # Braces, not `wc ... 2>/dev/null`: an unreadable path fails at REDIRECTION,
    # which the shell reports before wc ever runs.
    _n="$( { wc -l < "$1"; } 2>/dev/null | tr -d ' ')"
    _num_ok "${_n}" || return 0
    [ "${_n}" -gt "${_LINE_TARGET}" ]
}

_over_hard_skip() {
    local _n
    _n="$( { wc -c < "$1"; } 2>/dev/null | tr -d ' ')"
    _num_ok "${_n}" || return 0
    # -gt, not -ge: exactly 4 MiB still loads in full. Boundary pinned in A4.
    [ "${_n}" -gt "${_HARD_SKIP}" ]
}

# Ratchet verdict: prints equal | grew | shrank | unmeasurable.
_combined_verdict() {
    _num_ok "$1" && _num_ok "$2" || { printf 'unmeasurable'; return; }
    if   [ "$1" -gt "$2" ]; then printf 'grew'
    elif [ "$1" -lt "$2" ]; then printf 'shrank'
    else                         printf 'equal'
    fi
}

_size_n=0
_line_bad=0
_skip_bad=0
_biggest=0
_biggest_name=""
_advisory=""
for _f in "${CLAUDE_MD}" "${RULES_DIR}"/*.md; do
    [ -e "${_f}" ] || continue
    _size_n=$((_size_n+1))
    _b="$(basename "${_f}")"
    # Reporting only. The RATCHET's total comes from _sum_bytes below, over the
    # same set -- deliberately not accumulated here, so a measurement failure
    # cannot be partially absorbed into a plausible sum.
    _bytes="$( { wc -c < "${_f}"; } 2>/dev/null | tr -d ' ')"
    if _num_ok "${_bytes}"; then
        if [ "${_bytes}" -gt "${_biggest}" ]; then _biggest="${_bytes}"; _biggest_name="${_b}"; fi
        if [ "${_bytes}" -ge "${_PERFILE_ADVISORY_BYTES}" ]; then _advisory="${_advisory} ${_b}(${_bytes})"; fi
    else
        echo "    ${_b}: could not be measured"
    fi
    # The 200-line target is documented for CLAUDE.md; applied to the rule
    # files too, since the adherence concern is identical and they are far
    # under it (18-44 lines today), so it costs nothing and catches a rule
    # file that grows into a wall of text.
    _over_line_target "${_f}" && { _line_bad=$((_line_bad+1)); echo "    ${_b}: over the documented ${_LINE_TARGET}-line target"; }
    _over_hard_skip   "${_f}" && { _skip_bad=$((_skip_bad+1)); echo "    ${_b}: over ${_HARD_SKIP} bytes (4 MiB) -- this file is SKIPPED ENTIRELY, not truncated"; }
done

assert_equals "every instruction file is within the documented ${_LINE_TARGET}-line target" "0" "${_line_bad}"
assert_equals "no instruction file is over the 4 MiB skip threshold" "0" "${_skip_bad}"

# The combined ratchet. Fails in BOTH directions on purpose: growth is the
# regression, and an unrecorded SHRINK banks slack invisibly, so a reduction
# must lower the constant in the same commit and say why.
# --- SESSION-START total: asserted against the REAL limit. ---
# Built as positional parameters, never an unquoted scalar: zsh does not
# word-split those (CLAUDE.md gotcha), so a space-joined string would collapse
# to one path.
set -- "${CLAUDE_MD}"
for _f in "${RULES_DIR}"/*.md; do
    [ -e "${_f}" ] || continue
    _loads_at_session_start "${_f}" && set -- "$@" "${_f}"
done
_start_n=$#
_start_total="$(_sum_bytes "$@")"
if ! _num_ok "${_start_total}"; then
    _record_fail "session-start instruction total" "unmeasurable -- never reported as clean"
elif [ "${_start_total}" -lt "${_COMBINED_REAL_LIMIT}" ]; then
    _record_pass "session-start total ${_start_total} bytes across ${_start_n} always-loaded file(s), under the ${_COMBINED_REAL_LIMIT} limit ($((_start_total * 100 / _COMBINED_REAL_LIMIT))%)"
else
    _record_fail "session-start instruction total" "${_start_total} bytes across ${_start_n} always-loaded file(s) is at or over the ${_COMBINED_REAL_LIMIT}-char limit -- this is the total the startup warning measures. Add \`paths:\` frontmatter to a rule, or cut CLAUDE.md."
fi

# --- WORST-CASE total: every instruction file, ratcheted. ---
# Same set as the loop above, expanded the same way.
_total="$(_sum_bytes "${CLAUDE_MD}" "${RULES_DIR}"/*.md)"
_verdict="$(_combined_verdict "${_total}" "${_COMBINED_BASELINE}")"
case "${_verdict}" in
    equal)
        _record_pass "combined instruction bytes pinned at ${_total} (ratchet holds)" ;;
    grew)
        _record_fail "combined instruction size ratchet" "grew to ${_total} bytes from a baseline of ${_COMBINED_BASELINE} (+$((_total - _COMBINED_BASELINE))). The real limit is ${_COMBINED_REAL_LIMIT} chars TOTAL and this repo is ALREADY OVER it. First choice: cut the growth, or move the prose out of the always-loaded set. Raising the baseline is permitted but never silent -- same convention as INCIDENT_SKILL_WORD_BASELINE: raise it in the SAME commit and say why in the message. An undisclosed raise is how this reached ${_total} bytes." ;;
    shrank)
        _record_fail "combined instruction size ratchet" "shrank to ${_total} bytes from ${_COMBINED_BASELINE}. Good -- now lower _COMBINED_BASELINE to ${_total} in the same commit so the reduction is banked and cannot be silently regrown." ;;
    *)
        _record_fail "combined instruction size ratchet" "the combined total is UNKNOWN (got '${_total}') -- at least one instruction file could not be measured. Treated as a failure, never as clean, and do NOT change _COMBINED_BASELINE on the strength of this run." ;;
esac

# Report the TRUE state every run. The ratchet only says "no worse"; this says
# where we actually are, so nobody reads a green suite as "size is fine".
if _num_ok "${_total}"; then
    # ~: a byte total over a CHAR limit. Bytes >= chars for UTF-8, so this
    # over-states by ~0.6% and never under-states. Stated, not hidden.
    echo "    worst case (all ${_size_n} files loaded): ${_total} bytes = ~$((_total * 100 / _COMBINED_REAL_LIMIT))% of ${_COMBINED_REAL_LIMIT} -- a context cost paid on demand, NOT a startup breach"
else
    echo "    combined: UNMEASURABLE across ${_size_n} instruction files -- percentage withheld rather than guessed"
fi
echo "    largest: ${_biggest_name} (${_biggest} bytes)"
[ -n "${_advisory}" ] && echo "    over ${_PERFILE_ADVISORY_BYTES} bytes, ~the 40.0k-char per-file advisory (#22364, reported only):${_advisory}"

# Floor: a broken CLAUDE_MD/RULES_DIR would make everything above pass having
# measured nothing, and would ALSO make the ratchet's total wrong-but-plausible.
if [ "${_size_n}" -ge 6 ]; then
    _record_pass "size floor (measured ${_size_n} instruction files, expected >= 6)"
else
    _record_fail "size floor" "measured only ${_size_n} instruction files -- the glob broke and this leg checked almost nothing"
fi

# ---------------------------------------------------------------------------
# LEG 7 CONTROLS.
#
# The real files pass every cell above, so a predicate that stopped working
# would leave the leg green. These are the cells that can tell.
# ---------------------------------------------------------------------------
_ctl7_dir="$(mktemp -d)"
trap 'rm -rf "${_ctl7_dir}"' EXIT
# Measured in review: with mktemp -d failing, _ctl7_dir is empty, every fixture
# write targets / and fails, and the A2/A4 controls PASS -- on a nonexistent
# path, for A5's reason (unmeasurable violates) rather than their own. Two
# guards, because one is not enough: the dir must exist, AND each fixture must
# measure the size its control assumes.
if [ -d "${_ctl7_dir}" ]; then
    _record_pass "control fixture dir exists"
else
    _record_fail "control fixture dir" "mktemp -d failed -- the fixture-backed controls below would pass having measured nothing"
fi
# 0 = fixture is the size its control needs; 1 = fail loudly and say why.
_ctl7_fixture_ok() {   # path | min-bytes | what
    local _n
    _n="$( { wc -c < "$1"; } 2>/dev/null | tr -d ' ')"
    if _num_ok "${_n}" && [ "${_n}" -ge "$2" ]; then return 0; fi
    _record_fail "control fixture: $3" "expected >= $2 bytes, measured '${_n}' -- the control using it would pass for the wrong reason"
    return 1
}

# A1 — the ratchet moves in BOTH directions and neither is silent. The 170410
# below is an ARBITRARY PIVOT, not today's total: these cells test
# _combined_verdict's classification, which must not change when the baseline
# is legitimately banked. Do not "update" it to match _COMBINED_BASELINE.
_ctl7_fail=0
_ctl7_n=0
while IFS='|' read -r _t _b _want; do
    # Guard the whole line, not just _t: an EMPTY total is one of the cells
    # below, and guarding on _t alone silently skipped it (count floor caught it).
    [ -z "${_t}${_b}${_want}" ] && continue
    _ctl7_n=$((_ctl7_n+1))
    _got="$(_combined_verdict "${_t}" "${_b}")"
    [ "${_got}" = "${_want}" ] || { _ctl7_fail=$((_ctl7_fail+1)); echo "    ratchet control: (${_t} vs ${_b}) => ${_got}, expected ${_want}"; }
done <<'RATCHET'
170410|170410|equal
170411|170410|grew
170409|170410|shrank
-1|170410|unmeasurable
|170410|unmeasurable
abc|170410|unmeasurable
08|170410|shrank
99999999999999999999|170410|unmeasurable
RATCHET
assert_equals "ratchet control: every direction classified correctly" "0" "${_ctl7_fail}"
assert_equals "ratchet control ran all its cells" "8" "${_ctl7_n}"

# A2 — the line target fires. 300 lines of nothing must be REJECTED; this is
# the cell that would have caught deleting the documented criterion.
_ctl7_long="${_ctl7_dir}/long.md"
awk 'BEGIN { for (i = 0; i < 300; i++) print "- short bullet" }' > "${_ctl7_long}"
_ctl7_fixture_ok "${_ctl7_long}" 4000 "300-line file"
if _over_line_target "${_ctl7_long}"; then
    _record_pass "control: a 300-line file is REJECTED by the documented line target"
else
    _record_fail "line-target control" "a 300-line file passed the ${_LINE_TARGET}-line target"
fi

# A3 — WORKED EXAMPLE, not a discriminator: measured as dominated by the
# real-file line assertion. Kept because it encodes the first cut's actual
# error. Do not defend it as a detector; do not delete it as redundant.
#
# A FAT, SHORT file must pass the line target, because the line
# target is not a size check. This is the pairing the first cut of this leg
# got wrong: it deleted the line cell believing a byte budget subsumed it.
# Neither subsumes the other, and the repo needs both.
_ctl7_fat="${_ctl7_dir}/fat.md"
{ printf '# two lines, 140k\n'; _pad="$(printf '%*s' 1000 '' | tr ' ' 'x')"; _i=0
  while [ "${_i}" -lt 140 ]; do printf '%s' "${_pad}"; _i=$((_i+1)); done; printf '\n'; } > "${_ctl7_fat}"
if _over_line_target "${_ctl7_fat}"; then
    _record_fail "line-target control (fat)" "a 2-line file was rejected by a LINE target — the predicate is measuring size"
else
    _record_pass "control: a 2-line/140k file passes the LINE target (the two criteria are independent)"
fi

# A4 — the 4 MiB skip threshold. Asserted against a real file over it, because
# a cell that never sees a file near the threshold proves nothing.
# Boundary, both sides, from ONE allocation truncated in place: the docs say
# 4 MiB exactly still loads IN FULL, so only a larger file may be flagged.
_ctl7_huge="${_ctl7_dir}/huge.md"
dd if=/dev/zero bs=1024 count=4100 2>/dev/null | tr '\0' 'x' > "${_ctl7_huge}"
_ctl7_fixture_ok "${_ctl7_huge}" "$((_HARD_SKIP + 1))" "over-4-MiB file"
if _over_hard_skip "${_ctl7_huge}"; then
    _record_pass "control: a file over 4 MiB is REJECTED (documented skip threshold)"
else
    _record_fail "hard-skip control" "a $( { wc -c < "${_ctl7_huge}"; } 2>/dev/null | tr -d ' ')-byte file passed the ${_HARD_SKIP}-byte threshold"
fi
# exactly _HARD_SKIP must NOT be flagged -- this is the cell that keeps the
# predicate honest to the "up to 4 MiB in full" quote rather than drifting to -ge.
python3 -c 'import sys,os; os.truncate(sys.argv[1], int(sys.argv[2]))' "${_ctl7_huge}" "${_HARD_SKIP}" 2>/dev/null \
    || dd if=/dev/null of="${_ctl7_huge}" bs=1 seek="${_HARD_SKIP}" 2>/dev/null
_ctl7_exact="$( { wc -c < "${_ctl7_huge}"; } 2>/dev/null | tr -d ' ')"
if [ "${_ctl7_exact}" = "${_HARD_SKIP}" ] && ! _over_hard_skip "${_ctl7_huge}"; then
    _record_pass "control: exactly ${_HARD_SKIP} bytes (4 MiB) is NOT flagged -- it loads in full"
else
    _record_fail "hard-skip boundary control" "at exactly ${_HARD_SKIP} bytes the file measured '${_ctl7_exact}' and/or was flagged as skipped; the docs say 4 MiB loads in full and only a LARGER file is skipped"
fi

# A5 — cannot-measure is never clean, for both per-file predicates.
if _over_line_target "${_ctl7_dir}/nope.md" && _over_hard_skip "${_ctl7_dir}/nope.md"; then
    _record_pass "control: an unmeasurable file violates BOTH per-file predicates, rather than passing"
else
    _record_fail "unmeasurable control" "an unreadable path passed a predicate — cannot-check is being reported as clean"
fi

# A5b — _loads_at_session_start, which decides which files the ASSERTED total
# contains. Getting it stuck on "yes" puts all 169,802 bytes into a total
# asserted against 150,000, so that mutation is caught by the real cell rather
# than only here; getting it stuck on "no" empties the total silently, which is
# why the both-directions pair and the unreadable case are all pinned.
_ctl7_scoped="${_ctl7_dir}/scoped.md";   printf -- '---\npaths:\n  - "x/**"\n---\n\n- b\n' > "${_ctl7_scoped}"
_ctl7_unscoped="${_ctl7_dir}/unscoped.md"; printf -- '# no frontmatter\n\n- b\n' > "${_ctl7_unscoped}"
_ss_fail=0
_loads_at_session_start "${_ctl7_scoped}"   && { _ss_fail=$((_ss_fail+1)); echo "    a path-scoped file was counted as session-start"; }
_loads_at_session_start "${_ctl7_unscoped}" || { _ss_fail=$((_ss_fail+1)); echo "    an UNSCOPED file was not counted as session-start"; }
_loads_at_session_start "${_ctl7_dir}/nope.md" || { _ss_fail=$((_ss_fail+1)); echo "    an unreadable file was excluded from the session-start total rather than counted"; }
assert_equals "session-start classifier: scoped out, unscoped in, unreadable counted (never silently dropped)" "0" "${_ss_fail}"

# A6/A7 — _sum_bytes. These are the cells the inline version could not have:
# the accumulation was a loop body, so "one member is unmeasurable" was not an
# expressible input. Position matters and is tested explicitly, because the
# defect was position-dependent -- the old sentinel survived only when the bad
# path came LAST, which is the one case a casual test would have used.
_ctl7_a="${_ctl7_dir}/a.md"; printf '12345' > "${_ctl7_a}"        # 5 bytes
_ctl7_b="${_ctl7_dir}/b.md"; printf '1234567890' > "${_ctl7_b}"   # 10 bytes
_ctl7_missing="${_ctl7_dir}/gone.md"

_sb_fail=0
_sb_n=0
_sb_check() {  # description | expected | actual
    _sb_n=$((_sb_n+1))
    [ "$2" = "$3" ] || { _sb_fail=$((_sb_fail+1)); echo "    _sum_bytes control: $1 => '$3', expected '$2'"; }
}
_sb_check "exact sum of two files"        "15"           "$(_sum_bytes "${_ctl7_a}" "${_ctl7_b}")"
_sb_check "single file"                   "5"            "$(_sum_bytes "${_ctl7_a}")"
_sb_check "empty set"                     "0"            "$(_sum_bytes)"
_sb_check "bad path FIRST"                "UNMEASURABLE" "$(_sum_bytes "${_ctl7_missing}" "${_ctl7_a}" "${_ctl7_b}")"
_sb_check "bad path in the MIDDLE"        "UNMEASURABLE" "$(_sum_bytes "${_ctl7_a}" "${_ctl7_missing}" "${_ctl7_b}")"
_sb_check "bad path LAST"                 "UNMEASURABLE" "$(_sum_bytes "${_ctl7_a}" "${_ctl7_b}" "${_ctl7_missing}")"
_sb_check "a directory is not a file"     "UNMEASURABLE" "$(_sum_bytes "${_ctl7_a}" "${_ctl7_dir}")"
assert_equals "_sum_bytes control: exact sums, and UNMEASURABLE at every position" "0" "${_sb_fail}"
assert_equals "_sum_bytes control ran all its cells" "7" "${_sb_n}"

# INTEGRATION CELL for F1, not a discriminator: no mutation is caught by it
# alone (the ratchet table fails alongside it). Kept because it is the one
# place the UNMEASURABLE string contract BETWEEN _sum_bytes and
# _combined_verdict is exercised end-to-end. Reviewed and nearly cut for that
# redundancy; this comment is why it stayed.
#
# The consequence that made F1 severe: an unknown total must NEVER route to
# the shrank/grew arms, whose remedies name a number to bank.
_sb_v="$(_combined_verdict "$(_sum_bytes "${_ctl7_a}" "${_ctl7_missing}" "${_ctl7_b}")" "${_COMBINED_BASELINE}")"
if [ "${_sb_v}" = "unmeasurable" ]; then
    _record_pass "control: an unmeasurable member yields 'unmeasurable', not a spurious grew/shrank that would name a bogus baseline"
else
    _record_fail "unmeasurable routing control" "a set with one unmeasurable member classified as '${_sb_v}' — the remedy text for that arm instructs banking a corrupted baseline"
fi

# B — the real historical file, not a hand-written stand-in. Its value here is
# narrow and stated as such: it pins that the 155k CLAUDE.md was ~119 lines,
# which is why the line target alone never saw the size problem. It does NOT
# show truncation; that claim was wrong (see the history block).
_ctl7_sha="63564586"
if git -C "${PROJECT_ROOT}" cat-file -e "${_ctl7_sha}:CLAUDE.md" 2>/dev/null; then
    _ctl7_hist="${_ctl7_dir}/historical-CLAUDE.md"
    git -C "${PROJECT_ROOT}" show "${_ctl7_sha}:CLAUDE.md" > "${_ctl7_hist}" 2>/dev/null
    _hb="$( { wc -c < "${_ctl7_hist}"; } 2>/dev/null | tr -d ' ')"
    _hl="$( { wc -l < "${_ctl7_hist}"; } 2>/dev/null | tr -d ' ')"
    # Both halves: over the COMBINED limit on its own, yet inside the per-file
    # line target. Either half alone is uninformative.
    if [ "${_hb}" -gt "${_COMBINED_REAL_LIMIT}" ] && ! _over_line_target "${_ctl7_hist}"; then
        _record_pass "control: the real ${_ctl7_sha} CLAUDE.md (${_hb} bytes, ${_hl} lines) exceeded the ${_COMBINED_REAL_LIMIT} TOTAL on its own while passing the ${_LINE_TARGET}-line target"
    else
        _record_fail "historical control" "${_ctl7_sha}:CLAUDE.md measured ${_hb} bytes / ${_hl} lines — expected over ${_COMBINED_REAL_LIMIT} bytes AND within the line target"
    fi
else
    # done-gates.yml checks out with actions/checkout@v4 at the default
    # fetch-depth: 1, so this object is genuinely absent there. Reported as
    # NOT CHECKED; recording a pass would be the cannot-check-reads-as-clean
    # failure this repo keeps re-finding. A1-A5 above always run.
    echo "    [not checked] historical control: ${_ctl7_sha}:CLAUDE.md unreachable (shallow checkout)"
fi

# ---------------------------------------------------------------------------
# LEG 8 — every "Obligations that no rule file can deliver" bullet CITES a rule
# file, and that citation must resolve: the named file must actually contain a
# symbol the bullet names. A cited proof that does not resolve is worse than an
# uncited claim, and the first cut of that section shipped one wrong citation
# (`_advisory_text_for_action` attributed to push-gate-telemetry.md; it lives in
# push-gate-enforcement.md).
#
# The bullets WRAP across lines, so this UNWRAPS first. A line-oriented reader
# finds zero citations and reports clean — the first cut of this cell did exactly
# that, and only the count floor below revealed it.
# ---------------------------------------------------------------------------
_cit_n=0
_cit_bad=0
while IFS= read -r _bullet; do
    [ -n "${_bullet}" ] || continue
    case "${_bullet}" in *'.md`)') ;; *) continue ;; esac
    _rf="$(printf '%s' "${_bullet}" | LC_ALL=C sed 's/.*(`\([a-z0-9-]*\.md\)`)$/\1/')"
    [ -n "${_rf}" ] || continue
    _cit_n=$((_cit_n+1))
    if [ ! -f "${RULES_DIR}/${_rf}" ]; then
        _cit_bad=$((_cit_bad+1)); echo "    cites a missing rule file: ${_rf}"; continue
    fi
    _hit=0
    for _sym in $(printf '%s' "${_bullet}" | LC_ALL=C tr '`' '\n' | LC_ALL=C awk 'NR%2==0' \
                  | LC_ALL=C grep -E '^[A-Za-z_][A-Za-z0-9_./-]{4,}$'); do
        case "${_sym}" in *.md) continue ;; esac
        if LC_ALL=C grep -qF "${_sym}" "${RULES_DIR}/${_rf}"; then _hit=1; break; fi
    done
    if [ "${_hit}" = "0" ]; then
        _cit_bad=$((_cit_bad+1))
        echo "    citation does not resolve: no symbol this bullet names is in ${_rf}"
        printf '      %s\n' "$(printf '%s' "${_bullet}" | LC_ALL=C cut -c1-104)"
    fi
done <<EOF
$(LC_ALL=C awk '
  /^### Obligations/{s=1; next}
  /^### Path-scoped/{s=0}
  s && /^- /{ if (b != "") print b; b=$0; next }
  s && /^  [^ ]/{ sub(/^  /,"",$0); b = b " " $0; next }
  s && /^$/{ if (b != "") { print b; b="" } }
  END{ if (b != "") print b }
' "${CLAUDE_MD}")
EOF
assert_equals "every obligation citation resolves in the rule file it names" "0" "${_cit_bad}"
# EVERY obligation bullet must carry a citation. Comparing the citation count to the
# BULLET count is self-adjusting (adding an obligation does not need a test edit) and
# catches a citation that fell off its bullet — which a fixed floor does not: with
# `>= 5` against 6 obligations, breaking one continuation indent took the count to 5
# and passed. A floor satisfiable by the degradation it guards pins nothing.
_obl_n="$(LC_ALL=C awk '/^### Obligations/{s=1;next} /^### Path-scoped/{s=0} s&&/^- /{n++} END{print n+0}' "${CLAUDE_MD}")"
assert_equals "every obligation bullet carries a citation (${_obl_n} bullets)" "${_obl_n}" "${_cit_n}"
if [ "${_cit_n}" -ge 5 ]; then
    _record_pass "obligation-citation floor (checked ${_cit_n}, >= 5 so neither count is vacuously 0)"
else
    _record_fail "obligation-citation floor" "only ${_cit_n} citations — the extractor stopped matching, so the cells above pinned nothing"
fi

print_summary
