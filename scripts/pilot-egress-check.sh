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
#
# Attribute matching accepts EITHER quote style. A double-quote-literal matcher
# does not merely mis-report a single-quoted block, it does not COUNT one — so a
# second, single-quoted `id='dion-report'` block was invisible to the
# duplicate-block refusal while being perfectly visible to a browser. The same
# reasoning extends the duplicate check to any `<script type="application/json">`
# block regardless of its id: a second JSON payload under another id is exactly
# the shape a leak would take, and this check has no opinion about it otherwise.
#
# Consequence worth knowing before launch: because the duplicate check counts
# `type="application/json"` openers, a block that omits that attribute entirely
# is now refused ("found 0"), where before it could pass on data alone. The
# brief mandates `<script type="application/json" id="dion-report">`, so this is
# the contract being enforced rather than a new opinion — attribute ORDER is
# free, the attribute itself is not.
#
# Scope, stated rather than implied: this validates the DESIGNATED data block.
# It does not validate the rest of the artifact — real holdings rendered into
# the visible HTML body are out of its reach, and that is named as residual in
# the design doc rather than papered over here.
set -u

_die() { printf 'pilot-egress-check: %s\n' "$*" >&2; exit 1; }

[ $# -eq 2 ] || _die "usage: pilot-egress-check.sh <artifact.html> <fixture.json>"
_ART="$1"; _FIX="$2"

[ -r "${_ART}" ] || _die "artifact unreadable: ${_ART} — refused"
[ -r "${_FIX}" ] || _die "fixture unreadable: ${_FIX} — refused"
command -v jq >/dev/null 2>&1 || _die "jq unavailable — refused rather than skipped"

_RESULT="$(awk -v Q="'" '
  BEGIN {
    # Built at runtime so both quote styles are matched without needing a
    # literal single quote inside this single-quoted program.
    RX_ID   = "<script[^>]*id=[\"" Q "]dion-report[\"" Q "][^>]*>"
    RX_JSON = "<script[^>]*type=[\"" Q "]application/json[\"" Q "][^>]*>"
  }
  { doc = doc $0 "\n" }
  END {
    # Count id="dion-report" openers (either quote style) and take the first body.
    n = 0
    pos = 1
    body = ""
    while (match(substr(doc, pos), RX_ID)) {
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
    # Count application/json openers of ANY id, independently.
    j = 0
    pos = 1
    while (match(substr(doc, pos), RX_JSON)) {
      j++
      pos = pos + RSTART - 1 + RLENGTH
    }
    print n
    print j
    print body
  }
' "${_ART}" 2>/dev/null)"

_N="$(printf '%s\n' "${_RESULT}" | head -1)"
_J="$(printf '%s\n' "${_RESULT}" | sed -n '2p')"
_EMB="$(printf '%s\n' "${_RESULT}" | tail -n +3)"

[ -z "${_N}" ] && _die "awk extraction failed — refused"
[ "${_N}" = "ERROR: no closing tag" ] && _die "opening tag has no closing tag — refused"
[ "${_N}" = "1" ] || _die "expected exactly one data block, found ${_N} — refused"
[ "${_J}" = "1" ] || _die "expected exactly one application/json block, found ${_J} — refused"
[ -n "${_EMB}" ] || _die "data block is empty — refused"

_A="$(printf '%s' "${_EMB}" | jq -S -c . 2>/dev/null)" \
    || _die "embedded block is not valid JSON — refused"
_B="$(jq -S -c . "${_FIX}" 2>/dev/null)" \
    || _die "fixture is not valid JSON — refused"

[ "${_A}" = "${_B}" ] \
    || _die "embedded data differs from the frozen fixture — refused"

printf 'ok: embedded data matches the frozen fixture\n'
