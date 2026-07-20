# memory-validate Sweep Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `scripts/memory-validate.sh` — a Bash 3.2 validator that flags structural defects (ERROR) and stale repo-path anchors (WARN) in a Claude Code auto-memory directory.

**Architecture:** A single standalone script modeled on `scripts/knowledge-validate.sh`, plus a hermetic bash test that builds a throwaway git repo + memory fixtures and asserts exit codes and messages. Structural checks fail the run (exit 1); staleness only warns (exit 0). Anchors resolve against `git … HEAD`, not the working tree.

**Tech Stack:** Bash 3.2 (macOS `/bin/bash`), `git cat-file`, `awk`, `grep -E`/`grep -F`, `sort -u`. Test harness: `tests/test-helpers.sh` (`_record_pass`/`_record_fail`/`print_summary`), auto-discovered by `tests/run-tests.sh`.

## Global Constraints

- Bash 3.2 compatible: no associative arrays, no `mapfile`, no unquoted `for x in $(...)` over paths; dedup via newline temp files + `sort -u`. (verbatim from spec / CLAUDE.md)
- Never `set -e` reasoning in the script; validator uses an `ERRORS` counter like knowledge-validate.sh. Exit 1 only on structural ERROR; WARN/NOTE never change exit code. (spec §Posture)
- Anchors resolve at HEAD: `git -C <repo-root> cat-file -e "HEAD:<path>"`. Working-tree-only path → NOTE, not WARN. (spec §Checks/4)
- `grep -F` for needles containing regex metacharacters (paths contain `.`). (spec §Bash notes)
- Ext allowlist for anchor path shape: `sh|md|json|yml|yaml|txt|ts|js|py`. (spec §Checks/4)
- Memory frontmatter nests `type:` under `metadata:` — extraction differs from knowledge-validate's top-level `type:`. Valid types: `feedback project reference user`. (spec §Checks/1)
- Script signature: `memory-validate.sh <memory-dir> [repo-root]`; `repo-root` defaults to `$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")`. (spec §Shape)

---

### Task 1: Script skeleton + frontmatter-type ERROR check (hermetic test harness)

**Files:**
- Create: `scripts/memory-validate.sh`
- Create: `tests/test-memory-validate.sh`

**Interfaces:**
- Consumes: `tests/test-helpers.sh` → `_record_pass "<label>"`, `_record_fail "<label>" "<detail>"`, `print_summary`.
- Produces: `scripts/memory-validate.sh <memory-dir> [repo-root]` — exits 1 if any memory file lacks a valid `metadata.type`, else 0. Helper (internal) `_meta_type <file>` echoes the nested type or empty.

- [ ] **Step 1: Write the failing test**

Create `tests/test-memory-validate.sh`. It builds a hermetic sandbox (throwaway git repo as repo-root + a memory dir) so HEAD resolution is deterministic and independent of the real repo.

```bash
#!/usr/bin/env bash
# test-memory-validate.sh — scripts/memory-validate.sh: structural ERRORs (exit 1),
# staleness WARNs (exit 0). Hermetic: builds a throwaway git repo + memory fixtures.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
VALIDATE="${PROJECT_ROOT}/scripts/memory-validate.sh"

echo "=== test-memory-validate.sh ==="

# --- hermetic sandbox: a repo-root with two committed files, and a memory dir ---
SBOX="$(mktemp -d)"
trap 'rm -rf "${SBOX}"' EXIT
REPO="${SBOX}/repo"; MEM="${SBOX}/memory"
mkdir -p "${REPO}/hooks" "${MEM}"
( cd "${REPO}"
  git init -q
  git config user.email t@t.t; git config user.name t
  mkdir -p hooks
  echo x > hooks/openspec-guard.sh
  echo x > config.json
  git add -A && git commit -qm init ) >/dev/null 2>&1

# helper: write a memory file
_mem() { printf '%s\n' "$2" > "${MEM}/$1"; }

# valid MEMORY.md index referencing every fixture we create with a valid type
_mem MEMORY.md "# Memory Index
- [Good](good.md) — ok"

# Fixture A: missing metadata.type -> ERROR
_mem bad_type.md "---
name: bad
metadata:
  foo: bar
---
body"
# ensure index has an entry so ONLY the type defect fires
printf '%s\n' "- [Bad](bad_type.md) — x" >> "${MEM}/MEMORY.md"

# Fixture B: valid type
_mem good.md "---
name: good
metadata:
  type: feedback
---
body"

out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "bad_type.md"; then
    _record_pass "missing metadata.type -> ERROR exit 1"
else
    _record_fail "missing metadata.type -> ERROR exit 1" "rc=${rc} out=${out}"
fi

print_summary
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: FAIL — `memory-validate.sh` does not exist yet (`rc=127`), summary reports the assertion failed.

- [ ] **Step 3: Write minimal implementation**

Create `scripts/memory-validate.sh`:

```bash
#!/usr/bin/env bash
# memory-validate.sh <memory-dir> [repo-root] — validate a Claude Code auto-memory
# directory. Structural defects -> ERROR (exit 1). Stale repo-path anchors -> WARN
# (exit 0). Bash 3.2 compatible. Advisory: never mutates memory. See
# docs/plans/2026-07-20-memory-validate-design.md.
MEM="${1:?usage: memory-validate.sh <memory-dir> [repo-root]}"
REPO="${2:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
[ -d "${MEM}" ] || exit 0
ERRORS=0
_err()  { printf '[ERROR] %s\n' "$1" >&2; ERRORS=$((ERRORS+1)); }
_warn() { printf '[WARN] %s\n'  "$1" >&2; }
_note() { printf '[NOTE] %s\n'  "$1" >&2; }

# echo the value of metadata.type (nested one level under `metadata:`), or empty.
_meta_type() {
    awk '
        NR==1 && $0=="---"{infm=1; next}
        infm && $0=="---"{exit}
        infm && $0 ~ /^metadata:[[:space:]]*$/{inmeta=1; next}
        infm && inmeta && $0 ~ /^[[:space:]]+type:[[:space:]]/{
            sub(/^[[:space:]]+type:[[:space:]]*/,""); print; exit }
        infm && inmeta && $0 ~ /^[^[:space:]]/{inmeta=0}
    ' "$1"
}

VALID_TYPES=" feedback project reference user "
for f in "${MEM}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
    t="$(_meta_type "${f}")"
    case "${VALID_TYPES}" in
        *" ${t} "*) : ;;
        *) _err "${base}: missing or invalid metadata.type ('${t}')" ;;
    esac
done

[ "${ERRORS}" -eq 0 ] || exit 1
exit 0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: PASS — "missing metadata.type -> ERROR exit 1".

- [ ] **Step 5: Commit**

```bash
git add scripts/memory-validate.sh tests/test-memory-validate.sh
git commit -m "feat: memory-validate.sh frontmatter-type ERROR check"
```

---

### Task 2: Dangling `[[slug]]` links + bidirectional index sync (ERROR)

**Files:**
- Modify: `scripts/memory-validate.sh` (add checks before the `exit` block)
- Modify: `tests/test-memory-validate.sh` (add assertions before `print_summary`)

**Interfaces:**
- Consumes: `_err`, the `for f` file loop from Task 1.
- Produces: two more ERROR conditions — a `[[slug]]` with no `<slug>.md`, and index↔disk desync (memory file missing from `MEMORY.md`, or a `(<slug>.md)` index link pointing at a missing file).

- [ ] **Step 1: Write the failing test**

Add to `tests/test-memory-validate.sh` immediately before `print_summary`:

```bash
# Fixture C: dangling [[link]] -> ERROR
_mem dangling.md "---
name: dangling
metadata:
  type: project
---
see [[nonexistent-slug]]"
printf '%s\n' "- [Dangling](dangling.md) — x" >> "${MEM}/MEMORY.md"

out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "nonexistent-slug"; then
    _record_pass "dangling [[link]] -> ERROR"
else
    _record_fail "dangling [[link]] -> ERROR" "rc=${rc} out=${out}"
fi

# Fixture D: file present on disk but absent from MEMORY.md -> ERROR (index sync)
_mem orphan_file.md "---
name: orphan
metadata:
  type: reference
---
body"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "orphan_file.md"; then
    _record_pass "file missing from index -> ERROR"
else
    _record_fail "file missing from index -> ERROR" "rc=${rc} out=${out}"
fi
# add its index entry so later assertions aren't polluted by this defect
printf '%s\n' "- [Orphan](orphan_file.md) — x" >> "${MEM}/MEMORY.md"

# Fixture E: index links a file that does not exist -> ERROR (reverse index sync)
printf '%s\n' "- [Ghost](ghost.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "ghost.md"; then
    _record_pass "index entry for missing file -> ERROR"
else
    _record_fail "index entry for missing file -> ERROR" "rc=${rc} out=${out}"
fi
# remove the ghost line to clean state for later tasks
grep -vF "ghost.md" "${MEM}/MEMORY.md" > "${MEM}/MEMORY.md.tmp" && mv "${MEM}/MEMORY.md.tmp" "${MEM}/MEMORY.md"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: FAIL on the three new assertions (checks not implemented).

- [ ] **Step 3: Write minimal implementation**

In `scripts/memory-validate.sh`, inside the existing `for f` loop (after the type check, before the loop's `done`), add the dangling-link check:

```bash
    for ref in $(grep -oE '\[\[[a-z0-9_-]+\]\]' "${f}" | sed 's/\[\[//;s/\]\]//' | sort -u); do
        [ -e "${MEM}/${ref}.md" ] || _err "${base}: dangling link [[${ref}]]"
    done
```

Then, after the `for f` loop closes, add bidirectional index sync:

```bash
if [ -e "${MEM}/MEMORY.md" ]; then
    # forward: every memory file appears in the index
    for f in "${MEM}"/*.md; do
        [ -e "${f}" ] || continue
        base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
        grep -qF "(${base})" "${MEM}/MEMORY.md" || _err "MEMORY.md missing entry for ${base}"
    done
    # reverse: every (<slug>.md) index link points at an existing file
    for link in $(grep -oE '\([a-z0-9_-]+\.md\)' "${MEM}/MEMORY.md" | sed 's/[()]//g' | sort -u); do
        [ -e "${MEM}/${link}" ] || _err "MEMORY.md links missing file (${link})"
    done
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: PASS on all assertions.

- [ ] **Step 5: Commit**

```bash
git add scripts/memory-validate.sh tests/test-memory-validate.sh
git commit -m "feat: memory-validate.sh dangling-link + bidirectional index sync"
```

---

### Task 3: Stale repo-path anchor check (WARN) with fenced-block skip + working-tree NOTE

**Files:**
- Modify: `scripts/memory-validate.sh` (add anchor scan after index sync, before exit)
- Modify: `tests/test-memory-validate.sh` (add WARN/NOTE/no-false-positive assertions)

**Interfaces:**
- Consumes: `_warn`, `_note`, `REPO`, the memory `for f` loop pattern.
- Produces: for each memory file, unresolved-at-HEAD backtick path anchors → WARN (exit unchanged); path resolvable in working tree but not HEAD → NOTE; anchors inside fenced code blocks ignored; `:NN` suffix stripped before resolution.

- [ ] **Step 1: Write the failing test**

Add to `tests/test-memory-validate.sh` before `print_summary`. These use the hermetic `${REPO}` (committed: `hooks/openspec-guard.sh`, `config.json`).

```bash
# Fixture F: anchor to a path absent at HEAD -> WARN, but exit stays 0 (reproduces #125)
_mem stale_anchor.md "---
name: stale
metadata:
  type: project
---
The old file \`hooks/deleted-file.sh\` no longer exists."
printf '%s\n' "- [Stale](stale_anchor.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -qF "hooks/deleted-file.sh"; then
    _record_pass "stale anchor -> WARN, exit stays 0"
else
    _record_fail "stale anchor -> WARN, exit stays 0" "rc=${rc} out=${out}"
fi

# Fixture G: anchor to a path that DOES exist at HEAD -> no warning
_mem live_anchor.md "---
name: live
metadata:
  type: project
---
Guard lives at \`hooks/openspec-guard.sh:12\` today."
printf '%s\n' "- [Live](live_anchor.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if printf '%s' "${out}" | grep -qF "openspec-guard.sh"; then
    _record_fail "live anchor -> no warning" "unexpected warn: ${out}"
else
    _record_pass "live anchor (with :line) -> no warning"
fi

# Fixture H: anchor inside a fenced code block -> ignored (no warning)
_mem fenced.md "---
name: fenced
metadata:
  type: reference
---
Example:
\`\`\`
cat \`hooks/imaginary-in-fence.sh\`
\`\`\`"
printf '%s\n' "- [Fenced](fenced.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if printf '%s' "${out}" | grep -qF "imaginary-in-fence.sh"; then
    _record_fail "fenced-block anchor ignored" "leaked: ${out}"
else
    _record_pass "fenced-block anchor ignored"
fi

# Fixture I: path exists in working tree but not at HEAD -> NOTE, not WARN
echo x > "${REPO}/uncommitted.md"   # on disk, never committed
_mem wt_only.md "---
name: wtonly
metadata:
  type: project
---
Draft at \`uncommitted.md\` here."
printf '%s\n' "- [WT](wt_only.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if printf '%s' "${out}" | grep -qF "[NOTE]" && printf '%s' "${out}" | grep -qF "uncommitted.md"; then
    _record_pass "working-tree-only path -> NOTE not WARN"
else
    _record_fail "working-tree-only path -> NOTE not WARN" "rc=${rc} out=${out}"
fi
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: FAIL on the new anchor assertions (check not implemented — no WARN/NOTE emitted).

- [ ] **Step 3: Write minimal implementation**

In `scripts/memory-validate.sh`, after the index-sync block and before the final `exit`, add the anchor scan. It re-loops memory files, strips fenced blocks, extracts allowlisted path anchors, and resolves each at HEAD.

```bash
# Stale repo-path anchor scan (WARN-only; never affects exit code).
_ANCHOR_EXT='sh|md|json|ya?ml|txt|ts|js|py'
for f in "${MEM}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
    # strip fenced code blocks (toggle on lines beginning with ```), then extract
    # backtick-wrapped path-shaped tokens, drop :NN suffix, dedup.
    anchors="$(awk '
        /^```/{infence = !infence; next}
        !infence{print}
    ' "${f}" \
      | grep -oE "\`[A-Za-z0-9_./-]+\.(${_ANCHOR_EXT})(:[0-9]+)?\`" \
      | sed 's/`//g; s/:[0-9]*$//' \
      | sort -u)"
    for a in ${anchors}; do
        if git -C "${REPO}" cat-file -e "HEAD:${a}" 2>/dev/null; then
            continue
        fi
        if [ -e "${REPO}/${a}" ]; then
            _note "${base}: '${a}' exists in working tree but not at HEAD"
        else
            _warn "${base}: repo-path anchor '${a}' not found at HEAD"
        fi
    done
done
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test-memory-validate.sh < /dev/null`
Expected: PASS on all anchor assertions AND all Task 1–2 assertions still pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/memory-validate.sh tests/test-memory-validate.sh
git commit -m "feat: memory-validate.sh stale-anchor WARN + working-tree NOTE"
```

---

### Task 4: Full-suite integration + CHANGELOG + design-doc cross-link

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]` section)
- Verify: `tests/run-tests.sh` auto-discovers the new test (no edit needed — confirm)

**Interfaces:**
- Consumes: nothing new.
- Produces: green full suite; changelog entry.

- [ ] **Step 1: Confirm auto-discovery + run the full suite**

Run: `bash tests/run-tests.sh < /dev/null`
Expected: `test-memory-validate.sh` appears in the run and PASSES; total suite pass count increases by 1 file with 0 failures. (No edit to `run-tests.sh` — it globs `test-*.sh`.)

- [ ] **Step 2: Run the script against the REAL memory dir (smoke, non-blocking)**

Run: `bash scripts/memory-validate.sh "$HOME/.claude/projects/-Users-damian-papadopoulos-IdeaProjects-auto-claude-skills/memory" "$(git rev-parse --show-toplevel)"; echo "exit=$?"`
Expected: exit 0 (WARNs/NOTEs are informational). Eyeball that structural ERRORs, if any, are real. Record the output in the commit body if notable. This is a smoke check, not an assertion.

- [ ] **Step 3: Add CHANGELOG entry**

Add under `## [Unreleased]` in `CHANGELOG.md` (create the `### Added` subsection if absent):

```markdown
### Added
- `scripts/memory-validate.sh` — advisory consistency/staleness validator for Claude Code auto-memory directories. Structural defects (missing `metadata.type`, dangling `[[links]]`, index desync) are ERROR (exit 1); stale repo-path anchors (backtick paths absent at repo HEAD) are WARN (exit 0). Mirrors `scripts/knowledge-validate.sh`. Motivated by improvement-miner issue #125 (a stale memory produced a dead proposal).
```

- [ ] **Step 4: Verify no regressions**

Run: `bash tests/run-tests.sh < /dev/null`
Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for memory-validate.sh"
```

---

## Self-Review

**Spec coverage:**
- Shape/signature `<memory-dir> [repo-root]` → Task 1 impl. ✓
- Advisory-first, two-tier exit (ERROR=1, WARN/NOTE=0) → Tasks 1–3; asserted by Fixture F (WARN keeps exit 0). ✓
- Frontmatter type (nested `metadata.type`) → Task 1. ✓
- Dangling `[[links]]` → Task 2. ✓
- Bidirectional index sync (extends knowledge-validate) → Task 2, Fixtures D+E. ✓
- Anchor WARN, HEAD resolution, fenced-block skip, ext allowlist, `:NN` strip, working-tree NOTE → Task 3, Fixtures F–I. ✓
- Cut check 4 (superseded/age) → not built; recorded as revival criterion in design doc. ✓ (nothing to implement)
- Testing (red #125 repro + structural + green no-false-positive) → Tasks 1–3 fixtures. ✓
- run-tests.sh wiring → Task 4 (auto-discovery, verified not edited). ✓
- Not-a-skill (no routing/content gate) → no task needed. ✓

**Placeholder scan:** No TBD/TODO; every code step shows complete code. ✓

**Type/name consistency:** `_meta_type`, `_err`, `_warn`, `_note`, `ERRORS`, `MEM`, `REPO`, `_ANCHOR_EXT` used consistently across Tasks 1–3. Test helper `_mem` defined in Task 1, reused in 2–3. ✓

**Bash-3.2 check:** `for a in ${anchors}` relies on `sort -u` newline output with no spaces in paths (path anchors never contain spaces); no associative arrays, no `mapfile`. `ya?ml` inside the ERE alternation is valid ERE. ✓
