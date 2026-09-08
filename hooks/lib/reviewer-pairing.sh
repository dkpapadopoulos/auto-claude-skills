#!/usr/bin/env bash
# reviewer-pairing.sh — the session-scoped join between a reviewer subagent's
# DISPATCH and its COMPLETION.
#
# Two hooks observe two halves of one fact and neither can credit alone:
#
#   reviewer-evidence-hook.sh   PostToolUse ^(Task|Agent)$   classifies (owns the
#                                                            measured predicate)
#   reviewer-completion-hook.sh SubagentStop                 observes completion
#
# NEITHER IS GUARANTEED TO RUN FIRST. Measured end-to-end against the real hooks
# on Claude Code CLI 2.1.236:
#
#   background dispatch : DISPATCH fires 1.44s BEFORE completion
#   foreground dispatch : COMPLETION fires ~30ms BEFORE dispatch (3 of 3)
#
# So the join is SYMMETRIC: each hook writes its own half first, then looks for
# the other, and whichever runs second records the milestone. A one-directional
# "dispatch writes, completion reads" design is a systematic no-op for foreground
# dispatches — that was the first cut, and it recorded `reviewer-ran` with no
# `reviewer-returned` for a foreground reviewer.
#
# FORMAT CHANGE SAFETY: both halves store "<agent_id> <ledger_key>". A record
# written in the earlier one-field format has an empty second field, so the key
# readers return nothing and the join degrades to a MISS — never to a false
# credit, since an empty key can never compare equal to a real one. That is the
# correct direction for a format change inside a live-session state family.
#
# The file format and the key derivation live HERE and only here, so the writer
# and the reader cannot drift — the recurring failure class behind
# #51/#97/#122/#131/#133/#151/#156.
#
# Sourced by HOOKS only (both are `#!/bin/bash`), never from a model Bash turn,
# so the zsh-compatibility constraints that bind `session-token.sh` and
# `phase-attest.sh` do not apply here. If that ever changes, re-read CLAUDE.md's
# "the Bash tool is NOT bash" gotcha before touching this file.
#
# Every function is fail-open and best-effort: on any error the pairing simply
# does not resolve, the milestone is not recorded, and the caller continues.
# Under-recording is the accepted direction; a false credit is not.
#
# Bash 3.2 compatible.

# _reviewer_pairing_file <kind> <session_id> — path of a session-scoped pairing
# file, or nothing (return 1).
#
# The session id becomes a filename component, so it is validated as a single
# path-safe segment rather than trusted: the payload is harness-supplied, but a
# recorder must not be the component that turns a surprising value into a read
# or a write outside ~/.claude.
#
# Naming mirrors _SESSION_TOKEN ("session-<id>") because `session_id` IS the
# transcript basename, so session-start's GC excludes the live session with a
# plain `! -name ".skill-reviewer-<kind>-${_SESSION_TOKEN}"` match. Both names
# must stay in that GC block's glob list.
_reviewer_pairing_file() {
    local kind="${1:-}" sid="${2:-}"
    [ -n "$kind" ] && [ -n "$sid" ] || return 1
    case "$kind" in dispatch|complete) ;; *) return 1 ;; esac
    case "$sid" in
        *[!A-Za-z0-9._-]*|.|..) return 1 ;;
    esac
    printf '%s' "${HOME}/.claude/.skill-reviewer-${kind}-session-${sid}"
}

# _reviewer_pairing_append <file> <line> — bounded, race-tolerant append.
#
# EXHAUSTING THE CEILING SILENCES THIS WHOLE FAMILY for the rest of the session,
# including reviewer_pairing_note_mismatch — so the diagnostic that exists to keep
# a refused credit visible is itself suppressed by the same condition, and the
# failure is ORDER-ASYMMETRIC (the background order keeps working off the other
# file). The completion file records EVERY subagent completion, not only
# reviewers, so it is fan-out-driven in exactly the agent-team sessions this
# evidence is for. Hence 1 MiB rather than a tighter bound: ~26k completions, not
# ~1.6k. Raising it is the proportionate fix — pruning would need a
# read-modify-write, which is the race this design avoids.
#
# A size CEILING, not a trim: parallel dispatches in one turn run their hooks
# concurrently, so a read-modify-write rotation would be a genuine race, while a
# short `printf >>` is a single write and interleaves safely at line
# granularity. Dropping new records past the ceiling is strictly safer than
# corrupting existing ones. ~40 bytes per line, so this bounds a pathological
# session, not a real one.
#
# On the `wc -c` line the `|| bytes=0` is what makes this safe, NOT the `[ -f ]`:
# `wc -c < missing` is a REDIRECTION failure that `2>/dev/null` does not
# suppress, and an UNHANDLED one under a caller's `trap 'exit 0' ERR` silently
# terminates the whole hook — that exact shape already cost this change one
# regression, killing the pre-existing `reviewer-ran` record (CLAUDE.md
# #137/#198). The `[ -f ]` only avoids a pointless fork on the common
# first-write path; deleting it breaks nothing, so do not read it as the guard.
_reviewer_pairing_append() {
    local f="${1:-}" line="${2:-}" bytes=0
    [ -n "$f" ] && [ -n "$line" ] || return 1
    if [ -f "$f" ]; then
        bytes="$(wc -c < "$f" 2>/dev/null | tr -d ' ')" || bytes=0
        case "$bytes" in ''|*[!0-9]*) bytes=0 ;; esac
    fi
    [ "$bytes" -lt 1048576 ] || return 1
    printf '%s\n' "$line" >> "$f" 2>/dev/null || return 1
    return 0
}

# reviewer_pairing_note_dispatch <session_id> <agent_id> <ledger_key>
# Records "this agent was dispatched as a reviewer, on this branch".
#
# The ledger key is stored so the completion side can refuse to credit a branch
# the reviewer never saw: branch_ledger_record derives its key from the cwd at
# CALL time, and a backgrounded reviewer completes while the parent session is
# free to check out something else.
reviewer_pairing_note_dispatch() {
    local sid="${1:-}" aid="${2:-}" key="${3:-}" f
    [ -n "$aid" ] && [ -n "$key" ] || return 1
    case "$aid" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    case "$key" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    f="$(_reviewer_pairing_file dispatch "$sid")" || return 1
    _reviewer_pairing_append "$f" "${aid} ${key}"
}

# reviewer_pairing_note_complete <session_id> <agent_id> <ledger_key>
# Records "this agent finished and emitted output, on this branch". NOT a credit
# on its own — the dispatch side still has to have classified it as a reviewer.
#
# The key is stored for the SAME reason the dispatch half stores one, and its
# absence was a measured false-credit path: the dispatch side credits on
# membership alone, so an agent-id collision ALONE (no matching branch, no
# ordering) was sufficient to record `reviewer-returned` at spawn time for a
# reviewer that had produced nothing. Reproduced against the real hooks with a
# positive control. Both halves now bind, so a collision must ALSO land on the
# same branch to matter.
reviewer_pairing_note_complete() {
    local sid="${1:-}" aid="${2:-}" key="${3:-}" f
    [ -n "$aid" ] && [ -n "$key" ] || return 1
    case "$aid" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    case "$key" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    f="$(_reviewer_pairing_file complete "$sid")" || return 1
    _reviewer_pairing_append "$f" "${aid} ${key}"
}

# reviewer_pairing_dispatch_key <session_id> <agent_id> — prints the ledger key
# recorded at dispatch for <agent_id>, or nothing (return 1) when this agent was
# not dispatched as a reviewer.
#
# `awk '$1==a'` is an exact FIELD comparison, so no stored value can be read as
# a pattern or match as a prefix. The `#`-prefixed diagnostic lines note_mismatch
# writes into THIS file do not collide with any REAL agent id (measured ids are
# 17 hex characters) — but `$1` of such a line is the literal `#`, so the
# exemption is a property of the id charset, not of the comparison. Do not
# restate it as "a comment line can never match".
#
# The hazard is concrete and was observed: this function returns `$2`, and `$2`
# of a mismatch line is the word `branch-mismatch`. A lookup that matched such a
# line would hand the caller "branch-mismatch" AS A LEDGER KEY. The charset
# validation above closes it from the other end — a caller can never ask for `#`
# — but do not remove either guard on the grounds that the other exists. Absent or unreadable file is a
# miss, not an error: a recorder degrades to "no record", never to a fabricated
# one.
reviewer_pairing_dispatch_key() {
    local sid="${1:-}" aid="${2:-}" f out
    [ -n "$aid" ] || return 1
    # Readers charset-validate too, matching the writers. Nothing stored could
    # today contain a character that changes `$1==a`, but awk -v processes POSIX
    # escapes in the value, and writer/reader validation asymmetry is a class this
    # repo has been bitten by before.
    case "$aid" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    f="$(_reviewer_pairing_file dispatch "$sid")" || return 1
    [ -f "$f" ] || return 1
    out="$(awk -v a="$aid" '$1==a {print $2; exit}' "$f" 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s' "$out"
}

# reviewer_pairing_complete_key <session_id> <agent_id> — prints the ledger key
# recorded when this agent was observed completing, or nothing (return 1).
#
# Returns the KEY rather than a boolean so the dispatch side can branch-bind the
# way the completion side does. A membership test was the earlier shape and it
# was a measured false-credit path — see note_complete.
reviewer_pairing_complete_key() {
    local sid="${1:-}" aid="${2:-}" f out
    [ -n "$aid" ] || return 1
    case "$aid" in *[!A-Za-z0-9._-]*) return 1 ;; esac
    f="$(_reviewer_pairing_file complete "$sid")" || return 1
    [ -f "$f" ] || return 1
    out="$(awk -v a="$aid" '$1==a {print $2; exit}' "$f" 2>/dev/null)" || return 1
    [ -n "$out" ] || return 1
    printf '%s' "$out"
}

# reviewer_pairing_note_mismatch <session_id> <agent_id> <dispatch_key> <now_key>
# A reviewer completed on a branch other than the one it was dispatched on, so
# nothing was credited. Recorded as a `#` comment line in the DISPATCH file — no
# new state family, no new GC entry, and `$1==a` lookups skip it (its `$1` is the
# literal `#`).
#
# The DISPATCH file, not the completion file, and that choice is the point: the
# completion file grows with EVERY subagent completion, so it is the half that
# approaches the size ceiling, and putting the diagnostic there meant it fell
# silent under exactly the condition that starts breaking the join. The dispatch
# file grows only with reviewer dispatches.
#
# This exists because a miss otherwise leaves NO trace anywhere, which is how
# the foreground ordering defect nearly shipped as a silent no-op: "no reviewer
# ran" and "a reviewer ran and the join failed" must not look identical.
reviewer_pairing_note_mismatch() {
    local sid="${1:-}" aid="${2:-}" dkey="${3:-}" nkey="${4:-}" f
    f="$(_reviewer_pairing_file dispatch "$sid")" || return 1
    _reviewer_pairing_append "$f" "# branch-mismatch ${aid} dispatched=${dkey} completed=${nkey}"
}
