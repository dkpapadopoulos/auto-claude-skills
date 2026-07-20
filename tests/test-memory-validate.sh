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

# give bad_type.md a valid type now so later multi-defect assertions isolate cleanly
_mem bad_type.md "---
name: bad
metadata:
  type: project
---
body"

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
# resolve the dangling link so downstream tasks start from a clean tree
_mem dangling.md "---
name: dangling
metadata:
  type: project
---
no link now"

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

print_summary
