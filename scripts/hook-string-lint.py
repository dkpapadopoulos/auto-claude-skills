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

The list above has already been wrong once — omitting `$( )` produced six false
accusations against a single-quoted jq program on the real tree — so treat it as
an enumeration that is known to be incomplete rather than as a proof. The
compensating control is that the lint is asserted CLEAN on the whole hooks tree:
a newly mishandled construct shows up as a false positive on a known-good file
and fails the gate loudly, rather than silently widening a blind spot.
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
                pass
            else:
                if j < n and text[j] == "-":
                    j += 1
                while j < n and text[j] in " \t":
                    j += 1
                quoted = False
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

    return hits


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
        for line, col, ctx in scan(text):
            total += 1
            print("%s:%d:%d: live backtick substitution inside %s" % (path, line, col, ctx))
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
