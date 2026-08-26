#!/usr/bin/env bash
# test-push-gate-jq-absent.sh — issue #213.
#
# With `jq` absent from PATH, hooks/openspec-guard.sh allowed EVERY gated
# command, silently. Not "fell open with an advisory" — silently: empty stdout,
# which the harness cannot distinguish from a deliberate allow. Measured at
# b05925c and again at the #192 fix, so it is neither new nor fixed by #192.
#
# Three causes compound, and this is why fixing only the first changes nothing:
#   1. openspec-guard.sh's no-jq payload fallback greps only "command", never
#      transcript_path, so no token resolves and the hook takes the empty-token
#      exit;
#   2. every check that reads recorded evidence parses it with jq, so seeding a
#      token so one DOES resolve still reaches no trustworthy conclusion;
#   3. every deny is emitted by `jq -n` (7 sites), so a deny that IS reached
#      cannot be emitted.
#
# Do NOT restate (2) as "every gate body is behind `command -v jq`". That was the
# original wording and it is FALSE: routing-governance is gated on _VERDICT_OK —
# the lib loading — not on jq, so without jq it RAN, its verdict predicates all
# returned "not clean" for want of a parser, it denied, and it died at its bare
# `jq -n` emitter. That is how cause 3 was found, and the false premise is why it
# was nearly missed.
#
# The fix is therefore NOT to make the gate work without jq — that would mean
# trusting a hand-rolled JSON parser with a security decision — and NOT to deny
# when jq is missing, which would violate the invariant the gate is built on (a
# check that cannot run must never block) and brick every push on a jq-less
# machine. The fix is to ANNOUNCE, via the one emitter that survives.
#
# CLAUDE.md calls jq "optional at runtime", so a jq-less machine is a supported
# configuration — on which this gate had never once worked and never said so.
#
# THE CONTROL IS THE LOAD-BEARING HALF. Every cell below is paired with the same
# run under a shim that differs ONLY by jq being relinked. Without that pair, a
# shim broken in some unrelated way (a missing `git`, a busted PATH) produces
# the same empty output as the defect and the test would "pass" while measuring
# nothing.
#
# Bash 3.2 compatible (macOS default). No associative arrays.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-push-gate-jq-absent.sh ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq unavailable — this test needs jq to BUILD the jq-less case and to parse the result."
    print_summary
    exit $?
fi

_OLDHOME="$HOME"
_THOME="$(mktemp -d /tmp/pgjq-home-XXXXXX)"
export HOME="${_THOME}"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"     # basename "t" -> token "session-t"

_TROOT="$(mktemp -d /tmp/pgjq-root-XXXXXX)"
cp -R "${PROJECT_ROOT}/hooks"  "${_TROOT}/hooks"
cp -R "${PROJECT_ROOT}/config" "${_TROOT}/config" 2>/dev/null || true

# Two shims differing by exactly one symlink. Built from the real PATH so that
# git, bash, grep, sed and friends stay reachable — the ONLY difference under
# test must be jq.
_NOJQ="$(mktemp -d /tmp/pgjq-nojq-XXXXXX)"
_oIFS="$IFS"; IFS=:
for _d in $PATH; do
    [ -d "$_d" ] || continue
    for _f in "$_d"/*; do
        [ -e "$_f" ] || continue
        _b="$(basename "$_f")"
        [ "$_b" = "jq" ] && continue
        [ -e "${_NOJQ}/$_b" ] && continue
        [ -x "$_f" ] && ln -s "$_f" "${_NOJQ}/$_b" 2>/dev/null
    done
done
IFS="$_oIFS"
_JQREAL="$(command -v jq)"
_WITHJQ="$(mktemp -d /tmp/pgjq-withjq-XXXXXX)"
cp -R "${_NOJQ}/." "${_WITHJQ}/" 2>/dev/null || true
ln -sf "${_JQREAL}" "${_WITHJQ}/jq"

_cleanup() { export HOME="$_OLDHOME"; rm -rf "${_TROOT}" "${_THOME}" "${_NOJQ}" "${_WITHJQ}"; }
trap _cleanup EXIT

# The shims must be usable at all, and must differ ONLY in jq. Asserted rather
# than assumed: a shim missing `git` would make every cell empty for a reason
# that has nothing to do with this issue.
_probe() { env -i PATH="$1" HOME="$HOME" /bin/bash -c 'command -v jq >/dev/null 2>&1 && echo PRESENT || echo ABSENT'; }
_probe_git() { env -i PATH="$1" HOME="$HOME" /bin/bash -c 'command -v git >/dev/null 2>&1 && echo yes || echo no'; }
assert_equals "shim without jq really lacks jq"  "ABSENT"  "$(_probe "${_NOJQ}")"
assert_equals "shim with jq really has jq"       "PRESENT" "$(_probe "${_WITHJQ}")"
assert_equals "the jq-less shim still has git"   "yes"     "$(_probe_git "${_NOJQ}")"

if [ "$(_probe "${_NOJQ}")" != "ABSENT" ] || [ "$(_probe_git "${_NOJQ}")" != "yes" ]; then
    echo "  SKIP: could not build a usable jq-less PATH"
    print_summary
    exit $?
fi

_HEAD="$(git -C "${PROJECT_ROOT}" rev-parse HEAD 2>/dev/null)"
_seed_verdict() {   # a clean verdict so routing-governance is not what denies
    jq -nc --arg s "${_HEAD}" \
        '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}' \
        > "${HOME}/.claude/.skill-project-verified-$1"
}
_seed_verdict "session-t"

jq -n --arg tp "$_TPATH" --arg cmd "git push origin HEAD" \
    '{"transcript_path":$tp,"tool_input":{"command":$cmd}}' > "$HOME/payload.json"

# run <PATH> — the guard, from the real checkout, with an explicit plugin root.
run() {
    ( cd "${PROJECT_ROOT}" && env -i PATH="$1" HOME="$HOME" \
        CLAUDE_PLUGIN_ROOT="${_TROOT}" /bin/bash "${_TROOT}/hooks/openspec-guard.sh" \
        < "$HOME/payload.json" 2>/dev/null )
}

_adv() { printf '%s' "${1:-}" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null || printf ''; }

# ---------------------------------------------------------------------------
# CONTROL — jq present. Proves the shim is otherwise sound and that the pair
# below differs by jq alone. If this is not a deny, every other cell is
# meaningless and the failure should be read here first.
# ---------------------------------------------------------------------------
_CTL="$(run "${_WITHJQ}")"
assert_not_empty "control (jq present): guard produces output" "${_CTL}"
assert_equals "control (jq present): guard DENIES" "deny" \
    "$(printf '%s' "${_CTL}" | jq -r '.hookSpecificOutput.permissionDecision // "NONE"' 2>/dev/null)"
# NOT a bare assert_not_contains: the control DENIES, so its additionalContext
# is empty and "does not contain jq" is trivially true of an empty string — the
# assertion would hold with the whole feature removed. Assert the deny shape
# instead, which is what "no degradation note leaked into the healthy path"
# actually means here.
_ctl_adv="$(_adv "${_CTL}")"
if [ -n "${_ctl_adv}" ]; then
    assert_not_contains "control (jq present): no jq degradation note" "jq" "${_ctl_adv}"
else
    _record_pass "control (jq present): denies outright, carrying no advisory at all"
fi

# ---------------------------------------------------------------------------
# Cause 1 — no jq, and no token resolvable. The payload's transcript_path is
# never parsed, so the hook reaches the empty-token exit. Pre-fix: EMPTY.
# ---------------------------------------------------------------------------
_A="$(run "${_NOJQ}")"
assert_not_empty "no jq, no token: guard is not silent" "${_A}"
assert_contains  "no jq, no token: announces degradation" "GATE DEGRADED" "$(_adv "${_A}")"
assert_contains  "no jq, no token: names jq as the cause" "jq" "$(_adv "${_A}")"
# Matched against the producer's actual wording rather than a paraphrase — the
# guard says "was NOT gated" here, and asserting a lowercase paraphrase failed
# while the feature worked, which is the same class of error as a hand-written
# fixture: the test agreeing with itself instead of with the code.
assert_contains  "no jq, no token: says the command was not gated" "NOT gated" "$(_adv "${_A}")"
assert_contains  "no jq, no token: names the remedy" "Install jq" "$(_adv "${_A}")"

# ---------------------------------------------------------------------------
# Cause 2 — no jq, but a token DOES resolve via the singleton. This is the cell
# that makes the "just parse transcript_path in the fallback" fix insufficient:
# the guard walks the entire gate and reaches nothing it can trust, because every
# check that reads recorded evidence parses it with jq. Pre-fix: EMPTY here too —
# and this is the cell that got further than the empty-token exit and died at
# routing-governance's bare `jq -n`, which is how cause 3 was found.
# ---------------------------------------------------------------------------
printf 'session-t' > "${HOME}/.claude/.skill-session-token"
_B="$(run "${_NOJQ}")"
assert_not_empty "no jq, token resolves: guard is not silent" "${_B}"
assert_contains  "no jq, token resolves: announces degradation" "GATE DEGRADED" "$(_adv "${_B}")"
assert_contains  "no jq, token resolves: names jq as the cause" "jq" "$(_adv "${_B}")"

# ---------------------------------------------------------------------------
# The announcement has to be VALID JSON, or the harness drops it and the guard
# is silent again — inside the code path added to stop being silent. The no-jq
# emitters are printf-based with a `tr` sanitiser, so this is a real risk, not a
# formality. Parsed here with the TEST's jq; the guard ran without one.
# ---------------------------------------------------------------------------
printf '%s' "${_A}" | jq -e . >/dev/null 2>&1 \
    && _record_pass "no-jq announcement is valid JSON (cause 1)" \
    || _record_fail "no-jq announcement is valid JSON (cause 1)" "unparseable: [${_A}]"
printf '%s' "${_B}" | jq -e . >/dev/null 2>&1 \
    && _record_pass "no-jq announcement is valid JSON (cause 2)" \
    || _record_fail "no-jq announcement is valid JSON (cause 2)" "unparseable: [${_B}]"

# A quote or backslash in an interpolated path must not break the JSON. The
# emitters interpolate ${_PLUGIN_ROOT}, so this is reachable from a plugin
# installed under an odd path, not merely theoretical.
_ODD="$(mktemp -d '/tmp/pgjq-odd-XXXXXX')/we ird\\path"
mkdir -p "${_ODD}"
_C="$( cd "${PROJECT_ROOT}" && env -i PATH="${_NOJQ}" HOME="$HOME" \
    CLAUDE_PLUGIN_ROOT="${_ODD}" /bin/bash "${_TROOT}/hooks/openspec-guard.sh" \
    < "$HOME/payload.json" 2>/dev/null )"
if [ -n "${_C}" ]; then
    printf '%s' "${_C}" | jq -e . >/dev/null 2>&1 \
        && _record_pass "announcement stays valid JSON with a backslash in the plugin path" \
        || _record_fail "announcement stays valid JSON with a backslash in the plugin path" \
            "unparseable: [${_C}]"
else
    _record_fail "announcement stays valid JSON with a backslash in the plugin path" \
        "guard emitted nothing at all for an unresolvable plugin root without jq"
fi

# ---------------------------------------------------------------------------
# _json_escape, driven directly over adversarial input.
#
# The end-to-end cells above only exercise whatever bytes a plugin path happens
# to contain, which is a narrow slice of what this helper must survive. It is
# hand-rolled JSON escaping in Bash 3.2 sitting in the code path whose whole
# purpose is to stop silent failure: anything it emits that `jq -e .` rejects is
# dropped by the harness, and the guard is silent again.
#
# The helper is EXTRACTED from the guard, never restated here — a copy would
# keep passing after the real one changed. The first cut of this helper named
# only \n\r\t and a raw BEL slipped through as unparseable output; that is why
# the class is [:cntrl:] and why this table exists.
# ---------------------------------------------------------------------------
_ESC_SRC="$(sed -n '/^_json_escape() {/,/^}/p' "${PROJECT_ROOT}/hooks/openspec-guard.sh")"
assert_contains "extracted the real _json_escape from the guard" "sed" "${_ESC_SRC:-<empty>}"

_esc_roundtrip() {   # prints VALID / INVALID for one payload, via the real helper
    ( eval "${_ESC_SRC}"
      _o="$(printf '{"a":"%s"}' "$(_json_escape "$1")")"
      printf '%s' "${_o}" | jq -e . >/dev/null 2>&1 && echo VALID || echo INVALID )
}

# One row per byte class that has to survive. Payloads are built with printf so
# the control characters are real bytes, not two-character escapes.
assert_equals "escape: plain text"          "VALID" "$(_esc_roundtrip 'hello world')"
assert_equals "escape: double quote"        "VALID" "$(_esc_roundtrip 'say "hi"')"
assert_equals "escape: single backslash"    "VALID" "$(_esc_roundtrip 'a\b')"
assert_equals "escape: TRAILING backslash"  "VALID" "$(_esc_roundtrip 'path\')"
assert_equals "escape: backslash then quote" "VALID" "$(_esc_roundtrip 'a\"b')"
assert_equals "escape: doubled backslash"   "VALID" "$(_esc_roundtrip 'a\\b')"
assert_equals "escape: dollar and backtick" "VALID" "$(_esc_roundtrip '$HOME `id`')"
assert_equals "escape: non-ASCII"           "VALID" "$(_esc_roundtrip 'café — ünïcode')"
assert_equals "escape: the live \\\"warn\\\" note shape" "VALID" \
    "$(_esc_roundtrip 'set to "deny", not \"warn\"')"
assert_equals "escape: real newline"        "VALID" "$(_esc_roundtrip "$(printf 'a\nb')")"
assert_equals "escape: real tab"            "VALID" "$(_esc_roundtrip "$(printf 'a\tb')")"
# The regression that motivated [:cntrl:]. A C0 byte other than \n\r\t.
assert_equals "escape: raw BEL control byte" "VALID" "$(_esc_roundtrip "$(printf 'a\007b')")"
assert_equals "escape: raw VT control byte"  "VALID" "$(_esc_roundtrip "$(printf 'a\013b')")"

# ---------------------------------------------------------------------------
# The announcement must never carry a permissionDecision. A decision on the
# advisory channel would auto-APPROVE the command and suppress every downstream
# warning — turning a "could not check" into an explicit allow (#198's rule).
# ---------------------------------------------------------------------------
# The emptiness guard is the point. `jq -e` ERRORS on empty input, so the else
# branch recorded PASS for an announcement that did not exist — and while the
# routing-governance defect made both of these empty, this pair reported green
# for a guard that was emitting nothing at all. An assertion that cannot tell
# "absent field" from "absent object" is not an assertion.
for _lbl in A B; do
    eval "_o=\"\${_${_lbl}}\""
    if [ -z "${_o}" ]; then
        _record_fail "no-jq announcement carries no permissionDecision (${_lbl})" \
            "there is no output at all to inspect — the guard was silent"
    elif printf '%s' "${_o}" | jq -e '.hookSpecificOutput | has("permissionDecision")' >/dev/null 2>&1; then
        _record_fail "no-jq announcement carries no permissionDecision (${_lbl})" "it does"
    else
        _record_pass "no-jq announcement carries no permissionDecision (${_lbl})"
    fi
done

print_summary
