#!/bin/bash
# --- Claude Code Skill Activation Hook v2 (config-driven) --------
# https://github.com/damianpapadopoulos/auto-claude-skills
#
# Config-driven routing engine that reads the cached skill registry
# instead of using hardcoded regex patterns.
#
# Input: {"prompt": "..."} via stdin
# Output: {"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"..."}}
#
# Bash 3.2 compatible (macOS default). Heavy jq usage for scoring.
# -----------------------------------------------------------------
# Note: -e is intentionally omitted. Regex match failures in [[ $P =~ $trigger ]] return exit 1, which would abort the script.
set -uo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# jq is required for registry-based routing
if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

# Capture stdin once; extract transcript_path + prompt in the SAME single jq
# fork the prompt already cost (\x1f-joined, transcript first — the prompt may
# contain anything, a path cannot contain \x1f).
_HOOK_INPUT="$(cat 2>/dev/null)" || _HOOK_INPUT=""
_FIELDS="$(printf '%s' "${_HOOK_INPUT}" | jq -r '[.transcript_path // "", .prompt // ""] | join("\u001f")' 2>/dev/null)" || _FIELDS=""
_TRANSCRIPT="${_FIELDS%%$'\x1f'*}"
PROMPT="${_FIELDS#*$'\x1f'}"

# Resolve session token payload-first (issue #51): the singleton races across
# concurrent sessions (last-writer-wins); our own payload names our conversation.
# Read early so early-exit gates can check for active composition state.
_SESSION_TOKEN=""
if [[ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]]; then
  # shellcheck source=lib/session-token.sh
  . "${PLUGIN_ROOT}/hooks/lib/session-token.sh"
  _SESSION_TOKEN="$(resolve_session_token_from_transcript "${_TRANSCRIPT}")"
else
  [[ -f "${HOME}/.claude/.skill-session-token" ]] && _SESSION_TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null)"
fi

# Re-stamp the singleton with OUR resolved token so no-payload SKILL.md
# consumers later in this turn read this conversation's token (narrows the
# residual no-payload race to one prompt-width; see issue #51). Only when the
# token came from the payload — re-stamping a singleton-fallback token is churn.
# tmp+mv: a plain `>` truncate-then-write exposes concurrent readers to empty
# reads; rename is atomic on the same filesystem (same shape as the
# composition-state write in skill-completion-hook.sh).
if [[ -n "${_SESSION_TOKEN}" && -n "${_TRANSCRIPT}" ]]; then
  _TOKEN_FILE="${HOME}/.claude/.skill-session-token"
  if printf '%s' "${_SESSION_TOKEN}" > "${_TOKEN_FILE}.tmp.$$" 2>/dev/null; then
    mv "${_TOKEN_FILE}.tmp.$$" "${_TOKEN_FILE}" 2>/dev/null || rm -f "${_TOKEN_FILE}.tmp.$$" 2>/dev/null || true
  fi
fi

# _comp_active: returns 0 (true) if composition state is live for this session,
# 1 (false) otherwise. Used to bypass short-prompt and blocklist early-exits
# so bare acks during an active SDLC chain can reach the sticky-emission logic.
_comp_active() {
  [[ -z "${_SESSION_TOKEN}" ]] && return 1
  local _f="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
  [[ -f "$_f" ]] || return 1
  jq -e '(.chain // [] | length) > (.completed // [] | length)' "$_f" >/dev/null 2>&1
}

# =================================================================
# EARLY EXITS
# =================================================================
[[ -z "$PROMPT" ]] && exit 0
# Skip slash commands — these are handled by the Skill tool directly
[[ "$PROMPT" =~ ^[[:space:]]*/ ]] && exit 0
(( ${#PROMPT} < 5 )) && ! _comp_active && exit 0
# Escape hatch: [no-skills] marker or -- prefix suppresses all routing
[[ "$PROMPT" == *"[no-skills]"* ]] && exit 0
[[ "$PROMPT" =~ ^[[:space:]]*--[[:space:]] ]] && exit 0

P=$(printf '%s' "$PROMPT" | tr '[:upper:]' '[:lower:]')

# =================================================================
# BLOCKLIST — skip greetings / acknowledgements
# =================================================================
# User-configurable via .greeting_blocklist in skill-config.json (regex string).
# Falls back to a built-in default covering common greetings and acks.
_BLOCKLIST=""
if [[ -f "${HOME}/.claude/skill-config.json" ]]; then
  _BLOCKLIST="$(jq -r '.greeting_blocklist // empty' "${HOME}/.claude/skill-config.json" 2>/dev/null)"
fi
[[ -z "$_BLOCKLIST" ]] && _BLOCKLIST='^(hi|hello|hey|thanks|thank.you|good.(morning|afternoon|evening)|bye|goodbye|ok|okay|yes|no|sure|yep|nope|got.it|sounds.good|cool|nice|great|perfect|awesome|understood)([[:space:]!.,]+.{0,20})?$'
if [[ "$P" =~ $_BLOCKLIST ]]; then
  TAIL="${P#*[[:space:]]}"
  if [[ "$TAIL" == "$P" ]] || (( ${#TAIL} < 20 )); then
    # Silent exit by default; SKILL_DEBUG=1 emits a one-line breadcrumb so users
    # can diagnose the case where a legitimate dev prompt was swallowed.
    [[ -n "${SKILL_DEBUG:-}" ]] && \
      printf '[skill-hook] greeting blocklist matched prompt; no routing emitted. Set SKILL_EXPLAIN=1 for full scoring trace.\n' >&2
    _comp_active || exit 0
  fi
fi

# =================================================================
# LOAD REGISTRY
# =================================================================
REGISTRY_CACHE="${HOME}/.claude/.skill-registry-cache.json"
FALLBACK_REGISTRY="${PLUGIN_ROOT}/config/fallback-registry.json"
REGISTRY=""
_PROJECT_ROOT="${SKILL_PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

if [[ -f "$REGISTRY_CACHE" ]] && jq empty "$REGISTRY_CACHE" >/dev/null 2>&1; then
  REGISTRY="$(cat "$REGISTRY_CACHE")"
elif [[ -f "$FALLBACK_REGISTRY" ]] && jq empty "$FALLBACK_REGISTRY" >/dev/null 2>&1; then
  REGISTRY="$(cat "$FALLBACK_REGISTRY")"
else
  # No registry available — emit minimal phase checkpoint and exit
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DISCOVER/DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/LEARN/DEBUG)
and consider whether any installed skill applies."
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "$OUT" | jq -Rs .)"
  exit 0
fi

# =================================================================
# LOAD USER SETTINGS
# =================================================================
MAX_SUGGESTIONS=3
USER_CONFIG="${HOME}/.claude/skill-config.json"
if [[ -f "$USER_CONFIG" ]] && jq empty "$USER_CONFIG" >/dev/null 2>&1; then
  _ms="$(jq -r '.settings.max_suggestions // .max_suggestions // 3' "$USER_CONFIG" 2>/dev/null)"
  # Validate as positive integer; fall back to 3
  if [[ "$_ms" =~ ^[1-9][0-9]*$ ]]; then
    MAX_SUGGESTIONS="$_ms"
  fi
fi

# =================================================================
# ROUTING ENGINE FUNCTIONS
# =================================================================
# These functions operate on shared globals (bash functions share scope).
# Extracted from the linear flow for maintainability.

# --- _score_skills ------------------------------------------------
# Input globals: SKILL_DATA, P
# Output globals: RESULTS, SORTED
# Explain globals (when SKILL_EXPLAIN is set): _EXPLAIN_SCORING
_score_skills() {
  # Score each skill (name-boost check merged into the same loop — no separate pre-pass)
  RESULTS=""
  _EXPLAIN_SCORING=""
  while IFS="$FS" read -r skill_name skill_name_lower skill_role skill_priority skill_invoke skill_phase triggers_joined keywords_joined _required_when; do
    [[ -z "$skill_name" ]] && continue

    # Name boost: full name match (100) or hyphen-segment match (20).
    # Full: "frontend-design" as whole word in prompt -> 100
    # Segment: "frontend" as whole word (segment of "frontend-design") -> 20
    name_boost=0
    if [[ "$P" =~ (^|[^a-z0-9-])${skill_name_lower}($|[^a-z0-9-]) ]]; then
      name_boost=100
    elif [[ "$skill_name_lower" == *-* ]]; then
      _seg_remaining="$skill_name_lower"
      while [[ -n "$_seg_remaining" ]]; do
        if [[ "$_seg_remaining" == *-* ]]; then
          _seg="${_seg_remaining%%-*}"
          _seg_remaining="${_seg_remaining#*-}"
        else
          _seg="$_seg_remaining"
          _seg_remaining=""
        fi
        # Skip segments shorter than 6 chars to avoid false positives on
        # common words like "test", "code", "plan" that are also trigger words
        [[ "${#_seg}" -lt 6 ]] && continue
        if [[ "$P" =~ (^|[^a-z0-9])${_seg}($|[^a-z0-9]) ]]; then
          name_boost=20
          break
        fi
      done
    fi

    # Score triggers (iterate using string splitting — no per-trigger jq fork)
    trigger_score=0
    _explain_parts=""  # accumulate per-trigger explain details
    if [[ -n "$triggers_joined" ]]; then
      _remaining="$triggers_joined"
      while [[ -n "$_remaining" ]]; do
        if [[ "$_remaining" == *"${DELIM}"* ]]; then
          trigger="${_remaining%%${DELIM}*}"
          _remaining="${_remaining#*${DELIM}}"
        else
          trigger="$_remaining"
          _remaining=""
        fi
        [[ -z "$trigger" ]] && continue

        # Test regex against lowercased prompt
        if [[ "$P" =~ $trigger ]]; then
          # Scan for the best match position (word-boundary=30 > substring=10).
          # The leftmost regex match may land inside a word (e.g. "bug" in
          # "debug"), even when a word-boundary match exists later (e.g.
          # standalone "error").  Re-try on progressively shorter suffixes
          # until a boundary hit is found or the string is exhausted.
          _best=10
          _scan="$P"
          _offset=0
          while true; do
            matched="${BASH_REMATCH[0]}"
            [[ -z "$matched" ]] && break

            _pre="${_scan%%"$matched"*}"
            _abs=$((_offset + ${#_pre}))
            _aft=$((_abs + ${#matched}))
            _wb=1
            [[ "$_abs" -gt 0 ]] && [[ "${P:$((_abs-1)):1}" =~ [a-z0-9_.-] ]] && _wb=0
            [[ "$_aft" -lt "${#P}" ]] && [[ "${P:${_aft}:1}" =~ [a-z0-9_.-] ]] && _wb=0

            if [[ "$_wb" -eq 1 ]]; then
              _best=30
              break
            fi

            # Advance one char past match start and retry regex
            _skip=$((${#_pre} + 1))
            _scan="${_scan:${_skip}}"
            _offset=$((_offset + _skip))
            [[ -z "$_scan" ]] && break
            [[ "$_scan" =~ $trigger ]] || break
          done
          trigger_score=$((trigger_score + _best))
          # Collect explain data for this trigger hit
          if [[ -n "${SKILL_EXPLAIN:-}" ]]; then
            _btype="substring"
            [[ "$_best" -eq 30 ]] && _btype="boundary"
            _explain_parts="${_explain_parts} ${_btype}=${_best}"
          fi
        fi
      done
    fi

    # Keyword matching: exact case-insensitive match, 20 points per hit
    keyword_score=0
    if [[ -n "$keywords_joined" ]]; then
      _kw_remaining="$keywords_joined"
      while [[ -n "$_kw_remaining" ]]; do
        if [[ "$_kw_remaining" == *"${DELIM}"* ]]; then
          keyword="${_kw_remaining%%${DELIM}*}"
          _kw_remaining="${_kw_remaining#*${DELIM}}"
        else
          keyword="$_kw_remaining"
          _kw_remaining=""
        fi
        [[ -z "$keyword" ]] && continue
        # Skip short keywords (same threshold as name-segment boost)
        [[ "${#keyword}" -lt 6 ]] && continue
        # Case-insensitive exact substring match (P is already lowercased)
        if [[ "$P" == *"$keyword"* ]]; then
          keyword_score=$((keyword_score + 20))
        fi
      done
    fi

    # Collect explain data for skills with no match
    if [[ -n "${SKILL_EXPLAIN:-}" ]]; then
      if [[ "$trigger_score" -eq 0 ]] && [[ "$name_boost" -eq 0 ]] && [[ "$keyword_score" -eq 0 ]]; then
        _trig_display="${triggers_joined//${DELIM}/|}"
        [[ ${#_trig_display} -gt 40 ]] && _trig_display="${_trig_display:0:37}..."
        _EXPLAIN_SCORING="${_EXPLAIN_SCORING}[skill-hook]   ${skill_name}: trigger=(${_trig_display}) no-match
"
      fi
    fi

    # Apply skill-name-mention boost (+100) and allow through even with zero trigger_score
    if [[ "$trigger_score" -gt 0 ]] || [[ "$name_boost" -gt 0 ]] || [[ "$keyword_score" -gt 0 ]]; then
      # ---- C2: per-skill iteration cap (role-allowlist: domain + required only) ----
      # Process and workflow roles are NEVER capped — this guard protects SDLC
      # phase gates (verification-before-completion, openspec-ship,
      # finishing-a-development-branch, requesting-code-review, etc.) from
      # accidental misconfiguration. Locked by tests/test-routing.sh::
      # test_max_iterations_role_allowlist.
      if [[ "$skill_role" == "domain" || "$skill_role" == "required" ]] && [[ -n "${_SESSION_TOKEN}" ]]; then
        _max_iter="$(printf '%s' "$REGISTRY" | jq -r --arg n "$skill_name" \
            '.skills[] | select(.name == $n) | .max_iterations // empty' 2>/dev/null)"
        if [[ "$_max_iter" =~ ^[0-9]+$ ]] && [[ "$_max_iter" -ge 1 ]]; then
          _comp_file="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
          if [[ -f "$_comp_file" ]]; then
            _iter_count="$(jq -r --arg n "$skill_name" \
                '[.completed // [] | .[] | select(. == $n)] | length' \
                "$_comp_file" 2>/dev/null)"
            if [[ "$_iter_count" =~ ^[0-9]+$ ]] && [[ "$_iter_count" -ge "$_max_iter" ]]; then
              [[ -n "${SKILL_EXPLAIN:-}" ]] && \
                  printf '[skill-hook] [max-iter] skipping %s (%s of %s)\n' \
                  "$skill_name" "$_iter_count" "$_max_iter" >&2
              continue
            fi
          fi
        fi
      fi
      # ---- end C2 ----
      final_score=$((trigger_score + skill_priority + name_boost + keyword_score))
      RESULTS="${RESULTS}${final_score}|${skill_name}|${skill_role}|${skill_invoke}|${skill_phase}
"
      # Collect explain data for matched skills
      if [[ -n "${SKILL_EXPLAIN:-}" ]]; then
        _score_breakdown="${_explain_parts}"
        [[ "$keyword_score" -gt 0 ]] && _score_breakdown="${_score_breakdown} keyword=${keyword_score}"
        [[ "$name_boost" -gt 0 ]] && _score_breakdown="${_score_breakdown} name-boost=${name_boost}"
        [[ "$skill_priority" -gt 0 ]] && _score_breakdown="${_score_breakdown} priority=${skill_priority}"
        _EXPLAIN_SCORING="${_EXPLAIN_SCORING}[skill-hook]   ${skill_name}: trigger=(${triggers_joined//${DELIM}/|})${_score_breakdown} = ${final_score}
"
      fi
    fi
  done <<EOF
${SKILL_DATA}
EOF

  # Sort by score descending
  SORTED="$(printf '%s' "$RESULTS" | grep -v '^$' | sort -s -t'|' -k1 -rn)"
}

# --- _apply_context_bonus -----------------------------------------
# If the last-invoked skill has `precedes` entries, boost those successor
# skills by +20 in the sorted results. Also boost skills whose `requires`
# array contains the last-invoked skill.
# Input globals: SORTED, REGISTRY, _SESSION_TOKEN
# Output globals: SORTED (re-sorted with bonus applied)
_LAST_INVOKED_SKILL=""
_apply_context_bonus() {
  [[ -z "${_SESSION_TOKEN:-}" ]] && return
  local _signal_file="${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}"
  [[ -f "$_signal_file" ]] || return

  local _last_skill
  _last_skill="$(jq -r '.skill // empty' "$_signal_file" 2>/dev/null)"
  [[ -z "$_last_skill" ]] && return

  # Store for use by _walk_composition_chain
  _LAST_INVOKED_SKILL="$_last_skill"

  # Find skills that should be boosted: those whose requires contains last_skill,
  # OR those that appear in last_skill's precedes array
  local _successors
  _successors="$(printf '%s' "$REGISTRY" | jq -r --arg last "$_last_skill" '
    [.skills[] | select(
      ((.requires // []) | any(. == $last))
    ) | .name] as $req_matches |
    [.skills[] | select(.name == $last) | .precedes // []] | flatten | . + $req_matches | unique | join("|")
  ' 2>/dev/null)"
  [[ -z "$_successors" ]] && return

  local _new_sorted=""
  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    local _boosted="$score"
    # Check if this skill name is in the successors list
    local _check="|${_successors}|"
    if [[ "$_check" == *"|${name}|"* ]]; then
      _boosted=$((score + 20))
    fi
    _new_sorted="${_new_sorted}${_boosted}|${name}|${role}|${invoke}|${phase}
"
  done <<EOF
${SORTED}
EOF

  SORTED="$(printf '%s' "$_new_sorted" | grep -v '^$' | sort -s -t'|' -k1 -rn)"
}

# --- _apply_sticky_composition ------------------------------------
# Sticky-emit the CURRENT chain step when composition state is active and
# the prompt is short (a bare ack like "yes"/"ok"/"do it"). Display-only:
# does NOT mutate .completed — that stays the responsibility of the
# PostToolUse ^Skill$ completion hook.
# Input globals: $P, $SORTED, $REGISTRY, $_SESSION_TOKEN
# Output: mutates $SORTED by injecting CURRENT skill.
# Fails open: any jq error, missing file, or unavailable skill returns silently.
_apply_sticky_composition() {
  [[ -z "${_SESSION_TOKEN}" ]] && return
  local _comp_file="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
  [[ -f "$_comp_file" ]] || return

  # Pure-cancel prompts clear the chain and suppress sticky for this turn.
  # Anchored to whole-prompt match so mixed prompts (e.g., "never mind,
  # different plan" — where "plan" naturally matches writing-plans) do not
  # pass through here; those go to the hijack guard below or normal routing.
  # Trailing punctuation class covers . , ! ? ; : and trailing whitespace.
  if [[ "$P" =~ ^[[:space:]]*(stop|cancel|abort|nevermind|never.mind|forget.it|scrap.that|drop.it|no.thanks|nope|nah)[[:space:]!.,?:\;]*$ ]]; then
    rm -f "$_comp_file" 2>/dev/null
    return
  fi

  # CURRENT = chain[length(completed)]. Bail if exhausted, chain empty, or any
  # completed entry is not in chain (malformed state).
  local _current_name
  _current_name="$(jq -r '
    (.chain // []) as $c | (.completed // []) as $d |
    if ($c | length) == 0 then empty
    elif ($d | length) >= ($c | length) then empty
    elif ($d | all(. as $x | $c | index($x))) then $c[$d | length]
    else empty end
  ' "$_comp_file" 2>/dev/null)"
  [[ -z "$_current_name" ]] && return

  # Eligibility: only fire on short prompts (the "yes"/"ok"/"do it" case).
  # Longer prompts route via normal triggers.
  local _word_count
  _word_count="$(printf '%s' "$P" | wc -w | tr -d '[:space:]')"
  [[ "${_word_count:-0}" -le 6 ]] || return

  # Registry lookup.
  local _lookup
  _lookup="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_current_name" '
    .skills[] | select(.name == $n and .available == true and .enabled == true) |
    [(.role // "process"), (.phase // ""), (.invoke // "Skill(\(.name))")] | @tsv
  ' 2>/dev/null)"
  [[ -z "$_lookup" ]] && return

  local _role _phase _invoke
  _role="$(printf '%s' "$_lookup" | awk -F'\t' '{print $1}')"
  _phase="$(printf '%s' "$_lookup" | awk -F'\t' '{print $2}')"
  _invoke="$(printf '%s' "$_lookup" | awk -F'\t' '{print $3}')"

  # Hijack guard: skip injection if a process skill already scored naturally.
  # Sticky is a fallback for the no-trigger-match case, not a boost.
  while IFS='|' read -r _ts _tn _tr _ti _tp; do
    [[ -z "$_tn" ]] && continue
    [[ "$_tr" == "process" ]] && return
  done <<EOF
${SORTED}
EOF

  # Inject CURRENT at a solid process-tier score; role-cap picks it.
  local _new_line="50|${_current_name}|${_role}|${_invoke}|${_phase}"
  SORTED="$(printf '%s\n%s' "$_new_line" "$SORTED" | grep -v '^$' | sort -s -t'|' -k1 -rn)"
}

# --- _select_by_role_caps -----------------------------------------
# Input globals: SORTED, MAX_SUGGESTIONS
# Output globals: SELECTED, OVERFLOW_DOMAIN, OVERFLOW_WORKFLOW, PROCESS_COUNT, DOMAIN_COUNT, WORKFLOW_COUNT, TOTAL_COUNT
# Explain globals (when SKILL_EXPLAIN is set): _EXPLAIN_CAPS
_select_by_role_caps() {
  # Max 1 process, up to 2 domain, max 1 workflow, total <= max_suggestions.
  # INVARIANT: The highest-ranked process skill always gets a reserved slot
  # (it is selected in the first pass and other roles fill remaining slots).
  SELECTED=""
  OVERFLOW_DOMAIN=""
  OVERFLOW_WORKFLOW=""
  PROCESS_COUNT=0
  DOMAIN_COUNT=0
  WORKFLOW_COUNT=0
  TOTAL_COUNT=0
  _EXPLAIN_CAPS=""

  # Pass 0: Collect required-role skills that match tentative phase.
  # These bypass all caps. Since all required skills have triggers,
  # they WILL be in SORTED when they match.
  REQUIRED_SELECTED=""
  REQUIRED_COUNT=0

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    [[ "$role" != "required" ]] && continue
    [[ "$phase" != "${_TENTATIVE_PHASE}" ]] && continue

    REQUIRED_SELECTED="${REQUIRED_SELECTED}${score}|${name}|${role}|${invoke}|${phase}
"
    REQUIRED_COUNT=$((REQUIRED_COUNT + 1))
    [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [required] ${name} (${score}) <- pass 0
"
  done <<EOF
${SORTED}
EOF

  # Pass 1: reserve the top process skill (if any)
  RESERVED_PROCESS_NAME=""
  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    # Skip skills already selected in pass 0
    printf '%s' "$REQUIRED_SELECTED" | grep -qF "|${name}|" && continue
    if [[ "$role" == "process" ]]; then
      RESERVED_PROCESS_NAME="$name"
      SELECTED="${score}|${name}|${role}|${invoke}|${phase}
"
      PROCESS_COUNT=1
      TOTAL_COUNT=1
      [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [process] ${name} (${score}) <- reserved
"
      break
    fi
  done <<EOF
${SORTED}
EOF

  # Pass 2: fill remaining slots, skipping reserved process and required skills
  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    # Skip skills already selected in pass 0
    printf '%s' "$REQUIRED_SELECTED" | grep -qF "|${name}|" && continue

    case "$role" in
      required)
        # Required skills not selected in pass 0 (wrong phase) — skip entirely
        continue
        ;;
      process)
        # Skip reserved process skill; cap additional process skills at 0
        [[ "$name" == "$RESERVED_PROCESS_NAME" ]] && continue
        if [[ "$PROCESS_COUNT" -ge 1 ]] || [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]]; then
          [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [process] ${name} (${score}) <- capped
"
          continue
        fi
        PROCESS_COUNT=$((PROCESS_COUNT + 1))
        [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [process] ${name} (${score}) <- slot ${PROCESS_COUNT}/1
"
        ;;
      domain)
        if [[ "$DOMAIN_COUNT" -ge 2 ]] || [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]]; then
          OVERFLOW_DOMAIN="${OVERFLOW_DOMAIN}${name}|${invoke}
"
          [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [domain]  ${name} (${score}) <- overflow
"
          continue
        fi
        DOMAIN_COUNT=$((DOMAIN_COUNT + 1))
        [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [domain]  ${name} (${score}) <- slot ${DOMAIN_COUNT}/2
"
        ;;
      workflow)
        if [[ "$WORKFLOW_COUNT" -ge 1 ]] || [[ "$TOTAL_COUNT" -ge "$MAX_SUGGESTIONS" ]]; then
          OVERFLOW_WORKFLOW="${OVERFLOW_WORKFLOW}${name}|${invoke}
"
          [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [workflow] ${name} (${score}) <- overflow
"
          continue
        fi
        WORKFLOW_COUNT=$((WORKFLOW_COUNT + 1))
        [[ -n "${SKILL_EXPLAIN:-}" ]] && _EXPLAIN_CAPS="${_EXPLAIN_CAPS}[skill-hook]   [workflow] ${name} (${score}) <- slot ${WORKFLOW_COUNT}/1
"
        ;;
      *)
        # Unknown role — skip to prevent bypassing caps
        continue
        ;;
    esac

    SELECTED="${SELECTED}${score}|${name}|${role}|${invoke}|${phase}
"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
  done <<EOF
${SORTED}
EOF

  # Prepend required skills and update total count
  if [[ -n "$REQUIRED_SELECTED" ]]; then
    SELECTED="${REQUIRED_SELECTED}${SELECTED}"
    TOTAL_COUNT=$((TOTAL_COUNT + REQUIRED_COUNT))
  fi
}

# --- _determine_label_phase ---------------------------------------
# Input globals: SELECTED
# Output globals: PLABEL, PRIMARY_PHASE, PROCESS_SKILL, HAS_DOMAIN, HAS_WORKFLOW
_determine_label_phase() {
  PLABEL=""
  PROCESS_SKILL=""
  HAS_DOMAIN=0
  HAS_WORKFLOW=0
  HAS_REQUIRED=0

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    case "$role" in
      process)
        PROCESS_SKILL="$name"
        case "$name" in
          systematic-debugging)       PLABEL="Fix / Debug" ;;
          brainstorming)              PLABEL="Build New" ;;
          executing-plans|subagent-driven-development) PLABEL="Plan Execution" ;;
          requesting-code-review|receiving-code-review) PLABEL="Review" ;;
          product-discovery)            PLABEL="Discover" ;;
          outcome-review)               PLABEL="Learn / Measure" ;;
        esac
        ;;
      domain)
        HAS_DOMAIN=1
        ;;
      workflow)
        HAS_WORKFLOW=1
        # If no process skill sets the label, workflow skills set Ship / Complete
        if [[ -z "$PLABEL" ]]; then
          case "$name" in
            verification-before-completion|finishing-a-development-branch|openspec-ship) PLABEL="Ship / Complete" ;;
          esac
        fi
        ;;
      required)
        HAS_REQUIRED=1
        ;;
    esac
  done <<EOF
${SELECTED}
EOF

  [[ -z "$PLABEL" ]] && PLABEL="(Claude: assess intent)"
  [[ "$HAS_DOMAIN" -eq 1 ]] && PLABEL="${PLABEL} + Domain"
  [[ "$HAS_WORKFLOW" -eq 1 ]] && PLABEL="${PLABEL} + Workflow"
  [[ "$HAS_REQUIRED" -eq 1 ]] && PLABEL="${PLABEL} + Required"

  # PRIMARY PHASE (process > workflow > domain > required > first non-empty)
  PRIMARY_PHASE=""
  _PHASE_PROCESS=""
  _PHASE_WORKFLOW=""
  _PHASE_DOMAIN=""
  _PHASE_REQUIRED=""
  _PHASE_FIRST=""

  while IFS='|' read -r score name role invoke phase; do
    [[ -z "$name" ]] && continue
    if [[ -n "$phase" ]] && [[ -z "$_PHASE_FIRST" ]]; then
      _PHASE_FIRST="$phase"
    fi
    case "$role" in
      process)  [[ -z "$_PHASE_PROCESS" ]] && _PHASE_PROCESS="$phase" ;;
      workflow) [[ -z "$_PHASE_WORKFLOW" ]] && _PHASE_WORKFLOW="$phase" ;;
      domain)   [[ -z "$_PHASE_DOMAIN" ]] && _PHASE_DOMAIN="$phase" ;;
      required) [[ -z "$_PHASE_REQUIRED" ]] && _PHASE_REQUIRED="$phase" ;;
    esac
  done <<EOF
${SELECTED}
EOF

  if [[ -n "$_PHASE_PROCESS" ]]; then
    PRIMARY_PHASE="$_PHASE_PROCESS"
  elif [[ -n "$_PHASE_WORKFLOW" ]]; then
    PRIMARY_PHASE="$_PHASE_WORKFLOW"
  elif [[ -n "$_PHASE_DOMAIN" ]]; then
    PRIMARY_PHASE="$_PHASE_DOMAIN"
  elif [[ -n "$_PHASE_REQUIRED" ]]; then
    PRIMARY_PHASE="$_PHASE_REQUIRED"
  else
    PRIMARY_PHASE="$_PHASE_FIRST"
  fi
}

# --- _build_skill_lines -------------------------------------------
# Input globals: SELECTED, OVERFLOW_DOMAIN, OVERFLOW_WORKFLOW, PROCESS_SKILL, TOTAL_COUNT
# Output globals: SKILL_LINES, EVAL_SKILLS
_build_skill_lines() {
  SKILL_LINES=""
  EVAL_SKILLS=""

  if [[ "$TOTAL_COUNT" -gt 0 ]]; then
    _SL_REQUIRED=""
    _SL_PROCESS=""
    _SL_DOMAIN=""
    _SL_WORKFLOW=""
    _SL_STANDALONE=""

    # Build required_when lookup (one jq call)
    _RW_LOOKUP="$(printf '%s' "$REGISTRY" | jq -r '
      [.skills[] | select(.required_when != null and .required_when != "")] |
      .[] | "\(.name)=\(.required_when)"
    ' 2>/dev/null)"

    while IFS='|' read -r score name role invoke phase; do
      [[ -z "$name" ]] && continue
      _rw=""
      if [[ "$role" == "process" ]]; then
        _eval_tag="MUST INVOKE"
      elif [[ "$role" == "required" ]]; then
        # Check if condition-gated
        if [[ -n "$_RW_LOOKUP" ]]; then
          _rw="$(printf '%s' "$_RW_LOOKUP" | grep "^${name}=" | head -1 | cut -d= -f2-)"
        fi
        if [[ -n "$_rw" ]]; then
          _eval_tag="INVOKE WHEN: ${_rw}"
        else
          _eval_tag="REQUIRED"
        fi
      else
        _eval_tag="YES/NO"
      fi
      if [[ -n "$EVAL_SKILLS" ]]; then
        EVAL_SKILLS="${EVAL_SKILLS}, ${name} ${_eval_tag}"
      else
        EVAL_SKILLS="${name} ${_eval_tag}"
      fi

      if [[ -n "$PROCESS_SKILL" ]] || [[ "$role" == "required" ]]; then
        case "$role" in
          required)
            if [[ -n "$_rw" ]]; then
              _SL_REQUIRED="${_SL_REQUIRED}
Required when ${_rw}: ${name} -> ${invoke}"
            else
              _SL_REQUIRED="${_SL_REQUIRED}
Required: ${name} -> ${invoke}"
            fi
            ;;
          process)  _SL_PROCESS="
Process: ${name} -> ${invoke}" ;;
          domain)   _SL_DOMAIN="${_SL_DOMAIN}
  Domain: ${name} -> ${invoke}" ;;
          workflow) _SL_WORKFLOW="${_SL_WORKFLOW}
Workflow: ${name} -> ${invoke}" ;;
        esac
      else
        _SL_STANDALONE="${_SL_STANDALONE}
${name} -> ${invoke}"
      fi
    done <<EOF
${SELECTED}
EOF

    SKILL_LINES="${_SL_REQUIRED}${_SL_PROCESS}${_SL_DOMAIN}${_SL_WORKFLOW}${_SL_STANDALONE}"

    # Overflow skills intentionally not displayed — role caps are the signal.
  fi
}

# --- _walk_composition_chain --------------------------------------
# Input globals: REGISTRY, PROCESS_SKILL, SELECTED
# Output globals: COMPOSITION_CHAIN, COMPOSITION_DIRECTIVE, COMPOSITION_HINTS (unused here but declared)
_walk_composition_chain() {
  # Walk the precedes graph forward from the process skill to build a
  # sequential chain.  Also walk requires backward to show prerequisites
  # when the user enters mid-chain (e.g. "execute the plan").
  COMPOSITION_CHAIN=""
  COMPOSITION_DIRECTIVE=""

  # Determine the anchor skill for chain walking: prefer process, fall back to workflow
  _CHAIN_ANCHOR=""
  if [[ -n "$PROCESS_SKILL" ]]; then
    _CHAIN_ANCHOR="$PROCESS_SKILL"
  else
    # Check if the selected workflow skill has precedes/requires
    while IFS='|' read -r _s _n _r _i _p; do
      [[ -z "$_n" ]] && continue
      if [[ "$_r" == "workflow" ]]; then
        _has_chain="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_n" '
          .skills[] | select(.name == $n) |
          if ((.precedes // []) | length) > 0 or ((.requires // []) | length) > 0 then "yes" else "no" end
        ' 2>/dev/null)"
        if [[ "$_has_chain" == "yes" ]]; then
          _CHAIN_ANCHOR="$_n"
          break
        fi
      fi
    done <<EOF
${SELECTED}
EOF
  fi

  if [[ -n "$_CHAIN_ANCHOR" ]]; then
    # Forward walk: anchor skill -> precedes[0] -> precedes[0] -> ...
    # Single jq call returns pipe-delimited chain: skill1|skill2|skill3
    _fwd_chain="$(printf '%s' "$REGISTRY" | jq -r --arg start "$_CHAIN_ANCHOR" '
      .skills as $all |
      def walk_fwd(name):
        ($all[] | select(.name == name) | .precedes // []) as $next |
        if ($next | length) > 0 then name + "|" + walk_fwd($next[0])
        else name end;
      walk_fwd($start)
    ' 2>/dev/null)"

    # Backward walk: anchor skill <- requires[0] <- requires[0] <- ...
    _bwd_chain="$(printf '%s' "$REGISTRY" | jq -r --arg start "$_CHAIN_ANCHOR" '
      .skills as $all |
      def walk_bwd(name):
        ($all[] | select(.name == name) | .requires // []) as $prev |
        if ($prev | length) > 0 then walk_bwd($prev[0]) + "|" + name
        else name end;
      walk_bwd($start)
    ' 2>/dev/null)"

    # Fallback: if anchor has precedes but the walk returned only itself
    # (successor skill missing from registry), build chain from precedes directly
    if [[ -n "$_CHAIN_ANCHOR" ]] && [[ "$_fwd_chain" != *"|"* ]]; then
      _precedes_list="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_CHAIN_ANCHOR" '
        .skills[] | select(.name == $n) | .precedes // [] | join("|")
      ' 2>/dev/null)"
      if [[ -n "$_precedes_list" ]]; then
        _fwd_chain="${_CHAIN_ANCHOR}|${_precedes_list}"
      fi
    fi

    # Merge: backward chain gives predecessors, forward chain gives successors
    # Remove duplicates at the join point (the process skill itself)
    if [[ -n "$_bwd_chain" ]] && [[ "$_bwd_chain" == *"|"* ]]; then
      # Has predecessors — combine backward (minus last) + forward
      _pre="${_bwd_chain%|*}"
      _full_chain="${_pre}|${_fwd_chain}"
    else
      _full_chain="$_fwd_chain"
    fi

    # Only emit composition if chain has 2+ skills
    if [[ "$_full_chain" == *"|"* ]]; then
      # Build display lines with [DONE?] / [CURRENT] / [NEXT] / [LATER] markers
      _step=0
      _current_idx=-1
      _chain_lines=""
      _next_skill=""
      _next_invoke=""

      # Find the index of the current process skill
      _idx=0
      _tmp="$_full_chain"
      while [[ -n "$_tmp" ]]; do
        if [[ "$_tmp" == *"|"* ]]; then
          _cname="${_tmp%%|*}"
          _tmp="${_tmp#*|}"
        else
          _cname="$_tmp"
          _tmp=""
        fi
        if [[ "$_cname" == "$_CHAIN_ANCHOR" ]]; then
          _current_idx=$_idx
        fi
        _idx=$((_idx + 1))
      done

      # Guard: if anchor not found in chain, skip composition display and state write
      if [[ "$_current_idx" -lt 0 ]]; then
        _full_chain=""
      fi
    fi

    # Only proceed with display if chain is still valid after guard
    if [[ "$_full_chain" == *"|"* ]]; then

      # Batch-lookup all chain skills in a single jq call (avoids N forks)
      # Format: name<FS>invoke<FS>description<FS>phase (one per line, chain order)
      _chain_detail="$(printf '%s' "$REGISTRY" | jq -r --arg chain "$_full_chain" '
        ($chain | split("|")) as $names |
        .skills as $all |
        $names[] as $n |
        ([$all[] | select(.name == $n)] | first // null) as $s |
        if $s then
          ($s.description // "" | split(".")[0]) as $desc |
          "\($n)\u001f\($s.invoke // "Skill(\($n))")\u001f\($desc)\u001f\($s.phase // "")"
        else
          "\($n)\u001fSkill(superpowers:\($n))\u001f\($n)\u001f"
        end
      ' 2>/dev/null)"

      # Find position of last-invoked skill in chain (for DONE vs DONE? markers)
      _last_skill_chain_idx=-1
      if [[ -n "${_LAST_INVOKED_SKILL:-}" ]]; then
        _lsi=0
        _ltmp="$_full_chain"
        while [[ -n "$_ltmp" ]]; do
          if [[ "$_ltmp" == *"|"* ]]; then
            _lname="${_ltmp%%|*}"
            _ltmp="${_ltmp#*|}"
          else
            _lname="$_ltmp"
            _ltmp=""
          fi
          [[ "$_lname" == "${_LAST_INVOKED_SKILL}" ]] && _last_skill_chain_idx=$_lsi
          _lsi=$((_lsi + 1))
        done
      fi

      # Read persisted composition state for definitive DONE markers
      _COMP_COMPLETED=""
      _COMP_FILE="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN:-default}"
      if [[ -f "$_COMP_FILE" ]]; then
        _COMP_COMPLETED="$(jq -r '.completed[]' "$_COMP_FILE" 2>/dev/null)" || _COMP_COMPLETED=""
      fi

      # Build the chain display + phase labels in one pass
      _idx=0
      _chain_lines=""
      _phase_labels=""
      _next_skill=""
      _next_invoke=""
      while IFS="$FS" read -r _cname _cinvoke _cdesc _cphase; do
        [[ -z "$_cname" ]] && continue

        if [[ "$_idx" -lt "$_current_idx" ]]; then
          # Check persisted state first, fall back to last-invoked signal
          if [[ -n "$_COMP_COMPLETED" ]] && printf '%s\n' "$_COMP_COMPLETED" | grep -qx "$_cname" 2>/dev/null; then
            _marker="DONE"
          elif [[ "$_last_skill_chain_idx" -ge 0 ]] && [[ "$_idx" -le "$_last_skill_chain_idx" ]]; then
            _marker="DONE"
          else
            _marker="DONE?"
          fi
        elif [[ "$_idx" -eq "$_current_idx" ]]; then
          _marker="CURRENT"
        elif [[ "$_idx" -eq $((_current_idx + 1)) ]]; then
          _marker="NEXT"
          _next_skill="$_cname"
          _next_invoke="$_cinvoke"
        else
          _marker="LATER"
        fi

        _step=$((_idx + 1))
        _chain_lines="${_chain_lines}
  [${_marker}] Step ${_step}: ${_cinvoke} -- ${_cdesc}"
        # Render an optional per-skill `precondition` ONLY under the CURRENT step.
        # This places conditional routing in the mandatory channel the model obeys
        # (the same guidance as an advisory hint gets 0/5 uptake). One jq fork, and
        # only when a composition is being rendered. Fail-open: no field => no line.
        if [[ "$_marker" == "CURRENT" ]]; then
          _cprecond="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_cname" '.skills[] | select(.name == $n) | .precondition // empty' 2>/dev/null)"
          if [[ -n "$_cprecond" ]]; then
            _chain_lines="${_chain_lines}
      ${_cprecond}"
          fi
        fi

        # Build phase label (fall back to skill name if no phase)
        _plabel="${_cphase:-${_cname}}"
        if [[ -n "$_phase_labels" ]]; then
          _phase_labels="${_phase_labels} -> ${_plabel}"
        else
          _phase_labels="$_plabel"
        fi

        _idx=$((_idx + 1))
      done <<EOF
${_chain_detail}
EOF

      COMPOSITION_CHAIN="
Composition: ${_phase_labels}${_chain_lines}"

      if [[ -n "$_next_skill" ]]; then
        COMPOSITION_DIRECTIVE="
IMPORTANT: After completing ${_CHAIN_ANCHOR}, invoke ${_next_invoke}. Do not stop at the current step."
      fi

      # Check for parallel workflow co-selection (same phase as process skill)
      _SELECTED_WORKFLOW=""
      while IFS='|' read -r _s _n _r _i _p; do
        [[ -z "$_n" ]] && continue
        [[ "$_r" == "workflow" ]] && _SELECTED_WORKFLOW="$_n" && break
      done <<EOF
${SELECTED}
EOF
      if [[ -n "$_SELECTED_WORKFLOW" ]] && [[ -n "$_PHASE_PROCESS" ]] && [[ -n "$_PHASE_WORKFLOW" ]] && [[ "$_PHASE_PROCESS" == "$_PHASE_WORKFLOW" ]]; then
        _wf_invoke="$(printf '%s' "$REGISTRY" | jq -r --arg n "$_SELECTED_WORKFLOW" '
          .skills[] | select(.name == $n) | .invoke // "Skill(\($n))"
        ' 2>/dev/null)"
        COMPOSITION_CHAIN="${COMPOSITION_CHAIN}
  [PARALLEL] ${_wf_invoke} -- use alongside current step if eligible"
      fi
    fi
  fi
}

# --- _format_output -----------------------------------------------
# Input globals: TOTAL_COUNT, PLABEL, SKILL_LINES, COMPOSITION_CHAIN, COMPOSITION_LINES,
#                EVAL_SKILLS, PRIMARY_PHASE, DOMAIN_HINT, COMPOSITION_DIRECTIVE,
#                HINTS, COMPOSITION_HINTS, REGISTRY, SORTED, _PROMPT_COUNT
# Output globals: OUT (+ prints final JSON)
_format_output() {
  if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    # Instrument zero-match rate
    _ZM_FILE="${HOME}/.claude/.skill-zero-match-count"
    _zm=0
    [[ -f "$_ZM_FILE" ]] && _zm="$(cat "$_ZM_FILE" 2>/dev/null)"
    [[ "$_zm" =~ ^[0-9]+$ ]] || _zm=0
    printf '%s' "$((_zm + 1))" > "$_ZM_FILE" 2>/dev/null || true

    # Log the zero-match prompt for diagnostics (rotate at 100 entries, cap at 50KB)
    _ZM_LOG="${HOME}/.claude/.skill-zero-match-log"
    # Truncate prompt to 200 chars to prevent unbounded log growth
    printf '%.200s\n' "$P" >> "$_ZM_LOG" 2>/dev/null || true
    if [[ -f "$_ZM_LOG" ]]; then
      # Rotate by line count
      _lc="$(wc -l < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_lc" =~ ^[0-9]+$ ]] && [[ "$_lc" -gt 100 ]]; then
        tail -n 100 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
      # Rotate by byte size (50KB cap)
      _zm_size="$(wc -c < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_zm_size" =~ ^[0-9]+$ ]] && [[ "$_zm_size" -gt 51200 ]]; then
        tail -n 50 "$_ZM_LOG" > "${_ZM_LOG}.tmp" 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
    fi

    # Zero-match: emit nothing (no additionalContext)
    return

  elif [[ "$_PROMPT_COUNT" -gt 10 ]]; then
    # --- minimal format (depth 11+): skill list + eval only ---
    EVAL_PHASE="$PRIMARY_PHASE"
    [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${COMPOSITION_DIRECTIVE}"

  elif [[ "$TOTAL_COUNT" -le 2 ]] && [[ "$_PROMPT_COUNT" -le 5 ]]; then
    # --- compact format (1-2 skills, depth 1-5) ---
    EVAL_PHASE="$PRIMARY_PHASE"
    [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"

  elif [[ "$_PROMPT_COUNT" -le 1 ]] && [[ "$TOTAL_COUNT" -ge 3 ]]; then
    # --- full format (3+ skills, prompt 1 only) ---
    # Build phase guide from registry (falls back to a minimal default)
    _PHASE_GUIDE="$(printf '%s' "$REGISTRY" | jq -r '
      .phase_guide // empty | to_entries | sort_by(.key) |
      .[] | "  " + .key + (" " * ((10 - (.key | length)) | if . < 0 then 0 else . end)) + " -> " + .value
    ' 2>/dev/null)"
    [[ -z "$_PHASE_GUIDE" ]] && _PHASE_GUIDE="  (no phase guide available — assess intent from context)"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})

Step 1 -- ASSESS PHASE. Check conversation context:
${_PHASE_GUIDE}

Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}
You MUST print a brief evaluation for each skill above. Format:
  **Phase: [PHASE]** | ${EVAL_SKILLS}
Process skills marked MUST INVOKE are mandatory — invoke them. Domain/workflow skills marked YES/NO are optional.
This line is MANDATORY -- do not skip it.

Step 3 -- INVOKE the process skill. Do not skip to a later phase.${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"

  else
    # --- compact format (depth 6-10, or any remaining cases) ---
    EVAL_PHASE="$PRIMARY_PHASE"
    [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}${COMPOSITION_LINES}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"
  fi

  # Append methodology hints if any
  if [[ -n "$HINTS" ]] || [[ -n "$COMPOSITION_HINTS" ]]; then
    OUT+="
${HINTS}${COMPOSITION_HINTS}"
  fi

  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "$OUT" | jq -Rs .)"

  # Write last-invoked skill signal for composition tie-breaking
  if [[ "$TOTAL_COUNT" -gt 0 ]] && [[ -n "${_SESSION_TOKEN:-}" ]]; then
    _top_skill="$(printf '%s' "$SELECTED" | head -1 | cut -d'|' -f2)"
    _top_phase="$(printf '%s' "$SELECTED" | head -1 | cut -d'|' -f5)"
    if [[ -n "$_top_skill" ]]; then
      jq -n --arg s "$_top_skill" --arg p "$_top_phase" '{skill:$s,phase:$p}' \
        > "${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}" 2>/dev/null || true
    fi
  fi

  # Write composition state for compaction resilience
  # Guard: skip write if _current_idx is -1 (anchor not found in chain)
  if [[ -n "${_full_chain:-}" ]] && [[ "${_full_chain}" == *"|"* ]] && [[ -n "${_SESSION_TOKEN:-}" ]] && [[ "${_current_idx:--1}" -ge 0 ]]; then
    _comp_completed="[]"
    # Determine how many chain positions are "done" for this write. Use the
    # furthest-advanced of two signals:
    #   (a) _current_idx - 1 — implicit, from the linear composition model
    #       (being at a chain anchor means predecessors are done).
    #   (b) _last_skill_chain_idx — explicit, from the last-invoked signal.
    # Without (a), a prior prompt's domain/workflow skill that isn't in the
    # chain resets _last_skill_chain_idx to -1 and drops `completed` back to
    # empty, which then blocks chore commits at the push gate.
    _progress_idx=-1
    if [[ "${_current_idx:--1}" -gt 0 ]]; then
      _progress_idx=$((_current_idx - 1))
    fi
    if [[ "${_last_skill_chain_idx:--1}" -gt "$_progress_idx" ]]; then
      _progress_idx="$_last_skill_chain_idx"
    fi
    if [[ "$_progress_idx" -ge 0 ]]; then
      _comp_completed="$(printf '%s' "$_full_chain" | tr '|' '\n' | head -n "$((_progress_idx + 1))" | jq -R . | jq -s . 2>/dev/null)" || _comp_completed="[]"
    fi
    _comp_chain="$(printf '%s' "$_full_chain" | tr '|' '\n' | jq -R . | jq -s . 2>/dev/null)" || {
      _comp_chain=""
      # Surface the failure under SKILL_EXPLAIN so compaction-recovery debug
      # isn't left guessing why state wasn't written.
      [[ -n "${SKILL_EXPLAIN:-}" ]] && \
        printf '[skill-hook] composition state write skipped: jq failed to encode chain\n' >&2
    }
    # (c) Monotonic floor vs the completion hook's on-disk progress: when the
    # chain is unchanged, union the computed prefix with the existing
    # .completed. A prompt that re-anchors EARLIER in the same chain (e.g.
    # "merge PR49" matching the review trigger after verification already
    # ran) must not truncate recorded progress — that re-arms the push gate
    # against already-reviewed work. Chain switch and pure-cancel remain the
    # only resets. Fail-open: missing/malformed prior state, or jq failure,
    # degrades to the prefix-only write. current_index intentionally stays
    # the anchor index (display semantics); the push gate keys off
    # .completed only.
    if [[ -n "$_comp_chain" ]]; then
      _prev_state="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
      if [[ -f "$_prev_state" ]]; then
        _merged="$(jq -n --argjson chain "$_comp_chain" \
                         --argjson completed "$_comp_completed" \
                         --slurpfile prev "$_prev_state" '
          ($prev[0] // {}) as $p |
          if ($p.chain // []) == $chain then
            ($completed + ($p.completed // [])) as $u |
            [ $chain[] | select(. as $x | $u | index($x) != null) ]
          else $completed end
        ' 2>/dev/null)" || _merged=""
        [[ -n "$_merged" ]] && _comp_completed="$_merged"
      fi
      jq -n --argjson chain "$_comp_chain" \
            --argjson completed "$_comp_completed" \
            --argjson idx "${_current_idx:-0}" \
            '{chain:$chain, current_index:$idx, completed:$completed, updated_at:now|todate}' \
        > "${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}" 2>/dev/null || true
    fi
  fi
}

# --- _emit_explain ------------------------------------------------
# Emits structured routing explanation to stderr when SKILL_EXPLAIN=1.
# Input globals: PROMPT, _EXPLAIN_SCORING, _EXPLAIN_CAPS, TOTAL_COUNT, PLABEL, PRIMARY_PHASE
_emit_explain() {
  [[ -z "${SKILL_EXPLAIN:-}" ]] && return

  {
    printf '[skill-hook] === EXPLAIN ===\n'
    printf '[skill-hook] Prompt: "%s"\n' "$PROMPT"
    printf '[skill-hook] Scoring:\n'
    if [[ -n "${_EXPLAIN_SCORING:-}" ]]; then
      printf '%s' "$_EXPLAIN_SCORING"
    else
      printf '[skill-hook]   (no skills evaluated)\n'
    fi
    printf '[skill-hook] Role-cap selection (max=%s):\n' "$MAX_SUGGESTIONS"
    if [[ -n "${_EXPLAIN_CAPS:-}" ]]; then
      printf '%s' "$_EXPLAIN_CAPS"
    else
      printf '[skill-hook]   (none selected)\n'
    fi
    printf '[skill-hook] Result: %s skills | %s | phase=%s\n' "$TOTAL_COUNT" "${PLABEL:-}" "${PRIMARY_PHASE:-}"
    # Raw scores from SORTED (format: score|name|role|invoke|phase per line)
    local _raw_scores=""
    if [[ -n "${SORTED:-}" ]]; then
      while IFS='|' read -r _sc _nm _rest; do
        [[ -z "$_nm" ]] && continue
        _raw_scores="${_raw_scores:+${_raw_scores} }${_nm}=${_sc}"
      done <<EOF
${SORTED}
EOF
    fi
    printf '[skill-hook] Raw scores: %s\n' "${_raw_scores:-(none)}"
    printf '[skill-hook] === END ===\n'
  } >&2
}

# =================================================================
# CONVERSATION-DEPTH COUNTER
# =================================================================
# Track how many prompts have been sent to reduce verbosity over time.
# File: $HOME/.claude/.skill-prompt-count
# SKILL_VERBOSE=1 forces full output regardless of depth.
# _SESSION_TOKEN is read near the top of the file (before early-exit gates).
_PROMPT_COUNT_FILE="${HOME}/.claude/.skill-prompt-count-${_SESSION_TOKEN:-default}"
_PROMPT_COUNT=1
if [[ -f "$_PROMPT_COUNT_FILE" ]]; then
  _prev="$(cat "$_PROMPT_COUNT_FILE" 2>/dev/null)"
  if [[ "$_prev" =~ ^[0-9]+$ ]]; then
    _PROMPT_COUNT=$((_prev + 1))
  fi
fi
printf '%s' "$_PROMPT_COUNT" > "$_PROMPT_COUNT_FILE" 2>/dev/null || true

# SKILL_VERBOSE=1 overrides depth — treat as prompt 1
if [[ -n "${SKILL_VERBOSE:-}" ]] && [[ "${SKILL_VERBOSE:-}" == "1" ]]; then
  _PROMPT_COUNT=1
fi

# =================================================================
# MAIN FLOW
# =================================================================

# --- Prepare skill data for scoring ---
# Use jq to iterate available+enabled skills, test each trigger regex
# against the lowercased prompt, compute scores, and return sorted results.
#
# Score formula: sum(trigger_scores) + priority + name_boost
# Per-trigger: 30 for word-boundary match, 10 for substring match (accumulated, not max).

# Single jq call extracts all enabled skills (replaces ~80 per-skill jq forks with 1).
# Format: name<US>name_lower<US>role<US>priority<US>invoke<US>phase<US>triggers
# US (\x1f) as field separator (non-whitespace, so empty fields survive IFS splitting).
# SOH (\x01) as intra-field trigger delimiter.
DELIM=$'\x01'
FS=$'\x1f'
SKILL_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  [.skills[] | select(.available == true and .enabled == true)] | .[] |
  (.name + "\u001f" + (.name | ascii_downcase) + "\u001f" + .role + "\u001f" +
   (.priority // 0 | tostring) + "\u001f" + (.invoke // "SKIP") + "\u001f" +
   (.phase // "") + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" + ((.keywords // []) | join("\u0001")) + "\u001f" + (.required_when // ""))
' 2>/dev/null)"

# --- Score, select, label, build, compose, format ---
_score_skills
_apply_context_bonus
_apply_sticky_composition

# --- Compute tentative phase for required-role pass 0 ---
# Priority: process > workflow > domain > first required skill.
# Required skills are only used as last resort (when all scored skills are required).
_TENTATIVE_PHASE=""
_TENTATIVE_PHASE_REQUIRED=""
while IFS='|' read -r _tp_score _tp_name _tp_role _tp_invoke _tp_phase; do
  [[ -z "$_tp_name" ]] && continue
  if [[ "$_tp_role" == "process" ]]; then
    _TENTATIVE_PHASE="$_tp_phase"
    break
  fi
  if [[ "$_tp_role" == "required" ]]; then
    # Track first required phase as last-resort fallback
    [[ -z "$_TENTATIVE_PHASE_REQUIRED" ]] && _TENTATIVE_PHASE_REQUIRED="$_tp_phase"
    continue
  fi
  [[ -z "$_TENTATIVE_PHASE" ]] && _TENTATIVE_PHASE="$_tp_phase"
done <<EOF
${SORTED}
EOF
# Last resort: if only required skills scored, use their phase
[[ -z "$_TENTATIVE_PHASE" ]] && _TENTATIVE_PHASE="$_TENTATIVE_PHASE_REQUIRED"

_select_by_role_caps
_determine_label_phase

# =================================================================
# METHODOLOGY HINTS
# =================================================================
# Single jq call extracts all hint data (replaces ~9 per-hint jq forks with 1)
HINTS=""
HINTS_DATA="$(printf '%s' "$REGISTRY" | jq -r '
  (.plugins // []) as $plugins |
  .methodology_hints // [] | .[] |
  # Gate plugin-scoped hints on plugin availability
  (if .plugin then
    (.plugin as $p | [$plugins[] | select(.name == $p and .available == true)] | length > 0)
  else true end) as $available |
  select($available) |
  ((.skill // "") + "\u001f" + .hint + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" + ((.phases // []) | join("\u0001")))
' 2>/dev/null)"

while IFS="$FS" read -r hint_skill hint_text hint_triggers_joined hint_phases_joined; do
  [[ -z "$hint_text" ]] && continue

  # Suppress hint if its associated skill is already selected
  if [[ -n "$hint_skill" ]] && printf '%s' "$SELECTED" | grep -qF "|${hint_skill}|"; then
    continue
  fi

  # Phase-scope check: if hint has phases, PRIMARY_PHASE must match one
  if [[ -n "$hint_phases_joined" ]] && [[ -n "$PRIMARY_PHASE" ]]; then
    _phase_match=0
    _hp_remaining="$hint_phases_joined"
    while [[ -n "$_hp_remaining" ]]; do
      if [[ "$_hp_remaining" == *"${DELIM}"* ]]; then
        _hp="${_hp_remaining%%${DELIM}*}"
        _hp_remaining="${_hp_remaining#*${DELIM}}"
      else
        _hp="$_hp_remaining"
        _hp_remaining=""
      fi
      [[ -z "$_hp" ]] && continue
      if [[ "$_hp" == "$PRIMARY_PHASE" ]]; then
        _phase_match=1
        break
      fi
    done
    [[ "$_phase_match" -eq 0 ]] && continue
  fi

  # Test hint triggers against prompt
  if [[ -n "$hint_triggers_joined" ]]; then
    _remaining="$hint_triggers_joined"
    while [[ -n "$_remaining" ]]; do
      if [[ "$_remaining" == *"${DELIM}"* ]]; then
        htrigger="${_remaining%%${DELIM}*}"
        _remaining="${_remaining#*${DELIM}}"
      else
        htrigger="$_remaining"
        _remaining=""
      fi
      [[ -z "$htrigger" ]] && continue
      if [[ "$P" =~ $htrigger ]]; then
        HINTS="${HINTS}
- ${hint_text}"
        break
      fi
    done
  fi
done <<EOF
${HINTS_DATA}
EOF

# =================================================================
# PHASE COMPOSITION: PARALLEL / SEQUENCE / HINTS
# =================================================================
COMPOSITION_LINES=""
COMPOSITION_HINTS=""

# Determine the current phase from selected skills (use PRIMARY_PHASE)
CURRENT_PHASE="$PRIMARY_PHASE"

# Single jq call computes all composition output (replaces ~20-30 per-entry jq forks with 1)
if [[ -n "$CURRENT_PHASE" ]]; then
  _comp_output="$(printf '%s' "$REGISTRY" | jq -r --arg ph "$CURRENT_PHASE" '
    [.plugins // [] | .[] | select(.available == true) | .name] as $avail |
    .phase_compositions[$ph] // empty |
    (
      (.parallel // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "LINE:  PARALLEL: \(.use) -> \(.purpose) [\(.plugin)]"
        elif .gate then
          "GATED:\(.gate):\(.marker // ""):\(.artifacts // [] | join(",")):\("  PARALLEL: \(.use) \u2014 \(.purpose)")"
        else
          "LINE:  PARALLEL: \(.use) \u2014 \(.purpose)"
        end),
      (.sequence // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "LINE:  SEQUENCE: \(.use // .step) -> \(.purpose) [\(.plugin)]"
        elif .gate then
          "GATED:\(.gate):\(.marker // ""):\(.artifacts // [] | join(",")):\("  SEQUENCE: \(.step) -> \(.purpose)")"
        else
          "LINE:  SEQUENCE: \(.step) -> \(.purpose)"
        end),
      (.hints // [] | .[] |
        if .plugin then
          select(.plugin as $p | $avail | any(. == $p)) |
          "HINT:\(.text)"
        else
          "HINT:\(.text)"
        end)
    )
  ' 2>/dev/null)"

  _TDD_EMITTED=0
  while IFS= read -r _cline; do
    [[ -z "$_cline" ]] && continue
    case "$_cline" in
      GATED:*)
        # Parse gate metadata: GATED:type:marker:artifacts:line
        _gate_rest="${_cline#GATED:}"
        _gate_type="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_marker="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_artifacts="${_gate_rest%%:*}"; _gate_rest="${_gate_rest#*:}"
        _gate_line="${_gate_rest}"

        _gate_pass=1
        case "$_gate_type" in
          session-marker)
            [[ -f "${HOME}/.claude/.skill-${_gate_marker}-${_SESSION_TOKEN:-default}" ]] && _gate_pass=0
            ;;
          artifact-presence)
            _gate_pass=0
            _saved_IFS="$IFS"; IFS=','
            set -f  # disable globbing during IFS split
            for _gpat in $_gate_artifacts; do
              IFS="$_saved_IFS"
              set +f
              [[ -z "$_gpat" ]] && continue
              [[ -n "$(compgen -G "${_PROJECT_ROOT}/${_gpat}" 2>/dev/null)" ]] && { _gate_pass=1; break; }
            done
            set +f
            IFS="$_saved_IFS"
            ;;
        esac
        [[ -n "${SKILL_EXPLAIN:-}" ]] && echo "[skill-hook]   [gate] ${_gate_type}: pass=${_gate_pass} root=${_PROJECT_ROOT}" >&2

        if [[ "$_gate_pass" -eq 1 ]]; then
          COMPOSITION_LINES="${COMPOSITION_LINES}
${_gate_line}"
        fi
        ;;
      LINE:*)
        COMPOSITION_LINES="${COMPOSITION_LINES}
${_cline#LINE:}"
        # Track if TDD was emitted from jq composition
        case "${_cline}" in *test-driven-development*) _TDD_EMITTED=1 ;; esac
        ;;
      HINT:*)  COMPOSITION_HINTS="${COMPOSITION_HINTS}
- ${_cline#HINT:}" ;;
    esac
  done <<EOF
${_comp_output}
EOF
fi

# Fallback: ensure TDD PARALLEL is present for IMPLEMENT/DEBUG even without jq composition
case "${CURRENT_PHASE:-}" in
  IMPLEMENT|DEBUG)
    if [[ "${_TDD_EMITTED:-0}" -eq 0 ]]; then
      COMPOSITION_LINES="${COMPOSITION_LINES}
  PARALLEL: test-driven-development -> Skill(superpowers:test-driven-development) — INVOKE before writing production code"
    fi
    ;;
esac

# --- Build skill display lines and walk composition chain ---
_build_skill_lines
_walk_composition_chain

# =================================================================
# RED FLAGS: Phase-aware enforcement checklists
# =================================================================
RED_FLAGS=""
case "${PRIMARY_PHASE}" in
  DISCOVER)
    RED_FLAGS="
HALT if any Red Flag is true:
- Skipping Jira/Confluence context pull when Atlassian Rovo MCP is connected (prefer 'search' for cross-system scoping)
- Jumping to design without presenting a discovery brief
- Writing code during the DISCOVER phase"
    ;;
  DESIGN)
    RED_FLAGS="
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:brainstorming)
- Skipping design presentation and user approval
- Jumping to writing code without exploring approaches first
- Not writing a design doc before transitioning to PLAN"
    ;;
  PLAN)
    RED_FLAGS="
HALT if any Red Flag is true:
- Editing implementation files before invoking Skill(superpowers:writing-plans)
- Implementing without an approved plan document
- Skipping TDD steps in the plan
- Not saving the plan to docs/plans/ before executing"
    ;;
  IMPLEMENT)
    RED_FLAGS="
HALT if any Red Flag is true:
- Implementing on main without setting up a git worktree first
- Skipping TDD: writing implementation before writing the failing test
- Not following the plan step by step
- Jumping to SHIP without going through REVIEW (requesting-code-review) first
- Not using subagent-driven-development or agent-team-execution for parallelizable tasks"
    ;;
  REVIEW)
    RED_FLAGS="
HALT if any Red Flag is true:
- Summarizing changes instead of dispatching superpowers:code-reviewer subagent
- Not providing BASE_SHA and HEAD_SHA git diff range to the reviewer
- Claiming review is complete without acting on critical/important findings
- Skipping security-scanner during review (Invoke Skill(auto-claude-skills:security-scanner) for deterministic scanning)"
    ;;
  LEARN)
    RED_FLAGS="
HALT if any Red Flag is true:
- Creating Jira follow-up tickets via Atlassian Rovo MCP without user approval
- Skipping metrics analysis and going straight to recommendations
- Editing code during the LEARN phase"
    ;;
esac

# SHIP: verification-specific RED FLAGS (appended, not replaced)
if printf '%s' "${SELECTED}${OVERFLOW_WORKFLOW}" | grep -q 'verification-before-completion'; then
  RED_FLAGS="${RED_FLAGS}
HALT if any Red Flag is true:
- Claiming 'tests pass' without showing test runner output
- Claiming 'everything works' without running verification commands
- Referencing files that were never read with the Read tool
- Claiming to have executed commands without Bash tool calls in this conversation
- Saying 'no changes needed' on code the user flagged as broken
- Skipping verification steps listed in the skill
- Generating placeholder/stub/TODO implementations as final output"
fi

if [[ -n "$RED_FLAGS" ]]; then
  SKILL_LINES="${SKILL_LINES}${RED_FLAGS}"
fi

# =================================================================
# DESIGN COMPLETENESS: PLAN-phase contract guard
# Closes DESIGN->PLAN contract loop. Reads the active change's
# design_path from session state and grep-checks for three canonical
# section headers. Advisory-only (emits hint, does not deny).
# Fail-open on every sub-check: missing state file, missing key,
# missing design file, or grep errors all degrade silently.
# =================================================================
if [[ "${PRIMARY_PHASE}" == "PLAN" ]] && [[ -n "${_SESSION_TOKEN:-}" ]]; then
  _STATE_FILE="${HOME}/.claude/.skill-openspec-state-${_SESSION_TOKEN}"
  _DP_DESIGN=""
  if [[ -f "$_STATE_FILE" ]] && jq empty "$_STATE_FILE" >/dev/null 2>&1; then
    # Batched into one jq call: count candidates and pick first.
    _DP_PAIR="$(jq -r '
      [.changes // {} | to_entries[]
        | select(.value.design_path != null and .value.design_path != "")
        | select(.value.archived_at == null)
        | .value.design_path] as $dps |
      ($dps | length | tostring) + "\t" + ($dps[0] // "")
    ' "$_STATE_FILE" 2>/dev/null)"
    _DP_COUNT="${_DP_PAIR%%$'\t'*}"
    _DP_DESIGN="${_DP_PAIR#*$'\t'}"
    if [[ "${_DP_COUNT:-0}" -gt 1 ]] && [[ -n "${SKILL_EXPLAIN:-}" ]]; then
      echo "[skill-hook]   [design-guard] WARN ${_DP_COUNT} open changes with design_path; picked first (${_DP_DESIGN})" >&2
    fi
  fi

  if [[ -n "$_DP_DESIGN" ]]; then
    DESIGN_COMPLETENESS=""
    if [[ ! -f "$_DP_DESIGN" ]]; then
      DESIGN_COMPLETENESS="
DESIGN COMPLETENESS:
  ! design file unreadable at ${_DP_DESIGN} — cannot verify DESIGN→PLAN contract.
Action: confirm the design_path or re-run the design step before invoking Skill(superpowers:writing-plans)."
      [[ -n "${SKILL_EXPLAIN:-}" ]] && \
        echo "[skill-hook]   [design-guard] unreadable: ${_DP_DESIGN}" >&2
    else
      # Tolerant match: h2/h3 only, case-insensitive, space-or-hyphen
      # word joins, prefix/suffix text allowed (e.g. "## Out of Scope",
      # "### Capabilities affected", "## 🚫 Acceptance Scenarios").
      # h4+, body-text mentions, and leading whitespace before ##
      # intentionally do not count.
      _DC_CAPS=0; _DC_OOS=0; _DC_ACC=0; _DC_ACC_HEAD=0; _DC_GWT=""; _DC_GWT_CLOSED=""; _DC_GWT_FILE=""
      grep -Eiq '^#{2,3} .*capabilities[- ]affected' "$_DP_DESIGN" 2>/dev/null && _DC_CAPS=1
      grep -Eiq '^#{2,3} .*out[- ]of[- ]scope'       "$_DP_DESIGN" 2>/dev/null && _DC_OOS=1
      grep -Eiq '^#{2,3} .*acceptance[- ]scenarios'  "$_DP_DESIGN" 2>/dev/null && _DC_ACC_HEAD=1
      _DC_ACC=$_DC_ACC_HEAD

      # G/W/T body check (validation-contract-hardening): the DESIGN->PLAN
      # contract promises 2-4 GIVEN/WHEN/THEN scenarios, so a bare heading
      # must not satisfy the check. When the heading exists, one awk pass
      # counts uppercase GIVEN/WHEN/THEN tokens inside the section (until
      # the next h2/h3; h4+ subsections stay inside). Case-sensitive so
      # lowercase prose ("when the user...") never counts. Contract holds
      # at min(GIVEN,WHEN,THEN) >= 2; upper bound not enforced. Counting
      # is per-line (a line with two full scenarios counts once; tokens on
      # the heading line are skipped) — an undercount can only make the
      # advisory stricter, never block. h3 sub-headings CLOSE the section
      # (h2/h3 are section boundaries per the heading grammar above) —
      # deliberate deny-bias: scenarios grouped under h3 trip the advisory
      # rather than risk counting a neighboring section (use h4
      # "#### Scenario:" grouping, the OpenSpec convention); early
      # closures are surfaced as gwt_closed_by_heading in the
      # SKILL_EXPLAIN breadcrumb so a false advisory is debuggable.
      # Fail-open: awk failure or non-numeric output degrades to heading
      # semantics.
      if [[ $_DC_ACC_HEAD -eq 1 ]]; then
        # Output: "<in-section min> <early closures> <file-wide min>".
        # file-wide min >= 2 while in-section < 2 means the scenarios
        # exist but sit outside the section (typically h3 sub-grouping)
        # -> the advisory carries a placement remedy instead of a bare
        # "write scenarios" instruction.
        _DC_GWT_PAIR="$(awk '
          {
            if ($0 ~ /(^|[^A-Za-z])GIVEN([^A-Za-z]|$)/) fg++
            if ($0 ~ /(^|[^A-Za-z])WHEN([^A-Za-z]|$)/)  fw++
            if ($0 ~ /(^|[^A-Za-z])THEN([^A-Za-z]|$)/)  ft++
          }
          /^##/ && !/^####/ {
            if (inacc && tolower($0) !~ /acceptance[- ]scenarios/) closed++
            inacc = (tolower($0) ~ /acceptance[- ]scenarios/) ? 1 : 0
            next
          }
          inacc {
            if ($0 ~ /(^|[^A-Za-z])GIVEN([^A-Za-z]|$)/) g++
            if ($0 ~ /(^|[^A-Za-z])WHEN([^A-Za-z]|$)/)  w++
            if ($0 ~ /(^|[^A-Za-z])THEN([^A-Za-z]|$)/)  t++
          }
          END {
            m = g + 0; if (w + 0 < m) m = w + 0; if (t + 0 < m) m = t + 0
            fm = fg + 0; if (fw + 0 < fm) fm = fw + 0; if (ft + 0 < fm) fm = ft + 0
            print m, closed + 0, fm
          }
        ' "$_DP_DESIGN" 2>/dev/null || true)"
        read -r _DC_GWT _DC_GWT_CLOSED _DC_GWT_FILE <<< "$_DC_GWT_PAIR" || true
        if [[ "$_DC_GWT" =~ ^[0-9]+$ ]] && [[ "$_DC_GWT" -lt 2 ]]; then
          _DC_ACC=0
        fi
      fi

      # Spec-path fallback (design-guard-spec-path): in spec-driven mode the
      # scenarios live in sibling specs/<cap>/spec.md files, not design.md —
      # without this, [OK] is unreachable for spec-driven changes (measured:
      # 8/10 real docs permanently [X] in the PR #105 dogfood). Satisfied
      # when sibling specs carry >=2 aggregated WHEN/THEN pairs. NOTE the
      # deliberate threshold divergence from the design-file check above:
      # that one requires min(GIVEN,WHEN,THEN); this one only
      # min(WHEN,THEN), because the OpenSpec scenario template makes GIVEN
      # optional — if that policy changes, change BOTH blocks. Strictly
      # additive: only flips [X]->[OK]; any error path (no specs dir,
      # empty glob, awk failure, non-numeric output) degrades to the
      # design-file verdict above. Empty-glob mechanics: bash 3.2 has no
      # nullglob here, so a matchless glob reaches cat as a literal path —
      # the resulting ENOENT is intentionally absorbed by 2>/dev/null and
      # `|| true`, not an oversight.
      _DC_ACC_SPECS=0; _DC_SPEC_WT=""
      if [[ $_DC_ACC -eq 0 ]]; then
        _DP_DIR="${_DP_DESIGN%/*}"
        if [[ -d "${_DP_DIR}/specs" ]]; then
          _DC_SPEC_WT="$(cat "${_DP_DIR}"/specs/*/spec.md 2>/dev/null | awk '
            {
              if ($0 ~ /(^|[^A-Za-z])WHEN([^A-Za-z]|$)/) w++
              if ($0 ~ /(^|[^A-Za-z])THEN([^A-Za-z]|$)/) t++
            }
            END { m = w + 0; if (t + 0 < m) m = t + 0; print m }
          ' 2>/dev/null || true)"
          if [[ "$_DC_SPEC_WT" =~ ^[0-9]+$ ]] && [[ "$_DC_SPEC_WT" -ge 2 ]]; then
            _DC_ACC=1
            _DC_ACC_SPECS=1
          fi
        fi
      fi

      # [i]-only numeric-bar nudge: advisory, never affects the verdict.
      # ERE avoids \b (BSD grep) and PCRE (Bash 3.2 gotcha); grep failure
      # degrades to the advisory line, never a block.
      _DC_BAR=0
      grep -Eiq '[0-9]+(\.[0-9]+)? ?(%|ms|sec|tokens?)|[0-9]+s($|[^a-z])|p(50|90|95|99)|threshold|>=|<=' "$_DP_DESIGN" 2>/dev/null && _DC_BAR=1
      _DC_LINE_BAR=""
      if [[ $_DC_BAR -eq 0 ]]; then
        _DC_LINE_BAR='
  [i]  No numeric bar found — if success is measurable (latency, %, tokens, pass-rate), state the threshold (advisory only)'
      fi

      if [[ $_DC_CAPS -eq 1 ]] && [[ $_DC_OOS -eq 1 ]] && [[ $_DC_ACC -eq 1 ]]; then
        # Keep the sibling-specs annotation on the summary line too — the
        # design file itself does NOT contain the scenarios in that case.
        _DC_ALL_SUFFIX=""
        [[ ${_DC_ACC_SPECS:-0} -eq 1 ]] && _DC_ALL_SUFFIX="; acceptance in sibling specs/"
        DESIGN_COMPLETENESS="
DESIGN COMPLETENESS: all sections present (${_DP_DESIGN}${_DC_ALL_SUFFIX})${_DC_LINE_BAR}"
      else
        if [[ $_DC_CAPS -eq 1 ]]; then
          _DC_LINE_CAPS='  [OK] Capabilities Affected'
        else
          _DC_LINE_CAPS='  [X]  Capabilities Affected (missing — add `## Capabilities Affected` section)'
        fi
        if [[ $_DC_OOS -eq 1 ]]; then
          _DC_LINE_OOS='  [OK] Out-of-Scope'
        else
          _DC_LINE_OOS='  [X]  Out-of-Scope (missing — add `## Out-of-Scope` section)'
        fi
        if [[ $_DC_ACC -eq 1 ]] && [[ ${_DC_ACC_SPECS:-0} -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios (in sibling specs/)'
        elif [[ $_DC_ACC -eq 1 ]]; then
          _DC_LINE_ACC='  [OK] Acceptance Scenarios'
        elif [[ $_DC_ACC_HEAD -eq 1 ]]; then
          if [[ "${_DC_GWT_FILE:-}" =~ ^[0-9]+$ ]] && [[ "$_DC_GWT_FILE" -ge 2 ]]; then
            _DC_LINE_ACC='  [X]  Acceptance Scenarios (heading present but <2 GIVEN/WHEN/THEN scenarios in the section — scenarios exist elsewhere in the doc; keep them directly under the heading (h2/h3 headings end the section) or use "#### Scenario:" (h4) sub-grouping)'
          else
            _DC_LINE_ACC='  [X]  Acceptance Scenarios (heading present but <2 GIVEN/WHEN/THEN scenarios — write 2-4 concrete GIVEN/WHEN/THEN scenarios)'
          fi
        else
          _DC_LINE_ACC='  [X]  Acceptance Scenarios (missing — add `## Acceptance Scenarios` section)'
        fi
        DESIGN_COMPLETENESS="
DESIGN COMPLETENESS (${_DP_DESIGN}):
${_DC_LINE_CAPS}
${_DC_LINE_OOS}
${_DC_LINE_ACC}${_DC_LINE_BAR}
Action: complete the missing section(s) before invoking Skill(superpowers:writing-plans)."
      fi
      [[ -n "${SKILL_EXPLAIN:-}" ]] && \
        echo "[skill-hook]   [design-guard] caps=${_DC_CAPS} oos=${_DC_OOS} acc=${_DC_ACC} gwt=${_DC_GWT:-n/a} gwt_closed_by_heading=${_DC_GWT_CLOSED:-n/a} gwt_filewide=${_DC_GWT_FILE:-n/a} gwt_specs=${_DC_SPEC_WT:-n/a} bar=${_DC_BAR} path=${_DP_DESIGN}" >&2
    fi

    SKILL_LINES="${SKILL_LINES}${DESIGN_COMPLETENESS}"
  fi
fi

# =================================================================
# INTENT EXTRACTION: DESIGN-phase pre-brainstorming directive.
# Hook-resident (not a config hint) because emission is state-gated:
#   confirmed-intent marker present -> handoff (Scenario 3) + suppress (Scenario 2, intent case)
#   discovery brief in openspec state -> suppress directive (Scenario 2, brief case)
#   otherwise -> emit directive (Scenario 1)
# Advisory-only; fail-open on every sub-check. Mechanical asks do not
# reach DESIGN phase, and the directive prose tells the model to skip
# them. See docs/plans/2026-06-26-intent-extraction-directive-plan.md.
# =================================================================
if [[ "${PRIMARY_PHASE}" == "DESIGN" ]]; then
  # Read confirmed-intent marker via lib helper (DRY: path lives in openspec-state.sh).
  # Requires a session token to locate the marker file; without a token
  # we can't check state, so we default to Scenario 1 (emit directive).
  _INTENT_TEXT=""
  _BRIEF_PRESENT=0
  if [[ -n "${_SESSION_TOKEN:-}" ]]; then
    if ! command -v openspec_state_read_intent >/dev/null 2>&1; then
      . "${PLUGIN_ROOT}/hooks/lib/openspec-state.sh" 2>/dev/null || true
    fi
    _INTENT_TEXT="$(command -v openspec_state_read_intent >/dev/null 2>&1 && openspec_state_read_intent "${_SESSION_TOKEN}" 2>/dev/null || true)"

    # Discovery brief present? (any non-archived change with a readable discovery_path)
    _IE_STATE="${HOME}/.claude/.skill-openspec-state-${_SESSION_TOKEN}"
    if [[ -f "$_IE_STATE" ]] && jq empty "$_IE_STATE" >/dev/null 2>&1; then
      _BRIEF_CT="$(jq -r '
        [.changes // {} | to_entries[]
          | select(.value.archived_at == null)
          | select((.value.discovery_path // "") != "")] | length
      ' "$_IE_STATE" 2>/dev/null)"
      [[ "${_BRIEF_CT:-0}" =~ ^[0-9]+$ ]] && [[ "${_BRIEF_CT}" -gt 0 ]] && _BRIEF_PRESENT=1
    fi
  fi

  if [[ -n "$_INTENT_TEXT" ]]; then
    # Scenario 3: handoff. Suppress the directive; reference confirmed intent.
    SKILL_LINES="${SKILL_LINES}
CONFIRMED INTENT (from earlier extraction): ${_INTENT_TEXT}
Brainstorming MUST build on this confirmed intent and out-of-scope boundary — do not re-elicit it from scratch."
    [[ -n "${SKILL_EXPLAIN:-}" ]] && echo "[skill-hook]   [intent-extraction] handoff: intent present" >&2
  elif [[ "$_BRIEF_PRESENT" -eq 1 ]]; then
    # Scenario 2: brief exists -> suppress (brainstorming uses the brief).
    [[ -n "${SKILL_EXPLAIN:-}" ]] && echo "[skill-hook]   [intent-extraction] suppressed: discovery brief present" >&2
    :
  else
    # Scenario 1: no intent, no brief (or no token) -> emit the directive.
    SKILL_LINES="${SKILL_LINES}
INTENT EXTRACTION: If your ask is underspecified (missing one or more of who/why/success-criteria/constraints), do NOT propose approaches, designs, or options yet. First run a one-question-at-a-time intent pass: ask ONE question at a time, track your confidence (low/med/high) in the real goal, and include a \"what would you actually want if this worked perfectly?\" probe for the underlying need (not just the literal request). Then, as soon as the user has given you enough to act on, you MUST — BEFORE proposing ANY approach, design, or option — emit this convergence block verbatim and stop for confirmation:
  **Confirmed intent:** <one line capturing who/why/success>
  **Out-of-scope:** <what this is explicitly NOT>
Only AFTER the user confirms that block may you propose approaches. Then persist it by running \`source \"\$CLAUDE_PLUGIN_ROOT/hooks/lib/openspec-state.sh\" && openspec_state_set_intent \"\$TOKEN\" \"<confirmed intent> :: out-of-scope: <...>\"\`. SKIP this pass entirely if the ask is already fully specified, is mechanical (rename/typo/file-move), or an approved discovery brief already covers intent."
    [[ -n "${SKILL_EXPLAIN:-}" ]] && echo "[skill-hook]   [intent-extraction] emitted directive (no intent, no brief)" >&2
  fi
fi

# --- PHASE REALITY: advisory-only reconciliation of claimed SHIP vs repo state.
# Advisory only (never blocks); fail-open on every sub-check. SHIP-only: at
# REVIEW, requesting-code-review is the current step and a clean tree is usually
# benign recap, so both rules would false-fire there.
if [[ "${PRIMARY_PHASE}" == "SHIP" ]]; then
  _PR_MSG=""

  # Rule B (no committed work): 0 commits ahead of origin/main AND clean tree.
  # origin/main literal (matches openspec-guard.sh; robust on un-pushed branches).
  _PR_AHEAD="$(git -C "$_PROJECT_ROOT" rev-list --count origin/main..HEAD 2>/dev/null)"
  [[ "$_PR_AHEAD" =~ ^[0-9]+$ ]] || _PR_AHEAD=-1   # detached/no-origin/error => silent
  _PR_DIRTY="$(git -C "$_PROJECT_ROOT" status --porcelain 2>/dev/null)"
  if [[ "$_PR_AHEAD" -eq 0 ]] && [[ -z "$_PR_DIRTY" ]]; then
    _PR_MSG="${_PR_MSG}
  [i]  No committed work on this branch (0 commits ahead of origin/main, clean tree) — SHIP phase may be premature."
  fi

  # Rule A (chain skipped REVIEW): chain contains requesting-code-review but
  # .completed does not. Self-scoping (checks .chain membership). Token-rotation
  # safe: stale/foreign/empty state lacks the .chain member => silent.
  # NOTE: SILENT by design when no composition-state file exists (single/zero-skill
  # prompt, e.g. the no-chain "debugging an API key" case) — Rule B covers that.
  # Do not "fix" this silence.
  _PR_COMP="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN:-default}"
  if [[ -f "$_PR_COMP" ]] && \
     jq -e '((.chain // []) | index("requesting-code-review")) != null
            and ((.completed // []) | index("requesting-code-review")) == null' \
        "$_PR_COMP" >/dev/null 2>&1; then
    _PR_MSG="${_PR_MSG}
  [i]  Chain has not completed REVIEW (requesting-code-review not in .completed) — run it before SHIP."
  fi

  if [[ -n "$_PR_MSG" ]]; then
    SKILL_LINES="${SKILL_LINES}
PHASE REALITY:${_PR_MSG}"
  fi
  [[ -n "${SKILL_EXPLAIN:-}" ]] && \
    echo "[skill-hook]   [phase-reality] ahead=${_PR_AHEAD:-na} dirty=${_PR_DIRTY:+1} phase=${PRIMARY_PHASE}" >&2
fi

# Domain invocation instruction (composition-aware)
DOMAIN_HINT=""
if [[ "$DOMAIN_COUNT" -gt 0 ]] || [[ -n "$OVERFLOW_DOMAIN" ]]; then
  if [[ -n "$COMPOSITION_CHAIN" ]]; then
    DOMAIN_HINT="
Domain skills evaluated YES: invoke them during the current step."
  elif [[ -n "$PROCESS_SKILL" ]]; then
    DOMAIN_HINT="
Domain skills evaluated YES: invoke them (before, during, or after the process skill) -- do not just note them."
  else
    DOMAIN_HINT="
Domain skills evaluated YES: invoke them -- do not just note them."
  fi
fi

# --- Format and emit final JSON output ---
_format_output

# --- Emit SKILL_EXPLAIN diagnostic output (stderr) ---
_emit_explain
