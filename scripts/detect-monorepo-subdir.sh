#!/usr/bin/env bash
# detect-monorepo-subdir.sh — Detect when Claude was launched above a package
# manifest directory in a monorepo and emit a hint to cd to the DEEPEST one.
#
# Spec: openspec/changes/context-economy-defaults/specs/context-economy/spec.md
#       (Scenario C3: Subdir launch warning fires)
#
# Behavior:
#   - Single find traversal (max depth 4) across all manifest patterns.
#   - Picks the deepest matching subdirectory (per spec wording "deepest
#     relevant subdirectory"), not the lex-first one.
#   - Respects ACSM_QUIET_SUBDIR=1 (no output, exit 0).
#   - Fail-open: any unexpected condition exits 0 silently.
#
# Bash 3.2 compatible. No deps beyond POSIX find/awk/sort.

set -u

if [ "${ACSM_QUIET_SUBDIR:-0}" = "1" ]; then
    exit 0
fi

# Single find call with -name alternation. Cheaper than per-pattern traversals.
# `-mindepth 2` skips the current directory — if the user already launched from
# within a package, nothing to warn about.
ALL_MATCHES="$(find . -mindepth 2 -maxdepth 4 -type f \
    \( -name package.json \
       -o -name pyproject.toml \
       -o -name pom.xml \
       -o -name build.gradle \
       -o -name build.gradle.kts \
       -o -name Cargo.toml \
       -o -name go.mod \) \
    -not -path '*/node_modules/*' \
    -not -path '*/.git/*' \
    -not -path '*/dist/*' \
    -not -path '*/build/*' \
    -not -path '*/target/*' \
    2>/dev/null)"

if [ -z "${ALL_MATCHES}" ]; then
    exit 0
fi

# Pick the deepest match. `awk -F/` counts path segments; `sort -nr` puts the
# highest first; `head -1` selects the deepest. Tie-break is lex order from
# find's natural ordering — acceptable for the spec.
SUBDIR_MATCH="$(printf '%s\n' "${ALL_MATCHES}" \
    | awk -F/ '{print NF, $0}' \
    | sort -nr \
    | head -1 \
    | sed -E 's/^[0-9]+ //')"

if [ -z "${SUBDIR_MATCH}" ]; then
    exit 0
fi

# Strip leading ./ and trailing manifest name to get the package directory.
PKG_DIR="$(dirname "${SUBDIR_MATCH}" | sed 's|^\./||')"

cat <<EOF
[context-economy] Monorepo subdirectory detected: ${PKG_DIR}/
  Launching Claude from inside the deepest relevant package directory shrinks
  auto-discovery scope and reduces context tokens. Consider:
    cd ${PKG_DIR} && claude
  Set ACSM_QUIET_SUBDIR=1 to suppress this hint.
EOF
