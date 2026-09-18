#!/bin/bash
# pilot-egress-check.sh — refuse to transmit an artifact whose embedded data is
# not the frozen pilot fixture.
#
# The trifecta review found the residual risk: an arm reads real portfolio data
# by absolute path and inlines it, and a human preview of a 7 KB HTML file will
# not catch a plausible-looking row. This check is mechanical on purpose — no
# human judgement is involved in the refusal.
#
# Refuses on ANY doubt (missing block, two blocks, malformed JSON, absent
# fixture, no jq). Refusing costs one regeneration; allowing costs a leak.
set -u

_die() { printf 'pilot-egress-check: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || _die "usage: pilot-egress-check.sh <artifact.html> <fixture.json>"
_ART="$1"; _FIX="$2"

[ -r "${_ART}" ] || _die "artifact unreadable: ${_ART} — refused"
[ -r "${_FIX}" ] || _die "fixture unreadable: ${_FIX} — refused"
command -v jq >/dev/null 2>&1 || _die "jq unavailable — refused rather than skipped"

_RESULT="$(awk '
  { doc = doc $0 "\n" }
  END {
    # Count opening tags and extract first block body
    n = 0
    pos = 1
    body = ""
    while (match(substr(doc, pos), /<script[^>]*id="dion-report"[^>]*>/)) {
      n++
      tag_start = pos + RSTART - 1
      tag_end = tag_start + RLENGTH - 1
      close_pos = index(substr(doc, tag_end + 1), "</script>")
      if (close_pos == 0) {
        print "ERROR: no closing tag"
        exit 1
      }
      if (n == 1) {
        body = substr(doc, tag_end + 1, close_pos - 1)
      }
      pos = tag_end + close_pos + 8
    }
    print n
    print body
  }
' "${_ART}" 2>/dev/null)"

_N="$(printf '%s\n' "${_RESULT}" | head -1)"
_EMB="$(printf '%s\n' "${_RESULT}" | tail -n +2)"

[ -z "${_N}" ] && _die "awk extraction failed — refused"
[ "${_N}" = "ERROR: no closing tag" ] && _die "opening tag has no closing tag — refused"
[ "${_N}" = "1" ] || _die "expected exactly one data block, found ${_N} — refused"
[ -n "${_EMB}" ] || _die "data block is empty — refused"

_A="$(printf '%s' "${_EMB}" | jq -S -c . 2>/dev/null)" \
    || _die "embedded block is not valid JSON — refused"
_B="$(jq -S -c . "${_FIX}" 2>/dev/null)" \
    || _die "fixture is not valid JSON — refused"

[ "${_A}" = "${_B}" ] \
    || _die "embedded data differs from the frozen fixture — refused"

printf 'ok: embedded data matches the frozen fixture\n'
