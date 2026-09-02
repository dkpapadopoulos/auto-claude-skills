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
    local _tab _delim _tstrip _q _q2 _w _bad _hd_reg
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
                        # "data" actually executes. Mark UNTRUSTED (push
                        # detection falls back to substring, which sees the
                        # embedded push in the raw command) but keep consuming
                        # the body so trailing code stays reliably segmented.
                        _GC_UNBALANCED=1 ;;
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
                        _hd_reg=0
                        case "${_w}" in
                            cat|*/cat|tee|*/tee|git|*/git)
                                # data sink: the body is data — consume it (but
                                # see the unquoted-body substitution guard in
                                # body mode). `git` is here so `git commit -F -
                                # <<EOF …` keeps its commit classification on
                                # the code part.
                                _hd_reg=1 ;;
                            bash|*/bash|sh|*/sh|zsh|*/zsh|dash|*/dash|ksh|*/ksh|eval|source|.)
                                # shell interpreter: the body EXECUTES — do NOT
                                # register a heredoc; body lines scan as code,
                                # so `bash <<EOF … git push … EOF` yields a real
                                # push segment (precisely).
                                _hd_reg=0 ;;
                            *)
                                # unknown owner (python/ssh/docker/empty/...):
                                # the body may execute in ways we cannot model,
                                # so mark the parse UNTRUSTED (push detection
                                # falls back to the substring path). But still
                                # CONSUME the body to its known delimiter rather
                                # than truncating — truncating dropped a real
                                # trailing `commit && push` from the segment
                                # stream (Finding 2), and the trailing top-level
                                # code must stay reliably segmented for the
                                # precise mutate-then-push predicate.
                                _hd_reg=1; _GC_UNBALANCED=1 ;;
                        esac
                        if [ "${_hd_reg}" -eq 1 ]; then
                            _q2="Q"; [ -z "${_q}" ] && _q2="U"
                            if [ -n "${_pending}" ]; then
                                _pending="${_pending} ${_tstrip}:${_q2}:${_delim}"
                            else
                                _pending="${_tstrip}:${_q2}:${_delim}"
                            fi
                        fi
                        _seg="${_seg}${_line:${_i}:$((_j-_i))}"
                        _i=$((_j-1))
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

# ---------------------------------------------------------------------------
# Subject resolution (#219)
#
# The gate that consumes these runs with the hook PROCESS's cwd, which the
# harness sets to the SESSION cwd — not to the tree the gated command acts on.
# These two helpers report what the COMMAND ITSELF says about its subject.
#
# SECURITY (same posture as pr_ref_from_command): the command text is
# model-authored, so NOTHING here is trusted. Both functions only *report* the
# claim; the caller MUST validate it — a directory against `git rev-parse
# --git-common-dir` of its own repository, a ref against `refs/heads/<name>`
# inside that repository — before any `git -C` or `git rev-parse` consumes it.
# Neither ever emits a leading `-`, so a discarded-but-interpolated value
# cannot become a flag.
#
# CEILING: `--git-dir=`, and any path or ref arriving through a variable,
# command substitution, or `bash -c` indirection, are NOT resolved — the same
# string-detection ceiling the rest of this lib documents. Unresolved means the
# caller keeps its process-cwd subject, i.e. today's behaviour.

# _gc_strip_openers <word> — drop leading group openers, as `(git push` and
# `{ git push` glue `(`/`{` onto the first token.
_gc_strip_openers() {
    local _w="$1"
    while :; do
        case "${_w}" in
            '('*) _w="${_w#\(}" ;;
            '{'*) _w="${_w#\{}" ;;
            *) break ;;
        esac
    done
    printf '%s' "${_w}"
}

# _gc_strip_closers <word> — drop trailing group closers, as `(git push)`
# glues `)` onto the last token. No path or ref legitimately ends in ) or }.
_gc_strip_closers() {
    local _w="$1"
    while :; do
        case "${_w}" in
            *')') _w="${_w%\)}" ;;
            *'}') _w="${_w%\}}" ;;
            *) break ;;
        esac
    done
    printf '%s' "${_w}"
}


# _gc_strip_closers_var <word> — like _gc_strip_closers, but sets `_GC_W`
#   instead of echoing. Same result, no subshell: the echoing form costs a FORK
#   per word, and these loops run per-argument inside a synchronous PreToolUse
#   gate. A closer-only word normalises to the empty string, so callers get the
#   closer-only test for free by matching `''` — which is why the separate
#   predicate that used to do it no longer exists.
_gc_strip_closers_var() {
    _GC_W="$1"
    while :; do
        case "${_GC_W}" in
            *')') _GC_W="${_GC_W%\)}" ;;
            *'}') _GC_W="${_GC_W%\}}" ;;
            *) break ;;
        esac
    done
}

# _gc_segment_dir_flag <segment> — the worktree directory a git invocation
# names via `-C <path>` or `--work-tree[=]<path>`, scanning only the global
# flags before the subcommand. Echoes nothing when there is none, and
# deliberately echoes nothing when there is MORE THAN ONE: git applies repeated
# -C cumulatively and relative to each other, so a single "the" directory does
# not exist and guessing one would point the gate at a tree the command never
# touches.
_gc_segment_dir_flag() {
    local _d="" _n=0 _u
    # shellcheck disable=SC2086
    set -- $1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*) _u="$(_gc_strip_openers "$1")"; shift; set -- "${_u}" "$@"; break ;;
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
    case "$1" in git|*/git) shift ;; *) return 0 ;; esac
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -C|--work-tree)
                if [ "$#" -ge 2 ]; then _d="$2"; _n=$((_n+1)); shift 2; else shift; fi ;;
            --work-tree=*)
                _d="${1#--work-tree=}"; _n=$((_n+1)); shift ;;
            -c|--git-dir|--namespace)
                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    [ "${_n}" -eq 1 ] || return 0
    _d="$(_gc_strip_closers "${_d}")"
    _d="${_d%\"}"; _d="${_d#\"}"; _d="${_d%\'}"; _d="${_d#\'}"
    case "${_d}" in ''|-*) return 0 ;; esac
    printf '%s' "${_d}"
}

# _gc_segment_cd_target <segment> — the single path argument of a `cd`
# segment. Echoes nothing for `cd` with no argument (that is $HOME, never a
# repo subject), with several arguments, or for anything that is not cd.
_gc_segment_cd_target() {
    local _p _u
    # shellcheck disable=SC2086
    set -- $1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*) _u="$(_gc_strip_openers "$1")"; shift; set -- "${_u}" "$@"; break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in
            env|command|builtin) shift ;;
            [A-Za-z_]*=*) shift ;;
            *) break ;;
        esac
    done
    [ "${1:-}" = "cd" ] || return 0
    shift
    while [ "$#" -gt 0 ]; do
        case "$1" in -L|-P|-@) shift ;; *) break ;; esac
    done
    [ "$#" -eq 1 ] || return 0
    _p="$(_gc_strip_closers "$1")"
    _p="${_p%\"}"; _p="${_p#\"}"; _p="${_p%\'}"; _p="${_p#\'}"
    case "${_p}" in ''|-*) return 0 ;; esac
    printf '%s' "${_p}"
}

# command_git_subject_dir <command>
#   The directory the command's `git push` acts in, as the command states it:
#   an explicit `-C`/`--work-tree` on that git invocation, else the target of a
#   `cd` in an EARLIER segment of the same compound command. Echoes nothing
#   when the command does not say.
#
#   Push only. `gh pr merge` has no local subject directory — its subject is the
#   PR, which hooks/lib/pr-diff.sh already resolves (#161).
command_git_subject_dir() {
    local _segs _oldifs _seg _cd="" _cd_try="" _dashc="" _found=0
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        if [ "$(_gc_segment_git_sub "${_seg}")" = "push" ]; then
            _dashc="$(_gc_segment_dir_flag "${_seg}")"
            _found=1
            IFS="${_oldifs}"
            break
        fi
        _cd_try="$(_gc_segment_cd_target "${_seg}")"
        [ -n "${_cd_try}" ] && _cd="${_cd_try}"
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    [ "${_found}" -eq 1 ] || return 0
    if [ -n "${_dashc}" ]; then printf '%s' "${_dashc}"; return 0; fi
    [ -n "${_cd}" ] && printf '%s' "${_cd}"
    return 0
}

# command_push_ref <command>
#   The LOCAL ref a `git push` names as the thing being pushed, when it names
#   exactly one: the source half of the single refspec. Echoes nothing for a
#   bare `git push`, for `HEAD` (which carries no information the subject
#   directory does not already have), for a wildcard or multi-refspec push, and
#   for a deletion (`--delete` pushes no content, so there is no subject to
#   measure).
#
#   A `refs/heads/x` form is reduced to `x`. The caller tries the branch form
#   FIRST and then any revision, so a tag or a remote-tracking name DOES resolve
#   — to the commit it peels to, which is the commit such a push actually ships.
#   (An earlier revision of this comment claimed they "simply fail to resolve";
#   that was true of the branch-only validation that turned out to be a bypass.)
#   Only a value that names no commit at all leaves the caller's subject alone.
#
#   Returning nothing is AMBIGUOUS by construction and the caller must treat it
#   so: it means "bare push" (HEAD is the subject) for one command and "deletion
#   or multi-ref push" (HEAD is NOT the subject) for another. Use
#   command_push_subject_is_partial to tell those apart.
command_push_ref() {
    local _segs _oldifs _seg _r="" _n=0 _found=0 _u
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        if [ "$(_gc_segment_git_sub "${_seg}")" = "push" ]; then
            _found=1
            # shellcheck disable=SC2086
            set -- ${_seg}
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    '('|'{') shift ;;
                    '('*|'{'*) _u="$(_gc_strip_openers "$1")"; shift; set -- "${_u}" "$@"; break ;;
                    *) break ;;
                esac
            done
            while [ "$#" -gt 0 ]; do
                case "$1" in env) shift ;; [A-Za-z_]*=*) shift ;; *) break ;; esac
            done
            case "${1:-}" in git|*/git) shift ;; *) IFS="${_GC_SEP}"; continue ;; esac
            # global flags, then the `push` word itself
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    -C|-c|--git-dir|--work-tree|--namespace)
                        if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                    -*) shift ;;
                    *) break ;;
                esac
            done
            [ "$#" -gt 0 ] && shift   # drop `push`
            while [ "$#" -gt 0 ]; do
                # Closer-normalise every word before matching, for the same
                # reason as _gc_push_seg_shape: a closer glued to a flag
                # (`(git push origin x --delete)`) otherwise misses its literal
                # arm and is read as an ordinary option.
                _gc_strip_closers_var "$1"
                case "${_GC_W}" in
                    '') shift; continue ;;
                    --delete|-d) return 0 ;;
                    --repo|-o|--push-option|--receive-pack|--exec)
                        if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                    --) shift ;;
                    -*) shift ;;
                    *)
                        # A word made up ENTIRELY of group closers is
                        # punctuation, not a refspec — a parenthesised push
                        # written with spaces and no trailing semicolon reaches
                        # here as ONE segment whose last word is a bare closer,
                        # and counting it made that a THREE-positional push, so
                        # the ref stopped resolving and the gate fell back to the
                        # checkout HEAD. That is now handled by the `''` arm
                        # above: the word is normalised before the `case`, so a
                        # closer-only word is already the empty string here.
                        _n=$((_n+1))
                        # positional 1 is the remote; positional 2 is the refspec.
                        [ "${_n}" -eq 2 ] && _r="$1"
                        [ "${_n}" -gt 2 ] && return 0
                        shift ;;
                esac
            done
            break
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    [ "${_found}" -eq 1 ] || return 0
    [ -n "${_r}" ] || return 0
    _r="$(_gc_strip_closers "${_r}")"
    _r="${_r%\"}"; _r="${_r#\"}"; _r="${_r%\'}"; _r="${_r#\'}"
    _r="${_r#+}"          # force-push marker
    _r="${_r%%:*}"        # src:dst -> src (what is being pushed)
    _r="${_r#refs/heads/}"
    # What survives here is any single revision git will accept as a push
    # SOURCE: a branch name, a fully-qualified ref, a raw sha, or a revision
    # expression (`topic~1`, `topic^{commit}`). Restricting this to branch names
    # was a BYPASS, not a safety measure: `git push origin <sha>:refs/heads/x`
    # is a perfectly ordinary push whose source the caller then failed to
    # resolve, so the gate silently fell back to the checkout's HEAD and
    # measured a commit the command does not push. Measured against the real
    # guard: with a clean worktree checked out, the sha form ALLOWED where the
    # equivalent named-branch push DENIED. The caller resolves this as a
    # revision (`<r>^{commit}`) and ignores it if it does not resolve, so an
    # unparseable value costs a fallback, never a wrong subject.
    case "${_r}" in
        ''|HEAD|-*) return 0 ;;
        *'*'*|*'?'*|*'['*) return 0 ;;
    esac
    printf '%s' "${_r}"
}

# command_push_subject_is_partial <command>
#   0 when the command's push carries something OTHER than one commit that
#   `command_push_ref` can name — i.e. when "no ref resolved" must NOT be read as
#   "the checkout's HEAD is the subject":
#     - a deletion (`--delete`, `-d`, or an empty-source refspec `:branch`),
#       which pushes no content at all;
#     - a multi-ref push (`--all`, `--mirror`, `--tags`, or 2+ refspecs), which
#       pushes several and HEAD is at best one of them.
#
#   ANNOUNCE-ONLY by contract. The caller must not use this to skip a deny:
#   a command can contain several push segments (`git push --delete origin x;
#   git push origin main`), and this returns 0 if ANY of them is partial — so
#   suppressing a gate on it would let a deletion in segment 1 excuse a real
#   push in segment 2. Reporting "the subject is not one commit" is safe in
#   that direction; acting on it is not.
#
#   Fail-safe: an unparseable command returns 1 (says nothing), never a claim.
command_push_subject_is_partial() {
    local _segs _oldifs _seg _shape
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        if [ "$(_gc_segment_git_sub "${_seg}")" = "push" ]; then
            # Expressed on the shared segment shape rather than a private copy
            # of the parsing loop. The two are exactly equivalent — this returns
            # 0 for a deletion flag, a broad flag, any empty-source refspec, or
            # two or more refspecs — and single-sourcing the parse is the point:
            # the bare-closer defect fixed in `command_push_ref` was present in
            # this function's duplicate loop too, which is how one parser came to
            # answer a different question than its neighbour about the same
            # command.
            _shape="$(_gc_push_seg_shape "${_seg}")"
            if [ -n "${_shape}" ]; then
                # shellcheck disable=SC2086
                set -- ${_shape}   # <del> <refs> <empty> <broad> <odd>
                if [ "$1" -eq 1 ] || [ "$4" -ne 0 ] || [ "$3" -ge 1 ] || [ "$2" -ge 2 ] \
                   || [ "$5" -ge 1 ]; then
                    IFS="${_oldifs}"; return 0
                fi
            fi
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    return 1
}

# _gc_push_seg_shape <segment>
#   Classifies ONE `git push` segment, echoing five space-separated integers:
#     <explicit-delete> <refspec-count> <empty-source-refspec-count> <broad> <odd>
#   where `broad` is 1 when the segment carries `--all`, `--mirror` or `--tags`
#   (each of which pushes refs no refspec names) and `odd` counts refspecs whose
#   shape is recognisable but classifiable neither way — today only a bare `:`,
#   empty on BOTH halves. Echoes nothing when the segment is not a `git push` —
#   the caller must treat that as "unparseable", never as a shape.
#
#   `odd` exists so the two callers can disagree about the same refspec, which
#   they must: a bare `:` ships no content (empty source) yet names nothing to
#   delete, so `command_push_is_all_deletions` MUST refuse it — a security
#   predicate guesses toward "keep measuring" — while
#   `command_push_subject_is_partial` MUST still announce it, which is free.
#   Collapsing `odd` into either `refs` or `empty` silently changes one of those
#   two answers; it dropped the announcement when this refactor first landed.
#
#   THE single place `git push` arguments are parsed for shape:
#   `command_push_subject_is_partial` and both predicates below are expressed on
#   it, so the "skip openers, env assignments, the git word, the global flags
#   and the `push` word" preamble exists once. That is not tidiness — the
#   bare-closer defect fixed in `command_push_ref` was present, identically, in
#   the duplicate loop `command_push_subject_is_partial` used to carry, so two
#   parsers were answering different questions about the same command.
#   `command_push_ref` keeps its own scan (it needs the refspec's VALUE, not a
#   count) and is the one remaining copy; a parsing fix here must be mirrored
#   there.
_gc_push_seg_shape() {
    local _u _n=0 _del=0 _refs=0 _empty=0 _broad=0 _odd=0 _a
    # shellcheck disable=SC2086
    set -- $1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*) _u="$(_gc_strip_openers "$1")"; shift; set -- "${_u}" "$@"; break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in env) shift ;; [A-Za-z_]*=*) shift ;; *) break ;; esac
    done
    case "${1:-}" in git|*/git) shift ;; *) return 0 ;; esac
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -C|-c|--git-dir|--work-tree|--namespace)
                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
            -*) shift ;;
            *) break ;;
        esac
    done
    [ "${1:-}" = "push" ] || return 0
    shift
    while [ "$#" -gt 0 ]; do
        # EVERY word is closer-normalised, not just the refspecs. Trailing group
        # closers were previously stripped only where a refspec was read, so a
        # closer GLUED to a flag never matched its literal arm and fell through
        # to the generic `-*`. Measured: `git push origin :x --tags` correctly
        # refuses (broad=1), while `(git push origin :x --tags)` emitted broad=0
        # and CERTIFIED as deletion-only — and `--tags` pushes every tag "in
        # addition to the refspecs explicitly listed", so that is a content push
        # the gate then skipped all four content legs for, while announcing
        # "ships no content". A trailing `;` restored the refusal, which is why
        # no cell caught it: every group cell used a spaced `)` or a brace group.
        # Normalising once, here, makes flags and refspecs impossible to treat
        # differently — the class of bug, not the instance.
        _gc_strip_closers_var "$1"
        case "${_GC_W}" in
            '') shift ;;
            --delete|-d) _del=1; shift ;;
            --all|--mirror|--tags) _broad=1; shift ;;
            --repo|-o|--push-option|--receive-pack|--exec)
                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
            --) shift ;;
            -*) shift ;;
            *)
                _n=$((_n+1))
                # positional 1 is the remote; 2+ are refspecs.
                if [ "${_n}" -ge 2 ]; then
                    _refs=$((_refs+1))
                    _a="${_GC_W}"
                    _a="${_a%\"}"; _a="${_a#\"}"; _a="${_a%\'}"; _a="${_a#\'}"
                    _a="${_a#+}"    # force-push marker
                    # `:<dst>` with a NON-EMPTY dst is the empty-source form,
                    # i.e. a deletion: there is no source half, so the refspec
                    # can carry no content by construction. A bare `:` (empty
                    # on both halves) is `odd`, not a deletion — it names
                    # nothing to delete, and a security predicate guesses toward
                    # "keep measuring", never toward "skip the gate".
                    case "${_a}" in
                        :) _odd=$((_odd+1)) ;;
                        :?*) _empty=$((_empty+1)) ;;
                    esac
                fi
                shift ;;
        esac
    done
    printf '%s %s %s %s %s' "${_del}" "${_refs}" "${_empty}" "${_broad}" "${_odd}"
}

# _gc_seg_is_inert <segment>
#   0 when a segment cannot execute anything that ships content: it is empty,
#   it is nothing but group punctuation (`)`, `}`, `;` — `{ git push …; }` splits
#   into a command segment and a bare `}`), or its command word is `cd` (which
#   cannot push, and which the guard's subject resolver already models).
#
#   Deliberately a WHITELIST. Everything else — another git invocation, a script,
#   `bash -c`, even `echo` — returns 1. See command_push_is_all_deletions for why
#   the fail direction has to be this strict.
_gc_seg_is_inert() {
    local _w
    # shellcheck disable=SC2086
    set -- $1
    while [ "$#" -gt 0 ]; do
        case "$1" in
            '('|'{') shift ;;
            '('*|'{'*) _w="$(_gc_strip_openers "$1")"; shift; set -- "${_w}" "$@"; break ;;
            *) break ;;
        esac
    done
    while [ "$#" -gt 0 ]; do
        case "$1" in *[!\)\}\;]*) break ;; *) shift ;; esac
    done
    [ "$#" -eq 0 ] && return 0
    case "$1" in cd) return 0 ;; esac
    return 1
}

# command_push_is_all_deletions <command>
#   0 iff the command contains at least one `git push` segment AND EVERY push
#   segment in it is a deletion — one that carries `--delete`/`-d`, or whose
#   refspecs are ALL of the empty-source `:<dst>` form. Such a command ships no
#   content at all, so measuring it at the checkout's HEAD is measuring a commit
#   it does not push: that is how `git push --delete origin foo` came to be
#   denied by routing-governance for routing files the deletion does not carry
#   (issue #229).
#
#   EVERY segment, not any — and that is the whole safety argument. `git push
#   --delete origin x; git push origin main` must NOT qualify: segment 2 ships
#   real content, and a predicate that fired on segment 1 would let the deletion
#   excuse it. `command_push_subject_is_partial` is the ANY-form and stays
#   announce-only for exactly this reason; this one is the ALL-form and is the
#   only one a gate may act on.
#
#   `--all`/`--mirror`/`--tags` anywhere in a segment disqualifies it: those push
#   refs no refspec names, so "all its refspecs are deletions" says nothing about
#   what the segment ships.
#
#   Fail-safe: no push segment, an unparseable segment, or any doubt returns 1
#   — "says nothing" — which leaves the caller measuring HEAD exactly as before.
#   Every failure mode therefore costs a stale measurement, never a skipped gate.
#   That direction is structural, not incidental: the only routes to "deletion"
#   are an explicit `--delete`/`-d`, or every refspec literally beginning with
#   `:` — which by construction has no source half. Word-splitting or quoting
#   differences can only ADD positionals, and an added positional that is not
#   `:`-prefixed pushes the answer toward not-a-deletion. Measured against the
#   parser for `$(...)`, `"$VAR"`, `\:a`, `":a main"`, `--`, and every
#   value-taking option form; see tests/test-push-gate-detection.sh.
#
#   DOCUMENTED CEILING: `--delete` supplied as the VALUE of an option this
#   parser does not model would be read as the deletion flag. Every value-taking
#   `git push` option that exists today is modelled (`--repo`, `-o`,
#   `--push-option`, `--receive-pack`, `--exec`), so reaching this needs a git
#   option that does not exist — the same class as the `bash -c` indirection
#   ceiling the guard already documents. If git gains a value-taking push
#   option, add it to the skip list here AND in `command_push_ref`.
command_push_is_all_deletions() {
    # `_cmd`, not `$1`, below the loop: `set -- ${_shape}` inside it REPLACES the
    # positional parameters, so by the time control reaches the end of this
    # function `$1` is a shape digit and not the command. Reading `$1` there
    # silently handed `command_parse_balanced` the string "0" — which parses
    # balanced — and re-opened the bypass this gate exists to close, with every
    # unit test still green because they exercise the predicate, not the
    # variable. Caught by re-running the attack probe after a pure refactor.
    local _cmd="$1"
    local _segs _oldifs _seg _shape _found=0
    # An UNTRUSTWORTHY PARSE cannot certify anything. This scanner does not
    # interpret backslash escapes (see the header), so outside an active quote a
    # `\'` is a literal quote character to real bash but toggles quote mode
    # here — and everything after it, including a genuine `;` and a real push,
    # is swallowed as "inside a quote". Measured:
    #     git push --delete origin scratch; cd \'; git push origin main
    # merges into one segment whose first word is `cd`, so the segment whitelist
    # vouches for it and the trailing push is never inspected — certified as
    # deletion-only while really pushing. Confirmed against real bash: the
    # deletion runs, `cd \'` fails harmlessly, and `;` does not care, so the
    # push lands on the remote. It contains no `$(`, backtick or `<(`, so the
    # substitution guard below does not see it either.
    #
    # The scanner ALREADY knows: it sets `_GC_UNBALANCED`, and `_gc_precise` in
    # openspec-guard.sh gates the other precise predicates on exactly this.
    # Checking it here rather than only at the call site is the point — this
    # function's contract is "any doubt returns 1", an unbalanced parse IS that
    # doubt, and a future call site cannot forget to gate what the function
    # gates itself. The same family (an incomplete heredoc, the 4096-char scan
    # budget) is covered by the same one check.
    #
    # Deliberately NOT applied to `command_push_subject_is_partial`: it is
    # announce-only, so its failure mode is a possibly-wrong advisory rather
    # than a skipped gate — and its advisory ("HEAD may not be what is pushed")
    # is if anything MORE true when the parse is untrustworthy. Gating it would
    # suppress information for symmetry's sake.
    #
    # The check is at the END of this function, not here, purely for cost:
    # `command_parse_balanced` re-runs the char scan, which is O(n^2) in bash
    # 3.2, and this runs synchronously in a PreToolUse gate. Placing it on the
    # success path alone means the second scan is paid only by commands that
    # would otherwise be certified — a small subset — instead of by every push.
    # Measured end-to-end against the real guard: at the head of the function it
    # cost +44ms on a typical push and +535ms on a 4KB command; on the success
    # path it costs those only for an actual deletion candidate. Semantically
    # identical: it only ever converts a `return 0` into a `return 1`.
    #
    # A command substitution RUNS, wherever it appears, and its output is only
    # what happens to the result afterwards. `$(…)`, backticks and process
    # substitution therefore each smuggle a whole command inside a segment this
    # predicate would otherwise vouch for — including inside the arguments of
    # the deletion itself. Measured against this predicate before the check
    # existed; every one of these certified as deletion-only while really
    # pushing content:
    #     git push --delete origin scratch && cd $(git push origin main)
    #     git push --delete origin scratch && cd `git push origin main`
    #     git push --delete origin $(git push origin main)
    #     git push --delete origin x < <(git push origin main)
    # Note the third: the substitution is an argument of the RECOGNISED deletion
    # segment, so a guard scoped to the `cd` whitelist entry — the obvious fix
    # once the first shape is known — leaves it wide open. Confirmed against
    # real bash: the inner push completes and the ref appears on the remote
    # before the outer command has done anything with the captured output.
    #
    # The check is therefore on the WHOLE raw command, not per-segment and not
    # per-token: `_gc_split_segments` does not treat `$(` as a boundary, and by
    # the time a segment has been word-split the construct is scattered across
    # tokens (`$(git`, `push`, …, `main)`), which is exactly how it slipped past
    # a first-word whitelist. Coarse on purpose — a substitution inside single
    # quotes is literal data and is refused anyway. Same trigger the heredoc
    # scanner above already uses to mark an expanded body untrusted, and the
    # same one-directional cost as the segment whitelist: a lost skip, a
    # fallback to measuring HEAD, never a new deny.
    # `=(` is ZSH process substitution, and zsh is the shell that actually
    # executes these commands (CLAUDE.md: "the model's Bash tool is NOT bash").
    # Measured here: `/bin/zsh -c 'cd =(touch /tmp/X; echo x)'` creates the file
    # — the inner command runs. Omitting it made `git push --delete origin
    # =(git push origin main)` certify as deletion-only, i.e. the substitution
    # sitting inside the recognised deletion's own arguments, which is the exact
    # shape this layer exists to stop. `${ ` / `${|` are bash>=5.3 funsubs,
    # unreachable on bash 3.2 or zsh 5.9 and added forward-looking; they are
    # narrow enough not to match an ordinary `${VAR}`.
    #
    # This list has now been wrong twice. Treat it as a KNOWN-INCOMPLETE
    # enumeration of one execution-smuggling family, not as a proof — which is
    # why the segment whitelist and the balanced-parse gate exist alongside it
    # rather than being folded into it.
    case "$1" in
        *'$('*|*'`'*|*'<('*|*'>('*|*'=('*|*'${ '*|*'${|'*) return 1 ;;
    esac
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        if [ "$(_gc_segment_git_sub "${_seg}")" != "push" ]; then
            # EVERY segment must be accounted for, not just the recognized
            # pushes. "All recognized push segments are deletions" is a WEAKER
            # claim than "this command ships no content", and the gap between
            # them is a false ALLOW rather than the safe fallback every other
            # ceiling in this file degrades to. Measured against this predicate
            # before the check existed — all three of these certified as
            # deletion-only while shipping real content:
            #   git push --delete origin x && git -c alias.p=push p origin main
            #   git push --delete origin x && ./deploy.sh
            #   git push --delete origin x && bash -c "git push origin main"
            # The first is the sharpest: a git ALIAS is invisible to
            # `_gc_segment_git_sub` (it reports the alias word, not `push`), and
            # it needs nothing new from git — an alias configured in
            # ~/.gitconfig in an earlier turn works just as well as the inline
            # `-c alias.…=push` above. Reproduced end-to-end against the real
            # guard: routing branch, no covering verdict, ordinary push DENIED
            # while the alias compound was ALLOWED with the guard announcing
            # "ships no content".
            #
            # Hence a WHITELIST, not a blocklist of git subcommands: a
            # subcommand check closes the alias case and leaves the script and
            # `bash -c` cases open. An allowlist of non-pushing git builtins was
            # considered and rejected — `git subtree push`, `git submodule
            # foreach`, and `git send-pack` all push, so the list would have to
            # be provably complete rather than merely plausible, and a future
            # subcommand would silently join the safe side.
            #
            # The cost is only a forgone optimisation: a compound command falls
            # back to measuring HEAD, which is exactly today's behaviour, so
            # this can lose a skip but can never add a deny.
            _gc_seg_is_inert "${_seg}" || { IFS="${_oldifs}"; return 1; }
            IFS="${_GC_SEP}"
            continue
        fi
        _shape="$(_gc_push_seg_shape "${_seg}")"
        if [ -z "${_shape}" ]; then IFS="${_oldifs}"; return 1; fi
        _found=1
        # shellcheck disable=SC2086
        set -- ${_shape}   # <del> <refs> <empty> <broad> <odd>
        if [ "$4" -ne 0 ]; then IFS="${_oldifs}"; return 1; fi
        if [ "$1" -eq 1 ]; then IFS="${_GC_SEP}"; continue; fi
        if [ "$2" -ge 1 ] && [ "$2" -eq "$3" ]; then IFS="${_GC_SEP}"; continue; fi
        IFS="${_oldifs}"; return 1
    done
    IFS="${_oldifs}"
    [ "${_found}" -eq 1 ] || return 1
    # Last gate, and the reason is in the header comment above: an untrustworthy
    # parse cannot certify anything, and paying for the re-scan here rather than
    # at the top confines the cost to commands that would otherwise be certified.
    # `|| return 1` on the ABSENCE too, not just on an unbalanced parse. The
    # `if command -v … ; then` form certified when the check was unavailable —
    # the opposite of this function's own "any doubt returns 1" contract. It is
    # currently unreachable (the predicate is defined earlier in this same file,
    # so sourcing order guarantees it), which makes the permissive form dead
    # code that falsely implies coverage — the anti-pattern CLAUDE.md already
    # calls out for the impl_evidence_detail token/jq guard.
    command -v command_parse_balanced >/dev/null 2>&1 || return 1
    command_parse_balanced "${_cmd}" || return 1
    return 0
}

