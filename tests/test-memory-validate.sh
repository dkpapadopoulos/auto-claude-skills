#!/usr/bin/env bash
# test-memory-validate.sh — scripts/memory-validate.sh.
# Corruption -> ERROR (exit 1); drift & stale anchors -> WARN (exit 0).
# Hermetic: builds a throwaway git repo + memory fixtures.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
. "${SCRIPT_DIR}/test-helpers.sh"
VALIDATE="${PROJECT_ROOT}/scripts/memory-validate.sh"

echo "=== test-memory-validate.sh ==="

# --- hermetic sandbox: a repo-root with committed files, and a memory dir ---
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

_mem() { printf '%s\n' "$2" > "${MEM}/$1"; }
# reset the memory dir to a known-clean baseline (no ERRORs, no WARNs)
_reset_mem() {
    rm -f "${MEM}"/*.md
    # index lists exactly the baseline files below
    _mem MEMORY.md "# Memory Index
- [Good](good.md) — ok
- [Top](toplevel.md) — ok"
    # nested metadata.type variant, name: good-slug
    _mem good.md "---
name: good-slug
metadata:
  type: feedback
---
body"
    # top-level type variant, name: top-slug
    _mem toplevel.md "---
name: top-slug
type: project
---
body"
}

# ---- ERROR: missing frontmatter type (neither top-level nor nested) ----
_reset_mem
_mem bad_type.md "---
name: bad
foo: bar
---
body"
printf '%s\n' "- [Bad](bad_type.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "bad_type.md"; then
    _record_pass "missing type -> ERROR exit 1"
else
    _record_fail "missing type -> ERROR exit 1" "rc=${rc} out=${out}"
fi

# ---- both type schema variants accepted (baseline is clean) ----
_reset_mem
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && [ -z "${out}" ]; then
    _record_pass "top-level AND nested type both accepted; clean baseline silent"
else
    _record_fail "top-level AND nested type both accepted" "rc=${rc} out=${out}"
fi

# ---- WARN: dangling [[name]] link (no file has that name:) exit stays 0 ----
_reset_mem
_mem linker.md "---
name: linker-slug
metadata:
  type: project
---
see [[no-such-name]] and [[good-slug]]"
printf '%s\n' "- [Linker](linker.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] \
   && printf '%s' "${out}" | grep -qF "no-such-name" \
   && ! printf '%s' "${out}" | grep -qF "good-slug"; then
    _record_pass "dangling [[link]] -> WARN (name-slug resolved), resolvable link silent"
else
    _record_fail "dangling [[link]] -> WARN, resolvable link silent" "rc=${rc} out=${out}"
fi

# ---- WARN: memory file absent from MEMORY.md (forward index drift) exit 0 ----
_reset_mem
_mem unindexed.md "---
name: unindexed-slug
metadata:
  type: reference
---
body"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -qF "unindexed.md"; then
    _record_pass "file missing from index -> WARN, exit 0"
else
    _record_fail "file missing from index -> WARN, exit 0" "rc=${rc} out=${out}"
fi

# ---- ERROR: index links a file that does not exist (reverse) ----
_reset_mem
printf '%s\n' "- [Ghost](ghost.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 1 ] && printf '%s' "${out}" | grep -qF "ghost.md"; then
    _record_pass "index entry for missing file -> ERROR exit 1"
else
    _record_fail "index entry for missing file -> ERROR exit 1" "rc=${rc} out=${out}"
fi

# ---- WARN: anchor to a path absent at HEAD (reproduces #125), exit 0 ----
_reset_mem
_mem stale_anchor.md "---
name: stale-slug
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

# ---- anchor to a live path (with :line) -> no warning ----
_reset_mem
_mem live_anchor.md "---
name: live-slug
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

# ---- bare basename of a NESTED HEAD file -> no warning (basename resolution) ----
_reset_mem
_mem bare_anchor.md "---
name: bare-slug
metadata:
  type: project
---
The guard \`openspec-guard.sh\` (committed under hooks/) is fine to cite by name."
printf '%s\n' "- [Bare](bare_anchor.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && ! printf '%s' "${out}" | grep -qF "openspec-guard.sh"; then
    _record_pass "bare basename of a nested HEAD file -> no warning"
else
    _record_fail "bare basename of a nested HEAD file -> no warning" "rc=${rc} out=${out}"
fi

# ---- bare basename absent everywhere at HEAD -> WARN ----
_reset_mem
_mem bare_stale.md "---
name: bare-stale-slug
metadata:
  type: project
---
Refers to \`totally-gone.sh\` which exists nowhere at HEAD."
printf '%s\n' "- [BareStale](bare_stale.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && printf '%s' "${out}" | grep -qF "totally-gone.sh"; then
    _record_pass "bare basename absent at HEAD -> WARN"
else
    _record_fail "bare basename absent at HEAD -> WARN" "rc=${rc} out=${out}"
fi

# ---- absolute path to a file whose basename exists at HEAD -> no warning ----
_reset_mem
_mem abs_anchor.md "---
name: abs-slug
metadata:
  type: project
---
Absolute ref \`/Users/somebody/repo/config.json\` resolves by basename."
printf '%s\n' "- [Abs](abs_anchor.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && ! printf '%s' "${out}" | grep -qF "config.json"; then
    _record_pass "absolute path w/ HEAD basename -> no warning"
else
    _record_fail "absolute path w/ HEAD basename -> no warning" "rc=${rc} out=${out}"
fi

# ---- anchor inside a fenced code block -> ignored ----
_reset_mem
_mem fenced.md "---
name: fenced-slug
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

# ---- path exists in working tree but not at HEAD -> NOTE, not WARN ----
_reset_mem
echo x > "${REPO}/uncommitted.md"   # on disk, never committed
_mem wt_only.md "---
name: wt-slug
metadata:
  type: project
---
Draft at \`uncommitted.md\` here."
printf '%s\n' "- [WT](wt_only.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] \
   && printf '%s' "${out}" | grep -qF "[NOTE]" \
   && printf '%s' "${out}" | grep -qF "uncommitted.md" \
   && ! printf '%s' "${out}" | grep -qF "[WARN]"; then
    _record_pass "working-tree-only path -> NOTE not WARN"
else
    _record_fail "working-tree-only path -> NOTE not WARN" "rc=${rc} out=${out}"
fi

# ---- review #1: prose parenthetical in MEMORY.md is NOT a markdown link -> no ERROR ----
_reset_mem
printf '%s\n' "Note: supersedes an old draft (nonexistent-draft.md) from before." >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && ! printf '%s' "${out}" | grep -qF "nonexistent-draft.md"; then
    _record_pass "prose parenthetical (foo.md) not treated as index link"
else
    _record_fail "prose parenthetical (foo.md) not treated as index link" "rc=${rc} out=${out}"
fi

# ---- review #2: absolute-path anchor to a working-tree-only file -> NOTE not WARN ----
_reset_mem
mkdir -p "${SBOX}/ext"; echo x > "${SBOX}/ext/wt-abs.md"   # on disk, not in REPO, not at HEAD
_mem abswt.md "---
name: abswt-slug
metadata:
  type: project
---
See \`${SBOX}/ext/wt-abs.md\` on disk."
printf '%s\n' "- [AbsWT](abswt.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] \
   && printf '%s' "${out}" | grep -qF "[NOTE]" \
   && printf '%s' "${out}" | grep -qF "wt-abs.md" \
   && ! printf '%s' "${out}" | grep -qF "[WARN]"; then
    _record_pass "absolute path present on disk -> NOTE not WARN"
else
    _record_fail "absolute path present on disk -> NOTE not WARN" "rc=${rc} out=${out}"
fi

# ---- review #3: prefix-stripped hyphenated link convention resolves ----
_reset_mem
_mem feedback_widget_thing.md "---
name: Widget Thing Human Name
metadata:
  type: feedback
---
body"
printf '%s\n' "- [Widget](feedback_widget_thing.md) — x" >> "${MEM}/MEMORY.md"
_mem linker2.md "---
name: linker2-slug
metadata:
  type: project
---
see [[widget-thing]]"
printf '%s\n' "- [Linker2](linker2.md) — x" >> "${MEM}/MEMORY.md"
out="$("${VALIDATE}" "${MEM}" "${REPO}" 2>&1)"; rc=$?
if [ "${rc}" -eq 0 ] && ! printf '%s' "${out}" | grep -qF "widget-thing"; then
    _record_pass "prefix-stripped hyphenated [[link]] resolves (no WARN)"
else
    _record_fail "prefix-stripped hyphenated [[link]] resolves (no WARN)" "rc=${rc} out=${out}"
fi

print_summary
