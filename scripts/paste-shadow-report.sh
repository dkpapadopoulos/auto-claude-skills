#!/bin/bash
# paste-shadow-report.sh [DIR] — read the #409 pasted-content shadow records.
#
# The activation hook writes one record per prompt carrying a harness paste wrapper to
# ~/.claude/.paste-shadow.d/ (DIR overrides). Nothing else reads them, and a corpus with no
# reader reaches its pre-registered floor unseen (#239), so this ships with the writer. It
# prints counts only, as "key: value" lines:
#   records         parsed records
#   sessions        distinct session tokens among them
#   with_pairs      records where the parser found at least one paste pair. Any value above 0
#                   is the pre-registration's G0 evidence that the hook payload carries the
#                   wrapper as the transcripts do.
#   process_hidden  records with a pair whose process mandate rule R would hide
#   process_kept    records with a pair whose process mandate R keeps
#   drift           status ok, opener present, no pair: a wrapper the parser does not know
#   capped, error   the parser's other two non-parsing outcomes
#   malformed       lines that are not a JSON object (counted, never dropped silently)
#   first, last     the earliest and latest record timestamps
# It decides nothing: the confirmation read is in docs/plans/2026-11-17-paste-scoring-409-prereg.md.
#
# Exit: 0 counted (including "no record directory", which says so); 3 cannot check (jq
# missing, the directory or a record unreadable). An unreadable corpus is never reported
# as empty.
set -u
D="${1:-${HOME}/.claude/.paste-shadow.d}"
command -v jq >/dev/null 2>&1 || { echo "cannot check: jq not found" >&2; exit 3; }
if [ ! -e "${D}" ]; then
    printf 'no record directory: %s\nrecords: 0\n' "${D}"
    exit 0
fi
if [ ! -d "${D}" ] || [ ! -r "${D}" ] || [ ! -x "${D}" ]; then
    echo "cannot check: ${D} is not a readable directory" >&2
    exit 3
fi
_all="$(find "${D}" -maxdepth 1 -type f -exec cat {} + 2>/dev/null)" || {
    echo "cannot check: a record under ${D} could not be read" >&2
    exit 3
}
printf '%s\n' "${_all}" | jq -nrR '
  [inputs | select(length > 0) | (try fromjson catch null)] as $all
  | [$all[] | select(type == "object" and has("schema_version"))] as $r
  | [$r[] | select((.pairs // 0) >= 1)] as $p
  | "records: \($r | length)",
    "sessions: \([$r[].session] | unique | length)",
    "with_pairs: \($p | length)",
    "process_hidden: \([$p[] | select((.process // "") != "" and .process_kept == false)] | length)",
    "process_kept: \([$p[] | select((.process // "") != "" and .process_kept == true)] | length)",
    "drift: \([$r[] | select(.status == "ok" and (.pairs // 0) == 0)] | length)",
    "capped: \([$r[] | select(.status == "capped")] | length)",
    "error: \([$r[] | select(.status == "error")] | length)",
    "malformed: \(($all | length) - ($r | length))",
    "first: \([$r[].ts] | min // "-")",
    "last: \([$r[].ts] | max // "-")"
' || { echo "cannot check: jq failed reading ${D}" >&2; exit 3; }
