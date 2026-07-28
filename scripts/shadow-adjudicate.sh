#!/bin/bash
# shadow-adjudicate.sh — label IMPLEMENT-leg shadow records (the Stage C1 corpus)
# and report the pre-registered false-block rate over independent episodes.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, and its output MUST
# NOT be wired into an enforcement decision — the guard is the only decider.
#
# The pre-registration in openspec/changes/implement-shadow-event/design.md is an
# INPUT here, not something this script may redefine: the bands, the n=29 floor,
# the >=2-repo diversity requirement and the episode denominator all come from
# that file.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

REQUIRED_PREDICATE_VERSION=2
FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${IMPLEMENT_SHADOW_LOG:-$HOME/.claude/.push-implement-shadow.jsonl}"
ADJ_LOG="${IMPLEMENT_ADJUDICATION_LOG:-$HOME/.claude/.push-implement-adjudication.jsonl}"

# _band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, 0.10) <  alpha
#   ADVISORY-ONLY <=> P(X >= k | n, 0.20) <= alpha
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED (a pinned test).
_band() {
    awk -v k="${1:-0}" -v n="${2:-0}" -v a="${ALPHA}" \
        -v dp="${DENY_P}" -v ap="${ADVISORY_P}" '
    function tail(kk, nn, p, mode,   i, t, s) {
        # mode "le": sum_{i<=kk}   mode "ge": sum_{i>=kk}
        # Term recurrence rather than factorials, so large n cannot overflow.
        s = 0; t = (1 - p) ^ nn
        for (i = 0; i <= nn; i++) {
            if (mode == "le" && i <= kk) s += t
            if (mode == "ge" && i >= kk) s += t
            if (i < nn) t = t * (nn - i) / (i + 1) * p / (1 - p)
        }
        return s
    }
    BEGIN {
        if (n < 1) { print "INSUFFICIENT"; exit }
        if (tail(k, n, dp, "le") <  a) { print "DENY";          exit }
        if (tail(k, n, ap, "ge") <= a) { print "ADVISORY-ONLY"; exit }
        print "NARROWED"
    }'
}

# _AWK_EPOCH — shared awk prelude converting ISO-8601 UTC to epoch seconds,
# returning -1 when unparseable. In awk rather than `date` because `date -d`
# (GNU) and `date -j -f` (BSD/macOS) are mutually incompatible.
_AWK_EPOCH='
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
        if (m <= 2) y = y - 1
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    function iso_epoch(s,   y, mo, d, hh, mi, ss) {
        if (s !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return -1
        y  = substr(s,1,4)+0;  mo = substr(s,6,2)+0;  d  = substr(s,9,2)+0
        hh = substr(s,12,2)+0; mi = substr(s,15,2)+0; ss = substr(s,18,2)+0
        return days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss
    }'

# _shadow_tsv <jq-array-expr> — emit TSV for v2 records, tolerating malformed
# lines. `jq` ABORTS on the first parse error, so a single truncated line would
# silently truncate the whole corpus (and `2>/dev/null` hid it). `-R` + `fromjson?`
# skips only the bad line. Unparseable lines are counted and reported by --status.
_shadow_tsv() {
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
       "fromjson? // empty | select(.predicate_version == \$pv) | ${1} | @tsv" \
       "${SHADOW_LOG}" 2>/dev/null
}

# _episodes — group v2 shadow records into independent episodes.
# One TAB-separated line per episode:
#   <episode_id> <repo> <branch> <session_token> <record_ids_csv>
# Membership: same (repo, branch, session_token) AND ts within
# EPISODE_WINDOW_SEC of the episode's FIRST record — anchored, not rolling.
# A rolling gap would chain a whole day of intermittent pushes into one episode
# and drive the denominator below the real number of decision points.
#
# Field splitting is done ENTIRELY in awk. `IFS=$'\t' read` treats tab as IFS
# WHITESPACE, so consecutive tabs collapse and every field after an empty one
# shifts left — a record with an empty branch (which implement-shadow.sh writes
# whenever `git rev-parse --abbrev-ref HEAD` fails) silently vanished from the
# denominator with no exclusion row. awk with an explicit -F'\t' preserves
# empty fields.
_episodes() {
    [ -f "${SHADOW_LOG}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    _shadow_tsv '[.repo, .branch, .session_token, .ts, .record_id]' \
    | awk -F'\t' "${_AWK_EPOCH}"'
        {
          # A malformed ts is EXCLUDED, not merged: iso_epoch returns -1 for
          # every unparseable value, so two corrupt records sharing a key would
          # satisfy (-1)-(-1)=0 <= window and collapse into one episode on a
          # time relation nothing verified. Excluding keeps corrupt data from
          # moving the denominator either way, and inflation is the dangerous
          # direction because it makes the floor easier to reach.
          if ($5 == "") next
          e = iso_epoch($4)
          if (e < 0) next
          print $1 "\t" $2 "\t" $3 "\t" e "\t" $5
        }' \
    | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n \
    | awk -F'\t' -v w="${EPISODE_WINDOW_SEC}" '
        # Compare the three key fields DIRECTLY rather than concatenating them
        # with a separator. A concatenated key collides whenever a field
        # contains the separator byte: branch="x\001y" + token="t1" builds the
        # same key as branch="x" + token="y\001t1", silently merging unrelated
        # episodes and shrinking the denominator. Field-wise comparison has no
        # such class of bug and is simpler.
        {
          if (NR == 1 || $1 != p1 || $2 != p2 || $3 != p3 || ($4 - anchor) > w) {
            if (NR > 1) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids
            eid = $5; erepo = $1; ebranch = $2; etok = $3; ids = $5
            anchor = $4; p1 = $1; p2 = $2; p3 = $3
          } else {
            ids = ids "," $5
          }
        }
        END { if (NR > 0) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids }'
}

# _claimant -> human | agent
# Biased toward "agent": a human using `!` inside a session is misclassified and
# pays one re-confirmation, whereas an agent's self-label counted silently would
# corrupt the rate. This leg governs agent pushes, so the subject has a live
# incentive to grade its own gate.
#
# Signals are DIRECT evidence of an agent context only: CLAUDECODE, and a parent
# process named claude. A "stdout is not a tty" check was specified originally
# and is deliberately NOT used — it misfires on a human redirecting or piping
# output, and because human-claimed episodes are the ONLY ones that count toward
# the rate, that false positive does not merely cost a re-confirmation: it makes
# the n=29 floor unreachable for anyone who habitually pipes. It also buys no
# integrity, since every signal here is forgeable regardless.
#
# The mitigation is not that forgery is impossible; it is that a forged clean
# rate requires a deliberate lie about provenance rather than merely running the
# tool. Output says human-CLAIMED, never human-verified.
# CLAUDE_CODE_SESSION_ID is the repo's established "inside a Claude Code turn"
# marker (session-token.sh, phase-attest.sh, verify-and-record.sh, gate-status.sh);
# CLAUDECODE is set alongside it. Both are checked so this stays consistent with
# the rest of the codebase rather than relying on one of the pair.
_claimant() {
    if [ -n "${CLAUDECODE:-}" ] || [ -n "${CLAUDE_CODE_SESSION_ID:-}" ]; then echo agent; return; fi
    # NOTE: this $PPID check is INERT in the Claude Code harness — a Bash tool
    # call runs the script under an intermediate shell, so the parent is
    # /bin/zsh and `claude` is only the GRANDparent. It fires only for a direct
    # `claude` parent. It is kept because it costs nothing and catches that case.
    #
    # Walking several ancestors WAS tried and reverted: ancestry survives
    # `env -u`, so it does harden the env-stripping bypass — but inside any
    # Claude Code session every ancestry contains `claude`, which makes the
    # human path unreachable in-session and, critically, untestable. Buying
    # marginal hardening (the docs already concede forgeability) by making the
    # only countable claimant untestable is the wrong trade. Do not re-add it
    # without an answer for how `label()` simulates a human.
    case "$(ps -o comm= -p "$PPID" 2>/dev/null)" in *claude*) echo agent; return;; esac
    echo human
}

_record_field() { # _record_field <record_id> <field>
    jq -r --arg id "${1:-}" --arg f "${2:-}" \
       'select(.record_id == $id) | .[$f] // empty' "${SHADOW_LOG}" 2>/dev/null | head -1
}

cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _pv _ts _claim
    case "${_verdict}" in
        true_catch|false_block|unknown) ;;
        *) echo "error: --verdict must be true_catch, false_block, or unknown" >&2; return 1;;
    esac
    [ -f "${SHADOW_LOG}" ] || { echo "error: no shadow log at ${SHADOW_LOG}" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; return 1; }
    _pv="$(_record_field "${_rid}" predicate_version)"
    [ -z "${_pv}" ] && { echo "error: no record '${_rid}' in ${SHADOW_LOG}" >&2; return 1; }
    if [ "${_pv}" != "${REQUIRED_PREDICATE_VERSION}" ]; then
        echo "error: record '${_rid}' is predicate_version ${_pv}; only v${REQUIRED_PREDICATE_VERSION} is adjudicable." >&2
        echo "       v1 measured a different subject for merges and MUST NOT be pooled with v2." >&2
        return 1
    fi
    if [ ! -f "${ADJ_LOG}" ]; then
        : > "${ADJ_LOG}" 2>/dev/null || { echo "error: cannot write ${ADJ_LOG}" >&2; return 1; }
    fi
    chmod 600 "${ADJ_LOG}" 2>/dev/null
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    _claim="$(_claimant)"
    # `tty` prints "not a tty" to STDOUT and ALSO exits 1, so `$(tty || echo X)`
    # captures BOTH strings — a two-line value in every non-interactive run,
    # which is nearly all of them. Branch on the exit status instead.
    if _tty="$(tty 2>/dev/null)"; then :; else _tty="not-a-tty"; fi
    jq -cn --arg rid "${_rid}" --arg ts "${_ts}" --arg v "${_verdict}" \
           --arg r "${_reason}" --arg c "${_claim}" \
           --arg u "${USER:-unknown}" --arg tty "${_tty}" \
           --arg par "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)" \
           --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
           --arg agentenv "$([ -n "${CLAUDECODE:-}" ] && echo present || echo absent)" \
       '{schema_version:1,record_id:$rid,ts:$ts,verdict:$v,reason:$r,claimant:$c,
         provenance:{user:$u,tty:$tty,parent:$par,repo_head:$head,agent_env:$agentenv}}' \
       >> "${ADJ_LOG}" 2>/dev/null || { echo "error: append to ${ADJ_LOG} failed" >&2; return 1; }
    echo "recorded: ${_rid}  ${_verdict}  (${_claim}-claimed)"
    [ "${_claim}" = "agent" ] && \
        echo "note: agent-claimed — excluded from the rate until a human re-confirms."
    # Must reflect the ACTUAL claimant. Hardcoding "HUMAN-CLAIMED" printed
    # "(agent-claimed)" and "HUMAN-CLAIMED" two lines apart on the same run.
    echo "label: $(printf '%s' "${_claim}" | tr '[:lower:]' '[:upper:]')-CLAIMED, not human-verified."
    return 0
}

_adjudicated_ids() {
    [ -f "${ADJ_LOG}" ] || return 0
    jq -r '.record_id // empty' "${ADJ_LOG}" 2>/dev/null | sort -u
}

# cmd_next — oldest v2 record with no adjudication, plus how to label it.
# Read-only: never touches the sidecar. Always exits 0 (observational).
cmd_next() {
    local _seen _line
    [ -f "${SHADOW_LOG}" ] || { echo "no shadow log at ${SHADOW_LOG} — nothing outstanding."; return 0; }
    command -v jq >/dev/null 2>&1 || { echo "jq required — cannot read the corpus."; return 0; }
    _seen="$(_adjudicated_ids)"
    # Records whose ts is unparseable are skipped here too — --status can never
    # count them, so offering one for adjudication wastes the operator's time.
    _line="$(_shadow_tsv 'select((.ts // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
              | [.record_id,.ts,.repo,.branch,.action,.diff_base,
                 (.impl_in_chain|tostring),(.material_source|tostring),
                 .impl_evidence_kind,.transcript_path]' \
            | sort -t "$(printf '\t')" -k2,2 \
            | while IFS= read -r _row; do
                  _id="$(printf '%s' "${_row}" | cut -f1)"
                  [ -z "${_id}" ] && continue
                  if [ -n "${_seen}" ] && printf '%s\n' "${_seen}" | grep -qxF "${_id}"; then
                      continue
                  fi
                  printf '%s\n' "${_row}"; break
              done)"
    if [ -z "${_line}" ]; then
        # "no v2 records exist" and "all v2 records adjudicated" are different
        # states and must not share a message: the first means nothing is
        # countable yet, the second means the work is done. Conflating them
        # reports an empty corpus as complete.
        local _n_v2 _n_v1
        _n_v2="$(_shadow_tsv '[.record_id]' | grep -c . )"
        _n_v1="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
                   'fromjson? // empty | select(.predicate_version != $pv) | .record_id' \
                   "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        if [ "${_n_v2}" -eq 0 ]; then
            printf 'no v%s records yet — nothing is adjudicable.\n' "${REQUIRED_PREDICATE_VERSION}"
            [ "${_n_v1}" -gt 0 ] && \
                printf '  %s v1 record(s) present, excluded: v1 measured a different subject and is unpoolable with v2.\n' "${_n_v1}"
            printf '  The corpus grows as the IMPLEMENT leg fires; see --status for the floor.\n'
            return 0
        fi
        printf 'nothing outstanding — all %s v%s record(s) are adjudicated.\n' \
               "${_n_v2}" "${REQUIRED_PREDICATE_VERSION}"
        return 0
    fi
    # Rendered by awk, not `IFS=$'\t' read`: tab is IFS whitespace, so an empty
    # field (e.g. a record with no branch) collapses and shifts every later
    # column left — which mislabels `action` as `branch` and blanks the
    # spec-mandated transcript_path pointer.
    printf '%s\n' "${_line}" | awk -F'\t' -v self="$0" '{
        printf "%s   %s\n", $1, $2
        printf "  repo    %s\n  branch  %s\n", $3, $4
        printf "  action  %s   diff_base %s\n", $5, $6
        printf "  why     impl_in_chain=%s, material_source=%s, evidence=%s\n", $7, $8, $9
        printf "  read    %s\n\n", $10
        printf "to label:\n  %s %s --verdict <true_catch|false_block|unknown> --reason \"...\"\n", self, $1
    }'
    return 0
}

# _episode_verdict <record_ids_csv>
# Prints two lines: the episode verdict, then human|agent.
# Worst-verdict-wins: any false_block -> false_block; else any unknown ->
# unknown; else true_catch; else unlabeled. Deny-bias, consistent with the
# verdict layer, and it biases AGAINST flipping the gate.
# Claimant is "agent" only when NO human-claimed adjudication exists for the
# episode — a human re-confirmation re-includes it.
_episode_verdict() {
    local _ids="${1:-}" _v="unlabeled" _claim="agent" _has_human=0 _id _rows
    local _latest _rv _rc
    if [ ! -f "${ADJ_LOG}" ]; then printf 'unlabeled\nagent\n'; return; fi
    _rows="$(jq -r '[.record_id,.verdict,.claimant] | @tsv' "${ADJ_LOG}" 2>/dev/null)"
    for _id in $(printf '%s' "${_ids}" | tr ',' ' '); do
        # LATEST adjudication per record wins. The sidecar is append-only, so the
        # last matching row is the most recent one. Folding over ALL rows instead
        # makes a correction a silent no-op: re-adjudicating a fat-fingered
        # false_block to true_catch would print success while the earlier verdict
        # continued to win, permanently poisoning a rate that gates a deny-flip.
        # Claimant comes from the same latest row, so an agent overwriting a
        # human's label correctly reverts the episode to excluded.
        _latest="$(printf '%s\n' "${_rows}" \
                   | awk -F'\t' -v id="${_id}" '$1 == id { v = $2; c = $3 }
                                                END { if (v != "") print v "\t" c }')"
        [ -z "${_latest}" ] && continue
        _rv="$(printf '%s' "${_latest}" | cut -f1)"
        _rc="$(printf '%s' "${_latest}" | cut -f2)"
        [ "${_rc}" = "human" ] && _has_human=1
        # `if` rather than `[ … ] && …`: this repo's CLAUDE.md documents the
        # &&-as-last-statement form as a recurring bug class (it yields exit 1
        # and can flip an enclosing function's return code). Harmless in this
        # position today, but this variable feeds a deny-flip decision.
        case "${_rv}" in
            false_block) _v="false_block" ;;
            unknown)     if [ "${_v}" != "false_block" ]; then _v="unknown"; fi ;;
            true_catch)  if [ "${_v}" = "unlabeled" ];    then _v="true_catch"; fi ;;
        esac
    done
    [ "${_has_human}" -eq 1 ] && _claim="human"
    printf '%s\n%s\n' "${_v}" "${_claim}"
}

# cmd_status — episode-level readout. Observational; always exits 0.
cmd_status() {
    local _tot=0 _lab=0 _fb=0 _tc=0 _unk=0 _agent=0 _unlab=0 _v1=0
    local _repos="" _eid _repo _branch _tok _ids _vc _v _c _nrepos
    local _den _wc_k _wc_n _band_hdl _band_wc
    local _badts=0 _unparsed=0 _lines=0 _parsed=0
    if [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1; then
        _v1="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
                 'fromjson? // empty | select(.predicate_version != $pv) | .record_id' \
                 "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        # v2 records whose ts cannot be parsed are dropped by _episodes; report
        # the count so the exclusion is visible rather than a silent shortfall.
        # `.ts // ""` is required: `null | test(...)` is a jq RUNTIME error, and
        # jq then skips that input entirely — so a record with a missing ts was
        # excluded from episodes AND counted zero here, silently.
        _badts="$(_shadow_tsv 'select(((.ts // "") | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")) | not) | [.record_id]' \
                  | grep -c . )"
        # Lines jq could not parse at all. Reported rather than swallowed: a
        # single truncated line used to abort the whole read and silently
        # truncate the corpus.
        _lines="$(grep -c . "${SHADOW_LOG}" 2>/dev/null)"; [ -n "${_lines}" ] || _lines=0
        _parsed="$(jq -R -r 'fromjson? // empty | .record_id // "?"' "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        [ -n "${_parsed}" ] || _parsed=0
        _unparsed=$(( _lines - _parsed ))
        [ "${_unparsed}" -lt 0 ] && _unparsed=0
    fi
    while IFS="$(printf '\t')" read -r _eid _repo _branch _tok _ids; do
        [ -z "${_eid:-}" ] && continue
        _tot=$(( _tot + 1 ))
        _vc="$(_episode_verdict "${_ids}")"
        _v="$(printf '%s' "${_vc}" | sed -n 1p)"
        _c="$(printf '%s' "${_vc}" | sed -n 2p)"
        if [ "${_v}" = "unlabeled" ]; then _unlab=$(( _unlab + 1 )); continue; fi
        if [ "${_c}" = "agent" ];    then _agent=$(( _agent + 1 )); continue; fi
        _lab=$(( _lab + 1 ))
        # Newline-separated with an exact whole-line match. An ad-hoc "|"
        # delimiter false-matches any repo path containing a literal "|"
        # (filesystem-legal), undercounting _nrepos and so weakening the
        # diversity floor. Same delimiter-collision class as the episode key.
        if [ -z "${_repos}" ] || ! printf '%s\n' "${_repos}" | grep -qxF "${_repo}"; then
            _repos="${_repos}${_repo}
"
        fi
        case "${_v}" in
            false_block) _fb=$((  _fb  + 1 )) ;;
            unknown)     _unk=$(( _unk + 1 )) ;;
            true_catch)  _tc=$((  _tc  + 1 )) ;;
        esac
    done <<EOF
$(_episodes)
EOF
    _nrepos="$(printf '%s' "${_repos}" | grep -c . )"
    echo "IMPLEMENT shadow corpus — predicate_version ${REQUIRED_PREDICATE_VERSION}"
    printf '  episodes          %s\n' "${_tot}"
    printf '  adjudicated       %s   (human-claimed)\n' "${_lab}"
    printf '  agent-claimed     %s   <- excluded until a human re-confirms\n' "${_agent}"
    printf '  unadjudicated     %s\n' "${_unlab}"
    printf '  v1 records        %s   <- unpoolable, excluded\n' "${_v1}"
    [ "${_badts}" -gt 0 ] && \
        printf '  malformed ts      %s   <- excluded: unparseable timestamp, cannot be placed in an episode\n' "${_badts}"
    [ "${_unparsed}" -gt 0 ] && \
        printf '  unparseable lines %s   <- excluded: not valid JSON\n' "${_unparsed}"
    printf '  true_catch        %s\n' "${_tc}"
    printf '  false_block       %s\n' "${_fb}"
    printf '  unknown           %s   <- excluded from the headline rate\n' "${_unk}"
    printf '  repos             %s' "${_nrepos}"
    [ "${_nrepos}" -gt 0 ] && printf '   %s' "$(printf '%s' "${_repos}" | tr '\n' ' ')"
    printf '\n\n'
    _den=$(( _tc + _fb ))
    # The floor is applied to _den — the population the rate is actually computed
    # over — not to _lab. `unknown` episodes are adjudicated but excluded from
    # the headline rate, so gating on _lab would let 29 labeled episodes of which
    # 15 were unknown print a band over n=14, below the pre-registered floor.
    if [ "${_den}" -lt "${FLOOR_EPISODES}" ] || [ "${_nrepos}" -lt "${FLOOR_REPOS}" ]; then
        echo "  rate              insufficient data"
        printf '  need              %s adjudicated episodes (have %s) across >=%s repos (have %s)\n' \
               "${FLOOR_EPISODES}" "${_den}" "${FLOOR_REPOS}" "${_nrepos}"
        echo "  horizon           ~2026-09-08 (pre-registered 2026-07-28)"
    else
        _wc_k=$(( _fb + _unk )); _wc_n=$(( _den + _unk ))
        _band_hdl="$(_band "${_fb}" "${_den}")"
        _band_wc="$(_band "${_wc_k}" "${_wc_n}")"
        printf '  rate              %s/%s false blocks\n' "${_fb}" "${_den}"
        printf '  band              %s\n' "${_band_hdl}"
        printf '  worst case        %s/%s -> %s   (every unknown counted as a false block)\n' \
               "${_wc_k}" "${_wc_n}" "${_band_wc}"
    fi
    echo
    echo "  Informational only — NOT an enforcement decision. The push gate decides."
    echo "  Verdicts are HUMAN-CLAIMED, not human-verified."
    return 0
}

_usage() {
    cat <<'HELP'
shadow-adjudicate.sh — label IMPLEMENT-leg shadow records and report the rate.

  --next                       show the oldest unadjudicated record + how to label it
  <record_id> --verdict <v> --reason "<why>"
                               record a verdict: true_catch | false_block | unknown
  --status                     episodes, exclusions, rate, band, distance to floor

Diagnostic only. Exits 0 for observational commands. Never wire the output of
--status into an enforcement decision: the push gate is the only decider.
HELP
}

# Allow tests to source the helpers without executing a command. `return` is
# valid here only because this branch is reached solely via `. script --source-only`;
# the 2>/dev/null covers the executed case, where the case below runs instead.
case "${1:-}" in
    --source-only) return 0 2>/dev/null ;;
    --next)        cmd_next; exit $? ;;
    --status)      cmd_status; exit $? ;;
    -h|--help)     _usage; exit 0 ;;
    "")            _usage; exit 1 ;;
    *)
        _RID="$1"; shift
        _V=""; _R=""
        # Arity MUST be checked before `shift 2`: in bash 3.2 `shift 2` with
        # only one positional left FAILS and shifts NOTHING, so the loop never
        # terminates — `shadow-adjudicate.sh <id> --verdict` spun at 100% CPU
        # until killed. A truncated command line is an ordinary typo, and an
        # agent that types it wedges its shell.
        while [ $# -gt 0 ]; do
            case "$1" in
                --verdict)
                    [ $# -ge 2 ] || { echo "error: --verdict requires a value" >&2; exit 1; }
                    _V="$2"; shift 2 ;;
                --reason)
                    [ $# -ge 2 ] || { echo "error: --reason requires a value" >&2; exit 1; }
                    _R="$2"; shift 2 ;;
                *) echo "error: unexpected argument '$1'" >&2; exit 1 ;;
            esac
        done
        cmd_adjudicate "${_RID}" "${_V}" "${_R}"; exit $?
        ;;
esac
