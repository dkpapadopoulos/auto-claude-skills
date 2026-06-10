#!/usr/bin/env bash
# test-frontmatter-extraction.sh — Eval family 2 of the format-handoff eval:
# deterministic field-extraction robustness, design-guard heading grep vs a
# minimal YAML front-matter reader, across realistic heading mutations.
#
# Motivating specimen: the approved 2026-05-23 serena-auto-register design doc
# uses "## Out of Scope" (spaces) while hooks/skill-activation-hook.sh:1461
# greps '^## Out-of-Scope' (hyphens) — the guard silently reported the section
# missing on a real, complete design doc.
#
# This test MEASURES both extractors; it ships no production code. Bash 3.2.
set -u

PASS=0
FAIL=0
TMPDIR_T="$(mktemp -d /tmp/fm-extract.XXXXXX)"
trap 'rm -rf "${TMPDIR_T}"' EXIT

# --- extractor A: design-guard heading grep (verbatim patterns from the hook) ---
guard_grep_oos() { grep -q '^## Out-of-Scope' "$1"; }

# --- extractor B: minimal front-matter reader (candidate fm_get, ~10 lines) ---
fm_get() {
    # $1 file, $2 key — prints scalar value; empty + exit 0 when absent (fail-open)
    awk -v key="$2" '
        NR == 1 && $0 != "---" { exit }
        NR > 1 && $0 == "---"  { exit }
        NR > 1 && index($0, key ":") == 1 {
            sub("^" key ":[ \t]*", ""); print; exit
        }' "$1" 2>/dev/null
    return 0
}

FM_BLOCK='---
type: design
status: approved
out_of_scope: true
capabilities: [skill-routing, setup]
---
'

make_doc() {
    # $1 path, $2 heading line to use for the out-of-scope section, $3 with_fm (0|1)
    {
        [ "$3" = "1" ] && printf '%s' "${FM_BLOCK}"
        printf '# Some Design\n\n## Capabilities Affected\n\n- skill-routing\n\n'
        printf '%s\n\n- nothing else\n\n## Acceptance Scenarios\n\nGIVEN x WHEN y THEN z\n' "$2"
    } > "$1"
}

check() {
    # $1 label, $2 extractor result (0 found / 1 missed), $3 expected (0|1)
    if [ "$2" -eq "$3" ]; then
        PASS=$((PASS + 1))
        printf 'ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf 'FAIL %s\n' "$1"
    fi
}

# Mutations: how the same complete design doc plausibly renders its
# out-of-scope section in the wild. m0 is the guard's happy path.
run_mutation() {
    # $1 id, $2 heading
    local doc_plain="${TMPDIR_T}/$1-plain.md" doc_fm="${TMPDIR_T}/$1-fm.md" g_rc fm_rc
    make_doc "${doc_plain}" "$2" 0
    make_doc "${doc_fm}"    "$2" 1

    guard_grep_oos "${doc_plain}"; g_rc=$?
    [ -n "$(fm_get "${doc_fm}" out_of_scope)" ]; fm_rc=$?

    printf '%-4s %-34s guard-grep=%s fm_get=%s\n' "$1" "$2" \
        "$([ ${g_rc} -eq 0 ] && echo found || echo MISS)" \
        "$([ ${fm_rc} -eq 0 ] && echo found || echo MISS)"
    echo "${g_rc} ${fm_rc}"
}

echo "== Eval 2: out-of-scope field extraction across heading mutations =="
GUARD_FOUND=0; GUARD_TOTAL=0; FM_FOUND=0; FM_TOTAL=0
run_all() {
    while read -r id heading; do
        result="$(run_mutation "${id}" "${heading}")"
        echo "${result}" | sed '$d'
        rcs="$(echo "${result}" | tail -1)"
        g="${rcs%% *}"; f="${rcs##* }"
        GUARD_TOTAL=$((GUARD_TOTAL + 1)); FM_TOTAL=$((FM_TOTAL + 1))
        [ "${g}" = "0" ] && GUARD_FOUND=$((GUARD_FOUND + 1))
        [ "${f}" = "0" ] && FM_FOUND=$((FM_FOUND + 1))
    done <<'EOF'
m0 ## Out-of-Scope
m1 ## Out of Scope
m2 ### Out-of-Scope
m3 ## Out-of-Scope & Non-Goals
m4 ## 🚫 Out-of-Scope
EOF
    echo ""
    echo "guard-grep found ${GUARD_FOUND}/${GUARD_TOTAL}; fm_get found ${FM_FOUND}/${FM_TOTAL}"

    # Assertions: fm_get must be mutation-proof; guard-grep is expected to hit
    # only m0/m3 (prefix anchor) — documenting, not aspirational.
    check "fm_get extracts on all ${FM_TOTAL} mutations" "$([ "${FM_FOUND}" -eq "${FM_TOTAL}" ] && echo 0 || echo 1)" 0
    check "guard-grep misses >=3 mutations (brittleness demonstrated)" "$([ $((GUARD_TOTAL - GUARD_FOUND)) -ge 3 ] && echo 0 || echo 1)" 0

    # Real-specimen regression: the shipped serena design doc heading
    real_doc="/Users/damian.papadopoulos/IdeaProjects/auto-claude-skills/docs/plans/2026-05-23-serena-auto-register-design.md"
    if [ -f "${real_doc}" ]; then
        guard_grep_oos "${real_doc}"
        check "real specimen: guard-grep misses approved serena design doc" "$([ $? -ne 0 ] && echo 0 || echo 1)" 0
    fi

    echo ""
    echo "PASS=${PASS} FAIL=${FAIL}"
    [ "${FAIL}" -eq 0 ]
}
run_all
