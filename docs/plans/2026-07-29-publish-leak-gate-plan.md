# Publish Leak Gate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop private local-memory text reaching a public GitHub tracker, by denying `gh issue|pr create|comment|edit` whose body reproduces text from the local memory corpus, and by switching `improvement-miner` from verbatim quotes to `path:line` citations.

**Architecture:** One deterministic engine (`scripts/memory-leak-check.sh`) decides; one PreToolUse hook (`hooks/publish-guard.sh`) enforces. The engine flags any 16-consecutive-normalized-word run present in the memory corpus and absent from the repo's tracked content. The hook is separate from `openspec-guard.sh` so the push gate's fail-open ERR trap and lib-sourcing order stay untouched.

**Tech Stack:** Bash 3.2, awk, jq, `gh`, `git`. No new runtime dependencies.

**Spec:** `openspec/changes/publish-leak-gate/` (proposal.md, design.md, specs/pdlc-safety/spec.md, specs/improvement-mining/spec.md). Issue: #174.

## Global Constraints

- **Bash 3.2 compatible** (macOS `/bin/bash`). No associative arrays. No quoted operands in `$(( ))` — that aborts the script at that line under 3.2.
- Syntax-check every hook and script edit with `/bin/bash -n <file>` before commit.
- **The model's Bash tool is zsh 5.9, not bash.** Unquoted *scalar* expansion does not word-split there. Nothing in this change is model-sourced, but any ad-hoc verification command you write runs under zsh — use `printf '%s\n' … | while IFS= read -r` rather than `for x in $VAR`.
- Field separator `\x1f` (US) is the repo convention for multi-field records. This change needs none: `gh_publish_body_files` emits one path per line, and paths contain no newlines.
- Hooks fail open on error; **detection is fail-closed** (a match always denies), **inability to check is fail-open and announced**.
- The deny message MUST NOT reproduce matched text — locations only.
- Commit messages: `<type>: <description>`, ending with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.
- `tests/run-tests.sh` glob-discovers `tests/test-*.sh`. Run it as `bash tests/run-tests.sh` (never with stdin attached to a socket).
- Assertions must NOT live inside `( … )` subshells — they exit 0 and never gate the suite. After writing each test, break the implementation once and confirm the suite exits non-zero.
- **Before pushing:** this branch touches `skills/` and `hooks/`, so push-gate routing-governance requires a clean `project-verification` verdict covering HEAD. Run it before any push.

## File Structure

| File | Responsibility |
|---|---|
| `scripts/memory-leak-check.sh` (new) | Engine. Corpus resolution, normalization, shingling, public exemption, verdict. No hook or `gh` knowledge. |
| `hooks/lib/git-command.sh` (modify) | Adds `command_invokes_gh_publish` and `gh_publish_body_files`. Command parsing only — no leak logic. |
| `hooks/publish-guard.sh` (new) | Wires the two together: parse command → resolve bodies → run engine → deny. |
| `hooks/hooks.json` (modify) | Registers the hook on the `Bash` matcher. |
| `hooks/session-start-hook.sh` (modify) | Adds the hook to the F5 canary and drift manifest. |
| `skills/improvement-miner/SKILL.md` (modify) | Citation contract; report/publish split. |
| `tests/test-memory-leak-check.sh` (new) | Engine behaviour. |
| `tests/test-publish-guard.sh` (new) | Hook behaviour, including push-gate non-interference. |
| `tests/test-git-command.sh` (modify) | Publish-predicate cases. |
| `tests/test-improvement-miner.sh` (modify) | SKILL.md content assertions. |
| `tests/test-push-gate-canary.sh` (modify) | Canary covers the new hook. |

---

### Task 1: Detection engine

**Files:**
- Create: `scripts/memory-leak-check.sh`
- Test: `tests/test-memory-leak-check.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `scripts/memory-leak-check.sh <body-file>` → exit `0` clean · `1` leak · `2` usage · `3` cannot check. On leak, stdout carries one line per finding: `LEAK: body line <N> <- memory/<file>.md:<line>`. Env override `MEMORY_LEAK_CHECK_MEMORY_DIR` selects the corpus directory (tests only).

- [ ] **Step 1: Write the failing test**

Create `tests/test-memory-leak-check.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-memory-leak-check.sh ==="

ENGINE="${PROJECT_ROOT}/scripts/memory-leak-check.sh"

WORK="$(mktemp -d /tmp/mlc-XXXXXX)"
MEM="${WORK}/memory"
REPO="${WORK}/repo"
mkdir -p "${MEM}" "${REPO}"

# A 20-word private run: long enough to exceed the 16-word threshold.
PRIVATE_RUN="the branch ledger record is overwritten in place rather than appended so a historical push cannot be replayed from it afterwards"
printf 'name: t\n---\n\n%s\n' "${PRIVATE_RUN}" > "${MEM}/feedback_ledger_overwrite.md"

# A run that exists in BOTH the corpus and tracked repo content.
PUBLIC_RUN="the composition state advances only when a chain member skill tool returns successfully which is why a trigger match alone is never evidence"
printf 'name: p\n---\n\n%s\n' "${PUBLIC_RUN}" > "${MEM}/project_public_overlap.md"

# Build a real git repo so `git ls-files` works.
( cd "${REPO}" && git init -q . \
  && printf '%s\n' "${PUBLIC_RUN}" > public.md \
  && git add public.md \
  && git -c user.email=t@t -c user.name=t commit -q -m init )

# Sets OUT and RC in the CURRENT shell. Never call this inside $( ) — a
# command substitution would set OUT in a subshell and the assertion would
# read a stale value.
_run() {  # _run <body-file>
    OUT="$( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
            /bin/bash "${ENGINE}" "$1" 2>/dev/null )"
    RC=$?
}

# (a) Verbatim private run -> leak.
printf 'Some preamble.\n\n%s\n' "${PRIVATE_RUN}" > "${WORK}/leaky.md"
_run "${WORK}/leaky.md"
assert_equals "verbatim private run is flagged" "1" "${RC}"
assert_contains "names the source file" "feedback_ledger_overwrite.md" "${OUT:-<empty>}"

# (b) The deny output must NOT reproduce the matched text.
assert_not_contains "output does not echo matched text" "branch ledger record is overwritten" "${OUT:-}"

# (c) Same fact as a path:line citation -> clean.
printf 'Evidence: memory/feedback_ledger_overwrite.md:4 (feedback).\n' > "${WORK}/cited.md"
_run "${WORK}/cited.md"
assert_equals "path:line citation is clean" "0" "${RC}"

# (d) Public exemption: text in corpus AND tracked repo content -> clean.
printf '%s\n' "${PUBLIC_RUN}" > "${WORK}/public.md"
_run "${WORK}/public.md"
assert_equals "text already in tracked content is not a leak" "0" "${RC}"

# (e) File-boundary: tail of one memory file + head of the next must not match.
# NO frontmatter in these two fixtures on purpose: with a `name:` block, file
# B's own frontmatter words sit between the two runs, no adjacent cross-file
# sequence ever forms, and the case passes even against an engine with the
# per-file reset REMOVED. Verified by mutation.
printf 'alpha bravo charlie delta echo foxtrot golf hotel\n' > "${MEM}/aaa_first.md"
printf 'india juliett kilo lima mike november oscar papa\n'  > "${MEM}/bbb_second.md"
printf 'alpha bravo charlie delta echo foxtrot golf hotel india juliett kilo lima mike november oscar papa\n' \
    > "${WORK}/spanning.md"
_run "${WORK}/spanning.md"
assert_equals "run spanning two memory files is not a match" "0" "${RC}"
rm -f "${MEM}/aaa_first.md" "${MEM}/bbb_second.md"

# (f) Short generic prose -> clean.
printf 'This fixes a bug in the hook.\n' > "${WORK}/short.md"
_run "${WORK}/short.md"
assert_equals "short generic prose is clean" "0" "${RC}"

# (g) Absent corpus -> clean (nothing to leak), announced on stderr.
OUT2="$( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${WORK}/nope" \
         /bin/bash "${ENGINE}" "${WORK}/leaky.md" 2>&1 )"
rc2=$?
assert_equals "absent corpus allows" "0" "${rc2}"
assert_contains "absent corpus is announced" "no memory corpus" "${OUT2:-<empty>}"

# (h) Missing argument -> usage error.
/bin/bash "${ENGINE}" >/dev/null 2>&1
assert_equals "no argument is a usage error" "2" "$?"

# (i) Unreadable body -> cannot check.
/bin/bash "${ENGINE}" "${WORK}/does-not-exist.md" >/dev/null 2>&1
assert_equals "unreadable body cannot be checked" "3" "$?"

rm -rf "${WORK}"
print_summary
exit $?
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-memory-leak-check.sh`
Expected: FAIL — the engine does not exist, so every case reports a non-matching exit code.

- [ ] **Step 3: Write the engine**

Create `scripts/memory-leak-check.sh`:

```bash
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `/bin/bash -n scripts/memory-leak-check.sh && bash tests/test-memory-leak-check.sh`
Expected: PASS for all cases (a)–(i).

- [ ] **Step 5: Mutation-prove the tests**

Two mutations, both of which MUST make the suite exit non-zero. Restore after each.

1. Set `N_WORDS=200` — case (a) must fail.
2. Delete the `split("", w); split("", ln); c = 0` line from `flush()` — case (e) must fail.

Mutation 2 is the one that matters: with frontmatter in the case-(e) fixtures it passes against a broken engine, which is exactly how a vacuous test looks from the outside. Both mutations were verified to be caught by the test as written above.

- [ ] **Step 6: Commit**

```bash
git add scripts/memory-leak-check.sh tests/test-memory-leak-check.sh
git commit -m "feat: deterministic private-memory leak detector (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `gh` publish-command predicates

**Files:**
- Modify: `hooks/lib/git-command.sh` (append after `command_invokes_gh_merge`)
- Test: `tests/test-git-command.sh` (append)

**Interfaces:**
- Consumes: `_gc_split_segments`, `_GC_SEP` from the same file.
- Produces:
  - `command_invokes_gh_publish <command>` → exit 0 when the command invokes `gh issue create|comment|edit` or `gh pr create|comment|edit`.
  - `gh_publish_body_files <command>` → prints one `--body-file`/`-F` path per line, surrounding quotes stripped; nothing when there are none.

**Inline `--body` text is deliberately NOT parsed.** `_gc_split_segments` is quote-aware for *segmentation*, but the per-segment `set -- ${_seg}` word-splits, so `--body "two words"` arrives as `"two` / `words"`. Any reconstruction from that under-detects, and under-detection in a gate is a bypass (measured: a naive `--body` parser captured only `text"hello`). The hook instead scans the **whole command string**, which covers inline bodies conservatively and needs no arg parsing.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-git-command.sh` (before its `print_summary` call):

```bash
# --- gh publish predicates (#174) -------------------------------------------
_pub() { command_invokes_gh_publish "$1" && echo yes || echo no; }

assert_equals "gh issue create is a publish" "yes" "$(_pub 'gh issue create --title t --body-file /tmp/b.md')"
assert_equals "gh issue comment is a publish" "yes" "$(_pub 'gh issue comment 12 --body-file /tmp/b.md')"
assert_equals "gh issue edit is a publish"    "yes" "$(_pub 'gh issue edit 12 --body-file /tmp/b.md')"
assert_equals "gh pr create is a publish"     "yes" "$(_pub 'gh pr create --body hello')"
assert_equals "gh pr comment is a publish"    "yes" "$(_pub 'gh pr comment 3 -b hi')"
assert_equals "gh pr merge is NOT a publish"  "no"  "$(_pub 'gh pr merge 3 --squash')"
assert_equals "gh issue list is NOT a publish" "no" "$(_pub 'gh issue list --limit 5')"
assert_equals "git push is NOT a publish"     "no"  "$(_pub 'git push origin main')"
assert_equals "echo mentioning gh is NOT a publish" "no" "$(_pub 'echo "gh issue create later"')"
assert_equals "publish in a compound segment is detected" "yes" \
    "$(_pub 'cd /tmp && gh issue create --body-file b.md')"

# body-file extraction
assert_equals "body-file path is captured" "/tmp/b.md" \
    "$(gh_publish_body_files 'gh issue create --title t --body-file /tmp/b.md')"
assert_equals "-F short form is captured" "/tmp/x.md" \
    "$(gh_publish_body_files 'gh issue create -F /tmp/x.md')"
assert_equals "quoted path is unquoted" "/tmp/b.md" \
    "$(gh_publish_body_files 'gh issue create --body-file "/tmp/b.md"')"
assert_equals "--body-file=path form is captured" "/tmp/e.md" \
    "$(gh_publish_body_files 'gh issue create --body-file=/tmp/e.md')"
assert_equals "inline --body yields no file (scanned via the command string)" "" \
    "$(gh_publish_body_files 'gh pr comment 3 --body "hello world"')"
assert_equals "non-publish yields nothing" "" \
    "$(gh_publish_body_files 'gh issue list')"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-git-command.sh`
Expected: FAIL — `command_invokes_gh_publish: command not found`.

- [ ] **Step 3: Implement the predicates**

Append to `hooks/lib/git-command.sh`:

```bash
# --- gh publication predicates (issue #174) ---------------------------------
# A publication is any gh subcommand that writes prose to the tracker:
#   gh issue create|comment|edit, gh pr create|comment|edit.
# `gh pr merge` is deliberately excluded — it publishes no body, and it is
# already covered by the push gate's outbound legs.
#
# PAIRED: both functions iterate _gc_split_segments output with
# IFS="${_GC_SEP}". Newline-splitting is wrong here — a quoted --body
# legitimately contains newlines (issue #155).
_gc_publish_verb() {
    # $1=noun $2=verb -> 0 when this pair publishes a body
    case "$1" in
        issue|pr) ;;
        *) return 1 ;;
    esac
    case "$2" in
        create|comment|edit) return 0 ;;
        *) return 1 ;;
    esac
}

command_invokes_gh_publish() {
    local _segs _oldifs _seg
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_seg}
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;;
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -ge 3 ]; then
            case "$1" in
                gh|*/gh)
                    if _gc_publish_verb "$2" "$3"; then
                        IFS="${_oldifs}"; return 0
                    fi ;;
            esac
        fi
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    return 1
}

gh_publish_body_files() {
    # Prints one --body-file/-F path per line (surrounding quotes stripped).
    # Inline --body text is deliberately NOT parsed here: `set -- ${_seg}`
    # word-splits, so `--body "two words"` arrives as `"two` / `words"` and any
    # reconstruction under-detects — a bypass. The hook instead scans the WHOLE
    # command string, which covers inline bodies conservatively.
    local _segs _oldifs _seg _out _p
    _out=""
    _segs="$(_gc_split_segments "$1")"
    _oldifs="$IFS"
    IFS="${_GC_SEP}"
    for _seg in ${_segs}; do
        IFS="${_oldifs}"
        # shellcheck disable=SC2086
        set -- ${_seg}
        while [ "$#" -gt 0 ]; do
            case "$1" in
                '('|'{') shift ;; env) shift ;; [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        case "${1:-}" in gh|*/gh) ;; *) IFS="${_GC_SEP}"; continue ;; esac
        if [ "$#" -lt 3 ] || ! _gc_publish_verb "${2:-}" "${3:-}"; then
            IFS="${_GC_SEP}"; continue
        fi
        shift 3
        while [ "$#" -gt 0 ]; do
            _p=""
            case "$1" in
                --body-file|-F) _p="${2:-}"; shift 2 ;;
                --body-file=*)  _p="${1#--body-file=}"; shift ;;
                *) shift ;;
            esac
            if [ -n "${_p}" ]; then
                _p="${_p%\"}"; _p="${_p#\"}"; _p="${_p%\'}"; _p="${_p#\'}"
                _out="${_out}${_p}
"
            fi
        done
        IFS="${_GC_SEP}"
    done
    IFS="${_oldifs}"
    [ -n "${_out}" ] && printf '%s' "${_out}"
    return 0
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `/bin/bash -n hooks/lib/git-command.sh && bash tests/test-git-command.sh`
Expected: PASS.

- [ ] **Step 5: Mutation-prove**

Temporarily change `create|comment|edit` to `create` in `_gc_publish_verb`, re-run, confirm the suite exits non-zero. Restore.

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/git-command.sh tests/test-git-command.sh
git commit -m "feat: gh publish-command predicates for the leak gate (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: The enforcement hook

**Files:**
- Create: `hooks/publish-guard.sh`
- Modify: `hooks/hooks.json`
- Test: `tests/test-publish-guard.sh`

**Interfaces:**
- Consumes: `command_invokes_gh_publish`, `gh_publish_body_files` (Task 2); `scripts/memory-leak-check.sh` (Task 1).
- Produces: PreToolUse JSON on stdout — `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":"…"}` on a leak; nothing otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/test-publish-guard.sh`:

```bash
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-publish-guard.sh ==="

GUARD="${PROJECT_ROOT}/hooks/publish-guard.sh"

WORK="$(mktemp -d /tmp/pg-XXXXXX)"
MEM="${WORK}/memory"; REPO="${WORK}/repo"
mkdir -p "${MEM}" "${REPO}"

PRIVATE_RUN="the verdict artifact carries the head sha at verify time so an ancestor failure never blocks a commit that has since been repaired"
printf 'name: v\n---\n\n%s\n' "${PRIVATE_RUN}" > "${MEM}/feedback_verdict_sha.md"
( cd "${REPO}" && git init -q . && printf 'unrelated\n' > r.md && git add r.md \
  && git -c user.email=t@t -c user.name=t commit -q -m init )

printf 'Proposal.\n\n%s\n' "${PRIVATE_RUN}" > "${WORK}/leaky.md"
printf 'Evidence: memory/feedback_verdict_sha.md:4 (feedback, 2026-07-29).\n' > "${WORK}/clean.md"

_run() {  # _run <command>
    jq -n --arg c "$1" '{"tool_input":{"command":$c}}' \
    | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${MEM}" \
        CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null )
}

out="$(_run "gh issue create --title t --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue create is denied" '"deny"' "${out:-<empty>}"
assert_contains "deny names the source file" "feedback_verdict_sha.md" "${out:-}"
assert_not_contains "deny does not echo matched text" "verdict artifact carries the head sha" "${out:-}"

out="$(_run "gh issue create --title t --body-file ${WORK}/clean.md")"
assert_equals "clean issue create is allowed silently" "" "${out:-}"

out="$(_run "gh issue comment 12 --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue comment is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh issue edit 12 --body-file ${WORK}/leaky.md")"
assert_contains "leaky issue edit is denied" '"deny"' "${out:-<empty>}"

out="$(_run "gh pr create --title t --body \"${PRIVATE_RUN}\"")"
assert_contains "leaky inline --body is denied" '"deny"' "${out:-<empty>}"

out="$(_run 'git push origin main')"
assert_equals "git push is untouched by this hook" "" "${out:-}"

out="$(_run 'gh issue list --limit 5')"
assert_equals "gh issue list is untouched" "" "${out:-}"

out="$(_run 'ls -la')"
assert_equals "unrelated command is untouched" "" "${out:-}"

out="$(_run 'gh pr merge 3 --squash')"
assert_equals "gh pr merge is not this hook's business" "" "${out:-}"

# Absent corpus: allow, and say so.
out="$( jq -n --arg c "gh issue create --body-file ${WORK}/leaky.md" '{"tool_input":{"command":$c}}' \
        | ( cd "${REPO}" && MEMORY_LEAK_CHECK_MEMORY_DIR="${WORK}/nope" \
            CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" /bin/bash "${GUARD}" 2>/dev/null ) )"
assert_not_contains "absent corpus does not deny" '"deny"' "${out:-}"
assert_contains "absent corpus is announced" "could not check" "${out:-<empty>}"

rm -rf "${WORK}"
print_summary
exit $?
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-publish-guard.sh`
Expected: FAIL — hook does not exist, every assertion sees empty output.

- [ ] **Step 3: Write the hook**

Create `hooks/publish-guard.sh`:

```bash
#!/bin/bash
# publish-guard.sh — denies gh publications carrying private memory text (#174).
# PreToolUse (Bash matcher). Separate from openspec-guard.sh on purpose: the
# push gate's fail-open ERR trap and lib-sourcing order are load-bearing.
#
# Detection is FAIL-CLOSED (a match always denies). Inability to check is
# FAIL-OPEN and announced (absent corpus, missing jq, unreadable body).

trap 'exit 0' ERR

_INPUT="$(cat)"
command -v jq >/dev/null 2>&1 || exit 0

_COMMAND="$(printf '%s' "${_INPUT}" | jq -r '.tool_input.command // ""' 2>/dev/null)" || exit 0
case "${_COMMAND}" in *gh*) ;; *) exit 0 ;; esac

_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${_ROOT}/hooks/lib/git-command.sh" ] || exit 0
. "${_ROOT}/hooks/lib/git-command.sh" 2>/dev/null || exit 0
command -v command_invokes_gh_publish >/dev/null 2>&1 || exit 0
command -v gh_publish_body_files      >/dev/null 2>&1 || exit 0

command_invokes_gh_publish "${_COMMAND}" || exit 0

_ENGINE="${_ROOT}/scripts/memory-leak-check.sh"
[ -f "${_ENGINE}" ] || exit 0

# Announced degradation: when no corpus resolves there is nothing to leak, but
# silence would be indistinguishable from a clean check. Probe once, on the
# publish path only, so ordinary Bash calls stay quiet.
_MEMPROBE="$(/bin/bash "${_ENGINE}" /dev/null 2>&1 >/dev/null)"
case "${_MEMPROBE}" in
    *"no memory corpus"*)
        jq -n --arg msg "publish-guard: could not check — no local memory corpus resolved for this repo. Allowing (nothing to leak)." \
            '{"systemMessage":$msg}'
        exit 0 ;;
esac

_TMP="$(mktemp -d "${TMPDIR:-/tmp}/pubguard.XXXXXXXX")" || exit 0
trap 'rm -rf "${_TMP}"' EXIT

_FINDINGS=""
_UNCHECKED=""

_check() {  # _check <file> <label>
    local _out _rc
    if [ ! -r "$1" ]; then
        _UNCHECKED="${_UNCHECKED}${_UNCHECKED:+; }$2 unreadable"
        return 0
    fi
    _out="$(/bin/bash "${_ENGINE}" "$1" 2>/dev/null)"
    _rc=$?
    case "${_rc}" in
        1) _FINDINGS="${_FINDINGS}${_FINDINGS:+
}${_out}" ;;
        0) : ;;
        *) _UNCHECKED="${_UNCHECKED}${_UNCHECKED:+; }$2 engine exit ${_rc}" ;;
    esac
}

# 1. The whole command string. This is what covers an inline `--body` without
#    parsing it — strictly conservative, since a 16-word private run cannot
#    appear among flags and paths unless it IS the body.
printf '%s\n' "${_COMMAND}" > "${_TMP}/cmd"
_check "${_TMP}/cmd" "command"

# 2. Each --body-file. Iterated through a pipe-free redirect so _FINDINGS
#    survives: `... | while read` would run the loop in a SUBSHELL and every
#    finding would be discarded.
gh_publish_body_files "${_COMMAND}" > "${_TMP}/files" 2>/dev/null || : > "${_TMP}/files"
_N=0
while IFS= read -r _bf; do
    [ -n "${_bf}" ] || continue
    _N=$((_N + 1))
    _check "${_bf}" "body-file ${_N}"
done < "${_TMP}/files"

if [ -n "${_FINDINGS}" ]; then
    _MSG="PUBLICATION BLOCKED (#174): this publication reproduces private local-memory text verbatim, and the tracker is public.

${_FINDINGS}

Cite the evidence as memory/<file>.md:<line> instead of quoting it. The citation is auditable by anyone holding the corpus, and publishes no private text."
    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
    exit 0
fi

if [ -n "${_UNCHECKED}" ]; then
    jq -n --arg msg "publish-guard: could not check this body for private-memory text (${_UNCHECKED}) — allowing, but the #174 leak gate did not run." \
        '{"systemMessage":$msg}'
fi
exit 0
```

- [ ] **Step 4: Register the hook**

Edit `hooks/hooks.json` — add a second entry to the `PreToolUse` array (do NOT modify the existing `openspec-guard.sh` entry):

```json
  {
    "matcher": "Bash",
    "hooks": [
      {
        "type": "command",
        "command": "${CLAUDE_PLUGIN_ROOT}/hooks/publish-guard.sh"
      }
    ]
  },
```

Insert it directly after the existing `Bash` entry. Verify with `jq '.hooks.PreToolUse | length' hooks/hooks.json` (expect one more than before) and `jq . hooks/hooks.json >/dev/null` for validity.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `/bin/bash -n hooks/publish-guard.sh && bash tests/test-publish-guard.sh`
Expected: PASS.

- [ ] **Step 6: Confirm the push gate is unperturbed**

Run: `bash tests/test-push-gate-detection.sh && bash tests/test-push-gate-failclosed.sh`
Expected: PASS, unchanged.

- [ ] **Step 7: Mutation-prove**

Temporarily make `command_invokes_gh_publish` always return 1, re-run `bash tests/test-publish-guard.sh`, confirm non-zero exit. Restore.

- [ ] **Step 8: Commit**

```bash
git add hooks/publish-guard.sh hooks/hooks.json tests/test-publish-guard.sh
git commit -m "feat: publish-guard denies gh publications carrying private memory text (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Canary and drift coverage

**Files:**
- Modify: `hooks/session-start-hook.sh:617-624` (parse-check block) and `:676` (drift file list)
- Test: `tests/test-push-gate-canary.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: a `PUSH-GATE CANARY` warning when `hooks/publish-guard.sh` is missing or unparseable, and `PLUGIN DRIFT CANARY` coverage for it.

`publish-guard.sh` is parse-checked, **not** source-probed — it executes and reads stdin, exactly like `openspec-guard.sh` and `skill-gate.sh`. It must NOT be added to `_GATE_ENFORCE_LIBS`, whose members are source-probed.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-push-gate-canary.sh` (before `print_summary`), following the file's existing harness for staging a plugin root and running session-start:

```bash
# --- publish-guard is canaried (#174) ---------------------------------------
# Uses the same staging helper the file already uses for the other components.
_stage_plugin_copy
rm -f "${STAGE}/hooks/publish-guard.sh"
out="$(_run_session_start)"
assert_contains "missing publish-guard.sh trips the canary" "publish-guard.sh (missing)" "${out:-<empty>}"

_stage_plugin_copy
printf 'if [ \n' > "${STAGE}/hooks/publish-guard.sh"
out="$(_run_session_start)"
assert_contains "unparseable publish-guard.sh trips the canary" "publish-guard.sh (unparseable)" "${out:-<empty>}"
```

If `_stage_plugin_copy` / `_run_session_start` are named differently in that file, reuse whatever the existing `openspec-guard.sh` cases use — mirror them exactly rather than inventing new helpers.

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-push-gate-canary.sh`
Expected: FAIL — the canary does not mention `publish-guard.sh`.

- [ ] **Step 3: Extend the canary**

In `hooks/session-start-hook.sh`, immediately after the `skill-gate.sh` parse-check block (ends at the line before `# Gate libs: SOURCE-probe…`), insert:

```bash
# publish-guard.sh (#174 leak gate): same shape as skill-gate.sh above — it
# executes and reads stdin (PreToolUse Bash), so parse-check only. It must NOT
# join _GATE_ENFORCE_LIBS, whose members are source-probed.
if [ ! -f "${PLUGIN_ROOT}/hooks/publish-guard.sh" ]; then
    _CANARY_BAD="${_CANARY_BAD}${_CANARY_BAD:+, }publish-guard.sh (missing)"
elif ! /bin/bash -n "${PLUGIN_ROOT}/hooks/publish-guard.sh" >/dev/null 2>&1; then
    _CANARY_BAD="${_CANARY_BAD}${_CANARY_BAD:+, }publish-guard.sh (unparseable)"
fi
```

Then extend the drift file list (currently line 676):

```bash
        for _df in "hooks/openspec-guard.sh" "hooks/skill-gate.sh" "hooks/publish-guard.sh" ${_GATE_ENFORCE_LIBS}; do
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `/bin/bash -n hooks/session-start-hook.sh && bash tests/test-push-gate-canary.sh && bash tests/test-plugin-drift-canary.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/session-start-hook.sh tests/test-push-gate-canary.sh
git commit -m "feat: canary and drift coverage for publish-guard (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `improvement-miner` citation contract

**Files:**
- Modify: `skills/improvement-miner/SKILL.md` (lines 59, 72-79, 108-113, 121-145)
- Test: `tests/test-improvement-miner.sh` (append)

**Interfaces:**
- Consumes: nothing at runtime.
- Produces: SKILL.md text asserted by the content test.

- [ ] **Step 1: Write the failing test**

Append to `tests/test-improvement-miner.sh` (before `print_summary`):

```bash
# --- citation contract (#174) -----------------------------------------------
SKILL_MD="${PROJECT_ROOT}/skills/improvement-miner/SKILL.md"

assert_contains "SKILL.md mandates path:line citation" \
    "memory/<file>.md:<line>" "$(cat "${SKILL_MD}")"
assert_contains "SKILL.md keeps the verbatim quote in the in-session report" \
    "not a publication surface" "$(cat "${SKILL_MD}")"
assert_contains "SKILL.md corrects the --body-file misreading" \
    "not a confidentiality control" "$(cat "${SKILL_MD}")"
assert_not_contains "SKILL.md no longer asks for a verbatim quote in the candidate contract" \
    "verbatim source quote + provenance" "$(cat "${SKILL_MD}")"
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bash tests/test-improvement-miner.sh`
Expected: FAIL on all four assertions.

- [ ] **Step 3: Edit SKILL.md**

Four targeted edits. Preserve surrounding text — do not rewrite the file.

At line 59, replace:
```
  worth a durable fix. Read the underlying memory file for detail; quote the
  exact line you rely on (A12 spot-check: a misquoted source descopes memory
  sources).
```
with:
```
  worth a durable fix. Read the underlying memory file for detail; cite the
  exact line you rely on as `memory/<file>.md:<line>` and confirm the line
  says what you claim (A12 spot-check: a miscited source descopes memory
  sources — a reader verifies with `sed -n '<line>p'`).
```

At line 77, replace:
```
- verbatim source quote + provenance: source sha or issue number,
  observed-at date, run id when citing workflow output.
```
with:
```
- source citation + provenance: for memory evidence, `memory/<file>.md:<line>`
  plus the observed-at date; for non-private evidence (eval-report bodies,
  gate output, shas, issue numbers) a verbatim quote is still fine. Source sha
  or issue number, observed-at date, run id when citing workflow output.
```

In Step 5 (Report), after the first sentence, add:
```
The in-session report is NOT a publication surface: quote memory evidence
verbatim HERE, where the quote is what makes the approve/reject decision at
Step 6 reviewable. The citation-only rule applies to published bodies (Steps 7
and 8), not to this report.
```

In Step 7, immediately before the `Title sanitization:` paragraph, add:
```
**Published bodies carry citations, never private text.** The tracker is
public and the memory corpus is not. Cite memory evidence as
`memory/<file>.md:<line>` with an observed-at date; never paste the line.
`hooks/publish-guard.sh` enforces this deterministically and will deny the
`gh issue create` if private text survives into the body (issue #174).
```

And extend the `--body-file` paragraph (line 140-145) with:
```
That rule is a **command-injection** control and is **not a confidentiality
control** — it governs how the bytes are passed, never what they say. The
confidentiality control is the citation rule above.
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `bash tests/test-improvement-miner.sh && bash tests/test-skill-anatomy.sh && bash tests/test-skill-content-coverage.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/improvement-miner/SKILL.md tests/test-improvement-miner.sh
git commit -m "feat: improvement-miner cites memory evidence by path:line (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Documentation

**Files:**
- Modify: `CLAUDE.md` (Gotchas section), `CHANGELOG.md` (`[Unreleased]`)

**Interfaces:**
- Consumes: nothing.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Add the CLAUDE.md gotcha**

Append one bullet to the Gotchas list:

```markdown
- **Publication is a separate trust boundary from intake.** `improvement-miner` may READ the whole local memory corpus but may not PUBLISH it: `hooks/publish-guard.sh` (PreToolUse `Bash`) denies `gh issue|pr create|comment|edit` whose body reproduces a 16+-word run present in `~/.claude/projects/<slug>/memory/` and absent from the repo's tracked content, via `scripts/memory-leak-check.sh`. Detection is fail-closed; inability to check (no corpus, no jq, unreadable body) is fail-open AND announced. Threshold 16 is read off a measured 16–25 plateau (0 false positives across 19 held-out non-miner issues; N=8 would deny 8 of 19). Shingles are built PER FILE — a shared word buffer fabricates matches spanning two files. The public exemption is load-bearing, not an optimization: without it, any issue restating a CLAUDE.md gotcha is denied. Residual gap, accepted: the citation publishes the memory FILENAME, and ~1 slug in 164 names a client — reviewed at the miner's human gate, because proper-noun matching is the fitted-heuristic failure mode the design rejects. `SKILL.md`'s `--body-file` rule is a COMMAND-INJECTION control and is not confidentiality — that misreading is what kept #174 open. PAIRED: `publish-guard.sh` is parse-checked in the session-start canary and in the drift manifest, but must NOT join `_GATE_ENFORCE_LIBS` (source-probed). Regression: `tests/test-memory-leak-check.sh`, `tests/test-publish-guard.sh`.
```

- [ ] **Step 2: Add the CHANGELOG entry**

Under `## [Unreleased]`, in the `### Added` subsection (create it if absent):

```markdown
- Publication leak gate (#174): `scripts/memory-leak-check.sh` + `hooks/publish-guard.sh` deny `gh issue|pr create|comment|edit` whose body reproduces private local-memory text; `improvement-miner` now cites memory evidence as `memory/<file>.md:<line>` instead of quoting it verbatim.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md CHANGELOG.md
git commit -m "docs: record the publication leak gate (#174)

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Remediate the 8 published bodies

**Files:** none in-repo. Mutates GitHub issues #124, #125, #127, #137, #138, #142, #143, #131.

**Interfaces:**
- Consumes: `scripts/memory-leak-check.sh` (Task 1), `hooks/publish-guard.sh` (Task 3 — it will gate these very edits, which is the intended dogfood).

This task is deliberately last: it needs the engine to verify each rewrite, and the guard to prove the rewrites pass their own gate.

- [ ] **Step 1: Confirm the current state**

```bash
for N in 124 125 127 131 137 138 142 143; do
  gh issue view "$N" --json body --jq '.body' > "/tmp/issue-$N.md"
  printf '#%s ' "$N"
  /bin/bash scripts/memory-leak-check.sh "/tmp/issue-$N.md" | tail -1
done
```
Expected: each prints a `private-memory run(s)` summary line naming its source file.

- [ ] **Step 2: Rewrite one body**

For each issue, replace only the flagged passages with a citation of the form:

```
Evidence: `memory/<file>.md:<line>` (<kind>, observed <YYYY-MM-DD>) — <one-line paraphrase in your own words>.
```

Keep everything else — title, structure, A/B contract, fingerprint — byte-identical. Write the new body to `/tmp/issue-<N>-new.md` with the Write tool, never by shell interpolation.

- [ ] **Step 3: Verify the rewrite before publishing**

```bash
/bin/bash scripts/memory-leak-check.sh /tmp/issue-<N>-new.md; echo "exit=$?"
```
Expected: `exit=0` and no `LEAK:` lines. Do not proceed to Step 4 while this is non-zero.

- [ ] **Step 4: Publish the rewrite**

```bash
gh issue edit <N> --body-file /tmp/issue-<N>-new.md
```
The new guard evaluates this command. A deny here means Step 3 was skipped or the paraphrase still carries a 16-word private run — fix the body, do not bypass the guard.

- [ ] **Step 5: Repeat Steps 2–4 for all eight issues**

Order: 124, 125, 127, 131, 137, 138, 142, 143.

- [ ] **Step 6: Confirm the tracker passes its own gate**

```bash
gh issue list --state all --limit 200 --json number --jq '.[].number' \
| while IFS= read -r N; do
    gh issue view "$N" --json body --jq '.body' > "/tmp/v-$N.md"
    /bin/bash scripts/memory-leak-check.sh "/tmp/v-$N.md" >/dev/null 2>&1 \
      || echo "STILL FLAGGED: #$N"
  done
```
Expected: no output.

- [ ] **Step 7: Record the outcome on #174**

Comment on #174 with the counts and the eight issue numbers — **numbers and file paths only, never the removed text.**

---

### Task 8: Full verification

**Files:** none.

- [ ] **Step 1: Run the whole suite**

Run: `bash tests/run-tests.sh`
Expected: all suites pass. Investigate any failure before proceeding — do not push on a red suite.

- [ ] **Step 2: Syntax-check every changed shell file under Bash 3.2**

```bash
for f in scripts/memory-leak-check.sh hooks/publish-guard.sh hooks/lib/git-command.sh hooks/session-start-hook.sh; do
  /bin/bash -n "$f" && echo "OK $f"
done
```
Expected: `OK` for each.

- [ ] **Step 3: Produce the verdict required to push**

This branch touches `skills/` and `hooks/`, so push-gate routing-governance denies the push without a clean verdict covering HEAD. Invoke `Skill(auto-claude-skills:project-verification)` and let it write the verdict via the sanctioned path (`scripts/verify-and-record.sh`) — do not hand-write the artifact.

- [ ] **Step 4: Review before merge**

Invoke `Skill(superpowers:requesting-code-review)`. This change adds an enforcement surface and touches `hooks/`, so the adversarial-governance lens applies: confirm no existing gate is weakened, and that `publish-guard.sh` cannot alter any `openspec-guard.sh` decision.

---

## Self-Review

**Spec coverage** — every requirement maps to a task:

| Spec requirement | Task |
|---|---|
| pdlc-safety: deny on 16-word private run | 1, 3 |
| pdlc-safety: per-file shingling, no cross-file match | 1 (test e) |
| pdlc-safety: public-content exemption | 1 (test d) |
| pdlc-safety: deny names `memory/<file>.md:<line>`, no matched text | 1 (test b), 3 |
| pdlc-safety: fail-closed detection / fail-open announced degradation | 1 (test g), 3 |
| pdlc-safety: not implemented inside `openspec-guard.sh`; push gate unperturbed | 3 (steps 3, 6) |
| pdlc-safety: corpus includes `MEMORY.md` | 1 (glob is `*.md`) |
| improvement-mining: published bodies cite path:line | 5 |
| improvement-mining: in-session report keeps the quote | 5 |
| improvement-mining: non-private evidence may still be quoted | 5 |
| improvement-mining: human gate and read access unweakened | 5 (no edit to `:128`) |
| improvement-mining: `--body-file` documented as injection-only | 5 |
| design decision 5: canary + drift coverage | 4 |
| design: remediate all 8 flagged bodies | 7 |

**Placeholder scan:** none — every code step carries runnable content. Task 4's test snippet names two harness helpers conditionally, with an explicit instruction to mirror the file's existing cases rather than invent them; that is the one place the implementer must read surrounding code first.

**Type consistency:** `command_invokes_gh_publish` and `gh_publish_body_files` are defined in Task 2 and consumed under those exact names in Task 3. `MEMORY_LEAK_CHECK_MEMORY_DIR` is the single corpus-override name across Tasks 1, 3 and their tests. Engine exit codes `0/1/2/3` are used consistently in Tasks 1, 3 and 7. `gh_publish_body_files` emits newline-separated paths and its only consumer reads them with `while IFS= read -r` from a redirect, never a pipe.
