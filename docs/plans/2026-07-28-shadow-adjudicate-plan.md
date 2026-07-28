# C2 Shadow-Corpus Adjudication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `scripts/shadow-adjudicate.sh` so IMPLEMENT-leg shadow records can be labeled and the deny-flip's pre-registered rate becomes computable.

**Architecture:** One bash-3.2 script reading the C1 shadow log read-only and appending adjudications to a separate sidecar log. Records collapse into episodes; episodes resolve worst-verdict-wins; the rate prints only above a floor of 29 episodes across ≥2 repos, banded by exact Clopper–Pearson.

**Tech Stack:** bash 3.2, `jq`, `awk`. No Python, no interactive input, no new dependencies.

## Global Constraints

- **Bash 3.2 compatible** (macOS `/bin/bash`). No associative arrays. No quoted operands in `$(( ))`.
- **Never `set -e`.** `set -u` only.
- **Never reads stdin.** The suite runs under `< /dev/null`.
- **Diagnostic-only.** Never sourced by `hooks/openspec-guard.sh`; MUST NOT be added to `_GATE_ENFORCE_LIBS`; writes no gate state; emits no `permissionDecision`.
- **Never mutates** `~/.claude/.push-implement-shadow.jsonl`.
- Paths overridable: `IMPLEMENT_SHADOW_LOG`, `IMPLEMENT_ADJUDICATION_LOG`.
- Constants, verbatim: `REQUIRED_PREDICATE_VERSION=2`, `FLOOR_EPISODES=29`, `FLOOR_REPOS=2`, `EPISODE_WINDOW_SEC=1800`, `ALPHA=0.05`, `DENY_P=0.10`, `ADVISORY_P=0.20`.
- Verdicts, exactly: `true_catch`, `false_block`, `unknown`.
- Output says **human-claimed**, never "human-verified".
- Commit messages: `<type>: <description>`.

---

### Task 1: Exact Clopper–Pearson band arithmetic

Highest-risk logic, so it goes first and standalone. A normal approximation disagrees with the exact rule at real boundaries — that disagreement is the pinned test.

**Files:**
- Create: `scripts/shadow-adjudicate.sh`
- Test: `tests/test-shadow-adjudicate.sh`

**Interfaces:**
- Produces: `_band <k> <n>` → prints exactly one of `DENY`, `ADVISORY-ONLY`, `NARROWED`, `INSUFFICIENT`. `INSUFFICIENT` when `n < 1`.

- [ ] **Step 1: Write the failing test**

Create `tests/test-shadow-adjudicate.sh`:

```bash
#!/bin/bash
# test-shadow-adjudicate.sh — C2 adjudication tool.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/shadow-adjudicate.sh"
PASS=0; FAIL=0
ok()   { PASS=$(( PASS + 1 )); echo "  PASS: $1"; }
bad()  { FAIL=$(( FAIL + 1 )); echo "  FAIL: $1"; echo "        expected: $2"; echo "        actual:   $3"; }
eq()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

echo "=== test-shadow-adjudicate.sh ==="

# --- Task 1: band arithmetic (exact Clopper-Pearson) ---
band() { ( . "$SCRIPT" --source-only; _band "$1" "$2" ); }

eq "0/29 clears the DENY floor"        "DENY"          "$(band 0 29)"
eq "0/28 does NOT clear it"            "NARROWED"      "$(band 0 28)"
eq "9/23 is ADVISORY-ONLY"             "ADVISORY-ONLY" "$(band 9 23)"
eq "8/23 is NARROWED, not advisory"    "NARROWED"      "$(band 8 23)"
eq "5/23 is NARROWED"                  "NARROWED"      "$(band 5 23)"
eq "empty corpus is INSUFFICIENT"      "INSUFFICIENT"  "$(band 0 0)"

echo
echo "Tests run: $(( PASS + FAIL ))  passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ] || exit 1
```

The `8/23 is NARROWED` case is load-bearing: Wilson calls it `ADVISORY-ONLY`. If someone swaps in a normal approximation, that line fails.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: FAIL — `scripts/shadow-adjudicate.sh` does not exist.

- [ ] **Step 3: Write the minimal implementation**

Create `scripts/shadow-adjudicate.sh`:

```bash
#!/bin/bash
# shadow-adjudicate.sh — label IMPLEMENT-leg shadow records (C1 corpus) and
# report the pre-registered false-block rate over independent episodes.
#
# DIAGNOSTIC ONLY. Never sourced by hooks/openspec-guard.sh, deliberately
# EXCLUDED from _GATE_ENFORCE_LIBS, writes no gate state, and its output MUST
# NOT be wired into an enforcement decision. The guard is the only decider.
#
# Pre-registration (openspec/changes/implement-shadow-event/design.md) is an
# INPUT here, not something this script may redefine.
#
# Bash 3.2. Never `set -e`. Never reads stdin.
set -u

REQUIRED_PREDICATE_VERSION=2
FLOOR_EPISODES=29
FLOOR_REPOS=2
EPISODE_WINDOW_SEC=1800
ALPHA=0.05
DENY_P=0.10
ADVISORY_P=0.20

SHADOW_LOG="${IMPLEMENT_SHADOW_LOG:-$HOME/.claude/.push-implement-shadow.jsonl}"
ADJ_LOG="${IMPLEMENT_ADJUDICATION_LOG:-$HOME/.claude/.push-implement-adjudication.jsonl}"

# _band <k> <n> -> DENY | ADVISORY-ONLY | NARROWED | INSUFFICIENT
#
# Exact Clopper-Pearson, stated as a direct CDF comparison so no interval
# inversion is needed (the binomial CDF is monotone in p):
#   DENY          <=> P(X <= k | n, 0.10) <  alpha
#   ADVISORY-ONLY <=> P(X >= k | n, 0.20) <= alpha
# Do NOT substitute a normal approximation: Wilson is anti-conservative in the
# tail and calls 8/23 ADVISORY-ONLY where exact says NARROWED.
_band() {
    awk -v k="${1:-0}" -v n="${2:-0}" -v a="${ALPHA}" \
        -v dp="${DENY_P}" -v ap="${ADVISORY_P}" '
    function tail(kk, nn, p, mode,   i, t, s) {
        # mode "le": sum_{i<=kk}   mode "ge": sum_{i>=kk}
        s = 0; t = (1 - p) ^ nn
        for (i = 0; i <= nn; i++) {
            if (mode == "le" && i <= kk) s += t
            if (mode == "ge" && i >= kk) s += t
            if (i < nn) t = t * (nn - i) / (i + 1) * p / (1 - p)
        }
        return s
    }
    BEGIN {
        if (n < 1) { print "INSUFFICIENT"; exit }
        if (tail(k, n, dp, "le") <  a) { print "DENY";          exit }
        if (tail(k, n, ap, "ge") <= a) { print "ADVISORY-ONLY"; exit }
        print "NARROWED"
    }'
}

# Allow tests to source the helpers without executing a command.
[ "${1:-}" = "--source-only" ] && return 0 2>/dev/null
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS, 6/6.

- [ ] **Step 5: Verify bash 3.2 compatibility**

Run: `/bin/bash -n scripts/shadow-adjudicate.sh && /bin/bash tests/test-shadow-adjudicate.sh`
Expected: no syntax errors; tests pass under real bash 3.2.

- [ ] **Step 6: Commit**

```bash
git add scripts/shadow-adjudicate.sh tests/test-shadow-adjudicate.sh
git commit -m "feat: exact Clopper-Pearson band arithmetic for the shadow corpus"
```

---

### Task 2: Episode grouping

**Files:**
- Modify: `scripts/shadow-adjudicate.sh`
- Test: `tests/test-shadow-adjudicate.sh`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `_episodes` — reads `$SHADOW_LOG`, prints one line per episode: `<episode_id>\t<repo>\t<branch>\t<session_token>\t<record_ids_csv>`. `episode_id` is the first record's id.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-shadow-adjudicate.sh` before the summary block:

```bash
# --- Task 2: episode grouping ---
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export IMPLEMENT_SHADOW_LOG="$TMP/shadow.jsonl"
export IMPLEMENT_ADJUDICATION_LOG="$TMP/adj.jsonl"

rec() { # rec <id> <ts> <repo> <branch> <token> [pv]
  printf '{"record_id":"%s","ts":"%s","repo":"%s","branch":"%s","session_token":"%s","predicate_version":%s,"action":"push","diff_base":"branch-local","impl_in_chain":true,"material_source":true,"impl_evidence_kind":"none","transcript_path":"/tmp/t.jsonl","gate":"push-implement","would_block":true,"schema_version":1}\n' \
    "$1" "$2" "$3" "$4" "$5" "${6:-2}" >> "$IMPLEMENT_SHADOW_LOG"
}
episodes() { ( . "$SCRIPT" --source-only; _episodes ); }

# the real v1 burst shape: 11 records, one repo+branch+token, 9-minute window
: > "$IMPLEMENT_SHADOW_LOG"
i=0
while [ "$i" -lt 11 ]; do
  rec "r$i" "2026-07-28T07:4$(( i % 10 )):08Z" "/repo/A" "feat/x" "tok1"
  i=$(( i + 1 ))
done
eq "an 11-record retry burst is ONE episode" "1" "$(episodes | wc -l | tr -d ' ')"

# anchored window: 0min, 25min, 35min -> 2 episodes (35 is outside 30 of the FIRST)
: > "$IMPLEMENT_SHADOW_LOG"
rec a "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec b "2026-07-28T10:25:00Z" "/repo/A" "feat/x" "tok1"
rec c "2026-07-28T10:35:00Z" "/repo/A" "feat/x" "tok1"
eq "window is anchored at first record, not rolling" "2" "$(episodes | wc -l | tr -d ' ')"

# different session tokens never merge
: > "$IMPLEMENT_SHADOW_LOG"
rec d "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec e "2026-07-28T10:01:00Z" "/repo/A" "feat/x" "tok2"
eq "distinct session tokens are distinct episodes" "2" "$(episodes | wc -l | tr -d ' ')"

# v1 records are excluded entirely
: > "$IMPLEMENT_SHADOW_LOG"
rec f "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1" 1
eq "v1 records are not episodes" "0" "$(episodes | wc -l | tr -d ' ')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: FAIL — `_episodes: command not found`.

- [ ] **Step 3: Write the implementation**

Insert into `scripts/shadow-adjudicate.sh` above the `--source-only` line:

```bash
# _iso_epoch — ISO-8601 UTC ("2026-07-28T07:45:08Z") -> epoch seconds.
# Implemented in awk rather than via `date`, because `date -d` (GNU) and
# `date -j -f` (BSD/macOS) are mutually incompatible and this must run on both.
_iso_epoch() {
    awk -v s="${1:-}" '
    function days_from_civil(y, m, d,   era, yoe, doy, doe) {
        if (m <= 2) y = y - 1
        era = int((y >= 0 ? y : y - 399) / 400)
        yoe = y - era * 400
        doy = int((153 * (m + (m > 2 ? -3 : 9)) + 2) / 5) + d - 1
        doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
        return era * 146097 + doe - 719468
    }
    BEGIN {
        if (s !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$/) { print -1; exit }
        y = substr(s,1,4)+0;  mo = substr(s,6,2)+0; d  = substr(s,9,2)+0
        hh = substr(s,12,2)+0; mi = substr(s,15,2)+0; ss = substr(s,18,2)+0
        print days_from_civil(y, mo, d) * 86400 + hh * 3600 + mi * 60 + ss
    }'
}

# _episodes — group v2 shadow records into independent episodes.
# One line per episode: <episode_id> <repo> <branch> <token> <record_ids_csv>
# (tab-separated). Membership: same (repo, branch, session_token) AND ts within
# EPISODE_WINDOW_SEC of the episode's FIRST record — anchored, not rolling.
_episodes() {
    [ -f "${SHADOW_LOG}" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
        select(.predicate_version == $pv)
        | [.repo, .branch, .session_token, .ts, .record_id] | @tsv
      ' "${SHADOW_LOG}" 2>/dev/null \
    | while IFS="$(printf '\t')" read -r _repo _branch _tok _ts _rid; do
          [ -z "${_rid:-}" ] && continue
          printf '%s\t%s\t%s\t%s\t%s\n' "$_repo" "$_branch" "$_tok" "$(_iso_epoch "$_ts")" "$_rid"
      done \
    | sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3 -k4,4n \
    | awk -F'\t' -v w="${EPISODE_WINDOW_SEC}" '
        {
          key = $1 "\x01" $2 "\x01" $3
          if (key != prev_key || ($4 - anchor) > w) {
            if (NR > 1) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids
            eid = $5; erepo = $1; ebranch = $2; etok = $3; ids = $5
            anchor = $4; prev_key = key
          } else {
            ids = ids "," $5
          }
        }
        END { if (NR > 0) print eid "\t" erepo "\t" ebranch "\t" etok "\t" ids }'
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS, 10/10.

- [ ] **Step 5: Commit**

```bash
git add scripts/shadow-adjudicate.sh tests/test-shadow-adjudicate.sh
git commit -m "feat: group shadow records into anchored-window episodes"
```

---

### Task 3: Adjudication write, claimant detection, provenance

**Files:**
- Modify: `scripts/shadow-adjudicate.sh`
- Test: `tests/test-shadow-adjudicate.sh`

**Interfaces:**
- Consumes: `$SHADOW_LOG`, `$ADJ_LOG`.
- Produces: `_claimant` → `human`|`agent`; `cmd_adjudicate <record_id> <verdict> <reason>` → exit 0 on success, 1 on refusal.

- [ ] **Step 1: Write the failing test**

Append before the summary block:

```bash
# --- Task 3: adjudication write ---
adj() { ( unset CLAUDECODE; "$SCRIPT" "$1" --verdict "$2" --reason "$3" >/dev/null 2>&1; echo $?; ); }

: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec g "2026-07-28T10:00:00Z" "/repo/A" "feat/x" "tok1"
rec h "2026-07-28T10:00:00Z" "/repo/B" "feat/y" "tok2" 1
BEFORE="$(cksum < "$IMPLEMENT_SHADOW_LOG")"

eq "adjudicating a v2 record succeeds" "0" "$(adj g true_catch 'resolved by attest')"
eq "one adjudication was appended"     "1" "$(wc -l < "$IMPLEMENT_ADJUDICATION_LOG" | tr -d ' ')"
eq "shadow log is untouched"           "$BEFORE" "$(cksum < "$IMPLEMENT_SHADOW_LOG")"
eq "verdict was recorded"              "true_catch" "$(jq -r '.verdict' "$IMPLEMENT_ADJUDICATION_LOG")"
eq "a v1 record is refused"            "1" "$(adj h true_catch 'nope')"
eq "refusal wrote nothing"             "1" "$(wc -l < "$IMPLEMENT_ADJUDICATION_LOG" | tr -d ' ')"
eq "an unknown record id is refused"   "1" "$(adj nosuch true_catch 'nope')"
eq "an invalid verdict is refused"     "1" "$(adj g bogus_verdict 'nope')"

: > "$IMPLEMENT_ADJUDICATION_LOG"
CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason "agent run" >/dev/null 2>&1
eq "CLAUDECODE marks the claimant agent" "agent" "$(jq -r '.claimant' "$IMPLEMENT_ADJUDICATION_LOG")"
eq "output never claims human-VERIFIED"  "0" \
   "$(CLAUDECODE=1 "$SCRIPT" g --verdict unknown --reason x 2>&1 | grep -ci 'human-verified')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: FAIL — no argument dispatch exists yet.

- [ ] **Step 3: Write the implementation**

Insert above the `--source-only` line:

```bash
# _claimant — who is running this. Deliberately biased toward "agent": a human
# using `!` inside a session is misclassified and pays one re-confirmation,
# whereas an agent's self-label counted silently would corrupt the rate.
# All three signals are forgeable; the output says human-CLAIMED, never verified.
_claimant() {
    if [ -n "${CLAUDECODE:-}" ]; then echo agent; return; fi
    if [ ! -t 1 ]; then echo agent; return; fi
    case "$(ps -o comm= -p "$PPID" 2>/dev/null)" in *claude*) echo agent; return;; esac
    echo human
}

_record_field() { # _record_field <record_id> <field>
    jq -r --arg id "${1:-}" --arg f "${2:-}" \
       'select(.record_id == $id) | .[$f] // empty' "${SHADOW_LOG}" 2>/dev/null | head -1
}

cmd_adjudicate() {
    local _rid="${1:-}" _verdict="${2:-}" _reason="${3:-}" _pv _ts _claim
    case "${_verdict}" in
        true_catch|false_block|unknown) ;;
        *) echo "error: --verdict must be true_catch, false_block, or unknown" >&2; return 1;;
    esac
    [ -f "${SHADOW_LOG}" ] || { echo "error: no shadow log at ${SHADOW_LOG}" >&2; return 1; }
    command -v jq >/dev/null 2>&1 || { echo "error: jq required" >&2; return 1; }
    _pv="$(_record_field "${_rid}" predicate_version)"
    [ -z "${_pv}" ] && { echo "error: no record '${_rid}' in ${SHADOW_LOG}" >&2; return 1; }
    if [ "${_pv}" != "${REQUIRED_PREDICATE_VERSION}" ]; then
        echo "error: record '${_rid}' is predicate_version ${_pv}; only v${REQUIRED_PREDICATE_VERSION} is adjudicable." >&2
        echo "       v1 measured a different subject for merges and MUST NOT be pooled with v2." >&2
        return 1
    fi
    [ -f "${ADJ_LOG}" ] || { : > "${ADJ_LOG}" 2>/dev/null || { echo "error: cannot write ${ADJ_LOG}" >&2; return 1; }; }
    chmod 600 "${ADJ_LOG}" 2>/dev/null
    _ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)"
    _claim="$(_claimant)"
    jq -cn --arg rid "${_rid}" --arg ts "${_ts}" --arg v "${_verdict}" \
           --arg r "${_reason}" --arg c "${_claim}" \
           --arg u "${USER:-unknown}" --arg tty "$(tty 2>/dev/null || echo not-a-tty)" \
           --arg par "$(ps -o comm= -p "$PPID" 2>/dev/null || echo unknown)" \
           --arg head "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
           --arg agentenv "$([ -n "${CLAUDECODE:-}" ] && echo present || echo absent)" \
       '{schema_version:1,record_id:$rid,ts:$ts,verdict:$v,reason:$r,claimant:$c,
         provenance:{user:$u,tty:$tty,parent:$par,repo_head:$head,agent_env:$agentenv}}' \
       >> "${ADJ_LOG}" 2>/dev/null || { echo "error: append failed" >&2; return 1; }
    echo "recorded: ${_rid}  ${_verdict}  (${_claim}-claimed)"
    [ "${_claim}" = "agent" ] && echo "note: agent-claimed — excluded from the rate until a human re-confirms."
    echo "label: HUMAN-CLAIMED, not human-verified."
    return 0
}
```

And replace the `--source-only` line with dispatch:

```bash
case "${1:-}" in
    --source-only) return 0 2>/dev/null ;;
    --next)        cmd_next; exit $? ;;
    --status)      cmd_status; exit $? ;;
    -h|--help)     _usage; exit 0 ;;
    "")            _usage; exit 1 ;;
    *)
        _RID="$1"; shift
        _V=""; _R=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --verdict) _V="${2:-}"; shift 2 ;;
                --reason)  _R="${2:-}"; shift 2 ;;
                *) echo "error: unexpected argument '$1'" >&2; exit 1 ;;
            esac
        done
        cmd_adjudicate "${_RID}" "${_V}" "${_R}"; exit $?
        ;;
esac
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS, 20/20.

- [ ] **Step 5: Commit**

```bash
git add scripts/shadow-adjudicate.sh tests/test-shadow-adjudicate.sh
git commit -m "feat: record adjudications with claimant detection and provenance"
```

---

### Task 4: `--next`

**Files:**
- Modify: `scripts/shadow-adjudicate.sh`
- Test: `tests/test-shadow-adjudicate.sh`

**Interfaces:**
- Consumes: `_episodes` is NOT used here — `--next` works at record granularity.
- Produces: `cmd_next` → exit 0 always; `_adjudicated_ids` → newline-separated record ids present in `$ADJ_LOG`.

- [ ] **Step 1: Write the failing test**

```bash
# --- Task 4: --next ---
: > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"
rec old "2026-07-28T09:00:00Z" "/repo/A" "feat/x" "tok1"
rec new "2026-07-28T11:00:00Z" "/repo/B" "feat/y" "tok2"
CLAUDECODE=1 "$SCRIPT" new --verdict true_catch --reason seen >/dev/null 2>&1
ADJ_BEFORE="$(cksum < "$IMPLEMENT_ADJUDICATION_LOG")"

eq "next surfaces the oldest unadjudicated" "1" "$("$SCRIPT" --next 2>&1 | grep -c '\bold\b')"
eq "next includes the transcript pointer"   "1" "$("$SCRIPT" --next 2>&1 | grep -c '/tmp/t.jsonl')"
eq "next shows why the leg fired"           "1" "$("$SCRIPT" --next 2>&1 | grep -ci 'material_source')"
eq "next does not modify the sidecar"       "$ADJ_BEFORE" "$(cksum < "$IMPLEMENT_ADJUDICATION_LOG")"
eq "next exits 0"                           "0" "$("$SCRIPT" --next >/dev/null 2>&1; echo $?)"

CLAUDECODE=1 "$SCRIPT" old --verdict unknown --reason seen >/dev/null 2>&1
eq "fully adjudicated corpus reports done"  "1" "$("$SCRIPT" --next 2>&1 | grep -ci 'nothing outstanding')"
eq "and still exits 0"                      "0" "$("$SCRIPT" --next >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: FAIL — `cmd_next: command not found`.

- [ ] **Step 3: Write the implementation**

```bash
_adjudicated_ids() {
    [ -f "${ADJ_LOG}" ] || return 0
    jq -r '.record_id // empty' "${ADJ_LOG}" 2>/dev/null | sort -u
}

cmd_next() {
    local _seen _rid _line
    [ -f "${SHADOW_LOG}" ] || { echo "no shadow log at ${SHADOW_LOG} — nothing outstanding."; return 0; }
    command -v jq >/dev/null 2>&1 || { echo "jq required"; return 0; }
    _seen="$(_adjudicated_ids)"
    _line="$(jq -r --argjson pv "${REQUIRED_PREDICATE_VERSION}" '
              select(.predicate_version == $pv)
              | [.record_id,.ts,.repo,.branch,.action,.diff_base,
                 (.impl_in_chain|tostring),(.material_source|tostring),
                 .impl_evidence_kind,.transcript_path] | @tsv' \
              "${SHADOW_LOG}" 2>/dev/null \
            | sort -t "$(printf '\t')" -k2,2 \
            | while IFS="$(printf '\t')" read -r id rest; do
                  case "
${_seen}
" in *"
${id}
"*) continue;; esac
                  printf '%s\t%s\n' "$id" "$rest"; break
              done)"
    if [ -z "${_line}" ]; then
        echo "nothing outstanding — every v${REQUIRED_PREDICATE_VERSION} record is adjudicated."
        return 0
    fi
    echo "${_line}" | while IFS="$(printf '\t')" read -r id ts repo branch action db chain mat ev tp; do
        printf '%s   %s\n' "$id" "$ts"
        printf '  repo    %s\n  branch  %s\n' "$repo" "$branch"
        printf '  action  %s   diff_base %s\n' "$action" "$db"
        printf '  why     impl_in_chain=%s, material_source=%s, evidence=%s\n' "$chain" "$mat" "$ev"
        printf '  read    %s\n\n' "$tp"
        printf 'to label:\n  %s %s --verdict <true_catch|false_block|unknown> --reason "..."\n' \
               "$0" "$id"
    done
    return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS, 27/27.

- [ ] **Step 5: Commit**

```bash
git add scripts/shadow-adjudicate.sh tests/test-shadow-adjudicate.sh
git commit -m "feat: --next surfaces the oldest unadjudicated shadow record"
```

---

### Task 5: `--status`

**Files:**
- Modify: `scripts/shadow-adjudicate.sh`
- Test: `tests/test-shadow-adjudicate.sh`

**Interfaces:**
- Consumes: `_band` (Task 1), `_episodes` (Task 2), `_adjudicated_ids` (Task 4).
- Produces: `cmd_status` → exit 0 always.

Episode verdict resolution is **worst-verdict-wins**: any `false_block` → `false_block`; else any `unknown` → `unknown`; else `true_catch`. An episode counts as agent-claimed only when it has NO human-claimed adjudication.

- [ ] **Step 1: Write the failing test**

```bash
# --- Task 5: --status ---
seed() { : > "$IMPLEMENT_SHADOW_LOG"; : > "$IMPLEMENT_ADJUDICATION_LOG"; }
mkrec() { rec "$1" "2026-07-28T$2:00Z" "$3" "br-$1" "tok-$1"; }
label() { ( unset CLAUDECODE; "$SCRIPT" "$1" --verdict "$2" --reason t >/dev/null 2>&1 ); }

# floor: 3 clean episodes in 1 repo must NOT print a rate
seed
mkrec e1 "10:01" /repo/A; mkrec e2 "10:02" /repo/A; mkrec e3 "10:03" /repo/A
label e1 true_catch; label e2 true_catch; label e3 true_catch
eq "below the floor prints insufficient data" "1" "$("$SCRIPT" --status 2>&1 | grep -ci 'insufficient data')"
eq "and prints no percentage rate"            "0" "$("$SCRIPT" --status 2>&1 | grep -c '0\.0%')"
eq "and names the 29-episode floor"           "1" "$("$SCRIPT" --status 2>&1 | grep -c '29')"

# worst-verdict-wins within one episode
seed
rec m1 "2026-07-28T10:00:00Z" /repo/A feat/x tok1
rec m2 "2026-07-28T10:05:00Z" /repo/A feat/x tok1
label m1 true_catch; label m2 false_block
eq "a mixed episode resolves false_block" "1" "$("$SCRIPT" --status 2>&1 | grep -ci 'false_block[^0-9]*1')"

# agent-claimed is segregated, then re-included by a human adjudication
seed
mkrec a1 "10:01" /repo/A
CLAUDECODE=1 "$SCRIPT" a1 --verdict true_catch --reason t >/dev/null 2>&1
eq "agent-claimed is excluded"  "1" "$("$SCRIPT" --status 2>&1 | grep -ci 'agent-claimed')"
label a1 true_catch
eq "human re-confirmation counts it" "1" "$("$SCRIPT" --status 2>&1 | grep -ci 'human-claimed')"

# repos are listed, not just counted
seed
mkrec p1 "10:01" /repo/A; mkrec p2 "10:02" /repo/B
label p1 true_catch; label p2 true_catch
eq "status lists contributing repos" "1" "$("$SCRIPT" --status 2>&1 | grep -c '/repo/B')"

# status never claims authority
eq "status disclaims enforcement" "1" "$("$SCRIPT" --status 2>&1 | grep -ci 'not.*enforcement\|informational')"
eq "status exits 0 on an empty corpus" "0" "$(seed; "$SCRIPT" --status >/dev/null 2>&1; echo $?)"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: FAIL — `cmd_status: command not found`.

- [ ] **Step 3: Write the implementation**

```bash
# _episode_verdict <record_ids_csv> -> false_block|unknown|true_catch|unlabeled
# plus, on a second line, human|agent (agent only when NO human adjudication).
_episode_verdict() {
    local _ids="${1:-}" _v="unlabeled" _claim="agent" _has_human=0 _id _rows
    [ -f "${ADJ_LOG}" ] || { echo "unlabeled"; echo "agent"; return; }
    _rows="$(jq -r '[.record_id,.verdict,.claimant] | @tsv' "${ADJ_LOG}" 2>/dev/null)"
    for _id in $(echo "${_ids}" | tr ',' ' '); do
        while IFS="$(printf '\t')" read -r rid rv rc; do
            [ "${rid}" = "${_id}" ] || continue
            [ "${rc}" = "human" ] && _has_human=1
            case "${rv}" in
                false_block) _v="false_block" ;;
                unknown)     [ "${_v}" = "false_block" ] || _v="unknown" ;;
                true_catch)  [ "${_v}" = "unlabeled" ] && _v="true_catch" ;;
            esac
        done <<EOF
${_rows}
EOF
    done
    [ "${_has_human}" -eq 1 ] && _claim="human"
    echo "${_v}"; echo "${_claim}"
}

cmd_status() {
    local _tot=0 _lab=0 _fb=0 _tc=0 _unk=0 _agent=0 _unlab=0
    local _repos="" _line _ids _vc _v _c _v1 _band_hdl _band_wc _rate _wc_k
    _v1="$( [ -f "${SHADOW_LOG}" ] && jq -r 'select(.predicate_version != 2) | .record_id' "${SHADOW_LOG}" 2>/dev/null | wc -l | tr -d ' ' || echo 0)"
    while IFS="$(printf '\t')" read -r _eid _repo _branch _tok _ids; do
        [ -z "${_eid:-}" ] && continue
        _tot=$(( _tot + 1 ))
        _vc="$(_episode_verdict "${_ids}")"
        _v="$(echo "${_vc}" | sed -n 1p)"; _c="$(echo "${_vc}" | sed -n 2p)"
        if [ "${_v}" = "unlabeled" ]; then _unlab=$(( _unlab + 1 )); continue; fi
        if [ "${_c}" = "agent" ]; then _agent=$(( _agent + 1 )); continue; fi
        _lab=$(( _lab + 1 ))
        case "${_repos}" in *"|${_repo}|"*) ;; *) _repos="${_repos}|${_repo}|";; esac
        case "${_v}" in
            false_block) _fb=$(( _fb + 1 ));;
            unknown)     _unk=$(( _unk + 1 ));;
            true_catch)  _tc=$(( _tc + 1 ));;
        esac
    done <<EOF
$(_episodes)
EOF
    local _nrepos; _nrepos="$(echo "${_repos}" | tr '|' '\n' | grep -c '[^[:space:]]' 2>/dev/null || echo 0)"
    echo "IMPLEMENT shadow corpus — predicate_version ${REQUIRED_PREDICATE_VERSION}"
    printf '  episodes          %s\n' "${_tot}"
    printf '  adjudicated       %s   (human-claimed)\n' "${_lab}"
    printf '  agent-claimed     %s   <- excluded until a human re-confirms\n' "${_agent}"
    printf '  unadjudicated     %s\n' "${_unlab}"
    printf '  v1 records        %s   <- unpoolable, excluded\n' "${_v1}"
    printf '  true_catch        %s\n  false_block       %s\n  unknown           %s   <- excluded from headline\n' \
           "${_tc}" "${_fb}" "${_unk}"
    printf '  repos             %s' "${_nrepos}"
    [ "${_nrepos}" -gt 0 ] && printf '  %s' "$(echo "${_repos}" | tr '|' ' ' | tr -s ' ')"
    printf '\n\n'
    local _den=$(( _tc + _fb ))
    if [ "${_lab}" -lt "${FLOOR_EPISODES}" ] || [ "${_nrepos}" -lt "${FLOOR_REPOS}" ]; then
        echo "  rate              insufficient data"
        printf '  need              %s adjudicated episodes (have %s) across >=%s repos (have %s)\n' \
               "${FLOOR_EPISODES}" "${_lab}" "${FLOOR_REPOS}" "${_nrepos}"
        echo "  horizon           ~2026-09-08 (pre-registered)"
    else
        _band_hdl="$(_band "${_fb}" "${_den}")"
        _wc_k=$(( _fb + _unk ))
        _band_wc="$(_band "${_wc_k}" $(( _den + _unk )) )"
        printf '  rate              %s/%s\n' "${_fb}" "${_den}"
        printf '  band              %s\n' "${_band_hdl}"
        printf '  worst case        %s/%s -> %s   (every unknown counted as a false block)\n' \
               "${_wc_k}" "$(( _den + _unk ))" "${_band_wc}"
    fi
    echo
    echo "  Informational only — this readout is NOT an enforcement decision."
    echo "  Verdicts are HUMAN-CLAIMED, not human-verified."
    return 0
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS, 36/36.

- [ ] **Step 5: Verify under real bash 3.2 and the full suite**

Run: `/bin/bash -n scripts/shadow-adjudicate.sh && /bin/bash tests/test-shadow-adjudicate.sh && bash tests/run-tests.sh < /dev/null`
Expected: all pass; the new file is auto-discovered by the runner's glob.

- [ ] **Step 6: Commit**

```bash
git add scripts/shadow-adjudicate.sh tests/test-shadow-adjudicate.sh
git commit -m "feat: --status reports episode rate, bands, and floor distance"
```

---

### Task 6: Documentation and gate-exclusion proof

**Files:**
- Modify: `CLAUDE.md` (Gotchas section)
- Modify: `tests/test-shadow-adjudicate.sh`

- [ ] **Step 1: Write the failing test**

```bash
# --- Task 6: the tool must never become a gate component ---
eq "not listed in _GATE_ENFORCE_LIBS" "0" \
   "$(grep -c 'shadow-adjudicate' "$ROOT/hooks/session-start-hook.sh" 2>/dev/null || echo 0)"
eq "not sourced by the guard"          "0" \
   "$(grep -c 'shadow-adjudicate' "$ROOT/hooks/openspec-guard.sh" 2>/dev/null || echo 0)"
eq "never emits a permissionDecision"  "0" \
   "$(grep -c 'permissionDecision' "$SCRIPT")"
eq "never uses set -e"                 "0" \
   "$(grep -cE '^[[:space:]]*set -e' "$SCRIPT")"
```

- [ ] **Step 2: Run it to verify it passes immediately**

Run: `bash tests/test-shadow-adjudicate.sh`
Expected: PASS — these are guard-rails pinning properties the implementation already has. If any fails, the implementation drifted and must be fixed, not the test.

- [ ] **Step 3: Add the CLAUDE.md gotcha**

Append one bullet to the Gotchas section:

```markdown
- `scripts/shadow-adjudicate.sh` (C2) labels IMPLEMENT shadow records and reports the pre-registered rate. **Diagnostic-only** — never sourced by the guard, deliberately EXCLUDED from `_GATE_ENFORCE_LIBS`, writes no gate state (pinned by `tests/test-shadow-adjudicate.sh`). Adjudications go to a SIDECAR (`~/.claude/.push-implement-adjudication.jsonl`); the C1 shadow log is never mutated. Three rules are easy to get wrong: (1) the denominator is independent **episodes**, not records — `(repo, branch, session_token)` within 30 min **anchored at the episode's first record**, not a rolling gap; (2) bands are **exact Clopper–Pearson**, computed as a direct CDF comparison (`DENY ⟺ P(X≤k|n,0.10)<0.05`, `ADVISORY-ONLY ⟺ P(X≥k|n,0.20)≤0.05`) — Wilson is anti-conservative and calls 8/23 advisory where exact says narrowed, which is a pinned test; (3) agent-claimed adjudications are EXCLUDED from the rate until a human re-confirms, since this leg governs agent pushes and the subject has an incentive to self-grade.
```

- [ ] **Step 4: Run the full suite**

Run: `bash tests/run-tests.sh < /dev/null`
Expected: all files pass.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md tests/test-shadow-adjudicate.sh
git commit -m "docs: record the C2 adjudication tool and its three easy-to-break rules"
```

---

## Self-Review

**Spec coverage.** Requirement 1 (adjudication) → Task 3. Requirement 2 (`--next`) → Task 4. Requirement 3 (episode rate and bands) → Tasks 1, 2, 5. All 8 spec scenarios map to a test: v2 write and shadow-untouched (T3), v1 refusal (T3), agent segregation (T3+T5), oldest-unadjudicated and its pointer (T4), nothing-outstanding (T4), retry burst → 1 episode (T2), floor suppression (T5), exact-vs-Wilson at 8/23 (T1), worst-verdict-wins (T5). No gaps.

**Placeholder scan.** No TBD/TODO. Every code step carries runnable code.

**Type consistency.** `_band`, `_episodes`, `_iso_epoch`, `_claimant`, `_adjudicated_ids`, `_record_field`, `_episode_verdict`, `cmd_next`, `cmd_adjudicate`, `cmd_status` are each defined once and referenced with matching arity. `_episodes` emits 5 tab-separated fields, consumed as 5 in `cmd_status`.

**Known risk carried into execution.** `_episode_verdict` re-reads `$ADJ_LOG` per episode, which is O(episodes × adjudications). At the floor (29 episodes) this is trivial; it is called out here so a future scale change is a deliberate decision rather than a surprise.
