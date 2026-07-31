#!/usr/bin/env bash
# knowledge-validate.sh <dir> — validate a .claude/knowledge bundle. Bash 3.2 compatible.
DIR="${1:?usage: knowledge-validate.sh <dir>}"
[ -d "${DIR}" ] || exit 0
ERRORS=0
_err() { printf '[ERROR] %s\n' "$1" >&2; ERRORS=$((ERRORS+1)); }

_frontmatter_field() {
    awk -v f="$2" 'NR==1 && $0=="---"{infm=1;next} infm && $0=="---"{exit}
        infm && $0 ~ "^"f": "{sub("^"f": ","");print;exit}' "$1"
}

# Collect existing slugs (basename without .md), excluding index.md
SLUGS=""
for f in "${DIR}"/*.md; do
    [ -e "${f}" ] || continue
    base="$(basename "${f}")"; [ "${base}" = "index.md" ] && continue
    slug="${base%.md}"
    SLUGS="${SLUGS} ${slug}"
    # type mandatory
    [ -n "$(_frontmatter_field "${f}" type)" ] || _err "${base}: missing 'type'"
    # source repo-relative path must resolve (skip URLs / PR refs / CLAUDE.md anchors)
    src="$(_frontmatter_field "${f}" source)"
    case "${src}" in
        http://*|https://*|"#"*|PR\#*|"") : ;;
        *:*) p="${src%%:*}"; [ -e "${p}" ] || _err "${base}: source path '${p}' not found" ;;
        *) case "${src}" in */*) [ -e "${src}" ] || _err "${base}: source path '${src}' not found";; esac ;;
    esac
    # dangling [[slug]] links
    for ref in $(grep -oE '\[\[[a-z0-9-]+\]\]' "${f}" | sed 's/\[\[//;s/\]\]//'); do
        [ -e "${DIR}/${ref}.md" ] || _err "${base}: dangling link [[${ref}]]"
    done
done

# index.md ↔ disk: every fact must have an entry the session-start hook will actually
# INJECT. Checking that the slug appears somewhere in index.md is too loose: an entry the
# injector drops (bold-wrapped, indented, numbered) is a fact that is committed, validated,
# and never reaches a single session — silent in both directions.
# So filter index.md through the injector's own predicate FIRST, then look for the slug in
# what survives — i.e. validate against what the consumer actually receives.
# PAIRED: '^- \[' is the injection predicate in hooks/session-start-hook.sh; if that changes,
# change it here too. tests/test-knowledge.sh extracts the pattern from the hook and fails
# on drift, so the two cannot diverge silently.
if [ -e "${DIR}/index.md" ]; then
    INJECTABLE="$(grep -E '^- \[' "${DIR}/index.md" 2>/dev/null)"
    for slug in ${SLUGS}; do
        printf '%s\n' "${INJECTABLE}" | grep -qF "(${slug}.md)" \
            || _err "index.md has no injectable entry for ${slug}.md — needs a '- [Title](${slug}.md) — desc' bullet at line start; run scripts/knowledge-rebuild-index.sh"
    done
fi

[ "${ERRORS}" -eq 0 ] || exit 1
