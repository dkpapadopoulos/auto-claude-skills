#!/usr/bin/env bash
# test-skill-plugin-root-reachable.sh — a plugin path named in a file the MODEL
# reads must resolve in the repo the model is standing in. Issue #311; defect
# class #248 (four hook-rendered surfaces), #305 (a fifth), #306 (a sixth,
# plus two more found while fixing it).
#
# THE DEFECT. 37 places under `skills/` and `commands/` tell the model to run
# or read a plugin file by working out where the plugin is. SIX mechanisms:
#
#   ${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}/scripts/x.sh   -> USER's repo root
#   ${CLAUDE_PLUGIN_ROOT:-.}/scripts/x.sh                                  -> the CWD
#   ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh   (bare, no fallback)               -> EMPTY, path starts at /
#   $(dirname "$0")/../scripts/x.sh                                        -> $0 is /bin/zsh, so /bin/../ = /
#   scripts/x.sh                         (bare relative, no derivation)    -> the CWD
#   find ~/.claude/plugins/cache -name auto-claude-skills                  -> CORRECT; must not be normalised
#
# THE COUNT WAS REVISED SIX TIMES (9 -> 13 -> 19 -> 28 -> 36 -> 37) and every
# revision came from changing the METHOD, never from looking harder with the
# same predicate. That is why the lints below are split by what they can see,
# and why each one states its own population.
#
# `CLAUDE_PLUGIN_ROOT` is UNSET in the model's Bash turn — measured `<unset>`,
# zsh 5.9 — so no expansion of it reaches the plugin. The CWD-relative shapes
# are the worse ones: which directory `.` names depends on where the model
# happens to be standing, so they can pick up a same-named script from an
# unrelated tree instead of failing.
#
# WHY #306's FIX CANNOT REACH THESE. `{{PLUGIN_ROOT}}` works because a hook
# renders that text and substitutes before emission. NOTHING renders a
# `SKILL.md` — the Skill tool hands the file to the model as-is. So the
# placeholder must NOT be copied here: it would reach the reader as literal
# braces, which is strictly worse than the pair, since the pair at least
# expands to something.
#
# THE MECHANISM. `session-start-hook.sh` already resolves `PLUGIN_ROOT` to an
# absolute path and already injects a block of capability lines into the
# session context. It now also emits `Plugin root: <abs>`, and the files under
# `skills/` reference THAT instead of re-deriving it. Chosen over deriving from
# the `Base directory for this skill:` line the harness prints because that is
# undocumented output this repo does not control and its test suite cannot
# simulate — and because it does not exist for `lead-prompt.md`, which is not a
# SKILL.md at all.
#
# WHY THIS FILE EXECUTES RATHER THAN MATCHES. A substring assertion passes on
# the broken version too: it also contains `scripts/verify-and-record.sh`. Only
# resolving the path from a repo that is NOT this plugin distinguishes a usable
# instruction from a plausible one. It went unnoticed for the same reason all
# six earlier surfaces did — plugin root and project root are the same
# directory HERE, so every instance is correct exactly where it is tested.
#
# Bash 3.2 compatible (macOS default).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

# ---------------------------------------------------------------------------
# THE THREE LINT PREDICATES, defined ONCE and called TWICE each.
# ---------------------------------------------------------------------------
# Every lint below asserts an ABSENCE, and an absence is equally true of a
# predicate that matches nothing. So each has a red control that seeds a
# violation and requires the predicate to see it.
#
# THE CONTROL MUST CALL THE SAME FUNCTION THE LINT CALLS. The first version of
# these controls re-implemented each predicate inline, and I measured the
# result: neutering the REAL variable lint to a never-matching pattern, with a
# genuine violation naming a REAL plugin script seeded into skills/, left the
# whole file 39/39 GREEN — lint dead, violation present, control passing on its
# own private copy. That is the hand-copied-helper mode this repo documents,
# reproduced while fixing the finding that warned about it.
#
# _lint_* print one line per violation and nothing when clean.

# Any expansion of CLAUDE_PLUGIN_ROOT. Catches mechanisms 1-3.
_lint_var() { grep -rn '\$CLAUDE_PLUGIN_ROOT\|\${CLAUDE_PLUGIN_ROOT' "$@" 2>/dev/null; }

# #306's renderer placeholder, which nothing substitutes in a non-rendered file.
_lint_braces() { grep -rn '{{PLUGIN_ROOT}}' "$@" 2>/dev/null; }

# An INVOCATION-context reference to a plugin file that is not <PLUGIN_ROOT>-rooted.
# Catches mechanisms 4 and 5, which name no variable at all.
_lint_invoke() {
  awk '
    FNR==1 { infence = 0 }
    {
      s = $0; sub(/^[ \t>]+/, "", s)
      if (s ~ /^```/) { infence = !infence; next }
      # INVOCATION CONTEXT outside a fence. Two shapes, and the second was a
      # blind spot that shipped a live violation: an exec VERB inside the
      # backticks (`bash ...`), OR a backticked path invoked DIRECTLY, which
      # has no verb at all. The discriminator for the second is ARGUMENTS -- a
      # path alone is a NAME the reader opens (bare is correct, #248), a path
      # followed by arguments is a COMMAND the reader pastes.
      #
      # KNOWN LIMIT, stated because it is unclosable by span content alone: a
      # backticked path with NO arguments is syntactically identical whether the
      # prose says "run" it or "see" it. Only the surrounding verb separates
      # them, and a verb list is the enumeration this whole change exists to
      # stop trusting. Every live site is decidable -- the commands carry
      # arguments, the references do not -- so the rule fits the corpus without
      # guessing. A future bare-and-run site would slip past; that is the price
      # of not keying on prose.
      inline = ($0 ~ /`(bash|sh|python3|source) /) \
            || ($0 ~ /`[^`]*\.(sh|py|mjs)[ \t][^`]*`/)
      if (!infence && !inline) next
      if ($0 ~ /<PLUGIN_ROOT>/) next
      if (s ~ /^#/) next
      # EXEMPT, with the reason, not silently:
      #  - setup.md references the user COPY made by an explicit `cp` from
      #    PLUGIN_SRC two lines earlier, so the relative path names the USER copy.
      if (FILENAME ~ /commands\/setup\.md$/ && $0 ~ /validate-active-openspec-changes|migrate-docs-plans-to-openspec/) next
      #  - a find over ~/.claude/plugins/cache IS the correct sixth mechanism and
      #    must not be normalised; it is how a reader LOCATES the root.
      if ($0 ~ /plugins\/cache/) next
      if ($0 ~ /(^|[^A-Za-z0-9\/_.<-])(scripts|hooks|tests)\/[A-Za-z0-9_.\/-]+\.(sh|py|mjs)/ \
          || $0 ~ /skills\/[A-Za-z0-9_-]+\/scripts\//                                        \
          || $0 ~ /dirname[ \t]+"?\$0/                                                        \
          || $0 ~ /rev-parse --show-toplevel/) {
        print FILENAME ":" FNR ": " substr($0, 1, 95)
      }
    }' "$@" 2>/dev/null
}

# THE QUOTING RULE, and it is unconditional on purpose.
#
#   A `<PLUGIN_ROOT>` immediately followed by `/` is a PATH and must be
#   single-quoted. A `<PLUGIN_ROOT>` not followed by `/` is the token being
#   named, and is unconstrained.
#
# That is the whole predicate: two characters of span content. No fence
# tracking, no exec-verb list, no arguments discriminator, no exemptions.
#
# THE EARLIER VERSION TRIED TO TELL A COMMAND FROM A REFERENCE, and #248's
# read-vs-paste asymmetry is why. But that rule protects a Read tool from
# receiving quote characters as part of a REAL path -- a hook emits
# /abs/path/file.md, an agent reuses that token verbatim, and the quoted form
# does not exist. The protection is against verbatim reuse of a RESOLVED
# string, and a <PLUGIN_ROOT>-bearing span can never be reused verbatim: it is
# not a path, it does not resolve, and the reader must build a new string
# before it is usable at all. The premise the asymmetry rests on is false for
# every span in this corpus.
#
# Two defects came from trying to draw that line anyway: an `inline` predicate
# that only saw a command when it began with an exec verb, which shipped a live
# unquoted invocation; and an exemption list whose justification was wrong.
# Both are deleted here rather than sharpened.
#
# WHAT KEEPS THIS SOUND is an invariant, not a check: the corpus contains ZERO
# placeholder-bearing READ targets. commands/setup.md:640 was the only one, and
# it now names no path at all because the script it referenced is already run
# with a substitutable quoted path one line below. If a future author adds a
# read target the rule quietly over-quotes it, and that direction is the safe
# one: over-quoting a read fails LOUDLY and names the quotes in its own error,
# while under-quoting a paste silently executes a substitution in the root.
# A design decision recorded once, not a judgement re-made per site.
# WHY THIS LINT HAS NO CONTEXT LOGIC AND ITS NEIGHBOUR DOES. The asymmetry is
# principled, not drift, so do not "unify" them.
#
# This lint's subject is a token that exists ONLY because this change put it
# there. Its mere presence is unambiguous, so surrounding context carries no
# information and deleting the context logic loses nothing.
#
# _lint_invoke's subject is an ordinary FILENAME, which prose uses constantly.
# There, context is the only thing separating "run `gate-gaming-check.sh`" from
# "`gate-gaming-check.sh` is a coarse line-diff". Measured on this tree: a
# target-only predicate there fires on 30 lines of which ZERO are real defects.
# Inventing a prose convention to disambiguate them would be the lint wagging
# the documentation -- it would make every mention less informative about where
# a script lives, and create the authoring-time judgement this side deletes.
#
# WHAT ENFORCES THE READ-TARGET INVARIANT is this rule itself, by construction,
# not a separate cell -- a content check cannot decide whether a quoted path is
# meant to be opened or pasted, which is the same prose problem in a new hat.
# The unconditional rule forbids the BARE spelling, and bare is the only form an
# author following the read-vs-paste convention would write. A read target
# therefore cannot be written in its correct shape, so it cannot appear
# silently: whoever adds one has to quote it, and quoting it makes it safe.
_lint_quote() {
  awk '
    {
      line = $0; n = 0
      while ((i = index(line, "<PLUGIN_ROOT>")) > 0) {
        rest = substr(line, i + 13)
        if (substr(rest, 1, 1) == "/") {
          if (i == 1 || substr(line, i-1, 1) != "\047") n++
        }
        line = rest
      }
      if (n > 0) print FILENAME ":" FNR ": " substr($0, 1, 95)
    }' "$@" 2>/dev/null
}

echo "=== test-skill-plugin-root-reachable.sh ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — session-start exits without emitting context" >&2
    # `print_summary` RETURNS, it does not exit; without this the SKIP prints a
    # zero-test all-green frame and then runs the file anyway.
    print_summary
    exit $?
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-skillroot.XXXXXXXX")" || WORK=""
if [ -z "${WORK}" ] || [ ! -d "${WORK}" ]; then
    echo "FATAL: could not create a temp dir; refusing to run" >&2
    exit 1
fi
trap 'chmod -R u+rwX "${WORK}" 2>/dev/null; rm -rf "${WORK}"' EXIT

# An "external repo": a real git repo that is NOT this plugin and has none of
# the directories the broken pair would resolve into.
EXT="${WORK}/external-repo"
mkdir -p "${EXT}"
( cd "${EXT}" && git init -q . && printf 'x\n' > a.txt && git add a.txt \
  && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1

for _d in scripts hooks skills; do
    if [ ! -e "${EXT}/${_d}" ]; then
        _record_pass "harness: the external repo has no ${_d}/ of its own"
    else
        _record_fail "harness: the external repo has no ${_d}/ of its own" \
            "it does — the defect would be invisible here"
    fi
done

# ---------------------------------------------------------------------------
# 1. THE INJECTION — session-start must emit an absolute, openable plugin root.
# ---------------------------------------------------------------------------
# `_SKILL_TEST_MODE=1` is mandatory: session-start REGENERATES
# `config/fallback-registry.json` from default-triggers.json, so without it a
# run of this file rewrites a git-tracked file in the checkout under test.
# `< /dev/null` is mandatory (#142): the hook reads stdin behind a TTY check,
# and a socket is not a TTY, so it blocks forever waiting for an EOF.
echo ""
echo "--- session-start emits a usable plugin root ---"
CTX="$( cd "${EXT}" && HOME="${WORK}/home" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
        SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 \
        /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" < /dev/null 2>/dev/null \
      | jq -r '.hookSpecificOutput.additionalContext // ""' )"

if [ -n "${CTX}" ]; then
    _record_pass "session-start produced session context at all"
else
    _record_fail "session-start produced session context at all" \
        "empty — every cell below would be vacuous"
fi

_ROOT_LINE="$(printf '%s\n' "${CTX}" | grep -i '^Plugin root:' | head -1)"
if [ -n "${_ROOT_LINE}" ]; then
    _record_pass "session context carries a 'Plugin root:' line"
else
    _record_fail "session context carries a 'Plugin root:' line" \
        "absent — the 13 skills/ sites have nothing to reference"
fi

_ROOT="$(printf '%s' "${_ROOT_LINE}" | sed -n 's/^[Pp]lugin root:[[:space:]]*//p')"
case "${_ROOT}" in
    /*) _record_pass "the emitted plugin root is absolute" ;;
    "") _record_fail "the emitted plugin root is absolute" "no value parsed from: ${_ROOT_LINE}" ;;
    *)  _record_fail "the emitted plugin root is absolute" "relative, so it is CWD-dependent: ${_ROOT}" ;;
esac

# NOT THE CELL THAT CARRIES THE CLAIM, despite how it reads: `_ROOT` is already
# asserted absolute two lines up, so `cd` and `env -u` are inert for `test -d`.
# Measured against a hook mutated to emit `Plugin root: /tmp`, THIS cell passes
# and section 2's cells are what fail. It checks the root exists; sections 3-5
# check that anything is rooted at it.
if [ -n "${_ROOT}" ] && ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT test -d "${_ROOT}" ); then
    _record_pass "the emitted plugin root OPENS from the external repo"
else
    _record_fail "the emitted plugin root OPENS from the external repo" \
        "unopenable for the reader: ${_ROOT}"
fi

# THE NO-JQ PATH, which is where this claim was FALSE. The comment on the
# injection originally said "emitted unconditionally"; it is not — the hook
# exits early when jq is missing, and this file SKIPs without jq, so nothing
# measured it. A no-jq user got 36 sites naming a placeholder defined nowhere.
#
# It is exercised by putting a jq-free directory first on PATH. Only jq is
# hidden: shadowing the whole of /usr/bin would change far more than the one
# variable under test, and a control that alters the environment wholesale
# cannot attribute what it observes.
echo ""
echo "--- the no-jq degraded path still states the plugin root ---"
# The hook tests `command -v jq`, so a failing SHIM is not absence — it is
# found and the normal path runs. jq has to be genuinely off PATH. Per this
# repo's convention, that means symlinking the tools we DO want rather than
# exposing a directory wholesale, which would drag jq back in with them.
_NOJQ="${WORK}/nojq-bin"; mkdir -p "${_NOJQ}"
for _t in sh bash git cat sed grep awk find head tail wc tr sort uniq date uname \
          mkdir cp mv rm chmod ls dirname basename mktemp printf env cut id stat; do
    _src="$(command -v "${_t}" 2>/dev/null)"
    [ -n "${_src}" ] && ln -sf "${_src}" "${_NOJQ}/${_t}" 2>/dev/null
done
_NOJQ_PATH="${_NOJQ}"   # ONE definition: the assertion and the run share it.
if [ -n "$(PATH="${_NOJQ_PATH}" command -v jq 2>/dev/null)" ]; then
    _record_fail "no-jq: jq is absent from the probe PATH" \
        "jq is still reachable, so the cells below would test the NORMAL path"
else
    _record_pass "no-jq: jq is absent from the probe PATH"
fi
_NOJQ_OUT="$( cd "${EXT}" && HOME="${WORK}/home-nojq" CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" \
    SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 PATH="${_NOJQ}" \
    /bin/bash "${PROJECT_ROOT}/hooks/session-start-hook.sh" < /dev/null 2>/dev/null )"
if printf '%s' "${_NOJQ_OUT}" | grep -q 'jq not found'; then
    _record_pass "no-jq: the degraded path was actually taken"
else
    _record_fail "no-jq: the degraded path was actually taken" \
        "jq was not hidden, so the cells below test the normal path: ${_NOJQ_OUT}"
fi
if printf '%s' "${_NOJQ_OUT}" | grep -qF "Plugin root: ${PROJECT_ROOT}"; then
    _record_pass "no-jq: the degraded message still states the plugin root"
else
    _record_fail "no-jq: the degraded message still states the plugin root" \
        "36 sites name <PLUGIN_ROOT> and this path defines it nowhere"
fi
# The hand-built JSON must still PARSE — that is the risk the condition guards.
if printf '%s' "${_NOJQ_OUT}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
    _record_pass "no-jq: the hand-built JSON still parses"
else
    _record_fail "no-jq: the hand-built JSON still parses" \
        "appending the root broke the degraded-mode message entirely"
fi

# THE SKIP BRANCH, which had ZERO coverage. Review measured that neutering the
# guard to a never-matching pattern left the suite fully green, because every
# run used PROJECT_ROOT -- a path containing none of the hostile characters. A
# guard no cell can reach is indistinguishable from one that was never written.
#
# Each root below is a REAL directory holding a copy of the hook, so the hook
# runs from it exactly as an install would. The newline case is the one that was
# broken: `"` and `\` were guarded, a control character was not, and the emitted
# object failed to parse -- losing the whole degraded message, "install jq" and
# all. That is the outcome the guard exists to prevent, reproduced BY the guard.
echo ""
echo "--- no-jq: a root that cannot be represented is omitted, never risked ---"
_hostile_root() {   # <label> <dirname>
    local label="$1" name="$2" root out
    root="${WORK}/roots/${name}"
    mkdir -p "${root}/hooks" 2>/dev/null || { _record_fail "no-jq/${label}: root created" "mkdir failed"; return; }
    cp "${PROJECT_ROOT}/hooks/session-start-hook.sh" "${root}/hooks/" 2>/dev/null
    # ASSERT the precondition here, do not merely arrange it. These cells claim
    # to exercise the no-jq branch and they ARRANGE that by setting PATH — but
    # an arranged absence is not a verified one, and the repo has already
    # measured the failure: a shim PATH that still carried /usr/bin found the
    # system jq, so the cells silently exercised the NORMAL branch and a
    # mutation to the fallback left every assertion green. `scripts/precondition-lint.py`
    # flags exactly this shape, and it flagged this function.
    # It asserts against _NOJQ_PATH, the SAME string the run below uses, not
    # against the shim directory. Checking the directory while the run builds
    # its PATH separately is two sites that can drift: appending `:${PATH}` to
    # the run would restore jq while a directory check stayed happy.
    if [ ! -e "${_NOJQ}/jq" ] && [ -z "$(PATH="${_NOJQ_PATH}" command -v jq 2>/dev/null)" ]; then
        :
    else
        _record_fail "no-jq/${label}: jq really is unresolvable under the arranged PATH" \
            "jq resolves, so this cell would exercise the normal branch and prove nothing"
        return
    fi
    out="$( cd "${EXT}" && HOME="${WORK}/home-${label}" CLAUDE_PLUGIN_ROOT="${root}" \
        SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 PATH="${_NOJQ_PATH}" \
        /bin/bash "${root}/hooks/session-start-hook.sh" < /dev/null 2>/dev/null )"
    # The invariant is the SAME for every root: whatever is emitted must parse.
    if printf '%s' "${out}" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        _record_pass "no-jq/${label}: the emitted object still parses"
    else
        _record_fail "no-jq/${label}: the emitted object still parses" \
            "the degraded message is lost entirely, including the install-jq instruction"
    fi
    # And the message itself must survive, or the guard traded one loss for another.
    if printf '%s' "${out}" | grep -q 'jq not found'; then
        _record_pass "no-jq/${label}: the install-jq instruction survives"
    else
        _record_fail "no-jq/${label}: the install-jq instruction survives" "message missing"
    fi
}
if command -v python3 >/dev/null 2>&1; then
    _hostile_root plain     'plain'
    _hostile_root quote     'we"ird'
    _hostile_root backslash 'back\slash'
    _hostile_root newline   "$(printf 'new\nline')"
    # The POSITIVE control: a representable root must still STATE the value, or
    # a guard that silently omits everything would pass all the cells above.
    _ok="$( cd "${EXT}" && HOME="${WORK}/home-okroot" CLAUDE_PLUGIN_ROOT="${WORK}/roots/plain" \
        SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 PATH="${_NOJQ}" \
        /bin/bash "${WORK}/roots/plain/hooks/session-start-hook.sh" < /dev/null 2>/dev/null )"
    if printf '%s' "${_ok}" | grep -qF "Plugin root: ${WORK}/roots/plain"; then
        _record_pass "no-jq: a representable root is still STATED (guard is not refusing everything)"
    else
        _record_fail "no-jq: a representable root is still STATED (guard is not refusing everything)" \
            "the guard omits even a safe path, so the cells above pass on silence"
    fi
else
    _record_fail "no-jq: python3 available to validate the emitted JSON" \
        "cannot check parseability; these cells did not run"
fi

# ---------------------------------------------------------------------------
# 2. A STALENESS CHECK — every plugin script NAMED still exists in the plugin.
# ---------------------------------------------------------------------------
# WHAT THIS IS NOT: a rooting backstop. Review measured it passing on a site
# that is broken — it harvests the script NAME out of the broken line and then
# confirms that NAME resolves under the root, so the cell's subject and its
# evidence are the same string. Seeded defects naming REAL plugin scripts scored
# 1 of 3 here. The rooting checks are sections 3-5; this one only catches a
# renamed or deleted script (it did catch one: `coverage-adequacy-check.sh` was
# named at a path that is wrong even inside the plugin).
#
# The harvest is grep with a three-alternative group. NOTE for the next author:
# ugrep 7.8.4 returns 0 on `(a|b)/[class containing '.']+\.<literal>` where BSD
# grep returns a match — measured. THIS pattern is unaffected (43 raw / 21
# distinct under both binaries, verified), but a two-alternative variant of it
# is not, so re-measure under both if you edit it.
echo ""
echo "--- every plugin script named under skills/ resolves under the emitted root ---"
_named="$(grep -rhoE '(scripts|hooks/lib|skills/[A-Za-z0-9_-]+/scripts)/[A-Za-z0-9_.-]+\.sh' \
            "${PROJECT_ROOT}/skills/" 2>/dev/null | sort -u)"
_named_n="$(printf '%s\n' "${_named}" | grep -c . )"
case "${_named_n}" in ''|*[!0-9]*) _named_n=0 ;; esac
if [ "${_named_n}" -ge 5 ]; then
    _record_pass "read ${_named_n} distinct plugin scripts named under skills/"
else
    _record_fail "read enough plugin scripts named under skills/" \
        "found ${_named_n} — the loop below would check almost nothing"
fi
# FED BY HEREDOC, NOT A PIPE. `printf … | while` runs the loop in a SUBSHELL,
# so every _record_pass/_record_fail inside it updates a counter that is then
# discarded — the cells execute, report nothing, and the file looks smaller
# rather than failing. Measured on the first run of this file: the loop ran
# against an empty root and not one of its failures reached the summary.
while IFS= read -r _rel; do
    [ -z "${_rel}" ] && continue
    if [ -n "${_ROOT}" ] && [ -r "${_ROOT}/${_rel}" ]; then
        _record_pass "resolves under the emitted root: ${_rel}"
    else
        _record_fail "resolves under the emitted root: ${_rel}" \
            "missing: ${_ROOT:-<no root emitted>}/${_rel}"
    fi
done <<EOF
${_named}
EOF

# ---------------------------------------------------------------------------
# 3. THE LINT — no file the model reads may re-derive the plugin root.
# ---------------------------------------------------------------------------
# Population floor first: keyed on the files, so a `skills/` that stopped
# matching cannot let this pass having inspected nothing.
echo ""
echo "--- lint: no skills/ file re-derives the plugin root ---"
_files_n="$(find "${PROJECT_ROOT}/skills" -type f -name '*.md' 2>/dev/null | grep -c . )"
case "${_files_n}" in ''|*[!0-9]*) _files_n=0 ;; esac
if [ "${_files_n}" -ge 20 ]; then
    _record_pass "lint population: ${_files_n} markdown files under skills/"
else
    _record_fail "lint population: enough markdown files under skills/" \
        "found ${_files_n} — the lint below would be near-vacuous"
fi

# EVERY shape, keyed on the EXPANSION rather than on a list of fallbacks.
#
# Three shapes shipped — `:-$(git rev-parse …)`, `:-.`, and a bare
# `$CLAUDE_PLUGIN_ROOT` with no fallback at all — and the count of them was
# wrong twice while this was being fixed (9, then 13, then 19). A lint keyed on
# the spellings that happened to ship is an enumeration, and every enumeration
# in this repo has rotted. Keying on `$CLAUDE_PLUGIN_ROOT` / `${CLAUDE_PLUGIN_ROOT`
# catches all three and anything else, because re-deriving the root requires
# EXPANDING the variable.
#
# It matches the expansion, not the bare name, so that prose may still SAY
# `CLAUDE_PLUGIN_ROOT` — the per-file note tells the reader not to re-derive it
# and names it to explain why, which is the guidance that prevents the next
# recurrence. Narrowing a warning until it stops firing buys silence; this
# narrows it to the thing that can actually be a defect.
#
# KNOWN LIMIT: a use that reaches the variable without a `$` (`env CLAUDE_PLUGIN_ROOT=…`,
# indirect expansion) would pass. No such use exists, and in a file that tells
# the model to run a command the value has to be expanded to be used.
_bad="$(_lint_var "${PROJECT_ROOT}/skills/" "${PROJECT_ROOT}/commands/" | sed "s|^${PROJECT_ROOT}/||" | cut -c1-120)"
if [ -z "${_bad}" ]; then
    _record_pass "no file under skills/ names CLAUDE_PLUGIN_ROOT"
else
    _record_fail "no file under skills/ names CLAUDE_PLUGIN_ROOT" \
        "unset in the model's shell, so each of these resolves somewhere else:
${_bad}"
fi

# #306's placeholder must NOT have been copied here: nothing substitutes it in
# a file the Skill tool hands over verbatim, so it would reach the reader as
# literal braces — strictly worse than the pair it replaced, which at least
# expanded to something. This is the obvious wrong fix, so it is pinned.
_ph="$(_lint_braces "${PROJECT_ROOT}/skills/" "${PROJECT_ROOT}/commands/" | sed "s|^${PROJECT_ROOT}/||" | cut -c1-120)"
if [ -z "${_ph}" ]; then
    _record_pass "no file under skills/ carries an unsubstitutable {{PLUGIN_ROOT}}"
else
    _record_fail "no file under skills/ carries an unsubstitutable {{PLUGIN_ROOT}}" \
        "nothing renders a SKILL.md, so these reach the reader as literal braces:
${_ph}"
fi

# ---------------------------------------------------------------------------
# 4. THE CONVENTION IS EXPLAINED WHERE IT IS USED.
# ---------------------------------------------------------------------------
# `<PLUGIN_ROOT>` is an angle-bracket placeholder, matching how these same files
# already mark substitution points (`<plan-file>`, `<discovery-doc>`). That
# choice is what keeps the word-count ratchet on incident-analysis at zero
# growth — an assignment line per block cost +12 there, against zero headroom.
#
# The trade is that nothing in the SKILL.md itself says what to substitute, so
# the session-context line is carrying the whole explanation. If that line ever
# stops naming the placeholder, every one of these files silently becomes a
# puzzle. These two cells are what make that a loud failure instead.
echo ""
echo "--- the placeholder convention is explained in the injected context ---"
_uses="$(grep -rl '<PLUGIN_ROOT>' "${PROJECT_ROOT}/skills/" 2>/dev/null | grep -c . )"
case "${_uses}" in ''|*[!0-9]*) _uses=0 ;; esac
if [ "${_uses}" -ge 10 ]; then
    _record_pass "${_uses} files under skills/ use the <PLUGIN_ROOT> placeholder"
else
    _record_fail "enough files under skills/ use the <PLUGIN_ROOT> placeholder" \
        "found ${_uses} — either the convention was abandoned or this cell is stale"
fi
if printf '%s\n' "${CTX}" | grep -qF '<PLUGIN_ROOT>'; then
    _record_pass "the injected context names the <PLUGIN_ROOT> placeholder it expects readers to substitute"
else
    _record_fail "the injected context names the <PLUGIN_ROOT> placeholder it expects readers to substitute" \
        "the placeholder is used in ${_uses} files and explained nowhere the reader can see"
fi

# EVERY USE MUST BE QUOTED, and this is the cell that makes the whole design
# safe rather than merely lucky.
#
# The argument for an angle-bracket placeholder is that an unsubstituted paste
# fails LOUDLY and self-diagnostically — measured under both bash and zsh:
#
#   bash "<PLUGIN_ROOT>/scripts/x.sh"  ->  bash: <PLUGIN_ROOT>/scripts/x.sh: No such file or directory
#
# which names its own cause, unlike the shapes it replaced (`/scripts/x.sh`
# reads as a missing file; `./scripts/x.sh` reads as the wrong directory).
#
# That holds ONLY while the placeholder is quoted. Unquoted, `<` is a REDIRECT
# operator, so the command would silently read from a file named `PLUGIN_ROOT`
# or fail with a parse error — a different and nastier failure than the defect
# this change removes. All uses are quoted today; nothing but this cell keeps
# them that way.
# TWO HOLES REVIEW MEASURED IN THE FIRST VERSION OF THIS CELL, both fixed here:
#
# (a) It exempted a leading BACKTICK. A backtick is markdown inline code, NOT
#     shell quoting — `<PLUGIN_ROOT>/scripts/x.sh` in prose renders as a command
#     with an unquoted redirect. Seeded into a copy, the file scored 34/35 and
#     the failure was a DIFFERENT cell; this one passed. Only a double quote
#     counts.
# (b) It filtered LINES with `grep -v`, so one quoted use excused an unquoted
#     one beside it: `bash "<PLUGIN_ROOT>/a.sh" && cat <PLUGIN_ROOT>/b.sh`
#     linted clean. It now counts OCCURRENCES per line.
#
# And the consequence is worse than first documented. `<PLUGIN_ROOT>/x` parses
# as `< PLUGIN_ROOT > /x`: with a file named PLUGIN_ROOT in the cwd it exits 0
# and TRUNCATES the target path, and under zsh copies that file's bytes into it.
# Silent and destructive, not a noisy parse error.
# SCOPE: invocation context only. Prose that EXPLAINS the placeholder
# (`commands/skill-explain.md`: "Where `<PLUGIN_ROOT>` is the plugin directory")
# writes it unquoted and correctly so — it is being named, not run. Firing there
# would push the next author to quote a word in a sentence, or to exempt the
# file wholesale, and the second is how a lint dies.
_UNQFILES="$(find "${PROJECT_ROOT}/skills" "${PROJECT_ROOT}/commands" -type f -name '*.md' 2>/dev/null)"
_unq="$(_lint_quote ${_UNQFILES} | sed "s|^${PROJECT_ROOT}/||" | cut -c1-120)"
if [ -z "${_unq}" ]; then
    _record_pass "every <PLUGIN_ROOT> use is quoted, so an unsubstituted paste cannot become a redirect"
else
    _record_fail "every <PLUGIN_ROOT> use is quoted, so an unsubstituted paste cannot become a redirect" \
        "unquoted '<' is a shell redirect, not a literal:
${_unq}"
fi


# ---------------------------------------------------------------------------
# 5. THE INVOCATION LINT — catches a derivation the variable lint cannot see.
# ---------------------------------------------------------------------------
# WHY A SECOND LINT EXISTS. Keying on `$CLAUDE_PLUGIN_ROOT` is an enumeration of
# MECHANISMS, and review found a fourth that never names the variable:
#
#   bash "$(dirname "$0")/../scripts/obs-preflight.sh"
#
# In the model's shell `$0` is `/bin/zsh`, so that is `/bin/../scripts/...` =
# `/scripts/...` — the same filesystem-root failure as a bare expansion, by a
# different route. The population of mechanisms was wrong FOUR times in this one
# change (9 -> 13 -> 19 -> 28), so it is not closable by listing them.
#
# This lint inverts the framing: it asks whether a line that INVOKES or BUILDS a
# path to a plugin file roots that path at <PLUGIN_ROOT>. The targets are files
# this repo owns, so they cannot silently grow a new form.
#
# SCOPE, because a lint's population is a claim: invocation context only — a
# fenced code line, or an inline `bash`/`python3`/`source` command. Prose that
# NAMES a script is deliberately out: measured, a target-only predicate fires on
# 74 lines of which ~9 are real, and a lint that cries wolf gets exempted into
# uselessness.
echo ""
echo "--- lint: a command that runs a plugin file roots it at <PLUGIN_ROOT> ---"
_INVFILES="$(find "${PROJECT_ROOT}/skills" "${PROJECT_ROOT}/commands" -type f -name '*.md' 2>/dev/null)"
_inv="$(_lint_invoke ${_INVFILES} | sed "s|^${PROJECT_ROOT}/||")"
if [ -z "${_inv}" ]; then
    _record_pass "every command that runs a plugin file roots it at <PLUGIN_ROOT>"
else
    _record_fail "every command that runs a plugin file roots it at <PLUGIN_ROOT>" \
        "these resolve outside the plugin for the reader:
${_inv}"
fi

# ---------------------------------------------------------------------------
# 6. RED CONTROLS — each lint must be CAPABLE of failing.
# ---------------------------------------------------------------------------
# Each control calls the SAME _lint_* function the cell above calls, against a
# file seeded with that lint's violation. Neutering a predicate therefore fails
# HERE as well as silently passing there — which is the whole point, and which
# the first version of these controls did not do (see the note by the
# definitions: hand-copied predicates left the file 39/39 green with a lint
# dead and a real violation present).
echo ""
echo "--- red controls: each lint can still fail ---"
_CTL="${WORK}/control"; mkdir -p "${_CTL}"
printf 'x `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"`\n'          > "${_CTL}/var.md"
printf 'x `bash "{{PLUGIN_ROOT}}/scripts/x.sh"`\n'                > "${_CTL}/braces.md"
# ONE SEEDED FILE PER CLAUSE. Review measured that a single control covering
# mechanism 4 left THREE of _lint_invoke's four clauses unheld: deleting the
# bare-relative clause, the skills/*/scripts clause, or the rev-parse clause
# each left the suite 48/48 GREEN, because the one control happened to match a
# neighbouring clause. The first of those is the mutation that would have made
# capture-knowledge's six sites invisible again.
#
# This file argues elsewhere that a list of mechanisms cannot be trusted. That
# argument applies to its OWN clause list, so each clause is held separately.
printf '```bash\nbash "$(dirname "$0")/../scripts/x.sh"\n```\n'        > "${_CTL}/inv.md"
printf '```bash\nbash scripts/x.sh --flag\n```\n'                      > "${_CTL}/inv-bare.md"
printf '```bash\nbash skills/improvement-miner/scripts/x.sh\n```\n'    > "${_CTL}/inv-skills.md"
printf '```bash\nP="$(git rev-parse --show-toplevel)/scripts/x.sh"\n```\n' > "${_CTL}/inv-revparse.md"
printf '```bash\nbash "<PLUGIN_ROOT>/scripts/x.sh"\n```\n'      > "${_CTL}/unq.md"

_control() {  # <label> <predicate> <seeded-file>
    if [ -n "$( "$2" "$3" )" ]; then
        _record_pass "control: ${1} sees its seeded violation"
    else
        _record_fail "control: ${1} sees its seeded violation" \
            "the predicate matches nothing, so the green cell above proves nothing"
    fi
}
_control "the CLAUDE_PLUGIN_ROOT lint"   _lint_var    "${_CTL}/var.md"
_control "the {{PLUGIN_ROOT}} lint"      _lint_braces "${_CTL}/braces.md"
_control "the invocation lint (dirname \$0)"      _lint_invoke "${_CTL}/inv.md"
_control "the invocation lint (bare relative)"   _lint_invoke "${_CTL}/inv-bare.md"
_control "the invocation lint (skills/*/scripts)" _lint_invoke "${_CTL}/inv-skills.md"
_control "the invocation lint (rev-parse)"       _lint_invoke "${_CTL}/inv-revparse.md"
_control "the single-quote lint"         _lint_quote  "${_CTL}/unq.md"

# And the inverse: each predicate must stay SILENT on correct text, or a lint
# that fires on everything would pass every control while being useless.
printf '```bash\nbash %s<PLUGIN_ROOT>/scripts/x.sh%s\n```\n' "'" "'" > "${_CTL}/ok.md"
for _pair in "_lint_var:the CLAUDE_PLUGIN_ROOT lint" "_lint_braces:the {{PLUGIN_ROOT}} lint" \
             "_lint_invoke:the invocation lint" "_lint_quote:the single-quote lint"; do
    _fn="${_pair%%:*}"; _lbl="${_pair#*:}"
    if [ -z "$( "${_fn}" "${_CTL}/ok.md" )" ]; then
        _record_pass "control: ${_lbl} stays silent on correct text"
    else
        _record_fail "control: ${_lbl} stays silent on correct text" \
            "it fires on the shape this change standardises on"
    fi
done

print_summary
