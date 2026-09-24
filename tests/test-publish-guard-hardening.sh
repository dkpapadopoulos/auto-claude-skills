#!/usr/bin/env bash
# tests/test-publish-guard-hardening.sh — #187 (S7, S8, S9)
#
# S7 is the one that matters. Every other failure mode of publish-guard.sh errs
# toward allowing AND ANNOUNCING; the deny emitter was a bare `jq -n`, so a
# non-zero jq there tripped the blanket `trap 'exit 0' ERR` and a CONFIRMED
# LEAK passed in SILENCE. Measured before the fix with a jq shim that fails on
# `-n`: the control denied, the shimmed run emitted nothing at all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

GUARD="${PROJECT_ROOT}/hooks/publish-guard.sh"
ENGINE="${PROJECT_ROOT}/scripts/memory-leak-check.sh"

# _publish <mode:good|failjq> <body-text> -> the permissionDecision, or empty
_publish() {
    local _mode="$1" _body_text="$2" _w _mem _slug _shim="" _out _real_jq
    _real_jq="$(command -v jq)"
    _w="$(mktemp -d /tmp/acs-pg-XXXXXX)"
    # The engine resolves the corpus from --git-common-dir, so a worktree shares
    # the MAIN repo slug. Deriving it here rather than hardcoding: a hardcoded
    # slug silently resolves to no corpus, and "no corpus" is an ALLOW.
    _slug="$(cd "${PROJECT_ROOT}" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' | sed 's|[/.]|-|g')"
    _mem="${_w}/home/.claude/projects/${_slug}/memory"
    mkdir -p "${_mem}"
    printf '%s\n' '---' 'name: probe' '---' "${_body_text}" > "${_mem}/probe.md"
    printf '%s\n' "${_body_text}" > "${_w}/body.md"
    if [ "${_mode}" = failjq ]; then
        _shim="${_w}/shim"; mkdir -p "${_shim}"
        { printf '%s\n' '#!/bin/bash' 'for a in "$@"; do [ "$a" = "-n" ] && exit 7; done'
          printf 'exec %s "$@"\n' "${_real_jq}"; } > "${_shim}/jq"
        chmod +x "${_shim}/jq"
    fi
    mkdir -p "${_w}/tmp"
    _out="$(printf '%s' "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"gh issue create --title x --body-file ${_w}/body.md\"}}" \
        | PATH="${_shim:+${_shim}:}${PATH}" HOME="${_w}/home" TMPDIR="${_w}/tmp" \
          CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
          /bin/bash "${GUARD}" 2>/dev/null)"
    # Attributable leftovers: an isolated TMPDIR means anything here was made
    # by this run. Recorded for the cleanup cell below, then reaped.
    _PG_LEFTOVERS="$(ls -1 "${_w}/tmp" 2>/dev/null | tr '\n' ' ')"
    rm -rf "${_w}"
    printf '%s' "${_out}" | "${_real_jq}" -r '.hookSpecificOutput.permissionDecision // ""' 2>/dev/null
}

# GENERATED AT RUNTIME, never a literal. The engine exempts any shingle that
# also appears in the repo's TRACKED content — correctly, since public text is
# not a leak — and a literal probe string written into this very file IS
# tracked content. Measured: with a hand-written sentence here, the engine
# found the candidate hits, exempted every one of them, and reported CLEAN,
# so the control cell and the S7 cell both failed for the harness's reason
# rather than the code's. 26 random words is well past the 16-word shingle.
LEAK="$(awk 'BEGIN{
    srand();
    a = "abcdefghijklmnopqrstuvwxyz"; s = "";
    for (i = 0; i < 26; i++) {
        w = "";
        for (j = 0; j < 7; j++) w = w substr(a, int(rand() * 26) + 1, 1);
        s = s (i ? " " : "") w;
    }
    print s
}')"

test_preconditions() {
    if ! command -v jq >/dev/null 2>&1 || [ ! -r "${GUARD}" ] || [ ! -r "${ENGINE}" ]; then
        _record_fail "jq, guard and engine are present" "missing one — every cell below would be vacuous"
        return
    fi
    # The probe must be absent from tracked content or the public exemption
    # clears it and every detection cell below passes vacuously.
    if (cd "${PROJECT_ROOT}" && git grep -qF -- "${LEAK}" HEAD 2>/dev/null); then
        _record_fail "the generated probe is absent from tracked content" \
            "the probe is public, so the exemption would clear it and detection could not fire"
        return
    fi
    _record_pass "jq, guard and engine are present, and the probe is not public"
}

test_leak_denies_normally() {
    # THE CONTROL for the cell below. If this stops denying, the harness has
    # stopped reaching the detector and the failjq cell proves nothing.
    local d; d="$(_publish good "${LEAK}")"
    [ "${d}" = "deny" ] && _record_pass "a confirmed leak denies (control)" \
        || _record_fail "a confirmed leak denies (control)" "got '${d}' — the harness is not reaching detection"
}

test_leak_denies_when_the_emitter_cannot_render() {
    # S7. A failing jq at the deny site must not turn a confirmed leak into
    # silence. The fallback is a fixed literal because printf does no JSON
    # escaping and the real message carries model-authored citations.
    local d; d="$(_publish failjq "${LEAK}")"
    [ "${d}" = "deny" ] && _record_pass "a confirmed leak still denies when jq -n fails" \
        || _record_fail "a confirmed leak still denies when jq -n fails" \
           "got '${d}' — a leak passed silently, the worst direction for this gate"
}

test_corpus_cache_is_invalidated_by_a_newer_file() {
    # S8. Caching may only ever make the engine FASTER, never make it compare a
    # body against a stale corpus — that would report clean on text that is now
    # private, which is the leak this gate exists to stop.
    local _w _mem _slug _cache _out
    _w="$(mktemp -d /tmp/acs-pgc-XXXXXX)"
    _slug="$(cd "${PROJECT_ROOT}" && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null | sed 's|/\.git$||' | sed 's|[/.]|-|g')"
    _mem="${_w}/home/.claude/projects/${_slug}/memory"; mkdir -p "${_mem}"
    # LONG ENOUGH TO SHINGLE. The shingle width is 16 words, so a short corpus
    # file yields NO shingles, the cache is written empty, and an empty cache is
    # never valid — the cell then rebuilds every run and pins nothing. Measured:
    # with a 9-word file the cache was 0 bytes and mutating the invalidation
    # check failed no cell at all.
    printf '%s\n' 'this first corpus file is deliberately long enough to produce at least one shingle of sixteen consecutive words so that the cache it warms is actually non empty and therefore actually valid' > "${_mem}/a.md"
    _cache="${_w}/cache"
    printf '%s\n' "${LEAK}" > "${_w}/body.md"
    # warm the cache against a corpus that does NOT contain the leak
    HOME="${_w}/home" MLC_CORPUS_CACHE="${_cache}" /bin/bash "${ENGINE}" "${_w}/body.md" >/dev/null 2>&1
    if [ ! -s "${_cache}" ]; then
        rm -rf "${_w}"
        _record_fail "a corpus file newer than the cache invalidates it" \
            "the warm run left an EMPTY cache, so the cached path is never taken and this cell pins nothing"
        return
    fi
    # now add the secret; the cache is stale and must be rebuilt
    sleep 1
    printf '%s\n' "${LEAK}" > "${_mem}/secret.md"
    _out="$(HOME="${_w}/home" MLC_CORPUS_CACHE="${_cache}" /bin/bash "${ENGINE}" "${_w}/body.md" 2>&1)"
    rm -rf "${_w}"
    if printf '%s' "${_out}" | grep -q 'LEAK'; then
        _record_pass "a corpus file newer than the cache invalidates it"
    else
        _record_fail "a corpus file newer than the cache invalidates it" \
            "the engine reported clean against a stale corpus: [${_out}]"
    fi
}

test_guard_leaves_no_temp_files() {
    # `trap ... EXIT` REPLACES. The corpus-cache cleanup and the _TMP cleanup
    # were two separate EXIT traps, so the second disarmed the first and every
    # publish left a pg-corpus.* file in TMPDIR. Silent, unbounded, and
    # invisible to every other cell here — the hook's decision is unaffected.
    _PG_LEFTOVERS=""
    _publish good "${LEAK}" >/dev/null
    if [ -z "${_PG_LEFTOVERS}" ]; then
        _record_pass "the guard leaves no temp files behind"
    else
        _record_fail "the guard leaves no temp files behind" \
            "left in an isolated TMPDIR: ${_PG_LEFTOVERS}"
    fi
}

test_engine_is_in_both_canaries() {
    # S9. Detection lives in the engine, not in the guard that calls it, so a
    # stale engine in the versioned plugin cache is the drift this canary is for.
    local h="${PROJECT_ROOT}/hooks/session-start-hook.sh" miss=""
    grep -q 'memory-leak-check.sh (unparseable)' "${h}" || miss="${miss} parse-check"
    grep -q '"scripts/memory-leak-check.sh"' "${h}" || miss="${miss} drift-manifest"
    [ -z "${miss}" ] && _record_pass "the detection engine is in both session-start canaries" \
        || _record_fail "the detection engine is in both canaries" "missing from:${miss}"
}

test_engine_stays_out_of_gate_enforce_libs() {
    # It is EXECUTED, not sourced. _GATE_ENFORCE_LIBS source-probes its members,
    # which would run the engine at session start — the same reason
    # publish-guard.sh is excluded.
    local h="${PROJECT_ROOT}/hooks/session-start-hook.sh"
    if grep -E '^_GATE_ENFORCE_LIBS=' "${h}" | grep -q 'memory-leak-check'; then
        _record_fail "the engine is not source-probed" \
            "it is in _GATE_ENFORCE_LIBS, which sources its members"
    else
        _record_pass "the engine is not in _GATE_ENFORCE_LIBS (it is executed, not sourced)"
    fi
}

test_preconditions
test_leak_denies_normally
test_leak_denies_when_the_emitter_cannot_render
test_corpus_cache_is_invalidated_by_a_newer_file
test_guard_leaves_no_temp_files
test_engine_is_in_both_canaries
test_engine_stays_out_of_gate_enforce_libs

print_summary
