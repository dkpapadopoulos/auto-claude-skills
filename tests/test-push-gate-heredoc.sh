#!/usr/bin/env bash
# Heredoc bodies are DATA, not command text (openspec: remedy-aware-backbone).
# Pins the false-block class measured live at v3.84.0: a doc/plan write via
# heredoc whose body mentions `git push` / `git commit` was classified as a real
# push (precise path <=4096 chars) or caught by the substring fallback (>4096,
# the production 35KB/6KB deny records). Both paths must treat bodies as data.
# The one deliberate exception: an interpreter-fed heredoc (`bash <<EOF`)
# EXECUTES its body, so it must stay fail-closed (unbalanced -> substring).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-heredoc.sh ==="

# ---------------------------------------------------------------- predicates
# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/git-command.sh"

_assert_pred() { # <desc> <expected 0|1> <fn> <cmd>
    local _rc=0
    "$3" "$4" >/dev/null 2>&1 || _rc=1
    assert_equals "$1" "$2" "${_rc}"
}

_NL='
'

# P1: doc write; body mentions a push -> NOT a git write, parse balanced.
_c1="cat > notes.md <<EOF${_NL}Deployment notes:${_NL}git push origin main${_NL}EOF"
_assert_pred "P1 doc-write heredoc is not a push"      1 command_invokes_git_write "${_c1}"
_assert_pred "P1 doc-write heredoc is not mutate"      1 command_git_mutate_before_push "${_c1}"
_assert_pred "P1 parse is balanced"                    0 command_parse_balanced "${_c1}"

# P2: plan doc with fenced git lines in the BODY, then a REAL push after the
# terminator -> push yes, mutate-then-push NO (the fenced lines are data).
# QUOTED delimiter: a plan containing ```bash fences MUST use <<'EOF' — an
# unquoted delimiter would make bash treat the backtick fences as live command
# substitution (correctly failing closed), so the realistic, safe workflow is
# the quoted form, which is what this fix keeps precise.
_c2="cat > plan.md <<'PLANEOF'${_NL}- [ ] step:${_NL}\`\`\`bash${_NL}git add -A${_NL}git commit -m x${_NL}\`\`\`${_NL}PLANEOF${_NL}git push"
_assert_pred "P2 trailing real push detected"          0 command_invokes_git_write "${_c2}"
_assert_pred "P2 fenced body lines are not mutations"  1 command_git_mutate_before_push "${_c2}"

# P3/P4 controls: real compounds must keep matching exactly as before.
_assert_pred "P3 control: commit&&push is mutate"      0 command_git_mutate_before_push 'git commit -m x && git push'
_assert_pred "P4 control: bare push is a push"         0 command_invokes_git_write 'git push origin main'
_c4b="cat > doc.md <<EOF${_NL}text${_NL}EOF${_NL}git commit -m x && git push"
_assert_pred "P4b mutate after a heredoc still fires"  0 command_git_mutate_before_push "${_c4b}"

# P5: quoted delimiter behaves like P1.
_c5="cat > notes.md <<'EOF'${_NL}git push origin main${_NL}EOF"
_assert_pred "P5 quoted-delimiter body is data"        1 command_invokes_git_write "${_c5}"
_assert_pred "P5 parse is balanced"                    0 command_parse_balanced "${_c5}"

# P6: <<- with a tab-indented terminator.
_TAB="$(printf '\t')"
_c6="cat <<-END${_NL}git push${_NL}${_TAB}END"
_assert_pred "P6 tab-stripped terminator closes body"  1 command_invokes_git_write "${_c6}"
_assert_pred "P6 parse is balanced"                    0 command_parse_balanced "${_c6}"

# P7: interpreter-fed heredoc EXECUTES its body — the body scans as CODE, so
# the embedded push is detected PRECISELY (design review: discarding it would
# be a brand-new gate bypass; the interpreter allowlist scans instead).
_c7="bash <<EOF${_NL}git push origin main${_NL}EOF"
_assert_pred "P7 bash-fed heredoc body push detected"  0 command_invokes_git_write "${_c7}"
# ...and prose in a bash-fed body must NOT become a false push (body-as-code
# keeps precise semantics, unlike a blanket unbalanced fallback would).
_c7b="bash <<EOF${_NL}echo \"reminder: git push later\"${_NL}EOF"
_assert_pred "P7b bash-fed body prose is not a push"   1 command_invokes_git_write "${_c7b}"

# P8: unterminated heredoc -> unbalanced (fail-closed).
_c8="cat <<EOF${_NL}git push origin main"
_assert_pred "P8 unterminated heredoc is unbalanced"   1 command_parse_balanced "${_c8}"

# P11: unknown heredoc owner (remote/interpreter we can't classify) -> fail
# CLOSED: never silently discard a body that might execute.
_c11="ssh prod-host <<EOF${_NL}git push${_NL}EOF"
_assert_pred "P11 ssh-fed heredoc is unbalanced"       1 command_parse_balanced "${_c11}"
_c11b="python3 - <<PY${_NL}print('git push')${_NL}PY"
_assert_pred "P11b python-fed heredoc is unbalanced"   1 command_parse_balanced "${_c11b}"

# P12: arithmetic `<<` is a shift, not a heredoc — a real push after it must
# not be swallowed as a phantom body (design review: required, not optional).
_assert_pred "P12 \$(( 1<<2 )) then push is a push"    0 command_invokes_git_write "echo \$((1<<2)) && git push origin main"
_assert_pred "P12 parse balanced"                      0 command_parse_balanced "echo \$((1<<2)) && git push origin main"
_c12b="((count<<1)); git commit -m x && git push"
_assert_pred "P12b bare arith then compound is mutate" 0 command_git_mutate_before_push "${_c12b}"

# P13: two heredocs on one line drain FIFO; trailing push still detected.
_c13="cat <<A <<B${_NL}foo${_NL}A${_NL}bar${_NL}B${_NL}git push"
_assert_pred "P13 double heredoc then push is a push"  0 command_invokes_git_write "${_c13}"
_assert_pred "P13 parse balanced"                      0 command_parse_balanced "${_c13}"

# P14: `<<-  EOF` (dash, then blanks) is tab-strip mode with delimiter EOF.
_c14="cat <<-  EOF${_NL}git push${_NL}${_TAB}EOF${_NL}git push origin main"
_assert_pred "P14 blanks after dash; trailing push"    0 command_invokes_git_write "${_c14}"
_assert_pred "P14 parse balanced"                      0 command_parse_balanced "${_c14}"

# P15: delimiters we cannot locate a terminator for -> unbalanced.
_c15="cat <<\$FOO${_NL}x${_NL}\$FOO"
_assert_pred "P15 \$-delimiter is unbalanced"          1 command_parse_balanced "${_c15}"
_c15b="cat <<\"EO F\"${_NL}x${_NL}EO F"
_assert_pred "P15b spaced delimiter is unbalanced"     1 command_parse_balanced "${_c15b}"

# P16: git itself is a data sink — a heredoc-fed commit keeps its
# mutate-then-push classification on the CODE part (design review test 11).
_c16="git commit -F - <<EOF${_NL}fix: unrelated text${_NL}EOF${_NL}git push"
_assert_pred "P16 heredoc-fed commit + push is mutate" 0 command_git_mutate_before_push "${_c16}"
_assert_pred "P16 parse balanced"                      0 command_parse_balanced "${_c16}"

# P17: CRLF-pasted heredoc still terminates (CR stripped before compare).
_CR="$(printf '\r')"
_c17="cat > n.md <<EOF${_CR}${_NL}git push origin main${_CR}${_NL}EOF${_CR}${_NL}echo done"
_assert_pred "P17 CRLF heredoc body is data"           1 command_invokes_git_write "${_c17}"
_assert_pred "P17 parse balanced"                      0 command_parse_balanced "${_c17}"

# P9: herestring is NOT a heredoc; same-line string operand, balanced.
_assert_pred "P9 herestring is not a push"             1 command_invokes_git_write 'grep -c push <<< "git push origin"'
_assert_pred "P9 herestring parse balanced"            0 command_parse_balanced 'grep -c push <<< "git push origin"'

# P10: body containing an apostrophe must not poison quote state (#155 class).
_c10="cat > n.md <<EOF${_NL}don't forget${_NL}EOF${_NL}git push"
_assert_pred "P10 apostrophe in body; real push seen"  0 command_invokes_git_write "${_c10}"
_assert_pred "P10 parse is balanced"                   0 command_parse_balanced "${_c10}"

# F1 (review): unquoted delimiter -> body `$(...)`/backtick EXECUTES, so a
# data-sink body is NOT inert. Must fail closed (unbalanced) so the substring
# path sees the embedded push. Quoted delimiter stays inert (balanced).
_c_f1="cat > plan.md <<EOF${_NL}\$(git push origin main)${_NL}EOF"
_assert_pred "F1 unquoted \$() body is unbalanced"     1 command_parse_balanced "${_c_f1}"
_c_f1b="cat > plan.md <<EOF${_NL}\`git push origin main\`${_NL}EOF"
_assert_pred "F1b unquoted backtick body is unbalanced" 1 command_parse_balanced "${_c_f1b}"
_c_f1c="cat > plan.md <<'EOF'${_NL}\$(git push origin main)${_NL}EOF"
_assert_pred "F1c quoted \$() body stays inert"        0 command_parse_balanced "${_c_f1c}"
_assert_pred "F1c quoted \$() body not a push"         1 command_invokes_git_write "${_c_f1c}"

# ---------------------------------------------------------------- guard e2e
GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgh-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# REVIEW+VERIFY armed, nothing completed: a real push DENIES, data must not.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

_run() {
    jq -n --arg tp "$_TPATH" --arg c "$1" \
      '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" PUSH_GATE_CAPTURE_DISABLE=1 bash "${GUARD}" 2>/dev/null
}

# E1: small doc-write heredoc -> no deny (precise path).
out="$(_run "${_c1}")"
assert_not_contains "E1 small heredoc doc-write not gated" '"deny"' "${out:-}"

# E2: LARGE doc-write heredoc (>4096 chars, the production shape) -> no deny.
# Pre-fix, the substring fallback saw `git push` inside the body and the chain
# gate denied a command that pushes nothing (observed at command_len 6082/35036).
_body=""
while [ "${#_body}" -lt 6000 ]; do _body="${_body}filler line for a plan document${_NL}"; done
_c_e2="cat > big-plan.md <<EOF${_NL}${_body}git push origin main${_NL}EOF"
out="$(_run "${_c_e2}")"
assert_not_contains "E2 large heredoc doc-write not gated" '"deny"' "${out:-}"

# E3: plan heredoc + trailing REAL push -> denied (real push, no evidence),
# but NOT as mutate-then-push (the fenced body lines are data).
out="$(_run "${_c2}")"
assert_contains     "E3 real push after heredoc still gated" '"deny"' "${out:-<empty>}"
assert_not_contains "E3 not misclassified as mutate"  'mutates history' "${out:-}"

# E4 control: a genuine compound stays denied AS mutate-then-push.
out="$(_run 'git commit -m x && git push')"
assert_contains "E4 control compound denied as mutate" 'mutates history' "${out:-<empty>}"

# E5: interpreter-fed heredoc with a push in the body stays gated (fail-closed
# substring path must still see it).
out="$(_run "${_c7}")"
assert_contains "E5 bash-fed heredoc push is gated" '"deny"' "${out:-<empty>}"

# E6 (Finding 1 e2e): unquoted-delimiter data-sink body running $(git push)
# must be DENIED, not allowed as inert data.
out="$(_run "${_c_f1}")"
assert_contains "E6 unquoted \$() heredoc push is gated" '"deny"' "${out:-<empty>}"

# E7 (Finding 2 e2e): an unrelated unknown-owner heredoc must NOT disarm the
# mutate-then-push deny for a real inline commit&&push. Seed evidence that
# legitimately covers a PLAIN push at HEAD (clean verdict + review ledger) so
# the ONLY thing that can deny is the compound-specific check.
_seed_mutate_evidence() {
    local _sha; _sha="$(cd "${PROJECT_ROOT}" && git rev-parse HEAD 2>/dev/null)"
    printf '%s' "{\"chain\":[\"requesting-code-review\",\"verification-before-completion\"],\"current_index\":2,\"completed\":[\"requesting-code-review\",\"verification-before-completion\"]}" \
        > "$HOME/.claude/.skill-composition-state-${_TOK}"
    printf '%s' "{\"passed\":[\"tests\"],\"failed\":[],\"could_not_verify\":[],\"gate_gaming_status\":\"clean\",\"sha\":\"${_sha}\"}" \
        > "$HOME/.claude/.skill-project-verified-${_TOK}"
}
_seed_mutate_evidence
_c_f2="python3 - <<PY${_NL}print(1)${_NL}PY${_NL}git commit -m fix && git push origin HEAD"
out="$(_run "${_c_f2}")"
assert_contains "E7 mutate deny survives unrelated heredoc" 'mutates history' "${out:-<empty>}"
# Control: a plain doc-write + push (no mutate verb) is NOT falsely denied as
# mutate-then-push even when the parse is untrusted.
_c_f2b="python3 - <<PY${_NL}print(1)${_NL}PY${_NL}cat > d.md <<EOF${_NL}notes${_NL}EOF${_NL}git push origin HEAD"
out="$(_run "${_c_f2b}")"
assert_not_contains "E7b doc-write+push not mutate-denied" 'mutates history' "${out:-}"

export HOME="$_OLDHOME"
print_summary
exit $?
