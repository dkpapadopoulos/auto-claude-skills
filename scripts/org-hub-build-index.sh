#!/bin/bash
# org-hub-build-index.sh — deterministic scoped index builder for the org-hub connector.
# Invoked by /setup onboarding (model-guided flow, deterministic emitter).
# Usage: org-hub-build-index.sh --hub <clone-path> --descriptor <descriptor-json>
# Reads scope/context_roots from the descriptor; writes index to its index_path
# (relative to the descriptor's directory parent repo); records hub HEAD sha.
# Descriptor also supports optional review_lens_allowlist: [{path, sha256}] — consumed by
# scripts/org-hub-review-lens.sh (REVIEW-phase hash-pinned body loading), not by this builder.
# Bash 3.2. Exits non-zero on hard errors (this is a CLI, not a fail-open hook).

HUB=""; DESC=""
while [ $# -gt 0 ]; do
    case "$1" in
        --hub) HUB="$2"; shift 2 ;;
        --descriptor) DESC="$2"; shift 2 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done
[ -n "${HUB}" ] && [ -d "${HUB}" ] || { echo "missing/invalid --hub" >&2; exit 2; }
[ -n "${DESC}" ] && [ -f "${DESC}" ] || { echo "missing --descriptor" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "jq required" >&2; exit 2; }
jq empty "${DESC}" 2>/dev/null || { echo "descriptor is not valid JSON" >&2; exit 2; }

HUB="$(cd "${HUB}" && pwd -P)"   # canonicalize hub root for escape checks
REPO_DIR="$(cd "$(dirname "${DESC}")/.." && pwd)"
IDX_REL="$(jq -r '.index_path // ".claude/org-hub-index.md"' "${DESC}")"
# Path-traversal guard: a ".." component in index_path would make this CLI write
# outside the repo (mkdir -p + mv below). Component-exact slash-wrapped match.
case "/${IDX_REL}/" in */../*) echo "index_path must not contain .. components: ${IDX_REL}" >&2; exit 2 ;; esac
OUT="${REPO_DIR}/${IDX_REL}"
# boolean-preserving read: `// true` would coerce an explicit false back to true
SCOPE_ORG="$(jq -r 'if .scope.org == false then "false" else "true" end' "${DESC}")"
TRIBES="$(jq -r '(.scope.tribes // []) | join(" ")' "${DESC}")"
ROOTS="$(jq -r '(.context_roots // ["context/"]) | join(" ")' "${DESC}")"

# days_since <YYYY-MM-DD> — echoes day count or "" on parse failure (both platforms)
days_since() {
    local then_epoch=""
    then_epoch="$(date -j -f "%Y-%m-%d" "$1" +%s 2>/dev/null)" || \
        then_epoch="$(date -d "$1" +%s 2>/dev/null)" || true
    [ -n "${then_epoch}" ] && [[ "${then_epoch}" =~ ^[0-9]+$ ]] || { echo ""; return 0; }
    local now; now="$(date +%s)"
    echo $(( (now - then_epoch) / 86400 ))
}

TMP_OUT="$(mktemp)"
for root in ${ROOTS}; do
    root_abs="${HUB}/${root%/}"
    [ -d "${root_abs}" ] || continue
    # -P: do not follow symlinks; then verify physical path stays under HUB
    find -P "${root_abs}" -type f -name "*.md" 2>/dev/null | while IFS= read -r f; do
        fdir="$(cd "$(dirname "${f}")" 2>/dev/null && pwd -P)" || continue
        case "${fdir}/" in "${HUB}/"*) : ;; *) continue ;; esac   # escape guard
        rel="${f#"${HUB}"/}"
        # scope filter: org/** iff scope.org; tribes/<t>/** iff t in scope.tribes
        keep=0
        case "${rel}" in
            */org/*|*/org.md) [ "${SCOPE_ORG}" = "true" ] && keep=1 ;;
            */tribes/*)
                seg="${rel#*tribes/}"; tribe="${seg%%/*}"
                for t in ${TRIBES}; do [ "${t}" = "${tribe}" ] && keep=1; done ;;
            *) [ "${SCOPE_ORG}" = "true" ] && keep=1 ;;
        esac
        [ "${keep}" -eq 1 ] || continue
        # frontmatter fields (first 20 lines, tolerant)
        head_block="$(head -20 "${f}" 2>/dev/null)"
        ftype="$(printf '%s\n' "${head_block}" | grep -E '^type:' | head -1 | sed 's/^type:[[:space:]]*//')"
        title="$(printf '%s\n' "${head_block}" | grep -E '^title:' | head -1 | sed 's/^title:[[:space:]]*//')"
        [ -n "${title}" ] || title="$(basename "${f}" .md)"
        [ -n "${ftype}" ] || continue     # untyped files (e.g. glossary) are descriptor-listed, not indexed
        scope_label="org"
        case "${rel}" in */tribes/*) seg="${rel#*tribes/}"; scope_label="tribes/${seg%%/*}" ;; esac
        marker=""
        lr="$(printf '%s\n' "${head_block}" | grep -E '^last_reviewed:' | head -1 | sed 's/^last_reviewed:[[:space:]]*//')"
        cad="$(printf '%s\n' "${head_block}" | grep -E '^review_cadence:' | head -1 | sed 's/^review_cadence:[[:space:]]*//')"
        if [ -n "${lr}" ] && [[ "${cad}" =~ ^[0-9]+d$ ]]; then
            days="$(days_since "${lr}")"
            cadn="${cad%d}"
            if [ -n "${days}" ] && [ "${days}" -gt "${cadn}" ]; then marker=" (overdue)"; fi
        fi
        printf -- '- [%s](%s) — scope:%s type:%s%s\n' "${title}" "${rel}" "${scope_label}" "${ftype}" "${marker}"
    done
done | sort > "${TMP_OUT}"

mkdir -p "$(dirname "${OUT}")"
mv "${TMP_OUT}" "${OUT}"
HEAD_SHA="$(git -C "${HUB}" log -1 --format=%H 2>/dev/null || echo "")"
TMP_DESC="$(mktemp)"
jq --arg sha "${HEAD_SHA}" '.index_built_at_sha = $sha' "${DESC}" > "${TMP_DESC}" && mv "${TMP_DESC}" "${DESC}"
echo "org-hub index written: ${OUT} ($(wc -l < "${OUT}" | tr -d ' ') entries, hub HEAD ${HEAD_SHA})"
