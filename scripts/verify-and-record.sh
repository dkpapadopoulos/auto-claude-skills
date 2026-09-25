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
# is recorded as unverified, and the recorded sha is the HEAD the gate actually
# ran against (a run that straddles a commit covers no single commit and says
# so, issue #181) — nothing is asserted, only measured. This is NOT
# a trust boundary (the artifact stays shell-writable; external CI is the
# boundary, per the skill's own disclaimer) — it is provenance + ergonomics.
#
# Exit code: 0 = a verdict was RECORDED (even an all-failing one — recording
# is this script's job); non-zero = could not measure or write (no .verify.yml
# AND no explicit commands, non-local substrate, no git repo, jq missing, write
# failure) OR the explicit arguments were REFUSED. The refusals are, e.g.: a
# declared .verify.yml is present, an unknown flag, a flag given with no value,
# --run with no preceding --name, a --name with no --run, a name that is empty /
# duplicated / contains a comma, newline or US, or a command that is empty,
# whitespace-only, multiline or contains US. Treat that list as illustrative --
# any refusal exits non-zero and prints its own reason. Callers must read the
# printed verdict summary, never treat exit 0 as "gates passed".
#
# Bash 3.2.

set -u

# Plugin root: env, else this script's parent dir (scripts/ -> repo root).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

# --- Explicit-commands mode (#295) -------------------------------------------
# This script does two separable jobs: decide WHICH commands are the gate, and
# RUN them while recording what actually happened. It used to refuse both
# together whenever .verify.yml was absent, so project-verification's SKILL.md
# had the MODEL hand-author the verdict JSON instead — and a hand-authored
# record states what the model believed, not what executed.
#
# Explicit mode separates them: the caller (after the discovery ladder's own
# disambiguation, which may involve the user) says which commands constitute the
# gate; this script executes them and records measured exit codes.
#
# It deliberately does NOT infer a gate from manifests. "A declared tool" is not
# "a declared gate": a package script `"test": "echo ok"` would manufacture a
# clean verdict, and creating verdicts where none was intended CHANGES GATE
# OUTCOMES even though no predicate moves (routing-governance newly passes).
# Selection stays with the caller; only measurement moves here.
EXPLICIT_PAIRS=""
_SEEN_NAMES=""
_EXPLICIT_USED=false
_x_name=""
# Validation lives where the value ARRIVES, not where it is consumed. An earlier
# cut validated the name in the --run branch, so a trailing `--name ""` was never
# checked at all and its declared check silently vanished.
_x_validate_name() {
    [ -n "$1" ] || { echo "verify-and-record: name may not be empty" >&2; return 1; }
    # A name is a KEY in the record: it is comma-split at serialization, and the
    # pair transport is read LINE-wise. A newline therefore splits one declared
    # check across two records, in one of two shapes — measured, and only the
    # second is a false clean: "a\nb" yields could_not_verify=[a] failed=[b] (a
    # CORRUPT record), while a BARE newline leaves both records nameless, so the
    # execution loop skips both, the command never runs, and the empty arrays
    # satisfy verdict_is_clean. Refuse both; do not try to repair either.
    case "$1" in
        *,*|*$'\x1f'*|*$'\n'*)
            echo "verify-and-record: name may not contain ',', a newline, or US" >&2; return 1 ;;
    esac
    # NOTE the unquoted $'\x1f' operands: $'..' is NOT expanded inside double
    # quotes, so "$'\x1f'${_SEEN_NAMES}" compares against a literal dollar-quote
    # and never matches. A duplicate name yields a repeated array entry that no
    # reader can attribute back to a command.
    case $'\x1f'"${_SEEN_NAMES}" in
        *$'\x1f'"$1"$'\x1f'*) echo "verify-and-record: duplicate name '$1'" >&2; return 1 ;;
    esac
    return 0
}
while [ $# -gt 0 ]; do
    case "$1" in
        --name)
            _EXPLICIT_USED=true
            [ $# -ge 2 ] || { echo "verify-and-record: --name needs a value" >&2; exit 1; }
            # A pending name with no --run would record a check that never ran.
            [ -z "$_x_name" ] || { echo "verify-and-record: --name '${_x_name}' has no --run" >&2; exit 1; }
            _x_validate_name "$2" || exit 1
            _x_name="$2"
            _SEEN_NAMES="${_SEEN_NAMES}${2}"$'\x1f'
            shift 2 ;;
        --run)
            _EXPLICIT_USED=true
            [ $# -ge 2 ] || { echo "verify-and-record: --run needs a value" >&2; exit 1; }
            [ -n "$_x_name" ] || { echo "verify-and-record: --run without a preceding --name" >&2; exit 1; }
            # $'..' rather than $(printf '\n'): command substitution STRIPS
            # trailing newlines, so a ${2%%$(...)*} guard matches everything and
            # refuses every command. Same idiom the execution loop uses.
            case "$2" in *$'\x1f'*) echo "verify-and-record: run may not contain US" >&2; exit 1 ;; esac
            case "$2" in *$'\n'*) echo "verify-and-record: run may not span lines" >&2; exit 1 ;; esac
            # This REPLACES the old `[ -n "$2" ]`, it does not join it: `-n` was
            # always meant to answer "did the caller supply a command", and it is
            # simply the wrong test for that — a stray space passes it while
            # `eval " "` exits 0, recording PASS having executed nothing. So the
            # justification is that the empty-argument check was buggy, not that
            # we validate command content; there is no slope to slide down.
            #
            # CEILING, deliberate: "executes nothing" is strictly wider than
            # "whitespace only". Measured under bash 3.2, `eval "# npm test"` and
            # `eval ":"` both exit 0 — and a commented-out command is the LIKELIER
            # accident, a caller pasting a line they had disabled. Neither is
            # refused: rejecting `#` means parsing shell intent, and `:` may be
            # genuinely meant. A command that runs but checks nothing is the
            # caller's completeness obligation, which nothing here can adjudicate.
            case "$2" in
                *[![:space:]]*) : ;;
                *) echo "verify-and-record: run may not be empty or whitespace-only" >&2; exit 1 ;;
            esac
            EXPLICIT_PAIRS="${EXPLICIT_PAIRS}${_x_name}"$'\x1f'"$2
"
            _x_name=""; shift 2 ;;
        *) echo "verify-and-record: unknown argument '$1'" >&2; exit 1 ;;
    esac
done
[ -z "$_x_name" ] || { echo "verify-and-record: --name '${_x_name}' has no --run" >&2; exit 1; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "verify-and-record: not a git repo" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "verify-and-record: jq required to write the verdict" >&2; exit 1; }
VY="${ROOT}/.verify.yml"

DISCOVERY="verify-yml"
if [ "$_EXPLICIT_USED" = "true" ]; then
    # A declared gate is the repo's contract and outranks anything a caller
    # passes. Allowing explicit args to win would turn this mode into a way to
    # substitute a narrower check for the declaration.
    { [ -e "$VY" ] || [ -L "$VY" ]; } && { echo "verify-and-record: .verify.yml exists — it is the declared gate; explicit --name/--run refused" >&2; exit 1; }
    [ -n "$EXPLICIT_PAIRS" ] || { echo "verify-and-record: no commands given" >&2; exit 1; }
    DISCOVERY="explicit"
else
    [ -f "$VY" ] || { echo "verify-and-record: no .verify.yml — refusing to guess the gate (see project-verification discovery ladder)" >&2; exit 1; }
fi

if [ "$DISCOVERY" = "verify-yml" ]; then
    SUBSTRATE="$(awk -F': *' '$1=="substrate"{print $2; exit}' "$VY")"
    [ "$SUBSTRATE" = "local" ] || { echo "verify-and-record: unsupported substrate '${SUBSTRATE:-none}' — only 'local' runs here" >&2; exit 1; }
fi

# Parse "- name: X" / "run: CMD" pairs. A declared name whose run: is missing
# (typo'd key) is emitted with an EMPTY run so the loop records it in
# could_not_verify[] — a declared-but-never-run check must never silently
# vanish from the verdict (that would under-gate toward a false clean).
if [ "$DISCOVERY" = "explicit" ]; then
    PAIRS="$EXPLICIT_PAIRS"
else
PAIRS="$(awk '
    /^[[:space:]]*-[[:space:]]*name:/ {
        if (n != "") printf "%s\x1f\n", n
        sub(/^[[:space:]]*-[[:space:]]*name:[[:space:]]*/,""); n=$0; next
    }
    /^[[:space:]]*run:/ { sub(/^[[:space:]]*run:[[:space:]]*/,""); if (n != "") { printf "%s\x1f%s\n", n, $0; n="" } }
    END { if (n != "") printf "%s\x1f\n", n }
' "$VY")"
fi
if [ -z "$PAIRS" ]; then
    if [ "$DISCOVERY" = "explicit" ]; then
        echo "verify-and-record: no commands given" >&2
    else
        echo "verify-and-record: no commands declared in .verify.yml" >&2
    fi
    exit 1
fi

# Capture the session token BEFORE running the gate (issue #122). This repo's
# suite runs ~16 minutes (measured 943s at c2ae84f); a concurrent session prompting in that window rebinds
# the shared last-writer-wins singleton (~/.claude/.skill-session-token), and a
# post-run read would bind the verdict to the SIBLING's token — the writer would
# then measure PASS but the push gate, reading the own-token file, would still
# deny.
#
# Precedence, highest first:
#   1. SKILL_SESSION_TOKEN — the explicit override contract (issue #122; e.g.
#      the invoking skill's hook-payload token, per #51 payload-first).
#   2. THIS conversation's own token, derived from CLAUDE_CODE_SESSION_ID and
#      trusted only when a transcript for it exists (issue #156, shared with
#      phase_attest via session-token.sh). Capturing the singleton alone was
#      not enough: it is last-writer-wins ACROSS sessions, so a concurrent
#      session stamping it before this run binds the verdict to a FOREIGN
#      token. The push gate then finds nothing under its own token and can only
#      be rescued by the cross-token bridge, which is EXACT-HEAD only — so the
#      own-token ancestor acceptance that routing-governance relies on is
#      silently lost, and one further commit turns a designed accept into a
#      deny (measured live during PR #154: the singleton rotated through three
#      foreign sessions in one conversation).
#   3. The singleton — unchanged pre-fix behaviour, and the degradation path
#      when the lib is unavailable or the session id is stale/unsafe/absent.
TOKEN="${SKILL_SESSION_TOKEN:-}"
if [ -z "$TOKEN" ] && [ -f "${PLUGIN_ROOT}/hooks/lib/session-token.sh" ]; then
    # shellcheck source=../hooks/lib/session-token.sh
    . "${PLUGIN_ROOT}/hooks/lib/session-token.sh" 2>/dev/null || true
    command -v resolve_own_session_token >/dev/null 2>&1 && TOKEN="$(resolve_own_session_token)"
fi
[ -n "$TOKEN" ] || TOKEN="$(cat "${HOME}/.claude/.skill-session-token" 2>/dev/null || echo default)"

# Capture the commit under test BEFORE the gate loop (issue #181) — same window
# and same hazard as the token above. This repo's suite runs 10+ minutes and
# running it in the background while continuing to work is the normal pattern,
# so a post-run read silently adopts any commit made meanwhile: the verdict then
# names a tree no gate ever executed against, and verdict.sh's HEAD-or-ancestor
# acceptance treats that commit as covered. Observed live while shipping #180.
# sha was the ONE field in this record measured at a different time from
# everything it describes.
SHA_BEFORE="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"

# worktree_dirty — ADVISORY ONLY, never deny-wired. A clean sha on a dirty tree
# has the same "tested something else" problem and the record should say so, but
# verifying uncommitted work and committing afterwards is a supported workflow;
# promoting it to could_not_verify[] would false-block routine pushes. Tracked
# modifications only: gate commands routinely leave untracked build/test
# artifacts, which would make this near-constantly true and the signal worthless.
# The BOOLEAN is not enough for the reader (#274). "Measured on a dirty tree"
# is only actionable if the advisory can name WHICH paths were uncommitted at
# measurement time — otherwise the reader is told to distrust a verdict with no
# way to judge whether the difference mattered. Captured at gate START, the same
# instant as the sha, so the record describes one moment and not three.
# Bounded: a large dirty tree would otherwise put an unbounded list into a state
# file the guard reads on every push. The count is recorded separately so a
# truncated list never reads as the whole list.
# `-z`, not plain --porcelain. Without it git applies C-STYLE QUOTING to any
# path that is not plain ASCII: measured, a dirty tree of seven files recorded
# "back\\slash.txt", "quote\"name.txt" and "unicode-\303\274.txt" — the last
# one octal-escaped past recognition. The advisory exists so a reader can judge
# whether the uncommitted paths matter to what they are pushing, and a name
# they cannot match against the one they know does not serve that.
#
# `-z` also renders a rename as two records (new path, then old) instead of one
# "old -> new" line, so the count is entries and not a path pair masquerading
# as one path. The awk skips the second record of an R/C entry.
#
# Ceiling, stated rather than hidden: `tr` splits on NUL, so a path containing
# a literal newline is reported as two entries. That OVER-reports, which for an
# advisory is the safe direction, and no other representation survives bash 3.2
# without a NUL-capable read.
_WD_PATHS="$(git -C "$ROOT" status --porcelain -z --untracked-files=no 2>/dev/null \
    | tr '\0' '\n' \
    | awk '
        skip { skip = 0; next }
        {
            st = substr($0, 1, 2)
            if (st ~ /[RC]/) skip = 1
            print substr($0, 4)
        }')"
if [ -n "${_WD_PATHS}" ]; then
    WORKTREE_DIRTY=true
else
    WORKTREE_DIRTY=false
fi
WORKTREE_DIRTY_COUNT="$(printf '%s' "${_WD_PATHS}" | grep -c . || :)"
_WD_PATHS_CAPPED="$(printf '%s\n' "${_WD_PATHS}" | head -20)"

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

# A commit landing while the gate ran means the run covers NO single commit, so
# neither sha is honest — record it as unverifiable rather than picking one
# (issue #181). Same fail-toward-not-clean posture as an unrunnable gate-gaming
# check: verdict_is_clean requires could_not_verify[] empty, so a straddled run
# stops satisfying routing-governance instead of silently claiming a result for
# an untested tree. The recorded sha stays the PRE-gate one — the commit whose
# tree the gate actually began measuring.
#
# HEAD-sha-only by design: a status-based straddle predicate would fire on every
# gate that writes a build artifact, converting a rare true signal into noise.
SHA="$SHA_BEFORE"
SHA_AFTER="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)"
if [ "$SHA_BEFORE" != "$SHA_AFTER" ]; then
    CNV="${CNV}${CNV:+,}gate-run-straddled-commit"
    echo "gate run STRADDLED a commit: ${SHA_BEFORE} -> ${SHA_AFTER} — the run covers no single commit (recorded as could-not-verify; re-run against the settled HEAD)"
fi
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
EXCERPT="$(tail -c 600 "$LOG" 2>/dev/null | tr -d '\000-\010\013-\037' | tr '\n' ' ')"
OUT="${HOME}/.claude/.skill-project-verified-${TOKEN}"

# test_delta (advisory): does a material source change carry a test change?
# docs = docs/**, openspec/**, *.md; test files = TOP-LEVEL tests/<name>.sh only
# (a case glob like tests/*.sh crosses '/', so nested fixtures such as
# tests/fixtures/routing/mock.sh would wrongly count as "the test" — the
# tests/*/* arm below is checked FIRST and swallows anything nested).
#
# Diff range: the branch's mainline base, NOT HEAD~1 alone (a single-commit
# window undercounts a multi-commit feature branch). Reuse the mainline
# merge-base ($BASE) the gate-gaming check already computed above when
# available; otherwise re-derive it directly; otherwise HEAD~1; otherwise
# the root commit's own file list.
_TD_BASE="$BASE"
[ -n "$_TD_BASE" ] || _TD_BASE="$(git -C "$ROOT" merge-base origin/main HEAD 2>/dev/null)"
[ -n "$_TD_BASE" ] || _TD_BASE="$(git -C "$ROOT" merge-base main HEAD 2>/dev/null)"
[ -n "$_TD_BASE" ] || _TD_BASE="$(git -C "$ROOT" rev-parse HEAD~1 2>/dev/null)"
if [ -n "$_TD_BASE" ]; then
    _TD_FILES="$(git -C "$ROOT" diff --name-only "$_TD_BASE"..HEAD 2>/dev/null)"
else
    _TD_FILES="$(git -C "$ROOT" show --name-only --format= HEAD 2>/dev/null)"
fi
_TD_SRC=0; _TD_TEST=0
while IFS= read -r _f; do
    [ -n "$_f" ] || continue
    case "$_f" in
        docs/*|openspec/*|*.md) continue ;;              # docs: ignored
        tests/*/*) continue ;;                            # nested test scaffolding: ignored (neither material nor test)
        tests/*.sh) _TD_TEST=1; continue ;;                # top-level test file: TEST change
        tests/*) continue ;;                               # other tests/ direct children: ignored, never material
        *) _TD_SRC=1 ;;                                    # everything else non-docs: MATERIAL SOURCE
    esac
done <<EOF
$_TD_FILES
EOF
if [ "$_TD_SRC" -eq 0 ]; then TEST_DELTA="n/a"
elif [ "$_TD_TEST" -eq 1 ]; then TEST_DELTA="covered"
else TEST_DELTA="missing"; fi

jq -n --arg sha "$SHA" --arg ts "$TS" --arg ex "$EXCERPT" --arg cmd "$CMDS" --arg disc "$DISCOVERY" \
      --arg p "$PASSED" --arg f "$FAILED" --arg c "$CNV" --arg gg "$GG_STATUS" --arg td "$TEST_DELTA" \
      --arg wd "$WORKTREE_DIRTY" --arg wdp "$_WD_PATHS_CAPPED" --arg wdn "$WORKTREE_DIRTY_COUNT" '
  def csv($s): if $s == "" then [] else ($s | split(",")) end;
  def lines($s): [$s | split("\n")[] | select(. != "")];
  {substrate:"local", discovery_source:$disc,
   passed:csv($p), failed:csv($f), could_not_verify:csv($c),
   gate_gaming_status:$gg, coverage_adequacy_status:"unverified",
   test_delta:$td, worktree_dirty:($wd == "true"),
   dirty_paths:lines($wdp), dirty_path_count:($wdn | tonumber? // 0),
   sha:$sha, command:$cmd, output_excerpt:$ex, ts:$ts,
   writer:"verify-and-record.sh"}
' > "${OUT}.tmp.$$" || { rm -f "${OUT}.tmp.$$"; echo "verify-and-record: verdict write failed" >&2; exit 1; }
mv "${OUT}.tmp.$$" "$OUT" || { rm -f "${OUT}.tmp.$$"; echo "verify-and-record: verdict write failed" >&2; exit 1; }

echo "verdict written: $OUT"
jq -c '{passed,failed,could_not_verify,gate_gaming_status,test_delta,worktree_dirty,sha}' "$OUT"
