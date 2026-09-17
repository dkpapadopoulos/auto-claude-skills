#!/bin/bash
# token-lint.sh — require token REFERENCES in the properties that carry visual meaning.
#
# WHY REFERENCES, NOT VALUES. A raw literal is a violation even when its value equals a
# token's value, because a literal does not follow a theme change: `color: #1b1a17` looks
# right today and stays black when the page switches to dark. Checking that values come
# from a finite set would pass that line. So the property enforced here is "this
# declaration points at a role", never "this value is on the list".
#
# DECLARED SCOPE — this is a line-oriented shell scanner, not a CSS parser, and it does
# not claim general enforcement:
#   Properties covered : color, background-color, border-color, outline-color, fill,
#                        stroke, background, border, outline, font-size, font-family
#   Files covered      : the files you name; with no arguments, *.css under the current
#                        directory, excluding node_modules/, dist/, build/, .git/
#   Never scanned      : tokens.css (it is where the literals are defined)
#   Ignored constructs : /* comments */ (quote-aware: a "/*" inside a CSS string is
#                        text, not a comment), at-rule lines (@media, @supports,
#                        @import, @font-face), url(...) references, and the keywords
#                        inherit/initial/unset/revert/currentColor/transparent/none/
#                        auto and a bare 0 — all matched case-insensitively
#   Not covered        : inline style attributes, CSS-in-JS, <svg> presentation
#                        attributes, shorthand sub-values inside calc(), anything in a
#                        file you did not name
#
# NEVER REPORTS CLEAN WHEN IT COULD NOT LOOK. An unreadable file, a failed directory
# walk, or any other incomplete scan exits 3 and says so — a checker whose failure mode
# is "clean" is worse than no checker, because CI passes on it.
#
# Exit: 0 clean, 1 violations found, 2 usage error, 3 scan incomplete (do not trust).
set -u

_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"

usage() {
    # Print the header block itself — every comment line after the shebang, stopping at
    # the first line that is not one. A hardcoded line range silently desyncs the moment
    # the header changes length, which is exactly how --help came to print `set -u` and
    # the top of this function as though they were documentation.
    awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' \
        "${_SELF_DIR}/$(basename "$0")"
    printf '\nusage: token-lint.sh [--help] [file.css ...]\n'
}

case "${1:-}" in
    --help|-h) usage; exit 0 ;;
esac

_WORK="$(mktemp -d "${TMPDIR:-/tmp}/token-lint.XXXXXX")" || {
    printf 'token-lint: cannot create a work directory — scan NOT run\n' >&2; exit 3; }
trap 'rm -rf "${_WORK}"' EXIT
_LIST="${_WORK}/files"   # NUL-separated: filenames may contain spaces or newlines
_LINES="${_WORK}/lines"

: > "${_LIST}" || { printf 'token-lint: cannot write %s — scan NOT run\n' "${_LIST}" >&2; exit 3; }

if [ "$#" -gt 0 ]; then
    for _f in "$@"; do
        case "${_f}" in -*) printf 'token-lint: unknown option %s\n' "${_f}" >&2; exit 2 ;; esac
        [ -f "${_f}" ] || { printf 'token-lint: no such file: %s\n' "${_f}" >&2; exit 2 ;}
        printf '%s\0' "${_f}" >> "${_LIST}"
    done
else
    # A failed walk must not read as an empty tree: keep find's status.
    if ! find . -type f -name '*.css' \
        ! -path '*/node_modules/*' ! -path '*/dist/*' ! -path '*/build/*' ! -path '*/.git/*' \
        -print0 >> "${_LIST}" 2>"${_WORK}/finderr"; then
        printf 'token-lint: the directory walk failed — scan INCOMPLETE, results not trustworthy\n' >&2
        sed 's/^/token-lint:   /' "${_WORK}/finderr" >&2
        exit 3
    fi
fi

if [ ! -s "${_LIST}" ]; then
    printf 'token-lint: no CSS files to scan\n'
    exit 0
fi

# Strip /* */ comments across lines while keeping line numbers, then emit "N<TAB>text".
_strip_comments() {
    awk '
    { line = $0; out = ""; i = 1; n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        if (incomment) {
          if (substr(line, i, 2) == "*/") { incomment = 0; i += 2 } else { i++ }
        } else if (instring) {
          # A "/*" inside a string is text. Without this the scanner treated
          # `content: "/*"` as opening a comment and silently swallowed the rest of
          # the FILE — an unbounded false negative that reports clean.
          if (c == "\\") { out = out substr(line, i, 2); i += 2 }
          else { out = out c; if (c == instring) instring = ""; i++ }
        } else {
          if (substr(line, i, 2) == "/*") { incomment = 1; i += 2 }
          else { if (c == "\"" || c == "\x27") instring = c; out = out c; i++ }
        }
      }
      # A string does not span lines in CSS; leaving instring set would mask the rest
      # of the file exactly like the bug above.
      instring = ""
      printf "%d\t%s\n", NR, out }' "$1"
}

# One covered declaration. Prints a diagnostic and returns 1 when it is a violation.
_check_decl() {
    _file="$1"; _n="$2"; _decl="$3"
    case "${_decl}" in *:*) ;; *) return 0 ;; esac
    _prop="${_decl%%:*}"
    _val="${_decl#*:}"
    # NOTE: BSD sed does not read \t inside a bracket expression — `[ \t]` is the set
    # {space, backslash, t}, which silently ate the t's in "transparent". Trim with
    # [:space:] classes only.
    _prop="$(printf '%s' "${_prop}" | tr -d '[:space:]')"
    _val="$(printf '%s' "${_val}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "${_val}" ] || return 0

    case "${_prop}" in
        color|background-color|border-color|outline-color|fill|stroke|background|border|outline)
            _class="TL-1"; _what="colour" ;;
        font-size|font-family)
            _class="TL-2"; _what="typography" ;;
        *) return 0 ;;
    esac

    case "${_val}" in *var\(--*) return 0 ;; esac
    # url(...) is an asset reference, not a colour: `background: url(/img/hero.png)` is
    # not a literal to tokenise. Strip those out and judge what is left, so
    # `background: url(x) #fff` still fires on the #fff.
    _bare="$(printf '%s' "${_val}" | sed 's/url([^)]*)//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "${_bare}" ] || return 0
    # Keywords are case-insensitive in CSS — `currentcolor` is the spec's own spelling.
    case "$(printf '%s' "${_bare}" | tr '[:upper:]' '[:lower:]')" in
        inherit|initial|unset|revert|currentcolor|transparent|none|auto|0) return 0 ;;
    esac

    printf '%s:%s: %s %s literal in `%s: %s` — reference a token, e.g. %s: var(--…)\n' \
        "${_file}" "${_n}" "${_class}" "${_what}" "${_prop}" "${_val}" "${_prop}"
    return 1
}

_violations=0
_unscannable=0

# Read from a file, not a pipe: the counters must survive the loop (a pipeline would run
# it in a subshell and every violation would be forgotten at the `done`).
while IFS= read -r -d '' _file; do
    [ -n "${_file}" ] || continue
    case "$(basename "${_file}")" in tokens.css) continue ;; esac

    if [ ! -r "${_file}" ]; then
        printf 'token-lint: cannot read %s — scan INCOMPLETE\n' "${_file}" >&2
        _unscannable=$((_unscannable + 1))
        continue
    fi
    if ! _strip_comments "${_file}" > "${_LINES}" 2>"${_WORK}/awkerr"; then
        printf 'token-lint: failed to read %s — scan INCOMPLETE\n' "${_file}" >&2
        sed 's/^/token-lint:   /' "${_WORK}/awkerr" >&2
        _unscannable=$((_unscannable + 1))
        continue
    fi

    while IFS="$(printf '\t')" read -r _n _text; do
        case "${_text}" in
            *@media*|*@supports*|*@import*|*@font-face*) continue ;;
        esac
        # Several declarations may share a line — minified CSS puts whole rules on one.
        # Braces are boundaries too, not just semicolons: `…;font-size:12px}.b{border:…`
        # ends one declaration and starts a new rule, and treating `}` as ordinary text
        # let a declaration after a rule boundary escape the scan entirely. Selectors
        # then arrive as their own segments; a pseudo-class like `a:hover` parses to the
        # property `a`, which is not covered, so it is skipped.
        _rest="${_text//\{/;}"
        _rest="${_rest//\}/;}"
        while [ -n "${_rest}" ]; do
            case "${_rest}" in
                *";"*) _one="${_rest%%;*}"; _rest="${_rest#*;}" ;;
                *)     _one="${_rest}";     _rest="" ;;
            esac
            _check_decl "${_file}" "${_n}" "${_one}" || _violations=$((_violations + 1))
        done
    done < "${_LINES}"
done < "${_LIST}"

if [ "${_unscannable}" -gt 0 ]; then
    printf '\ntoken-lint: %s file(s) could not be scanned; %s violation(s) in what was read. INCOMPLETE — do not read this as clean.\n' \
        "${_unscannable}" "${_violations}" >&2
    exit 3
fi
if [ "${_violations}" -gt 0 ]; then
    printf '\ntoken-lint: %s violation(s). Scope: see --help.\n' "${_violations}" >&2
    exit 1
fi
printf 'token-lint: clean (scope: see --help)\n'
exit 0
