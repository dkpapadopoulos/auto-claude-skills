#!/bin/bash
# compact-recovery-render.sh — shared post-compaction recovery renderer.
# Sourced by compact-recovery-hook.sh (SessionStart, manual /compact) and
# compact-recovery-prompt-hook.sh (UserPromptSubmit prompt-carrier).
# render_compact_recovery <token> [trigger] prints the recovery block to
# stdout, or nothing when no recoverable state exists. Fail-open: every
# sub-render degrades independently; never exits the caller.
# Advisory-only output (NOT gate enforcement) — deliberately excluded from
# the _GATE_ENFORCE_LIBS canary list, like consol-marker.sh.
# Spec: openspec/changes/compact-recovery-prompt-carrier.

render_compact_recovery() {
    local _token="${1:-}"
    local _trigger="${2:-}"
    local _sections=""

    # --- Team checkpoint (token-independent) ---
    local _ckpt="${HOME}/.claude/team-checkpoint.md"
    if [ -f "$_ckpt" ]; then
        local _team=""
        _team="$(cat "$_ckpt" 2>/dev/null)" || _team=""
        if [ -n "$_team" ]; then
            _sections="=== Team State Recovery (from pre-compaction checkpoint) ===
${_team}
=== End Team State Recovery ==="
        fi
    fi

    if [ -n "$_token" ]; then
        # --- Confirmed intent (marker file; path owned by openspec-state.sh) ---
        # Plain-text read via head -c only — no jq requirement, so this degrades
        # independently of jq availability.
        local _intent_file="${HOME}/.claude/.skill-confirmed-intent-${_token}"
        if [ -f "$_intent_file" ]; then
            local _intent=""
            _intent="$(head -c 2048 "$_intent_file" 2>/dev/null)" || _intent=""
            if [ -n "$_intent" ]; then
                [ -n "$_sections" ] && _sections="${_sections}
"
                _sections="${_sections}Confirmed intent (persisted pre-compaction): ${_intent}"
            fi
        fi

        if command -v jq >/dev/null 2>&1; then
            # --- Composition chain state (single jq fork; empty when no chain) ---
            local _comp="${HOME}/.claude/.skill-composition-state-${_token}"
            if [ -f "$_comp" ]; then
                local _chain=""
                _chain="$(jq -r '
                    if ((.chain // []) | length) > 0 then
                      "Chain: "        + (.chain | join(" -> "))            + "\n" +
                      "Completed: "    + ((.completed // []) | join(", "))  + "\n" +
                      "Current step: " + (if (.current_index // 0) >= 0 then (.chain[.current_index // 0] // "unknown") else "unknown" end) + "\n" +
                      "Resume from: "  + (if (.current_index // 0) >= 0 then (.chain[.current_index // 0] // "unknown") else "unknown" end)
                    else empty end' "$_comp" 2>/dev/null)" || _chain=""
                if [ -n "$_chain" ]; then
                    [ -n "$_sections" ] && _sections="${_sections}
"
                    _sections="${_sections}=== Composition Recovery (from pre-compaction state) ===
${_chain}
=== End Composition Recovery ==="
                fi
            fi

            # --- Active OpenSpec changes (bounded to 6; single jq fork) ---
            local _ostate="${HOME}/.claude/.skill-openspec-state-${_token}"
            if [ -f "$_ostate" ]; then
                local _changes=""
                _changes="$(jq -r '
                    [.changes // {} | to_entries[]
                      | select(.value.archived_at == null)
                      | "- " + .key
                        + ((.value.capability_slug // "") | if . == "" then "" else " (capability: " + . + ")" end)
                    ] | .[0:6] | join("\n")' "$_ostate" 2>/dev/null)" || _changes=""
                if [ -n "$_changes" ]; then
                    [ -n "$_sections" ] && _sections="${_sections}
"
                    _sections="${_sections}Active OpenSpec changes:
${_changes}"
                fi
            fi
        fi
    fi

    [ -z "$_sections" ] && return 0

    printf '%s\n' "=== Post-Compaction State Recovery${_trigger:+ (trigger=${_trigger})} ===
Reference state restored from pre-compaction checkpoints. Verify against the repo before acting on it.
${_sections}
=== End Post-Compaction State Recovery ==="
    return 0
}
