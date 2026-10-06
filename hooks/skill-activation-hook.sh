#!/bin/bash
# --- Claude Code Skill Activation Hook v2 (config-driven) --------
# https://github.com/dkpapadopoulos/auto-claude-skills
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

# Background-task notifications arrive as UserPromptSubmit prompts made up entirely of
# <task-notification> blocks. They are not the user, and their summaries are ordinary
# words ("Capture a second, path-normalised baseline" routed to second-opinion, observed
# 2026-09-17), so they are not routed. The classifier is shared with
# egress-consent-turn-hook.sh (hooks/lib/task-notification.sh); without it every prompt
# is routed, as before. A prompt the classifier cannot evaluate is routed too, and so is
# every prompt when the lib's definition does not compile (the call is retried with the
# fallback below, so a lib whose jq does not compile cannot make this hook drop the
# user's prompt). The first kind the lib yields is used, and anything other than
# "notification" or "unclassifiable" counts as "prompt" (a kind containing US or several
# kinds would otherwise corrupt the field split).
TASK_NOTIFICATION_JQ_DEF=""
if [[ -f "${PLUGIN_ROOT}/hooks/lib/task-notification.sh" ]]; then
  # shellcheck source=lib/task-notification.sh
  . "${PLUGIN_ROOT}/hooks/lib/task-notification.sh" 2>/dev/null || TASK_NOTIFICATION_JQ_DEF=""
fi
_TN_FALLBACK_DEF='def notification_kind: "prompt";'
[[ -n "${TASK_NOTIFICATION_JQ_DEF}" ]] || TASK_NOTIFICATION_JQ_DEF="${_TN_FALLBACK_DEF}"

# Two more inputs reach UserPromptSubmit without having been typed by the user, and get no
# routing DISPLAY. Measured 2026-10-04 over 745 distinct non-human inputs from real
# transcripts: 111 got a routing block, 109 of them with a MUST INVOKE line — 80 of 84 peer
# messages and 29 of 29 notices-with-reminder (a hand-back saying "the test fails" was told
# to start systematic-debugging). After this change: 0 blocks, and routing state identical
# to before on all 745.
#   * a PEER MESSAGE: a prompt that opens with an <agent-message from="..."> tag (after the
#     optional harness intro line), contains exactly ONE closing tag, and has after it
#     nothing, or ONE LINE that opens like one of the two harness paragraphs and ends
#     "permission laundering.". "One line" means no vertical-space character at all: LF, CR,
#     VT, FF, NEL, U+2028, U+2029 (review found a request after U+2028 was swallowed when
#     only LF was excluded). Opening tags are not counted: a report that QUOTES an opening
#     tag in its body is still one message.
#   * a NOTICE WITH A REMINDER: what the shared classifier calls a notification, followed
#     only by <system-reminder> blocks (goal check-ins, background review notices).
# This is the ACTIVATION hook's own definition, on purpose. hooks/lib/task-notification.sh is
# shared with egress-consent-turn-hook.sh, where "not the user" keeps an egress approval
# alive; widening it there would lengthen approvals. Here a match means ONE thing: the
# final routing block is not printed. Scoring, the chain walk and every state write
# (composition state, prompt counter, zero-match counters, last-invoked) happen exactly as
# they did before this change — see _DISPLAY_SUPPRESS below for the bypass that an early
# exit caused. So a peer's message still arms a chain, as it always did (70 of the 745
# measured inputs do). Whether automated text SHOULD move a workflow is a separate
# question, and not one to answer by removing a gate's precondition.
# That is the whole consequence, so the looser shape is affordable. A text shape is not
# authenticated provenance: a user who pastes one of these verbatim gets no routing display
# for that prompt, and nothing else changes ([no-skills] already lets a user suppress it).
# Anything that is not exactly one of those shapes is the user: leading text, text on a line
# after the block or after the harness paragraph, two agent-message blocks, an empty `from`,
# a reminder with no notification before it. A prompt the regex engine cannot evaluate is
# the user too. Known residual: text appended on the SAME line as the harness paragraph and
# still ending "permission laundering." is not seen as the user.
# The harness paragraph is matched by its opening and closing words, not verbatim: two
# wordings were already observed in five weeks, and an exact match would silently stop
# recognising peer messages at the next rewording. If the opening or closing words change,
# the intro+paragraph form is routed again (the old behaviour); the bare-block form is not
# affected.
# The notice shape reuses notification_kind, so without the shared lib it cannot be
# recognised and is routed as before; the peer shape does not depend on the lib.
# COST. The prompt is cut with split() and every regex is anchored at the start of its input.
# That removes the one quadratic shape found; it is a bounded-regression claim pinned by a
# timing cell, not a proof of linearity. The first cut used an unanchored `sub(...+\s*$)` to strip the reminders:
# on a prompt of N spaces followed by a reminder tag that was quadratic (25k spaces 1.2 s,
# 50k 4.6 s, against 0.03 s before the change; found in review). `contains` runs first, so a
# prompt with neither closing tag costs no regex at all.
# Fixtures (live wrapper text): tests/fixtures/routing-input/. Regression:
# tests/test-activation-nonhuman-skip.sh.
_NONHUMAN_JQ_DEF='def acs_nonhuman:
  . as $p
  | try (
      if ($p | contains("</agent-message>")) then
        ($p | sub("^\\s+"; "") | ltrimstr("Another Claude session sent a message:") | sub("^\\s+"; "")
            | split("</agent-message>")) as $parts
        | ($parts | length) == 2
          and ($parts[0] | test("^<agent-message from=\"[^\"\\n]{1,200}\">"))
          and ($parts[1] | test("^\\s*(?:(?:That \"other Claude session\" is an agent working inside this same session|This came from another Claude session)[^\\n\\r\\x{0B}\\f\\x{85}\\x{2028}\\x{2029}]{0,1400}permission laundering\\.\\s*)?$"))
      elif ($p | contains("</task-notification>")) and ($p | contains("<system-reminder>")) then
        ($p | split("</task-notification>")) as $parts
        | ($parts[-1] | test("^\\s*(?:<system-reminder>(?:(?!</system-reminder>)[\\s\\S])*</system-reminder>\\s*)+$"))
          and (([first((($parts[:-1] | join("</task-notification>")) + "</task-notification>") | notification_kind)][0]) == "notification")
      else false end
    ) catch false;'

# Capture stdin once; extract the first payload's kind, then transcript_path and prompt,
# in the SAME single jq fork the prompt already cost (\x1f-joined; the prompt goes last
# because it may contain anything, and a kind cannot contain \x1f; a transcript_path
# containing one splits wrongly, as it always has). Several JSON values on stdin keep
# their previous meaning: one line per value, a value that raises an error is skipped,
# the call fails only if the LAST value fails (jq's own exit status), and the kind is
# computed on exactly the text the hook then uses as the prompt.
# Bounded, not unbounded (#188). A socket or FIFO on fd 0 is not a TTY, so an
# unbounded `cat` waits for an EOF that never arrives and this hook hangs
# forever — silently, reading as slowness rather than as a fault. `read -t`
# takes an integer in Bash 3.2, so the floor is one second, paid only when
# stdin is hostile or absent; in production the payload is written and the pipe
# closed, so data is available immediately. `$( )` strips trailing newlines
# exactly as `$(cat)` did, so the parsed payload is unchanged.
_HOOK_INPUT="$(
    _hs_line=""
    while IFS= read -r -t "${ACS_HOOK_STDIN_TIMEOUT:-2}" _hs_line; do
        printf '%s\n' "${_hs_line}"
        _hs_line=""
    done
    [ -n "${_hs_line}" ] && printf '%s' "${_hs_line}"
    exit 0
)" || _HOOK_INPUT=""
# If this hook's OWN definition ever fails to compile, classify nothing as non-human rather
# than drop the user's prompt: the last retry below swaps it for this.
_NH_FALLBACK_DEF='def acs_nonhuman: false;'
_fields_extract() {
  printf '%s' "${_HOOK_INPUT}" | jq -nr "$1 $2"' [inputs] as $all
    | [$all[] | try ([.transcript_path // "", .prompt // ""] | join("\u001f")) catch null] as $lines
    | if ($lines | length) > 0 and $lines[-1] == null then error("last value failed") else . end
    | ([$lines[] | select(. != null)] | join("\n")) as $joined
    | ($joined | split("\u001f") | .[1:] | join("\u001f")) as $text
    | ($text | [first(notification_kind)][0] | if . == "notification" or . == "unclassifiable" then . else "prompt" end) as $lib_kind
    | (if $lib_kind == "prompt" and ([first($text | acs_nonhuman)][0] == true) then "nonhuman" else $lib_kind end) as $kind
    | $kind + "\u001f" + $joined' 2>/dev/null
}
# Each retry gives up ONE definition, so a fault in one does not cost the other: first the
# hook's own (a pure task notification must still be recognised through the lib), then the
# lib's (a peer message must still be recognised without it), then both.
_FIELDS="$(_fields_extract "${TASK_NOTIFICATION_JQ_DEF}" "${_NONHUMAN_JQ_DEF}")" || _FIELDS=""
if [[ -z "${_FIELDS}" && -n "${_HOOK_INPUT}" ]]; then
  _FIELDS="$(_fields_extract "${TASK_NOTIFICATION_JQ_DEF}" "${_NH_FALLBACK_DEF}")" || _FIELDS=""
fi
if [[ -z "${_FIELDS}" && -n "${_HOOK_INPUT}" && "${TASK_NOTIFICATION_JQ_DEF}" != "${_TN_FALLBACK_DEF}" ]]; then
  _FIELDS="$(_fields_extract "${_TN_FALLBACK_DEF}" "${_NONHUMAN_JQ_DEF}")" || _FIELDS=""
  if [[ -z "${_FIELDS}" ]]; then
    _FIELDS="$(_fields_extract "${_TN_FALLBACK_DEF}" "${_NH_FALLBACK_DEF}")" || _FIELDS=""
  fi
fi
_PROMPT_KIND="${_FIELDS%%$'\x1f'*}"
_FIELDS="${_FIELDS#*$'\x1f'}"
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

# --- consultation-versus-development discrimination (contracts C2/C3) ----
#
# A consultation request asks ANOTHER MODEL for its view. It is phase-agnostic: it can
# happen during DESIGN, during REVIEW, or with no development work in flight at all.
# Measured before this guard existed: "ask codex to weigh in on this approach" started
# a full seven-step DESIGN->SHIP workflow, because `approach` matches brainstorming's
# trigger and brainstorming is a role=process skill, which is what
# _walk_composition_chain anchors on. The chain appeared because a development process
# skill co-selected -- NOT because any consultation skill declares a phase.
#
# The rule is deliberately NOT "suppress the chain on consultation prompts". design.md
# rejects that: it would strand a development session that pauses to consult. The rule
# is: do not START an unrelated workflow, and do not DISTURB one in progress.
#
# Both patterns are KNOWN-INCOMPLETE enumerations. Their failure directions are NOT the
# same, and an earlier version of this comment claimed they were:
#
#   _CONSULT_PARTICIPANT is a PRECONDITION -- a miss returns 1, the walker runs, and the
#   result is today's behaviour. Fails safe.
#   _DEV_WORK is a VETO -- a miss falls through to `return 0`, i.e. to SUPPRESSION.
#   Fails UNSAFE. Every verb missing from it turns a mixed request into a
#   consultation-only one.
#
# So the two lists carry different risk and deserve different bias: keep the participant
# list narrow, and keep the dev-work list GENEROUS.
#
# `agent`/`agents` is deliberately NOT accepted bare: it is this repo's own orchestration
# vocabulary, and "the other agent is stuck; take over and continue the plan" is a
# development prompt, not a consultation. It must be qualified by a model-ish word.
# Right boundary EXCLUDES _ . and - , matching the trigger regexes in
# config/default-triggers.json. With a bare [^a-z] this matched inside identifiers:
# measured, "make the client o3-compatible" and "bump the gpt-4-turbo timeout"
# read as consultation and SUPPRESSED the composition chain display, while a plain
# dev prompt rendered it. Display-only (state is still written, so the push gate is
# unaffected) but wrong, and the mismatch with the trigger boundary was the cause.
_CONSULT_PARTICIPANT='(^|[^a-z])(codex|gpt-?[0-9]|gemini|o3|chatgpt)($|[^a-z0-9_.-])|(another|other|second|different|independent|several|multiple|two|three|each) +([a-z]+ +)?(model|models|llm|llms)($|[^a-z])|(model|llm) +agents?($|[^a-z])|second opinion|(panel of models|model panel|standalone panel)'

# Development work the requester wants DONE, as opposed to an opinion they want heard.
# Its presence makes a request MIXED, and a mixed request keeps its chain.
#
# POSITIONAL, not vocabulary-presence, and that distinction is the whole design. A
# version of this matched a dev stem ANYWHERE in the prompt. Measured, it vetoed 7 of 7
# genuine consultations -- "what does codex think of the proposed FIX", "an opinion on
# the IMPLEMENTation tradeoffs", "a second opinion on the TEST strategy" -- because a
# consultation about engineering always names its subject. On the 50 held-out prompts it
# put spurious chains back to 7 of 7, exactly the no-guard number: the feature was inert
# while appearing to be implemented.
#
# Work is REQUESTED in three shapes, and mentioning a dev noun is none of them:
#   1. after a sequencing cue   -- "ask codex, THEN implement it"
#   2. as an opening imperative -- "build the thing, and ask codex what it thinks"
#   3. addressed at a participant -- "codex, optimize this algorithm"
# Shape 3 exists because those prompts delegate work rather than seek an opinion, and
# without it they classified as consultation-only.
#
# The failure direction is now affordable in a way it was not before: suppression is
# DISPLAY-only, so a missed veto hides a chain rather than disarming the push gate.
# That is what allows this rule to be precise instead of paranoid.
_DEV_VERB='(implement|build|writ|refactor|fix|migrat|renam|scaffold|deploy|rewrit|appl|add|updat|creat|chang|remov|delet|commit|push|ship|merg|execut|split|bump|revert|patch|optimi|harden|roll.?back)'
# The gap after a sequencing cue is `[^.!?]{0,60}`, not a couple of words: a cue is
# routinely followed by a whole clause -- "then ONCE WE'VE PICKED ONE, go implement it",
# "and after we decide, ACTUALLY apply the migration". A two-word window missed both,
# and punctuation broke the word-run besides. Stopping at sentence punctuation keeps the
# verb in the same clause as its cue, so a later unrelated sentence cannot veto.
_DEV_WORK="(then|and then|after (that|we|you|which)|once we|once you|afterwards|finally)[^.!?]{0,60}${_DEV_VERB}|^ *${_DEV_VERB}|(codex|gemini|gpt-?[0-9]|o3|chatgpt|model|llm)[ ,:]+ *(please +)?${_DEV_VERB}"

# True when the prompt asks for another model's input and asks for NO work to follow.
_prompt_is_consultation_only() {
  [[ "$P" =~ $_CONSULT_PARTICIPANT ]] || return 1
  [[ "$P" =~ $_DEV_WORK ]] && return 1
  return 0
}

# =================================================================
# EARLY EXITS
# =================================================================
[[ -z "$PROMPT" ]] && exit 0
# A background-task notification is not the user: no routing and no composition state
# (the session-token singleton above is re-stamped, as for every prompt).
if [[ "${_PROMPT_KIND}" == "notification" ]]; then
  [[ -n "${SKILL_DEBUG:-}" ]] && \
    printf '[skill-hook] prompt is a background-task notification; no routing emitted.\n' >&2
  exit 0
fi
# DISPLAY SUPPRESSION. Non-human input gets no routing block, and the rule is the one the
# consultation guard below learned the hard way: suppress what is DISPLAYED, never what is
# WRITTEN. Scoring, the chain walk and every state write run exactly as they would have;
# only the final print is skipped (see _format_output).
#
# The first cut stopped earlier -- an `exit 0` here -- and that also skipped the
# composition-state write. openspec-guard.sh runs its chain checks only when that file
# exists, so, measured with review evidence and a clean verdict in place,
# `git push origin HEAD` went DENY -> allow after a peer's work order and after a notice
# with a reminder. Review caught it before it was published.
# Regression at the GATE's decision, not at the state file:
# tests/test-push-gate-display-suppression.sh.
#
# A second use of this mechanism was built, measured and REMOVED: hiding the block on a plain
# question whose only process match was a trigger word. In its final, tight form it removed
# 2 of 83 wrong mandates on a held-out half and 8 of 90 on the development half, lost no
# right one and changed no state -- too small an effect for its heuristics, and every looser
# form that removed more also hid real work orders. The record, the three rules tried and
# the code (commit 7bdd2de2) are in docs/plans/2026-10-04-frontier-value-results.md, section 7.
# Anything that revives it MUST go through _DISPLAY_SUPPRESS, never through the scorer.
_DISPLAY_SUPPRESS=""
if [[ "${_PROMPT_KIND}" == "nonhuman" ]]; then
  _DISPLAY_SUPPRESS="non-human input"
fi

# STICKY REPEAT (#333). Once a prompt arms a composition chain, _apply_sticky_composition
# re-emits the chain's CURRENT step as MUST INVOKE on every later short prompt that selects
# no process skill of its own: "go", "yes" and "thanks" each get a multi-kilobyte block for
# a step the session has already been shown. Measured on five and a half weeks of real
# sessions, 92 of 451 mandated blocks on typed prompts were of that kind, and four of the
# 92 were followed by the mandated skill being invoked in the same turn.
#
# The RULE under test: a block is not displayed when ALL of these hold --
#   - its process mandate was injected by sticky composition (the prompt selected no
#     process skill of its own);
#   - it carries nothing else: the sticky step is the only skill in it. A short prompt can
#     still select a domain or workflow skill by its own words, and hiding the block would
#     hide that too (found in review);
#   - this session has already been shown that step, on this chain, since the user last
#     asked for a process step in their own words, and since the last compaction.
# It is a third use of _DISPLAY_SUPPRESS and obeys the same law: only the print is skipped.
# Scoring, the chain walk and every state write run as before. What HOLDS that is the
# turn-by-turn state identity in tests/test-activation-sticky-repeat.sh (cells ID, and X1's
# exit-early mutant). tests/test-push-gate-display-suppression.sh shows the gate's answer
# is unchanged after a hidden reply, but cannot by itself detect a hidden turn that skipped
# its state write: a hidden turn is never the one that armed the chain.
#
# It is NOT known to be an improvement. A repeated reminder may be what keeps an unfinished
# review in view, and nothing measured so far says otherwise. So it ships in SHADOW, and
# ACS_STICKY_REPEAT selects:
#   shadow   (default) display exactly as before; record what the rule WOULD hide
#   trial    hide in half the sessions, chosen by the session token and fixed for the
#            session; record the arm. This is the only mode that can show whether hiding
#            the reminder changes what gets done
#   suppress hide in every session
#   off      no rule, no record, no marker
# The default moves only on the two-stage verdict pre-registered in
# docs/plans/2026-10-05-routing-precision-prereg.md. An unrecognised value is shadow: a
# typo must never turn suppression on. The four words are matched in any letter case.
#
# What it keeps on disk is read by no gate and is deliberately OUTSIDE the `.skill-*` family:
# that family is routing state, which every display-suppression proof in this repository
# requires to be byte-identical whether or not a block was displayed. These record what
# was DISPLAYED, so they differ by design and must not be enumerated with it.
#   .sticky-repeat-shown-<token>  the chain this session is on, then the process steps it
#                                 has been shown on that chain, one per line. "Already
#                                 shown" is about an OBLIGATION, not a skill name. The
#                                 list starts again on another chain; when the user's own
#                                 words select a process step (a new task re-arms the same
#                                 chain, and its steps are owed their first display again);
#                                 on a cancel; and at a compaction, because the earlier
#                                 display may no longer be in the model's context
#                                 (pre-compact-hook.sh removes the file for manual AND auto
#                                 compaction; compact-recovery-hook.sh does again).
#   .sticky-repeat-shadow.d/      one small file per mandated block. No prompt text.
#
# HOW THEY ARE TOUCHED, because the first two cuts got this wrong (cross-family review):
#  - The marker is trusted for one thing: a line naming a step, under a first line naming
#    THIS chain, means that step was displayed. It is ignored -- which displays -- when it is
#    missing, unreadable, a symlink, for another chain, holds an over-long line, when no
#    chain was walked, or when ~/.claude is not writable (a compaction could not then have
#    removed it).
#  - Its read happens before the print and therefore before the state writes, and this
#    hook is killed after ten seconds (hooks.json), so the read must not be able to use
#    that up: it is opened read-write, which does not block on a FIFO; each read gives up
#    after one second; at most 64 lines of 1024 characters are read; and the whole loop
#    stops once two seconds have passed, so a FIFO fed slowly costs about three. That bounds
#    this read, not the hook: nothing reserves time for the state writes that follow, so a
#    hook already near its ten seconds for other reasons can still be killed before them.
#  - NOTHING IS MODIFIED IN PLACE. The marker is replaced by writing a new file that must
#    not already exist (noclobber) and renaming it over the old name; each record is its own
#    new file, created the same way. A rename changes a name, and an exclusive create makes
#    a new inode, so a marker or record path that has been made a symlink or a hard link to
#    a state file cannot be used to write into that state file.
#  - Both are written at the very end of _format_output, after every existing state write.
# NOT defended, and known:
#  - A compaction whose removal of the marker fails while ~/.claude is otherwise writable.
#    The stale entries are then believed: in shadow that is a wrong record, in suppress or
#    the hide arm it hides a block that should be shown again. The writability test above
#    is a partial stand-in, not a signal that the removal happened.
#  - Another process racing the hook's own check-then-open or check-then-rename (a FIFO or
#    a directory planted at an output name can stall or misplace a write; both come after
#    the state writes). Such a process can already rewrite the state files directly.
_STICKY_SKILL=""
case "${ACS_STICKY_REPEAT:-shadow}" in
  [Tt][Rr][Ii][Aa][Ll])             _STICKY_REPEAT_MODE="trial" ;;
  [Ss][Uu][Pp][Pp][Rr][Ee][Ss][Ss]) _STICKY_REPEAT_MODE="suppress" ;;
  [Oo][Ff][Ff])                     _STICKY_REPEAT_MODE="off" ;;
  *)                                _STICKY_REPEAT_MODE="shadow" ;;
esac
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

# The registry sections the hook reads: the skills list, the methodology hints, the
# required_when pairs, and the phase compositions. Each filter is defined ONCE and used
# two ways: all together in one jq call at load (the normal path), or one call each
# (the fallback below). The single call replaced five forks (a `jq empty` validation
# plus four extractions), about 10ms of fixed overhead — see
# openspec/changes/composition-contract-fixes/PERF-activation-hook.md.
_REG_F_SKILLS='
  [.skills[] | select(.available == true and .enabled == true)] | .[] |
  (.name + "\u001f" + (.name | ascii_downcase) + "\u001f" + .role + "\u001f" +
   (.priority // 0 | tostring) + "\u001f" + (.invoke // "SKIP") + "\u001f" +
   (.phase // "") + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" + ((.keywords // []) | join("\u0001")) + "\u001f" + (.required_when // ""))
'
_REG_F_HINTS='
  (.plugins // []) as $plugins |
  .methodology_hints // [] | .[] |
  # Gate plugin-scoped hints on plugin availability
  (if .plugin then
    (.plugin as $p | [$plugins[] | select(.name == $p and .available == true)] | length > 0)
  else true end) as $available |
  select($available) |
  ((.skill // "") + "\u001f" + .hint + "\u001f" + ((.triggers // []) | join("\u0001")) + "\u001f" + ((.phases // []) | join("\u0001")))
'
_REG_F_RW='
  [.skills[] | select(.required_when != null and .required_when != "")] |
  .[] | "\(.name)=\(.required_when)"
'
_REG_F_AVAIL='
  [.plugins // [] | .[] | select(.available == true) | .name] as $avail |
'
_REG_F_COMP_BODY='
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
'
# One phase's compositions ($ph), as the per-phase call of the fallback path runs it.
_REG_F_COMP_ONE="${_REG_F_AVAIL}"' .phase_compositions[$ph] // empty | '"${_REG_F_COMP_BODY}"

# The single call. `-n [inputs]` reads every JSON document in the file, and each filter
# runs per document inside its own `try`, which is what the separate calls did: jq's
# CLI reports a runtime error and moves on to the NEXT document, keeping the output
# already emitted. `[inputs]` must stay OUTSIDE every `try`: a parse error then ends
# the call with a non-zero exit, which means "invalid registry" and selects the
# fallback registry, as `jq empty` did. `try inputs` WOULD catch a parse error and let
# an unparseable cache count as valid.
#
# Output (-j; every line carries its own newline): four sections, each introduced by a
# lone RS (\x1e), split below with IFS=RS in one linear pass. Bash 3.2 parameter-
# expansion splitting measured 278-529ms on a 50KB output and `read -d` 16ms, against
# ~2ms for IFS splitting.
#   1 SKILLS  name<US>name_lower<US>role<US>priority<US>invoke<US>phase<US>triggers<US>keywords<US>required_when
#             (US \x1f between fields, SOH \x01 inside the trigger/keyword lists)
#   2 HINTS   skill<US>hint<US>triggers<US>phases
#   3 RW      name=required_when
#   4 COMP    <PHASE><US><line> for EVERY phase, since the phase is known only after
#             scoring. Each phase has its own `try` (the old call evaluated one phase,
#             so a broken phase must not cost the others), EVERY physical line of a
#             multi-line value carries the prefix, and a key containing NUL, a newline
#             or a US is skipped: the old exact-key lookup could never select it, and
#             it would forge another phase's prefix (bash drops NUL from the captured
#             output, so `IMPLEMENT<NUL>` would read as `IMPLEMENT`). The test uses
#             `explode` because jq 1.6's `contains` stops at NUL, which would make
#             `contains("<NUL>")` true for every key.
# If any extracted text contains RS, the sections would shift, so the call prints
# REGISTRY-HAS-RS instead and the hook runs the filters separately, as it did before.
# The detector uses `index`, which is length-aware since jq 1.5: jq 1.6's `contains`
# stops at NUL, so a NUL before the RS would hide it, and `explode` measured ~10ms
# per check on a real registry (index: ~0.1ms). `test` is avoided because jq builds
# without the regex library raise on it, which would read as an invalid registry.
_REG_PROGRAM='
  [inputs] as $all |
  [$all[] | try ('"${_REG_F_SKILLS}"') catch empty | . + "\n"] as $s |
  [$all[] | try ('"${_REG_F_HINTS}"') catch empty | . + "\n"] as $h |
  [$all[] | try ('"${_REG_F_RW}"') catch empty | . + "\n"] as $r |
  [$all[] | try ('"${_REG_F_AVAIL}"'
      (.phase_compositions | objects | to_entries[]
        | select(.key | explode | any(.[]; . == 0 or . == 10 or . == 31) | not)) as $e |
      ($e.key + "\u001f") as $pfx |
      (try ($e.value // empty | '"${_REG_F_COMP_BODY}"') catch empty) |
      $pfx + (split("\n") | join("\n" + $pfx)) + "\n"
    ) catch empty] as $c |
  if any(($s + $h + $r + $c)[]; index("\u001e") != null) then "REGISTRY-HAS-RS"
  else "\u001e", $s[], "\u001e", $h[], "\u001e", $r[], "\u001e", $c[]
  end
'
_REG_OUT=""
if [[ -f "$REGISTRY_CACHE" ]] && _REG_OUT="$(jq -nj "$_REG_PROGRAM" "$REGISTRY_CACHE" 2>/dev/null)"; then
  REGISTRY="$(cat "$REGISTRY_CACHE")"
elif [[ -f "$FALLBACK_REGISTRY" ]] && _REG_OUT="$(jq -nj "$_REG_PROGRAM" "$FALLBACK_REGISTRY" 2>/dev/null)"; then
  REGISTRY="$(cat "$FALLBACK_REGISTRY")"
else
  # No registry available — emit minimal phase checkpoint and exit
  OUT="SKILL ACTIVATION (0 skills | phase checkpoint only)

Phase: assess current phase (DISCOVER/DESIGN/PLAN/IMPLEMENT/REVIEW/SHIP/LEARN/DEBUG)
and consider whether any installed skill applies."
  [[ -n "${_DISPLAY_SUPPRESS}" ]] || \
  printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
    "$(printf '%s' "$OUT" | jq -Rs .)"
  exit 0
fi

_REG_SEPARATE=0
if [[ "$_REG_OUT" == "REGISTRY-HAS-RS" ]]; then
  # Rare: registry text contains RS. Run each filter separately, as before this change;
  # the compositions are then read per phase in the composition block.
  _REG_SEPARATE=1
  SKILL_DATA="$(printf '%s' "$REGISTRY" | jq -r "$_REG_F_SKILLS" 2>/dev/null)"
  HINTS_DATA="$(printf '%s' "$REGISTRY" | jq -r "$_REG_F_HINTS" 2>/dev/null)"
  _RW_LOOKUP="$(printf '%s' "$REGISTRY" | jq -r "$_REG_F_RW" 2>/dev/null)"
  _REG_COMP=""
else
  # Element 0 is the empty text before the first RS. IFS holds only RS, which is not
  # IFS whitespace, so empty sections survive and nothing inside a section is split;
  # noglob is on for the split and restored to its previous state after it.
  case "$-" in *f*) _reg_noglob=1 ;; *) _reg_noglob=0 ;; esac
  _reg_ifs="$IFS"; IFS=$'\x1e'; set -f
  _reg_parts=( $_REG_OUT )
  IFS="$_reg_ifs"
  [[ "$_reg_noglob" -eq 1 ]] || set +f
  SKILL_DATA="${_reg_parts[1]:-}"
  HINTS_DATA="${_reg_parts[2]:-}"
  _RW_LOOKUP="${_reg_parts[3]:-}"
  _REG_COMP="${_reg_parts[4]:-}"
  unset _reg_parts
fi
unset _REG_OUT

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

    # Name boost: the FULL hyphenated name as a whole word -> 100. Nothing else.
    #
    # A hyphen-SEGMENT boost (+20 for any segment >=6 chars) used to live here. It was
    # removed after measurement: across a 63-prompt corpus it produced six selections
    # with no trigger match, and every one was wrong. The segments that fired were
    # `design`, `agents`, `implementation`, `project`, and `before` -- a preposition
    # sitting in `verification-before-completion` as connective grammar. The >=6 guard
    # existed to exclude common words like "test"/"code"/"plan", but `design`, `review`
    # and `deploy` are all exactly 6, so it never held at its own threshold.
    #
    # A hyphen is a naming convention, not evidence that each component is a command.
    # Ordinary language is the trigger regexes' job. This boost survives because a
    # multi-word name requires the literal hyphenated token, which a user types
    # deliberately -- note that is a strong signal of REFERENCE, not proof of a request
    # ("do not use design-debate" still matches), so it is a ranking aid and must not be
    # read as authorisation by anything downstream.
    name_boost=0
    if [[ "$P" =~ (^|[^a-z0-9-])${skill_name_lower}($|[^a-z0-9-]) ]]; then
      if [[ "$skill_name_lower" == *-* ]]; then
        # Multi-word: the user had to type the literal hyphenated token, which is
        # deliberate. (It is a strong signal of REFERENCE, not proof of a request --
        # "do not use design-debate" matches too -- so nothing downstream may read it
        # as authorisation.)
        name_boost=100
      else
        # Single-word names are ordinary English -- panel, synthesize, brainstorming --
        # and the bare word is not evidence of intent. Measured: "the control panel
        # component is misaligned on mobile" scored panel=116, and on held-out data "the
        # collapsible panel on the settings screen" SELECTED panel, which dispatches
        # repository content to another vendor. So these require an invocation marker.
        # The marker may be separated from the name by up to two determiners/adjectives
        # the|this|that are DELIBERATELY ABSENT from the determiner list. All three are
        # DEFINITE references to an existing thing, so "use the panel on the settings page"
        # and "run this panel on the design doc" are instructions about a panel that already
        # exists, not invocations of the skill (measured: both scored the full boost and
        # routed to panel, which dispatches content to an external vendor). Only indefinite
        # and qualifier forms invoke: "run a standalone panel", "use another panel".
        # ("run a standalone panel" -- probe case sp-1, whose triggers deliberately no
        # longer fire because it names no model).
        #
        # The name must also be the HEAD of its phrase, not a modifier: "use panel data"
        # (econometrics) and "fix the /panel route" both scored the full boost and routed
        # repo content to another vendor. This is enforced with a CLOSED-CLASS follow
        # set -- after the name the phrase must end or continue with a function word.
        # The earlier version blocklisted nouns (data|route|component|...), which is an
        # OPEN set and let through "use panel regression", "run the panel tests", "run
        # panel migrations" and "use synthesize_audio" (measured: 4 of 5 escaped).
        # Function words are a closed class, so this direction is bounded.
        #
        # The "/" marker is GONE, and it was never doing the job it looked like it did:
        # the hook exits at the top of the file on a leading slash (slash commands are
        # handled by the Skill tool), so "/" could only ever match a MID-prompt slash --
        # i.e. a URL path. It enabled "fix the /panel route" and no real slash command.
        _nb_named="(^|[^a-z0-9-])${skill_name_lower}($|[^a-z0-9-])"
        _nb_follow='($|[^a-z0-9-] *($|(on|for|with|to|over|against|about|from|in|at|and|or|then|please|now|instead|again|here|first)($|[^a-z0-9-])))'
        _nb_marked="((^|[^a-z0-9-])(run|use|invoke|call|skill|using) +((a|an|another|standalone|independent|new|quick|full) +){0,2})${skill_name_lower}${_nb_follow}"
        # _nb_named is LOGICALLY REDUNDANT -- _nb_marked ends with the same skill name, so
        # a marked match implies a named one. It is kept as a cheap short-circuit: the vast
        # majority of prompts contain no skill name at all, and this is the cheaper of the
        # two patterns to fail. Drop it only if profiling says it costs more than it saves.
        if [[ "$P" =~ $_nb_named ]] && [[ "$P" =~ $_nb_marked ]]; then
          name_boost=100
        fi
      fi
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
          # Match quality is POSITIONAL, and the left edge is what decides whether a
          # partial-word hit is meaningful at all:
          #   both edges at a boundary -> whole word            -> 30
          #   left edge at a boundary  -> stemming ("debug" in
          #                               "debugging")          -> 10
          #   left edge mid-word       -> an accident ("hang" in
          #                               "changes")            -> NOT a match
          # The third case used to score 10 like the second. Measured consequence:
          # systematic-debugging scored 60 (10 + priority 50) on "please review the
          # code changes in this pull request" and beat requesting-code-review's 55
          # (30 + priority 25) -- a clean word match losing to an infix accident.
          # Re-weighting cannot fix this: priority spans 10..200 in the real registry,
          # so any additive weight able to dominate it would swamp priority outright.
          _best=0
          _scan="$P"
          _offset=0
          while true; do
            matched="${BASH_REMATCH[0]}"
            [[ -z "$matched" ]] && break

            _pre="${_scan%%"$matched"*}"
            _abs=$((_offset + ${#_pre}))
            _aft=$((_abs + ${#matched}))
            # A HYPHEN IS A WORD SEPARATOR HERE, unlike in the name matcher above.
            # `team-review` is two words, so a trigger matching `team.review` inside
            # "agent-team-review" is a real match; `hang` inside "changes" is not.
            # Counting `-` as a word character made every hyphenated compound an
            # infix: measured, "run agent-team-review on this branch" dropped BOTH of
            # that skill's trigger regexes (each matches preceded by `-`), taking it
            # from 140 to 120 and out of the required-role pass entirely -- a user
            # typing a skill's exact name stopped getting it. The name matcher keeps
            # `-` as a word character on purpose, so that `debug` does not match
            # inside `debug-advanced`; these two rules are deliberately different.
            _left_ok=1
            [[ "$_abs" -gt 0 ]] && [[ "${P:$((_abs-1)):1}" =~ [a-z0-9_.] ]] && _left_ok=0
            _right_ok=1
            [[ "$_aft" -lt "${#P}" ]] && [[ "${P:${_aft}:1}" =~ [a-z0-9_.] ]] && _right_ok=0

            if [[ "$_left_ok" -eq 1 ]] && [[ "$_right_ok" -eq 1 ]]; then
              _best=30
              break
            fi
            # A hit touching a word boundary on EITHER side is morphology, not an
            # accident, and stays a match at partial quality:
            #   left edge  -> `debug` in "debugging"   (suffixed)
            #   right edge -> `check` in "recheck"     (prefixed)
            # Only a hit interior to a word on BOTH sides is rejected -- `hang` inside
            # "changes". Requiring the LEFT edge specifically was wrong and measured so:
            # "recheck the diff for the auth module" and "redeploy the service to
            # staging" dropped to ZERO routing, losing verification-before-completion,
            # a push-gate milestone, from a genuine redeploy turn. Keep scanning either
            # way: a whole-word hit later in the prompt still outranks this.
            if [[ "$_left_ok" -eq 1 ]] || [[ "$_right_ok" -eq 1 ]]; then
              _best=10
            fi

            # Advance one char past match start and retry regex
            _skip=$((${#_pre} + 1))
            _scan="${_scan:${_skip}}"
            _offset=$((_offset + _skip))
            [[ -z "$_scan" ]] && break
            [[ "$_scan" =~ $trigger ]] || break
          done
          # _best == 0 means every hit was mid-word: the regex matched, but nothing
          # it matched was a word. Adding 0 keeps the skill below the
          # trigger_score > 0 selection gate, which is the intended outcome.
          trigger_score=$((trigger_score + _best))
          # Collect explain data for this trigger hit
          if [[ -n "${SKILL_EXPLAIN:-}" ]] && [[ "$_best" -gt 0 ]]; then
            _btype="word-prefix"
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
# the prompt is short (a bare ack like "yes"/"ok"/"do it").
#
# WHAT ADVANCES THE WALK, AND WHAT IS RECORDED AS DONE. These used to be one list. This
# comment said a sticky reply "does NOT mutate .completed", and that was false: the step
# it displayed was written as the last-invoked signal, the next prompt credited that
# signal, and six bare replies recorded DESIGN, PLAN and IMPLEMENT as completed with
# nothing invoked. They are two lists now:
#   .completed  a Skill tool that really returned (skill-completion-hook.sh). The walker
#               never adds to it; it carries it forward on the same chain, and ONLY there:
#               a chain switch, or a prior file it cannot read, starts both lists again,
#               as it always did. A state file written by an older build keeps the
#               inferred names it already held in .completed until the chain changes.
#   .assumed    what the walker INFERS: the steps before an anchor, and a step it showed
#               on the previous prompt. Never evidence. Rendered [DONE?].
# The walk position is chain[count of steps in either list], so WHICH step is mandated on
# each prompt is exactly what it was. Whether a bare reply should advance the walk at all
# is a separate question, deliberately not changed here.
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
    # The cancelled task's POSITION goes with its chain. The last-invoked signal is that
    # position: left behind, the next task's first prompt credited every step up to it,
    # and a new build order was told to request a code review on its second prompt
    # (measured). The push guard reads this file only for its phase, to decide whether to
    # print SHIP-phase advisories; after a cancel there is no phase to advise on.
    rm -f "${HOME}/.claude/.skill-last-invoked-${_SESSION_TOKEN}" 2>/dev/null
    # Sticky repeat (#333): the chain is gone, so what was shown for it is no longer a
    # reason to hide anything. Unlinking a name writes through nothing.
    rm -f "${HOME}/.claude/.sticky-repeat-shown-${_SESSION_TOKEN}" 2>/dev/null
    return
  fi

  # CURRENT = chain[number of chain steps that are confirmed OR assumed]. Bail if
  # exhausted, chain empty, or either list holds a name that is not a chain member
  # (malformed state). A list that is not an array makes jq fail, which is also a bail.
  # Counted over the chain, so a name in both lists counts once.
  local _current_name
  _current_name="$(jq -r '
    (.chain // []) as $c | (.completed // []) as $d | (.assumed // []) as $a |
    if ($c | length) == 0 then empty
    elif (($d + $a) | all(. as $x | $c | index($x))) | not then empty
    else
      ([$c[] | select(. as $x | ($d + $a) | index($x))] | length) as $n
      | if $n >= ($c | length) then empty else $c[$n] end
    end
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
  # _STICKY_SKILL records that this step came from the chain and not from the prompt's own
  # words (the hijack guard above has just established that no process skill scored). The
  # sticky-repeat rule reads it; nothing else does.
  _STICKY_SKILL="${_current_name}"
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

    # _RW_LOOKUP (name=required_when) was extracted at registry load (_REG_PROGRAM section 3).

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

# --- _expand_precondition_plugin_root -----------------------------
# In/out global: _cprecond (mutated in place). Input global: PLUGIN_ROOT.
#
# A precondition may name `phase_attest`, which lives in this plugin and is NOT
# on any path the model's shell knows: CLAUDE_PLUGIN_ROOT is unset in a Bash
# turn, and `git rev-parse --show-toplevel` is the USER's repo, which has no
# hooks/lib. Rendering the call verbatim therefore shipped an unrunnable remedy
# to every IMPLEMENT-phase prompt in every repo — more often than the push
# gate's own advisory, and it is the exact remedy the IMPLEMENT deny-flip
# pre-registration treats as available (#248).
#
# The path is single-quoted IN THE CONFIG TEXT, so this substitution inserts a
# literal; a path containing `'` is the one case single quotes cannot hold, so
# it is escaped here rather than left to produce a broken line.
#
# TWO call sites read a `precondition` out of the registry and render it: the
# CURRENT step of a composition chain, and _render_driver_precondition below.
# Both must expand and escape, or one of them re-ships the #248 defect — and
# hand-copying the escape is precisely how the four paired #248 renderings
# drifted in the first place. It lives here so there is one copy to get right.
# tests/test-attest-remedy-reachable.sh lifts the three lines below out of this
# file with `sed` and executes them, so it tests THIS code and not a copy; it
# also asserts there is exactly ONE `_pr_esc=` line in the repo, which a second
# inline copy would break. Mutating the escape must fail that file.
#
# It mutates the caller's variable rather than echoing, because the CURRENT-step
# site is the ~50ms hot path and a command substitution there is a fork.
_expand_precondition_plugin_root() {
  if [[ -n "$_cprecond" && "$_cprecond" == *'{{PLUGIN_ROOT}}'* ]]; then
    # POSIX single-quote escaping, fork-free (this is the ~50ms hot
    # path). Inside double quotes `\'` is NOT an escape — it is a
    # backslash followed by a quote — so the replacement is assembled
    # from explicit single-character variables. Getting this wrong
    # emitted `a\'\\'\'b`, a malformed line that breaks the whole
    # pasted command, which is worse than the missing path it replaced.
    _sq="'" ; _bs='\' ; _rep="${_sq}${_bs}${_sq}${_sq}"
    _pr_esc="${PLUGIN_ROOT//${_sq}/${_rep}}"
    _cprecond="${_cprecond//\{\{PLUGIN_ROOT\}\}/${_pr_esc}}"
  fi
}

# --- _expand_composition_hint_plugin_root -------------------------
# `phase_compositions[*].hints[].text` is the SIXTH rendering surface that
# reaches the model's prompt (#306). #248 wired `{{PLUGIN_ROOT}}` into
# `precondition`, #305 into `methodology_hints[].hint`, and both missed this
# field — so it rendered VERBATIM and shipped the #248 broken pair
# (`${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}`), which resolves to
# the USER's repo root and gives rc=127 for every reader outside this repo.
#
# THE QUOTING ASYMMETRY IS PINNED AND MUST NOT BE "MADE CONSISTENT". A
# precondition IS a shell command to paste, so it is single-quoted and escaped;
# a hint NAMES a file to read, and shell quotes handed to a Read tool are
# literal characters that make the path unopenable. This field carries BOTH
# kinds, so the text declares its own context: a placeholder written
# `'{{PLUGIN_ROOT}}/…'` is a pasted command and takes the escaping, and a bare
# `{{PLUGIN_ROOT}}/…` is a file to read and takes none. A space survives the
# bare form because backticks delimit the span.
#
# The escaped branch delegates to _expand_precondition_plugin_root through its
# in/out global rather than repeating the escape, because hand-copying it is how
# the four #248 renderings drifted apart in the first place.
#
# PRECISELY WHAT IS PINNED, since the looser claim is what this file keeps
# getting wrong: tests/test-attest-remedy-reachable.sh asserts exactly one
# `_pr_esc=` line WITHIN A SED-EXTRACTED RANGE of this hook — not repo-wide. A
# second copy in another file would NOT fail it. So the pin stops this function
# from growing a rival escape; it does not stop anyone else from writing one.
#
# In/out global: _cprecond. Input global: PLUGIN_ROOT.
_expand_composition_hint_plugin_root() {
  _cprecond="$1"
  case "$_cprecond" in
    *"'{{PLUGIN_ROOT}}"*) _expand_precondition_plugin_root ;;
    *'{{PLUGIN_ROOT}}'*)  _cprecond="${_cprecond//\{\{PLUGIN_ROOT\}\}/${PLUGIN_ROOT}}" ;;
  esac
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
          # [DONE] is a claim: the Skill tool returned for this step (the completion hook
          # put it in .completed). Everything else before the current step is inferred and
          # says so. The last-invoked signal used to earn [DONE] here; it is written when a
          # step is DISPLAYED, so it is not evidence that anything ran.
          if [[ -n "$_COMP_COMPLETED" ]] && printf '%s\n' "$_COMP_COMPLETED" | grep -qxF -- "$_cname" 2>/dev/null; then
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
          _expand_precondition_plugin_root
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

      # Surface active skip-attestations on EVERY prompt that displays a chain (a prompt
      # whose display is suppressed -- see _DISPLAY_SUPPRESS -- shows nothing) (phase-enforcement,
      # codex #5): a skipped step must stay visible to the human and the REVIEW
      # lens, not live only in logs. Fail-open; single jq fork; bounded to 6.
      # Appended to COMPOSITION_CHAIN (not SKILL_LINES): this site only runs
      # inside the "_full_chain has 2+ skills" block, where COMPOSITION_CHAIN
      # was just set non-empty above (the "Composition: ..." block) — so the
      # attest lines land directly under the chain they annotate instead of
      # detaching above it in every _format_output render order.
      _ATTEST_F="${HOME}/.claude/.skill-phase-attest-${_SESSION_TOKEN:-default}"
      if [[ -f "$_ATTEST_F" ]] && command -v jq >/dev/null 2>&1; then
        _ATTEST_LINES="$(jq -r '[to_entries[] | "  ATTESTED SKIP (agent-recorded, verify before trusting): " + (.key | gsub("[\r\n\t]+"; " ")) + " — " + ((.value.reason // "?") | gsub("[\r\n\t]+"; " ") | .[0:200]) + " (" + ((.value.ts // "?") | tostring) + ")"] | .[0:6] | join("\n")' "$_ATTEST_F" 2>/dev/null)" || _ATTEST_LINES=""
        [[ -n "$_ATTEST_LINES" ]] && COMPOSITION_CHAIN="${COMPOSITION_CHAIN}
${_ATTEST_LINES}"
      fi

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

# --- _render_driver_precondition ----------------------------------
# Input globals: REGISTRY, PRIMARY_PHASE, COMPOSITION_CHAIN, PLUGIN_ROOT
# Output global: DRIVER_PRECONDITION ("" when nothing should render)
#
# _walk_composition_chain anchors on a `process` skill, else on a selected
# `workflow` skill carrying precedes/requires. A `domain` skill can NEVER
# anchor, so a prompt whose only matches are domain skills ("prototype the
# dashboard components") got no chain block at all — and the CURRENT-step
# `precondition` renders ONLY inside that block. For DESIGN that silently
# dropped both the product-discovery prerequisite and the lethal-trifecta
# classification gate, on exactly the prompts most likely to need them.
#
# This renders that one precondition and nothing else, attributed by a single
# line naming the driver's Skill() invocation so the text has an antecedent
# ("...then return to brainstorming" does not parse with nothing before it).
#
# IT MUST NOT ESTABLISH A CHAIN, and that is a gate constraint rather than a
# display preference. _full_chain/_current_idx are what the composition-state
# write is gated on, and the DESIGN chain contains BOTH push-gate milestones
# (requesting-code-review, verification-before-completion) which
# openspec-guard.sh reads out of `.chain`. Anchoring here would make a session
# that merely asked a UI question owe a dispatched code review and a
# verification run before it could push anything. So: no _full_chain, no
# _current_idx, no COMPOSITION_CHAIN, no COMPOSITION_DIRECTIVE — and no
# continuation directive either, because no trigger matched the driver and a
# directive would push a full DESIGN->SHIP sequence off a phase default rather
# than off evidence of intent.
#
# The driver name is read from `phase_compositions[<phase>].driver`, never
# hardcoded. Fail-open throughout: every unresolved case leaves
# DRIVER_PRECONDITION empty and the rest of the output untouched.
_render_driver_precondition() {
  DRIVER_PRECONDITION=""

  # Only where NO anchor resolved. A resolved chain already renders its CURRENT
  # step's precondition, so firing here as well would duplicate it — and this
  # predicate is also what keeps the fallback from displacing either anchor or
  # reordering the two.
  if [[ -n "$COMPOSITION_CHAIN" ]]; then
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] skipped: a chain already anchored\n' >&2
    return 0
  fi
  # "No chain" is NOT the same set as "no process skill was selected", and the
  # spec's condition is the latter. Three shipped process skills carry
  # `precedes: [] requires: []` — systematic-debugging, receiving-code-review,
  # subagent-driven-development — so selecting one anchors the walker but
  # produces no 2+-skill chain, leaving COMPOSITION_CHAIN empty while a process
  # skill is MUST INVOKE. Without this line the output then contradicts itself
  # in adjacent lines, naming the very skill it is ordering:
  #
  #   Process: systematic-debugging -> Skill(superpowers:systematic-debugging)
  #   DEBUG driver not invoked: Skill(superpowers:systematic-debugging)
  #
  # Suppressing only when the driver EQUALS the selected process skill was
  # rejected: it is a second predicate to maintain beside this one, and it
  # leaves the spec divergence standing. PROCESS_SKILL is set by
  # _determine_label_phase, which runs well before this function's call site.
  if [[ -n "${PROCESS_SKILL:-}" ]]; then
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] skipped: a process skill (%s) was selected\n' \
        "$PROCESS_SKILL" >&2
    return 0
  fi
  # No phase, nothing to look up. _determine_label_phase falls back through
  # process -> workflow -> domain -> required, so a domain-only match still has
  # one; an empty value means no skill carried a phase at all.
  if [[ -z "${PRIMARY_PHASE:-}" ]]; then
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] skipped: no skill (and so no phase) was selected\n' >&2
    return 0
  fi

  # ONE jq call for the driver name plus that skill's invoke and precondition.
  # It runs only on this path — where no anchor resolved — so the ~50ms
  # activation budget is unaffected on the chain path.
  #
  # `gsub` is deliberately not used to flatten the text: a jq built without the
  # regex library raises on it, which would read here as an unparseable
  # registry. split/join needs no regex engine.
  _dp_raw=""
  _dp_raw="$(printf '%s' "$REGISTRY" | jq -r --arg ph "$PRIMARY_PHASE" '
    ((.phase_compositions // {}) | if type == "object" then . else {} end) as $pc |
    (($pc[$ph] // {}) | if type == "object" then (.driver // "") else "" end) as $d0 |
    (if ($d0 | type) == "string" then $d0 else "" end) as $d |
    if $d == "" then "\u001f\u001f"
    else
      ((.skills | if type == "array" then . else [] end)
        | map(select((.name? // "") == $d)) | first) as $s |
      if ($s | type) != "object" then $d + "\u001f\u001f"
      else
        $d + "\u001f"
        + (($s.invoke // "") | if type == "string" and . != "" then . else "Skill(" + $d + ")" end)
        + "\u001f"
        + ((($s.precondition // "") | if type == "string" then . else "" end)
            | split("\n") | join(" ") | split("\r") | join(" "))
      end
    end
  ' 2>/dev/null)"
  _dp_rc=$?

  # INFRASTRUCTURE FAULT — a SEPARATE early return from "this phase has no
  # driver" below, per the spec requirement that the two be distinguishable. A
  # non-zero jq (an unparseable registry, a jq that cannot compile this program,
  # no jq at all) means we could not look; an empty stdout means the same, since
  # the program above always emits at least the two field separators. Routing
  # both through the same silent return as an absent driver is what would make a
  # broken install read as a phase that simply has no driver configured.
  if [[ "$_dp_rc" -ne 0 ]] || [[ -z "$_dp_raw" ]]; then
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] could not resolve for %s (jq rc=%s) — infrastructure fault, not an absent driver\n' \
        "$PRIMARY_PHASE" "$_dp_rc" >&2
    return 0
  fi

  # Literal \x1f rather than $FS: FS is assigned further down this file, and a
  # function must not depend on where it is called from under `set -u`.
  IFS=$'\x1f' read -r _dp_name _dp_invoke _dp_precond <<EOF
${_dp_raw}
EOF

  if [[ -z "${_dp_name:-}" ]]; then
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] %s has no driver configured\n' "$PRIMARY_PHASE" >&2
    return 0
  fi
  if [[ -z "${_dp_invoke:-}" ]]; then
    # Named, but absent from the registry: uninstalled, renamed, or misspelt.
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] %s driver %s is not in the registry\n' \
        "$PRIMARY_PHASE" "$_dp_name" >&2
    return 0
  fi
  if [[ -z "${_dp_precond:-}" ]]; then
    # Present, but has nothing conditional to say. Rendering a bare attribution
    # line would be noise, not guidance.
    #
    # This is the function's MOST COMMON outcome — six of the eight shipped
    # drivers carry no `precondition` — and it was the only one of the four that
    # left no trace, so "checked, nothing to say" could not be told apart from
    # "never ran". That silence already cost real diagnostic effort: it is why
    # establishing where the infra-fault arm actually fires needed a second
    # probe. A path that declines to act must say so.
    [[ -n "${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [driver-precondition] %s driver %s carries no precondition\n' \
        "$PRIMARY_PHASE" "$_dp_name" >&2
    return 0
  fi

  # Shared with the CURRENT-step render (#248): the remedy the text names lives
  # in this plugin and is unreachable from the model's shell without the
  # absolute path.
  _cprecond="$_dp_precond"
  _expand_precondition_plugin_root

  # The precondition is rendered VERBATIM under the attribution, as the
  # CURRENT-step site renders it. Every shipped precondition already opens with
  # the `PRECONDITION:` label (held by
  # tests/test-context.sh::test_precondition_label_is_a_config_convention), so
  # the label is config text, not something synthesised here.
  DRIVER_PRECONDITION="
${PRIMARY_PHASE} driver not invoked: ${_dp_invoke}
  ${_cprecond}"
  [[ -n "${SKILL_EXPLAIN:-}" ]] && \
    printf '[skill-hook]   [driver-precondition] rendered %s driver %s\n' \
      "$PRIMARY_PHASE" "$_dp_name" >&2
}

# --- _format_output -----------------------------------------------
# Input globals: TOTAL_COUNT, PLABEL, SKILL_LINES, COMPOSITION_CHAIN, COMPOSITION_LINES,
#                DRIVER_PRECONDITION,
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
    # Secure BEFORE the first content write: this log holds RAW PROMPT TEXT,
    # the most sensitive of the local diagnostic corpora, and a pre-existing
    # 0644 file would leak every record appended to it. Same shape as
    # scripts/push-gate-capture.sh -- umask covers a fresh file, the explicit
    # chmod fixes an already-loose one. The prompt is deliberately NOT hashed:
    # seeing which prompts matched no trigger IS the diagnostic value.
    ( umask 077; : >> "$_ZM_LOG" ) 2>/dev/null || true
    chmod 0600 "$_ZM_LOG" 2>/dev/null || true
    # Truncate prompt to 200 chars to prevent unbounded log growth
    printf '%.200s\n' "$P" >> "$_ZM_LOG" 2>/dev/null || true
    if [[ -f "$_ZM_LOG" ]]; then
      # Rotate by line count
      _lc="$(wc -l < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_lc" =~ ^[0-9]+$ ]] && [[ "$_lc" -gt 100 ]]; then
        ( umask 077; tail -n 100 "$_ZM_LOG" > "${_ZM_LOG}.tmp" ) 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
      # Rotate by byte size (50KB cap)
      _zm_size="$(wc -c < "$_ZM_LOG" 2>/dev/null | tr -d ' ')"
      if [[ "$_zm_size" =~ ^[0-9]+$ ]] && [[ "$_zm_size" -gt 51200 ]]; then
        ( umask 077; tail -n 50 "$_ZM_LOG" > "${_ZM_LOG}.tmp" ) 2>/dev/null && mv "${_ZM_LOG}.tmp" "$_ZM_LOG" 2>/dev/null || true
      fi
      # The .tmp holds the SAME raw prompt text as the log, so it is created
      # under `umask 077` too -- otherwise it sits world-readable in the window
      # between `tail >` and `mv`, which would defeat the point of securing the
      # log at all. push-gate-capture.sh has this same gap; matching an
      # existing gap is not a reason to keep one.
      # Both rotations write a FRESH .tmp under the ambient umask and mv it
      # over the log, so the mv carries the .tmp's mode across and undoes the
      # write-path chmod above. Re-secure after rotating, or the log reverts
      # to 0644 the first time it fills up.
      chmod 0600 "$_ZM_LOG" 2>/dev/null || true
    fi

    # Zero-match: emit nothing (no additionalContext)
    return

  elif [[ "$_PROMPT_COUNT" -gt 10 ]]; then
    # --- minimal format (depth 11+): skill list + eval only ---
    EVAL_PHASE="$PRIMARY_PHASE"
    [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}${DRIVER_PRECONDITION}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${COMPOSITION_DIRECTIVE}"

  elif [[ "$TOTAL_COUNT" -le 2 ]] && [[ "$_PROMPT_COUNT" -le 5 ]]; then
    # --- compact format (1-2 skills, depth 1-5) ---
    EVAL_PHASE="$PRIMARY_PHASE"
    [[ -z "$EVAL_PHASE" ]] && EVAL_PHASE="IMPLEMENT"

    OUT="SKILL ACTIVATION (${TOTAL_COUNT} skills | ${PLABEL})
${SKILL_LINES}${COMPOSITION_CHAIN}${DRIVER_PRECONDITION}${COMPOSITION_LINES}

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

Step 2 -- EVALUATE skills against your phase assessment.${SKILL_LINES}${COMPOSITION_CHAIN}${DRIVER_PRECONDITION}${COMPOSITION_LINES}
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
${SKILL_LINES}${COMPOSITION_CHAIN}${DRIVER_PRECONDITION}${COMPOSITION_LINES}

Evaluate: **Phase: [${EVAL_PHASE}]** | ${EVAL_SKILLS}${DOMAIN_HINT}${COMPOSITION_DIRECTIVE}"
  fi

  # Append methodology hints if any
  if [[ -n "$HINTS" ]] || [[ -n "$COMPOSITION_HINTS" ]]; then
    OUT+="
${HINTS}${COMPOSITION_HINTS}"
  fi

  # Sticky repeat (#333; see _STICKY_REPEAT_MODE near the top). Decided here, immediately
  # before the print it may suppress. `sticky` = the role caps kept the step the chain
  # injected. `already` = this session was shown that step before, on this chain. `alone`
  # = the block holds no other skill. Only the three together are ever hidden; a prompt
  # whose own words selected a process skill never has _STICKY_SKILL set.
  _sr_file=""; _sr_sticky=0; _sr_already=0; _sr_header=0; _sr_arm="-"; _sr_hide_now=0; _sr_alone=0
  _sr_prior="${_DISPLAY_SUPPRESS:-}"; _sr_chain="${_full_chain:-}"
  if [[ "${_STICKY_REPEAT_MODE}" != "off" ]] && [[ -n "${PROCESS_SKILL:-}" ]] && [[ -n "${_SESSION_TOKEN:-}" ]]; then
    _sr_file="${HOME}/.claude/.sticky-repeat-shown-${_SESSION_TOKEN}"
    [[ -n "${_STICKY_SKILL}" ]] && [[ "${_STICKY_SKILL}" == "${PROCESS_SKILL}" ]] && _sr_sticky=1
    # The marker's first line names the chain its entries belong to. On another chain the
    # entries are ignored (and the file is started again below): the same skill name on a
    # different chain is a different obligation and gets its first display.
    # A hide needs a chain: "already shown" is scoped to one, so with no chain walked
    # (_full_chain empty) nothing in the marker is believed. Reviewed as a hole: without
    # this, a step listed under ANOTHER chain's header counted as shown.
    [[ "${TOTAL_COUNT:-0}" -eq 1 ]] && _sr_alone=1
    _sr_sig=""; _sr_ln=0; _sr_entries=""; _sr_t0="${SECONDS}"
    if [[ -n "${_sr_chain}" ]] && [[ -w "${HOME}/.claude" ]] && [[ -f "${_sr_file}" ]] && [[ ! -L "${_sr_file}" ]]; then
      # The outer braces put stderr away BEFORE the file is opened (`done < f 2>/dev/null`
      # opens first, so an unreadable marker printed a diagnostic that `off` does not).
      # `<>` opens read-write: that cannot block on a FIFO, and `read -t` then gives up.
      {
        {
          while [[ "${_sr_ln}" -lt 64 ]] && [[ $((SECONDS - _sr_t0)) -lt 2 ]] && IFS= read -r -t 1 -n 1025 _sr_line; do
            _sr_ln=$((_sr_ln + 1))
            # `read -n` returns CHUNKS: a physical line longer than 1024 characters comes
            # back as two reads, and its tail could equal a skill name. Believe nothing.
            if [[ "${#_sr_line}" -ge 1025 ]]; then _sr_sig=""; _sr_already=0; _sr_entries=""; break; fi
            if [[ "${_sr_ln}" -eq 1 ]]; then
              [[ "${_sr_line}" == "#chain ${_sr_chain}" ]] || break
              _sr_sig="${_sr_chain}"
              continue
            fi
            [[ "${_sr_line}" =~ ^[A-Za-z0-9._-]+$ ]] || continue
            _sr_entries="${_sr_entries}${_sr_line}"$'\n'
            [[ "${_sr_line}" == "${PROCESS_SKILL}" ]] && _sr_already=1
          done
        } <> "${_sr_file}"
      } 2>/dev/null
    fi
    [[ -n "${_sr_chain}" ]] && [[ "${_sr_sig}" != "${_sr_chain}" ]] && { _sr_header=1; _sr_already=0; _sr_entries=""; }
    # The trial arm is a property of the SESSION: the token's last character, so it costs
    # no fork and cannot change mid-session. Half the hex digits hide, half show.
    case "${_SESSION_TOKEN}" in *[89abcdefABCDEF]) _sr_arm="hide" ;; *) _sr_arm="show" ;; esac
    if [[ "${_sr_sticky}" -eq 1 ]] && [[ "${_sr_already}" -eq 1 ]] && [[ "${_sr_alone}" -eq 1 ]] && [[ -z "${_DISPLAY_SUPPRESS:-}" ]]; then
      case "${_STICKY_REPEAT_MODE}" in
        suppress) _sr_hide_now=1 ;;
        trial)    [[ "${_sr_arm}" == "hide" ]] && _sr_hide_now=1 ;;
      esac
    fi
    if [[ "${_sr_hide_now}" -eq 1 ]]; then
      _DISPLAY_SUPPRESS="sticky repeat: ${PROCESS_SKILL} was already shown on this chain and is the only skill in this block"
    fi
  fi

  # Display suppression (see the definition of _DISPLAY_SUPPRESS near the top): everything
  # below this print -- last-invoked signal, composition state -- still runs.
  if [[ -n "${_DISPLAY_SUPPRESS:-}" ]]; then
    [[ -n "${SKILL_DEBUG:-}${SKILL_EXPLAIN:-}" ]] && \
      printf '[skill-hook]   [display-suppressed] %s; nothing is emitted, routing state is written as usual\n' "${_DISPLAY_SUPPRESS}" >&2
  else
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' \
      "$(printf '%s' "$OUT" | jq -Rs .)"
  fi

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
      # Gating-milestone exclusion (hardcoded invariant, like the
      # max_iterations role-allowlist — deliberately NOT config-driven): the
      # computed prefix must never contain the two push-gate milestones. A
      # trigger match or a later step's invocation is not evidence that
      # review/verification ran; those names enter .completed only via the
      # PostToolUse completion hook (real Skill return) or the on-disk union
      # below. Everything else still back-fills (chore false-block guard).
      # PAIRED: adding a third gated milestone means updating this filter, the
      # crediting case in skill-completion-hook.sh, and the openspec-guard.sh
      # milestone checks together.
      _comp_completed="$(printf '%s' "$_full_chain" | tr '|' '\n' | head -n "$((_progress_idx + 1))" | jq -R . | jq -s 'map(select(. != "requesting-code-review" and . != "verification-before-completion"))' 2>/dev/null)" || _comp_completed="[]"
    fi
    _comp_chain="$(printf '%s' "$_full_chain" | tr '|' '\n' | jq -R . | jq -s . 2>/dev/null)" || {
      _comp_chain=""
      # Surface the failure under SKILL_EXPLAIN so compaction-recovery debug
      # isn't left guessing why state wasn't written.
      [[ -n "${SKILL_EXPLAIN:-}" ]] && \
        printf '[skill-hook] composition state write skipped: jq failed to encode chain\n' >&2
    }
    # WHERE THE COMPUTED PREFIX GOES. It is what the walker INFERS (the steps before
    # this prompt's anchor, and the step the last prompt displayed), so it is written to
    # .assumed. It used to be written to .completed, where it read as "this ran".
    # .completed is now only ever what the completion hook put there.
    #
    # (c) Monotonic floor, both lists: when the chain is unchanged, .completed is carried
    # forward exactly as it is on disk and .assumed is the union of the computed prefix
    # with the one on disk, less anything confirmed. A prompt that re-anchors EARLIER in
    # the same chain (e.g. "merge PR49" matching the review trigger after verification
    # already ran) must not truncate recorded progress — that re-arms the push gate
    # against already-reviewed work. Chain switch and pure-cancel remain the only resets.
    # Fail-open: missing/malformed prior state, or jq failure, degrades to nothing
    # confirmed and the prefix assumed. current_index intentionally stays the anchor
    # index (display semantics); the push gate keys off .completed only, and only for the
    # two gated steps, which the prefix never contains.
    if [[ -n "$_comp_chain" ]]; then
      _comp_assumed="$_comp_completed"; _comp_completed="[]"
      _prev_state="${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}"
      if [[ -f "$_prev_state" ]]; then
        _merged="$(jq -cn --argjson chain "$_comp_chain" \
                          --argjson credit "$_comp_assumed" \
                          --slurpfile prev "$_prev_state" '
          ($prev[0] // {}) as $p |
          if ($p.chain // []) == $chain then
            (($p.completed // []) | if type == "array" then . else [] end) as $pc |
            (($p.assumed // [])   | if type == "array" then . else [] end) as $pa |
            { completed: [ $chain[] | select(. as $x | $pc | index($x) != null) ],
              assumed:   [ $chain[] | select(. as $x | (($credit + $pa) | index($x) != null) and ($pc | index($x) == null)) ] }
          else { completed: [], assumed: $credit } end
        ' 2>/dev/null)" || _merged=""
        if [[ -n "$_merged" ]]; then
          _comp_completed="$(printf '%s' "$_merged" | jq -c '.completed' 2>/dev/null)" || _comp_completed="[]"
          _comp_assumed="$(printf '%s' "$_merged" | jq -c '.assumed' 2>/dev/null)" || _comp_assumed="[]"
          [[ -n "$_comp_completed" ]] || _comp_completed="[]"
          [[ -n "$_comp_assumed" ]] || _comp_assumed="[]"
        fi
      fi
      jq -n --argjson chain "$_comp_chain" \
            --argjson completed "$_comp_completed" \
            --argjson assumed "$_comp_assumed" \
            --argjson idx "${_current_idx:-0}" \
            '{chain:$chain, current_index:$idx, completed:$completed, assumed:$assumed, updated_at:now|todate}' \
        > "${HOME}/.claude/.skill-composition-state-${_SESSION_TOKEN}" 2>/dev/null || true
    fi
  fi
  # Sticky repeat (#333), LAST: remember a step that was displayed and write the shadow
  # record. Deliberately after every state write above. A block hidden for any reason (this
  # rule, or non-human input) is not remembered as shown. Both writes are best-effort.
  if [[ -n "${_sr_file:-}" ]]; then
    _sr_displayed=1; [[ -n "${_DISPLAY_SUPPRESS:-}" ]] && _sr_displayed=0
    _sr_add=0; [[ "${_sr_displayed}" -eq 1 ]] && [[ "${_sr_already}" -eq 0 ]] && _sr_add=1
    # RE-ANCHOR, a POLICY of the rule and part of its version: whenever the user's own words
    # select a process step and it is displayed, the list restarts with that step alone. It
    # is NOT evidence that a new task began -- the hook cannot tell a new task from the same
    # one asked for again, and a new task re-arms the same chain with the same signature. It
    # is chosen because it errs toward displaying: later steps get one more first display.
    # The cost is that the rule fires less often than "already shown on this chain" would
    # (found in review: cancel, then a new build order, hid the new task's planning step).
    if [[ "${_sr_sticky}" -eq 0 ]] && [[ "${_sr_displayed}" -eq 1 ]] && [[ "${_sr_entries}" != "${PROCESS_SKILL}"$'\n' ]]; then
      _sr_entries=""; _sr_add=1
    fi
    if [[ -n "${_sr_chain}" ]] && [[ ! -d "${_sr_file}" ]] && { [[ "${_sr_header}" -eq 1 ]] || [[ "${_sr_add}" -eq 1 ]]; }; then
      # Replace, never modify: the new content goes to a name that must not exist (noclobber
      # refuses a planted file, symlink or hard link) and is renamed over the marker. One
      # step, so a failed write cannot leave a header without its entry or the reverse.
      _sr_new="#chain ${_sr_chain}"$'\n'"${_sr_entries}"
      [[ "${_sr_add}" -eq 1 ]] && _sr_new="${_sr_new}${PROCESS_SKILL}"$'\n'
      _sr_tmp="${_sr_file}.new.$$"
      {
        set -C
        if printf '%s' "${_sr_new}" > "${_sr_tmp}"; then
          set +C
          mv -f "${_sr_tmp}" "${_sr_file}" || rm -f "${_sr_tmp}"
        else
          set +C
        fi
      } 2>/dev/null || true
    fi
    _sr_tf=(false true)   # indexed by the 0/1 flags below: no fork per field
    _sr_wh=0; [[ "${_sr_sticky}" -eq 1 ]] && [[ "${_sr_already}" -eq 1 ]] && [[ "${_sr_alone}" -eq 1 ]] && _sr_wh=1
    _sr_n="${TOTAL_COUNT:-0}"; [[ "${_sr_n}" =~ ^[0-9]{1,4}$ ]] || _sr_n=0
    _sr_os=0; [[ -n "${_sr_prior}" ]] && _sr_os=1
    _sr_cs="${_sr_chain//|/>}"
    _sr_pc="${_PROMPT_COUNT:-0}"; [[ "${_sr_pc}" =~ ^[1-9][0-9]{0,8}$ ]] || _sr_pc=0
    # No value below is taken from the prompt: they are registry skill names, the session
    # token, mode words, flags and counts. Names and the token are cut down to
    # [A-Za-z0-9._>-] rather than escaped, and the count is checked to be a plain number,
    # so the line is valid JSON without a jq fork on this hot path.
    # One record, one NEW file (see "nothing is modified in place" at the top): an append to
    # a shared log would write into whatever that name had been linked to.
    _sr_tok="${_SESSION_TOKEN//[^A-Za-z0-9._-]/}"
    _sr_dir="${HOME}/.claude/.sticky-repeat-shadow.d"
    {
      [[ -d "${_sr_dir}" ]] || mkdir -p "${_sr_dir}"
      set -C
      printf '{"schema_version":1,"rule_version":3,"ts":"%s","session":"%s","prompt_count":%s,"skill":"%s","chain":"%s","sticky":%s,"already_shown":%s,"would_hide":%s,"new_chain":%s,"mode":"%s","arm":"%s","hidden_by_rule":%s,"displayed":%s,"other_suppression":%s,"skills_in_block":%s,"block_chars":%s}\n' \
        "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${_sr_tok}" "${_sr_pc}" \
        "${PROCESS_SKILL//[^A-Za-z0-9._-]/}" "${_sr_cs//[^A-Za-z0-9._>-]/}" \
        "${_sr_tf[_sr_sticky]}" "${_sr_tf[_sr_already]}" "${_sr_tf[_sr_wh]}" "${_sr_tf[_sr_header]}" \
        "${_STICKY_REPEAT_MODE}" "${_sr_arm}" "${_sr_tf[_sr_hide_now]}" "${_sr_tf[_sr_displayed]}" "${_sr_tf[_sr_os]}" "${_sr_n}" "${#OUT}" \
        > "${_sr_dir}/${_sr_tok}.${_sr_pc}.${RANDOM}${RANDOM}.json"
      set +C
    } 2>/dev/null || true
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
# SKILL_DATA was extracted at registry load (_REG_PROGRAM section 1).

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
HINTS=""
# HINTS_DATA was extracted at registry load (_REG_PROGRAM section 2).

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
        # A hint may name a file that lives in the PLUGIN, not in the user's
        # repo, and the rendered text is the ONLY place the reader can learn
        # where: `CLAUDE_PLUGIN_ROOT` is unset in the model's Bash turn and the
        # file is absent from the project, so a repo-relative name is
        # unopenable everywhere but this repo (#248 for the `precondition`
        # sites; the same defect reached `hint` because only that renderer
        # substituted).
        #
        # UNLIKE a precondition the path is emitted BARE, not single-quoted. A
        # precondition IS a shell command (`source '<path>'`), so #248 quotes
        # it to survive a paste; a hint NAMES a file for the agent to read, and
        # shell quotes handed to a Read tool are literal characters that break
        # it. A space in the path is survivable because backticks delimit the
        # span; nothing downstream re-splits it.
        _htext="$hint_text"
        if [[ "$_htext" == *'{{PLUGIN_ROOT}}'* ]]; then
          _htext="${_htext//\{\{PLUGIN_ROOT\}\}/${PLUGIN_ROOT}}"
        fi
        HINTS="${HINTS}
- ${_htext}"
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

if [[ -n "$CURRENT_PHASE" ]]; then
  if [[ "${_REG_SEPARATE:-0}" -eq 1 ]]; then
    _comp_output="$(printf '%s' "$REGISTRY" | jq -r --arg ph "$CURRENT_PHASE" "$_REG_F_COMP_ONE" 2>/dev/null)"
  else
    # This phase's lines from the load-time extraction (_REG_PROGRAM section 4,
    # every line prefixed with its phase and a US).
    _comp_output=""
    _comp_pfx="${CURRENT_PHASE}${FS}"
    while IFS= read -r _comp_l; do
      case "$_comp_l" in
        "$_comp_pfx"*) _comp_output="${_comp_output}${_comp_l#"$_comp_pfx"}
" ;;
      esac
    done <<EOF
${_REG_COMP}
EOF
  fi

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
      HINT:*)
        # #306: this text reaches the prompt, so it gets the same
        # {{PLUGIN_ROOT}} expansion the `precondition` and `hint` surfaces
        # already get. `_cprecond` is the shared expander's in/out global.
        #
        # WHY REUSING IT IS SAFE, stated correctly because the obvious version
        # is FALSE: this loop is not after the chain walk, it is BEFORE it —
        # `_walk_composition_chain` and `_render_driver_precondition` are both
        # called ~50 lines below, so this is the FIRST writer of `_cprecond`,
        # not the last. The invariant that actually holds is that every later
        # consumer ASSIGNS `_cprecond` before reading it
        # (`_walk_composition_chain` at the jq capture, `_render_driver_-
        # precondition` from `_dp_precond`, and its early returns exit before
        # touching it). THAT is what a future edit must preserve: adding a
        # read-before-write to either function makes this reuse unsafe.
        _expand_composition_hint_plugin_root "${_cline#HINT:}"
        COMPOSITION_HINTS="${COMPOSITION_HINTS}
- ${_cprecond}" ;;
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
# The walker ALWAYS runs. The spec requires only that a consultation not cause a chain
# to be RENDERED; skipping the walk suppressed the chain STATE instead, and that is a
# push-gate BYPASS rather than a display change:
#
#   openspec-guard.sh gates its whole chain block on the state file existing, and the
#   state write lives inside the walker. With no file, Check 1 (deny:chain-review) and
#   Check 2 (deny:chain-verify) never run. Measured: `git push origin feat` after
#   "commit and push this, but ask codex first" went DENY -> allow, and reverted to DENY
#   when this one predicate was forced to return 1. Four other phrasings flipped the
#   same way, as did two ordinary agent-team prompts -- which are the HIGHEST-autonomy
#   development workflow in the registry, not adversarial input.
#
# So: walk, write state, gate exactly as before, and clear only what is DISPLAYED. The
# cost is that a consultation turn still records development progress it did not make.
# That is a fabrication worth fixing on its own, but it is the status quo, it is not
# gate evidence (gating milestones are excluded from the walker's prefix), and it errs
# toward the gate FIRING rather than toward it being skipped.
#
# These globals are also the walker's outputs and must stay defined regardless: the hook
# runs under `set -u` and the renderer reads them unconditionally. Leaving them unset
# once made the hook die and emit NOTHING, and every test still passed, because "no
# chain was started" is satisfied just as well by a crash as by a deliberate skip.
COMPOSITION_CHAIN=""
COMPOSITION_DIRECTIVE=""
DRIVER_PRECONDITION=""
_walk_composition_chain
# CALL ORDER IS LOAD-BEARING: immediately after the walker and BEFORE the
# consultation block. The fallback fires only when COMPOSITION_CHAIN is empty,
# and the block below EMPTIES it — so the same call placed after the block would
# see an emptied chain on a consultation prompt and hand "ask codex about this
# schema" a DESIGN precondition it never asked for. Here it sees the chain the
# walker actually resolved, and the block then clears the render alongside it.
_render_driver_precondition
if _prompt_is_consultation_only; then
  COMPOSITION_CHAIN=""
  COMPOSITION_DIRECTIVE=""
  # Cleared for the same reason as the chain: a consultation is not a request to
  # start development work, so it must not be handed the phase driver's
  # precondition either. This covers the case the ordering above cannot — a
  # consultation prompt whose only matches are domain skills never had a chain,
  # so the fallback legitimately rendered and this is what suppresses it.
  DRIVER_PRECONDITION=""
  [[ -n "${SKILL_EXPLAIN:-}" ]] && \
    printf '[skill-hook]   [consultation] chain DISPLAY suppressed; state NOT suppressed\n' >&2
fi

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
- Summarizing changes instead of dispatching a code-reviewer subagent (general-purpose + the superpowers code-reviewer.md template; prefer pr-review-toolkit:code-reviewer or feature-dev:code-reviewer when installed)
- Not providing BASE_SHA and HEAD_SHA git diff range to the reviewer
- Claiming review is complete without acting on critical/important findings
- Skipping security-scanner during review (Invoke Skill(auto-claude-skills:security-scanner) for deterministic scanning)"
    # Standing reviewer-dispatch authorization. Default is "auto"; ANY read
    # failure (no file, no key, no jq, unparseable) also yields "auto",
    # because falling back to silence would restore the very stall this
    # renders to remove. Opt out with review_dispatch: "ask".
    _RD_MODE="auto"
    if command -v jq >/dev/null 2>&1 && [[ -f "${HOME}/.claude/skill-config.json" ]]; then
      _RD_RAW="$(jq -r '.phase_enforcement.review_dispatch // "auto"' \
                 "${HOME}/.claude/skill-config.json" 2>/dev/null)" || _RD_RAW="auto"
      if [[ "${_RD_RAW}" == "ask" ]]; then _RD_MODE="ask"; fi
    fi
    if [[ "${_RD_MODE}" != "ask" ]]; then
      RED_FLAGS="${RED_FLAGS}
REVIEWER DISPATCH: dispatching a read-only reviewer subagent is pre-authorized for this phase. Dispatch it directly; do NOT pause to ask the user to approve the dispatch. This authorization covers agents that only read and report. It does NOT cover agents that edit files, push, or take outbound actions — those still require approval."
    fi
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
    # #306: this directive carried its own copy of the #248 broken pair. It is
    # SKILL_LINES, not hints[].text, so no config lint reaches it — but it
    # renders into the same prompt and failed the same way. It is a command to
    # PASTE, so it takes the single-quoted, escaped form.
    #
    # It calls the PRECONDITION expander directly rather than the composition
    # classifier, for two reasons. (1) The consumer here is KNOWN — this is a
    # pasted command, always — so classifying it at runtime would make the
    # escaping contingent on the literal below keeping its quotes; an edit that
    # dropped them would silently fall to the unescaped branch, and the lint on
    # that line only checks for the ABSENCE of the broken pair, which would
    # stay true. Asking for the treatment directly cannot fail that way.
    # (2) The classifier is named for composition hints; this is not one.
    _cprecond='{{PLUGIN_ROOT}}/scripts/persist-state.sh'
    _expand_precondition_plugin_root
    _IE_PS="'${_cprecond}'"
    SKILL_LINES="${SKILL_LINES}
INTENT EXTRACTION: If your ask is underspecified (missing one or more of who/why/success-criteria/constraints), do NOT propose approaches, designs, or options yet. First converge with the user on the real goal — the underlying need, not just the literal request. Then, as soon as the user has given you enough to act on, you MUST — BEFORE proposing ANY approach, design, or option — emit this convergence block verbatim and stop for confirmation:
  **Confirmed intent:** <one line capturing who/why/success>
  **Out-of-scope:** <what this is explicitly NOT>
Only AFTER the user confirms that block may you propose approaches. Then persist it in ONE Bash call: \`bash ${_IE_PS} set-intent \"<confirmed intent> :: out-of-scope: <...>\"\` — the script resolves the session token internally (issue #157), so you author only the intent text. SKIP this pass entirely if the ask is already fully specified, is mechanical (rename/typo/file-move), or an approved discovery brief already covers intent."
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
