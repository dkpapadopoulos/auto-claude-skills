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
# LEG 7 — the documented Claude Code target: under 200 lines per instruction file.
# Not a ratchet; a ratchet here would fight every ordinary edit.
# ---------------------------------------------------------------------------
_lines="$(wc -l < "${CLAUDE_MD}" | tr -d ' ')"
if [ "${_lines}" -le 200 ]; then
    _record_pass "CLAUDE.md is within the documented 200-line target (${_lines})"
else
    _record_fail "CLAUDE.md line target" "${_lines} lines — Claude Code's own guidance is under 200; move a section to a path-scoped rule"
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
