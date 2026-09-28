#!/usr/bin/env bash
# test-composition-hint-plugin-root.sh — `phase_compositions[*].hints[].text` is
# a rendering surface that reaches the model's prompt, and it must not name a
# plugin-internal file by a path the reader cannot open. Issue #306; defect
# class #248 (four surfaces), #305 (a fifth, `methodology_hints[].hint`).
#
# THE DEFECT. `hooks/skill-activation-hook.sh` accumulates COMPOSITION_HINTS
# from the composition's `hints[].text` VERBATIM. `{{PLUGIN_ROOT}}` was wired
# into the `precondition` renderer by #248 and into the `hint` renderer by #305;
# this third field was missed by both. Three live instances shipped the old
# broken pair:
#
#   bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/scripts/persist-state.sh"
#
# `CLAUDE_PLUGIN_ROOT` is unset in the model's Bash turn (measured `<unset>`,
# zsh 5.9), so that resolves to the USER's repo root, which has no
# `scripts/persist-state.sh` => rc=127. The DISCOVER and DESIGN instances ARE
# the state-persist step, so `discovery_path` / `design_path` are silently never
# written and the PLAN-phase activation guard that reads them degrades with no
# diagnostic.
#
# WHY A RENDER, NOT A STRING MATCH. A substring assertion passes on the broken
# version too — it also contained `scripts/persist-state.sh`. Only resolving the
# rendered path from a repo that is NOT this plugin distinguishes a usable
# instruction from a plausible one. This file therefore renders through the REAL
# hook from a scratch external git repo and then OPENS what it named.
#
# THE SECOND WRITER. `hooks/session-start-hook.sh` REWRITES the DESIGN hint's
# `.text` under the `spec-driven` preset. It carried its own copy of the broken
# pair, so fixing the configs alone left every spec-driven repo broken — and
# `spec-driven` is this repo's own active preset. That is a paired site in the
# sense of [[paired-sites-drift-when-one-is-hand-edited]]: same field, different
# writer, and the config lint cannot see it because it lives in shell.
#
# HARNESS LIMIT, stated rather than papered over. A hint renders only when its
# phase is detected AND at least one skill is selected. DISCOVER and DESIGN are
# reachable from a bare prompt; PLAN is not — it gates on prior session state
# (`design_path`), which this file does not construct. So the PLAN instance is
# held by the STATIC lint only, and the two rc=127 instances (the ones that
# silently break state persistence) are the ones held end-to-end.
#
# Bash 3.2 compatible (macOS default).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-composition-hint-plugin-root.sh ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — the hook exits 0 without it and nothing here can run" >&2
    # `print_summary` RETURNS, it does not exit. Without the explicit exit the
    # SKIP prints a zero-test `All tests passed.` block and then runs the whole
    # file anyway, emitting a SECOND summary — a skip that did not skip, and a
    # spurious all-green frame in the suite log, which is exactly the
    # confusable shape #263's sentinel exists to disambiguate.
    print_summary
    exit $?
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-comphint.XXXXXXXX")" || WORK=""
if [ -z "${WORK}" ] || [ ! -d "${WORK}" ]; then
    echo "FATAL: could not create a temp dir; refusing to run" >&2
    exit 1
fi
trap 'chmod -R u+rwX "${WORK}" 2>/dev/null; rm -rf "${WORK}"' EXIT

# An "external repo": a real git repo that is NOT this plugin and has no
# scripts/ of its own. This is what makes the defect visible at all.
EXT="${WORK}/external-repo"
mkdir -p "${EXT}"
( cd "${EXT}" && git init -q . && printf 'x\n' > a.txt && git add a.txt \
  && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1

if [ ! -e "${EXT}/scripts/persist-state.sh" ]; then
    _record_pass "harness: the external repo has no scripts/persist-state.sh"
else
    _record_fail "harness: the external repo has no scripts/persist-state.sh" \
        "it does — the defect would be invisible here"
fi

# The two phases whose hints carry the rc=127 instances, and a prompt that
# reaches each. See HARNESS LIMIT above for why PLAN is absent.
# HARNESS TRAP, measured: a hint renders only when >=1 skill is SELECTED, and
# the external repo's registry marks every skill this plugin does not own
# `available: false`. So "lets design a caching layer" — which wants
# `brainstorming` from superpowers — selects NOTHING there and renders NOTHING,
# which looks exactly like a broken hint. Both prompts below select a skill the
# plugin itself owns (`product-discovery`, `design-debate`).
DISCOVER_PROMPT="discovery for the new onboarding initiative"
DESIGN_PROMPT="debate the design of the caching layer"

# ---------------------------------------------------------------------------
# build_cache / render — real session-start, real activation hook, run FROM the
# external repo. `< /dev/null` on session-start is mandatory (#142).
#
# `_SKILL_TEST_MODE=1` is NOT optional: session-start REGENERATES
# `${PLUGIN_ROOT}/config/fallback-registry.json` from default-triggers.json, so
# without it a run of this file rewrites a git-tracked file in the checkout it
# is testing.
# ---------------------------------------------------------------------------
build_cache() {
    local home="$1" proot="$2" preset="${3:-}"
    mkdir -p "${home}/.claude"
    if [ -n "${preset}" ]; then
        printf '{"preset":"%s"}\n' "${preset}" > "${home}/.claude/skill-config.json"
    else
        rm -f "${home}/.claude/skill-config.json"
    fi
    ( cd "${EXT}" && HOME="${home}" CLAUDE_PLUGIN_ROOT="${proot}" \
        SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 \
        /bin/bash "${proot}/hooks/session-start-hook.sh" \
        < /dev/null >/dev/null 2>&1 ) || true
}
# render <home> <plugin-root> <prompt> <needle> — the rendered hint line.
render() {
    local home="$1" proot="$2" prompt="$3" needle="$4"
    printf '{"prompt":"%s"}' "${prompt}" \
      | ( cd "${EXT}" && HOME="${home}" CLAUDE_PLUGIN_ROOT="${proot}" \
            SKILL_PROJECT_ROOT="${EXT}" /bin/bash "${proot}/hooks/skill-activation-hook.sh" 2>/dev/null ) \
      | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
      | grep -F "${needle}" | head -1
}

# _persist_path <line> — the SINGLE-QUOTED absolute persist-state.sh path the
# rendered line names. Single quotes are the contract for this instance, not an
# extraction convenience: the text is a shell command the reader pastes, so the
# fix emits `bash '<abs>/scripts/persist-state.sh' …`. Taking the span BETWEEN
# the quotes is also what lets a path containing a space survive.
#
# Deliberately strict. A looser "first absolute run" pattern passed on the
# PRE-FIX line by extracting `/persist-state.sh` out of the middle of the
# `${CLAUDE_PLUGIN_ROOT:-…}` expansion — a cell that reports a path where there
# is none is worse than one that reports nothing.
_persist_path() {
    printf '%s' "${1:-}" | sed -n "s|.*bash '\(/[^']*persist-state\.sh\)'.*|\1|p" | head -1
}

# ===========================================================================
# 1. STATIC LINT — no composition hint may carry an unresolvable plugin path.
# ===========================================================================
# Keyed on the plugin's own top-level directories, with a population floor so a
# config whose shape drifts cannot go green having checked nothing.
echo ""
echo "--- lint: every composition hint's plugin path is placeholder-rooted ---"
for _cfg in "${PROJECT_ROOT}/config/default-triggers.json" "${PROJECT_ROOT}/config/fallback-registry.json"; do
    _base="$(basename "${_cfg}")"

    # `select(type == "string" and . != "")` is load-bearing, not tidiness: a
    # hint object with no `.text` key yields `null`, and `length` COUNTS the
    # null. So a config whose shape drifted would clear this floor while both
    # lints below inspected nothing — measured by review at 23/23 with every
    # `.text` deleted. The sibling file states this caveat about its own floor
    # (`[.hint]` tolerates nulls) and it was not carried across; it is now.
    _n="$(jq '[.phase_compositions[]?.hints[]?.text | select(type == "string" and . != "")] | length' "${_cfg}" 2>/dev/null)"
    case "${_n}" in ''|*[!0-9]*) _n=0 ;; esac
    if [ "${_n}" -ge 10 ]; then
        _record_pass "${_base}: read ${_n} composition hints to lint"
    else
        _record_fail "${_base}: read enough composition hints to lint" \
            "found ${_n} — the lint below would pass having checked nothing"
    fi

    # (a) The broken pair itself. This is the exact shape that shipped.
    _rc=0
    _pair="$(jq -r '
        .phase_compositions | to_entries[] | .key as $p
        | (.value.hints // [])[] | (.text // "")
        | select(test("CLAUDE_PLUGIN_ROOT:-"))
        | "\($p): \(.[0:60])…"
    ' "${_cfg}" 2>/dev/null)" || _rc=$?
    if [ "${_rc}" -ne 0 ]; then
        _record_fail "${_base}: the broken-pair lint ran to completion" \
            "jq exited ${_rc} — it aborted mid-stream, so an empty result is NOT a clean result"
    elif [ -z "${_pair}" ]; then
        _record_pass "${_base}: no composition hint uses the CLAUDE_PLUGIN_ROOT fallback pair"
    else
        _record_fail "${_base}: no composition hint uses the CLAUDE_PLUGIN_ROOT fallback pair" \
            "resolves to the USER's repo root => rc=127:
${_pair}"
    fi

    # (b) Relative plugin FILE paths, backticked AND bare.
    #
    # SCOPE, stated rather than implied — a lint's population is a claim. This
    # matches a plugin directory followed by a path ending in a FILENAME (it
    # must carry an extension). Two deliberate exclusions:
    #
    #   `docs/plans/…` — the USER's own scratch directory, not a plugin file. It
    #     must STAY relative, the same asymmetry #305 pinned for `design/`.
    #   a bare directory mention (`hooks/`, `config/` with no filename) — the
    #     ADVERSARIAL REVIEW hint says "files in `hooks/` or `config/`" as
    #     prose about the repo under review. That is not a path the reader is
    #     asked to open, so requiring an extension is what keeps this lint
    #     pointed at the defect instead of at English.
    #
    # KNOWN LIMIT: an extensionless plugin file named relatively would slip
    # past. No such instance exists today, and narrowing to catch it would
    # re-admit every prose directory mention.
    _rc2=0
    _rel="$(jq -r '
        .phase_compositions | to_entries[] | .key as $p
        | (.value.hints // [])[] | (.text // "")
        | [ match("(^|[^A-Za-z0-9/_.{-])((assets|docs|hooks|scripts|skills|config|tests)/[A-Za-z0-9_*/-]*\\.[A-Za-z0-9]+)"; "g")
            | .captures[1].string ]
        | map(select(startswith("docs/plans/") | not))
        | select(length > 0) | "\($p): \(join(", "))"
    ' "${_cfg}" 2>/dev/null)" || _rc2=$?
    if [ "${_rc2}" -ne 0 ]; then
        _record_fail "${_base}: the relative-path lint ran to completion" "jq exited ${_rc2}"
    elif [ -z "${_rel}" ]; then
        _record_pass "${_base}: no composition hint names a plugin file by relative path"
    else
        _record_fail "${_base}: no composition hint names a plugin file by relative path" \
            "unreachable in an adopting repo:
${_rel}"
    fi

    # (c) THE PLACEHOLDER'S OWN SPELLING. The two lints above are both keyed on
    # what the BROKEN text looked like, so a hint that is neither broken nor
    # correct sails past both. Three ways that happens, all measured:
    #
    #   {{PLUGINROOT}}      a typo. Nothing substitutes it, so the raw brace
    #                       pair reaches the model's prompt. Review measured
    #                       this on PLAN with ZERO cells red, because PLAN has
    #                       no end-to-end coverage (see HARNESS LIMIT).
    #   "{{PLUGIN_ROOT}}"   double-quoted. The expander recognises exactly one
    #                       shell-context marker, `'`, so this silently takes
    #                       the UNESCAPED file-to-read treatment — and it is the
    #                       most natural shell spelling, the very form the three
    #                       fixed instances were migrated away from. A root
    #                       containing `$` or `"` then expands or breaks the
    #                       quoting on paste.
    #   mixed spellings     the dispatch classifies the whole STRING on its
    #                       first match and then rewrites every occurrence, so
    #                       a text carrying both `'{{PLUGIN_ROOT}}` and a bare
    #                       one gets a single treatment for both.
    #
    # One lint covers all three: every `{{…}}` in a hint must be exactly
    # `{{PLUGIN_ROOT}}`, it must not be preceded by a double quote, and a single
    # text must not mix the quoted and bare spellings.
    #
    # POPULATION: this shares the `_n >= 10` floor recorded above, which runs
    # BEFORE it over the same `phase_compositions[*].hints[].text` set. A config
    # that yielded zero texts would fail that floor, so this lint cannot pass
    # vacuously — it does not need a floor of its own, but it DOES depend on
    # that one, so do not reorder them.
    #
    # The mixing predicate keys on the SPELLINGS, not on a count of
    # placeholders: `'{{PLUGIN_ROOT}}/a' and '{{PLUGIN_ROOT}}/b'` is legal and
    # must stay legal, because the escaped branch rewrites every occurrence
    # uniformly and that is correct when they are all quoted. Only a text
    # carrying BOTH a quoted and an unquoted placeholder is ambiguous.
    #
    # Its bare-side probe is anchored (^|[^quote]) rather than a bare negated
    # class. A negated class needs a character to negate, so a bare placeholder
    # at INDEX 0 could not match one, and a text STARTING with a bare
    # placeholder and later carrying a quoted one went unflagged — measured,
    # and it is exactly the shape the spec makes normative. A lint hole rather
    # than a shipped bug (every live hint starts with a label), but this leg is
    # the mitigation the per-text classification was accepted on.
    #
    # NOTE FOR EDITORS: the jq below lives in a SINGLE-QUOTED shell string, so
    # an apostrophe anywhere in it — including in a comment — ends that string
    # and breaks the file. Quotes reach the program only via the '"'"' dance.
    # Keep prose about quoting out here, where it is safe to write.
    _rc3=0
    _spell="$(jq -r '
        .phase_compositions | to_entries[] | .key as $p
        | (.value.hints // [])[] | (.text // "")
        | . as $t
        | [ ( [ match("\\{\\{[^}]*\\}\\}"; "g") | .string ]
              | map(select(. != "{{PLUGIN_ROOT}}")) | map("bad placeholder \(.)") ),
            ( if ($t | test("\"\\{\\{PLUGIN_ROOT\\}\\}")) then ["double-quoted placeholder"] else [] end ),
            ( if ($t | test("'"'"'\\{\\{PLUGIN_ROOT\\}\\}")) and ($t | test("(^|[^'"'"'])\\{\\{PLUGIN_ROOT\\}\\}"))
              then ["mixes quoted and bare spellings in one text"] else [] end )
          ] | add
        | select(length > 0) | "\($p): \(join("; "))"
    ' "${_cfg}" 2>/dev/null)" || _rc3=$?
    if [ "${_rc3}" -ne 0 ]; then
        _record_fail "${_base}: the placeholder-spelling lint ran to completion" "jq exited ${_rc3}"
    elif [ -z "${_spell}" ]; then
        _record_pass "${_base}: every placeholder is spelled {{PLUGIN_ROOT}}, unambiguously quoted"
    else
        _record_fail "${_base}: every placeholder is spelled {{PLUGIN_ROOT}}, unambiguously quoted" \
            "supported spellings are '{{PLUGIN_ROOT}}/…' (pasted command) and bare {{PLUGIN_ROOT}}/… (file to read):
${_spell}"
    fi
done

# ===========================================================================
# 2. THE SECOND WRITER — the spec-driven preset's injected hint text.
# ===========================================================================
# session-start-hook.sh rewrites the DESIGN hint's `.text` for spec-driven
# repos. The config lint above cannot see it: it lives in a shell heredoc.
echo ""
echo "--- lint: the spec-driven injected hint text ---"
# EVERY `.text =` assignment, not the one that happened to be broken.
#
# The first version anchored on `PERSIST DESIGN (spec-driven)`, which is 1 of
# 3 such assignments in this hook — an enumeration of the sites the author
# remembered, which is the same shape as the `set-intent` anchor that review
# measured green-while-broken. The other two (`DESIGN→PLAN CONTRACT`, `CARRY
# SCENARIOS`) name `openspec/changes/<feature-slug>/…`, which is the USER's own
# directory and correctly relative — but nothing stopped a future edit there
# from naming a plugin file, and no config lint can see this file at all.
#
# The floor is what keeps it honest: if the rewrite mechanism is restructured so
# `.text =` no longer matches, this reports rather than passing on an empty set.
#
# THESE LINTS ARE LINE-ORIENTED, and that is sound only because of a constraint
# worth naming rather than assuming: a jq string literal cannot contain a raw
# newline, so each `.text =` assignment MUST be one physical line and a
# violation cannot hide on a continuation. If the mechanism ever moves to
# `--arg`, a heredoc, or string concatenation, a new site becomes invisible AND
# the floor still reads 3 — which is the anchor failure this section exists to
# fix, one level up. Re-derive the floor if that shape changes.
_SS="${PROJECT_ROOT}/hooks/session-start-hook.sh"
_inj_n="$(grep -c '\.text = "' "${_SS}" 2>/dev/null)" || _inj_n=0
case "${_inj_n}" in ''|*[!0-9]*) _inj_n=0 ;; esac
if [ "${_inj_n}" -ge 3 ]; then
    _record_pass "session-start-hook.sh: read ${_inj_n} injected hint texts to lint"
else
    _record_fail "session-start-hook.sh: read enough injected hint texts to lint" \
        "found ${_inj_n} — the rewrite mechanism moved and this lint is now vacuous"
fi
_inj_bad="$(grep -n '\.text = "' "${_SS}" 2>/dev/null | grep 'CLAUDE_PLUGIN_ROOT:-' | cut -c1-120)"
if [ -z "${_inj_bad}" ]; then
    _record_pass "session-start-hook.sh: no injected hint uses the CLAUDE_PLUGIN_ROOT fallback pair"
else
    _record_fail "session-start-hook.sh: no injected hint uses the CLAUDE_PLUGIN_ROOT fallback pair" \
        "the config fix is defeated for every repo using that preset:
${_inj_bad}"
fi
# A relative plugin FILE path, same population, same reasoning as the config
# lint. `openspec/` is NOT a plugin directory, so the user's own change folder
# is correctly untouched by this.
#
# The `docs/plans/` exclusion below is currently DEAD, and is kept deliberately
# rather than removed: the live string is `docs/plans/YYYY-MM-DD-<slug>-plan.md`,
# whose `<` and `>` the path character class rejects, so nothing ever reaches
# the filter. It becomes live the moment a concrete filename appears. Do not
# count it as exercised.
_inj_rel="$(grep -n '\.text = "' "${_SS}" 2>/dev/null \
    | grep -oE '(^|[^A-Za-z0-9/_.{-])(assets|docs|hooks|scripts|skills|config|tests)/[A-Za-z0-9_*/-]*\.[A-Za-z0-9]+' \
    | grep -v 'docs/plans/')"
if [ -z "${_inj_rel}" ]; then
    _record_pass "session-start-hook.sh: no injected hint names a plugin file by relative path"
else
    _record_fail "session-start-hook.sh: no injected hint names a plugin file by relative path" \
        "unreachable in an adopting repo:
${_inj_rel}"
fi
# THE SPELLING LINTS MUST REACH THIS WRITER TOO. Review named this explicitly:
# this is the second writer, it lives in shell where no config lint reaches it,
# and it is exactly where the `'\''` near-miss happened. A spelling lint that
# ran only against the two configs would leave the ungated spelling landing
# precisely in a spec-driven repo.
_inj_spell="$(grep -n '\.text = "' "${_SS}" 2>/dev/null \
    | grep -oE '\{\{[^}]*\}\}' | sort -u | grep -v '^{{PLUGIN_ROOT}}$')"
if [ -z "${_inj_spell}" ]; then
    _record_pass "session-start-hook.sh: every injected placeholder is spelled {{PLUGIN_ROOT}}"
else
    _record_fail "session-start-hook.sh: every injected placeholder is spelled {{PLUGIN_ROOT}}" \
        "nothing substitutes these, so the literal braces reach the reader:
${_inj_spell}"
fi
# The double-quoted spelling takes the UNESCAPED treatment silently. In this
# file the placeholder is additionally wrapped for the enclosing single-quoted
# shell string, so the shipped form is `'\''{{PLUGIN_ROOT}}...'\''` — a bare
# `"{{PLUGIN_ROOT}}` here would be both wrong and invisible to the config lint.
if grep -n '\.text = "' "${_SS}" 2>/dev/null | grep -q '\\"{{PLUGIN_ROOT}}'; then
    _record_fail "session-start-hook.sh: no injected placeholder is double-quoted" \
        "a double-quoted placeholder silently takes the unescaped file-to-read treatment"
else
    _record_pass "session-start-hook.sh: no injected placeholder is double-quoted"
fi

# ===========================================================================
# 3. END-TO-END — render from the external repo, then OPEN what it named.
# ===========================================================================
echo ""
echo "--- end-to-end: rendered composition hints resolve outside this plugin ---"
H1="${WORK}/home-default"
build_cache "${H1}" "${PROJECT_ROOT}" ""

_e2e() {
    local label="$1" line="$2"
    if [ -z "${line}" ]; then
        _record_fail "${label}: the hint rendered at all" \
            "empty — the probe prompt no longer reaches this phase, so every cell below is vacuous"
        return
    fi
    _record_pass "${label}: the hint rendered at all"

    if printf '%s' "${line}" | grep -q 'CLAUDE_PLUGIN_ROOT:-'; then
        _record_fail "${label}: no unresolved CLAUDE_PLUGIN_ROOT fallback" \
            "the reader's shell has it unset, so this resolves to their repo root"
    else
        _record_pass "${label}: no unresolved CLAUDE_PLUGIN_ROOT fallback"
    fi

    if printf '%s' "${line}" | grep -q '{{PLUGIN_ROOT}}'; then
        _record_fail "${label}: the placeholder was substituted" \
            "raw {{PLUGIN_ROOT}} reached the prompt — the renderer does not substitute this field"
    else
        _record_pass "${label}: the placeholder was substituted"
    fi

    local p
    p="$(_persist_path "${line}")"
    if [ -z "${p}" ]; then
        _record_fail "${label}: names an absolute persist-state.sh" "none found in: ${line}"
        return
    fi
    _record_pass "${label}: names an absolute persist-state.sh"

    # THE CELL THAT CARRIES THE CLAIM: the path the reader was handed must
    # exist and be readable. The pre-fix text named one that did not.
    #
    # NOT A CONTROL, and the comment used to claim it was: `${p}` is already an
    # absolute, fully-expanded string by this point, so `test -r` consults
    # neither `CLAUDE_PLUGIN_ROOT` nor the cwd. The `cd` and `env -u` are
    # therefore inert here. They are kept because they cost nothing and make the
    # reader's environment explicit, but the cell's content is "absolute and
    # exists", not "survives an unset variable" — the substitution itself is
    # what the derivation and expander cells prove.
    if ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT test -r "${p}" ); then
        _record_pass "${label}: the rendered path OPENS from the external repo"
    else
        _record_fail "${label}: the rendered path OPENS from the external repo" \
            "unreadable => rc=127 for the reader: ${p}"
    fi
}

_e2e "DISCOVER" "$(render "${H1}" "${PROJECT_ROOT}" "${DISCOVER_PROMPT}" 'PERSIST DISCOVERY')"
_e2e "DESIGN"   "$(render "${H1}" "${PROJECT_ROOT}" "${DESIGN_PROMPT}"   'PERSIST DESIGN')"

# Spec-driven: the second writer's output, end to end.
H2="${WORK}/home-specdriven"
build_cache "${H2}" "${PROJECT_ROOT}" "spec-driven"
_SD_LINE="$(render "${H2}" "${PROJECT_ROOT}" "${DESIGN_PROMPT}" 'PERSIST DESIGN (spec-driven)')"
if [ -n "${_SD_LINE}" ]; then
    _e2e "DESIGN/spec-driven" "${_SD_LINE}"
else
    _record_fail "DESIGN/spec-driven: the preset's hint rendered" \
        "empty — the preset did not take effect, so the second writer is untested"
fi

# ===========================================================================
# 3b. THE TWO EXPANDER BRANCHES, executed directly.
# ===========================================================================
# The quoted branch is covered end-to-end above. The BARE branch is not: it is
# PLAN's `scope-conformance.sh`, and PLAN does not render from a bare prompt
# (see HARNESS LIMIT). An untested branch in the function this whole change
# turns on is exactly where the next defect hides, so both branches are lifted
# out of the hook with `sed` and EXECUTED — testing the hook's own code, not a
# hand-copy of it. A hand-copied expander is how #248's test went green over a
# broken escape.
echo ""
echo "--- expander: both branches, lifted from the hook and executed ---"
_FN="$(sed -n '/^_expand_composition_hint_plugin_root() {/,/^}/p' "${PROJECT_ROOT}/hooks/skill-activation-hook.sh")"
_FN_PRE="$(sed -n '/^_expand_precondition_plugin_root() {/,/^}/p' "${PROJECT_ROOT}/hooks/skill-activation-hook.sh")"
if [ -z "${_FN}" ] || [ -z "${_FN_PRE}" ]; then
    _record_fail "expander: both functions lifted from the hook" \
        "sed extracted nothing — the cells below would run against an empty definition"
else
    _record_pass "expander: both functions lifted from the hook"

    # A root containing a single quote AND a space: the two characters that
    # break the two treatments in opposite directions.
    _probe() {
        PLUGIN_ROOT="$1" /bin/bash -c "
            ${_FN_PRE}
            ${_FN}
            _expand_composition_hint_plugin_root \"\$1\"
            printf '%s' \"\${_cprecond}\"
        " _ "$2"
    }

    # Quoted => escaped, and the result must survive a paste as ONE word.
    _got="$(_probe "/o'd plug" "bash '{{PLUGIN_ROOT}}/scripts/persist-state.sh' set-intent")"
    _want="bash '/o'\''d plug/scripts/persist-state.sh' set-intent"
    if [ "${_got}" = "${_want}" ]; then
        _record_pass "expander/quoted: a single quote in the root is escaped"
    else
        _record_fail "expander/quoted: a single quote in the root is escaped" \
            "got:  ${_got}
want: ${_want}"
    fi
    # And it must actually PARSE — the #248 escape bug produced a plausible
    # string that broke the whole pasted line.
    if /bin/bash -c "set -- ${_got}; [ \"\$2\" = \"/o'd plug/scripts/persist-state.sh\" ]" 2>/dev/null; then
        _record_pass "expander/quoted: the escaped result parses as one shell word"
    else
        _record_fail "expander/quoted: the escaped result parses as one shell word" \
            "a paste of this line would break: ${_got}"
    fi

    # Bare => NOT escaped. Shell quotes handed to a Read tool are literal
    # characters that make the path unopenable; backticks delimit the span, so
    # a space survives without them.
    _got2="$(_probe "/o'd plug" 'REVIEW runs `{{PLUGIN_ROOT}}/scripts/scope-conformance.sh`')"
    _want2="REVIEW runs \`/o'd plug/scripts/scope-conformance.sh\`"
    if [ "${_got2}" = "${_want2}" ]; then
        _record_pass "expander/bare: the path is emitted unescaped, for a reader not a shell"
    else
        _record_fail "expander/bare: the path is emitted unescaped, for a reader not a shell" \
            "got:  ${_got2}
want: ${_want2}"
    fi

    # TWO QUOTED placeholders in one text must stay LEGAL and both be escaped.
    # The mixing rule forbids MIXED spellings, not multiple placeholders — the
    # escaped branch rewrites every occurrence uniformly, which is correct when
    # they are all quoted. A lint keyed on a COUNT would reject this, so this
    # cell pins the distinction the lint has to make.
    _got4="$(_probe "/o'd plug" "bash '{{PLUGIN_ROOT}}/scripts/a.sh' && bash '{{PLUGIN_ROOT}}/scripts/b.sh'")"
    _want4="bash '/o'\''d plug/scripts/a.sh' && bash '/o'\''d plug/scripts/b.sh'"
    if [ "${_got4}" = "${_want4}" ]; then
        _record_pass "expander/quoted: two quoted placeholders are both escaped"
    else
        _record_fail "expander/quoted: two quoted placeholders are both escaped" \
            "got:  ${_got4}
want: ${_want4}"
    fi

    # Text with no placeholder must pass through byte-identical.
    _got3="$(_probe "/plug" 'ATLASSIAN: Pull Jira issues and Confluence docs.')"
    if [ "${_got3}" = "ATLASSIAN: Pull Jira issues and Confluence docs." ]; then
        _record_pass "expander/passthrough: hint text with no placeholder is unchanged"
    else
        _record_fail "expander/passthrough: hint text with no placeholder is unchanged" "got: ${_got3}"
    fi
fi

# ===========================================================================
# 4. THE HOOK-HARDCODED INTENT DIRECTIVE — same defect, same hook, no config.
# ===========================================================================
# `SKILL_LINES` carries an INTENT EXTRACTION directive with its own copy of the
# broken pair. It is not `hints[].text`, so neither lint above reaches it, but
# it renders into the same prompt and fails the same way.
echo ""
echo "--- end-to-end: the hook-hardcoded intent directive ---"
# THIS IS RENDERED, NOT GREPPED, and the difference is the whole point.
#
# The first version of this section grepped the hook for the line matching
# `set-intent` and asserted it carried no `CLAUDE_PLUGIN_ROOT:-`. Review
# measured that GREEN WHILE BROKEN: the fix for this site does not live on the
# `set-intent` line at all — that line now reads `bash ${_IE_PS} set-intent …`
# and the path is computed two lines earlier. Reverting those two lines to the
# broken pair leaves the anchored line byte-identical, so the cell passed while
# the hook emitted the rc=127 instruction into the prompt.
#
# The anchor was a substring present in BOTH the fixed and broken versions,
# which means it never distinguished them — it only appeared to, back when the
# path happened to share a line with the anchor. Rendering is immune to that:
# it asserts on what the reader actually receives, wherever it was assembled.
#
# The directive is Scenario 1 (no confirmed intent, no discovery brief) on a
# DESIGN prompt, which is exactly the state the harness above already produces.
_e2e "INTENT" "$(render "${H1}" "${PROJECT_ROOT}" "${DESIGN_PROMPT}" 'set-intent')"

# ===========================================================================
# 5. MUTATION — remove the renderer's substitution; the e2e cells must go red.
# ===========================================================================
# Per [[applying-a-fix-is-not-holding-it]]: a correct guard with no cell that
# fails on its revert is unheld. This copies the plugin, strips the
# substitution from the HINT: branch, and asserts the render breaks. It runs in
# an ISOLATED COPY — never against the checkout under test.
echo ""
echo "--- mutation: stripping the HINT substitution must break the render ---"
MUT="${WORK}/plugin-mutated"
# `.claude/worktrees` is excluded, not just `.git`: run from the main checkout,
# PROJECT_ROOT contains every OTHER session's live worktree (26M measured), and
# copying those is both wasteful and a needless reach into work this test has no
# business touching.
if command -v rsync >/dev/null 2>&1; then
    rsync -a --exclude '.git' --exclude '.claude/worktrees' "${PROJECT_ROOT}/" "${MUT}/" >/dev/null 2>&1
else
    mkdir -p "${MUT}" && ( cd "${PROJECT_ROOT}" && tar cf - --exclude='.git' --exclude='./.claude/worktrees' . ) | ( cd "${MUT}" && tar xf - )
fi

if [ -f "${MUT}/hooks/skill-activation-hook.sh" ]; then
    _record_pass "mutation: the isolated copy exists"

    # ---- DERIVATION, before the copy is mutated -------------------------
    # Every cell above is satisfied by a config hint that HARDCODES the
    # author's own absolute path: lint (a) finds no `CLAUDE_PLUGIN_ROOT:-`,
    # lint (b) skips it (the leading char class excludes a preceding `/`),
    # `_persist_path` extracts it, and `test -r` succeeds on this machine.
    # Section 3b proves the EXPANDER substitutes PLUGIN_ROOT; nothing proved
    # the CONFIG (or the hook's own literal) still contains a placeholder for it
    # to substitute.
    #
    # Rendering the same text from a second plugin root settles it: if the path
    # is derived, it moves; if it is baked in, it does not. The inference holds
    # specifically because HOME differs between the two renders as well — a
    # shared HOME could have made them agree via a cached registry instead.
    #
    # SCOPE, stated because the comment used to imply more: this covers the two
    # sites rendered here — the DESIGN hint (config) and the INTENT directive
    # (the hook's own literal). DISCOVER is structurally identical to DESIGN and
    # PLAN has no end-to-end path at all (see HARNESS LIMIT), so both remain
    # bake-in-passable. The placeholder-spelling lint is what covers those.
    H4="${WORK}/home-derivation"
    build_cache "${H4}" "${MUT}" ""
    _derivation_cell() {
        local label="$1" needle="$2" dpath ppath
        dpath="$(_persist_path "$(render "${H4}" "${MUT}" "${DESIGN_PROMPT}" "${needle}")")"
        ppath="$(_persist_path "$(render "${H1}" "${PROJECT_ROOT}" "${DESIGN_PROMPT}" "${needle}")")"
        if [ -z "${dpath}" ] || [ -z "${ppath}" ]; then
            _record_fail "derivation/${label}: both roots rendered a path" \
                "one render produced none, so the comparison proves nothing (copy=${dpath} orig=${ppath})"
            return
        fi
        if [ "${dpath}" = "${ppath}" ]; then
            _record_fail "derivation/${label}: the rendered path follows the plugin root" \
                "identical from two different roots — the path is BAKED IN, not substituted: ${dpath}"
            return
        fi
        _record_pass "derivation/${label}: the rendered path follows the plugin root"
        # NOTE: this prefix match assumes the hook does NOT canonicalise
        # PLUGIN_ROOT — it takes the env value verbatim today. `mktemp -d` on
        # macOS yields /var/folders/… whose realpath is /private/var/folders/…,
        # so if a `cd … && pwd` normalisation is ever added this goes red for a
        # non-reason. The failure direction is loud, so it is safe; this note is
        # to save the next reader the chase.
        case "${dpath}" in
            "${MUT}/"*) _record_pass "derivation/${label}: the path resolves under the root that rendered it" ;;
            *) _record_fail "derivation/${label}: the path resolves under the root that rendered it" \
                   "expected a path under ${MUT}, got ${dpath}" ;;
        esac
    }
    _derivation_cell "hint"   'PERSIST DESIGN'
    _derivation_cell "intent" 'set-intent'
    # ---------------------------------------------------------------------

    # Strip the marker line the fix adds. Asserting the strip CHANGED something
    # is mandatory — "the pattern is absent afterwards" is equally true when the
    # strip worked and when the pattern never matched.
    cp "${MUT}/hooks/skill-activation-hook.sh" "${WORK}/pre-mutation.sh"
    # SURGICAL, and that matters: deleting every line naming the function takes
    # its DEFINITION too, leaving an orphaned body that is a syntax error. The
    # hook then renders nothing, and "nothing rendered" is a DIFFERENT fault
    # from "the placeholder leaked" — it would pass a sloppy cell for the wrong
    # reason. This replaces only the CALL, with the verbatim pre-fix line.
    sed 's|^\( *\)_expand_composition_hint_plugin_root "\(.*\)"$|\1_cprecond="\2"|' \
        "${WORK}/pre-mutation.sh" > "${MUT}/hooks/skill-activation-hook.sh" 2>/dev/null || true
    if cmp -s "${WORK}/pre-mutation.sh" "${MUT}/hooks/skill-activation-hook.sh"; then
        _record_fail "mutation: the strip changed the hook" \
            "byte-identical — the mutation did not apply, so the cell below proves nothing"
    else
        _record_pass "mutation: the strip changed the hook"

        H3="${WORK}/home-mutated"
        build_cache "${H3}" "${MUT}" ""
        _MUT_LINE="$(render "${H3}" "${MUT}" "${DESIGN_PROMPT}" 'PERSIST DESIGN')"
        if [ -z "${_MUT_LINE}" ]; then
            _record_fail "mutation: the mutated hook still renders the hint" \
                "empty render — the hook broke outright, which is a DIFFERENT fault than the one named"
        else
            _record_pass "mutation: the mutated hook still renders the hint"
            if printf '%s' "${_MUT_LINE}" | grep -q '{{PLUGIN_ROOT}}'; then
                _record_pass "mutation: without the substitution the placeholder leaks (fault reproduced)"
            else
                _record_fail "mutation: without the substitution the placeholder leaks (fault reproduced)" \
                    "the e2e cells above would pass with the fix removed — they hold nothing:
${_MUT_LINE}"
            fi
        fi
    fi
else
    _record_fail "mutation: the isolated copy exists" "copy failed; the mutation cell did not run"
fi

print_summary
