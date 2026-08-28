#!/bin/bash
# git-command.sh — predicate: does a shell command actually INVOKE a git write
# (push/commit), vs merely mention the phrase as an argument/string? Sourced by
# openspec-guard.sh. Bash 3.2 compatible. No side effects. Fail-open by design:
# a parse it cannot handle returns 1 (not a write) — callers that need
# fail-CLOSED behavior keep a substring fallback.

# Segment record separator: US (\x1f), per the repo's field-separator
# convention. MUST NOT be newline — see issue #155 below.
_GC_SEP=$'\037'

# Split a command into segments on UNQUOTED ; | & and NEWLINE boundaries
# (covers ; | && || and multi-line scripts). Quote-aware: operators inside
# '...' or "..." are literal, not boundaries. HEREDOC-aware (openspec:
# remedy-aware-backbone): a body fed to a known DATA SINK (cat/tee/git) is
# data and is discarded, never emitted as segments — pre-fix, a plan doc
# written via `cat > plan.md <<EOF` whose body contained `git push` was
# classified as a real push (~17-22%% of live denies). A body fed to a known
# SHELL INTERPRETER (bash/sh/…/eval) EXECUTES, so it is scanned as code; a
# body fed to anything else (python/ssh/docker/unknown) cannot be proven
# data and fails CLOSED via _GC_UNBALANCED. Arithmetic contexts `((…))` are
# depth-tracked so `$((1<<2))` is never misread as a heredoc operator.
# Emits segments separated by ${_GC_SEP}. Backslash escapes and `#` comments
# are still NOT interpreted. A false negative here is a gate BYPASS, i.e. the
# UNSAFE direction. Callers must not rely on the precise predicates when
# `command_parse_balanced` reports an unbalanced parse; see `_gc_precise` in
# openspec-guard.sh.
#
# ISSUE #155 — two coupled requirements, BOTH needed:
#  (1) Newline is a boundary HERE, in the quote-aware scanner, so a newline
#      inside quotes is consumed literally while an unquoted one still splits
#      a genuine multi-line compound.
#  (2) The emitted record separator is US, NOT newline. A quoted segment
#      legitimately CONTAINS newlines, so a newline-delimited output format is
#      re-split by the callers' IFS loop no matter how careful this scanner is.
# Pre-fix, a payload like
#   node x.mjs task "review this<NL>git push origin main<NL>and tell me why"
# yielded a bare `git push origin main` segment and was classified as a real
# push. PAIRED: every caller iterating this output must use IFS="${_GC_SEP}".
#
# COST MODEL: the char-scan is O(len^2) in bash 3.2 (substring indexing walks
# the string), so CODE characters are budgeted at 4096 — beyond that the parse
# is declared unbalanced and callers use their fail-closed substring path
# (byte-for-byte the pre-change behavior for >4KB commands). Heredoc BODIES
# and fully-quoted continuation lines are consumed line-wise (O(n) total) and
# do NOT spend budget — that is what makes a 35KB doc-write parseable at all.
_gc_split_segments() {
    local _s="$1" _seg="" _sq=0 _dq=0 _out="" _line _c _i _n _j
    local _pending="" _body=0 _arith=0 _budget=4096 _pend_sep=0
    local _tab _delim _tstrip _q _q2 _w _bad
    _tab=$'\t'
    # An empty separator would make IFS="" disable splitting in every caller —
    # the whole command becomes one segment and a real `git add -A && git push`
    # goes undetected. Re-assert it here so the fail direction stays CLOSED.
    [ -n "${_GC_SEP:-}" ] || _GC_SEP=$'\037'
    _GC_UNBALANCED=0
    while IFS= read -r _line || [ -n "${_line}" ]; do
        _line="${_line%$'\r'}"   # CRLF paste: \r glued to a terminator would
                                 # never compare equal and cost precision
        # ---- heredoc body mode: whole-line compare, no char scan, no budget.
        # Pending entry encoding: "<tstrip>:<q>:<delim>", tstrip in {P,T},
        # q in {Q,U} (Quoted vs Unquoted delimiter). An UNQUOTED delimiter
        # does NOT suppress expansion, so real bash runs `$(...)`/backticks in
        # the body BEFORE the sink sees it — discarding such a body as inert
        # would miss a live push (Finding 1). Fail CLOSED when an unquoted
        # body carries a command-substitution trigger.
        if [ "${_body}" -eq 1 ]; then
            _delim="${_pending%% *}"
            _tstrip="${_delim%%:*}"; _delim="${_delim#*:}"
            _q="${_delim%%:*}"; _delim="${_delim#*:}"
            _c="${_line}"
            if [ "${_tstrip}" = "T" ]; then
                while [ "${_c#"${_tab}"}" != "${_c}" ]; do _c="${_c#"${_tab}"}"; done
            fi
            if [ "${_c}" = "${_delim}" ]; then
                case "${_pending}" in
                    *" "*) _pending="${_pending#* }" ;;
                    *) _pending=""; _body=0 ;;
                esac
                continue
            fi
            if [ "${_q}" = "U" ]; then
                case "${_line}" in
                    *'$('*|*'`'*)
                        # live command substitution in an expanded body — the
                        # discarded "data" actually executes. Untrustworthy.
                        _GC_UNBALANCED=1; printf '%s' "${_out}${_seg}"; return 0 ;;
                esac
            fi
            continue
        fi
        # ---- normal mode: flush the segment boundary owed by the previous
        # line's newline (deferred so the output never gains a trailing SEP).
        if [ "${_pend_sep}" -eq 1 ]; then
            _out="${_out}${_seg}${_GC_SEP}"; _seg=""; _pend_sep=0
        fi
        # Quote fast-path: a continuation line with no closing-quote character
        # is consumed whole — bounds the #155 large-quoted-payload cost.
        if [ "${_sq}" -eq 1 ]; then
            case "${_line}" in
                *"'"*) : ;;
                *) _seg="${_seg}${_line}"$'\n'; continue ;;
            esac
        elif [ "${_dq}" -eq 1 ]; then
            case "${_line}" in
                *'"'*) : ;;
                *) _seg="${_seg}${_line}"$'\n'; continue ;;
            esac
        fi
        _n=${#_line}; _i=0
        while [ "${_i}" -lt "${_n}" ]; do
            _budget=$((_budget - 1))
            if [ "${_budget}" -le 0 ]; then
                _GC_UNBALANCED=1; printf '%s' "${_out}${_seg}"; return 0
            fi
            _c="${_line:${_i}:1}"
            if [ "${_sq}" -eq 1 ]; then
                [ "${_c}" = "'" ] && _sq=0
                _seg="${_seg}${_c}"; _i=$((_i+1)); continue
            fi
            if [ "${_dq}" -eq 1 ]; then
                [ "${_c}" = '"' ] && _dq=0
                _seg="${_seg}${_c}"; _i=$((_i+1)); continue
            fi
            case "${_c}" in
                "'") _sq=1; _seg="${_seg}${_c}" ;;
                '"') _dq=1; _seg="${_seg}${_c}" ;;
                '(')
                    # `((`/`$((` opens an arithmetic context; `<<` inside one
                    # is a shift, not a heredoc (`$((1<<2))` bypass — design
                    # review requirement).
                    if [ "${_line:$((_i+1)):1}" = "(" ]; then
                        _arith=$((_arith+1)); _seg="${_seg}(("; _i=$((_i+1))
                    else
                        _seg="${_seg}${_c}"
                    fi ;;
                ')')
                    if [ "${_arith}" -gt 0 ] && [ "${_line:$((_i+1)):1}" = ")" ]; then
                        _arith=$((_arith-1)); _seg="${_seg}))"; _i=$((_i+1))
                    else
                        _seg="${_seg}${_c}"
                    fi ;;
                '<')
                    if [ "${_arith}" -gt 0 ] || [ "${_line:$((_i+1)):1}" != "<" ]; then
                        _seg="${_seg}${_c}"
                    elif [ "${_line:$((_i+2)):1}" = "<" ]; then
                        # herestring `<<<`: same-line operand, plain text —
                        # consume all three so `<<` is not re-matched at i+1.
                        _seg="${_seg}<<<"; _i=$((_i+2))
                    else
                        # heredoc operator: <<[-][blanks]['"]delim['"]
                        _j=$((_i+2)); _tstrip="P"
                        if [ "${_line:${_j}:1}" = "-" ]; then _tstrip="T"; _j=$((_j+1)); fi
                        while :; do
                            _c="${_line:${_j}:1}"
                            case "${_c}" in
                                ' '|"${_tab}") _j=$((_j+1)) ;;
                                *) break ;;
                            esac
                        done
                        _q=""
                        case "${_line:${_j}:1}" in
                            "'"|'"') _q="${_line:${_j}:1}"; _j=$((_j+1)) ;;
                        esac
                        _delim=""
                        while :; do
                            _c="${_line:${_j}:1}"
                            case "${_c}" in
                                [A-Za-z0-9_]) _delim="${_delim}${_c}"; _j=$((_j+1)) ;;
                                *) break ;;
                            esac
                        done
                        _bad=0
                        [ -n "${_delim}" ] || _bad=1
                        if [ -n "${_q}" ]; then
                            if [ "${_line:${_j}:1}" = "${_q}" ]; then _j=$((_j+1)); else _bad=1; fi
                        fi
                        if [ "${_bad}" -eq 1 ]; then
                            # empty / non-[A-Za-z0-9_] / mixed-quote delimiter:
                            # cannot locate the terminator — fail CLOSED.
                            _GC_UNBALANCED=1; printf '%s' "${_out}${_seg}"; return 0
                        fi
                        _w="$(_gc_segment_cmd_word "${_seg}")"
                        case "${_w}" in
                            cat|*/cat|tee|*/tee|git|*/git)
                                # data sink: the body is data — discard it
                                # (but see the unquoted-body substitution guard
                                # in body mode: an unquoted delimiter whose body
                                # runs `$(...)` fails closed). `git` is here so
                                # `git commit -F - <<EOF …` keeps its commit
                                # (and mutate-then-push) classification.
                                _q2="Q"; [ -z "${_q}" ] && _q2="U"
                                if [ -n "${_pending}" ]; then
                                    _pending="${_pending} ${_tstrip}:${_q2}:${_delim}"
                                else
                                    _pending="${_tstrip}:${_q2}:${_delim}"
                                fi
                                _seg="${_seg}${_line:${_i}:$((_j-_i))}"
                                _i=$((_j-1)) ;;
                            bash|*/bash|sh|*/sh|zsh|*/zsh|dash|*/dash|ksh|*/ksh|eval|source|.)
                                # shell interpreter: the body EXECUTES — do
                                # NOT register a heredoc; body lines scan as
                                # code, so `bash <<EOF … git push … EOF`
                                # yields a real push segment (precisely).
                                _seg="${_seg}${_line:${_i}:$((_j-_i))}"
                                _i=$((_j-1)) ;;
                            *)
                                # unknown owner (python/ssh/docker/empty/...):
                                # the body may execute remotely or via an
                                # interpreter we cannot enumerate — fail
                                # CLOSED to the substring path.
                                _GC_UNBALANCED=1; printf '%s' "${_out}${_seg}"; return 0 ;;
                        esac
                    fi ;;
                ';'|'|'|'&') _out="${_out}${_seg}${_GC_SEP}"; _seg="" ;;
                *) _seg="${_seg}${_c}" ;;
            esac
            _i=$((_i+1))
        done
        # ---- end of line
        if [ "${_sq}" -eq 1 ] || [ "${_dq}" -eq 1 ]; then
            # inside quotes: the newline is literal (#155 requirement (1)).
            _seg="${_seg}"$'\n'
        else
            _pend_sep=1
            [ -n "${_pending}" ] && _body=1
        fi
    done <<< "${_s}"
    # Publish whether the scan ended in a trustworthy state: inside a quote
    # (#155), or with an unterminated heredoc body (this change), the
    # segmentation cannot be trusted and precise detection would UNDER-detect —
    # a gate bypass. Callers must fail CLOSED on unbalanced.
    if [ "${_sq}" -eq 1 ] || [ "${_dq}" -eq 1 ] || [ -n "${_pending}" ] || [ "${_body}" -eq 1 ]; then
        _GC_UNBALANCED=1
    fi
    printf '%s' "${_out}${_seg}"
}

# _gc_segment_cmd_word <segment-text>
#   Echoes the segment's effective command word: unwraps leading `(`/`{` group
#   openers and skips env/assignment/wrapper prefixes. Used ONLY to classify
#   the OWNER of a heredoc operator (data sink vs shell interpreter vs
#   unknown) — it deliberately returns the word verbatim (path prefixes are
#   matched by the caller's case patterns). PAIRED: shares the group-opener
#   unwrap shape with _gc_segment_git_sub — a fix to one likely applies to
#   the other.
_gc_segment_cmd_word() {
    local _gcw
    # shellcheck disable=SC2086
    set -- $1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*)
                _gcw="$1"
                while :; do
                    case "${_gcw}" in
                        '('*) _gcw="${_gcw#\(}" ;;
                        '{'*) _gcw="${_gcw#\{}" ;;
                        *) break ;;
                    esac
                done
                shift
                set -- "${_gcw}" "$@"
                break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in
            env|sudo|nohup|command|exec|time) shift ;;
            [A-Za-z_]*=*) shift ;;
            *) break ;;
        esac
    done
    [ "$#" -gt 0 ] || return 0
    printf '%s' "$1"
}

# command_parse_balanced <command>
#   0 when the quote-aware scan of <command> ended with all quotes closed, i.e.
#   the segmentation is trustworthy. 1 otherwise — callers should then use their
#   fail-CLOSED substring path instead of the precise predicates.
command_parse_balanced() {
    _gc_split_segments "$1" >/dev/null
    [ "${_GC_UNBALANCED:-1}" -eq 0 ]
}

# _gc_segment_git_sub <segment>
#   Echoes the git subcommand when the segment's first real token (after
#   `env`/VAR=val prefixes) is git or */git; echoes nothing otherwise.
#   Extracted from command_invokes_git_write — semantics unchanged.
_gc_segment_git_sub() {
    local _gc_t
    # shellcheck disable=SC2086
    set -- $1
    # Unwrap leading subshell/brace group openers so `(git push)` or
    # `{ git push` cannot hide the invocation from the gate.
    # PAIRED: command_invokes_gh_merge carries a structural copy of this
    # unwrap (it collects two words instead of echoing one) — update both.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*)
                _gc_t="$1"
                while :; do
                    case "${_gc_t}" in
                        '('*) _gc_t="${_gc_t#\(}" ;;
                        '{'*) _gc_t="${_gc_t#\{}" ;;
                        *) break ;;
                    esac
                done
                shift
                set -- "${_gc_t}" "$@"
                break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in
            env) shift ;;
            [A-Za-z_]*=*) shift ;;
            *) break ;;
        esac
    done
    [ "$#" -gt 0 ] || return 0
    case "$1" in
        git|*/git) shift ;;
        *) return 0 ;;
    esac
    # Skip git global flags to reach the subcommand.
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -C|-c|--git-dir|--work-tree|--namespace)
                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *)
                # Strip trailing group closers: in `(git push)` the closer
                # glues onto the final token, yielding `push)` — no git
                # subcommand contains ) or }, so stripping is always safe.
                _gc_t="$1"
                while :; do
                    case "${_gc_t}" in
                        *')') _gc_t="${_gc_t%\)}" ;;
                        *'}') _gc_t="${_gc_t%\}}" ;;
                        *) break ;;
                    esac
                done
                printf '%s' "${_gc_t}"
                return 0 ;;
        esac
    done
    return 0
}

# command_invokes_git_write <command> [subcommands]
#   subcommands: space-separated, default "push commit".
#   Returns 0 if any ; | && || -separated segment's first real token is git
#   (or */git) whose first non-flag argument is one of <subcommands>.
command_invokes_git_write() {
    local _gc_cmd _gc_want _gc_segs _gc_oldifs _gc_seg _gc_sub _gc_w
    _gc_cmd="$1"
    _gc_want="${2:-push commit}"
    _gc_segs="$(_gc_split_segments "${_gc_cmd}")"
    _gc_oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        _gc_sub="$(_gc_segment_git_sub "${_gc_seg}")"
        if [ -n "${_gc_sub}" ]; then
            for _gc_w in ${_gc_want}; do
                if [ "${_gc_sub}" = "${_gc_w}" ]; then
                    IFS="${_gc_oldifs}"
                    return 0
                fi
            done
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_gc_oldifs}"
    return 1
}

# command_invokes_gh_merge <command>
#   Returns 0 if any segment actually invokes a PR merge via gh:
#     - `gh [flags] pr [flags] merge ...` (any flag order, incl. -R/--repo)
#     - `gh api ...` naming the REST pull-merge path (pulls/…/merge) or the
#       GraphQL mergePullRequest mutation.
#   Phrase mentions inside quotes of NON-gh segments never match (segment's
#   first real token must be gh). `gh pr create` never matches.
command_invokes_gh_merge() {
    local _gc_segs _gc_oldifs _gc_seg _gc_w1 _gc_w2 _gc_t
    _gc_segs="$(_gc_split_segments "$1")"
    _gc_oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_gc_seg}
        # Unwrap leading group openers (see _gc_segment_git_sub).
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;;
                '('*|'{'*)
                    _gc_t="$1"
                    while :; do
                        case "${_gc_t}" in
                            '('*) _gc_t="${_gc_t#\(}" ;;
                            '{'*) _gc_t="${_gc_t#\{}" ;;
                            *) break ;;
                        esac
                    done
                    shift
                    set -- "${_gc_t}" "$@"
                    break ;;
                *) break ;;
            esac
        done
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -gt 0 ]; then
            case "$1" in
                gh|*/gh)
                    shift
                    # Collect the first two non-flag words, skipping
                    # value-taking global flags in any position.
                    _gc_w1=""; _gc_w2=""
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            -R|--repo|--hostname)
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            -*) shift ;;
                            *)
                                # Strip trailing group closers (`(gh pr merge)`
                                # glues `)` onto the last collected word).
                                _gc_t="$1"
                                while :; do
                                    case "${_gc_t}" in
                                        *')') _gc_t="${_gc_t%\)}" ;;
                                        *'}') _gc_t="${_gc_t%\}}" ;;
                                        *) break ;;
                                    esac
                                done
                                if [ -z "${_gc_w1}" ]; then _gc_w1="${_gc_t}"
                                elif [ -z "${_gc_w2}" ]; then _gc_w2="${_gc_t}"; break
                                fi
                                shift ;;
                        esac
                    done
                    if [ "${_gc_w1}" = "pr" ] && [ "${_gc_w2}" = "merge" ]; then
                        IFS="${_gc_oldifs}"; return 0
                    fi
                    if [ "${_gc_w1}" = "api" ]; then
                        # REST pull-merge is a WRITE only as PUT — a bare
                        # `gh api …/pulls/N/merge` is the merge-STATUS read
                        # (review round 2: over-gating a read breeds evasion).
                        case "${_gc_seg}" in
                            *pulls/*/merge*)
                                case "${_gc_seg}" in
                                    *PUT*) IFS="${_gc_oldifs}"; return 0 ;;
                                esac ;;
                        esac
                        case "${_gc_seg}" in
                            *mergePullRequest*)
                                IFS="${_gc_oldifs}"; return 0 ;;
                        esac
                    fi
                    ;;
            esac
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_gc_oldifs}"
    return 1
}

# command_git_mutate_before_push <command>
#   Returns 0 when a content-mutating git subcommand (commit merge cherry-pick
#   rebase revert am) is invoked in a segment ORDERED BEFORE a `git push`
#   segment of the same command. The push gate evaluates PRE-EXEC state, so no
#   evidence can cover a commit created inline — such compounds must be split.
#   `pull` and `reset` are deliberately excluded (false-block discipline; see
#   openspec/changes archive gate-gh-merge-and-compound-push design).
command_git_mutate_before_push() {
    local _gc_segs _gc_oldifs _gc_seg _gc_sub _gc_seen
    _gc_segs="$(_gc_split_segments "$1")"
    _gc_seen=0
    _gc_oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        _gc_sub="$(_gc_segment_git_sub "${_gc_seg}")"
        case "${_gc_sub}" in
            commit|merge|cherry-pick|rebase|revert|am) _gc_seen=1 ;;
            push)
                if [ "${_gc_seen}" -eq 1 ]; then
                    IFS="${_gc_oldifs}"; return 0
                fi ;;
        esac
        IFS="${_GC_SEP}"
    done
    IFS="${_gc_oldifs}"
    return 1
}

# --- gh publication predicates (issue #174) ---------------------------------
# A publication is any gh subcommand that writes prose to the tracker:
#   gh issue create|comment|edit, gh pr create|comment|edit.
# `gh pr merge` is deliberately excluded — it publishes no body, and it is
# already covered by the push gate's outbound legs.
#
# PAIRED: both functions iterate _gc_split_segments output with
# IFS="${_GC_SEP}". Newline-splitting is wrong here — a quoted --body
# legitimately contains newlines (issue #155).
_gc_publish_verb() {
    # $1=noun $2=verb -> 0 when this pair publishes a body
    case "$1" in
        issue|pr) ;;
        *) return 1 ;;
    esac
    case "$2" in
        create|comment|edit) return 0 ;;
        *) return 1 ;;
    esac
}

# _gc_api_publish_endpoint <rest-path>
#   0 when <rest-path> (the first non-flag arg after `gh api`) is an
#   issue/PR-body write surface: issue creation/edit, issue or PR comments,
#   PR creation. `pulls/*/merge` is excluded FIRST (case tests top-down) —
#   it publishes no body and is already command_invokes_gh_merge's territory;
#   without the exclusion the broader `*/pulls/*` pattern below would also
#   match it.
_gc_api_publish_endpoint() {
    case "$1" in
        */pulls/*/merge) return 1 ;;
        */issues|*/issues/*|*/pulls|*/pulls/*) return 0 ;;
        *) return 1 ;;
    esac
}

# _gc_api_is_write <method> <has-fields 0|1>
#   0 when the `gh api` call actually sends a body: an explicit
#   --method/-X of POST or PATCH, OR no explicit method but at least one
#   -f/-F/--field/--raw-field/--input (gh's own default-to-POST-when-fields
#   rule). A bare read (`gh api repos/o/r/issues`, no method, no fields)
#   sends nothing and is deliberately NOT a write — same
#   over-gating-breeds-evasion discipline as command_invokes_gh_merge's
#   bare-merge-status-read exclusion.
_gc_api_is_write() {
    local _m
    _m="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
    case "${_m}" in
        POST|PATCH) return 0 ;;
    esac
    [ -z "$1" ] && [ "$2" = "1" ] && return 0
    return 1
}

command_invokes_gh_publish() {
    local _segs _oldifs _seg _w1 _w2 _t _api_method _api_has_fields
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_seg}
        # Unwrap leading group openers (see _gc_segment_git_sub).
        # PAIRED: command_invokes_gh_merge carries a structural copy of this
        # unwrap — update both.
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;;
                '('*|'{'*)
                    _t="$1"
                    while :; do
                        case "${_t}" in
                            '('*) _t="${_t#\(}" ;;
                            '{'*) _t="${_t#\{}" ;;
                            *) break ;;
                        esac
                    done
                    shift
                    set -- "${_t}" "$@"
                    break ;;
                *) break ;;
            esac
        done
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -gt 0 ]; then
            case "$1" in
                gh|*/gh)
                    shift
                    # Collect the first two non-flag words, skipping
                    # value-taking global flags in any position. `gh api`'s
                    # --method/-X and field flags (-f/-F/--field/--raw-field/
                    # --input) are recognized here too — as plain "-*"
                    # catch-alls they would each swallow only ONE token,
                    # leaving the flag's value to be mis-collected as _w2
                    # in place of the real REST endpoint when they precede it
                    # (e.g. `gh api --method POST repos/o/r/issues/1/comments`).
                    # PAIRED: publish-w1w2-collector — gh_publish_body_files
                    # carries the same skip list under this anchor
                    # (`grep -n publish-w1w2-collector`).
                    _w1=""; _w2=""; _api_method=""; _api_has_fields=0
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            -R|--repo|--hostname)
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            --method|-X)
                                _api_method="${2:-}"
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            --method=*)
                                _api_method="${1#--method=}"; shift ;;
                            -f|-F|--field|--raw-field|--input)
                                _api_has_fields=1
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            -*) shift ;;
                            *)
                                # Strip trailing group closers.
                                _t="$1"
                                while :; do
                                    case "${_t}" in
                                        *')') _t="${_t%\)}" ;;
                                        *'}') _t="${_t%\}}" ;;
                                        *) break ;;
                                    esac
                                done
                                if [ -z "${_w1}" ]; then _w1="${_t}"
                                elif [ -z "${_w2}" ]; then _w2="${_t}"; break
                                fi
                                shift ;;
                        esac
                    done
                    if _gc_publish_verb "${_w1}" "${_w2}"; then
                        IFS="${_oldifs}"; return 0
                    fi
                    if [ "${_w1}" = "api" ] && [ -n "${_w2}" ]; then
                        # The collection loop above breaks the instant _w2 is
                        # set, WITHOUT shifting it off — so $1 here is still
                        # the endpoint itself. Drop it, then scan whatever
                        # follows for --method/-X/field flags that came AFTER
                        # the endpoint (the common
                        # `gh api <path> -f body=...` shape).
                        shift
                        while [ "$#" -gt 0 ]; do
                            case "$1" in
                                --method|-X)
                                    _api_method="${2:-}"
                                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                                --method=*)
                                    _api_method="${1#--method=}"; shift ;;
                                -f|-F|--field|--raw-field|--input)
                                    _api_has_fields=1
                                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                                *) shift ;;
                            esac
                        done
                        if _gc_api_publish_endpoint "${_w2}" \
                            && _gc_api_is_write "${_api_method}" "${_api_has_fields}"; then
                            IFS="${_oldifs}"; return 0
                        fi
                    fi ;;
            esac
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    return 1
}

gh_publish_body_files() {
    # Prints one --body-file/-F path per line (surrounding quotes stripped).
    # Inline --body text is deliberately NOT parsed here: `set -- ${_seg}`
    # word-splits, so `--body "two words"` arrives as `"two` / `words"` and any
    # reconstruction under-detects — a bypass. The hook instead scans the WHOLE
    # command string, which covers inline bodies conservatively.
    local _segs _oldifs _seg _out _p _w1 _w2 _t _opener_count _i
    _out=""
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_seg}
        # Unwrap leading group openers (see _gc_segment_git_sub).
        # Count how many openers we consume — this bounds the later closer strip.
        _opener_count=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') _opener_count=$((_opener_count+1)); shift ;;
                '('*|'{'*)
                    _t="$1"
                    while :; do
                        case "${_t}" in
                            '('*) _opener_count=$((_opener_count+1)); _t="${_t#\(}" ;;
                            '{'*) _opener_count=$((_opener_count+1)); _t="${_t#\{}" ;;
                            *) break ;;
                        esac
                    done
                    shift
                    set -- "${_t}" "$@"
                    break ;;
                *) break ;;
            esac
        done
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        case "${1:-}" in gh|*/gh) ;; *) IFS="${_GC_SEP}"; continue ;; esac
        shift
        # Collect the first two non-flag words, skipping value-taking global flags.
        _w1=""; _w2=""
        while [ "$#" -gt 0 ]; do
            case "$1" in
                -R|--repo|--hostname)
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                # PAIRED: publish-w1w2-collector — keep this skip list in sync
                # with the identically-anchored collector in
                # command_invokes_gh_publish (`grep -n publish-w1w2-collector`).
                # Without it, a value-taking `gh api` flag appearing BEFORE the
                # endpoint (e.g. `gh api -X POST repos/o/r/issues --input f`)
                # is swallowed as a plain "-*" and its VALUE ("POST") is
                # mis-collected as _w2 in place of the real endpoint, so the
                # api branch below never finds the endpoint and never
                # resolves the payload path (issue #174 round).
                --method|-X|-f|-F|--field|--raw-field|--input)
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                --method=*) shift ;;
                -*) shift ;;
                *)
                    # Strip trailing group closers.
                    _t="$1"
                    while :; do
                        case "${_t}" in
                            *')') _t="${_t%\)}" ;;
                            *'}') _t="${_t%\}}" ;;
                            *) break ;;
                        esac
                    done
                    if [ -z "${_w1}" ]; then _w1="${_t}"
                    elif [ -z "${_w2}" ]; then _w2="${_t}"; break
                    fi
                    shift ;;
            esac
        done
        if ! _gc_publish_verb "${_w1}" "${_w2}"; then
            # gh api: `--input <path>` and `-f|-F|--field|--raw-field name=@<path>`
            # carry the body in a FILE gh reads directly, same as --body-file
            # for issue/pr (issue #174 round: this branch used to `continue`
            # for every `api` verb, so those paths were never scanned or
            # announced). command_invokes_gh_publish already gated this
            # segment as a write to an issue/pr endpoint before this function
            # runs, so this only widens WHICH file gets scanned, not WHETHER.
            if [ "${_w1}" = "api" ] && _gc_api_publish_endpoint "${_w2}"; then
                shift  # endpoint token is still unshifted here (see command_invokes_gh_publish)
                while [ "$#" -gt 0 ]; do
                    _p=""
                    case "$1" in
                        --method|-X)
                            if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                        --method=*) shift ;;
                        --input)
                            _p="${2:-}"
                            if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                        --input=*) _p="${1#--input=}"; shift ;;
                        -f|-F|--field|--raw-field)
                            case "${2:-}" in *=@*) _p="${2#*=@}" ;; esac
                            if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                        *) shift ;;
                    esac
                    if [ -n "${_p}" ]; then
                        _i=0
                        while [ "${_i}" -lt "${_opener_count}" ]; do
                            case "${_p}" in
                                *')') _p="${_p%\)}"; _i=$((_i+1)) ;;
                                *'}') _p="${_p%\}}"; _i=$((_i+1)) ;;
                                *) break ;;
                            esac
                        done
                        _p="${_p%\"}"; _p="${_p#\"}"; _p="${_p%\'}"; _p="${_p#\'}"
                        _out="${_out}${_p}
"
                    fi
                done
            fi
            IFS="${_GC_SEP}"; continue
        fi
        while [ "$#" -gt 0 ]; do
            _p=""
            case "$1" in
                --body-file|-F)
                    _p="${2:-}"
                    if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                --body-file=*)  _p="${1#--body-file=}"; shift ;;
                *) shift ;;
            esac
            if [ -n "${_p}" ]; then
                # Strip trailing group closers (from paren-wrapped commands).
                # Strip AT MOST _opener_count closers, to avoid corrupting
                # legitimate paths like /tmp/report(v2) or /tmp/set{a}.
                _i=0
                while [ "${_i}" -lt "${_opener_count}" ]; do
                    case "${_p}" in
                        *')')
                            _p="${_p%\)}"
                            _i=$((_i+1)) ;;
                        *'}')
                            _p="${_p%\}}"
                            _i=$((_i+1)) ;;
                        *) break ;;
                    esac
                done
                # Strip surrounding quotes.
                _p="${_p%\"}"; _p="${_p#\"}"; _p="${_p%\'}"; _p="${_p#\'}"
                _out="${_out}${_p}
"
            fi
        done
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    [ -n "${_out}" ] && printf '%s' "${_out}"
    return 0
}
