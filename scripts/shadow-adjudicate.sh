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

_usage() {
    cat <<'HELP'
shadow-adjudicate.sh — label IMPLEMENT-leg shadow records and report the rate.

  --next                       show the oldest unadjudicated record + how to label it
  <record_id> --verdict <v> --reason "<why>"
                               record a verdict: true_catch | false_block | unknown
  --status                     episodes, exclusions, rate, band, distance to floor
  --rate-episodes              TSV of the would-block episodes --status rates over

Diagnostic only. Exits 0 for observational commands, except that
--rate-episodes exits 2 when the corpus exists but cannot be read: its stdout is
parsed, and no rows would read as no episodes. Never wire the output of
--status into an enforcement decision: the push gate is the only decider.
HELP
}

# --help is answered before the refusals below, as in the REVIEW reader (#416):
# how to call the script does not depend on the producer lib being loadable.
# Only as the first argument, so `--reason --help` stays a reason.
case "${1:-}" in -h|--help) _usage; exit 0 ;; esac

# Adjudicable predicate version. DERIVED FROM THE PRODUCER, not hardcoded: this
# constant and hooks/lib/implement-shadow.sh's IMPLEMENT_SHADOW_PREDICATE_VERSION
# are the two halves of one contract, and pinning them independently is a silent
# corpus blackout — measured when #219 bumped the producer to 3 while this stayed
# at 2: `--status` reported 0 episodes with the real records counted as
# "unpoolable", and `--verdict` refused every new record. That reads exactly like
# an empty corpus, which is the one state this instrument must never fake.
#
# There is NO literal fallback (#383). One used to stand in when the lib was
# absent, and it lagged the producer (3 against 6), so the fallback reproduced
# the very blackout described above. When the version cannot be derived the
# script REFUSES, exactly as it does below without shadow-corpus.sh.
REQUIRED_PREDICATE_VERSION=""
_sa_lib="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd)/hooks/lib/implement-shadow.sh"
if [ -f "${_sa_lib}" ]; then
    # Cleared first, so a value inherited from the caller's environment can
    # never stand in for one the lib failed to set (an early return, a
    # partial update).
    unset IMPLEMENT_SHADOW_PREDICATE_VERSION
    # shellcheck disable=SC1090
    . "${_sa_lib}" 2>/dev/null || true
    case "${IMPLEMENT_SHADOW_PREDICATE_VERSION:-}" in
        ''|*[!0-9]*) : ;;
        *) REQUIRED_PREDICATE_VERSION="${IMPLEMENT_SHADOW_PREDICATE_VERSION}" ;;
    esac
fi
if [ -z "${REQUIRED_PREDICATE_VERSION}" ]; then
    echo "error: cannot check: no valid IMPLEMENT_SHADOW_PREDICATE_VERSION from hooks/lib/implement-shadow.sh (looked at ${_sa_lib})." >&2
    echo "       Refusing to guess the adjudicable predicate version: a wrong guess reports an empty corpus." >&2
    exit 2
fi
# Shared corpus measurement, single-sourced with the REVIEW leg's adjudicator:
# the band rule, the ISO->epoch prelude and the episode grouping are ONE method
# serving two pre-registrations, and re-deriving them per leg is how this repo
# has repeatedly shipped two implementations of one rule that then drifted.
#
# REFUSE to run without it rather than falling back to a local copy. Every
# other lib-absent path in this repo degrades to a weaker but honest answer;
# here the degraded answer would be a NUMBER, and a measurement instrument that
# silently reports a rate computed by unknown means is worse than one that
# stops. The failure is loud and on stderr.
_sc_lib="$(cd "$(dirname "${BASH_SOURCE:-$0}")/.." 2>/dev/null && pwd)/hooks/lib/shadow-corpus.sh"
if [ -f "${_sc_lib}" ]; then
    # shellcheck disable=SC1090
    . "${_sc_lib}" 2>/dev/null || true
fi
if ! command -v shadow_band >/dev/null 2>&1 || ! command -v shadow_group_episodes >/dev/null 2>&1; then
    echo "error: hooks/lib/shadow-corpus.sh did not load (looked at ${_sc_lib})." >&2
    echo "       Refusing to report a rate computed by a local fallback." >&2
    exit 2
fi
# The plugin-version separator (#450; the rule and its reason are in
# shadow-corpus.sh). Refused, not skipped, when the lib does not supply it: a
# reader that silently pools across the separator is the state #450 was filed
# for. `null` when this reader's predicate is not the one the separator names.
if [ -z "${SHADOW_JQ_ACS:-}" ] || ! command -v shadow_acs_sep_json >/dev/null 2>&1; then
    echo "error: hooks/lib/shadow-corpus.sh supplies no acs_version separator (looked at ${_sc_lib})." >&2
    echo "       Refusing to report a rate pooled across it." >&2
    exit 2
fi
# The lib validates the separator and the leg's predicate constant and returns
# non-zero on either; this glob is a second, looser check (it would pass a
# four-number array, which the lib cannot emit).
ACS_SEP_JSON="$(shadow_acs_sep_json "${REQUIRED_PREDICATE_VERSION}" "${SHADOW_ACS_SEPARATOR_IMPLEMENT_PREDICATE:-}")" || ACS_SEP_JSON=""
case "${ACS_SEP_JSON}" in
    null|\[[0-9]*,[0-9]*,[0-9]*\]) ;;
    *) echo "error: cannot check: the acs_version separator did not resolve (separator '${SHADOW_ACS_SEPARATOR:-}', leg predicate '${SHADOW_ACS_SEPARATOR_IMPLEMENT_PREDICATE:-}')." >&2
       echo "       Refusing to report a rate pooled across it." >&2
       exit 2 ;;
esac

FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${IMPLEMENT_SHADOW_LOG:-$HOME/.claude/.push-implement-shadow.jsonl}"
ADJ_LOG="${IMPLEMENT_ADJUDICATION_LOG:-$HOME/.claude/.push-implement-adjudication.jsonl}"

# "Exists but cannot be read" is its own state (#453), as in the REVIEW reader
# (#416): `-f` says nothing about readability, and every read below discards
# jq's error, so an unreadable corpus read as an empty one and an unreadable
# sidecar as "no labels".
_unreadable() { [ -f "${1:-}" ] && [ ! -r "${1:-}" ]; }
_say_corpus_unreadable() {
    echo "ERROR: ${SHADOW_LOG} exists but is NOT READABLE."
    echo "  No claim is made about its contents. This is not an empty corpus."
}
_say_sidecar_unreadable() {
    echo "ERROR: the label sidecar ${ADJ_LOG} exists but is NOT READABLE."
    echo "  No label in it was read. This is not an unlabeled corpus."
}

# A ts the episode grouping can place. One definition for every jq read: the
# string check keeps a numeric ts from raising a jq error, which drops the
# record from whatever was counting it, and \A..\z because jq's `$` also
# matches before a trailing newline, which awk's does not.
_TS_OK_JQ='((.ts | type) == "string" and (.ts | test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z")))'

# What --next offers and the label command accepts: a placeable ts, a boolean
# would_block that is true, and no explicit advisory_emitted:false. The reasons
# are at cmd_next. One filter, because --next's closing count, its offer and
# the label command's refusal must describe the same records (#453, #454).
_OFFERABLE_JQ='select('"${_TS_OK_JQ}"')
              | select(has("would_block") and ((.would_block|type) == "boolean") and .would_block == true)
              | select((has("advisory_emitted") | not) or ((.advisory_emitted|type) != "boolean") or .advisory_emitted == true)'

# _band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, 0.10) <  alpha
#   ADVISORY-ONLY <=> P(X >= k | n, 0.20) <= alpha
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED (a pinned test).
_band() { shadow_band "${1:-0}" "${2:-0}"; }


# _shadow_tsv <jq-array-expr> — emit TSV for v2 records, tolerating malformed
# lines. `jq` ABORTS on the first parse error, so a single truncated line would
# silently truncate the whole corpus (and `2>/dev/null` hid it). `-R` + `fromjson?`
# skips only the bad line. Unparseable lines are counted and reported by --status.
#
# Records the acs_version separator excludes (#450) are not in this population:
# every consumer below — episodes, --next, the ts count — reads through here.
# They are counted by _presep_counts and reported by --status.
_shadow_tsv() {
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
       "${SHADOW_JQ_ACS} fromjson? // empty | select(.predicate_version == \$pv)
        | select(acs_class(\$sep) == \"ok\") | ${1} | @tsv" \
       "${SHADOW_LOG}" 2>/dev/null
}

# _presep_counts -> "<before> <unstamped>": records of the adjudicable predicate
# that the acs_version separator excludes, by cause.
_presep_counts() {
    [ -f "${SHADOW_LOG}" ] && [ -r "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || { printf '0 0'; return 0; }
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
       "${SHADOW_JQ_ACS} fromjson? // empty | select(.predicate_version == \$pv) | acs_class(\$sep)" \
       "${SHADOW_LOG}" 2>/dev/null \
    | awk '$0 == "before" { b++ } $0 == "unstamped" { u++ } END { printf "%d %d", b+0, u+0 }'
}

# _presep_total -> their sum, always a number.
_presep_total() {
    local _c _b _u
    _c="$(_presep_counts)"; _b="${_c% *}"; _u="${_c#* }"
    case "${_b}" in ''|*[!0-9]*) _b=0 ;; esac
    case "${_u}" in ''|*[!0-9]*) _u=0 ;; esac
    printf '%s' "$(( _b + _u ))"
}

# _presep_labelled -> "<only> <shared>": how many of those records the sidecar
# holds a label for, split as described at the end of the function.
# Such a label can no longer reach the rate, and a human false_block that stops
# counting lowers k, so it is announced by --status and never dropped silently.
# The orphan check cannot see it: the record is still in the corpus.
_presep_labelled() {
    [ -f "${ADJ_LOG}" ] && [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || { printf '0 0'; return 0; }
    { jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
         "${SHADOW_JQ_ACS} fromjson? // empty | select(type == \"object\") | select(.predicate_version == \$pv)
          | (if acs_class(\$sep) != \"ok\" then \"X\" else \"K\" end) as \$side
          | .record_id | strings | \$side + \"\t\" + @json" \
         "${SHADOW_LOG}" 2>/dev/null
      jq -R -r 'fromjson? // empty | select(type == "object") | .record_id | strings | "A\t" + @json' \
         "${ADJ_LOG}" 2>/dev/null | LC_ALL=C sort -u
    } | awk -F'\t' '$1 == "X" { x[$2] = 1; next } $1 == "K" { k[$2] = 1; next }
                    $1 == "A" && x[$2] { if (k[$2]) s++; else n++ }
                    END { printf "%d %d", n+0, s+0 }'
    # Ids travel as JSON text (@json), so a tab or newline inside one cannot
    # split a row or forge one.
    # Two numbers: labels on ids that only excluded records carry, then labels
    # on ids a record at or after the separator (a K row) carries too. The
    # second kind was counted with the first and called NOT counted, while the
    # rate read the same label against the other record (#453). It is reported
    # apart and never dropped: whether the rate counts it depends on that other
    # record, which may itself be outside the rate. No producer writes the pair.
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
    | shadow_group_episodes "${EPISODE_WINDOW_SEC}"
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

# Every read of the corpus and the sidecar is `-R` + `fromjson?` (#454), as in
# _shadow_tsv: a plain `jq` read stops at the first malformed line, so --next
# offered a record the label command then could not find, and a truncated
# sidecar line hid every label after it.
_record_field() { # _record_field <record_id> <field>
    jq -R -r --arg id "${1:-}" --arg f "${2:-}" \
       'fromjson? // empty | objects | select(.record_id == $id) | .[$f] // empty' "${SHADOW_LOG}" 2>/dev/null | head -1
}

cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _pv _ts _claim _cls
    case "${_verdict}" in
        true_catch|false_block|unknown) ;;
        *) echo "error: --verdict must be true_catch, false_block, or unknown" >&2; return 1;;
    esac
    [ -f "${SHADOW_LOG}" ] || { echo "error: no shadow log at ${SHADOW_LOG}" >&2; return 1; }
    # Otherwise the lookup below finds nothing and blames the record id.
    if _unreadable "${SHADOW_LOG}"; then _say_corpus_unreadable >&2; return 1; fi
    command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; return 1; }
    # Classified by jq, on the record's own types. Comparing the printed
    # predicate_version as a shell string accepted the JSON string "6", which
    # every other read here treats as another predicate (#454).
    _cls="$(jq -R -r --arg id "${_rid}" --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
               "${SHADOW_JQ_ACS} fromjson? // empty | objects | select(.record_id == \$id)
                | if .predicate_version != \$pv then \"pv\"
                  elif acs_class(\$sep) != \"ok\" then \"presep\"
                  elif ([${_OFFERABLE_JQ}] | length) == 0 then \"notoffer\"
                  else \"ok\" end" \
               "${SHADOW_LOG}" 2>/dev/null | head -1)"
    [ -z "${_cls}" ] && { echo "error: no record '${_rid}' in ${SHADOW_LOG}" >&2; return 1; }
    if [ "${_cls}" = "pv" ]; then
        _pv="$(jq -R -r --arg id "${_rid}" 'fromjson? // empty | objects | select(.record_id == $id) | .predicate_version | tojson' \
                  "${SHADOW_LOG}" 2>/dev/null | head -1)"
        echo "error: record '${_rid}' is predicate_version ${_pv}; only v${REQUIRED_PREDICATE_VERSION} is adjudicable." >&2
        echo "       Records of another predicate version measured a different subject and MUST NOT be pooled." >&2
        return 1
    fi
    # A record the separator excludes can never reach the rate, so a label on
    # it would be work the readout then ignores without saying why.
    if [ "${_cls}" = "presep" ]; then
        echo "error: record '${_rid}' carries an acs_version below ${SHADOW_ACS_SEPARATOR}, or none; it is not adjudicable." >&2
        echo "       #432 changed this leg's population at that plugin version (#435); earlier records MUST NOT be pooled." >&2
        return 1
    fi
    # The same records --next never offers. A label on one reaches no rate
    # episode, and --status withholds the rate over a human label it cannot
    # place, so accepting it here would let one mistyped id stop the readout.
    if [ "${_cls}" != "ok" ]; then
        echo "error: record '${_rid}' is not adjudicable: would_block is not true, the leg emitted no advisory, or its ts is unparseable." >&2
        echo "       --next never offers it, and a label on it could not reach the rate." >&2
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

# What a sidecar line must hold to be a label: a string record_id and one of
# the three verdicts. One definition, because the count of lines that are not
# labels and the rows the verdict is resolved from must not disagree (#454): an
# object with no verdict used to count as a label and, through latest-wins,
# erase an earlier false_block for its record.
_ADJ_LABEL_JQ='objects | select((.record_id | type) == "string")
               | select(.verdict == "true_catch" or .verdict == "false_block" or .verdict == "unknown")'

# A line that is not a label marks nothing adjudicated: --status does not count
# it, so --next must not stop offering the record over it.
_adjudicated_ids() {
    [ -f "${ADJ_LOG}" ] || return 0
    # As @tsv text, because cmd_next compares them with ids cut from @tsv
    # rows: printed raw, an id holding a backslash never matched and its
    # record was offered again after it was labelled.
    jq -R -r "fromjson? // empty | ${_ADJ_LABEL_JQ} | [.record_id] | @tsv" "${ADJ_LOG}" 2>/dev/null | sort -u
}

# _adj_unparsed -> sidecar lines that hold no label: unparseable, not an object,
# or an object that is not a label as defined above. Counted so a lost label is
# ANNOUNCED (#454); the REVIEW reader's function of the same name (#386).
# LC_ALL=C because in a UTF-8 locale a pattern does not match an invalid byte.
# A line of whitespace only is not a line: it lost nothing.
_adj_unparsed() {
    [ -f "${ADJ_LOG}" ] || { printf '0'; return 0; }
    local _t _p
    _t="$(LC_ALL=C grep -c '[^[:space:]]' "${ADJ_LOG}" 2>/dev/null | tr -d '[:space:]')"
    _p="$(jq -R -r "fromjson? | ${_ADJ_LABEL_JQ} | 1" "${ADJ_LOG}" 2>/dev/null | grep -c . | tr -d '[:space:]')"
    printf '%s' "$(( ${_t:-0} - ${_p:-0} ))"
}

# _adj_orphans -> labels naming a record_id this corpus does not hold, at any
# predicate version. The label command refuses an unknown id, so one appears
# only when the record was removed or edited after it was labelled, or the
# sidecar belongs to another corpus. Either way a labelled false_block may have
# left the count (#454). Ids travel as JSON text, as in _presep_labelled.
_adj_orphans() {
    [ -f "${ADJ_LOG}" ] && [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || { printf '0'; return 0; }
    { jq -R -r 'fromjson? | objects | .record_id | strings | "X\t" + @json' "${SHADOW_LOG}" 2>/dev/null
      jq -R -r "fromjson? | ${_ADJ_LABEL_JQ} | \"A\t\" + (.record_id | @json)" "${ADJ_LOG}" 2>/dev/null | LC_ALL=C sort -u
    } | awk -F'\t' '$1 == "X" { x[$2] = 1; next } $1 == "A" && !x[$2] { n++ } END { printf "%d", n+0 }'
}

# _labels_unplaced <placed ids, one per line> -> "<outside> <other-predicate>"
#
# The label half of the one rule --status withholds on (#454): every record a
# human has labelled is in an episode the rate counted, or a named row says why
# it is not, or no rate is printed. <placed ids> are the members of the
# would-block episodes --status found a label for, as _episodes printed them.
# A human-labelled record that is not among them is then one of:
#   absent from the corpus        -> the orphan row (_adj_orphans), withholds
#   of another predicate version  -> <other-predicate>, a row; the labels of a
#                                    retired predicate are expected, so no withhold
#   pre-separator                 -> the pre-separator labels row, no withhold
#   anything else                 -> <outside>, withholds
# <outside> is found by subtraction and names no cause, on purpose: an edited
# would_block, a ts that stopped parsing, an id the episode list cannot carry
# and whatever is found next all land there without a check written for each.
# "Human-labelled" is any valid label line claiming human, not only the latest;
# a human label that a later agent line replaced is _adj_superseded's.
# Ids are compared as the @tsv text _episodes carries, and as strings.
_labels_unplaced() {
    [ -f "${ADJ_LOG}" ] && [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || { printf '0 0'; return 0; }
    { printf '%s\n' "${1:-}" | awk 'length($0) > 0 { print "P\t" $0 }'
      jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
         "${SHADOW_JQ_ACS} fromjson? // empty | objects | select((.record_id | type) == \"string\")
          | [\"X\", .record_id,
             (if .predicate_version != \$pv then \"other\" elif acs_class(\$sep) != \"ok\" then \"presep\" else \"cur\" end)] | @tsv" \
         "${SHADOW_LOG}" 2>/dev/null
      jq -R -r "fromjson? // empty | ${_ADJ_LABEL_JQ} | select(.claimant == \"human\") | [\"H\", .record_id] | @tsv" \
         "${ADJ_LOG}" 2>/dev/null | LC_ALL=C sort -u
    } | awk -F'\t' '
        $1 == "P" { p[$2 ""] = 1; next }
        $1 == "X" { x[$2 ""] = 1; c[($2 "") SUBSEP $3] = 1; next }
        $1 == "H" {
            id = $2 ""
            if (id in p) next
            if (!(id in x)) next
            if ((id SUBSEP "cur") in c)    { out++; next }
            if ((id SUBSEP "presep") in c) next
            oth++
        }
        END { printf "%d %d", out + 0, oth + 0 }'
}

# _record_classes -> one line per record of the adjudicable population, by
# what the episode grouping does with it, read without the grouping's @tsv so
# a record that cannot print is still listed:
#   N           no id; the grouping skips it
#   B           an id, and a ts that does not parse
#   K<TAB><id>  an id and a placeable ts, so it belongs in an episode. The id
#               is written as the grouping carries it; one @tsv cannot print
#               (an array, an object) is written as a byte no id can equal.
_record_classes() {
    [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || return 0
    jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
       "${SHADOW_JQ_ACS} fromjson? // empty | objects | select(.predicate_version == \$pv)
        | select(acs_class(\$sep) == \"ok\")
        | if (.record_id == null or .record_id == \"\") then \"N\"
          elif (${_TS_OK_JQ} | not) then \"B\"
          else \"K\\t\" + (.record_id | if (type == \"array\" or type == \"object\") then \"\\u0001\" else ([.] | @tsv) end) end" \
       "${SHADOW_LOG}" 2>/dev/null
}

# _adj_superseded -> records whose latest label is not human-claimed while an
# earlier one was. The episode verdict takes the latest line per record, so
# that line replaced what the human said: alone in its episode the record
# moves to agent-claimed, and beside a human-labelled sibling the agent's
# verdict is counted as if a human gave it. Either way a human false_block can
# leave k on one agent command, so --status withholds until a human
# re-confirms the record.
#
# Only for a record of the adjudicable population. One of another predicate
# version or before the separator is in no rate episode, so nothing left k,
# its label already has a row that does not withhold, and the label command
# refuses it: counting it here withheld the rate with no way to clear it. A
# record the corpus does not hold is the orphan row's.
_adj_superseded() {
    [ -f "${ADJ_LOG}" ] && [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1 || { printf '0'; return 0; }
    { jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
         "${SHADOW_JQ_ACS} fromjson? // empty | objects | select((.record_id | type) == \"string\")
          | select(.predicate_version == \$pv) | select(acs_class(\$sep) == \"ok\") | [\"X\", .record_id] | @tsv" \
         "${SHADOW_LOG}" 2>/dev/null
      jq -R -r "fromjson? // empty | ${_ADJ_LABEL_JQ} | [\"L\", .record_id, (if .claimant == \"human\" then \"h\" else \"a\" end)] | @tsv" \
         "${ADJ_LOG}" 2>/dev/null
    } | awk -F'\t' '$1 == "X" { x[$2 ""] = 1; next }
                    $1 == "L" { id = $2 ""; if ($3 == "h") h[id] = 1; last[id] = $3 }
                    END { for (id in last) if (last[id] != "h" && (id in h) && (id in x)) n++; printf "%d", n + 0 }'
}

# cmd_next — oldest v2 record with no adjudication, plus how to label it.
# Read-only: never touches the sidecar. Always exits 0 (observational).
cmd_next() {
    local _seen _line
    [ -f "${SHADOW_LOG}" ] || { echo "no shadow log at ${SHADOW_LOG} — nothing outstanding."; return 0; }
    if _unreadable "${SHADOW_LOG}"; then _say_corpus_unreadable; return 0; fi
    command -v jq >/dev/null 2>&1 || { echo "jq required — cannot read the corpus."; return 0; }
    # With no labels read, the oldest record would be offered again whether or
    # not it is already labelled.
    if _unreadable "${ADJ_LOG}"; then
        _say_sidecar_unreadable
        echo "  Nothing is offered: which records are already labelled is not known."
        return 0
    fi
    _seen="$(_adjudicated_ids)"
    # Records whose ts is unparseable are skipped here too — --status can never
    # count them, so offering one for adjudication wastes the operator's time.
    # Field 11 flattens impl_evidence_detail (schema 3+) to "<leg>=<status> ..."
    # because @tsv rejects objects. An absent field yields the empty string,
    # which the renderer must report as "not recorded" rather than print blank —
    # a schema-2 record genuinely has no per-leg data, and that is different
    # from every leg having been checked.
    # Adjudicating an attested record is meaningless work — a verdict on it can
    # never inform a false-block rate — so it is never offered. Type-checked for
    # the same reason as _episode_wb: a JSON string "true" must not qualify.
    # An ADVISORY-SILENT record must not be queued either: the leg said nothing
    # about it, so it cannot contain a false block, and offering it spends
    # operator time on the one population that provably cannot inform the
    # measurement. Same reason attested records are not offered. The field
    # arrives in SCHEMA 4; predicate_version 5 is the separate thing that
    # excludes the older firing population. Conflating the two version counters
    # is how a later reader talks itself into the wrong exclusion, so they are
    # named apart here. Records written before schema 4 carry no such field and
    # fall through this filter unchanged.
    #
    # One filter, held in a variable, because the end-of-queue message below
    # counts the same population it was offered from (#453).
    local _offerable="${_OFFERABLE_JQ}"
    _line="$(_shadow_tsv "${_offerable}"'
              | [.record_id,.ts,.repo,.branch,.action,.diff_base,
                 (.impl_in_chain|tostring),(.material_source|tostring),
                 .impl_evidence_kind,.transcript_path,
                 ((.impl_evidence_detail | if type == "object" then . else {} end)
                  | to_entries
                  | map("\(.key)=\(.value)") | join(" ")),
                 (.schema_version // 0 | tostring)]' \
            | sort -t "$(printf '\t')" -k2,2 \
            | while IFS= read -r _row; do
                  _id="$(printf '%s' "${_row}" | cut -f1)"
                  [ -z "${_id}" ] && continue
                  if [ -n "${_seen}" ] && printf '%s\n' "${_seen}" | grep -qxF -e "${_id}"; then
                      continue
                  fi
                  printf '%s\n' "${_row}"; break
              done)"
    if [ -z "${_line}" ]; then
        # "no v2 records exist" and "all v2 records adjudicated" are different
        # states and must not share a message: the first means nothing is
        # countable yet, the second means the work is done. Conflating them
        # reports an empty corpus as complete.
        local _n_v2 _n_v1 _n_ps _n_off _n_not
        _n_v2="$(_shadow_tsv '[.record_id]' | grep -c . )"
        # What --next offers from, which is not every record (#453): "all N
        # adjudicated" over _n_v2 claimed attested, advisory-silent and
        # unplaceable records nobody was ever shown.
        _n_off="$(_shadow_tsv "${_offerable} | [.record_id]" | grep -c . )"
        case "${_n_v2}"  in ''|*[!0-9]*) _n_v2=0 ;; esac
        case "${_n_off}" in ''|*[!0-9]*) _n_off=0 ;; esac
        _n_not=$(( _n_v2 - _n_off ))
        [ "${_n_not}" -lt 0 ] && _n_not=0
        _n_ps="$(_presep_total)"
        _n_v1="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
                   'fromjson? // empty | objects | select(.predicate_version != $pv) | 1' \
                   "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        if [ "${_n_v2}" -eq 0 ]; then
            if [ "${_n_ps}" -gt 0 ]; then
                printf 'no v%s records at or after the acs_version separator — nothing is adjudicable.\n' "${REQUIRED_PREDICATE_VERSION}"
            else
                printf 'no v%s records yet — nothing is adjudicable.\n' "${REQUIRED_PREDICATE_VERSION}"
            fi
            [ "${_n_v1}" -gt 0 ] && \
                printf '  %s record(s) of another predicate version present, excluded: they measured a different subject and are unpoolable.\n' "${_n_v1}"
            [ "${_n_ps}" -gt 0 ] && \
                printf '  %s v%s record(s) present, excluded: acs_version below %s or absent (#435). See --status.\n' \
                       "${_n_ps}" "${REQUIRED_PREDICATE_VERSION}" "${SHADOW_ACS_SEPARATOR}"
            printf '  The corpus grows as the IMPLEMENT leg fires; see --status for the floor.\n'
            return 0
        fi
        if [ "${_n_off}" -eq 0 ]; then
            printf 'nothing to adjudicate — none of the %s v%s record(s) is offerable.\n' \
                   "${_n_v2}" "${REQUIRED_PREDICATE_VERSION}"
        else
            printf 'nothing outstanding — all %s offerable v%s record(s) are adjudicated.\n' \
                   "${_n_off}" "${REQUIRED_PREDICATE_VERSION}"
        fi
        [ "${_n_not}" -gt 0 ] && [ "${_n_off}" -gt 0 ] && \
            printf '  %s more v%s record(s) were never offered: would_block is not true, the leg emitted no advisory, or the ts is unparseable. See --status.\n' \
                   "${_n_not}" "${REQUIRED_PREDICATE_VERSION}"
        [ "${_n_not}" -gt 0 ] && [ "${_n_off}" -eq 0 ] && \
            printf '  They are never offered: would_block is not true, the leg emitted no advisory, or the ts is unparseable. See --status.\n'
        [ "${_n_ps}" -gt 0 ] && \
            printf '  %s more v%s record(s) are excluded and were never offered: acs_version below %s or absent (#435). See --status.\n' \
                   "${_n_ps}" "${REQUIRED_PREDICATE_VERSION}" "${SHADOW_ACS_SEPARATOR}"
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
        # A `cannot_check` leg is the tell that the advisory named the WRONG
        # remedy — the pre-registered false_block condition — rather than that
        # the push lacked implementation work. Surfaced here so the adjudicator
        # does not have to re-derive it from ~/.claude state that session-start
        # GC deletes after 7 days.
        # Branch on the RECORD.s schema_version ($12), never on $11 being empty.
        # implement-shadow.sh emits impl_evidence_detail:null for an omitted or
        # malformed detail (pinned by test-push-gate-implement-leg.sh), so a
        # genuine schema-3 record can arrive here with $11 empty — inferring
        # "schema <3" from that printed a false claim about the record.s own
        # schema.
        if ($11 == "") {
            if ($12 != "" && $12 + 0 >= 3)
                printf "  legs    not recorded — schema %s record carried no per-leg detail (omitted or malformed at write time)\n", $12
            else
                printf "  legs    not recorded (schema %s < 3) — per-leg outcome is unrecoverable for this record\n", ($12 == "" ? "?" : $12)
        }
        else {
            printf "  legs    %s\n", $11
            if ($11 ~ /cannot_check/)
                printf "          NOTE: a cannot_check leg means the check could not run. Weigh false_block:\n          the advisory names executing-plans, but the leg may have fired on infrastructure failure.\n"
        }
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
# _episode_wb <comma-separated record ids> -> yes | no | malformed
#
# Which episodes the false-block rate may be computed over. CLAUDE.md has always
# required `select(.would_block == true)`; this file had ZERO references to the
# field, so --status pooled attested non-blocks — records that BY CONSTRUCTION
# cannot be a false block — into the denominator, and --next queued them for
# adjudication. Measured on the live corpus: 17 records, 2 would-block, 15
# attested. A diluted denominator biases the rate toward CLEARING the deny-flip,
# which is the unsafe direction.
#
# The filter deliberately lives HERE and in the two callers, NOT inside
# _episodes(): that function is shared, and filtering there would erase the
# attested population from --status entirely — which is exactly what #169 added
# those records to make visible. Excluded from the rate, still reported.
#
# THE MIXED-EPISODE RULE IS "ANY", AND THAT IS THE POINT. An episode collapses
# records sharing (repo, branch, session_token) within the window, so it can in
# principle hold both kinds. "Any record would have blocked" is used because it
# is ANCHOR-INDEPENDENT: _episodes() anchors episode_id on the FIRST record by
# timestamp, so any rule that consulted only the anchor would classify the same
# episode differently depending on arrival order. Both orders are pinned by test.
# No mixed episode exists in the corpus today — this is a rule DEFINED in advance
# rather than discovered later, because an undefined rule is how this instrument
# came to be wrong in the first place.
#
# SECOND MEMBERSHIP FIELD, schema 4 (#245): `advisory_emitted`. `would_block`
# turned out not to mean what the rate needed, in two ways that had nothing to do
# with each other: on the gh-merge path it is passed as a hardcoded literal, so a
# merge whose subject never resolved asserted a block the leg would not perform;
# and a deletion-shaped command that lost its certification to an unaccountable
# pipeline segment produced a would_block record while shipping no content. Both
# are events the leg SAID NOTHING about, so neither could have blocked anyone,
# and both were adjudicable only as false blocks — moving the pre-registered rate
# for a reason unrelated to the predicate under test.
#
# Recording what the leg actually did retires that class instead of filtering one
# instance of it: the next premise-false shape drops out without another reader
# fix. An episode joins the rate only when a record both would have blocked AND
# produced an advisory. The exclusion is REPORTED, never silent.
#
# ONLY AN EXPLICIT `false` EXCLUDES, and the asymmetry with `would_block` is
# deliberate rather than an oversight. For `would_block`, an unknown folded into
# the population would DILUTE the denominator, so it is malformed. Here the
# directions are reversed: excluding an episode is what biases the rate toward
# CLEARING the deny-flip, so an absent or malformed `advisory_emitted` must
# resolve to "assume the leg spoke" and stay in. A producer bug that drops the
# field then costs a possibly-spurious episode in the denominator — the safe
# direction — instead of silently shrinking the population the bar is measured
# over. Records written before schema 4 carry no such field and are unaffected.
#
# Membership is read from `would_block` and `advisory_emitted` ONLY, never
# inferred from `impl_evidence_kind`. The two correlate perfectly in today's data, which is
# precisely the trap: that field is format-frozen and describes EVIDENCE, not
# rate membership, and coupling them would re-create the implicit contract that
# broke this reader.
#
# A missing or non-boolean value is "malformed", never silently "no": folding an
# unknown into the population that looks safe is the same bias in miniature.
_episode_wb() {
    local _ids="${1:-}" _id _v _sawtrue=false _sawbad=false _sawsilent=false
    [ -n "${_ids}" ] && [ -f "${SHADOW_LOG}" ] || { echo malformed; return 0; }
    command -v jq >/dev/null 2>&1 || { echo malformed; return 0; }
    # A here-document, not `for _id in ${_ids}`: an unquoted expansion globs,
    # so an id of `*` became the file names in the working directory.
    while IFS= read -r _id; do
        [ -n "${_id}" ] || continue
        # Type-checked, not `tostring`: a JSON *string* "true" would otherwise be
        # indistinguishable from the boolean and would silently join the rate
        # population.
        # Emits one of: true | false | SILENT | MALFORMED.
        # SILENT = would_block true but the leg emitted no advisory, i.e. an
        # event nobody could have been blocked by. Reported separately rather
        # than folded into `false`, which means "attestation satisfied the leg" —
        # a different state that #169 records deliberately.
        # Looked up among the records the episodes are built from, and no
        # others: by id alone, a pre-separator or other-predicate record that
        # shared the id and came first in the file lent ITS would_block to the
        # episode, so an excluded record could put a non-blocking episode into
        # the rate (#453).
        _v="$(jq -R -r --arg id "${_id}" --argjson pv "${REQUIRED_PREDICATE_VERSION}" --argjson sep "${ACS_SEP_JSON}" \
             "${SHADOW_JQ_ACS}"' fromjson? // empty | objects | select(.record_id == $id)
              | select(.predicate_version == $pv) | select(acs_class($sep) == "ok")
              | if (has("would_block") and ((.would_block|type) == "boolean")) | not
                then "MALFORMED"
                elif (.would_block == false) then "false"
                elif (has("advisory_emitted") and ((.advisory_emitted|type) == "boolean")
                      and .advisory_emitted == false) then "SILENT"
                else "true" end' \
             "${SHADOW_LOG}" 2>/dev/null | head -1)"
        case "${_v}" in
            true)   _sawtrue=true ;;
            false)  ;;
            SILENT) _sawsilent=true ;;
            *)      _sawbad=true ;;
        esac
    done <<EOF_WB
$(printf '%s' "${_ids}" | tr ',' '\n')
EOF_WB
    # Order is UNCHANGED from before the silent arm existed: any would-block wins
    # (the anchor-independent ANY rule), then malformed. `silent` is appended
    # LAST so an episode holding both a real would-block and a silent record
    # still counts — narrowing that would quietly drop episodes the rate is
    # entitled to. Only an episode whose would-block records are ALL silent is
    # excluded, which is exactly the premise-false population.
    if [ "${_sawtrue}"   = true ]; then echo yes;       return 0; fi
    if [ "${_sawbad}"    = true ]; then echo malformed; return 0; fi
    if [ "${_sawsilent}" = true ]; then echo silent;    return 0; fi
    echo no
}

_episode_verdict() {
    local _ids="${1:-}" _v="unlabeled" _claim="agent" _has_human=0 _id _rows
    local _latest _rv _rc
    if [ ! -f "${ADJ_LOG}" ]; then printf 'unlabeled\nagent\n'; return; fi
    # A claimant that is not a string is no human claim. Left as it was, @tsv
    # failed on an array or object and the whole label vanished from here while
    # _adj_unparsed still counted it as one.
    _rows="$(jq -R -r "fromjson? // empty | ${_ADJ_LABEL_JQ}
                       | [.record_id,.verdict,(.claimant | if type == \"string\" then . else \"\" end)] | @tsv" "${ADJ_LOG}" 2>/dev/null)"
    # Split on the comma only (an id may hold a space), with no globbing.
    while IFS= read -r _id; do
        [ -n "${_id}" ] || continue
        # LATEST adjudication per record wins. The sidecar is append-only, so the
        # last matching row is the most recent one. Folding over ALL rows instead
        # makes a correction a silent no-op: re-adjudicating a fat-fingered
        # false_block to true_catch would print success while the earlier verdict
        # continued to win, permanently poisoning a rate that gates a deny-flip.
        # Claimant comes from the same latest row, so an agent overwriting a
        # human's label reverts a one-record episode to excluded. In a larger
        # episode a sibling's human label keeps it counted with the agent's
        # verdict in it, which is why --status withholds on _adj_superseded.
        # Compared as STRINGS, and the id passed through ENVIRON: awk compares
        # two numeric-looking values as numbers (a label for "1e2" answered for
        # the record "100"), and -v processes backslash escapes.
        _latest="$(printf '%s\n' "${_rows}" \
                   | _SA_ID="${_id}" awk -F'\t' '($1 "") == (ENVIRON["_SA_ID"] "") { v = $2; c = $3 }
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
    done <<EOF_EV
$(printf '%s' "${_ids}" | tr ',' '\n')
EOF_EV
    [ "${_has_human}" -eq 1 ] && _claim="human"
    printf '%s\n%s\n' "${_v}" "${_claim}"
}

# cmd_status — episode-level readout. Observational; always exits 0.
cmd_status() {
    local _tot=0 _lab=0 _fb=0 _tc=0 _unk=0 _agent=0 _unlab=0 _v1=0
    local _wbep=0 _attep=0 _malwb=0 _silep=0 _wb
    local _repos="" _eid _repo _branch _tok _ids _vc _v _c _nrepos
    local _den _wc_k _wc_n _band_hdl _band_wc
    local _badts=0 _unparsed=0 _lines=0 _parsed=0 _ps _psb=0 _psu=0 _psl=0 _pss=0 _adjbad=0 _orph=0 _uncount=0
    local _eps="" _placed="" _rc _noid=0 _epids="" _unplaced=0 _lu _lout=0 _loth=0 _sup=0
    # Before any count (#453). The sidecar too: every row below the episode
    # total is read from labels, and with none read a labelled false_block
    # printed as unadjudicated.
    if _unreadable "${SHADOW_LOG}" || _unreadable "${ADJ_LOG}"; then
        echo "IMPLEMENT shadow corpus — predicate_version ${REQUIRED_PREDICATE_VERSION}"
        if _unreadable "${SHADOW_LOG}"; then _say_corpus_unreadable; fi
        if _unreadable "${ADJ_LOG}"; then _say_sidecar_unreadable; fi
        echo "  No counts and no rate are reported."
        return 0
    fi
    _ps="$(_presep_counts)"; _psb="${_ps% *}"; _psu="${_ps#* }"
    case "${_psb}" in ''|*[!0-9]*) _psb=0 ;; esac
    case "${_psu}" in ''|*[!0-9]*) _psu=0 ;; esac
    if [ -f "${SHADOW_LOG}" ] && command -v jq >/dev/null 2>&1; then
        _v1="$(jq -R -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" \
                 'fromjson? // empty | objects | select(.predicate_version != $pv) | 1' \
                 "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        # v2 records whose ts cannot be parsed are dropped by _episodes; report
        # the count so the exclusion is visible rather than a silent shortfall.
        # The type check in _TS_OK_JQ is required: `test` on a ts that is not
        # a string is a jq RUNTIME error, and jq then skips that input entirely
        # — so a record with a missing or numeric ts was excluded from episodes
        # AND counted zero here, silently. `[1]`, never the id: see below.
        _badts="$(_shadow_tsv "select(${_TS_OK_JQ} | not) | [1]" | grep -c . )"
        # Lines jq could not parse at all. Reported rather than swallowed: a
        # single truncated line used to abort the whole read and silently
        # truncate the corpus.
        # LC_ALL=C: in a UTF-8 locale a pattern does not match an invalid byte,
        # so a line of corrupt bytes was not a line at all. A whitespace-only
        # line is not counted: nothing was on it. One `1` per object, never
        # the id: an id holding a newline printed as two lines and cancelled an
        # unparseable one, and an empty id printed as none (#454).
        _lines="$(LC_ALL=C grep -c '[^[:space:]]' "${SHADOW_LOG}" 2>/dev/null)"; [ -n "${_lines}" ] || _lines=0
        _parsed="$(jq -R -r 'fromjson? | objects | 1' "${SHADOW_LOG}" 2>/dev/null | grep -c . )"
        [ -n "${_parsed}" ] || _parsed=0
        # These two feed the decision to print a rate, so a count that is not
        # a number is read as one lost record, never as none.
        case "${_lines}${_parsed}" in *[!0-9]*) _unparsed=1 ;; *) _unparsed=$(( _lines - _parsed )) ;; esac
        [ "${_unparsed}" -lt 0 ] && _unparsed=0
        case "${_badts}" in ''|*[!0-9]*) _badts=1 ;; esac
    fi
    # Re-split on \x1f (US), NOT tab. Tab is an IFS *whitespace* character, so
    # `IFS=$'\t' read` collapses consecutive tabs: an empty `branch` shifted
    # session_token into branch and left _ids EMPTY, so _episode_verdict ""
    # returned unlabeled and the episode was silently counted unadjudicated —
    # a human's labelling work would vanish from the count. \x1f is not IFS
    # whitespace, so empty fields survive. (This is the repo's declared field
    # separator; _episodes still emits tab for its own consumers.)
    # The heredoc keeps the loop in THIS shell so the counters survive.
    _eps="$(_episodes)"
    while IFS="$(printf '\037')" read -r _eid _repo _branch _tok _ids; do
        [ -z "${_eid:-}" ] && continue
        _tot=$(( _tot + 1 ))
        # Rate membership first. Everything below this point — adjudicated,
        # agent-claimed, the verdict counts AND the repo-diversity set — is
        # would-block-only. The diversity floor matters as much as the rate: if
        # attestation episodes could satisfy >=2 repos, the corpus would clear
        # the diversity requirement with zero false-block evidence spanning
        # repos, which is the same dilution one level up.
        _epids="${_epids}$(printf '%s' "${_ids}" | tr ',' '\n')
"
        _wb="$(_episode_wb "${_ids}")"
        case "${_wb}" in
            yes)    _wbep=$(( _wbep + 1 )) ;;
            no)     _attep=$(( _attep + 1 )); continue ;;
            silent) _silep=$(( _silep + 1 )); continue ;;
            *)      _malwb=$(( _malwb + 1 )); continue ;;
        esac
        _vc="$(_episode_verdict "${_ids}")"
        _v="$(printf '%s' "${_vc}" | sed -n 1p)"
        _c="$(printf '%s' "${_vc}" | sed -n 2p)"
        if [ "${_v}" = "unlabeled" ]; then _unlab=$(( _unlab + 1 )); continue; fi
        # The records a label was looked up for and found, human or agent:
        # what _labels_unplaced checks the sidecar against.
        _placed="${_placed}$(printf '%s' "${_ids}" | tr ',' '\n')
"
        if [ "${_c}" = "agent" ];    then _agent=$(( _agent + 1 )); continue; fi
        _lab=$(( _lab + 1 ))
        # Newline-separated with an exact whole-line match. An ad-hoc "|"
        # delimiter false-matches any repo path containing a literal "|"
        # (filesystem-legal), undercounting _nrepos and so weakening the
        # diversity floor. Same delimiter-collision class as the episode key.
        if [ -z "${_repos}" ] || ! printf '%s\n' "${_repos}" | grep -qxF -e "${_repo}"; then
            _repos="${_repos}${_repo}
"
        fi
        case "${_v}" in
            false_block) _fb=$((  _fb  + 1 )) ;;
            unknown)     _unk=$(( _unk + 1 )) ;;
            true_catch)  _tc=$((  _tc  + 1 )) ;;
        esac
    done <<EOF
$(printf '%s\n' "${_eps}" | tr '\t' '\037')
EOF
    # The record half of the rule: the records with an id and a placeable ts
    # are exactly the records the episodes hold. Compared id by id, both ways,
    # because two totals can agree by accident: one record dropped (an object
    # where a string belongs fails @tsv) beside one id the comma-joined list
    # split in two. Anything on one side only has no row of its own.
    _rc="$(_record_classes)"
    _noid="$(printf '%s\n' "${_rc}" | grep -c '^N$')"
    case "${_noid}" in ''|*[!0-9]*) _noid=0 ;; esac
    _unplaced="$( { printf '%s\n' "${_rc}" | awk -F'\t' '$1 == "K" { print "K\t" substr($0, 3) }'
                    printf '%s' "${_epids}" | awk 'length($0) > 0 { print "E\t" $0 }'
                  } | awk -F'\t' '{ id = substr($0, 3); if ($1 == "K") k[id]++; else e[id]++ }
                                  END { for (id in k) { d = k[id] - e[id]; n += (d < 0 ? -d : d) }
                                        for (id in e) if (!(id in k)) n += e[id]
                                        printf "%d", n + 0 }')"
    case "${_unplaced}" in ''|*[!0-9]*) _unplaced=1 ;; esac
    _sup="$(_adj_superseded)"
    case "${_sup}" in ''|*[!0-9]*) _sup=1 ;; esac
    _lu="$(_labels_unplaced "${_placed}")"; _lout="${_lu% *}"; _loth="${_lu#* }"
    case "${_lout}" in ''|*[!0-9]*) _lout=1 ;; esac
    case "${_loth}" in ''|*[!0-9]*) _loth=0 ;; esac
    _nrepos="$(printf '%s' "${_repos}" | grep -c . )"
    echo "IMPLEMENT shadow corpus — predicate_version ${REQUIRED_PREDICATE_VERSION}"
    printf '  episodes          %s\n' "${_tot}"
    printf '  would-block       %s   <- the ONLY population the rate is computed over\n' "${_wbep}"
    printf '  attestation-only  %s   <- observation (#169): attestation satisfied the leg; cannot contain a false block\n' "${_attep}"
    [ "${_silep}" -gt 0 ] && \
        printf '  advisory-silent   %s   <- excluded: the leg emitted no advisory, so nobody could have been blocked; the premise was never established\n' "${_silep}"
    [ "${_malwb}" -gt 0 ] && \
        printf '  malformed would_block %s   <- excluded: field missing or not boolean; NOT counted as attestation-only\n' "${_malwb}"
    printf '  adjudicated       %s   (human-claimed)\n' "${_lab}"
    printf '  agent-claimed     %s   <- excluded until a human re-confirms\n' "${_agent}"
    printf '  unadjudicated     %s\n' "${_unlab}"
    printf '  other-predicate   %s   <- unpoolable, excluded\n' "${_v1}"
    [ "${_loth}" -gt 0 ] && \
        printf '  other-predicate labels %s   <- NOT counted: that many of those records carry a human label\n' "${_loth}"
    # Never silent (#450): these are v-current records, so without this row a
    # corpus that is mostly pre-separator reads as a nearly empty one.
    if [ $(( _psb + _psu )) -gt 0 ]; then
        printf '  pre-separator     %s   <- excluded, in none of the counts above: acs_version below %s (%s) or no usable acs_version (%s); #432 changed this population at that plugin version (#435)\n' \
               "$(( _psb + _psu ))" "${SHADOW_ACS_SEPARATOR}" "${_psb}" "${_psu}"
        _psl="$(_presep_labelled)"; _pss="${_psl#* }"; _psl="${_psl% *}"
        case "${_psl}" in ''|*[!0-9]*) _psl=0 ;; esac
        case "${_pss}" in ''|*[!0-9]*) _pss=0 ;; esac
        [ "${_psl}" -gt 0 ] && \
            printf '  pre-separator labels %s   <- NOT counted: the sidecar holds a label for that many of those records\n' "${_psl}"
        [ "${_pss}" -gt 0 ] && \
            printf '  shared-id labels  %s   <- a label for an id that a pre-separator record and a record at or after the separator both carry; only the latter can place it in the rate\n' "${_pss}"
    fi
    [ "${_badts}" -gt 0 ] && \
        printf '  malformed ts      %s   <- excluded: unparseable timestamp, cannot be placed in an episode\n' "${_badts}"
    [ "${_unparsed}" -gt 0 ] && \
        printf '  unparseable lines %s   <- excluded: not valid JSON\n' "${_unparsed}"
    [ "${_noid}" -gt 0 ] && \
        printf '  no record_id      %s   <- excluded: cannot be addressed, so cannot be labelled\n' "${_noid}"
    [ "${_unplaced}" -gt 0 ] && \
        printf '  unplaced records  %s   <- that many record(s) with an id and a parseable ts are in no episode, or episode members match no such record; no row above says why\n' "${_unplaced}"
    # A count that cannot be read is treated as a lost line, never as none.
    _adjbad="$(_adj_unparsed)"
    case "${_adjbad}" in ''|*[!0-9]*) _adjbad=1 ;; esac
    [ "${_adjbad}" -gt 0 ] && \
        printf '  unparseable labels %s   <- sidecar line(s) holding no readable label; what they said is lost\n' "${_adjbad}"
    _orph="$(_adj_orphans)"
    case "${_orph}" in ''|*[!0-9]*) _orph=1 ;; esac
    [ "${_orph}" -gt 0 ] && \
        printf '  orphan labels     %s   <- the sidecar labels that many record(s) this corpus does not hold\n' "${_orph}"
    [ "${_sup}" -gt 0 ] && \
        printf '  superseded human labels %s   <- a later line that is not human-claimed replaced a human label for that many record(s); withheld until a human labels each again\n' "${_sup}"
    [ "${_lout}" -gt 0 ] && \
        printf '  labels outside the rate %s   <- that many human-labelled record(s) are in no episode the rate counted, and no row above says why\n' "${_lout}"
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
    # A lost sidecar line may have been a false_block, and a corpus record that
    # cannot be placed (or whose episode left the rate on a malformed
    # would_block, or that is gone while its label remains) leaves the
    # denominator with its label unseen. Each lowers the rate toward clearing
    # the flip, so no rate is printed over one (#454). The REVIEW reader blocks
    # its floor on the first three counts and only warns about orphans; here an
    # orphan withholds too, because this reader has one corpus per sidecar.
    #
    # The last two terms are the rule the first five are instances of: a record
    # a human labelled that the rate did not count and no row explains, and a
    # record no episode and no row accounts for. They are found by subtraction,
    # so an input nobody listed withholds the rate as well. The last term is
    # a human label an agent's later line replaced (_adj_superseded).
    _uncount=$(( _adjbad + _orph + _unparsed + _badts + _malwb + _lout + _unplaced + _sup ))
    if [ "${_uncount}" -gt 0 ]; then
        printf '  rate              cannot check — %s label(s), line(s) or record(s) above could not be placed (unparseable labels %s, orphan labels %s, unparseable lines %s, malformed ts %s, malformed would_block %s, labels outside the rate %s, unplaced records %s, superseded human labels %s)\n' \
               "${_uncount}" "${_adjbad}" "${_orph}" "${_unparsed}" "${_badts}" "${_malwb}" "${_lout}" "${_unplaced}" "${_sup}"
        echo "  need              each one accounted for: any of them may be a lost false_block"
    elif [ "${_den}" -lt "${FLOOR_EPISODES}" ] || [ "${_nrepos}" -lt "${FLOOR_REPOS}" ]; then
        echo "  rate              insufficient data"
        printf '  need              %s adjudicated episodes (have %s) across >=%s repos (have %s)\n' \
               "${FLOOR_EPISODES}" "${_den}" "${FLOOR_REPOS}" "${_nrepos}"
        # The registration's own words. The 2026-09-08 date printed here until
        # 2026-11-20 was withdrawn by the re-registration of 2026-08-29 ("No new
        # horizon date is committed"), so the readout was quoting a deadline
        # the window does not have.
        echo "  horizon           unknown, pending re-estimate (re-registered 2026-08-29; no date is committed)"
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

# cmd_rate_episodes — the rate population, one tab-separated _episodes row per
# episode whose _episode_wb is "yes" (the same membership cmd_status counts).
# stdout carries ONLY those rows; consumers parse it. Re-split on \x1f as
# cmd_status does, then re-joined with tabs: a tab IFS read would collapse an
# empty branch.
cmd_rate_episodes() {
    local _eid _repo _branch _tok _ids _row
    # No rows would read as no episodes to whatever parses this (#453), so the
    # one command with a parsed stdout says it on stderr and exits non-zero.
    if _unreadable "${SHADOW_LOG}"; then _say_corpus_unreadable >&2; return 2; fi
    while IFS="$(printf '\037')" read -r _eid _repo _branch _tok _ids; do
        [ -z "${_eid:-}" ] && continue
        [ "$(_episode_wb "${_ids}")" = "yes" ] || continue
        printf '%s\t%s\t%s\t%s\t%s\n' "${_eid}" "${_repo}" "${_branch}" "${_tok}" "${_ids}"
    done <<EOF_EPS
$(_episodes | tr '\t' '\037')
EOF_EPS
    return 0
}

# Allow tests to source the helpers without executing a command. `return` is
# valid here only because this branch is reached solely via `. script --source-only`;
# the 2>/dev/null covers the executed case, where the case below runs instead.
case "${1:-}" in
    --source-only) return 0 2>/dev/null ;;
    --next)        cmd_next; exit $? ;;
    --status)      cmd_status; exit $? ;;
    --rate-episodes) cmd_rate_episodes; exit $? ;;
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
