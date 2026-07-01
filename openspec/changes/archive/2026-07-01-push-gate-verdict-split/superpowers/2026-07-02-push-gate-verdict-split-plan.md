# Push-Gate Verdict Split (Phase B) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split *status* (a gating Skill returned) from *verdict* (it passed): harden the `git push` gate on an owned, SHA-fresh verification verdict — without ever re-introducing the PR #81 false-blocks.

**Architecture:** Keep `.completed` + branch-ledger as the unchanged STATUS layer. Add a fail-open `hooks/lib/verdict.sh` that reads the owned `~/.claude/.skill-project-verified-<token>` artifact (gaining a `sha` field). `hooks/openspec-guard.sh` gains (a) fail-open verify-verdict hardening and (b) a fail-closed routing-governance gate scoped to skill-routing plugin repos. Verdict is read live at push time (no new ledger).

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), jq (optional at runtime), git. Spec at `openspec/changes/push-gate-verdict-split/`.

## Global Constraints

- Bash 3.2 compatible: no associative arrays; no quoted operands in `$(( ))`; syntax-check every hook edit with `/bin/bash -n`.
- All new hook/lib code fail-open: on any error, behave as "no usable verdict" so the caller falls back to STATUS behavior. Never let an unguarded non-zero trip `trap 'exit 0' ERR` and skip a later deny — guard sourced libs with `|| true` and use `&&` chains (see [[feedback_err_trap_unguarded_source_hooks]]).
- The verdict artifact is honored ONLY when its `sha` covers the pushed HEAD (== HEAD, or ancestor of HEAD on the branch). Absent/unrelated/no-sha → treat as no verdict.
- Verify-hardening DENY fires only on POSITIVE failure evidence (`failed[]` non-empty) covering HEAD → zero new false-block. `suspect`/`could_not_verify` stay advisory (consistent with the gate-gaming decision, never hard-block).
- Routing gate: DENY only when NO clean covering verdict exists; clean-but-ancestor (stale-on-branch) → advisory warn, allow. Scoped to repos containing `config/default-triggers.json`.
- Preserve every existing test: `tests/test-push-gate-ledger.sh`, `tests/test-branch-ledger.sh`, `tests/test-completion-ledger.sh`, and the two `.completed` monotonicity tests in `tests/test-routing.sh`. `tests/run-tests.sh` auto-discovers `tests/test-*.sh`.
- grep runtime output with `grep -E`/`grep -F` for literals with regex metacharacters.

## File Structure

- `skills/project-verification/SKILL.md` — artifact schema + write snippet gains `sha`.
- `hooks/lib/verdict.sh` (NEW) — fail-open verdict/diff-scope readers. One responsibility: interpret the verdict artifact + routing-diff scope. No writes.
- `hooks/openspec-guard.sh` — push-gate: verify-hardening + routing gate. Sources verdict.sh once.
- `tests/test-verdict-lib.sh` (NEW) — unit tests for verdict.sh.
- `tests/test-push-gate-verdict.sh` (NEW) — gate integration tests (model harness on `tests/test-push-gate-ledger.sh`).
- `CLAUDE.md` — gotcha entry. `CHANGELOG.md` — `[Unreleased]`.

---

### Task 1: Add `sha` to the verification verdict artifact

**Files:**
- Modify: `skills/project-verification/SKILL.md` (Step 3 emit-evidence block, ~lines 47-63)
- Test: `tests/test-push-gate-verdict.sh` (grep-guard added here; full gate tests in Task 4)

**Interfaces:**
- Produces: the artifact JSON now contains `"sha": "<git rev-parse HEAD>"` — consumed by `verdict.sh` (Task 2).

- [ ] **Step 1: Write the failing guard test** (new file `tests/test-verdict-schema.sh` OR fold into Task 4 file; here use a standalone quick guard)

```bash
# tests/test-verdict-schema.sh
#!/bin/bash
. "$(dirname "$0")/test-helpers.sh"
SKILL="$(dirname "$0")/../skills/project-verification/SKILL.md"
# The emit-evidence snippet and JSON schema must document the sha field.
if grep -q 'git rev-parse HEAD' "$SKILL" && grep -q '"sha"' "$SKILL"; then
    pass "project-verification artifact documents sha (HEAD) field"
else
    fail "project-verification artifact missing sha (HEAD) field"
fi
finish
```

- [ ] **Step 2: Run it, verify FAIL**

Run: `bash tests/test-verdict-schema.sh`
Expected: FAIL — sha not yet documented.

- [ ] **Step 3: Add `sha` to the bash snippet and JSON block**

In `skills/project-verification/SKILL.md` Step 3, change the bash snippet:

```bash
TOKEN="$(cat ~/.claude/.skill-session-token 2>/dev/null || echo default)"
SHA="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
# write the JSON below to ~/.claude/.skill-project-verified-${TOKEN} (include "sha": "$SHA")
```

Add the field to the JSON schema block (after `"gate_gaming_status"`):

```json
  "gate_gaming_status": "clean",
  "sha": "<git rev-parse HEAD — the commit this verdict covers>",
```

Add one prose line after the field-shape paragraph (~line 68):

> `sha` records the HEAD commit the verdict was produced against; the push gate honors a verdict only when this `sha` covers the pushed HEAD (equal, or an ancestor on the branch).

- [ ] **Step 4: Run it, verify PASS**

Run: `bash tests/test-verdict-schema.sh`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skills/project-verification/SKILL.md tests/test-verdict-schema.sh
git commit -m "feat: project-verification verdict artifact records HEAD sha for freshness"
```

---

### Task 2: `hooks/lib/verdict.sh` — fail-open verdict + diff-scope readers

**Files:**
- Create: `hooks/lib/verdict.sh`
- Test: `tests/test-verdict-lib.sh`

**Interfaces:**
- Consumes: artifact `sha` from Task 1.
- Produces (all fail-open; token first arg, proj_root where noted):
  - `verdict_artifact_path <token>` → prints path; non-zero if token empty.
  - `verdict_sha_is_head <token> <proj_root>` → 0 iff artifact `.sha` == HEAD.
  - `verdict_covers_head <token> <proj_root>` → 0 iff `.sha` == HEAD OR is ancestor of HEAD.
  - `verdict_has_test_failure <token>` → 0 iff present+parseable AND `(.failed|length)>0`.
  - `verdict_is_clean <token>` → 0 iff present+parseable AND `failed[]` empty AND `could_not_verify[]` empty AND `gate_gaming_status=="clean"`.
  - `verdict_failing_gates <token>` → prints comma-joined `.failed` names (empty on none).
  - `is_routing_repo <proj_root>` → 0 iff `config/default-triggers.json` exists.
  - `diff_touches_routing <proj_root>` → 0 iff branch diff vs base touches `^(skills|config|hooks)/`.

- [ ] **Step 1: Write failing unit tests** — `tests/test-verdict-lib.sh`

Harness builds a temp git repo + temp HOME with a crafted artifact. Representative cases (write all):

```bash
#!/bin/bash
. "$(dirname "$0")/test-helpers.sh"
LIB="$(cd "$(dirname "$0")/../hooks/lib" && pwd)/verdict.sh"
. "$LIB"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
REPO="$TMP/repo"; mkdir -p "$REPO"; ( cd "$REPO"
  git init -q; git config user.email t@t; git config user.name t
  mkdir -p config; echo '{}' > config/default-triggers.json
  git add -A; git commit -qm c1 )
C1="$(git -C "$REPO" rev-parse HEAD)"
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
TOKEN=tok1
mkfile() { printf '%s' "$1" > "$HOME/.claude/.skill-project-verified-${TOKEN}"; }

# clean verdict at C1
mkfile "$(jq -nc --arg s "$C1" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
verdict_is_clean "$TOKEN"            && pass "clean verdict detected"     || fail "clean verdict"
verdict_sha_is_head "$TOKEN" "$REPO" && pass "sha_is_head at C1"          || fail "sha_is_head C1"
verdict_covers_head "$TOKEN" "$REPO" && pass "covers_head at C1"          || fail "covers_head C1"
verdict_has_test_failure "$TOKEN"    && fail "clean has no failure"       || pass "clean => no failure"
is_routing_repo "$REPO"              && pass "routing repo detected"      || fail "routing repo"

# failing verdict
mkfile "$(jq -nc --arg s "$C1" '{failed:["tests"],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
verdict_has_test_failure "$TOKEN"    && pass "failure detected"           || fail "failure"
[ "$(verdict_failing_gates "$TOKEN")" = "tests" ] && pass "failing gate named" || fail "failing gate"
verdict_is_clean "$TOKEN"            && fail "failing not clean"          || pass "failing => not clean"

# ancestor sha: add C2, artifact still at C1
( cd "$REPO"; echo x >> config/default-triggers.json; git commit -qam c2 )
mkfile "$(jq -nc --arg s "$C1" '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:$s}')"
verdict_covers_head "$TOKEN" "$REPO" && pass "ancestor covers_head"       || fail "ancestor covers"
verdict_sha_is_head "$TOKEN" "$REPO" && fail "ancestor not head"          || pass "ancestor != head"

# unrelated sha (cross-branch): random 40-hex not in history
mkfile "$(jq -nc '{failed:[],could_not_verify:[],gate_gaming_status:"clean",sha:"0000000000000000000000000000000000000000"}')"
verdict_covers_head "$TOKEN" "$REPO" && fail "unrelated must NOT cover"   || pass "unrelated !covers (false-block guard)"

# no artifact
rm -f "$HOME/.claude/.skill-project-verified-${TOKEN}"
verdict_is_clean "$TOKEN"            && fail "absent not clean"           || pass "absent => not clean"
verdict_has_test_failure "$TOKEN"    && fail "absent no failure"          || pass "absent => no failure"
verdict_covers_head "$TOKEN" "$REPO" && fail "absent no cover"            || pass "absent => no cover"

# non-routing repo
REPO2="$TMP/repo2"; mkdir -p "$REPO2"; ( cd "$REPO2"; git init -q; git config user.email t@t; git config user.name t; echo hi>f; git add -A; git commit -qm c )
is_routing_repo "$REPO2"             && fail "no triggers => not routing" || pass "non-routing repo"
finish
```

- [ ] **Step 2: Run, verify FAIL** — `bash tests/test-verdict-lib.sh` → FAIL (lib missing).

- [ ] **Step 3: Implement `hooks/lib/verdict.sh`**

```bash
#!/usr/bin/env bash
# verdict.sh — read + interpret the owned verification verdict artifact
# (~/.claude/.skill-project-verified-<token>) and routing-diff scope. Separates
# STATUS (a gating Skill returned) from VERDICT (it passed). Bash 3.2. All
# functions fail-open: on any error they return "no usable verdict / no scope"
# so the push gate falls back to the status layer (never a false-block).

verdict_artifact_path() {
    local token="${1:-}"
    [ -z "$token" ] && return 1
    printf '%s' "${HOME}/.claude/.skill-project-verified-${token}"
}

_verdict_sha() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -r '.sha // empty' "$f" 2>/dev/null
}

verdict_sha_is_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -n "$head" ] && [ "$sha" = "$head" ]
}

verdict_covers_head() {
    local token="${1:-}" proot="${2:-}" sha head
    sha="$(_verdict_sha "$token")" || return 1
    [ -z "$sha" ] && return 1
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    head="$(git -C "${proot:-.}" rev-parse HEAD 2>/dev/null)" || return 1
    [ -z "$head" ] && return 1
    [ "$sha" = "$head" ] && return 0
    git -C "${proot:-.}" merge-base --is-ancestor "$sha" "$head" 2>/dev/null
}

verdict_has_test_failure() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length) > 0' "$f" >/dev/null 2>&1
}

verdict_is_clean() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 1
    [ -f "$f" ] || return 1
    command -v jq >/dev/null 2>&1 || return 1
    jq -e '((.failed // []) | length == 0)
       and ((.could_not_verify // []) | length == 0)
       and ((.gate_gaming_status // "") == "clean")' "$f" >/dev/null 2>&1
}

verdict_failing_gates() {
    local token="${1:-}" f
    f="$(verdict_artifact_path "$token")" || return 0
    [ -f "$f" ] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    jq -r '((.failed // []) | join(", "))' "$f" 2>/dev/null || true
}

is_routing_repo() {
    local proot="${1:-}"
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -n "$proot" ] && [ -f "${proot}/config/default-triggers.json" ]
}

_routing_base() {
    local proot="${1:-.}" b
    for ref in origin/HEAD '@{upstream}' origin/main main; do
        b="$(git -C "$proot" merge-base HEAD "$ref" 2>/dev/null)" && [ -n "$b" ] && { printf '%s' "$b"; return 0; }
    done
    return 1
}

diff_touches_routing() {
    local proot="${1:-}" head base names
    [ -z "$proot" ] && proot="$(git rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$proot" ] && return 1
    head="$(git -C "$proot" rev-parse HEAD 2>/dev/null)" || return 1
    base="$(_routing_base "$proot")" || return 1
    names="$(git -C "$proot" diff --name-only "$base" "$head" 2>/dev/null)" || return 1
    printf '%s\n' "$names" | grep -Eq '^(skills|config|hooks)/'
}
```

- [ ] **Step 4: Run, verify PASS** — `bash tests/test-verdict-lib.sh` → all PASS. Then `/bin/bash -n hooks/lib/verdict.sh`.

- [ ] **Step 5: Commit**

```bash
git add hooks/lib/verdict.sh tests/test-verdict-lib.sh
git commit -m "feat: verdict.sh — fail-open verification-verdict + routing-diff readers"
```

---

### Task 3: Verify-verdict hardening in the push gate (fail-open)

**Files:**
- Modify: `hooks/openspec-guard.sh` (inside `*"git push"*)` case, after the VERIFY-completed check ~line 97)
- Test: `tests/test-push-gate-verdict.sh`

**Interfaces:**
- Consumes: `verdict_covers_head`, `verdict_has_test_failure`, `verdict_failing_gates`, `_SESSION_TOKEN`, `_verif_in_chain`, `_PLUGIN_ROOT`.

- [ ] **Step 1: Write failing gate tests** — `tests/test-push-gate-verdict.sh` (model harness on `tests/test-push-gate-ledger.sh`: craft stdin JSON `{"transcript_path":...,"tool_input":{"command":"git push"}}`, temp HOME with `.skill-session-token`, composition-state with chain incl. `verification-before-completion` marked completed, and a verdict artifact; run the guard; assert stdout deny/allow). Cases:
  - verify completed(status) + **failing verdict covering HEAD** → stdout contains `"permissionDecision":"deny"` and the gate name. 
  - verify completed(status) + **failing verdict NOT covering HEAD** (stale sha) → NO deny (false-block guard).
  - verify completed(status) + **no artifact** → NO deny on verdict grounds.
  - verify completed(status) + **clean verdict covering HEAD** → NO deny.

- [ ] **Step 2: Run, verify FAIL** — `bash tests/test-push-gate-verdict.sh` → the failing-verdict-denies case FAILs (gate allows today).

- [ ] **Step 3: Initialize chain flags + source verdict.sh once, then add hardening**

Near the top of the `*"git push"*)` case (right after `_COMP_STATE=...`), ensure defaults exist:

```bash
_review_in_chain=false; _verif_in_chain=false
```
(Move/duplicate these initializers out of the `if [ -f "${_COMP_STATE}" ]` block so they are defined even when comp-state is absent. The in-block assignments remain.)

Source the lib once after the branch-ledger source (~line 60):

```bash
_VERDICT_OK=false
if [ -f "${_PLUGIN_ROOT}/hooks/lib/verdict.sh" ]; then
    # `|| true` so a non-zero source cannot trip `trap 'exit 0' ERR`.
    . "${_PLUGIN_ROOT}/hooks/lib/verdict.sh" 2>/dev/null && _VERDICT_OK=true || true
fi
```

Insert AFTER the existing Check 2 (VERIFY not-completed) `fi` (~line 97), still inside the `if [ -f "${_COMP_STATE}" ] && command -v jq ]` block:

```bash
            # Verify-verdict hardening (fail-open): status != verdict.
            # A recorded verify milestone means the Skill returned, NOT that tests
            # passed. If an owned verdict COVERS HEAD and shows a test failure, deny
            # even when status says completed. Absent/stale/cross-branch => no deny.
            if [ "${_VERDICT_OK}" = "true" ] && [ "${_verif_in_chain}" = "true" ] \
               && verdict_covers_head "${_SESSION_TOKEN}" "" \
               && verdict_has_test_failure "${_SESSION_TOKEN}"; then
                _gates="$(verdict_failing_gates "${_SESSION_TOKEN}")"
                _MSG="PUSH GATE: verification-before-completion is recorded, but the verification verdict at HEAD reports failing gate(s): ${_gates}. Fix and re-run Skill(auto-claude-skills:project-verification) before pushing."
                jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                exit 0
            fi
```

- [ ] **Step 4: Run, verify PASS + syntax + no regressions**

Run: `bash tests/test-push-gate-verdict.sh` → PASS. `/bin/bash -n hooks/openspec-guard.sh`. `bash tests/test-push-gate-ledger.sh` → still PASS.

- [ ] **Step 5: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-push-gate-verdict.sh
git commit -m "feat: push gate — fail-open verify-verdict hardening (deny on failing tests at HEAD)"
```

---

### Task 4: Routing-governance gate (fail-closed, scoped)

**Files:**
- Modify: `hooks/openspec-guard.sh` (inside `*"git push"*)` case, after Task 3's hardening, OUTSIDE the comp-state `if` so it fires without a chain)
- Test: `tests/test-push-gate-verdict.sh` (extend)

**Interfaces:**
- Consumes: `is_routing_repo`, `diff_touches_routing`, `verdict_is_clean`, `verdict_covers_head`, `verdict_sha_is_head`, `_VERDICT_OK`, `_SESSION_TOKEN`, `_STALE_MSG`.

- [ ] **Step 1: Write failing tests** (extend `tests/test-push-gate-verdict.sh`; harness makes proj_root a real git repo with `config/default-triggers.json` and a routing-path change vs base). Cases:
  - routing repo + routing diff + **no clean verdict** → deny with `project-verification` remedy.
  - routing repo + routing diff + **clean verdict covering HEAD** → NO deny.
  - routing repo + routing diff + **clean verdict at ancestor** (later commit added) → NO deny (advisory only).
  - **non-routing repo** (no `config/default-triggers.json`) + routing-named diff → NO deny.
  - routing repo + **non-routing diff** (only docs changed) → NO deny.

- [ ] **Step 2: Run, verify FAIL** — the no-clean-verdict-denies case FAILs (gate allows today).

- [ ] **Step 3: Add the routing gate** — after Task 3's block, but placed AFTER the comp-state `if ... fi` closes (so it is chain-independent), still inside the `*"git push"*)` case:

```bash
        # Routing-governance gate (fail-closed, scoped). In a skill-routing plugin
        # repo, pushes touching routing paths require a CLEAN verdict covering the
        # branch. Fires regardless of composition chain (routing changes are high-risk
        # by nature). Fail-safe: no lib / not a routing repo / base unresolvable => no gate.
        if [ "${_VERDICT_OK}" = "true" ]; then
            _proot="$(git rev-parse --show-toplevel 2>/dev/null || true)"
            if is_routing_repo "${_proot}" && diff_touches_routing "${_proot}"; then
                if verdict_is_clean "${_SESSION_TOKEN}" && verdict_covers_head "${_SESSION_TOKEN}" "${_proot}"; then
                    if ! verdict_sha_is_head "${_SESSION_TOKEN}" "${_proot}"; then
                        _STALE_MSG="${_STALE_MSG}${_STALE_MSG:+; }routing change: the clean verification verdict covers an earlier commit, not HEAD. Re-run project-verification if later commits changed routing files."
                    fi
                    : # clean + on-branch history — allow
                else
                    _MSG="PUSH GATE (routing governance): this push modifies routing files (skills/, config/, or hooks/) but no clean verification verdict covering this branch exists. Run Skill(auto-claude-skills:project-verification) until it reports a clean verdict, then push."
                    jq -n --arg msg "${_MSG}" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny"},"systemMessage":$msg}'
                    exit 0
                fi
            fi
        fi
```

- [ ] **Step 4: Run, verify PASS + syntax + full regression**

Run: `bash tests/test-push-gate-verdict.sh` → PASS. `/bin/bash -n hooks/openspec-guard.sh`. `bash tests/run-tests.sh` → all files pass (67 + 3 new).

- [ ] **Step 5: Commit**

```bash
git add hooks/openspec-guard.sh tests/test-push-gate-verdict.sh
git commit -m "feat: push gate — fail-closed routing-governance verdict gate (skills/config/hooks)"
```

---

### Task 5: Docs — CLAUDE.md gotcha + CHANGELOG

**Files:**
- Modify: `CLAUDE.md` (Gotchas section), `CHANGELOG.md` (`[Unreleased]`)

- [ ] **Step 1: Add CLAUDE.md gotcha** (under Gotchas):

> - Push gate splits **status** (a gating Skill returned — `.completed`/branch-ledger, unchanged) from **verdict** (it passed). Verify-hardening (`hooks/openspec-guard.sh` + `hooks/lib/verdict.sh`) denies `git push` only on a `failed[]`-non-empty verdict whose `sha` covers HEAD; absent/stale/cross-branch verdicts fall back to status (no false-block — the `sha`-covers-HEAD check is the load-bearing guard). A separate **routing-governance** gate (fail-closed) requires a clean covering verdict for pushes touching `skills/|config/|hooks/`, but only in repos with `config/default-triggers.json`, and only denies on absence — clean-but-ancestor warns. `suspect`/`could_not_verify` stay advisory (never hard-block), consistent with gate-gaming detection.

- [ ] **Step 2: Add CHANGELOG `[Unreleased]` entry:**

```markdown
### Added
- Push-gate verdict split (Phase B): `hooks/lib/verdict.sh` reads the owned SHA-fresh verification verdict; the push gate hardens on failing tests at HEAD (fail-open) and adds a fail-closed routing-governance gate for `skills/config/hooks` changes in skill-routing repos. Verdict artifact gains a `sha` field.
```

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md CHANGELOG.md
git commit -m "docs: document status-vs-verdict push-gate split (Phase B)"
```

---

### Task 6: Full regression + OpenSpec re-validate

- [ ] **Step 1:** `bash tests/run-tests.sh` → all pass. Capture the summary line.
- [ ] **Step 2:** `/bin/bash -n hooks/openspec-guard.sh hooks/lib/verdict.sh` → clean.
- [ ] **Step 3:** `openspec validate push-gate-verdict-split --strict` → valid.
- [ ] **Step 4:** Manual false-block probe: replay the `tests/test-push-gate-ledger.sh` "ledger satisfies both gates ⇒ ALLOW" scenario with NO verdict artifact present → still ALLOW (verdict split must not touch the PR #81 fix). Include as an assertion in `test-push-gate-verdict.sh` if not already covered.
- [ ] **Step 5:** No commit (verification only) → proceed to REVIEW.

## Self-Review

- **Spec coverage:** SHA-freshness → Task 1+2 (`verdict_covers_head`); verify-hardening → Task 3; routing gate → Task 4; review status-only → no code path derives a review verdict (unchanged), asserted implicitly. All four spec requirements have tasks.
- **Type consistency:** function names (`verdict_covers_head`, `verdict_has_test_failure`, `verdict_is_clean`, `verdict_sha_is_head`, `verdict_failing_gates`, `is_routing_repo`, `diff_touches_routing`) used identically in Tasks 2/3/4.
- **False-block guards** are explicit test cases (stale/unrelated sha, absent artifact, ledger-allow-without-verdict) — the hard constraint is a first-class assertion, not an afterthought.
