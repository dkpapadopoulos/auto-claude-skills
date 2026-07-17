#!/bin/bash
# scope-conformance.sh — deterministic declared-vs-actual file-scope verdict.
# Adapted from worklease's `conformance` primitive (post-hoc respected/violation
# partition); Node dependency rejected, bash-3.2 reimplementation.
#
# Usage: scope-conformance.sh <plan-file> [<base-ref>]
# Exit:  0 = clean, 1 = violation (advisory — caller surfaces, never blocks),
#        2 = unverified (missing/unparseable manifest or unresolvable base).
#
# Manifest = every "- Create:|Modify:|Test:|Delete:|Allow: `path`" line in the
# plan (superpowers writing-plans Files-block format), line ranges stripped.
# Matching is exact path or bash case-glob; case-glob `*` crosses `/`, which is
# deliberately conservative-inclusive. Meta artifacts every chain touches
# (docs/plans/*, openspec/*, CHANGELOG.md) are always covered.

set -u

PLAN="${1:-}"
BASE="${2:-}"

say() { printf '%s\n' "$*"; }

if [ -z "$PLAN" ] || [ ! -r "$PLAN" ]; then
    say "scope-conformance: unverified — no readable plan file (${PLAN:-<none>})"
    exit 2
fi

if [ -z "$BASE" ]; then
    for cand in origin/main main origin/master master; do
        if git rev-parse --verify --quiet "$cand" >/dev/null 2>&1; then
            BASE="$(git merge-base "$cand" HEAD 2>/dev/null)" && [ -n "$BASE" ] && break
        fi
    done
fi
if [ -z "$BASE" ] || ! git rev-parse --verify --quiet "$BASE" >/dev/null 2>&1; then
    say "scope-conformance: unverified — cannot resolve base ref"
    exit 2
fi

# Normalize an explicit base to its merge-base with HEAD: identity when the
# base is already an ancestor, and on a diverged mainline this stops mainline
# churn from being misattributed to the branch (false violations).
BASE="$(git merge-base "$BASE" HEAD 2>/dev/null)"
if [ -z "$BASE" ]; then
    say "scope-conformance: unverified — cannot resolve base ref"
    exit 2
fi

# Manifest entries: backticked payload of Create/Modify/Test/Delete/Allow
# lines, with a trailing :N or :N-M line-range suffix stripped. A trailing-/
# directory entry becomes dir/* so it covers contained files.
MANIFEST="$(sed -n -E 's/^[[:space:]]*-[[:space:]]*(Create|Modify|Test|Delete|Allow):[[:space:]]*`([^`]+)`.*/\2/p' "$PLAN" \
    | sed -E 's/:[0-9]+(-[0-9]+)?$//' \
    | sed -E 's|/$|/*|')"

if [ -z "$MANIFEST" ]; then
    say "scope-conformance: unverified — no Files/Allow entries parseable in ${PLAN}"
    exit 2
fi

# Changed set: committed + uncommitted vs base (includes deletes), + untracked.
# quotePath off so non-ASCII filenames come out raw, not octal-escape-quoted.
CHANGED="$( { git -c core.quotePath=false diff --name-only "$BASE" -- 2>/dev/null;
              git -c core.quotePath=false ls-files --others --exclude-standard 2>/dev/null; } | sort -u )"

if [ -z "$CHANGED" ]; then
    say "scope-conformance: clean — no changes vs base ${BASE}"
    exit 0
fi

META_ALLOW="docs/plans/* openspec/* CHANGELOG.md"

# The plan file itself is always in-scope: it IS the manifest artifact of the
# workflow being checked (strip a leading ./ to match git's repo-relative paths).
PLAN_REL="${PLAN#./}"

VIOLATIONS=""
while IFS= read -r f; do
    [ -n "$f" ] || continue
    covered=0
    [ "$f" = "$PLAN_REL" ] && covered=1
    for pat in $META_ALLOW; do
        case "$f" in $pat) covered=1 ;; esac
    done
    if [ "$covered" -eq 0 ]; then
        while IFS= read -r m; do
            [ -n "$m" ] || continue
            # Pattern deliberately UNQUOTED: quoting would disable glob
            # semantics; a glob-free path still matches itself literally.
            case "$f" in
                $m) covered=1; break ;;
            esac
        done <<MANIFEST_EOF
$MANIFEST
MANIFEST_EOF
    fi
    if [ "$covered" -eq 0 ]; then
        VIOLATIONS="${VIOLATIONS}${f}
"
    fi
done <<CHANGED_EOF
$CHANGED
CHANGED_EOF

if [ -n "$VIOLATIONS" ]; then
    say "scope-conformance: VIOLATION — files changed outside declared scope (advisory):"
    printf '%s' "$VIOLATIONS" | sed 's/^/  - /'
    say "manifest: ${PLAN} | base: ${BASE}"
    exit 1
fi

say "scope-conformance: clean — all changed files within declared scope (base ${BASE})"
exit 0
