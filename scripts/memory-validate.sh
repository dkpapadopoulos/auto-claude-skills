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
    # dangling [[slug]] links
    for ref in $(grep -oE '\[\[[a-z0-9_-]+\]\]' "${f}" | sed 's/\[\[//;s/\]\]//' | sort -u); do
        [ -e "${MEM}/${ref}.md" ] || _err "${base}: dangling link [[${ref}]]"
    done
done

# bidirectional index sync
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

[ "${ERRORS}" -eq 0 ] || exit 1
exit 0
