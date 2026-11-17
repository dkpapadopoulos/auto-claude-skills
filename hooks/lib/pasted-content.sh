#!/bin/bash
# pasted-content.sh — find the harness's paste wrapper in a prompt (#409).
#
# Defines PASTED_CONTENT_JQ_DEF, a jq definition to prepend to a program:
#   paste_strip: string -> {status, openers, pairs, text}
# Sourcing defines nothing else and runs no command. Used only by the activation hook's
# shadow record; nothing that routes or gates reads its output.
#
# THE WRAPPER, measured in all 79 wrapped prompts on the owner's machine (Claude Code
# 2.1.277..2.1.311, 2026-10-01..11-16): a blank line, `<pasted_content id="hhhh">` with four
# LOWERCASE hex digits, the pasted text, `</pasted_content id="hhhh">` with the SAME id, a
# newline. A tag inside the paste is escaped by the harness (`<\pasted_content>`), so a paste
# cannot close its own block early. No unterminated, mismatched or nested block was seen.
#
# A pair is an opener up to the FIRST closer carrying the same id (lazy body), and the body
# may not contain another opener with that id. Each pair is replaced by one newline, so typed
# words on either side cannot fuse into one token. Everything else is returned byte-identical.
# In particular an opener with no closer of its id strips NOTHING: an unterminated block
# cannot swallow the typed text after it, even when a later block happens to reuse its id
# (without the opener exclusion the lazy body ran from the stray opener to the later closer;
# found in review). A wrapper
# the harness never produced (another id length or case) matches nothing, which reads as
# `status: "ok", pairs: 0` — the signal that the format changed.
#
# status
#   none    the opener literal `<pasted_content id="` does not occur; no regex runs.
#   capped  more than 16 openers; no regex runs, nothing stripped. Each unmatched opener
#           costs a scan of the rest of the prompt (measured with jq 1.8.2: 1,000 openers
#           0.5 s, 4,000 openers 3.3 s); the most a real prompt carried was 2.
#   error   jq raised; nothing stripped. Reached by a non-string, and by the regex engine
#           giving up on a very large body (measured with jq 1.8.2: 4 MB parses, 8 MB is an
#           error in under 0.1 s; the largest real paste measured was 18.6 KB).
#   ok      parsed; `pairs` may be 0.
# Regression: tests/test-pasted-content-lib.sh.
PASTED_CONTENT_JQ_DEF='def paste_strip:
  . as $p
  | "<pasted_content id=\"(?<i>[0-9a-f]{4})\">(?:(?!<pasted_content id=\"\\k<i>\">)[\\s\\S])*?</pasted_content id=\"\\k<i>\">" as $re
  | try (
      ($p | indices("<pasted_content id=\"") | length) as $n
      | if $n == 0 then {status: "none", openers: 0, pairs: 0, text: $p}
        elif $n > 16 then {status: "capped", openers: $n, pairs: 0, text: $p}
        else {status: "ok", openers: $n, pairs: ([$p | match($re; "g")] | length), text: ($p | gsub($re; "\n"))}
        end
    ) catch {status: "error", openers: 0, pairs: 0, text: $p};'
