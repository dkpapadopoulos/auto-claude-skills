#!/usr/bin/env bash
# memory-validate.sh <memory-dir> [repo-root] — validate a Claude Code auto-memory
# directory. Corruption -> ERROR (exit 1). Drift & stale anchors -> WARN (exit 0).
# Bash 3.2 compatible. Advisory: never mutates memory. See
# docs/plans/2026-07-20-memory-validate-design.md.
#
# Tiering (calibrated against the real store, 2026-07-20):
#   ERROR  missing/invalid frontmatter type; MEMORY.md links a nonexistent file
#   WARN   dangling [[name]] link (unresolved against any file's `name:` slug);
#          memory file absent from MEMORY.md; repo-path anchor absent at HEAD
#   NOTE   repo-path anchor present in the working tree but not at HEAD
# Auto-memory `[[name]]` links reference the frontmatter `name:` slug (NOT the
# filename) and are allowed to point at not-yet-written memories, so a dangling
# link is drift (WARN), never corruption.
MEM="${1:?usage: memory-validate.sh <memory-dir> [repo-root]}"
REPO="${2:-$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "$PWD")}"
[ -d "${MEM}" ] || exit 0
ERRORS=0
_err()  { printf '[ERROR] %s\n' "$1" >&2; ERRORS=$((ERRORS+1)); }
_warn() { printf '[WARN] %s\n'  "$1" >&2; }
_note() { printf '[NOTE] %s\n'  "$1" >&2; }

# echo a frontmatter field's value: top-level `field: value`, or nested one level
# under `metadata:` (auto-memory has both schema variants). Prefers nested.
_fm_field() {
    awk -v f="$2" '
        NR==1 && $0=="---"{infm=1; next}
        infm && $0=="---"{exit}
        infm && $0 ~ ("^"f":[[:space:]]")            {top=$0; sub("^"f":[[:space:]]*","",top)}
        infm && $0 ~ /^metadata:[[:space:]]*$/        {inmeta=1; next}
        infm && inmeta && $0 ~ ("^[[:space:]]+"f":[[:space:]]"){
            nest=$0; sub("^[[:space:]]+"f":[[:space:]]*","",nest)}
        infm && inmeta && $0 ~ /^[^[:space:]]/        {inmeta=0}
        END{ if (nest!="") print nest; else print top }
    ' "$1"
}

# Resolution set for [[name]] links. The store links by three interchangeable
# conventions: the frontmatter `name:` slug, the bare filename (underscores), and
# the filename with underscores->hyphens. A link resolving to ANY is not dangling.
# (Auto-memory also allows links to not-yet-written memories, so misses are WARN.)
LINK_TARGETS="$(for f in "${MEM}"/*.md; do
    [ -e "${f}" ] || continue
    b="$(basename "${f}")"; [ "${b}" = "MEMORY.md" ] && continue
    stem="${b%.md}"                               # e.g. feedback_match_scope_to_fix_size
    nopfx="${stem#feedback_}"; nopfx="${nopfx#project_}"; nopfx="${nopfx#reference_}"
    printf '%s\n' "${stem}"                       # filename slug (underscores)
    printf '%s\n' "${stem}" | tr '_' '-'          # filename slug (hyphens)
    printf '%s\n' "${nopfx}"                      # prefix-stripped (underscores)
    printf '%s\n' "${nopfx}" | tr '_' '-'         # prefix-stripped (hyphens)
    _fm_field "${f}" name                         # frontmatter name: value
done | sort -u)"

VALID_TYPES=" feedback project reference user "
for f in "${MEM}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
    # frontmatter type (ERROR — schema requires it)
    t="$(_fm_field "${f}" type)"
    case "${VALID_TYPES}" in
        *" ${t} "*) : ;;
        *) _err "${base}: missing or invalid frontmatter type ('${t}')" ;;
    esac
    # dangling [[name]] links (WARN — resolved against the multi-convention set)
    for ref in $(grep -oE '\[\[[a-z0-9_-]+\]\]' "${f}" | sed 's/\[\[//;s/\]\]//' | sort -u); do
        printf '%s\n' "${LINK_TARGETS}" | grep -qxF "${ref}" \
            || _warn "${base}: dangling link [[${ref}]] (matches no memory by name, filename, or slug)"
    done
done

# index sync
if [ -e "${MEM}/MEMORY.md" ]; then
    # forward (WARN): every memory file appears in the index
    for f in "${MEM}"/*.md; do
        [ -e "${f}" ] || continue
        base="$(basename "${f}")"; [ "${base}" = "MEMORY.md" ] && continue
        grep -qF "(${base})" "${MEM}/MEMORY.md" || _warn "MEMORY.md missing entry for ${base}"
    done
    # reverse (ERROR): every markdown-link (<file>.md) index target exists. Require
    # the `](` link syntax so a bare parenthetical in prose ("supersedes (x.md)")
    # is not mistaken for an index link and does not false-trip exit 1.
    for link in $(grep -oE '\]\([a-z0-9_-]+\.md\)' "${MEM}/MEMORY.md" | sed 's/^](//;s/)$//' | sort -u); do
        [ -e "${MEM}/${link}" ] || _err "MEMORY.md links missing file (${link})"
    done
fi

# Stale repo-path anchor scan (WARN-only; never affects exit code).
# Anchors are frequently written as a BARE basename (`openspec-guard.sh`) rather
# than a repo-relative path (`hooks/openspec-guard.sh`); resolving a basename only
# at the repo root false-flags every nested file. So: a path anchor (contains `/`)
# resolves by exact HEAD path; a bare basename resolves if ANY HEAD file has that
# basename. Precision over recall — a same-named file elsewhere suppresses the WARN.
_ANCHOR_EXT='sh|md|json|ya?ml|txt|ts|js|py'
HEADFILES="$(git -C "${REPO}" ls-tree -r --name-only HEAD 2>/dev/null)"
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
    # Unquoted ${anchors} word-split is INTENTIONAL and safe: the grep ERE above
    # restricts anchors to [A-Za-z0-9_./-] (no spaces, no glob metachars). Do NOT
    # "fix" to "${anchors}" — that would iterate once over the whole newline blob.
    for a in ${anchors}; do
        # cross-memory-file reference (points at a sibling memory .md, not a repo
        # path) — out of scope for repo-staleness; the [[link]] check owns those.
        [ -e "${MEM}/$(basename "${a}")" ] && continue
        case "${a}" in
            /*)  # absolute path (or /tmp scratch): not repo-relative — resolve by basename only
                printf '%s\n' "${HEADFILES}" | awk -F/ -v b="$(basename "${a}")" '$NF==b{hit=1} END{exit !hit}' && continue ;;
            */*) # path anchor: exact OR suffix match at HEAD (memories cite partial paths)
                printf '%s\n' "${HEADFILES}" | grep -qxF "${a}" && continue
                printf '%s\n' "${HEADFILES}" | grep -qF "/${a}" && continue ;;
            *)   # bare basename: match any HEAD file's basename
                printf '%s\n' "${HEADFILES}" | awk -F/ -v b="${a}" '$NF==b{hit=1} END{exit !hit}' && continue ;;
        esac
        # working-tree fallback: an absolute anchor is checked as-is; a repo-relative
        # one is resolved under REPO (joining REPO to an absolute path double-roots).
        case "${a}" in /*) wt="${a}" ;; *) wt="${REPO}/${a}" ;; esac
        if [ -e "${wt}" ]; then
            _note "${base}: '${a}' exists in working tree but not at HEAD"
        else
            _warn "${base}: repo-path anchor '${a}' not found at HEAD"
        fi
    done
done

[ "${ERRORS}" -eq 0 ] || exit 1
exit 0
