#!/bin/bash
# verify-and-record.sh — deterministic verification-verdict writer.
#
# Runs the target repo's declared gate (.verify.yml, substrate: local) and
# writes ~/.claude/.skill-project-verified-<token> from ITS OWN measured exit
# codes and gate-gaming-check output. The model invokes this script during
# the project-verification skill but never authors the verdict content —
# measured provenance, and the write is not the model self-certifying.
#
# HONEST BY CONSTRUCTION: failures (non-zero exit) go to failed[], unrunnable
# commands (exit 127) to could_not_verify[], an unrunnable gate-gaming check
# is recorded as unverified — nothing is asserted, only measured. This is NOT
# a trust boundary (the artifact stays shell-writable; external CI is the
# boundary, per the skill's own disclaimer) — it is provenance + ergonomics.
#
# Exit code: 0 = a verdict was RECORDED (even an all-failing one — recording
# is this script's job); non-zero = could not measure or write (no .verify.yml,
# non-local substrate, no git repo, jq missing, write failure). Callers must
# read the printed verdict summary, never treat exit 0 as "gates passed".
#
# Bash 3.2.

set -u

# Plugin root: env, else this script's parent dir (scripts/ -> repo root).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "verify-and-record: not a git repo" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "verify-and-record: jq required to write the verdict" >&2; exit 1; }
VY="${ROOT}/.verify.yml"
[ -f "$VY" ] || { echo "verify-and-record: no .verify.yml — refusing to guess the gate (see project-verification discovery ladder)" >&2; exit 1; }

SUBSTRATE="$(awk -F': *' '$1=="substrate"{print $2; exit}' "$VY")"
[ "$SUBSTRATE" = "local" ] || { echo "verify-and-record: unsupported substrate '${SUBSTRATE:-none}' — only 'local' runs here" >&2; exit 1; }

# Parse "- name: X" / "run: CMD" pairs.
PAIRS="$(awk '
    /^[[:space:]]*-[[:space:]]*name:/ { sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/,""); n=$0; next }
    /^[[:space:]]*run:/ { sub(/^[[:space:]]*run:[[:space:]]*/,""); if (n != "") { printf "%s\x1f%s\n", n, $0; n="" } }
' "$VY")"
[ -n "$PAIRS" ] || { echo "verify-and-record: no commands declared in .verify.yml" >&2; exit 1; }

PASSED=""; FAILED=""; CNV=""; CMDS=""
LOG="$(mktemp "${TMPDIR:-/tmp}/verify-and-record.XXXXXX")" || exit 1
trap 'rm -f "$LOG"' EXIT

while IFS=$'\x1f' read -r name run; do
    [ -n "$name" ] || continue
    CMDS="${CMDS}${CMDS:+ && }${run}"
    # stdin nulled: suites block on a socket-inherited stdin (repo gotcha).
    ( cd "$ROOT" && eval "$run" ) </dev/null >>"$LOG" 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
        PASSED="${PASSED}${PASSED:+,}${name}";  echo "gate ${name}: PASS (exit 0)"
    elif [ "$rc" -eq 127 ]; then
        CNV="${CNV}${CNV:+,}${name}";           echo "gate ${name}: COULD NOT RUN (exit 127)"
    else
        FAILED="${FAILED}${FAILED:+,}${name}";  echo "gate ${name}: FAIL (exit ${rc})"
    fi
done <<EOF
$PAIRS
EOF

# Gate-gaming check: resolved from the PLUGIN root (target repos don't vendor
# it). Empty output = the check could not run => unverified, per the skill
# contract — never assumed clean.
GGC="${PLUGIN_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"
BASE="$(git -C "$ROOT" merge-base HEAD @{u} 2>/dev/null || git -C "$ROOT" merge-base HEAD main 2>/dev/null || echo HEAD~1)"
GG="$(git -C "$ROOT" diff "$BASE"...HEAD -- '*test*' '*spec*' 2>/dev/null | bash "$GGC" 2>/dev/null)"
GG_STATUS="unverified"
case "$GG" in clean) GG_STATUS="clean" ;; suspect*) GG_STATUS="suspect" ;; esac
[ "$GG_STATUS" = "unverified" ] && CNV="${CNV}${CNV:+,}gate-gaming-check"

TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null || echo default)"
SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXCERPT="$(tail -c 600 "$LOG" 2>/dev/null | tr -d '\000-\010\013-\037' | tr '\n' ' ')"
OUT="${HOME}/.claude/.skill-project-verified-${TOKEN}"

jq -n --arg sha "$SHA" --arg ts "$TS" --arg ex "$EXCERPT" --arg cmd "$CMDS" \
      --arg p "$PASSED" --arg f "$FAILED" --arg c "$CNV" --arg gg "$GG_STATUS" '
  def csv($s): if $s == "" then [] else ($s | split(",")) end;
  {substrate:"local", discovery_source:"verify-yml",
   passed:csv($p), failed:csv($f), could_not_verify:csv($c),
   gate_gaming_status:$gg, coverage_adequacy_status:"unverified",
   sha:$sha, command:$cmd, output_excerpt:$ex, ts:$ts,
   writer:"verify-and-record.sh"}
' > "$OUT" || { echo "verify-and-record: verdict write failed" >&2; exit 1; }

echo "verdict written: $OUT"
jq -c '{passed,failed,could_not_verify,gate_gaming_status,sha}' "$OUT"
