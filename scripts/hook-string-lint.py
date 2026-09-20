#!/usr/bin/env python3
"""
hook-string-lint.py — flag backticks that are LIVE command substitutions inside
hook source, i.e. the PR#38 class: a backticked word written as markdown quoting
inside a DOUBLE-quoted shell string is executed at assignment time, prints
`command not found` to stderr, and silently vanishes from the rendered text.

`bash -n` cannot catch it (the substitution is syntactically valid) and the suite
cannot catch it unless something asserts that string's rendered content.

The unit is the QUOTING STATE, not the line. Most backticks in this tree are
markdown quoting inside comments, and one long jq program quotes shell-special
characters inside SINGLE quotes where a backtick is literal. A line-oriented
matcher reports one of those two populations as a defect and the real one as
clean, which is this repo's recurring shape.

KNOWN-INCOMPLETE, by construction and deliberately labelled as such: this is a
scanner over one shell's quoting rules, not a parser. It tracks single quotes,
double quotes, comments, backslash escapes, heredocs (quoted and unquoted
delimiters) and `$( )` nesting. It does NOT handle arithmetic contexts, `case`
patterns, backslash-continued heredoc delimiters, or backtick-delimited
substitution as a nesting context of its own.

The list above has been wrong twice, in opposite directions, so treat it as an
enumeration known to be incomplete rather than as a proof. First it produced
FALSE ACCUSATIONS: omitting `$( )` nesting flagged six backticks inside a
single-quoted jq program. Then a reviewer showed the worse direction — three
constructs (a heredoc opener with a trailing comment, ANSI-C quoting, and a
backslash-quoted heredoc delimiter) desynchronised the quote
state so the scanner reported NOTHING on a file that really did execute its
backtick.

An earlier version of this comment claimed the compensating control was that a
new blind spot would surface as a false positive on a known-good file. That was
false, and it was the central argument for shipping an incomplete scanner. The
actual control is that the scan REPORTS ITS OWN COHERENCE: an unclosed quote,
heredoc or substitution at EOF yields CANNOT-CHECK (exit 3), never "clean". A
desync is the mechanism by which this class of scanner goes silent, and that is
now the thing it detects.
"""
import sys

SAFE, ACTIVE = "safe", "active"


def scan(text):
    """Yield (lineno, col, context) for every backtick in an ACTIVE context.

    Quoting is a STACK, not a pair of booleans. `"$( ... )"` opens a fresh
    quoting context inside a double-quoted string: the single quotes of
    `jq '...'` written in there are real single quotes, and a backtick between
    them is literal. The first cut of this scanner tracked two booleans, and on
    the real tree it reported six live substitutions inside a single-quoted jq
    program — all false. That also falsified its own stated guarantee of
    degrading toward silence, which is why the stack is here rather than a note
    about a known limitation.
    """
    hits = []
    i, n = 0, len(text)
    line, col = 1, 1
    # Each frame: [single_quoted, double_quoted]. Frame 0 is the file itself.
    stack = [[False, False]]
    comment = False
    heredocs = []
    in_heredoc = None
    at_line_start = True

    def advance(ch):
        nonlocal line, col
        if ch == "\n":
            line += 1
            col = 1
        else:
            col += 1

    while i < n:
        c = text[i]
        sq, dq = stack[-1]

        if in_heredoc is not None:
            delim, quoted = in_heredoc
            if at_line_start:
                eol = text.find("\n", i)
                raw = text[i:eol if eol != -1 else n]
                if raw.strip() == delim:
                    in_heredoc = None
                    for ch in raw:
                        advance(ch)
                    i += len(raw)
                    at_line_start = False
                    continue
            if c == "`" and not quoted and (i == 0 or text[i - 1] != "\\"):
                hits.append((line, col, "unquoted heredoc <<%s" % delim))
            at_line_start = c == "\n"
            advance(c)
            i += 1
            continue

        if comment:
            if c == "\n":
                comment = False
                at_line_start = True
                # A comment AFTER a heredoc opener still ends the line that
                # opened it, so the body starts on the next line. Popping only
                # in the newline handler at the bottom of the loop meant
                # `cat <<EOF   # note` never entered body mode and the whole
                # body was scanned as code — reported clean while bash ate the
                # backticked word. Measured.
                if heredocs:
                    in_heredoc = heredocs.pop(0)
            advance(c)
            i += 1
            continue

        # A backslash escapes inside double quotes and unquoted text, never
        # inside single quotes.
        if not sq and c == "\\":
            advance(c); i += 1
            if i < n:
                advance(text[i]); i += 1
            at_line_start = False
            continue

        # `$(` opens a nested quoting context; `)` closes it. Only recognised
        # outside single quotes, where `$(` is literal.
        if not sq and c == "$" and text[i:i + 2] == "$(":
            stack.append([False, False])
            advance(c); i += 1
            advance(text[i]); i += 1
            at_line_start = False
            continue
        # A `)` only closes the substitution when the frame's own quoting is
        # balanced. `"$(_json_escape "PUSH GATE (advisory): $1")"` contains a
        # `)` inside a double-quoted string; popping there unbalanced the stack
        # for the rest of the file and turned an entire comment block into 48
        # false accusations.
        if not sq and not dq and c == ")" and len(stack) > 1:
            stack.pop()
            advance(c); i += 1
            at_line_start = False
            continue

        # `$'...'` is ANSI-C quoting: unlike an ordinary single-quoted string,
        # a backslash escapes there, so `$'don\'t'` contains an apostrophe and
        # does NOT end at the second quote. Treating it as an ordinary `'...'`
        # desynchronised the quote state for the whole rest of the file.
        if not sq and not dq and c == "$" and text[i:i + 2] == "$'":
            advance(c); i += 1          # $
            advance(text[i]); i += 1    # '
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    advance(text[i]); i += 1
                    advance(text[i]); i += 1
                    continue
                if text[i] == "'":
                    advance(text[i]); i += 1
                    break
                advance(text[i]); i += 1
            at_line_start = False
            continue

        if c == "'" and not dq:
            stack[-1][0] = not sq
            advance(c); i += 1; at_line_start = False
            continue
        if c == '"' and not sq:
            stack[-1][1] = not dq
            advance(c); i += 1; at_line_start = False
            continue

        if c == "#" and not sq and not dq:
            if i == 0 or text[i - 1] in " \t\n;&|(":
                comment = True
                advance(c); i += 1
                continue

        if not sq and not dq and text[i:i + 2] == "<<":
            j = i + 2
            if j < n and text[j] == "<":
                # Here-string. CONSUME ALL THREE characters: advancing by one
                # leaves `<<` matching again on characters 2 and 3, and the
                # operand is then read as a heredoc delimiter. Measured on
                # hooks/skill-activation-hook.sh:1983 — `read ... <<< "$VAR"`
                # registered a heredoc named `$_DC_GWT_PAIR`, whose terminator
                # never arrives, so the remaining ~200 lines of that hook were
                # swallowed as heredoc body and never scanned at all. The file
                # reported CLEAN because nothing was looked at.
                #
                # hooks/lib/git-command.sh's own scanner carries this exact fix
                # and this exact reason; this port did not inherit it.
                advance(c); i += 1
                advance(text[i]); i += 1
                advance(text[i]); i += 1
                at_line_start = False
                continue
            else:
                if j < n and text[j] == "-":
                    j += 1
                while j < n and text[j] in " \t":
                    j += 1
                quoted = False
                # `<<\EOF` quotes the delimiter exactly as `<<'EOF'` does, so
                # the body does not expand. The delimiter scan below accepts
                # only word characters, so an unhandled backslash left `delim`
                # empty, the heredoc was never registered, and the body was
                # scanned as code — where an apostrophe in ordinary prose
                # ("Don't") opened a quote that never closed.
                if j < n and text[j] == "\\":
                    quoted = True
                    j += 1
                if j < n and text[j] in "'\"":
                    q = text[j]
                    quoted = True
                    j += 1
                    start = j
                    while j < n and text[j] != q:
                        j += 1
                    delim = text[start:j]
                else:
                    start = j
                    while j < n and (text[j].isalnum() or text[j] in "_-."):
                        j += 1
                    delim = text[start:j]
                if delim:
                    heredocs.append((delim, quoted))

        if c == "`" and dq and not sq:
            hits.append((line, col, "double-quoted string"))

        if c == "\n":
            at_line_start = True
            if heredocs:
                in_heredoc = heredocs.pop(0)
        else:
            at_line_start = False
        advance(c)
        i += 1

    # THE compensating control, and it replaces a claim that was false.
    #
    # This scanner cannot be proved complete, so the docstring used to argue
    # that a newly mishandled construct would surface as a false positive on a
    # known-good file. A reviewer refuted that with three measured cases where
    # the quote state DESYNCHRONISES and the scanner then reports nothing at all
    # on a file containing a live backtick — silent, which is the direction that
    # matters. A blind spot does not announce itself.
    #
    # So the scanner now reports whether it finished in a coherent state. If a
    # quote or a heredoc is still open at EOF, or a `$( )` frame never closed,
    # the parse is untrustworthy and the caller is told it CANNOT CHECK the file
    # rather than that the file is clean. That is a property of the scan itself,
    # not a guess about which constructs exist.
    unbalanced = bool(stack[-1][0] or stack[-1][1] or in_heredoc or len(stack) > 1)
    return hits, unbalanced


def main(argv):
    files = argv[1:]
    if not files:
        print("usage: hook-string-lint.py <file>...", file=sys.stderr)
        return 3
    total = 0
    for path in files:
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError as exc:
            print("CANNOT-CHECK %s: %s" % (path, exc), file=sys.stderr)
            return 3
        found, unbalanced = scan(text)
        if unbalanced:
            print("CANNOT-CHECK %s: the scan ended with an unclosed quote, "
                  "heredoc or substitution — this file's quoting is not modelled, "
                  "so a clean result would be meaningless" % path, file=sys.stderr)
            return 3
        for line, col, ctx in found:
            total += 1
            print("%s:%d:%d: live backtick substitution inside %s" % (path, line, col, ctx))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
