#!/bin/bash
# phase-gate-backtest.sh — replay Skill-invocation sequences from local
# Claude Code transcripts and report where the phase gates WOULD have fired.
# Usage: phase-gate-backtest.sh [transcripts-dir]
# Output: one line per would-have-denied event + a summary; classification
# of true-catch vs false-block is a HUMAN step (small n expected).
# Pre-registered thresholds (discovery brief 2026-07-16): deny ships <10% FB;
# 10-20% narrowed; >20% advisory-only. Not a hook: plain exit codes, no JSON.
#
# ADVISORY-ONLY — replay error is BIDIRECTIONAL (codex #7):
#   (a) replay treats any prior in-session tool_use as evidence, but the live
#       hook ignores ERRORED Skill returns — replay can UNDERCOUNT live denies.
#   (b) branch-ledger/attestation state at the time is invisible to replay —
#       replay can OVERCOUNT (a live push may have been allowed via ledger
#       coverage that this script cannot see).
#   (c) the hardcoded canonical chain omits conditional members
#       (product-discovery).
# Every DENY line below is human-classified before any rate is computed,
# which bounds all three simplifications above.
set -u

DIR="${1:-$HOME/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills}"
CHAIN="brainstorming writing-plans executing-plans subagent-driven-development requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch"

command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 1; }
[ -d "$DIR" ] || { echo "no transcript dir: $DIR" >&2; exit 1; }

_idx() {  # chain index of bare skill name, -1 if absent; SDD and executing-plans share slot 2
    local s="$1" i=0 c
    case "$s" in executing-plans|subagent-driven-development|agent-team-execution) echo 2; return;; esac
    for c in brainstorming writing-plans _impl requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch; do
        [ "$c" = "$s" ] && { echo "$i"; return; }
        i=$(( i + 1 ))
    done
    echo -1
}

TOTAL_SESSIONS=0; TOTAL_INVOCATIONS=0; DENIES=0
for f in "$DIR"/*.jsonl; do
    [ -f "$f" ] || continue
    TOTAL_SESSIONS=$(( TOTAL_SESSIONS + 1 ))
    # Ordered bare skill names invoked via the Skill tool in this session.
    _SEQ="$(jq -r 'select(.type=="assistant")
        | .message.content[]? | select(.type=="tool_use" and .name=="Skill")
        | (.input.skill // .input.name // "") | split(":") | last' "$f" 2>/dev/null)"
    [ -z "$_SEQ" ] && continue
    _SEEN=" "   # bare names with evidence so far (invocation = evidence in replay)
    while IFS= read -r s; do
        [ -z "$s" ] && continue
        TOTAL_INVOCATIONS=$(( TOTAL_INVOCATIONS + 1 ))
        i="$(_idx "$s")"
        if [ "$i" -gt 0 ]; then
            j=0
            for c in brainstorming writing-plans _impl requesting-code-review verification-before-completion openspec-ship finishing-a-development-branch; do
                [ "$j" -ge "$i" ] && break
                if [ "$c" != "_impl" ]; then
                    case "$_SEEN" in *" $c "*) : ;; *)
                        DENIES=$(( DENIES + 1 ))
                        printf 'DENY session=%s skill=%s missing=%s\n' "$(basename "$f" .jsonl)" "$s" "$c"
                        ;;
                    esac
                else
                    case "$_SEEN" in *" executing-plans "*|*" subagent-driven-development "*|*" agent-team-execution "*) : ;; *)
                        [ "$i" -gt 2 ] && { DENIES=$(( DENIES + 1 )); printf 'DENY session=%s skill=%s missing=implementation-step\n' "$(basename "$f" .jsonl)" "$s"; }
                        ;;
                    esac
                fi
                j=$(( j + 1 ))
            done
        fi
        _SEEN="${_SEEN}${s} "
    done <<EOF_SEQ
$_SEQ
EOF_SEQ
done
printf -- '---\nsessions=%s skill_invocations=%s would_have_denied=%s\n' "$TOTAL_SESSIONS" "$TOTAL_INVOCATIONS" "$DENIES"
printf 'Classify each DENY above as true-catch or false-block. Thresholds: <10%%FB deny | 10-20%% narrow | >20%% advisory.\n'
printf 'ADVISORY-ONLY — replay error is BIDIRECTIONAL: errored Skill returns counted as evidence here but not by the live hook (undercounts); ledger/attestation state is invisible to replay (overcounts); hardcoded chain omits conditional members (product-discovery). Human-classify every DENY before computing any rate.\n'
exit 0
