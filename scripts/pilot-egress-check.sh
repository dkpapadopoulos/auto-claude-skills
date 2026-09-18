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

_N="$(grep -c 'id="dion-report"' "${_ART}" 2>/dev/null)" || _N=0
[ "${_N}" = "1" ] || _die "expected exactly one data block, found ${_N} — refused"

_EMB="$(awk '/<script[^>]*id="dion-report"/{f=1;next} f&&/<\/script>/{exit} f' "${_ART}")"
[ -n "${_EMB}" ] || _die "data block is empty — refused"

_A="$(printf '%s' "${_EMB}" | jq -S -c . 2>/dev/null)" \
    || _die "embedded block is not valid JSON — refused"
_B="$(jq -S -c . "${_FIX}" 2>/dev/null)" \
    || _die "fixture is not valid JSON — refused"

[ "${_A}" = "${_B}" ] \
    || _die "embedded data differs from the frozen fixture — refused"

printf 'ok: embedded data matches the frozen fixture\n'
