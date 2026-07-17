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

# Parse "- name: X" / "run: CMD" pairs. A declared name whose run: is missing
# (typo'd key) is emitted with an EMPTY run so the loop records it in
# could_not_verify[] — a declared-but-never-run check must never silently
# vanish from the verdict (that would under-gate toward a false clean).
PAIRS="$(awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
        if (n != "") printf "%s\x1f\n", n
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/,""); n=$0; next
    }
    /^[[:space:]]*run:/ { sub(/^[[:space:]]*run:[[:space:]]*/,""); if (n != "") { printf "%s\x1f%s\n", n, $0; n="" } }
    END { if (n != "") printf "%s\x1f\n", n }
' "$VY")"
[ -n "$PAIRS" ] || { echo "verify-and-record: no commands declared in .verify.yml" >&2; exit 1; }

# Capture the session token BEFORE running the gate (issue #122). This repo's
# suite runs ~3 minutes; a concurrent session prompting in that window rebinds
# the shared last-writer-wins singleton (~/.claude/.skill-session-token), and a
# post-run read would bind the verdict to the SIBLING's token — the writer would
# then measure PASS but the push gate, reading the own-token file, would still
# deny. An explicit SKILL_SESSION_TOKEN (e.g. the invoking skill's hook-payload
# token, per issue #51 payload-first resolution) wins over the file.
TOKEN="${SKILL_SESSION_TOKEN:-}"
[ -n "$TOKEN" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null || echo default)"

PASSED=""; FAILED=""; CNV=""; CMDS=""
LOG="$(mktemp "${TMPDIR:-/tmp}/verify-and-record.XXXXXX")" || exit 1
trap 'rm -f "$LOG"' EXIT

# Note: fail_fast in .verify.yml is deliberately unhonored — every command
# runs and is recorded, so a later failure is never hidden by an earlier one.
# 127 detection catches a missing top-level command; a missing command inside
# a pipeline is masked by the shell (no pipefail), same as CI/manual runs.
while IFS=$'\x1f' read -r name run; do
    [ -n "$name" ] || continue
    if [ -z "$run" ]; then
        CNV="${CNV}${CNV:+,}${name}"; echo "gate ${name}: NO run: DECLARED (could not verify)"
        continue
    fi
    CMDS="${CMDS}${CMDS:+ && }${run}"
    # stdin nulled: suites block on a socket-inherited stdin (repo gotcha).
    # set +u: the gate command runs as it would in CI/manual shells — the
    # script's own strictness must not fail a command that tolerates unset
    # optional env vars.
    ( cd "$ROOT" && set +u && eval "$run" ) </dev/null >>"$LOG" 2>&1
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

# Gate-gaming check: checker resolved from the PLUGIN root (target repos
# don't vendor it); diff base resolved via the guard's own _routing_base
# (verdict.sh) — MAINLINE-first, never the branch's own upstream first (an
# @{u}-first base collapses to ~HEAD on a pushed branch and under-scopes the
# check). Anything unresolvable — lib missing, no mainline ref, git diff
# itself failing — is unverified, never assumed clean; only a diff that was
# actually COMPUTED (even if empty) reaches the checker.
GG_STATUS="unverified"
GGC="${PLUGIN_ROOT}/skills/project-verification/scripts/gate-gaming-check.sh"
BASE=""
if [ -f "${PLUGIN_ROOT}/hooks/lib/verdict.sh" ]; then
    # shellcheck source=/dev/null
    . "${PLUGIN_ROOT}/hooks/lib/verdict.sh" 2>/dev/null || true
    command -v _routing_base >/dev/null 2>&1 && BASE="$(_routing_base "$ROOT" 2>/dev/null)" || BASE=""
fi
if [ -n "$BASE" ] && [ -f "$GGC" ]; then
    # Canonical a/-b/ prefixes pinned: the checker's file tracker parses diff
    # headers, and a user diff.mnemonicPrefix/noprefix gitconfig would change
    # them per-machine (the checker also tolerates variant prefixes — belt AND
    # suspenders, this is gate evidence).
    if DIFF="$(git -C "$ROOT" -c diff.mnemonicPrefix=false -c diff.noprefix=false diff "$BASE"...HEAD -- '*test*' '*spec*' '.verify.yml' 2>/dev/null)"; then
        GG="$(printf '%s' "$DIFF" | bash "$GGC" 2>/dev/null)"
        case "$GG" in clean) GG_STATUS="clean" ;; suspect*) GG_STATUS="suspect" ;; esac
    fi
fi
[ "$GG_STATUS" = "unverified" ] && CNV="${CNV}${CNV:+,}gate-gaming-check"

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
' > "${OUT}.tmp.$$" || { rm -f "${OUT}.tmp.$$"; echo "verify-and-record: verdict write failed" >&2; exit 1; }
mv "${OUT}.tmp.$$" "$OUT" || { rm -f "${OUT}.tmp.$$"; echo "verify-and-record: verdict write failed" >&2; exit 1; }

echo "verdict written: $OUT"
jq -c '{passed,failed,could_not_verify,gate_gaming_status,sha}' "$OUT"
