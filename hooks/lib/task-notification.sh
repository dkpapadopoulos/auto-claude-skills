#!/bin/bash
# task-notification.sh — classify a UserPromptSubmit prompt: is it a background-task
# notification, the user, or impossible to tell? Shared by egress-consent-turn-hook.sh
# (a notification must not end an egress approval) and skill-activation-hook.sh (a
# notification must not be routed), so the two cannot drift.
#
# Defines TASK_NOTIFICATION_JQ_DEF, a jq definition to prepend to a program:
#   notification_kind: string -> "notification" | "prompt" | "unclassifiable"
# Sourcing defines nothing else and runs no command. A hook that cannot source it must
# fall back to its pre-existing behaviour (see each hook's fallback definition).
#
# Measured live 2026-09-17: a background-task notification arrives as UserPromptSubmit
# whose prompt is the "<task-notification>" block. It is not the user speaking, and treating
# it as a turn boundary revoked a genuine approval mid-flow.
# A prompt counts as a notification only if it consists ENTIRELY of notification blocks:
# a user who pastes one and then writes "no" is the user speaking.
# - A block body may not contain a closing tag (a lazy `.*?` backtracks across one, so
#   text BETWEEN two blocks matched).
# - A nested block — an opening tag right after the outer one, or at the start of a line —
#   is not a notification shape. An opening tag QUOTED mid-line (a command description,
#   an agent result about this feature) is allowed: rejecting it withdrew approvals on
#   genuine notifications.
# - "Start of a line" means after any vertical-space character (LF, CR, VT, FF, NEL,
#   U+2028, U+2029), optionally indented with spaces/tabs. VT is written \x{0B}: in jq's
#   regex syntax `\v` is a literal letter v (measured), which silently broke both
#   directions in an earlier revision.
# - If the regex engine cannot evaluate the prompt (retry limit on multi-MB input), the
#   prompt is treated as the user speaking: withdrawing is the safe direction.
# - Known costs (safe direction, one re-ask): a genuine notification whose text starts a
#   line with an opening tag (an XML example in an agent result), or quotes the CLOSING tag
#   anywhere, is treated as the user.
# - Plain text typed INSIDE one well-formed block is indistinguishable from a
#   notification's free-text fields (agent results are arbitrary): accepted residual.
# Fixture: tests/fixtures/egress-consent/task-notification-bash.txt, captured live
# 2026-09-17 — nothing follows the closing tag. Agent-completion notifications were not
# captured; if one ever carries trailing text it is treated as the user (one re-ask).
# Regression: tests/test-consult-dispatch.sh (R7-R10), tests/test-activation-notification-skip.sh.
TASK_NOTIFICATION_JQ_DEF='def notification_kind:
  try (if test("^\\s*(<task-notification>(?![ \\t]*<task-notification>)(?:(?!</task-notification>|[\\n\\r\\x{0B}\\f\\x{85}\\x{2028}\\x{2029}][ \\t]*<task-notification>)[\\s\\S])*</task-notification>\\s*)+$")
       then "notification" else "prompt" end)
  catch "unclassifiable";'
