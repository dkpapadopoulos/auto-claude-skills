#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-review-dispatch-authorization.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-activation-hook.sh"
_OLDHOME="$HOME"

# Drive the hook with a REVIEW-phase prompt and a controlled HOME.
#
# TWO measured facts are load-bearing here; changing either silently guts this test.
#
# 1. THE PROMPT. The RED_FLAGS `case` keys off the DETECTED PHASE, so the
#    sentinel renders only when the phase is REVIEW. Measured against the real
#    hook: "review the code", "code review please", "requesting code review",
#    and "review my pull request" ALL route to LEARN, not REVIEW. Only a
#    diff-quality phrasing reaches REVIEW. Do not "simplify" this prompt to
#    something that reads more like a review request — it will route to LEARN
#    and every assertion below will fail for the wrong reason.
#
# 2. NO `< /dev/null` HERE. The payload is PIPED in. Adding the redirect
#    overrides the pipe, the hook reads an EMPTY payload, exits 0 with no
#    output, and all four assertions fail confusingly. The standing
#    `< /dev/null` rule applies to hooks invoked WITHOUT a piped payload
#    (e.g. session-start-hook), not to this one.
_REVIEW_PROMPT='check the code quality of this diff'

_run_review() {   # $1 = skill-config.json content, or empty for "no file"
    export HOME="$(mktemp -d /tmp/rda-home-XXXXXX)"
    mkdir -p "$HOME/.claude"
    # The activation hook needs a registry cache; session-start builds it.
    # This one takes NO piped payload, so it DOES need < /dev/null.
    ( cd "${PROJECT_ROOT}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" _SKILL_TEST_MODE=1 \
        bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" >/dev/null 2>&1 < /dev/null )
    [ -n "$1" ] && printf '%s' "$1" > "$HOME/.claude/skill-config.json"
    printf '{"prompt":"%s"}' "${_REVIEW_PROMPT}" \
      | ( cd "${PROJECT_ROOT}" && CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" 2>/dev/null )
}

# (0) VACUITY GUARD — run FIRST. Every assertion below infers "the
# authorization did not render" from the sentinel's absence. That inference is
# only valid if the REVIEW phase was reached at all. Without this guard, a
# routing change turns the whole test green-by-absence in the (b) case and
# red-for-the-wrong-reason everywhere else, and the failure message would send
# the next engineer hunting in the wrong file.
_probe="$(_run_review "")"
if printf '%s' "${_probe}" | grep -qF 'Summarizing changes instead of dispatching'; then
    _record_pass "REVIEW phase is actually reached (test is not vacuous)"
else
    _record_fail "REVIEW phase is actually reached (test is not vacuous)" \
        "the REVIEW red-flag block did not render — the prompt no longer routes to REVIEW, so every assertion below is meaningless"
fi

# (a) No config at all => authorization renders (the default is auto).
if _run_review "" | grep -qF 'REVIEWER DISPATCH:'; then
    _record_pass "default install renders the dispatch authorization"
else
    _record_fail "default install renders the dispatch authorization" "sentinel absent"
fi

# (b) Explicit opt-out => suppressed.
if _run_review '{"phase_enforcement":{"review_dispatch":"ask"}}' | grep -qF 'REVIEWER DISPATCH:'; then
    _record_fail "opt-out suppresses the authorization" "sentinel present despite ask"
else
    _record_pass "opt-out suppresses the authorization"
fi

# (c) Unparseable config => falls back to the DEFAULT (auto), not to silence.
# A config read failure must not restore the stall this feature removes.
if _run_review '{not valid json' | grep -qF 'REVIEWER DISPATCH:'; then
    _record_pass "unparseable config falls back to the authorization"
else
    _record_fail "unparseable config falls back to the authorization" "sentinel absent"
fi

# (d) Explicit auto => renders.
if _run_review '{"phase_enforcement":{"review_dispatch":"auto"}}' | grep -qF 'REVIEWER DISPATCH:'; then
    _record_pass "explicit auto renders the authorization"
else
    _record_fail "explicit auto renders the authorization" "sentinel absent"
fi

export HOME="$_OLDHOME"
print_summary
exit $?
