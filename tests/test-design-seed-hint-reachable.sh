#!/usr/bin/env bash
# test-design-seed-hint-reachable.sh — the design-seed hint's paths must resolve
# in the repo the hint is rendered INTO. Issue class: #248.
#
# THE DEFECT. The `design-seed` methodology hint ships in both registries and
# renders on DESIGN/IMPLEMENT prompts mentioning ui / components / screens /
# dashboards / tokens. It named two files by REPO-RELATIVE path:
#
#   assets/design-seed/ADOPT.md
#   docs/design-seed-method.md
#
# Neither exists in an adopting repo — they live in the plugin. Measured from a
# scratch external git repo with the real hook: both paths MISSING, and
# `CLAUDE_PLUGIN_ROOT` is unset in the model's shell (measured `<unset>`, zsh
# 5.9), so the reader cannot re-derive them either. And `ADOPT.md` itself opened
# with a literal `<plugin>` placeholder in its copy command, so even a reader who
# somehow found the file could not run step 1.
#
# It went unnoticed because the paths DO resolve in this repo, where the plugin
# root and the project root are the same directory — the exact shape of #248.
#
# THE FIX. The hook already resolves PLUGIN_ROOT to an absolute path and already
# substitutes `{{PLUGIN_ROOT}}` into a skill's `precondition`. It never did so
# for a `hint`. The configs now carry the placeholder in the hint text and the
# hint renderer fills it in.
#
# WHY THIS TEST EXECUTES RATHER THAN MATCHES. A string assertion passes on the
# broken version too: it contained `assets/design-seed/ADOPT.md` and
# `design-seed-method.md`. Only opening the rendered path, and RUNNING the
# adoption command the file holds, distinguishes a usable instruction from a
# plausible one. Both shells, because the reader is the MODEL (zsh) while every
# hook runs under bash.
#
# THE ASYMMETRY THAT MUST SURVIVE. `design/styleguide.md` in the same hint stays
# RELATIVE on purpose: it names the user's own adopted copy, not a plugin file.
# A future "make every path absolute" pass would break it, so it is pinned.
#
# AND THE PATHS ARE EMITTED BARE, not single-quoted like the `precondition`
# paths. That is deliberate and also pinned: a precondition IS a shell command
# (`source '<path>'`), so #248 quotes it to survive a paste; a hint NAMES a file
# for the agent to read, and shell quotes handed to a Read tool are literal
# characters that break it.
#
# HARNESS NOTE — a hint renders only when at least one skill was SELECTED
# (`_format_output` takes the zero-match branch at TOTAL_COUNT 0 and emits no
# hints). So the probe prompt must both fire the hint's trigger AND select a
# skill from the plugin's own registry; a bare "design the admin ui" selects
# nothing here and rendered nothing, which looks exactly like a broken hint.
# For the same reason config/fallback-registry.json cannot be exercised by
# rendering at all — every skill in it is `available: false` — so its copy of
# the hint is held to the default-triggers copy by an equality cell instead.
#
# Bash 3.2 compatible (macOS default).

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=tests/test-helpers.sh
. "${SCRIPT_DIR}/test-helpers.sh"

echo "=== test-design-seed-hint-reachable.sh ==="
echo ""

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not installed — the hook exits 0 without it and nothing here can run" >&2
    print_summary
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/acs-seedhint.XXXXXXXX")" || WORK=""
if [ -z "${WORK}" ] || [ ! -d "${WORK}" ]; then
    echo "FATAL: could not create a temp dir; refusing to run" >&2
    exit 1
fi
trap 'chmod -R u+rwX "${WORK}" 2>/dev/null; rm -rf "${WORK}"' EXIT

# An "external repo": a real git repo that is NOT this plugin and has no
# assets/ or docs/ of its own.
EXT="${WORK}/external-repo"
mkdir -p "${EXT}"
( cd "${EXT}" && git init -q . && printf 'x\n' > a.txt && git add a.txt \
  && git -c user.email=t@t -c user.name=t commit -q -m init ) >/dev/null 2>&1

# zsh carries the headline claim (the reader is the model's shell). Announce a
# skipped leg rather than silently dropping it.
SHELLS=""
for _sh in /bin/bash /bin/zsh; do
    [ -x "${_sh}" ] && SHELLS="${SHELLS} ${_sh}"
done
case "${SHELLS}" in
    *zsh*) : ;;
    *) echo "WARNING: zsh not installed — the leg that carries this file's headline claim did NOT run." >&2 ;;
esac

# Fires the hint's trigger ("components") AND selects prototype-lab, so the
# output is emitted at all. See HARNESS NOTE above.
UI_PROMPT="prototype the dashboard components"

# ---------------------------------------------------------------------------
# build_cache <home> <plugin-root>   — real session-start, real discovery.
# render_hint <home> <plugin-root>   — real activation hook, from the external
#                                      repo, and prints the DESIGN SEED line.
# `< /dev/null` on session-start is mandatory (#142). The activation hook reads
# its payload from stdin, so its stdin is the pipe, which is EOF-terminated.
#
# `_SKILL_TEST_MODE=1` is NOT optional here: session-start REGENERATES
# `${PLUGIN_ROOT}/config/fallback-registry.json` from default-triggers.json, so
# without it a run of this file rewrites a git-tracked file in the checkout it is
# testing. Measured while mutation-testing this change: a mutation applied to
# default-triggers.json propagated into fallback-registry.json and the restore
# silently dropped the real edit. The flag is the hook's own suppression (it also
# skips the live `claude mcp add`) and does not affect cache building.
# ---------------------------------------------------------------------------
build_cache() {
    local home="$1" proot="$2"
    ( cd "${EXT}" && HOME="${home}" CLAUDE_PLUGIN_ROOT="${proot}" \
        SKILL_PROJECT_ROOT="${EXT}" _SKILL_TEST_MODE=1 \
        /bin/bash "${proot}/hooks/session-start-hook.sh" \
        < /dev/null >/dev/null 2>&1 ) || true
}
render_hint() {
    local home="$1" proot="$2"
    printf '{"prompt":"%s"}' "${UI_PROMPT}" \
      | ( cd "${EXT}" && HOME="${home}" CLAUDE_PLUGIN_ROOT="${proot}" \
            SKILL_PROJECT_ROOT="${EXT}" /bin/bash "${proot}/hooks/skill-activation-hook.sh" 2>/dev/null ) \
      | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null \
      | grep 'DESIGN SEED' | head -1
}

# _backtick_paths <line> — the absolute paths the hint names, one per line.
# Backticks delimit, so a path containing a space survives extraction.
_backtick_paths() {
    printf '%s' "${1:-}" | awk '
        {
            n = split($0, parts, "`")
            # Odd indices are outside backticks, even indices inside.
            for (i = 2; i <= n; i += 2) if (parts[i] ~ /^\//) print parts[i]
        }'
}

# ---------------------------------------------------------------------------
# 1. RED CONTROL: the pre-fix paths are unresolvable from the external repo.
# ---------------------------------------------------------------------------
# Without this, "the rendered paths resolve" would not establish that the old
# text failed — the whole change could be a no-op dressed as a fix.
echo "--- red control: the pre-fix repo-relative paths ---"
# The external repo must EXIST before the red control means anything: a failed
# `cd` short-circuits the `&&`, `test` never runs, and the cell would record PASS
# for the wrong reason.
if [ -d "${EXT}" ] && [ -f "${EXT}/a.txt" ]; then
    _record_pass "the external repo was created (the red control below is meaningful)"
else
    _record_fail "the external repo was created" \
        "${EXT} missing or empty — every cell in this file is testing nothing"
fi
for _old in assets/design-seed/ADOPT.md docs/design-seed-method.md; do
    if ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT test -f "${_old}" ); then
        _record_fail "pre-fix path '${_old}' is unresolvable in an external repo" \
            "it resolved — the external repo is not external enough and every cell below is weakened"
    else
        _record_pass "pre-fix path '${_old}' is unresolvable in an external repo"
    fi
done
# And the input that made this invisible: in THIS repo they do resolve.
for _old in assets/design-seed/ADOPT.md docs/design-seed-method.md; do
    assert_file_exists "…but resolves in the plugin repo (why it went unnoticed): ${_old}" \
        "${PROJECT_ROOT}/${_old}"
done

# ---------------------------------------------------------------------------
# 2. The rendered hint's plugin paths are absolute and open.
# ---------------------------------------------------------------------------
echo ""
echo "--- the rendered hint, from an external repo ---"
HOME_C="${WORK}/home-cache"; mkdir -p "${HOME_C}/.claude"
build_cache "${HOME_C}" "${PROJECT_ROOT}"
if [ -f "${HOME_C}/.claude/.skill-registry-cache.json" ]; then
    _record_pass "session-start built a registry cache from config/default-triggers.json"
else
    _record_fail "session-start built a registry cache from config/default-triggers.json" \
        "no cache — the hook falls back to a registry whose skills are all unavailable, so nothing renders"
fi

_ADOPT_DIR=""
HINT_LINE="$(render_hint "${HOME_C}" "${PROJECT_ROOT}")"
if [ -z "${HINT_LINE}" ]; then
    _record_fail "the design-seed hint renders on '${UI_PROMPT}'" \
        "no DESIGN SEED line — every cell in this section is vacuous"
else
    _record_pass "the design-seed hint renders on '${UI_PROMPT}'"

    # The placeholder must not survive into the rendered text…
    assert_not_contains "no unsubstituted {{PLUGIN_ROOT}} reaches the model" \
        '{{PLUGIN_ROOT}}' "${HINT_LINE}"
    # …and the substitution must have put the real root there. Asserting only
    # the absence above would pass on a hint that dropped the paths entirely.
    assert_contains "the hint names the running plugin root" \
        "${PROJECT_ROOT}/" "${HINT_LINE}"

    # Every absolute path the hint names must open, from the external repo,
    # with CLAUDE_PLUGIN_ROOT unset — the reader's actual conditions. Collected
    # into a variable because the identity cells below read the SAME list; two
    # extractions would let them disagree about what the hint said.
    _paths="$(_backtick_paths "${HINT_LINE}")"
    _n=0
    while IFS= read -r _p; do
        [ -z "${_p}" ] && continue
        _n=$((_n + 1))
        if ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT test -r "${_p}" ); then
            _record_pass "hint path opens from an external repo: ${_p##*/}"
        else
            _record_fail "hint path opens from an external repo: ${_p##*/}" "unreadable: ${_p}"
        fi
        case "${_p}" in */assets/design-seed/ADOPT.md) _ADOPT_DIR="${_p%/*}" ;; esac
    done <<EOF
${_paths}
EOF
    # A floor: with a hint that named no absolute path at all, the loop above
    # would report nothing and this section would pass having checked nothing.
    if [ "${_n}" -ge 2 ]; then
        _record_pass "the hint names >= 2 plugin files (found ${_n})"
    else
        _record_fail "the hint names >= 2 plugin files" "found ${_n}"
    fi

    # IDENTITY, not just readability. `test -r` above says the rendered paths
    # OPEN; it does not say they are the two files the hint exists to send the
    # reader to. Review measured the second path repointed to
    # `{{PLUGIN_ROOT}}/docs/CI.md` with the whole suite green — so the method doc
    # was tied to nothing. Both are pinned by suffix (the prefix is the install
    # root, which legitimately varies).
    for _want in /assets/design-seed/ADOPT.md /docs/design-seed-method.md; do
        _hits=0
        while IFS= read -r _p; do
            [ -z "${_p}" ] && continue
            case "${_p}" in *"${_want}") _hits=$((_hits + 1)) ;; esac
        done <<EOF
${_paths}
EOF
        assert_equals "the hint names exactly one ${_want##*/}" "1" "${_hits}"
    done

    # The deliberate asymmetry: the user's own adopted copy stays relative.
    assert_contains "the adopted copy stays repo-relative" \
        '`design/styleguide.md`' "${HINT_LINE}"
    assert_not_contains "the adopted copy is NOT rewritten into the plugin" \
        "${PROJECT_ROOT}/design/styleguide.md" "${HINT_LINE}"

    # Bare, not shell-quoted — see the header. A quoted path breaks a Read.
    assert_not_contains "plugin paths are emitted bare, not single-quoted" \
        "'${PROJECT_ROOT}/" "${HINT_LINE}"
fi

# The fallback registry cannot render (see HARNESS NOTE), so its copy of the
# hint is held to the rendering one by equality. The two files drifting is the
# recurring PAIRED failure in this repo.
_H_DEF="$(jq -r '.methodology_hints[] | select(.name == "design-seed") | .hint' \
    "${PROJECT_ROOT}/config/default-triggers.json" 2>/dev/null)"
_H_FB="$(jq -r '.methodology_hints[] | select(.name == "design-seed") | .hint' \
    "${PROJECT_ROOT}/config/fallback-registry.json" 2>/dev/null)"
assert_not_empty "default-triggers.json carries the design-seed hint" "${_H_DEF}"
assert_equals "fallback-registry.json's copy is identical (it cannot be render-tested)" \
    "${_H_DEF}" "${_H_FB}"

# ---------------------------------------------------------------------------
# 3. ADOPT.md names nothing the reader cannot obtain.
# ---------------------------------------------------------------------------
echo ""
echo "--- ADOPT.md: the second half of the defect ---"
ADOPT_TXT="$(cat "${PROJECT_ROOT}/assets/design-seed/ADOPT.md" 2>/dev/null)"
assert_not_empty "ADOPT.md is readable" "${ADOPT_TXT}"
assert_not_contains "ADOPT.md carries no <plugin> placeholder" '<plugin>' "${ADOPT_TXT}"
# The other unobtainable form: deriving the path from the env var that is
# measurably unset in the shell the reader is reading in. Naming the variable to
# say it is unset is fine and is what the file now does, so the needles are the
# two EXPANSION forms, not the bare name.
assert_not_contains "ADOPT.md does not derive a path from \$CLAUDE_PLUGIN_ROOT" \
    '$CLAUDE_PLUGIN_ROOT' "${ADOPT_TXT}"
assert_not_contains "ADOPT.md does not derive a path from \${CLAUDE_PLUGIN_ROOT}" \
    '${CLAUDE_PLUGIN_ROOT' "${ADOPT_TXT}"

# ---------------------------------------------------------------------------
# 4. EXECUTE the adoption, from the path the hint rendered.
# ---------------------------------------------------------------------------
# The full chain an agent walks: hint -> absolute ADOPT.md -> its copy command
# -> an adopted design/ the shipped lint can run over. Extracted from the real
# file, never hand-copied.
echo ""
echo "--- the adoption command, extracted and run ---"
if [ -z "${_ADOPT_DIR}" ]; then
    _record_fail "the hint named an absolute ADOPT.md to adopt from" \
        "no */assets/design-seed/ADOPT.md path was rendered — the cells below are vacuous"
else
    _record_pass "the hint named an absolute ADOPT.md to adopt from"
    # EXTRACTION IS ANCHORED AND SINGULAR, and that is not pedantry.
    # `grep 'cp -R' | head -1` knows nothing about the markdown fence, so an
    # earlier `cp -R` in PROSE or in a `#` comment silently wins — and the
    # adoption/overwrite cells run the extracted string with the REAL `cp` on
    # PATH, not the shim. Measured by review: a prose line reached `bash -c`.
    # Given what an unguarded copy did in this very file's history, a sentence
    # containing `>`, `;` or a glob is not a risk worth carrying.
    _cp_n="$(printf '%s\n' "${ADOPT_TXT}" | grep -c '^test .*cp -Rn' | tr -d ' ')"
    case "${_cp_n}" in ''|*[!0-9]*) _cp_n=0 ;; esac
    assert_equals "ADOPT.md has exactly ONE anchored copy command" "1" "${_cp_n}"
    CP_LINE="$(printf '%s\n' "${ADOPT_TXT}" | grep '^test .*cp -Rn' | head -1)"
    assert_contains "the anchored line is the copy" 'cp -Rn' "${CP_LINE}"
    assert_not_empty "ADOPT.md has a copy command" "${CP_LINE}"
    # A CRLF checkout leaves a trailing CR that is INVISIBLE in a failure
    # message, so the command reads as correct while being unrunnable — the
    # needle-defeating input CLAUDE.md already names elsewhere.
    case "${CP_LINE}" in
        *$'\r'*) _record_fail "the copy command carries no carriage return" \
                     "CR found — the extracted command is unrunnable but prints as correct" ;;
        *)       _record_pass "the copy command carries no carriage return" ;;
    esac
    # A `\` continuation would make the single-line extraction a syntax error.
    # This happened: it was added, broke the extraction, and was removed.
    case "${CP_LINE}" in
        *\\) _record_fail "the copy command is self-contained (no line continuation)" \
                 "trailing backslash — a partial paste and this extraction both break" ;;
        *)   _record_pass "the copy command is self-contained (no line continuation)" ;;
    esac
    # It must read from the one thing the reader genuinely holds: the directory
    # it opened this file from.
    assert_contains "the copy command reads from SEED_DIR" 'SEED_DIR' "${CP_LINE}"
    # A SPACED SEED_DIR MUST STILL COPY — asserted by RUNNING it, not by
    # looking for a quote character. The previous form, `assert_contains '"'`,
    # was satisfied by any double quote anywhere on the line: review measured
    # `cp -Rn ${SEED_DIR:?"...message..."}/. design/` passing that needle while
    # the adoption genuinely broke for a spaced path. A plugin cache path under
    # a HOME containing a space is the real case.
    #
    # BASH is the load-bearing leg here, and that inverts this file's usual
    # asymmetry. Measured against the unquoted form: bash FAILS (it word-splits
    # the unquoted scalar) and zsh PASSES, because zsh does not split unquoted
    # scalars at all — the same CLAUDE.md gotcha, arriving as a MASK rather than
    # a hazard. Verifying this cell only under zsh would certify a broken file.
    _sp_seed="${WORK}/sp ace dir/seed"
    mkdir -p "${_sp_seed}"
    cp -R "${_ADOPT_DIR}/." "${_sp_seed}/" 2>/dev/null
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _sd2="${WORK}/spaced-dest-${_b}"; mkdir -p "${_sd2}"
        ( cd "${_sd2}" && env SEED_DIR="${_sp_seed}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
        if [ -r "${_sd2}/design/tokens.css" ]; then
            _record_pass "a SEED_DIR containing spaces still copies (${_b})"
        else
            _record_fail "a SEED_DIR containing spaces still copies (${_b})" \
                "tokens.css absent — the expansion is not quoted in the file"
        fi
    done

    # PASTE SAFETY of the assignment itself. Its default value contains `<` and
    # `>`, which are redirection operators in a shell; they are inert only
    # because they sit inside a `${VAR:-...}` expansion within double quotes.
    # Getting that wrong would redirect on paste instead of assigning, so it is
    # asserted by RUNNING the line rather than by reading it.
    SD_LINE="$(printf '%s\n' "${ADOPT_TXT}" | grep '^SEED_DIR=' | head -1)"
    assert_not_empty "ADOPT.md has a SEED_DIR assignment" "${SD_LINE}"
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _sd_out="$(env -u SEED_DIR "${_sh}" -c "${SD_LINE}"'; printf "%s" "${SEED_DIR}"' 2>/dev/null)"
        assert_not_empty "the SEED_DIR line assigns rather than redirects (${_b})" "${_sd_out}"
        # …and it yields to a caller who already knows the directory, which is
        # what makes the adoption runnable with no editing at all.
        _sd_pre="$(SEED_DIR=/tmp/preset "${_sh}" -c "${SD_LINE}"'; printf "%s" "${SEED_DIR}"' 2>/dev/null)"
        assert_equals "a preset SEED_DIR wins (${_b})" "/tmp/preset" "${_sd_pre}"
    done

    # AN UNSET SEED_DIR MUST NOT EXPAND TO THE FILESYSTEM ROOT.
    #
    # This hazard was INTRODUCED by the fix, not found in the original: the
    # `<plugin>` token it replaced was a literal, so it could not expand to
    # anything. `cp -R "${SEED_DIR}/." design/` with SEED_DIR unset is
    # `cp -R "/." design/`. Measured, by this very test before the guard existed:
    # 123 GB of the filesystem root copied into a temp dir before it was killed.
    # The realistic trigger is not a broken file — it is an agent pasting ONLY
    # the `cp` line, which is exactly what the cell below does.
    #
    # So the guard must ride on the DANGEROUS LINE, not on a neighbouring
    # assignment that a selective paste leaves behind.
    assert_contains "the copy command refuses an unset/empty SEED_DIR" ':?' "${CP_LINE}"

    # THE SHIM CELLS REFUSE TO RUN ON AN EMPTY CP_LINE.
    # The extraction anchor (`^test .*cp -Rn`) embeds the guards under test, so
    # deleting a guard can empty CP_LINE — and `sh -c ""` invokes no `cp`, which
    # every "cp is never reached" cell reads as success. Measured by review at
    # 92999aa: removing the guard scored 69/91 with ALL TEN shim cells PASSING,
    # each of them named for the guard that was gone. An assertion satisfied by
    # the fallback path pins nothing, so the guard is checked before the cells
    # that depend on it rather than after.
    if [ -z "${CP_LINE}" ]; then
        _record_fail "CP_LINE is non-empty before the shim cells run" \
            "empty — every 'cp is never reached' cell below would pass on a command that does not exist"
    else
        _record_pass "CP_LINE is non-empty before the shim cells run"
    fi

    # Asserted through a `cp` SHIM, deliberately. Running the unguarded form for
    # real is the disaster this cell exists to prevent, so a regression must be
    # OBSERVABLE without being destructive: the shim records its arguments and
    # copies nothing, and the assertion is that cp was never reached at all.
    _shimdir="${WORK}/shimbin"; mkdir -p "${_shimdir}"
    {
        printf '#!/bin/sh\n'
        printf 'printf "%%s\\n" "$*" >> "${CP_SHIM_LOG}"\n'
        printf 'exit 0\n'
    } > "${_shimdir}/cp"
    chmod +x "${_shimdir}/cp"
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _ud="${WORK}/unreplaced-${_b}"; mkdir -p "${_ud}"
        _shimlog="${_ud}/cp-invocations"
        : > "${_shimlog}"
        if [ -z "${CP_LINE}" ]; then
            _record_fail "an unset SEED_DIR fails non-zero (${_b})" "CP_LINE empty — nothing was run"
            _record_fail "cp is never reached with an unset SEED_DIR (${_b})" "CP_LINE empty — nothing was run"
            continue
        fi
        _urc=0
        ( cd "${_ud}" && env -u SEED_DIR CP_SHIM_LOG="${_shimlog}" \
            PATH="${_shimdir}:${PATH}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1 || _urc=$?
        if [ "${_urc}" -ne 0 ]; then
            _record_pass "an unset SEED_DIR fails non-zero (${_b})"
        else
            _record_fail "an unset SEED_DIR fails non-zero (${_b})" \
                "exited 0 — a reader could mistake this for a successful adoption"
        fi
        # The cell that matters: cp must never have been invoked, so it can
        # never have been invoked with `/.`.
        _shimseen="$(cat "${_shimlog}" 2>/dev/null)"
        if [ -z "${_shimseen}" ]; then
            _record_pass "cp is never reached with an unset SEED_DIR (${_b})"
        else
            _record_fail "cp is never reached with an unset SEED_DIR (${_b})" \
                "cp would have run with: ${_shimseen}"
        fi
        # And the shim itself must be load-bearing: if PATH interception did not
        # work, the two cells above prove nothing about cp. Establish it
        # positively in the same harness.
        : > "${_shimlog}"
        ( cd "${_ud}" && env CP_SHIM_LOG="${_shimlog}" PATH="${_shimdir}:${PATH}" \
            "${_sh}" -c 'cp probe-arg /dev/null' ) >/dev/null 2>&1
        assert_contains "the cp shim intercepts (positive control, ${_b})" \
            'probe-arg' "$(cat "${_shimlog}" 2>/dev/null)"
    done

    # ADOPTION MUST NOT OVERWRITE A design/ THE READER ALREADY HAS.
    #
    # Measured on the pre-`-n` version: a reader with their own
    # design/styleguide.md had it silently REPLACED by the seed's. That is
    # identical in the version this change replaced, so it is not newly
    # introduced — but this change is what takes ADOPT.md from unopenable to
    # reachable, so it takes the data loss from ~impossible to live. The hint
    # tells such a reader to read their own design/ instead of adopting; ADOPT.md
    # cannot rely on them having read it.
    #
    # The guard is `-n` ON THE COPY ITSELF, for the same partial-paste reason as
    # the `:?` above: a separate pre-flight check is not carried by the one line
    # a reader is most likely to paste. It fails SAFE (reader's files win, and an
    # unsupported `-n` errors rather than clobbering) rather than loud, which is
    # the right trade when the alternative is destroying work.
    assert_contains "the copy command refuses to overwrite existing files" '-Rn' "${CP_LINE}"
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _od="${WORK}/overwrite-${_b}"; mkdir -p "${_od}/design"
        printf 'READER OWN STYLEGUIDE\n' > "${_od}/design/styleguide.md"
        printf 'reader own note\n'       > "${_od}/design/reader-note.md"
        ( cd "${_od}" && env SEED_DIR="${_ADOPT_DIR}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
        assert_equals "an existing design/styleguide.md is NOT overwritten (${_b})" \
            "READER OWN STYLEGUIDE" "$(head -1 "${_od}/design/styleguide.md" 2>/dev/null)"
        assert_equals "an unrelated reader file survives (${_b})" \
            "reader own note" "$(head -1 "${_od}/design/reader-note.md" 2>/dev/null)"
        # The control that keeps the cell above from passing vacuously: the copy
        # must still have RUN, i.e. files the reader did not have do land.
        if [ -r "${_od}/design/tokens.css" ]; then
            _record_pass "…while files the reader lacked still land (${_b})"
        else
            _record_fail "…while files the reader lacked still land (${_b})" \
                "tokens.css absent — the copy did not run, so the two cells above prove nothing"
        fi
    done

    # A SEED_DIR THAT IS SET BUT WRONG MUST NOT BE TRAVERSED.
    #
    # `:?` only catches unset/empty, and `/`, `$HOME` and the plugin root are
    # none of those; `-n` prevents OVERWRITING, not TRAVERSING, so into a fresh
    # design/ nothing collides and a full recursive walk proceeds. Measured via
    # shim: all four reached `cp` with a traversal target before the tokens.css
    # test was added. This was originally documented as an accepted residual gap
    # on the reasoning that step 3 catches it — wrong, because step 3 runs AFTER
    # the copy, and "we notice once your home directory has been copied" is not
    # a control.
    #
    # Asserted through the `cp` shim: the property is that `cp` is NEVER REACHED,
    # which is stronger than any assertion about what it produced, and it is the
    # only safe way to test a traversal target.
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        for _bad_seed in / "${HOME}" "${PROJECT_ROOT}"; do
            _td="${WORK}/traverse-${_b}-$(printf '%s' "${_bad_seed}" | tr -c 'a-zA-Z0-9' '_')"
            mkdir -p "${_td}"
            _tlog="${_td}/cp-invocations"; : > "${_tlog}"
            ( cd "${_td}" && env SEED_DIR="${_bad_seed}" CP_SHIM_LOG="${_tlog}" \
                PATH="${_shimdir}:${PATH}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
            if [ -s "${_tlog}" ]; then
                _record_fail "cp is never reached for SEED_DIR=${_bad_seed} (${_b})" \
                    "cp would have run with: $(cat "${_tlog}")"
            else
                _record_pass "cp is never reached for SEED_DIR=${_bad_seed} (${_b})"
            fi
        done
    done

    # A DECOY DIRECTORY THAT MERELY CONTAINS tokens.css IS NOT THE SEED.
    #
    # Identity by ONE filename is too weak: `tokens.css` is a plausible file in
    # any design-system repo, so a coincidental match sends the copy at that tree
    # instead. Measured before the second marker was added: cp was invoked with
    # the decoy. Two markers (`tokens.css` AND `checks/token-lint.sh`) separate
    # them.
    #
    # This cell exists because the mutation said so: reverting to the single
    # marker failed NOTHING — the traversal cells use `/`, `$HOME` and the plugin
    # root, none of which has a top-level tokens.css, so the fix was unverified
    # until a decoy shaped like the near-miss was added.
    _decoy="${WORK}/decoy-seed"
    mkdir -p "${_decoy}"
    printf '/* someone else design tokens */\n' > "${_decoy}/tokens.css"
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _dd="${WORK}/decoy-dest-${_b}"; mkdir -p "${_dd}"
        _dlog="${_dd}/cp-invocations"; : > "${_dlog}"
        ( cd "${_dd}" && env SEED_DIR="${_decoy}" CP_SHIM_LOG="${_dlog}" \
            PATH="${_shimdir}:${PATH}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
        if [ -s "${_dlog}" ]; then
            _record_fail "cp is never reached for a decoy holding only tokens.css (${_b})" \
                "cp would have run with: $(cat "${_dlog}")"
        else
            _record_pass "cp is never reached for a decoy holding only tokens.css (${_b})"
        fi
    done
    # CONTROL: the real seed must still be ACCEPTED, or the cell above is
    # satisfied by an identity check that rejects everything.
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _ad="${WORK}/decoy-accept-${_b}"; mkdir -p "${_ad}"
        _alog="${_ad}/cp-invocations"; : > "${_alog}"
        ( cd "${_ad}" && env SEED_DIR="${_ADOPT_DIR}" CP_SHIM_LOG="${_alog}" \
            PATH="${_shimdir}:${PATH}" "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
        if [ -s "${_alog}" ]; then
            _record_pass "…and the real seed is still accepted (${_b})"
        else
            _record_fail "…and the real seed is still accepted (${_b})" \
                "cp was never reached for the REAL seed — the identity check rejects everything"
        fi
    done

    # THE `rm` MUST NOT DELETE A design/ADOPT.md THE READER ALREADY HAD.
    # `-n` preserves their file, and an unconditional `rm -f design/ADOPT.md` on
    # the next line then destroyed it — `-n` protecting a file that the following
    # line deletes. The guard compares against the seed's own copy.
    RM_LINE="$(printf '%s\n' "${ADOPT_TXT}" | grep '^cmp -s' | head -1)"
    assert_not_empty "ADOPT.md has a guarded remove" "${RM_LINE}"
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _rd="${WORK}/rmguard-${_b}"; mkdir -p "${_rd}/design"
        printf 'READER OWN ADOPT NOTES\n' > "${_rd}/design/ADOPT.md"
        ( cd "${_rd}" && env SEED_DIR="${_ADOPT_DIR}" "${_sh}" -c "${RM_LINE}" ) >/dev/null 2>&1
        assert_equals "a reader's own design/ADOPT.md survives the remove (${_b})" \
            "READER OWN ADOPT NOTES" "$(head -1 "${_rd}/design/ADOPT.md" 2>/dev/null)"
        # …and the control: the SEED's own copy IS removed, or the guard is just
        # a disabled `rm` and the cell above passes for the wrong reason.
        _rd2="${WORK}/rmguard2-${_b}"; mkdir -p "${_rd2}/design"
        cp "${_ADOPT_DIR}/ADOPT.md" "${_rd2}/design/ADOPT.md"
        ( cd "${_rd2}" && env SEED_DIR="${_ADOPT_DIR}" "${_sh}" -c "${RM_LINE}" ) >/dev/null 2>&1
        if [ -e "${_rd2}/design/ADOPT.md" ]; then
            _record_fail "the seed's own ADOPT.md is removed (${_b})" \
                "still present — the guard disabled the remove entirely"
        else
            _record_pass "the seed's own ADOPT.md is removed (${_b})"
        fi
    done

    # ============================================================
    # THE WHOLE FENCED BLOCK, EXECUTED AS ONE UNIT.
    # ============================================================
    # Every cell above executes THREE hand-picked lines (`^SEED_DIR=`,
    # `^test .*cp -Rn`, `^cmp -s`) out of a six-statement fenced block. Review
    # measured what that costs: reintroducing the unconditional
    # `rm -f design/ADOPT.md` scored 89/91 and the cell whose SUBJECT is that
    # data loss — "a reader's own design/ADOPT.md survives the remove" — PASSED,
    # because the destructive statement was on a line no anchor selects, so it
    # was never in the string the cell ran. Worse, the two cells that did fail
    # pointed at the opposite diagnosis ("the guard disabled the remove").
    #
    # The same blind spot hid a live defect: step 2's `cat > design/adopted.json`
    # was unguarded and destroyed a reader's provenance record, with the suite
    # green. Anchors cannot be trusted to enumerate a block's statements; the
    # block is what a reader pastes, so the block is what must run.
    _fence="${WORK}/adopt-block.sh"
    awk '/^```bash/{f=1;next} /^```/{if(f)exit} f{print}' \
        "${PROJECT_ROOT}/assets/design-seed/ADOPT.md" > "${_fence}"
    _fence_stmts="$(grep -cE '^[^#[:space:]]' "${_fence}" | tr -d ' ')"
    case "${_fence_stmts}" in ''|*[!0-9]*) _fence_stmts=0 ;; esac
    # A floor: if the extraction silently yielded nothing, every cell below
    # would pass having run an empty script.
    if [ "${_fence_stmts}" -ge 4 ]; then
        _record_pass "extracted the fenced block (${_fence_stmts} non-comment lines)"
    else
        _record_fail "extracted the fenced block" \
            "found ${_fence_stmts} non-comment lines — the cells below would run an empty script"
    fi
    # The extracted fence must be the ADOPTION block, by IDENTITY not position.
    # `awk` takes the FIRST ```bash fence and ADOPT.md has a second one (the
    # tokens.json pipeline), so a reordering would silently hand these cells the
    # wrong script.
    if grep -q 'cp -Rn' "${_fence}"; then
        _record_pass "the extracted fence is the adoption block (contains the copy)"
    else
        _record_fail "the extracted fence is the adoption block (contains the copy)" \
            "no 'cp -Rn' — awk picked a different fence and every block cell below is testing the wrong script"
    fi

    # A CHANGE DETECTOR over the statements touching `design/`, deliberately NOT
    # a list of destructive verbs. The first version grepped for
    # `(>|cp -Rn|rm -f) *design/…` and MISSED `tee`, `mv`, `install`, `ln -sf`,
    # `truncate`, `sed -i`, `rsync`, `dd`, `rm -rf design` and even a plain
    # `cp -R` — measured. That is this repo's recurring lesson: a blocklist of
    # command shapes is unsound, and a whitelist/ratchet is what holds. So the
    # COUNT is pinned instead: add or remove a statement touching `design/` and
    # this fails, forcing whoever does it to cover it above and bump the number.
    # The block-execution cells are the real control; this is the tripwire that
    # says "you added a statement nobody covered".
    # TWO derivations, because one constant compared against itself is a single
    # authority: an author who adds a statement and bumps the number satisfies it.
    # These read the same file at different granularities — every statement, and
    # the statements touching `design/` — so adding anything moves the first and
    # adding a design-touching statement moves both. Neither is a hand-written
    # list of the statements, which is the enumeration this file spent four
    # rounds removing; a disagreement is a prompt to look, which is the whole
    # job of the constant.
    # NON-COMMENT LINES, not statements: this counts the heredoc body and its
    # `JSON` terminator too. That is fine for a change detector — any edit moves
    # it — and the label is accurate rather than flattering. The first version
    # called them statements and pinned 8, which was already stale by one from
    # the advisory added above; the cell caught its own author on its first run.
    ADOPT_BLOCK_LINES=9
    ADOPT_DESIGN_STMTS=6
    _dstmt="$(grep -E '^[^#[:space:]]' "${_fence}" | grep -c 'design/' | tr -d ' ')"
    case "${_dstmt}" in ''|*[!0-9]*) _dstmt=0 ;; esac
    # The failure PRINTS the statements. Without that a bump is a judgement call
    # made with no information — the author is told a number changed, not which
    # statement is new, and the cheapest response is to edit the constant.
    if [ "${_dstmt}" = "${ADOPT_DESIGN_STMTS}" ]; then
        _record_pass "the block touches exactly ${ADOPT_DESIGN_STMTS} design/ statements"
    else
        _record_fail "the block touches exactly ${ADOPT_DESIGN_STMTS} design/ statements (found ${_dstmt})" \
            "cover the new statement above, then bump ADOPT_DESIGN_STMTS. Statements now:
$(grep -nE '^[^#[:space:]]' "${_fence}" | grep 'design/' | cut -c1-100)"
    fi
    if [ "${_fence_stmts}" = "${ADOPT_BLOCK_LINES}" ]; then
        _record_pass "the block has exactly ${ADOPT_BLOCK_LINES} non-comment lines"
    else
        _record_fail "the block has exactly ${ADOPT_BLOCK_LINES} non-comment lines (found ${_fence_stmts})" \
            "a line was added or removed; cover it, then bump ADOPT_BLOCK_LINES. Lines now:
$(grep -nE '^[^#[:space:]]' "${_fence}" | cut -c1-100)"
    fi
    # …and the two that WRITE are the ones the cells below exercise, by name.
    for _w in 'design/adopted.json' 'design/ADOPT.md'; do
        if grep -qF "${_w}" "${_fence}"; then
            _record_pass "the block still writes ${_w} (covered below)"
        else
            _record_fail "the block still writes ${_w} (covered below)" \
                "absent — a cell below now asserts about a statement that is gone"
        fi
    done

    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"

        # --- a fresh adoption: the block must produce a usable design/ --------
        _fb="${WORK}/fence-fresh-${_b}"; mkdir -p "${_fb}"
        ( cd "${_fb}" && env SEED_DIR="${_ADOPT_DIR}" "${_sh}" "${_fence}" ) >/dev/null 2>&1
        for _want in tokens.css styleguide.md checks/token-lint.sh adopted.json; do
            if [ -r "${_fb}/design/${_want}" ]; then
                _record_pass "block: fresh adoption produced design/${_want} (${_b})"
            else
                _record_fail "block: fresh adoption produced design/${_want} (${_b})" "missing"
            fi
        done
        if [ -e "${_fb}/design/ADOPT.md" ]; then
            _record_fail "block: the seed's ADOPT.md is removed (${_b})" "still present"
        else
            _record_pass "block: the seed's ADOPT.md is removed (${_b})"
        fi

        # --- a reader who ALREADY has files: NOTHING of theirs is lost --------
        # A WHOLE-TREE SNAPSHOT, not a list of filenames. The previous version
        # named four files under design/ and review measured two escapes at
        # 116/116 green: `rm -f design/reference.html` (a design/ file in neither
        # the survival set nor the fresh-adoption set) and
        # `…; rm -f README.md CLAUDE.md` appended to an existing statement (the
        # count ratchet sees one line, and the damage is outside design/ where
        # nothing looked). Replacing a verb blocklist with a FILE enumeration was
        # the same defect on a different axis; the fix is to enumerate nothing and
        # compare the tree to itself.
        # The launch dir sits inside a WRAPPER whose siblings are snapshotted
        # too. The previous version snapshotted only the launch dir, so a
        # relocation (`cd ..`, `rm -f ../x`) wrote where nothing looked. The
        # guard for that was a `grep` for `cd ` — review measured it missing 11
        # of 16 shapes (subshell and brace grouping, bare `cd`, `pushd`, and the
        # whole `-C` family: `env -C`, `git -C`, `tar -C`, `make -C`,
        # `find -execdir`, which need no `cd` at all). That was the FOURTH
        # blocklist in this file's history, so it is deleted rather than
        # extended: containment is checked instead of spelling forbidden.
        #
        # RESIDUAL, and honest: a statement relocating to an ABSOLUTE path
        # outside the wrapper is not covered by this. The block contains none.
        # A `cd` at the TOP of the block is separately caught by the "it still
        # ran" control below, since the adoption then lands elsewhere.
        _wrap="${WORK}/fence-own-${_b}"
        _fo="${_wrap}/repo"; mkdir -p "${_fo}/design/checks" "${_fo}/src"
        printf 'sibling of the launch dir\n'  > "${_wrap}/sibling.txt"
        mkdir -p "${_wrap}/neighbour"
        printf 'neighbour file\n'             > "${_wrap}/neighbour/keep.txt"
        printf 'READER STYLEGUIDE\n'                        > "${_fo}/design/styleguide.md"
        printf '{"preset":"loud-airy","notes":"mine"}\n'     > "${_fo}/design/adopted.json"
        printf 'READER ADOPT NOTES\n'                        > "${_fo}/design/ADOPT.md"
        printf '/* reader tokens */\n'                       > "${_fo}/design/tokens.css"
        printf 'READER REFERENCE\n'                          > "${_fo}/design/reference.html"
        printf 'reader note\n'                               > "${_fo}/design/notes.md"
        # …and files OUTSIDE design/, because a statement can reach anywhere.
        printf '# reader readme\n'                           > "${_fo}/README.md"
        printf 'reader claude md\n'                          > "${_fo}/CLAUDE.md"
        printf 'reader source\n'                             > "${_fo}/src/app.js"
        # `find -type f` uses lstat, so replacing a file with a SYMLINK (even to
        # identical content), a directory, a FIFO or a device node drops its
        # before-line and fails the comparison — measured. An earlier comment
        # here claimed symlink swaps were invisible; that was wrong, and a false
        # "known limit" invites someone to close a non-problem or to distrust the
        # neighbouring claim that is real. `chmod 000` is also caught, because
        # `cksum` then fails and the line disappears. What IS invisible: a
        # readability-PRESERVING mode or ownership change (`chmod +x`, `chown`).
        # Not closed with a mode column: such a statement must appear in the
        # block, where ADOPT_DESIGN_STMTS catches it if it names `design/`.
        #
        # SOUNDNESS LIMIT of this comparison, stated beside the control it
        # affects: `cksum` emits `sum size path`, so a filename containing a
        # NEWLINE splits one entry across two lines and `comm -23` can mis-pair
        # them (measured: two files produced three lines). Nothing in the seeded
        # tree or the seed has such a name and creating one needs a deliberate
        # edit, so this is recorded rather than closed — but it is a limit of the
        # load-bearing control, not of a peripheral cell, and it matters if this
        # snapshot is ever pointed at a user-supplied tree.
        _before="${WORK}/snap-before-${_b}"
        ( cd "${_wrap}" && find . -type f -exec cksum {} + | LC_ALL=C sort ) > "${_before}" 2>/dev/null
        _snap_n="$(wc -l < "${_before}" | tr -d ' ')"
        case "${_snap_n}" in ''|*[!0-9]*) _snap_n=0 ;; esac
        if [ "${_snap_n}" -ge 11 ]; then
            _record_pass "block: snapshotted ${_snap_n} reader files before the run (${_b})"
        else
            _record_fail "block: snapshotted the reader's files before the run (${_b})" \
                "only ${_snap_n} — the comparison below would check almost nothing"
        fi
        ( cd "${_fo}" && env SEED_DIR="${_ADOPT_DIR}" "${_sh}" "${_fence}" ) >/dev/null 2>&1
        _after="${WORK}/snap-after-${_b}"
        ( cd "${_wrap}" && find . -type f -exec cksum {} + | LC_ALL=C sort ) > "${_after}" 2>/dev/null
        # Every line present BEFORE must still be present after, byte-identical.
        # Adoption is allowed to ADD files, so this is one-directional.
        _lost="$(LC_ALL=C comm -23 "${_before}" "${_after}" | sed 's/^[0-9]* *[0-9]* *//' | tr '\n' ' ')"
        if [ -z "${_lost}" ]; then
            _record_pass "block: every pre-existing reader file is byte-identical after (${_b})"
        else
            _record_fail "block: every pre-existing reader file is byte-identical after (${_b})" \
                "changed or deleted: ${_lost}"
        fi
        # CONTROL: the block must still have RUN, or the comparison above is
        # satisfied by a script that did nothing.
        if [ -r "${_fo}/design/checks/token-lint.sh" ]; then
            _record_pass "block: …and it still ran (a file the reader lacked landed) (${_b})"
        else
            _record_fail "block: …and it still ran (a file the reader lacked landed) (${_b})" \
                "checks/token-lint.sh absent — the comparison above proves nothing"
        fi
    done

    # A SET-but-wrong SEED_DIR must also fail loudly and copy nothing. Safe to
    # run for real: it names a path that does not exist, never the root.
    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _wd="${WORK}/wrongseed-${_b}"; mkdir -p "${_wd}"
        _wrc=0
        ( cd "${_wd}" && env SEED_DIR="${WORK}/no-such-seed-dir" "${_sh}" -c "${CP_LINE}" ) \
            >/dev/null 2>&1 || _wrc=$?
        if [ "${_wrc}" -ne 0 ]; then
            _record_pass "a wrong SEED_DIR fails non-zero (${_b})"
        else
            _record_fail "a wrong SEED_DIR fails non-zero (${_b})" "exited 0"
        fi
        if [ -e "${_wd}/design/tokens.css" ]; then
            _record_fail "a wrong SEED_DIR copies nothing (${_b})" "tokens.css appeared"
        else
            _record_pass "a wrong SEED_DIR copies nothing (${_b})"
        fi
    done

    for _sh in ${SHELLS}; do
        _b="$(basename "${_sh}")"
        _dest="${WORK}/adopt-${_b}"
        mkdir -p "${_dest}"
        ( cd "${_dest}" && env -u CLAUDE_PLUGIN_ROOT SEED_DIR="${_ADOPT_DIR}" \
            "${_sh}" -c "${CP_LINE}" ) >/dev/null 2>&1
        for _want in tokens.css styleguide.md checks/token-lint.sh; do
            if [ -r "${_dest}/design/${_want}" ]; then
                _record_pass "adoption landed design/${_want} (${_b})"
            else
                _record_fail "adoption landed design/${_want} (${_b})" \
                    "missing after: ${CP_LINE}"
            fi
        done
        # And the adopted tree is USABLE: the shipped lint runs and passes over
        # a stylesheet that references roles. A copy that lands unrunnable
        # files is not an adoption.
        # NOT wrapped in `if [ -r ]`: a guarded cell simply DISAPPEARS when the
        # copy did not happen, and the only tell is the `Tests run` count
        # dropping — review measured 67 -> 65 with the extraction broken. Record
        # a failure instead, so the absence is a FAIL line.
        if [ -r "${_dest}/design/checks/token-lint.sh" ]; then
            printf '.a { color: var(--text-primary); }\n' > "${_dest}/ok.css"
            _rc=0
            ( cd "${_dest}" && env -u CLAUDE_PLUGIN_ROOT "${_sh}" design/checks/token-lint.sh ok.css ) \
                >/dev/null 2>&1 || _rc=$?
            assert_equals "the adopted lint runs and passes a role-referencing css (${_b})" "0" "${_rc}"
        else
            _record_fail "the adopted lint runs and passes a role-referencing css (${_b})" \
                "design/checks/token-lint.sh was never copied — the cell cannot run"
        fi
    done
fi

# ---------------------------------------------------------------------------
# 4b. The other file the hint names must not repeat the defect one hop on.
# ---------------------------------------------------------------------------
# docs/design-seed-method.md pointed at `assets/design-seed/` — a repo-relative
# plugin path, unopenable in an adopting repo for exactly the same reason. A
# static doc cannot be substituted, so the reference is written relative to the
# DOC, which a reader holding its absolute path can resolve. Asserted by
# resolving it, not by matching the text.
echo ""
echo "--- the method doc's own references resolve from where it lives ---"
METHOD="${PROJECT_ROOT}/docs/design-seed-method.md"
assert_file_exists "the method doc exists" "${METHOD}"
_md_bad=""
_md_n=0
# Collected into a variable FIRST. A backtick inside an unquoted `<<EOF` body is
# live command substitution, and although the single quotes here happen to
# protect it (measured: bash does not execute it), the shape is exactly the
# heredoc-body ambiguity tests/test-hook-string-lint.sh exists to forbid — and
# that lint caught this file. Do not inline it back into the heredoc.
_md_refs="$(grep -oE '`\.\.?/[^`]*`' "${METHOD}" 2>/dev/null | tr -d '`')"
while IFS= read -r _ref; do
    [ -z "${_ref}" ] && continue
    _md_n=$((_md_n + 1))
    # Resolved against the doc's own directory, which is what "relative to this
    # file" means to whoever opened it.
    if [ -e "${METHOD%/*}/${_ref}" ]; then
        _record_pass "method-doc reference resolves from the doc: ${_ref}"
    else
        _md_bad="${_md_bad}${_md_bad:+, }${_ref}"
    fi
done <<EOF
${_md_refs}
EOF
if [ -n "${_md_bad}" ]; then
    _record_fail "every relative reference in the method doc resolves from the doc" \
        "unresolvable: ${_md_bad}"
fi
# A FLOOR, because the loop above records nothing when it does not iterate.
# `_md_n` was previously incremented and never read: review measured the seed
# reference replaced with plain prose giving 66/66 PASS and 0 FAIL, because the
# absence assertion below is ALSO satisfied when nothing relative remains. The
# two cells fail in opposite directions, so neither alone is a check.
if [ "${_md_n}" -ge 1 ]; then
    _record_pass "the method doc names >= 1 doc-relative reference (found ${_md_n})"
else
    _record_fail "the method doc names >= 1 doc-relative reference" \
        "found 0 — the resolution loop checked nothing, and the absence cell below cannot tell"
fi
# The path shape the defect took: a bare plugin directory, resolved against the
# READER's repo rather than the doc. A floor is unnecessary — this is an absence
# assertion whose needle is the historical bug.
_md_rel="$(grep -oE '`(assets|docs|hooks|scripts|skills|config|tests)/[^`]*`' "${METHOD}" 2>/dev/null | tr -d '`' | tr '\n' ' ')"
assert_equals "the method doc names no plugin path relative to the reader's repo" "" \
    "$(printf '%s' "${_md_rel}" | sed 's/[[:space:]]*$//')"
# BARE paths too. The config lint grew a bare-path leg because all three live
# `phase_compositions` violations are unbackticked; this leg did not get one, so
# the paired sites had drifted. Zero live matches today — a guard against the
# next occurrence, added at the right time rather than after it. `docs/plans/` is
# the USER's scratch dir and is excluded, as in the config lint.
_md_bare="$(sed 's/`[^`]*`//g' "${METHOD}" 2>/dev/null \
    | grep -oE '(^|[^A-Za-z0-9/_.-])(assets|hooks|scripts|skills|config|tests)/[A-Za-z0-9_./-]*' \
    | grep -oE '(assets|hooks|scripts|skills|config|tests)/[A-Za-z0-9_./-]*' \
    | LC_ALL=C sort -u | tr '\n' ' ')"
assert_equals "the method doc names no plugin path by bare relative path" "" \
    "$(printf '%s' "${_md_bare}" | sed 's/[[:space:]]*$//')"

# ---------------------------------------------------------------------------
# 5. A plugin root containing a space still yields openable paths.
# ---------------------------------------------------------------------------
# HOME can contain a space, so the plugin cache path can too. The hint emits
# paths bare inside backticks, which is why a space is survivable here — but
# only if nothing downstream re-splits them.
echo ""
echo "--- a plugin root containing a space ---"
SP_ROOT="${WORK}/od d/plug"
mkdir -p "${SP_ROOT}"
for _d in hooks config assets docs skills scripts; do
    cp -R "${PROJECT_ROOT}/${_d}" "${SP_ROOT}/${_d}" 2>/dev/null
done
HOME_SP="${WORK}/home-space"; mkdir -p "${HOME_SP}/.claude"
build_cache "${HOME_SP}" "${SP_ROOT}"
SP_LINE="$(render_hint "${HOME_SP}" "${SP_ROOT}")"
if [ -z "${SP_LINE}" ]; then
    _record_fail "the hint renders under a plugin root containing a space" "no DESIGN SEED line"
else
    _record_pass "the hint renders under a plugin root containing a space"
    assert_contains "the spaced root is substituted whole" "${SP_ROOT}/" "${SP_LINE}"
    _sp_n=0
    while IFS= read -r _p; do
        [ -z "${_p}" ] && continue
        _sp_n=$((_sp_n + 1))
        if ( cd "${EXT}" && env -u CLAUDE_PLUGIN_ROOT test -r "${_p}" ); then
            _record_pass "spaced-root hint path opens: ${_p##*/}"
        else
            _record_fail "spaced-root hint path opens: ${_p##*/}" "unreadable: ${_p}"
        fi
    done <<EOF
$(_backtick_paths "${SP_LINE}")
EOF
    if [ "${_sp_n}" -ge 2 ]; then
        _record_pass "spaced-root hint names >= 2 plugin files (found ${_sp_n})"
    else
        _record_fail "spaced-root hint names >= 2 plugin files" "found ${_sp_n}"
    fi
fi

# ---------------------------------------------------------------------------
# 6. LINT: no hint may name a plugin-internal path relatively.
# ---------------------------------------------------------------------------
# Because the defect was one hint and the next one will be another. Keyed on
# the plugin's own top-level directories, with a population floor so a config
# the grep stops matching cannot go green by checking nothing.
echo ""
echo "--- lint: every hint's plugin path is placeholder-rooted ---"
for _cfg in "${PROJECT_ROOT}/config/default-triggers.json" "${PROJECT_ROOT}/config/fallback-registry.json"; do
    _base="$(basename "${_cfg}")"
    _hints_n="$(jq '[.methodology_hints[]? | .hint] | length' "${_cfg}" 2>/dev/null)"
    case "${_hints_n}" in
        ''|*[!0-9]*) _hints_n=0 ;;
    esac
    if [ "${_hints_n}" -ge 5 ]; then
        _record_pass "${_base}: read ${_hints_n} hints to lint"
    else
        _record_fail "${_base}: read enough hints to lint" \
            "found ${_hints_n} — the lint below would pass having checked nothing"
    fi
    # A backticked span starting with one of the plugin's own top-level
    # directories is a plugin file named relatively. `design/` is the adopted
    # copy in the USER's repo and is deliberately NOT in this list.
    # jq's EXIT STATUS is captured. It aborts on the first row it cannot handle
    # and returns what it already streamed, so a malformed earlier entry (a hint
    # with no `hint` key => `null | splits`) empties `_bad` and the lint reads
    # clean with the violation present. Review measured exactly that: a keyless
    # entry at index 0 plus a real violation after it gave 67/67 PASS. Position
    # decides, which is the jq-abort class CLAUDE.md already documents — and the
    # `_hints_n >= 5` floor does not help, because `[.hint]` tolerates nulls.
    _jq_rc=0
    _bad="$(jq -r '
        .methodology_hints[]? | .name as $n | (.hint // "") |
        [ splits("`") ] as $parts |
        [ range(0; ($parts | length)) | select(. % 2 == 1) | $parts[.] ] |
        map(select(test("^(assets|docs|hooks|scripts|skills|config|tests)/"))) |
        select(length > 0) | "\($n): \(join(", "))"
    ' "${_cfg}" 2>/dev/null)" || _jq_rc=$?
    if [ "${_jq_rc}" -ne 0 ]; then
        _record_fail "${_base}: the relative-path lint ran to completion" \
            "jq exited ${_jq_rc} — it aborted mid-stream, so an empty result is NOT a clean result"
    else
        _record_pass "${_base}: the relative-path lint ran to completion"
    fi
    if [ -z "${_bad}" ]; then
        _record_pass "${_base}: no hint names a plugin file by relative path"
    else
        _record_fail "${_base}: no hint names a plugin file by relative path" \
            "unreachable in an adopting repo:
${_bad}"
    fi
    # BARE paths too — the backtick-only form was the exact recurrence the lint
    # was added to stop. Review measured a hint reading
    # `read docs/design-seed-method.md and run scripts/foo.sh` passing 67/67,
    # and the three live instances in the sibling field below are ALL unbackticked.
    # `docs/plans/` is excluded: that is the USER's scratch directory, not a
    # plugin file. Measured at authoring time: zero bare matches, so this is a
    # guard against the next one, not a retrofit.
    _jq_rc2=0
    _bare="$(jq -r '
        .methodology_hints[]? | .name as $n | (.hint // "") |
        [ splits("`") ] as $parts |
        [ range(0; ($parts | length)) | select(. % 2 == 0) | $parts[.] ] | join(" ") |
        [ match("(^|[^A-Za-z0-9/_.-])((assets|docs|hooks|scripts|skills|config|tests)/[A-Za-z0-9_.*/-]*)"; "g")
          | .captures[1].string ] |
        map(select(startswith("docs/plans/") | not)) |
        select(length > 0) | "\($n): \(join(", "))"
    ' "${_cfg}" 2>/dev/null)" || _jq_rc2=$?
    if [ "${_jq_rc2}" -ne 0 ]; then
        _record_fail "${_base}: the bare-path lint ran to completion" "jq exited ${_jq_rc2}"
    elif [ -z "${_bare}" ]; then
        _record_pass "${_base}: no hint names a plugin file by bare relative path"
    else
        _record_fail "${_base}: no hint names a plugin file by bare relative path" \
            "unreachable in an adopting repo:
${_bare}"
    fi
done

print_summary
