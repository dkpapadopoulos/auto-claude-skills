#!/usr/bin/env bash
# test-injection-budget.sh — bounds the context THIS PLUGIN injects into an
# installer's session.
#
# WHY THIS EXISTS, and why it is not the instruction-file gate in
# test-claude-md-rule-split.sh. Recent Claude Code versions warn when
# instruction FILES on disk exceed a combined limit (the warning string is
# sourced in that sibling gate, via anthropics/claude-code#96506; the version
# that introduced it is NOT verifiable from this repo, so it is not asserted
# here). Measuring those files again would be duplication.
#
# Hook stdout is different in kind: this plugin's `UserPromptSubmit` output is
# injected per PROMPT, is not a file, and is not present at session start. That
# it is therefore invisible to a session-start instruction-FILE warning is
# REASONING, not a measurement in this file -- it is not measurable without a
# product-internals probe, and it is labelled as reasoning deliberately. What
# IS measured here is the size of that output.
#
# TEN HARNESS DEFECTS, in the order found. Four before review, six in review.
# The pattern is the point: every one produced a confident wrong number that
# read as a clean pass.
#
#   1. The hook is STATEFUL. Measured against THIS harness's registry, probing
#      one token five times: `review this PR before I merge it` gives
#      7066, 6030, 6030, 6030, 6030 -- the composition hint changes once the
#      chain advances. So a corpus measured in one pass, one prompt after
#      another, measures the previous prompt's leftovers. Every shape gets a
#      FRESH token with its state wiped, and is probed three times and must
#      agree (leg 2).
#
#      PROVENANCE MATTERS and an earlier version of this comment got it wrong:
#      it quoted "3586, 3586, 0, 0, 0", which came from a probe against the
#      author's real ~/.claude plugin cache, NOT from this harness's derived
#      registry, and is not reproducible here. Review caught it. Cite the
#      registry a number came from, or the number is not evidence for this file.
#
#   2. An isolated HOME has NO REGISTRY, so the scorer sees nothing and EVERY
#      prompt reads as "injects 0 bytes" -- deterministic, uniform, and
#      completely false. Leg 1 exists because that failure is indistinguishable
#      from success by inspection.
#
#   3. `config/fallback-registry.json` ships `"available": false` on all of its
#      skills (44/44, and all 11 `.plugins[]` too); it is a template, not a
#      usable cache. Copying it verbatim reproduces defect 2. Availability is
#      flipped on explicitly below.
#
#   4. Machine plugin DISCOVERIES are excluded deliberately. They differ per
#      machine, so including them would make the total unratchetable -- it
#      would pass locally and fail in CI for reasons unrelated to any change.
#      The population is therefore "every skill this repo SHIPS".
#
#   5. The injection renders ABSOLUTE PATHS, so a RAW byte count scales with the
#      length of the checkout path: measured raw 6,793 at a 45-character path
#      and 7,021 at a longer worktree, same code and same HEAD, because the
#      DESIGN hint renders the root three times. Paths are normalised to fixed
#      placeholders before measuring, so the figure tracks what the PLUGIN
#      emits rather than where the repo sits. Leg 2b pins that the
#      normalisation fires; the normalised figure is path-invariant.
#
#   6. `${#var}` counts CHARACTERS under a UTF-8 locale and BYTES under C, so
#      the first version measured a locale-dependent quantity while calling it
#      "bytes": 24,863 under en_US.UTF-8 and 24,918 under LC_ALL=C, a +55
#      difference from 24 em dashes, 3 arrows and a middot. `.verify.yml`
#      declares this suite as the push gate, so in a locale-less shell -- a
#      minimal container, cron, `docker exec`, a CI step exporting no LANG --
#      that one cell would have denied every push in the repo. Length is now
#      computed under a pinned `LC_ALL=C`; leg 2c keeps the word "bytes" honest.
#
#      Noted because it is the same error twice: the sibling size gate rejects
#      `wc -m` in its own header for exactly this reason, and this file
#      reintroduced the dependence through a different primitive.
#
#   7. The total was a function of the process CWD. The hook resolves
#      `_PROJECT_ROOT` as `${SKILL_PROJECT_ROOT:-$(git rev-parse
#      --show-toplevel || pwd)}` and feeds it to an artifact-presence gate, so
#      running from anywhere but the repo root dropped a 169-byte composition
#      line and the total fell to 24,525. Thirteen other test files pin
#      `SKILL_PROJECT_ROOT`; this one did not. Pinned, with leg 2e asserting it.
#
#   8. The state wipe was INERT and INCOMPLETE. Inert because every probe
#      already uses a unique token, so the file stayed green with the wipe
#      deleted. Incomplete because one probe writes THREE token-keyed files
#      (`.skill-composition-state-`, `.skill-last-invoked-`,
#      `.skill-prompt-count-`) and the wipe named two, one of which is never
#      created here; reusing a token moved the injection 7065 -> 6032. Now a
#      GLOB over the token suffix, because an enumeration rots silently the
#      moment a fourth file appears -- and leg 2d catches both the removal and
#      the narrowing.
#
#   9. `${var//pat/repl}` treats pat as a GLOB, not a literal. Measured under
#      /bin/bash 3.2.57: a checkout path containing `[0]` is NOT replaced (it
#      matches `a0b` instead), and `*` and `?` OVER-match and silently swallow
#      unrelated text, which is the quiet direction. Metacharacters are escaped
#      and `_normalize` is a pure function, so leg 2f tests `[`, `*` and spaces
#      as DATA rather than requiring such directories to exist.
#
#  10. The figure is NOT an upper bound, which is how this file and its commit
#      first described it. Every probe takes a fresh token, so the harness
#      measures PROMPT #1 of a session. Steady state differs and NOT only
#      downward -- measured, `ship it` goes 4,527 first-prompt to 5,573 at
#      steady state, while `review this PR` falls 7,066 to 6,030. The pinned
#      figure is a deterministic FIRST-PROMPT total. Leg 2d-i keeps one
#      steady-state measurement as a standing counterexample; note that this
#      means the file reports two numbers describing DIFFERENT populations, and
#      says so where each appears. A second ratchet over steady-state totals is
#      deliberately NOT added -- it would double the runtime to pin a number
#      nobody has yet shown is actionable.
#
#  11. The total is a function of WORKING-TREE COMPLETENESS. The hook evaluates
#      its artifact-presence gate with `compgen -G` against SKILL_PROJECT_ROOT,
#      so a sparse, partial or filtered checkout changes the rendered output:
#      measured, moving `openspec/`, `docs/` and `tests/fixtures/evals/` aside
#      drops the total to 24,576, -342, which is the 171-byte
#      `implementation-drift-check` PARALLEL line times the two shapes that
#      carry it. PRECONDITION, stated rather than engineered around: this
#      figure assumes a FULL CHECKOUT. It fails LOUD, so leg 2g is a canary
#      with a diagnosis rather than a gate -- and pinning to a synthetic
#      fixture repo was rejected, because it would trade a stated precondition
#      for a baseline nobody can relate to this repo.
#
# Not a defect in this file but worth knowing, since it is an environmental
# input that silences the plugin entirely: with `SHELLOPTS=errexit` exported,
# the hook dies mid-run, emits nothing, and routing disappears -- total 0. The
# hook deliberately omits `set -e` for this reason (see its own header note),
# and an exported SHELLOPTS reimposes it from outside.
#
# A crashed hook also produces empty stdout, and on a genuinely silent prompt
# the real hook exits 0 with empty stdout, so the EXIT STATUS is the only
# discriminator. Before that was captured, deleting the hook outright left
# "every shape is measurable" and "shapes marked SILENT inject zero bytes"
# PASSING -- the latter is the cell this file calls behavioural. Both are now
# guarded, including a SILENT floor, because fixing the exit status alone left
# the silence cell passing over SKIPPED shapes.
#
# So the figure is a deterministic FIRST-PROMPT total for the plugin's own
# injection -- not an upper bound, and not a prediction of any user's session.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
# Pin the hook's project-root resolution (failure 6). Without this the hook
# falls back to `pwd` and an artifact-presence gate changes the rendered
# output, so the ratchet becomes a function of where the suite was launched.
export SKILL_PROJECT_ROOT="${PROJECT_ROOT}"
CORPUS="${SCRIPT_DIR}/fixtures/injection-budget/prompts.txt"

# shellcheck source=test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-injection-budget.sh ==="

# RATCHET, not a ceiling -- same convention as _COMBINED_BASELINE in
# test-claude-md-rule-split.sh and INCIDENT_SKILL_WORD_BASELINE in
# test-incident-analysis-content.sh. Growth fails; an unbanked REDUCTION also
# fails, so a win is recorded rather than silently re-spendable. Raising it is
# permitted and never silent: raise it in the SAME commit and say why.
#
# There is no "correct" value to assert instead. Nothing documents a budget for
# hook output, and the native warning does not measure it, so the honest gate is
# "this does not grow without someone saying so".
_INJECTION_BASELINE=24918
_MIN_SHAPES=6

setup_test_env

# --- deterministic registry (see failures 2-4 in the header) ---------------
_REG="${HOME}/.claude/.skill-registry-cache.json"
mkdir -p "$(dirname "${_REG}")"
if ! jq '.skills |= map(.available = true | .enabled = true)
         | .plugins |= (map(.available = true) // [])' \
       "${PROJECT_ROOT}/config/fallback-registry.json" > "${_REG}" 2>/dev/null; then
    _record_fail "registry build" "could not derive a test registry from config/fallback-registry.json"
fi

# ---------------------------------------------------------------------------
# LEG 1 — REGISTRY FLOOR. Without this every other cell can pass having
# measured an empty scorer, which is failure 2 and reads exactly like success.
# ---------------------------------------------------------------------------
# DERIVED, not hardcoded. A second hand-maintained constant buys no coverage
# here -- it catches only "the shipped population changed", which the ratchet
# already reports with a better message and the actual number -- while costing a
# second mechanical bump on an event that happens roughly monthly in this repo.
# Two constants for one cause is how a ratchet decays into a reflex: the second
# edit gets made BECAUSE the first had to be, and nobody re-reads the number.
# The two sides are different computations (the derived test registry vs the
# shipped template), so this is not self-referentially vacuous.
_shipped="$(jq '.skills | length' "${PROJECT_ROOT}/config/fallback-registry.json" 2>/dev/null)"
_vis="$(jq '[.skills[] | select(.available == true and .enabled == true)] | length' "${_REG}" 2>/dev/null)"
case "${_vis}" in ''|*[!0-9]*) _vis=-1 ;; esac
case "${_shipped}" in ''|*[!0-9]*) _shipped=-1 ;; esac
if [ "${_shipped}" -lt 1 ]; then
    _record_fail "registry floor" "could not read the shipped skill count from config/fallback-registry.json -- the floor has nothing to compare against"
elif [ "${_vis}" -eq "${_shipped}" ]; then
    _record_pass "registry floor: all ${_vis} shipped skills are visible to the scorer"
else
    # Deliberately a DIFFERENT message from the ratchet's: "the scorer sees
    # nothing" and "someone added a skill" must not read as the same failure.
    _record_fail "registry floor" "the scorer sees ${_vis} of ${_shipped} shipped skills -- the test registry is not being built correctly (availability not flipped, registry missing, or empty), so every byte figure below is measuring a different population and is meaningless. This is NOT the same as the shipped population changing; that shows up as a ratchet delta with the new number."
fi

# Probe one prompt under a FRESH token. Prints the byte size of
# additionalContext, or UNMEASURABLE -- never a number it could not compute,
# because a silent 0 here is the failure this whole file is guarding against.
_probe() {
    local _p="$1" _tok="injbudget-$2" _out _ctx _rc _v
    printf '%s' "${_tok}" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || {
        printf 'UNMEASURABLE'; return; }
    # Wipe ALL token-keyed state by GLOB, not by enumeration. Measured: one
    # probe writes three such files (.skill-composition-state-, .skill-
    # last-invoked-, .skill-prompt-count-), and the first version of this wipe
    # named two, one of which does not even exist. Reusing a token then moved
    # the injection 7065 -> 6032 bytes. An enumeration rots the moment the hook
    # writes a fourth file, and it rots SILENTLY -- the glob cannot.
    rm -f "${HOME}/.claude/".skill-*-"${_tok}" 2>/dev/null
    _out="$(jq -n --arg p "${_p}" '{"prompt":$p}' 2>/dev/null \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" 2>/dev/null)"
    _rc=$?
    # Empty stdout is LEGITIMATE -- the hook stays silent when nothing routes --
    # but a CRASHED hook is also empty, and on a silent prompt the real hook
    # exits 0, so the exit status is the ONLY discriminator (failure 9).
    # Measured before this check: with the hook deleted outright the file
    # reported 5 PASS / 2 FAIL, and two of those passes were "every shape is
    # measurable" and "shapes marked SILENT inject zero bytes" -- the cell this
    # commit calls load-bearing, passing because nothing ran.
    _v="$(_classify "${_out}" "${_rc}")"
    if [ "${_v}" != "MEASURE" ]; then printf '%s' "${_v}"; return; fi
    _ctx="$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" \
        || { printf 'UNMEASURABLE'; return; }
    # Normalise absolute paths (failure 5). Root FIRST, then home -- a fixed
    # order, NOT longest-first, which an earlier comment here wrongly claimed.
    # Measured counterexample: _normalize '/a/b/c' '/a' '/a/b' yields
    # '<ROOT>/b/c', exactly the fragment that claim said could not happen. Not
    # live -- HOME sits under TMPDIR, disjoint from PROJECT_ROOT -- so the fixed
    # order is kept and the behaviour is PINNED by leg 2f rather than described.
    _ctx="$(_normalize "${_ctx}" "${PROJECT_ROOT}" "${HOME}")"
    _ctx_bytes "${_ctx}"
}

# Classify a hook invocation. Extracted as a function for one reason: inline,
# the rc branch was never exercised on a healthy tree, so reverting it to a
# bare `printf 0` left the file 16/16 GREEN while silently removing 2 of the 7
# catches that the hook-deleted scenario produces. Measured. A control can only
# hold it by calling THIS function -- a control with its own copy of the rule
# tests its own copy.
#
# 'MEASURE'      -> there is output; measure it.
# '0'            -> legitimately silent (empty stdout, rc 0).
# 'UNMEASURABLE' -> empty stdout with a non-zero rc, i.e. the hook died. On a
#                   genuinely silent prompt the real hook exits 0 with empty
#                   stdout, so rc is the ONLY discriminator between the two.
_classify() {   # stdout rc
    if [ -n "$1" ]; then printf 'MEASURE'; return; fi
    case "$2" in ''|*[!0-9]*) printf 'UNMEASURABLE'; return ;; esac
    if [ "$2" -eq 0 ]; then printf '0'; else printf 'UNMEASURABLE'; fi
}

# Escape bash pattern metacharacters. `${var//pat/repl}` treats pat as a GLOB,
# not a literal (failure 8): measured under /bin/bash 3.2, a checkout path
# containing `[0]` is NOT replaced, and a DIFFERENT path `a0b` IS -- so the
# normalisation both missed its target and corrupted unrelated text.
# KNOWN LIMIT: this is an ENUMERATION of metacharacters, complete only while
# `extglob` and `nocaseglob` are OFF. Enable extglob inside this file and `(`,
# `)`, `+`, `@` and `!` become pattern metacharacters and the list silently
# under-escapes -- the same rotting-enumeration class the state wipe was moved
# away from. Measured: `BASHOPTS=extglob` in the ENVIRONMENT does not move the
# total, so there is no live exposure; the risk is a future edit in this file.
# Escape order is load-bearing: backslash first, then the rest.
#
# The `[` and `]` escapes are JOINTLY load-bearing and individually redundant --
# measured, so that an un-caught mutation here is not mistaken for a blind test
# and the escapes are not deleted as dead. Dropping `[` alone is behaviourally
# IDENTICAL (the escaped `]` stops the bracket expression forming), so leg 2f
# correctly stays green; dropping BOTH fails leg 2f in both directions at once
# (the literal path stops being replaced AND the glob twin starts being
# replaced). Equivalent mutation, not a coverage gap.
_glob_escape() {
    local _s="$1"
    _s="${_s//\\/\\\\}"
    _s="${_s//\[/\\[}"
    _s="${_s//\]/\\]}"
    _s="${_s//\*/\\*}"
    _s="${_s//\?/\\?}"
    printf '%s' "${_s}"
}

# Replace absolute paths with fixed placeholders. A function so leg 2f can test
# it against metacharacter-laden roots without creating such directories.
_normalize() {   # text root home
    local _t="$1" _r _h
    _r="$(_glob_escape "$2")"
    _h="$(_glob_escape "$3")"
    _t="${_t//${_r}/<ROOT>}"
    _t="${_t//${_h}/<HOME>}"
    printf '%s' "${_t}"
}

# BYTES, under a pinned locale (failure 7). A subshell so the pin cannot leak
# into the rest of the file, and `${#}` rather than `wc -c` so no trailing
# newline is counted.
_ctx_bytes() { ( LC_ALL=C LANG=C; printf '%s' "${#1}" ); }

# Same probe, but returns the normalised TEXT rather than its length, so leg 2b
# can assert on what was measured instead of trusting that it was normalised.
_probe_text() {
    local _p="$1" _tok="injbudget-$2" _out _ctx _rc _v
    printf '%s' "${_tok}" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || return 1
    # Wipe ALL token-keyed state by GLOB, not by enumeration. Measured: one
    # probe writes three such files (.skill-composition-state-, .skill-
    # last-invoked-, .skill-prompt-count-), and the first version of this wipe
    # named two, one of which does not even exist. Reusing a token then moved
    # the injection 7065 -> 6032 bytes. An enumeration rots the moment the hook
    # writes a fourth file, and it rots SILENTLY -- the glob cannot.
    rm -f "${HOME}/.claude/".skill-*-"${_tok}" 2>/dev/null
    _out="$(jq -n --arg p "${_p}" '{"prompt":$p}' 2>/dev/null \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" 2>/dev/null)"
    _rc=$?
    [ "$(_classify "${_out}" "${_rc}")" = "MEASURE" ] || { [ -n "${_out}" ] || [ "${_rc}" -eq 0 ]; return; }
    _ctx="$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" || return 1
    _ctx="$(_normalize "${_ctx}" "${PROJECT_ROOT}" "${HOME}")"
    printf '%s' "${_ctx}"
}

# ---------------------------------------------------------------------------
# LEG 2 — DETERMINISM, per shape, three probes. This is the cell that would
# have caught the stateful-measurement error, and it is why the corpus is
# probed shape-by-shape rather than in one pass.
# ---------------------------------------------------------------------------
_shapes=0
_measured=0
_total=0
_nondet=0
_silent_bad=0
_silent_n=0
_unmeasurable=0
_report=""

_i=0
while IFS='|' read -r _mode _prompt; do
    case "${_mode}" in ''|'#'*) continue ;; esac
    [ -z "${_prompt}" ] && continue
    _i=$((_i + 1))
    _shapes=$((_shapes + 1))

    _a="$(_probe "${_prompt}" "a${_i}")"
    _b="$(_probe "${_prompt}" "b${_i}")"
    _c="$(_probe "${_prompt}" "c${_i}")"

    if [ "${_a}" = "UNMEASURABLE" ] || [ "${_b}" = "UNMEASURABLE" ] || [ "${_c}" = "UNMEASURABLE" ]; then
        _unmeasurable=$((_unmeasurable + 1))
        echo "    UNMEASURABLE: ${_prompt}"
        continue
    fi
    if [ "${_a}" != "${_b}" ] || [ "${_b}" != "${_c}" ]; then
        _nondet=$((_nondet + 1))
        echo "    NONDETERMINISTIC (${_a}/${_b}/${_c}): ${_prompt}"
        continue
    fi

    case "${_mode}" in
        SILENT)
            _silent_n=$((_silent_n + 1))
            if [ "${_a}" -ne 0 ]; then
                _silent_bad=$((_silent_bad + 1))
                echo "    SILENT shape injected ${_a} bytes: ${_prompt}"
            fi
            ;;
        MEASURE)
            _measured=$((_measured + 1))
            _total=$((_total + _a))
            ;;
        *)
            _record_fail "corpus mode" "unrecognised mode '${_mode}' in ${CORPUS} -- expected MEASURE or SILENT"
            ;;
    esac
    _report="${_report}
    ${_a} bytes  [${_mode}]  ${_prompt}"
done < "${CORPUS}"

assert_equals "every shape is deterministic across three fresh-token probes" "0" "${_nondet}"

# ---------------------------------------------------------------------------
# LEG 2b — PATH NORMALISATION. Without this the ratchet is a function of the
# checkout path, which is how failure 5 was found: a worktree at the same HEAD
# measured +228 bytes. Asserted on the measured TEXT, not inferred from the
# count, and anchored on the DESIGN shape because that is the one that renders
# paths. The floor matters: a shape that injects nothing trivially contains no
# path, so a non-empty context is required for the cell to mean anything.
# ---------------------------------------------------------------------------
# Read the anchor FROM the corpus rather than duplicating it: a reworded corpus
# line would otherwise leave this cell probing a prompt that is no longer a
# measured shape. It still has to be a shape that renders paths, so the DESIGN
# one is selected by position among MEASURE shapes, and the empty-context branch
# below fails loudly if that selection ever stops injecting.
_norm_anchor="$(grep '^MEASURE|' "${CORPUS}" 2>/dev/null | sed -n '2p' | cut -d'|' -f2-)"
_norm_ctx="$(_probe_text "${_norm_anchor}" "norm")"
if [ -z "${_norm_ctx}" ]; then
    _record_fail "path-normalisation control" "the DESIGN shape injected nothing, so this cell could not check normalisation -- not reported as clean"
elif printf '%s' "${_norm_ctx}" | grep -qF "${PROJECT_ROOT}"; then
    _record_fail "path-normalisation control" "the measured context still contains the literal checkout path, so the ratchet is a function of where this repo sits and will not hold in CI"
elif ! printf '%s' "${_norm_ctx}" | grep -qF '<ROOT>'; then
    _record_fail "path-normalisation control" "no <ROOT> placeholder in the measured context -- either the injection stopped rendering paths (then delete this cell) or the substitution silently did nothing"
else
    _record_pass "path-normalisation control: paths replaced, no literal checkout path in the measured bytes"
fi
assert_equals "every shape is measurable" "0" "${_unmeasurable}"

# ---------------------------------------------------------------------------
# LEG 2c — LOCALE INVARIANCE (failure 7). The one cell that keeps the word
# "bytes" honest; without it the ratchet is red in any locale-less shell.
# ---------------------------------------------------------------------------
_utf8_len="$( ( LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8; _s='a—b'; printf '%s' "${#_s}" ) )"
_c_len="$(_ctx_bytes 'a—b')"
if [ "${_utf8_len}" = "3" ] && [ "${_c_len}" = "5" ]; then
    _record_pass "locale control: \${#var} is locale-sensitive (3 chars vs 5 bytes) and _ctx_bytes pins BYTES"
elif [ "${_c_len}" = "5" ]; then
    # The probe string proves the pin works even if this shell cannot reach a
    # UTF-8 locale to demonstrate the contrast. Not a pass claim about contrast.
    _record_pass "locale control: _ctx_bytes returns BYTES (5); UTF-8 contrast unavailable in this shell"
else
    _record_fail "locale control" "_ctx_bytes('a—b') returned '${_c_len}', expected 5 -- the length is not being counted in bytes, so the ratchet is locale-dependent and the word 'bytes' is false"
fi

# Deliberately does NOT wipe, so leg 2d-i can show leftover state is POTENT.
# Without that, 2d-ii passes trivially if the hook ever stops writing
# token-keyed state, and the wipe silently becomes untested again.
_probe_nowipe() {
    local _p="$1" _tok="injbudget-$2" _out _ctx _rc _v
    printf '%s' "${_tok}" > "${HOME}/.claude/.skill-session-token" 2>/dev/null || {
        printf 'UNMEASURABLE'; return; }
    _out="$(jq -n --arg p "${_p}" '{"prompt":$p}' 2>/dev/null \
        | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" 2>/dev/null)"
    _rc=$?
    _v="$(_classify "${_out}" "${_rc}")"
    if [ "${_v}" != "MEASURE" ]; then printf '%s' "${_v}"; return; fi
    _ctx="$(printf '%s' "${_out}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)" \
        || { printf 'UNMEASURABLE'; return; }
    _ctx_bytes "$(_normalize "${_ctx}" "${PROJECT_ROOT}" "${HOME}")"
}

# ---------------------------------------------------------------------------
# LEG 2f — NORMALISATION against metacharacter roots (failure 8). Tested as a
# pure function, so no directory named `a[0]b` has to exist. Both directions
# matter, because the broken version did the wrong thing on both: the real path
# must be replaced, AND a glob-equivalent string must NOT be.
# ---------------------------------------------------------------------------
_nz_fail=0
_nz_n=0
_nz() {
    _nz_n=$((_nz_n + 1))
    [ "$2" = "$3" ] || { _nz_fail=$((_nz_fail + 1)); echo "    normalise: $1 => '$3', expected '$2'"; }
}
_nz "plain path"             "x <ROOT> y"    "$(_normalize 'x /tmp/aXb y'    '/tmp/aXb'   '/nope')"
_nz "path with a space"      "x <ROOT> y"    "$(_normalize 'x /tmp/a b/c y'  '/tmp/a b/c' '/nope')"
_nz "path with [0]"          "x <ROOT> y"    "$(_normalize 'x /tmp/a[0]b y'  '/tmp/a[0]b' '/nope')"
_nz "glob twin NOT matched"  "x /tmp/a0b y"  "$(_normalize 'x /tmp/a0b y'    '/tmp/a[0]b' '/nope')"
_nz "path with a star"       "x <ROOT> y"    "$(_normalize 'x /tmp/a*b y'    '/tmp/a*b'   '/nope')"
_nz "star twin NOT matched"  "x /tmp/aQQb y" "$(_normalize 'x /tmp/aQQb y'   '/tmp/a*b'   '/nope')"
_nz "HOME too"               "x <HOME> y"    "$(_normalize 'x /h/me y'       '/nope'      '/h/me')"
# NESTED pair, both orders. Documents the fixed root-then-home order rather
# than claiming an ordering property the code does not have.
_nz "home under root"        "<ROOT>/b/c"    "$(_normalize '/a/b/c'          '/a'         '/a/b')"
_nz "root under home"        "<HOME>/c"      "$(_normalize '/a/b/c'          '/a/b/c/d'   '/a/b')"
assert_equals "normalisation control: literal paths replaced, glob twins untouched" "0" "${_nz_fail}"
assert_equals "normalisation control ran all its cells" "9" "${_nz_n}"


# ---------------------------------------------------------------------------
# LEG 2h — the rc CLASSIFIER, as data. Tests _classify directly rather than
# needing a crashed hook, for the same reason leg 2f tests _normalize as data:
# the branch is unreachable on a healthy tree, so nothing else asserts it.
# ---------------------------------------------------------------------------
_cl_fail=0
_cl_n=0
_cl() {   # description | expected | actual
    _cl_n=$((_cl_n + 1))
    [ "$2" = "$3" ] || { _cl_fail=$((_cl_fail + 1)); echo "    classify: $1 => '$3', expected '$2'"; }
}
_cl "output present, rc 0"        "MEASURE"      "$(_classify '{"a":1}' 0)"
_cl "output present, rc non-zero" "MEASURE"      "$(_classify '{"a":1}' 3)"
_cl "silent: empty, rc 0"         "0"            "$(_classify '' 0)"
_cl "CRASHED: empty, rc 1"        "UNMEASURABLE" "$(_classify '' 1)"
_cl "CRASHED: empty, rc 2"        "UNMEASURABLE" "$(_classify '' 2)"
_cl "empty, rc 127 (not found)"   "UNMEASURABLE" "$(_classify '' 127)"
_cl "empty, unparseable rc"       "UNMEASURABLE" "$(_classify '' '')"
assert_equals "rc classifier: silence and breakage are distinguished by exit status" "0" "${_cl_fail}"
assert_equals "rc classifier control ran all its cells" "7" "${_cl_n}"

# ---------------------------------------------------------------------------
# LEG 2c-ii — SOURCE LINT, because leg 2c cannot catch its own regression.
#
# Leg 2c tests the HELPER. Reverting the CALL SITE to a bare length expansion leaves
# the file fully green on any C-locale machine -- measured: under LC_ALL=C the
# total is still 24,918 and leg 2c still passes, because under C `${#var}` IS
# the byte count. The two implementations are runtime-indistinguishable in
# exactly the environment the fix was written for, so only a source assertion
# can hold it. Same idiom as the single-site lint in skill-activation-hook.sh.
# ---------------------------------------------------------------------------
# The lint must not match ITSELF: its own pattern and failure text contain the
# token it searches for, which made the first version report 3 hits and fail on
# a correct file. Own lines are tagged and excluded. (A lint that matches its
# own source is the same family as a red control that tests its own copy.)
_self='LINT-SELF'
_lintsrc="${SCRIPT_DIR}/test-injection-budget.sh"
_bare_len="$(grep -v "${_self}" "${_lintsrc}" 2>/dev/null | grep -c '{#_ctx}' || true)"   # LINT-SELF
_via_helper="$(grep -c '_ctx_bytes "' "${_lintsrc}" 2>/dev/null || true)"
case "${_bare_len}" in ''|*[!0-9]*) _bare_len=-1 ;; esac
case "${_via_helper}" in ''|*[!0-9]*) _via_helper=-1 ;; esac
if [ "${_bare_len}" -eq 0 ] && [ "${_via_helper}" -ge 2 ]; then
    _record_pass "source lint: every measuring path goes through _ctx_bytes (${_via_helper} call sites, 0 bare length expansions)"
else
    _record_fail "source lint" "found ${_bare_len} bare length expansion(s) of the context variable and ${_via_helper} _ctx_bytes call sites -- a bare length is a CHARACTER count under UTF-8 and would silently make the ratchet locale-dependent again. No runtime cell can catch this under LC_ALL=C; that is why this lint exists."   # LINT-SELF
fi

# ---------------------------------------------------------------------------
# LEG 2d — STATE WIPE, exercised by TOKEN REUSE rather than a hand-made fixture.
#
# Two earlier versions of this cell were vacuous and the second one is the
# instructive one. Each probe uses a unique token, so the wipe in _probe is
# inert in normal operation -- measured: removing it leaves the file green. The
# first fix seeded hand-written composition JSON under a token; that ALSO left
# the file green, because the hook discards state whose `.chain` matches no real
# composition (silently, by design -- see .claude/rules/routing-state.md). A
# fixture invented by the test proved only that the test agreed with itself.
#
# The real discriminator is the behaviour the harness exists to defeat: probing
# the SAME token twice. The hook writes composition state on the first call, so
# without the wipe the second call reads it and the injection changes -- this is
# the 3586 -> 0 collapse from failure 1, reproduced deliberately. With the wipe,
# both calls are identical.
# ---------------------------------------------------------------------------
_wipe_prompt="ship it"

# 2d-i — POTENCY. Leftover state must actually CHANGE the injection, or the
# neutralisation cell below proves nothing. Measured: `ship it` goes 4,527 on
# the first prompt to 5,573 at steady state -- it injects MORE, which is also
# the counterexample to calling this file's figure an upper bound (failure 10).
# (An earlier version of this comment said 3,763 -> 5,123; those were measured
# without the SKILL_PROJECT_ROOT pin, i.e. under defect 7, and review caught
# the inconsistency with this file's own potency output.)
_pot1="$(_probe_nowipe "${_wipe_prompt}" "potency")"
_pot2="$(_probe_nowipe "${_wipe_prompt}" "potency")"
if [ "${_pot1}" = "UNMEASURABLE" ] || [ "${_pot2}" = "UNMEASURABLE" ]; then
    _record_fail "state-potency control" "could not measure one of the two unwiped probes"
elif [ "${_pot1}" -eq 0 ]; then
    _record_fail "state-potency control" "the control prompt injected nothing, so neither this cell nor the wipe cell below means anything"
elif [ "${_pot1}" != "${_pot2}" ]; then
    _record_pass "state-potency control: leftover state IS potent (${_pot1} then ${_pot2} bytes, unwiped)"
else
    _record_fail "state-potency control" "an unwiped token reuse produced ${_pot1} bytes twice -- leftover state is inert, so the wipe cell below is vacuous. Either the hook stopped writing token-keyed state (then this pair can go) or the probe is not reusing the token."
fi

# 2d-ii — NEUTRALISATION. The same reuse, wiped, must be idempotent.
_w1="$(_probe "${_wipe_prompt}" "wipe-reuse")"
_w2="$(_probe "${_wipe_prompt}" "wipe-reuse")"
if [ "${_w1}" = "UNMEASURABLE" ] || [ "${_w2}" = "UNMEASURABLE" ]; then
    _record_fail "state-wipe control" "could not measure one of the two probes"
elif [ "${_w1}" -eq 0 ]; then
    _record_fail "state-wipe control" "the control prompt injected nothing, so this cell proves nothing"
elif [ "${_w1}" = "${_w2}" ]; then
    _record_pass "state-wipe control: with the wipe, reusing a token is idempotent (${_w1} == ${_w2} bytes)"
else
    _record_fail "state-wipe control" "reusing a token changed the injection (${_w1} then ${_w2} bytes) DESPITE the wipe -- state is leaking between probes, which is how a corpus measured in one pass reports the previous prompt's leftovers"
fi

# LEG 2e — CWD INVARIANCE (failure 6). Asserts the pin above actually binds.
# ---------------------------------------------------------------------------
_here="$(_probe "${_wipe_prompt}" "cwd-here")"
_there="$( cd / 2>/dev/null && _probe "${_wipe_prompt}" "cwd-root" )"
if [ "${_here}" = "${_there}" ] && [ "${_here}" != "UNMEASURABLE" ] && [ "${_here}" -ne 0 ]; then
    _record_pass "cwd control: injection is invariant to the process CWD (${_here} bytes from both)"
else
    _record_fail "cwd control" "injection differs by CWD (${_here} here vs ${_there} from /) -- SKILL_PROJECT_ROOT is not pinned, so the ratchet depends on where the suite was launched"
fi

# ---------------------------------------------------------------------------
# LEG 2g — FULL-CHECKOUT canary.
#
# `SKILL_PROJECT_ROOT` is pinned to this repo (defect 7), deliberately, so the
# figure describes THIS repo rather than a synthetic fixture tree. The cost is
# that the hook's artifact-presence gate for `implementation-drift-check` is
# evaluated with `compgen -G` against the live checkout, so the total is a
# function of what is ON DISK -- which is defect 11.
#
# CORRECTED after review measured the margin: an earlier version of this comment
# said the gate was satisfied by ONE tracked fixture "by luck". That is false.
# Four independent TRACKED families satisfy it (49 `openspec/changes/*/`, 24
# `openspec/specs/*/spec.md`, 39 force-added `docs/plans/` files, 7
# `docs/superpowers/` files) plus the eval fixtures, and removing any one
# changes nothing -- measured. So the gitignored entries in that glob list can
# never tip the total while any tracked family survives, and the real
# precondition is simply a FULL CHECKOUT. This cell is that canary, across the
# whole glob list rather than a two-glob proxy.
# ---------------------------------------------------------------------------
_gate_globs="openspec/changes/*/
openspec/specs/*/spec.md
docs/plans/*-design.md
docs/plans/*-plan.md
docs/plans/*-spec.md
docs/superpowers/specs/*-design.md
docs/superpowers/plans/*.md
tests/fixtures/evals/*.json"
_tracked_families=0
while IFS= read -r _g; do
    [ -z "${_g}" ] && continue
    if [ -n "$(cd "${PROJECT_ROOT}" && git ls-files -- "${_g}" 2>/dev/null | head -1)" ]; then
        _tracked_families=$((_tracked_families + 1))
    fi
done <<EOF
${_gate_globs}
EOF
if [ "${_tracked_families}" -ge 1 ]; then
    _record_pass "full-checkout canary: ${_tracked_families} tracked artifact famil(y|ies) satisfy the drift gate, so untracked scratch cannot move the total"
else
    _record_fail "full-checkout canary" "no TRACKED file matches any of the drift gate's artifact globs. Either this is a partial/sparse checkout -- in which case the total is measuring a smaller tree and the ratchet delta is not a real change (defect 11) -- or every tracked artifact family was removed, and the gate now depends on gitignored working-tree scratch."
fi

# ---------------------------------------------------------------------------
# LEG 3 — CORPUS FLOOR. A truncated or unreadable corpus makes the ratchet pass
# over a smaller set, which is the partial-run failure shape: well-formed,
# entirely green, and measuring the wrong population.
# ---------------------------------------------------------------------------
if [ "${_shapes}" -ge "${_MIN_SHAPES}" ]; then
    _record_pass "corpus floor: ${_shapes} shapes read (>= ${_MIN_SHAPES})"
else
    _record_fail "corpus floor" "only ${_shapes} shapes read from ${CORPUS} -- expected >= ${_MIN_SHAPES}"
fi

# ---------------------------------------------------------------------------
# LEG 4 — SILENCE. A question about code and a mechanical rename are not SDLC
# phases. Injecting routing guidance for them is cost with no benefit, and the
# plugin is correctly silent on both today -- this pins that it stays so.
# ---------------------------------------------------------------------------
assert_equals "shapes marked SILENT inject zero bytes" "0" "${_silent_bad}"
# FLOOR, and it is not ceremony: with the hook deleted the SILENT shapes become
# UNMEASURABLE and are skipped, so _silent_bad stays 0 and the cell above
# passed having evaluated NOTHING. Measured -- it survived the hook being
# removed outright. The count is derived from the corpus so adding a SILENT
# shape needs no edit here.
_silent_expected="$(grep -c '^SILENT|' "${CORPUS}" 2>/dev/null || echo 0)"
case "${_silent_expected}" in ''|*[!0-9]*) _silent_expected=-1 ;; esac
if [ "${_silent_n}" -eq "${_silent_expected}" ] && [ "${_silent_n}" -gt 0 ]; then
    _record_pass "SILENT floor: all ${_silent_n} SILENT shapes were actually evaluated"
else
    _record_fail "SILENT floor" "evaluated ${_silent_n} of ${_silent_expected} SILENT shapes -- the silence assertion above is vacuous for any shape that was skipped"
fi

# ---------------------------------------------------------------------------
# LEG 5 — THE RATCHET.
# ---------------------------------------------------------------------------
if [ "${_total}" -eq 0 ]; then
    # Independent of leg 1 on purpose: leg 1 checks the registry FILE, this
    # checks that probing it actually produced bytes. Both failed together in
    # the harness drafts, and either alone reads as a clean pass.
    _record_fail "injection ratchet" "total is 0 across ${_measured} MEASURE shapes -- the harness measured nothing. Treated as a failure, never as a 'budget met'."
elif [ "${_total}" -eq "${_INJECTION_BASELINE}" ]; then
    _record_pass "plugin injection pinned at ${_total} bytes across ${_measured} shapes (ratchet holds)"
elif [ "${_total}" -gt "${_INJECTION_BASELINE}" ]; then
    _record_fail "injection ratchet" "grew to ${_total} bytes from ${_INJECTION_BASELINE} (+$((_total - _INJECTION_BASELINE))). This is context taken from every prompt in every installing repo, and no native warning will ever report it. Cut the injection, narrow a trigger, or raise the baseline in the SAME commit and say why."
else
    _record_fail "injection ratchet" "shrank to ${_total} bytes from ${_INJECTION_BASELINE} (-$((_INJECTION_BASELINE - _total))). Good -- now lower _INJECTION_BASELINE to ${_total} in the same commit so the reduction is banked and cannot be silently respent."
fi

# Report the shape table every run: the ratchet only says "no worse", and the
# per-shape spread is what tells a reader WHERE the cost is.
echo "    --- per-shape injection (deterministic, fresh token each) ---${_report}"
if [ "${_measured}" -gt 0 ]; then
    echo "    MEASURE total ${_total} bytes over ${_measured} shapes; mean $((_total / _measured))"
fi

teardown_test_env
print_summary
