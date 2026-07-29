#!/bin/bash
# memory-leak-check.sh — deterministic private-memory leak detector (issue #174).
#
#   memory-leak-check.sh <body-file>
#
# Flags any run of N_WORDS consecutive normalized words in <body-file> that
# appears in the local memory corpus and NOT in the repository's tracked
# content at HEAD. Text already in the public repo is definitionally not a leak.
#
# Exit: 0 clean | 1 leak | 2 usage | 3 cannot check.
#
# Output names LOCATIONS ONLY. It must never reproduce matched text — a control
# that prints the private string hands the caller the bytes to paste again.
set -u

N_WORDS=16

BODY="${1:-}"
[ -n "${BODY}" ] || { echo "usage: memory-leak-check.sh <body-file>" >&2; exit 2; }
[ -r "${BODY}" ] || { echo "ERROR: cannot read body file: ${BODY}" >&2; exit 3; }

# --- corpus resolution: mirrors mine-evidence.sh::memory_dir exactly ---------
memory_dir() {
    if [ -n "${MEMORY_LEAK_CHECK_MEMORY_DIR:-}" ]; then
        printf '%s' "${MEMORY_LEAK_CHECK_MEMORY_DIR}"; return
    fi
    local common root slug
    common="$(git rev-parse --git-common-dir 2>/dev/null)" || { printf ''; return; }
    root="$(cd "$(dirname "${common}")" && pwd -P)" || { printf ''; return; }
    slug="$(printf '%s' "${root}" | sed 's|[/.]|-|g')"
    printf '%s' "${HOME}/.claude/projects/${slug}/memory"
}

MEMDIR="$(memory_dir)"
if [ -z "${MEMDIR}" ] || [ ! -d "${MEMDIR}" ]; then
    echo "NOTE: no memory corpus at '${MEMDIR:-<unresolved>}' — nothing to leak, not checked" >&2
    exit 0
fi

# --- shingling ---------------------------------------------------------------
# Emits: <file>\t<line>\t<shingle>. The word buffer RESETS at each file
# boundary: without that, a run formed by the tail of one file plus the head of
# the next fabricates a match (observed in the prototype).
# split("",arr) rather than `delete arr` — portable across awk implementations.
shingle_files() {
    awk -v n="${N_WORDS}" '
        function flush(   i, j, s) {
            for (i = 1; i + n - 1 <= c; i++) {
                s = w[i]
                for (j = 1; j < n; j++) s = s " " w[i + j]
                print fname "\t" ln[i] "\t" s
            }
            split("", w); split("", ln); c = 0
        }
        FNR == 1 && NR > 1 { flush() }
        FNR == 1 { fname = FILENAME }
        {
            gsub(/[^a-zA-Z0-9]/, " "); $0 = tolower($0)
            for (i = 1; i <= NF; i++) { w[++c] = $i; ln[c] = FNR }
        }
        END { flush() }
    ' "$@"
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/mlc.XXXXXXXX")" || exit 3
trap 'rm -rf "${TMP}"' EXIT

set -- "${MEMDIR}"/*.md
[ -e "$1" ] || { echo "NOTE: no memory corpus files in '${MEMDIR}' — nothing to leak" >&2; exit 0; }
shingle_files "$@" | awk -F'\t' '{ n = split($1, p, "/"); print $3 "\t" p[n] "\t" $2 }' \
    | sort -t"$(printf '\t')" -k1,1 > "${TMP}/mem"

shingle_files "${BODY}" | awk -F'\t' '{ print $3 "\t" $2 }' \
    | sort -t"$(printf '\t')" -k1,1 > "${TMP}/body"

# candidate hits: <shingle>\t<body-line>\t<mem-file>\t<mem-line>
join -t"$(printf '\t')" -1 1 -2 1 -o 0,1.2,2.2,2.3 "${TMP}/body" "${TMP}/mem" \
    > "${TMP}/hits" 2>/dev/null || : > "${TMP}/hits"

[ -s "${TMP}/hits" ] || exit 0

# --- public exemption --------------------------------------------------------
# Only built once a candidate exists, so the cost lands on the deny path.
# One normalized line PER TRACKED FILE, so a grep -F match cannot span files.
git ls-files -z 2>/dev/null \
    | xargs -0 awk '
        function flush() { if (buf != "") print buf; buf = "" }
        FNR == 1 && NR > 1 { flush() }
        { gsub(/[^a-zA-Z0-9]/, " "); $0 = tolower($0)
          for (i = 1; i <= NF; i++) buf = buf (buf == "" ? "" : " ") $i }
        END { flush() }
      ' 2>/dev/null > "${TMP}/repo" || : > "${TMP}/repo"

# Overlapping shingles from one passage all resolve to the same (body line,
# source line) pair — a single 20-word run yields 5 hits. Dedupe so the report
# counts RUNS, not shingles (verified: 6 identical lines before this fix).
while IFS="$(printf '\t')" read -r shingle bline mfile mline; do
    [ -n "${shingle}" ] || continue
    if [ -s "${TMP}/repo" ] && grep -Fq -- "${shingle}" "${TMP}/repo" 2>/dev/null; then
        continue   # already public in this repo
    fi
    printf 'LEAK: body line %s <- memory/%s:%s\n' "${bline}" "${mfile}" "${mline}"
done < "${TMP}/hits" | sort -u > "${TMP}/findings"

FOUND="$(wc -l < "${TMP}/findings" | tr -d ' ')"

if [ "${FOUND}" -gt 0 ]; then
    cat "${TMP}/findings"
    echo "${FOUND} private-memory run(s) of ${N_WORDS}+ words found. Cite memory/<file>.md:<line> instead of quoting."
    exit 1
fi
exit 0
