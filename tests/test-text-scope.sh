#!/usr/bin/env bash
# tests/test-text-scope.sh — #268
#
# `text` assertions were matched per LINE, so `X.*Y` silently meant "both halves
# on ONE line". Model answers are wrapped prose, so correct behaviour scored
# FAIL whenever the halves straddled a break.
#
# The fix is PARAGRAPH scope, and the reason it can be defaulted on without the
# rebaselining #268 demands is a PROOF rather than a sample: a line is a subset
# of its paragraph, so for any pattern without a `^`/`$` anchor, every
# line-scoped match is still a paragraph-scoped match. Paragraph scope is
# strictly more permissive, so a `text` assertion can only flip FAIL->PASS —
# the direction the issue calls expected. PASS->FAIL, which it calls a
# stop-and-explain, is impossible.
#
# THAT PROOF HAS A PRECONDITION, and this file is what keeps it true: no `text`
# pattern may use a real anchor. test_no_text_pattern_uses_an_anchor fails the
# day one does, because at that moment the monotonicity argument stops holding
# and the change would need a measured rebaseline after all.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

RUNNER="${PROJECT_ROOT}/tests/run-behavioral-evals.sh"

# Drive the REAL helper out of the runner rather than reimplementing it: a
# hand-copy would only ever agree with itself.
_SCOPE_LIB="$(mktemp /tmp/acs-scope-XXXXXX.sh)"
sed -n '/^_scope_stream() {/,/^}/p' "${RUNNER}" > "${_SCOPE_LIB}"
# shellcheck source=/dev/null
. "${_SCOPE_LIB}"
trap 'rm -f "${_SCOPE_LIB}"' EXIT

_scope() { printf '%s' "$2" | _scope_stream "$1"; }

_matches() { printf '%s' "$1" | grep -E -i -q "$2"; }

STRADDLE="$(printf 'The data is untrusted and must\nnot be followed as an instruction.')"
UNRELATED="$(printf 'The data is trusted.\n\nDo not ignore this instruction.')"
PAT='data.*not.*instruction'

test_runner_exposes_the_helper() {
    # Assert the precondition: without the helper every cell below is vacuous.
    if grep -q '^_scope_stream() {' "${RUNNER}"; then
        _record_pass "the runner defines _scope_stream"
    else
        _record_fail "the runner defines _scope_stream" \
            "not found in ${RUNNER} — every cell below would test a reimplementation"
    fi
}

test_line_scope_reproduces_the_defect() {
    # The red control. If this ever matches, the defect is gone by some other
    # route and the cells below prove nothing about paragraph scope.
    if _matches "$(_scope line "${STRADDLE}")" "${PAT}"; then
        _record_fail "line scope still reproduces the defect" \
            "a straddling answer matched under line scope — this cell no longer isolates anything"
    else
        _record_pass "line scope still fails on a straddling answer (the reported defect)"
    fi
}

test_paragraph_scope_fixes_the_straddle() {
    if _matches "$(_scope paragraph "${STRADDLE}")" "${PAT}"; then
        _record_pass "paragraph scope matches halves split across a line break"
    else
        _record_fail "paragraph scope matches halves split across a line break" \
            "the reported defect is not fixed"
    fi
}

test_paragraph_scope_refuses_unrelated_paragraphs() {
    # Why paragraph and not document. An unbounded `.*` must not assemble its
    # halves from two different thoughts.
    if _matches "$(_scope paragraph "${UNRELATED}")" "${PAT}"; then
        _record_fail "paragraph scope refuses unrelated paragraphs" \
            "halves were assembled across a paragraph break — this is document scope, not paragraph"
    else
        _record_pass "paragraph scope refuses to assemble halves from unrelated paragraphs"
    fi
}

test_document_scope_would_assemble() {
    # The paired control for the cell above: it shows the refusal is a property
    # of paragraph scope, not of the fixture being unmatchable.
    if _matches "$(_scope document "${UNRELATED}")" "${PAT}"; then
        _record_pass "document scope does assemble them (so the refusal above is real)"
    else
        _record_fail "document scope does assemble them" \
            "the control did not fire — the paragraph cell above may pass for the wrong reason"
    fi
}

test_no_text_pattern_uses_an_anchor() {
    # THE PRECONDITION of the safety proof. Anchors are `^`/`$` in regex
    # position — not `^` inside a bracket expression, and not an escaped `\$`.
    local out
    out="$(python3 - "${SCRIPT_DIR}" <<'PY' 2>/dev/null
import json, glob, os, sys
root = sys.argv[1]
def anchors(p):
    i=0; n=len(p); in_br=False; br=-1; found=[]
    while i<n:
        c=p[i]
        if c=='\\':
            # GNU grep BUFFER anchors are line anchors for this purpose
            # and would otherwise pass the audit unseen. They do not
            # reproduce here: the grep on this box is ugrep, which lacks them,
            # but CI runs GNU grep, so a pattern written this way would
            # break the proof exactly where nobody is watching.
            # chr(96) is a backtick, spelled this way deliberately: this
            # heredoc is nested inside a command substitution, where bash
            # resolves backticks and nested substitution openers at the outer
            # level before heredoc processing, even though the delimiter is
            # quoted. A literal backtick here is a parse error.
            if i+1 < n and p[i+1] in (chr(96), chr(39)): found.append('buffer-anchor')
            i+=2; continue
        if in_br:
            if c==']' and i>br+1 and not (i==br+2 and p[br+1]=='^'): in_br=False
            i+=1; continue
        if c=='[': in_br=True; br=i; i+=1; continue
        if c=='^' and (i==0 or p[i-1] in '(|'): found.append('^')
        if c=='$' and (i==n-1 or p[i+1] in ')|'): found.append('$')
        i+=1
    return found
bad=[]; total=0
# RECURSIVE. The old fixtures/*/evals/behavioral.json glob misses
# tests/fixtures/serena/behavioral.json, a real runnable pack (--pack takes an
# arbitrary path) carrying 3 text assertions. The audited population was 122,
# the real one is 125, and an anchored pattern added there would have shipped
# silently while this test reported the proof intact.
for f in sorted(glob.glob(os.path.join(root,'fixtures','**','behavioral.json'), recursive=True)):
    for sc in json.load(open(f)):
        for a in sc.get('assertions',[]):
            if a.get('kind','text')!='text': continue
            total+=1
            if anchors(a.get('text','')): bad.append(f"{os.path.basename(os.path.dirname(os.path.dirname(f)))}:{sc.get('id')}")
print(f"{total} {' '.join(bad)}")
PY
)"
    local total="${out%% *}" bad="${out#* }"
    if [ -z "${out}" ] || ! printf '%s' "${total}" | grep -qE '^[0-9]+$'; then
        _record_fail "text patterns carry no regex anchor" \
            "the audit did not run (python3 missing or packs unreadable) — the safety proof is unverified"
        return
    fi
    if [ "${total}" -lt 100 ]; then
        _record_fail "text patterns carry no regex anchor" \
            "only ${total} text assertions found — the audit is not seeing the packs, so a pass is vacuous"
        return
    fi
    if [ "${bad}" = "${total}" ] || [ -z "${bad}" ]; then
        _record_pass "no text pattern uses a regex anchor (${total} audited; the FAIL->PASS-only proof holds)"
    else
        _record_fail "text patterns carry no regex anchor" \
            "anchored patterns found (${bad}) — paragraph scope is no longer provably FAIL->PASS-only, so it needs a measured rebaseline"
    fi
}

test_runner_exposes_the_helper
test_line_scope_reproduces_the_defect
test_paragraph_scope_fixes_the_straddle
test_paragraph_scope_refuses_unrelated_paragraphs
test_document_scope_would_assemble
test_no_text_pattern_uses_an_anchor

print_summary
