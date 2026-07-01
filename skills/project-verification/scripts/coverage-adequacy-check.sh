#!/bin/bash
# coverage-adequacy-check.sh — deterministic test-adequacy tripwire.
# Mirrors gate-gaming-check.sh: advisory, fail-open (exit 0 always). Empty stdout
# means "unverified" (no coverage artifact / unparseable) — the caller treats empty
# as unverified, a normal run prints an explicit clean|suspect.
# Modes (COVERAGE_ADEQUACY_MODE): changed-lines (debug: emit added path\tline) |
# verdict (default: emit clean|suspect + uncovered lines).
set -u

# _changed_lines: unified diff on stdin -> "path<TAB>newline" per added content line.
_changed_lines() {
  awk '
    /^\+\+\+ / { f=$2; sub(/^b\//,"",f); next }
    /^--- /    { next }
    /^@@ /     { match($0, /\+[0-9]+/); ln=substr($0,RSTART+1,RLENGTH-1)+0; next }
    /^\+/      { if (f!="") print f "\t" ln; ln++; next }
    /^-/       { next }
    /^ /       { ln++; next }
  '
}

# _lcov_hits <file>: emit "sourcepath<TAB>line<TAB>hits" for each DA record.
_lcov_hits() {
  awk -F'[:,]' '
    /^SF:/ { sf=substr($0,4); next }
    /^DA:/ { print sf "\t" $2 "\t" $3 }
  ' "$1" 2>/dev/null
}

# _cobertura_hits <xml>: one <line number= hits=> per output row as path<TAB>line<TAB>hits.
_cobertura_hits() {
  awk '
    match($0, /filename="[^"]*"/) { fn=substr($0,RSTART+10,RLENGTH-11) }
    {
      s=$0
      while (match(s, /<line number="[0-9]+" hits="[0-9]+"/)) {
        adv=RSTART+RLENGTH
        seg=substr(s,RSTART,RLENGTH)
        match(seg,/number="[0-9]+"/); num=substr(seg,RSTART+8,RLENGTH-9)
        match(seg,/hits="[0-9]+"/);   h=substr(seg,RSTART+6,RLENGTH-7)
        if (fn!="") print fn "\t" num "\t" h
        s=substr(s,adv)
      }
    }
  ' "$1" 2>/dev/null
}

_mode="${COVERAGE_ADEQUACY_MODE:-verdict}"
_diff="$(cat 2>/dev/null || true)"

if [ "$_mode" = "changed-lines" ]; then
  printf '%s\n' "$_diff" | _changed_lines
  exit 0
fi

if [ "$_mode" = "lcov-hits" ]; then
  [ -f "${COVERAGE_ADEQUACY_LCOV:-}" ] && _lcov_hits "${COVERAGE_ADEQUACY_LCOV}"
  exit 0
fi

if [ "$_mode" = "cobertura-hits" ]; then
  [ -f "${COVERAGE_ADEQUACY_LCOV:-}" ] && _cobertura_hits "${COVERAGE_ADEQUACY_LCOV}"
  exit 0
fi

_floor="${COVERAGE_ADEQUACY_FLOOR:-80}"
[[ "$_floor" =~ ^[0-9]+$ ]] || _floor=80

_lcov="${COVERAGE_ADEQUACY_LCOV:-}"
if [ ! -f "$_lcov" ]; then echo "unverified"; exit 0; fi

# Build "path<TAB>line -> hits" table from the coverage artifact; suffix-match diff paths
# against source paths. Auto-select parser by extension: *.xml -> cobertura, else lcov.
case "$_lcov" in
  *.xml) _cov="$(_cobertura_hits "$_lcov")" ;;
  *)     _cov="$(_lcov_hits "$_lcov")" ;;
esac
_changed="$(printf '%s\n' "$_diff" | _changed_lines)"

# Join: for each changed path:line, is there a coverage record (suffix match) and hits>0?
_join="$(awk -F'\t' '
  NR==FNR { key=$1 SUBSEP $2; hits[key]=$3; paths[$1]=1; next }
  {
    cp=$1; cl=$2; matched=0; covered=0
    for (p in paths) {
      # suffix match either direction (handle abs vs rel paths)
      if (p==cp || index(p, "/" cp) == length(p)-length(cp) || index(cp, "/" p) == length(cp)-length(p)) {
        k=p SUBSEP cl
        if (k in hits) { matched=1; if (hits[k]+0>0) covered=1; break }
      }
      k2=cp SUBSEP cl
      if (k2 in hits) { matched=1; if (hits[k2]+0>0) covered=1; break }
    }
    if (matched) { total++; if (covered) cov++; else print "UNCOV\t" cp ":" cl }
  }
  END { print "TOTAL\t" total+0 "\t" cov+0 }
' <(printf '%s\n' "$_cov") <(printf '%s\n' "$_changed"))"

_total="$(printf '%s\n' "$_join" | awk -F'\t' '/^TOTAL/{print $2}')"
_covn="$(printf '%s\n' "$_join" | awk -F'\t' '/^TOTAL/{print $3}')"
[[ "$_total" =~ ^[0-9]+$ ]] || _total=0
[[ "$_covn" =~ ^[0-9]+$ ]] || _covn=0

if [ "$_total" -eq 0 ]; then echo "unverified"; exit 0; fi

_pct=$(( _covn * 100 / _total ))
if [ "$_pct" -lt "$_floor" ]; then
  echo "suspect"
  printf '%s\n' "$_join" | awk -F'\t' '/^UNCOV/{print "> " $2}'
  exit 0
fi
echo "clean"
exit 0
