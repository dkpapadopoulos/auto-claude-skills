#!/bin/bash
# token-lint.sh — require token REFERENCES in the properties that carry visual meaning.
#
# WHY REFERENCES, NOT VALUES. A raw literal is a violation even when its value equals a
# token's value, because a literal does not follow a theme change: `color: #1b1a17` looks
# right today and stays black when the page switches to dark. Checking that values come
# from a finite set would pass that line. So the property enforced here is "this
# declaration points at a role", never "this value is on the list".
#
# DECLARED SCOPE — this reads declarations, not lines, but it is still a shell scanner
# and not a CSS parser, and it does not claim general enforcement:
#   Properties covered : color, background-color, border-color, outline-color, fill,
#                        stroke, background, border, outline, font-size, font-family
#   Files covered      : the files you name; with no arguments, *.css under the current
#                        directory, excluding node_modules/, dist/, build/, .git/
#   Never scanned      : tokens.css (it is where the literals are defined)
#   Ignored constructs : /* comments */ (quote-aware: a "/*" inside a CSS string is
#                        text, not a comment), at-rule PRELUDES (@media, @supports,
#                        @import) and @font-face BODIES, url(...) references, the keywords
#                        inherit/initial/unset/revert/currentColor/transparent/none/
#                        auto and a bare 0 — all matched case-insensitively
#   Shorthands         : background/border/outline fire only on a COLOUR-SHAPED value
#                        (#hex, rgb()/hsl()/lab()/lch()/color(), or a common colour
#                        name) — they legitimately carry `no-repeat`, `1px solid`,
#                        `center / cover`, and accusing those makes the lint unusable
#   Not covered        : inline style attributes, CSS-in-JS, <svg> presentation
#                        attributes, sub-values inside calc(), colour names outside the
#                        common list, anything in a file you did not name
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

# Emit one DECLARATION per output record as "N<TAB>text", N being the line the
# declaration started on.
#
# Declaration-oriented, not line-oriented, and that distinction is the whole design:
# CSS declarations do not respect line boundaries in either direction. A minified file
# puts a hundred of them on one line (so a per-LINE at-rule skip exempted the entire
# file the moment it contained one `@media`), and a hand-formatted file splits a single
# declaration across three lines (so a per-LINE parser saw `color:` with no value and
# `#ff0000;` with no property, and silently found nothing). Both reported CLEAN.
_emit_decls() {
    awk '
    function flush(   t) {
      t = buf; gsub(/^[ \t]+|[ \t]+$/, "", t)
      # skipdepth: inside an @font-face block, where `font-family: "Custom"` is the
      # point rather than a violation. At-rule PRELUDES (`@media (min-width: 900px)`)
      # are skipped as chunks; declarations INSIDE @media are still scanned, which is
      # what you want — a literal in a media query is still a literal.
      if (t != "" && skipdepth == 0 && substr(t, 1, 1) != "@") printf "%d\t%s\n", start, t
      buf = ""; start = 0
    }
    { line = $0; i = 1; n = length(line)
      while (i <= n) {
        c = substr(line, i, 1)
        if (incomment) {
          if (substr(line, i, 2) == "*/") { incomment = 0; i += 2 } else { i++ }
          continue
        }
        if (instring) {
          # A "/*" inside a string is text. Treating it as a comment silently swallowed
          # the rest of the FILE — an unbounded false negative that reported clean.
          if (c == "\\") { buf = buf substr(line, i, 2); i += 2; continue }
          buf = buf c; if (c == instring) instring = ""; i++
          continue
        }
        if (substr(line, i, 2) == "/*") { incomment = 1; i += 2; continue }
        if (c == "\"" || c == "\x27") { instring = c; if (buf == "") start = NR; buf = buf c; i++; continue }
        # url(...) is opaque: a data URI legitimately contains ";" and "{", and letting
        # those split the declaration left an unclosed url( that later stripping could
        # not match, so an inline SVG background became a permanent false positive.
        if (tolower(substr(line, i, 4)) == "url(") {
          if (buf == "") start = NR
          buf = buf substr(line, i, 4); i += 4
          while (i <= n) { c = substr(line, i, 1); buf = buf c; i++; if (c == ")") break }
          continue
        }
        if (c == ";") { flush(); i++; continue }
        if (c == "{") { prelude = buf
                        if (prelude ~ /@font-face/ && skipdepth == 0) skipdepth = depth + 1
                        depth++; flush(); i++; continue }
        if (c == "}") { flush(); depth--
                        if (skipdepth > 0 && depth < skipdepth) skipdepth = 0
                        i++; continue }
        if (buf == "" && c ~ /[ \t]/) { i++; continue }
        if (buf == "") start = NR
        buf = buf c; i++
      }
      # A declaration may continue on the next line: keep the buffer, join with a space.
      # A string, however, does not span lines in CSS — leaving instring set would mask
      # the rest of the file exactly like the bug above.
      instring = ""
      if (buf != "") buf = buf " "
    }
    END { flush() }' "$1"
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
        color|background-color|border-color|outline-color|fill|stroke)
            _class="TL-1"; _what="colour"; _shorthand=no ;;
        background|border|outline)
            # Shorthands legitimately carry non-colour values (`no-repeat`, `1px solid`,
            # `center / cover`), so "not a token reference" is not enough to accuse them:
            # they fire only on a value that LOOKS like a colour. Judging them like
            # `color` made `background: url(...) no-repeat` a permanent false positive,
            # which is how a project ends up disabling the lint.
            _class="TL-1"; _what="colour"; _shorthand=yes ;;
        font-size|font-family)
            _class="TL-2"; _what="typography"; _shorthand=no ;;
        *) return 0 ;;
    esac

    case "${_val}" in *var\(--*) return 0 ;; esac
    # url(...) is an asset reference, not a colour: `background: url(/img/hero.png)` is
    # not a literal to tokenise. Strip those out and judge what is left, so
    # `background: url(x) #fff` still fires on the #fff.
    _bare="$(printf '%s' "${_val}" | sed 's/url([^)]*)//g; s/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "${_bare}" ] || return 0
    # Keywords are case-insensitive in CSS — `currentcolor` is the spec's own spelling.
    _low="$(printf '%s' "${_bare}" | tr '[:upper:]' '[:lower:]')"
    case "${_low}" in
        inherit|initial|unset|revert|currentcolor|transparent|none|auto|0) return 0 ;;
    esac
    if [ "${_shorthand}" = "yes" ]; then
        # Colour-shaped only: #hex, rgb()/hsl()/color()/lab(), or a named colour.
        case "${_low}" in
            *"#"*|*rgb*|*hsl*|*lab\(*|*lch\(*|*color\(*) ;;
            *red*|*blue*|*green*|*black*|*white*|*gray*|*grey*|*orange*|*yellow*|*purple*\
            |*pink*|*brown*|*navy*|*teal*|*olive*|*silver*|*gold*|*cyan*|*magenta*|*lime*\
            |*maroon*|*aqua*|*fuchsia*|*indigo*|*violet*|*crimson*|*coral*|*salmon*) ;;
            *) return 0 ;;
        esac
    fi

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
    if ! _emit_decls "${_file}" > "${_LINES}" 2>"${_WORK}/awkerr"; then
        printf 'token-lint: failed to read %s — scan INCOMPLETE\n' "${_file}" >&2
        sed 's/^/token-lint:   /' "${_WORK}/awkerr" >&2
        _unscannable=$((_unscannable + 1))
        continue
    fi

    # One record per declaration, already separated from selectors, at-rule preludes and
    # @font-face bodies by the emitter. Nothing to re-split here — the splitting used to
    # live in this loop, per line, which is exactly what made minified and multi-line CSS
    # invisible. Selectors arrive as their own records; a pseudo-class like `a:hover`
    # parses to the property `a`, which is not covered, so it is skipped.
    while IFS="$(printf '\t')" read -r _n _text; do
        _check_decl "${_file}" "${_n}" "${_text}" || _violations=$((_violations + 1))
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
