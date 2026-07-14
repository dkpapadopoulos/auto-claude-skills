# Push-gate Review Crediting + Precise git-write Detection — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix two `openspec-guard.sh` push-gate defects at the acsm source — credit review-embedding skills toward the REVIEW milestone (#2), and detect a real `git` write by first token instead of raw substring (#3).

**Architecture:** Fix #2 is a writer-side change in `hooks/skill-completion-hook.sh` (map review-embedding skills to the canonical `requesting-code-review` ledger key). Fix #3 adds a sourceable predicate `hooks/lib/git-command.sh` (`command_invokes_git_write`) and routes `openspec-guard.sh`'s two trigger checks through it, keeping the raw-substring match only as a fail-safe fallback when the lib is absent.

**Tech Stack:** POSIX/Bash 3.2 shell hooks; `jq`; the repo's `tests/` shell-test harness (`test-helpers.sh`, `run-tests.sh`).

## Global Constraints

- **Bash 3.2 compatible** (macOS default) — no `declare -A`, no `mapfile`, no `${var,,}`. Match existing hook style.
- **Fail-open on infra error** — a missing lib / missing `jq` / parse failure MUST NOT raise or block. Hooks keep `trap 'exit 0' ERR`.
- **Preserve the fail-CLOSED push gate** — when the new lib is unavailable, behavior MUST fall back to the current substring match (never silently stop gating real pushes).
- **Canonical REVIEW key is exactly `requesting-code-review`** — review-embedding skills record under that literal string; readers are unchanged.
- **Credited review-embedding skills (exact names):** `subagent-driven-development`, `agent-team-execution`, `agent-team-review`. `executing-plans` is NOT credited.
- **branch-ledger API:** `branch_ledger_record "<milestone>" ["<proj_root>"]`, `branch_ledger_has "<milestone>" ["<proj_root>"]` (returns 0/1), `branch_ledger_dir "<proj_root>"`.
- **GOTCHA — the active session hook is the CACHED plugin, not your edits.** Editing `hooks/openspec-guard.sh` in this repo does NOT change the hook running against your Bash tool this session (that's `~/.claude/plugins/cache/acsm/…`, still the buggy version). Therefore **any Bash command whose command-line text contains the literal adjacent phrase `git push` or `git commit` will be DENIED** by the stale gate — including `git commit -m "…git push…"`. Keep those literal phrases OUT of your commit messages and ad-hoc `grep`/`echo` command lines (use "push-gate" / "write-command" / hyphenated forms). Test *files* may contain the phrase (it lives inside the file; the Bash command line is just `bash tests/<file>.sh`, which is fine to run).
- **Run tests:** `bash tests/run-tests.sh` (all) or `bash tests/<file>.sh` (one). Optional lint: `shellcheck hooks/lib/git-command.sh hooks/openspec-guard.sh hooks/skill-completion-hook.sh`.
- Spec of record: `openspec/changes/push-gate-crediting-and-detection/` (proposal + design + `specs/pdlc-safety/spec.md`).

---

## File Structure

**Modified**
- `hooks/skill-completion-hook.sh` — Fix #2: map review-embedding skills → canonical REVIEW milestone.
- `hooks/openspec-guard.sh` — Fix #3 wiring: source the lib; route the fast-path and the push discriminator through `command_invokes_git_write`, with substring fallback.

**New**
- `hooks/lib/git-command.sh` — Fix #3 predicate `command_invokes_git_write`.

**Tests**
- `tests/test-completion-ledger.sh` — extend (structural: new arm present).
- `tests/test-completion-ledger-crediting.sh` — new (behavioral: SDD completion records REVIEW; executing-plans does not).
- `tests/test-git-command.sh` — new (unit: the predicate across cases).
- `tests/test-push-gate-detection.sh` — new (behavioral: read-only phrase not gated; real push gated).

---

## Task 1: Fix #2 — credit review-embedding skills toward REVIEW

**Files:**
- Modify: `hooks/skill-completion-hook.sh` (the milestone `case`, currently lines 71-84)
- Modify: `tests/test-completion-ledger.sh`
- Create: `tests/test-completion-ledger-crediting.sh`

**Interfaces:**
- Consumes: `branch_ledger_record "<milestone>" ` (from `hooks/lib/branch-ledger.sh`); `_BARE`, `_PLUGIN_ROOT` (already set in the hook).
- Produces: on completion of a review-embedding skill, a branch-ledger milestone recorded under key `requesting-code-review`.

- [ ] **Step 1: Extend the structural test (RED)**

Append to `tests/test-completion-ledger.sh`, before `print_summary`:

```sh
assert_contains "credits subagent-driven-development"  "subagent-driven-development" "${h}"
assert_contains "credits agent-team-execution"         "agent-team-execution"        "${h}"
assert_contains "credits agent-team-review"            "agent-team-review"           "${h}"
assert_contains "review-embedding arm records canonical key" 'branch_ledger_record "requesting-code-review"' "${h}"
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `bash tests/test-completion-ledger.sh`
Expected: FAIL on the four new assertions (`_BARE` case does not yet name the review-embedding skills).

- [ ] **Step 3: Write the behavioral test (RED)**

Create `tests/test-completion-ledger-crediting.sh`:

```sh
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-completion-ledger-crediting.sh ==="

HOOK="${PROJECT_ROOT}/hooks/skill-completion-hook.sh"

# Sandbox HOME; transcript basename "t" -> token "session-t".
_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/cl-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# A valid composition state must exist or the hook exits early.
printf '%s' '{"chain":[],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

# Build a PostToolUse(Skill) payload for a given completed skill name.
_run_completion() {
    jq -n --arg tp "$_TPATH" --arg name "$1" \
      '{"transcript_path":$tp,"tool_response":{"is_error":false},"tool_input":{"name":$name}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${HOOK}" >/dev/null 2>&1
}

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/branch-ledger.sh"

# (a) subagent-driven-development completion => REVIEW milestone recorded.
_run_completion "subagent-driven-development"
if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
    _record_pass "SDD completion records canonical REVIEW milestone"
else
    _record_fail "SDD completion records canonical REVIEW milestone" "ledger has no requesting-code-review"
fi

# (b) executing-plans completion => NO REVIEW milestone.
rm -rf "$(branch_ledger_dir "${PROJECT_ROOT}")" 2>/dev/null
_run_completion "executing-plans"
if branch_ledger_has "requesting-code-review" "${PROJECT_ROOT}"; then
    _record_fail "executing-plans does NOT count as REVIEW" "ledger unexpectedly has requesting-code-review"
else
    _record_pass "executing-plans does NOT count as REVIEW"
fi

export HOME="$_OLDHOME"
print_summary
exit $?
```

- [ ] **Step 4: Run it — expect FAIL**

Run: `bash tests/test-completion-ledger-crediting.sh`
Expected: FAIL on (a) — SDD does not yet record the milestone.

- [ ] **Step 5: Implement Fix #2**

In `hooks/skill-completion-hook.sh`, replace the milestone block (currently lines 71-84, the comment through the `esac`) with a small helper + a two-arm `case`:

```sh
# ---- Durable gating-milestone ledger (push-gate readiness, branch-scoped) ----
# Record review/verify completion to a per-(repo+branch) ledger so the push gate
# survives composition chain re-anchors that reset .completed. Fail-open.
# Review-embedding skills (subagent-driven-development, agent-team-execution,
# agent-team-review) each carry a mandated internal review, so they credit the
# canonical `requesting-code-review` milestone — the same "skill-ran" proxy the
# gate already trusts for the literal review skill.
_record_gating_milestone() {
    [ -f "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" ] || return 0
    # shellcheck source=lib/branch-ledger.sh
    # `|| true` so a non-zero source cannot trip `trap ERR` and skip telemetry.
    . "${_PLUGIN_ROOT}/hooks/lib/branch-ledger.sh" 2>/dev/null || true
    branch_ledger_record "$1" 2>/dev/null || true
}
case "${_BARE}" in
    requesting-code-review|verification-before-completion)
        _record_gating_milestone "${_BARE}" ;;
    subagent-driven-development|agent-team-execution|agent-team-review)
        _record_gating_milestone "requesting-code-review" ;;
esac
```

(The guarded source string `branch-ledger.sh" 2>/dev/null || true` is preserved, so the existing assertion in `test-completion-ledger.sh:17` still holds.)

- [ ] **Step 6: Run both tests — expect PASS**

Run: `bash tests/test-completion-ledger.sh && bash tests/test-completion-ledger-crediting.sh`
Expected: both print "All tests passed."

- [ ] **Step 7: Commit** (keep the literal write-command phrase out of the message — see Global Constraints gotcha)

```bash
git add hooks/skill-completion-hook.sh tests/test-completion-ledger.sh tests/test-completion-ledger-crediting.sh
git commit -m "fix(push-gate): credit review-embedding skills toward REVIEW milestone"
```

---

## Task 2: Fix #3 helper — `command_invokes_git_write` + unit test

**Files:**
- Create: `hooks/lib/git-command.sh`
- Create: `tests/test-git-command.sh`

**Interfaces:**
- Produces: `command_invokes_git_write <command-string> [subcommands]` → returns 0 if a shell-separated segment's first real token is `git`/`*/git` with a subcommand in `[subcommands]` (default `"push commit"`), else 1. Pure predicate, no side effects, fail-open.

- [ ] **Step 1: Write the unit test (RED)**

Create `tests/test-git-command.sh`:

```sh
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-git-command.sh ==="

# shellcheck disable=SC1090
. "${PROJECT_ROOT}/hooks/lib/git-command.sh"

# _yes desc cmd [subs] : expect the predicate returns 0 (is a git write)
_yes() { if command_invokes_git_write "$2" ${3:-}; then _record_pass "$1"; else _record_fail "$1" "expected git-write: $2"; fi; }
# _no  desc cmd [subs] : expect returns 1 (not a git write)
_no()  { if command_invokes_git_write "$2" ${3:-}; then _record_fail "$1" "unexpected git-write: $2"; else _record_pass "$1"; fi; }

# Real invocations -> yes
_yes "plain push"                 "git push origin HEAD"
_yes "plain commit"               "git commit -m msg"
_yes "push with -C global flag"   "git -C /repo push -u origin feature/x"
_yes "env-prefixed commit"        "GIT_AUTHOR_NAME=x git commit -m msg"
_yes "env keyword prefix"         "env GIT_PAGER=cat git push"
_yes "chained after cd"           "cd /repo && git push"
_yes "absolute git path"          "/usr/bin/git push"

# Phrase-as-argument / read-only -> no
_no  "grep mentioning the phrase" 'grep -nE "git push|deny" hooks/openspec-guard.sh'
_no  "echo mentioning the phrase" 'echo "run git push later"'
_no  "comment only"               '# git push placeholder'
_no  "unrelated git read"         "git status"
_no  "git log is not a write"     "git log --oneline -3"

# Subcommand filter: restrict to push only
_yes "commit matches default set" "git commit -m x"
_no  "commit excluded when asking push-only" "git commit -m x" "push"

print_summary
exit $?
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `bash tests/test-git-command.sh`
Expected: FAIL/erroring — `hooks/lib/git-command.sh` does not exist yet.

- [ ] **Step 3: Implement the predicate**

Create `hooks/lib/git-command.sh`:

```sh
#!/bin/bash
# git-command.sh — predicate: does a shell command actually INVOKE a git write
# (push/commit), vs merely mention the phrase as an argument/string? Sourced by
# openspec-guard.sh. Bash 3.2 compatible. No side effects. Fail-open by design:
# a parse it cannot handle returns 1 (not a write) — callers that need
# fail-CLOSED behavior keep a substring fallback.

# command_invokes_git_write <command> [subcommands]
#   subcommands: space-separated, default "push commit".
#   Returns 0 if any ; | && || -separated segment's first real token is git
#   (or */git) whose first non-flag argument is one of <subcommands>.
command_invokes_git_write() {
    _gc_cmd="$1"
    _gc_want="${2:-push commit}"
    # One segment per line: split on && || ; |
    _gc_segs="$(printf '%s' "${_gc_cmd}" | sed -e 's/&&/\
/g' -e 's/||/\
/g' -e 's/[;|]/\
/g')"
    _gc_oldifs="$IFS"
    IFS='
'
    for _gc_seg in ${_gc_segs}; do
        IFS="${_gc_oldifs}"
        # Word-split the segment with default IFS.
        # shellcheck disable=SC2086
        set -- ${_gc_seg}
        # Strip leading `env` and VAR=val assignment prefixes.
        while [ "$#" -gt 0 ]; do
            case "$1" in
                env) shift ;;
                [A-Za-z_]*=*) shift ;;
                *) break ;;
            esac
        done
        if [ "$#" -gt 0 ]; then
            case "$1" in
                git|*/git)
                    shift
                    # Skip git global flags to reach the subcommand.
                    _gc_sub=""
                    while [ "$#" -gt 0 ]; do
                        case "$1" in
                            -C|-c|--git-dir|--work-tree|--namespace)
                                if [ "$#" -ge 2 ]; then shift 2; else shift; fi ;;
                            -*) shift ;;
                            *) _gc_sub="$1"; break ;;
                        esac
                    done
                    for _gc_w in ${_gc_want}; do
                        if [ "${_gc_sub}" = "${_gc_w}" ]; then
                            IFS="${_gc_oldifs}"
                            return 0
                        fi
                    done
                    ;;
            esac
        fi
        IFS='
'
    done
    IFS="${_gc_oldifs}"
    return 1
}
```

- [ ] **Step 4: Run it — expect PASS**

Run: `bash tests/test-git-command.sh`
Expected: "All tests passed."

- [ ] **Step 5: Lint**

Run: `shellcheck hooks/lib/git-command.sh`
Expected: no errors (warnings intentionally silenced with inline `disable` are acceptable).

- [ ] **Step 6: Commit**

```bash
git add hooks/lib/git-command.sh tests/test-git-command.sh
git commit -m "feat(push-gate): add command_invokes_git_write first-token detector"
```

---

## Task 3: Fix #3 wiring — route openspec-guard through the detector

**Files:**
- Modify: `hooks/openspec-guard.sh` (source lib after `_COMMAND` extraction; fast-path at lines 24-28; push discriminator at line 58-59)
- Create: `tests/test-push-gate-detection.sh`

**Interfaces:**
- Consumes: `command_invokes_git_write` (Task 2).
- Produces: the gate enters its logic and applies the deny path only for real `git push`/`git commit`; a command merely mentioning the phrase exits early (no deny).

- [ ] **Step 1: Write the behavioral test (RED)**

Create `tests/test-push-gate-detection.sh` (models `test-push-gate-ledger.sh`; NO ledger/verdict set up, so a real push denies and a non-push does not):

```sh
#!/usr/bin/env bash
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
echo "=== test-push-gate-detection.sh ==="

GUARD="${PROJECT_ROOT}/hooks/openspec-guard.sh"

_OLDHOME="$HOME"
export HOME="$(mktemp -d /tmp/pgd-home-XXXXXX)"
mkdir -p "$HOME/.claude"
_TPATH="$HOME/t.jsonl"; touch "$_TPATH"
_TOK="session-t"
# REVIEW+VERIFY in chain, completed empty, no ledger, no verdict => a real push
# hits the fail-closed gate and DENIES. A non-write command must exit before that.
printf '%s' '{"chain":["requesting-code-review","verification-before-completion"],"current_index":0,"completed":[]}' \
    > "$HOME/.claude/.skill-composition-state-${_TOK}"

_run() {
    jq -n --arg tp "$_TPATH" --arg c "$1" \
      '{"transcript_path":$tp,"tool_input":{"command":$c}}' \
    | CLAUDE_PLUGIN_ROOT="${PROJECT_ROOT}" bash "${GUARD}" 2>/dev/null
}

# (a) Read-only command that merely mentions the phrase -> NO deny.
out="$(_run 'grep -nE "git push|deny" hooks/openspec-guard.sh')"
assert_not_contains "grep with phrase is not gated" '"deny"' "${out:-}"

# (b) echo mentioning the phrase -> NO deny.
out="$(_run 'echo "reminder: git push later"')"
assert_not_contains "echo with phrase is not gated" '"deny"' "${out:-}"

# (c) A real push with no evidence -> DENY (gate still fires).
out="$(_run 'git push origin HEAD')"
assert_contains "real push is gated" '"deny"' "${out:-<empty>}"

# (d) A real push via -C global flag -> DENY.
out="$(_run 'git -C /tmp/x push -u origin feature/y')"
assert_contains "push with -C is gated" '"deny"' "${out:-<empty>}"

export HOME="$_OLDHOME"
print_summary
exit $?
```

- [ ] **Step 2: Run it — expect FAIL**

Run: `bash tests/test-push-gate-detection.sh`
Expected: FAIL on (a)/(b) — the current substring match denies the `grep`/`echo` because their text contains the phrase.

- [ ] **Step 3: Source the lib early**

In `hooks/openspec-guard.sh`, immediately AFTER the `_COMMAND`/`_TRANSCRIPT` extraction block (after line 22, before the `# Fast path` comment at line 24), insert:

```sh
# Precise git-write detection (fail-open): source the predicate. If unavailable,
# the substring fallbacks below preserve the original (fail-closed) behavior.
_GC_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
[ -f "${_GC_ROOT}/hooks/lib/git-command.sh" ] && \
    . "${_GC_ROOT}/hooks/lib/git-command.sh" 2>/dev/null || true
```

- [ ] **Step 4: Route the fast-path through the detector**

Replace the fast-path (lines 24-28):

```sh
# Fast path: only care about git commit/push
case "${_COMMAND}" in
    *"git commit"*|*"git push"*) ;;
    *) exit 0 ;;
esac
```

with:

```sh
# Fast path: only proceed for a REAL git commit/push invocation. Precise when the
# detector lib loaded; substring fallback (fail-closed) when it did not.
if command -v command_invokes_git_write >/dev/null 2>&1; then
    command_invokes_git_write "${_COMMAND}" || exit 0
else
    case "${_COMMAND}" in *"git commit"*|*"git push"*) ;; *) exit 0 ;; esac
fi
```

- [ ] **Step 5: Route the push discriminator through the detector**

Replace the opening of the push-gate case (lines 58-59):

```sh
case "${_COMMAND}" in
    *"git push"*)
```

with an `if` guarded by the detector (substring fallback preserves fail-closed):

```sh
if command -v command_invokes_git_write >/dev/null 2>&1; then
    _gc_is_push=false; command_invokes_git_write "${_COMMAND}" "push" && _gc_is_push=true
else
    case "${_COMMAND}" in *"git push"*) _gc_is_push=true ;; *) _gc_is_push=false ;; esac
fi
if [ "${_gc_is_push}" = "true" ]; then
```

Then find the matching close of that `case` — the `;;` followed by `esac` that ends the `*"git push"*)` branch (originally at lines 234-235):

```sh
        ;;
esac
```

and replace it with a single `fi`:

```sh
fi
```

Leave the SHIP-phase advisory section (originally from line 237, `# Check if we're in SHIP phase`) unchanged — it runs after this block for both commit and push.

- [ ] **Step 6: Run the detection + existing gate tests — expect PASS**

Run: `bash tests/test-push-gate-detection.sh && bash tests/test-push-gate-ledger.sh && bash tests/test-push-gate-failclosed.sh && bash tests/test-push-gate-verdict.sh`
Expected: all print "All tests passed." (existing gate behavior preserved; new detection passes.)

- [ ] **Step 7: Full suite + lint**

Run: `bash tests/run-tests.sh`
Expected: all files pass, exit 0.
Run: `shellcheck hooks/openspec-guard.sh`
Expected: no new errors.

- [ ] **Step 8: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-push-gate-detection.sh
git commit -m "fix(push-gate): trigger only on real git writes, not phrase mentions"
```

---

## Self-Review

**1. Spec coverage** (`openspec/changes/push-gate-crediting-and-detection/specs/pdlc-safety/spec.md`):
- "REVIEW milestone credited to review-embedding skills" → Task 1 (SDD/agent-team arms; `executing-plans` excluded; fail-open source). Scenarios: SDD-satisfies-gate (Task 1 behavioral + the gate reads the same key), executing-plans-not-credited (Task 1 (b)), recording-fail-open (guarded source retained; the `_record_gating_milestone` `[ -f … ] || return 0` + `|| true` guards).
- "git-write gate fires only on real invocations" → Tasks 2+3. Scenarios: read-only phrase not gated (Task 3 (a)/(b)), real push still gated (Task 3 (c)/(d)), env-prefixed commit detected (Task 2 unit `env-prefixed commit`). Fail-open parse → predicate returns 1 + substring fallback (Task 3 Steps 4/5).

**2. Placeholder scan:** none — every step has complete code and exact commands.

**3. Type/name consistency:** `command_invokes_git_write` (Task 2) used identically in Task 3 Steps 4-5. Milestone key `requesting-code-review` consistent across Task 1 and the unchanged readers. `branch_ledger_has/record/dir` signatures match `test-push-gate-ledger.sh` usage. Credited skill names identical to Global Constraints.

**Ordering:** Task 2 (helper) precedes Task 3 (wiring), which sources it. Task 1 is independent and may run first.
