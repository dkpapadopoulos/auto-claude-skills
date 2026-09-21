#!/usr/bin/env python3
"""precondition-lint.py — flag test cells that ARRANGE a precondition they claim to test.

    precondition-lint.py <file.sh> [<file.sh> ...]

Exit: 0 clean | 1 findings | 2 usage | 3 cannot check.

Three defects were found in ONE change's tests (2026-09-19), all the same
shape: the cell ran, every assertion held, and the branch it advertised never
executed because the surrounding environment sent it somewhere else. That is a
different failure from a mutation that never applied — here the mutation
applied perfectly and a byte comparison confirms it. Comparing artifacts tells
you the file changed; it says nothing about which branch ran.

THE UNIT IS THE CELL, NOT THE LINE. This repo has five recorded instances of a
line-oriented matcher over a declaration-shaped language reporting clean in
every direction it can fail (see CLAUDE.md, and the KNOWN-INCOMPLETE note in
tests/test-deny-reason-reaches-model.sh). A per-line rule here would flag every
`PATH=` in the suite and miss the one that matters, because what makes an
arrangement a defect is the label it sits under and the assertion it lacks —
both of which live elsewhere in the same cell.

A cell is:
  * a shell function body `name() { ... }` — delimited by a closing brace at the
    function's own indentation, so a nested `}` does not end it; or
  * a top-level SECTION between two markers: `echo "--- ... ---"`, a `# ---` /
    `# ===` rule, or a `# (a)` / `# (1)` step comment.
Functions nested inside a section are their own cells AND stay part of the
section, because either scope can carry the missing assertion.

This is a KNOWN-INCOMPLETE enumeration of three measured shapes, not a proof of
totality. Widen it when a fourth is found; do not read a clean result as "no
cell in this file arranges its own precondition".
"""
import re
import sys

# --- vocabulary --------------------------------------------------------------
# A label claiming the cell exercises a path where some TOOL is unavailable.
ABSENT_LABEL = re.compile(
    r"""(?ix)
    \b no[-\s]?(jq|gh|git|awk|python3?|node|gitleaks|openspec)\b
  | \b(jq|gh|git|awk|python3?|node|gitleaks|openspec)[-\s]?(less|absent|missing|unavailable)\b
  | \bwithout\s+(jq|gh|git|awk|python3?|node|gitleaks|openspec)\b
  | \b(absent|missing|unavailable|unresolvable)\s+(tool|binary|command|jq|gh|git)\b
    """,
)
TOOL_IN_LABEL = re.compile(
    r"(?i)\b(jq|gh|git|awk|python3?|node|gitleaks|openspec)\b")

# The arrangement: rebuilding PATH so the tool "is not there".
PATH_ARRANGE = re.compile(r"""(?x) (^|[\s;(`"']) PATH \s* = """)
# The assertion: a run-time check that the tool really does not resolve.
#
# NAMING THE TOOL IS LOAD-BEARING, and the first cut got this wrong. A bare
# `command -v` matcher passed the measured red fixture, because the cell BUILDS
# its shim with `_p="$(command -v "${_t}")" && ln -sf "${_p}" ...` — resolving
# each tool in order to symlink it. That is the opposite of asserting the tool
# is gone, and the lint agreed the cell was fine. The assertion has to name the
# label's tool LITERALLY and must not be a line that is populating the shim.
RESOLVE_VERB = r"(?:command\s+-v|type\s+-P|which)"
SHIM_BUILD = re.compile(r"\bln\s+-s|\bcp\s|\binstall\s")


def asserts_absent(text, tool):
    """Does the cell CHECK, at run time, that `tool` does not resolve?

    Two accepted forms, because the suite uses both and a matcher that knows
    only one produces a false positive on a cell that is doing the right thing:
      * `command -v <tool>` / `which <tool>` naming the tool literally, on a
        line that is not populating the shim;
      * a file test against the shim directory — `[ ! -e "$NOJQ_BIN/jq" ]` —
        which is the same claim stated about the arranged PATH instead of the
        resolver. Missing this form flagged test-push-gate-failclosed.sh (g),
        a cell that asserts its precondition correctly.
    """
    resolve = re.compile(r"%s\s+[\"']?%s[\"']?(\s|$|['\"])" % (RESOLVE_VERB, re.escape(tool)))
    filetest = re.compile(r"""\[\s*!\s*-[efxrs]\s+["']?\$\{?\w+\}?/%s["']?\s*\]""" % re.escape(tool))
    for line in text.split("\n"):
        if filetest.search(line):
            return True
        if resolve.search(line) and not SHIM_BUILD.search(line):
            return True
    return False


# How far apart the LABEL and the ARRANGEMENT may sit and still be read as one
# cell. A file with no early section markers is one enormous cell, and in such a
# file an "absent git" label on line 12 and an unrelated `PATH=` on line 400
# were reported as a defect twice. The claim the rule makes is about one cell's
# setup, so the two halves must be near each other; 25 lines covers every
# measured instance (the red fixture's are 15 apart) and cuts the whole-file
# coincidences. It is a bound on the CLAIM, not a heuristic for severity: past
# it the lint does not know the two are related, so it must not assert they are.
PROXIMITY = 25

# Roots that decide a hook's MODE as well as its code.
ROOT_ASSIGN = re.compile(
    r"""(?x) \b (CLAUDE_PLUGIN_ROOT | SKILL_PROJECT_ROOT) \s* = \s* (?P<val>"[^"]*"|\S+)""")
POSITIONAL = re.compile(r"^\$\{?[0-9]+\}?$")
# A MUTATION here is a REWRITE OF PRODUCTION CODE INTO A MUTANT COPY — `sed ... > "${TMP}/x.sh"`. Building a
# disposable tree is NOT one, and including `cp -R` made the rule fire on every
# hermetic harness in the suite. Sharper still: a cell whose whole intervention
# IS the root (a plugin root with one lib removed, probed once with the real
# root and once without) legitimately varies the root between its two runs —
# there the root is the treatment, not a confounder. The defect this rule names
# is TWO interventions at once: the file is rewritten AND the root moves, so a
# difference in output cannot be attributed to either.
# — a `sed` whose INPUT is a path under the real checkout and whose OUTPUT is a
# path under some other variable. Every weaker form tried first fired on a
# legitimate idiom: `cp -R` matched every hermetic harness in the suite, and a
# bare "sed writing into a variable path" matched a cell that rewrites a
# FIXTURE. Matched over LOGICAL lines, because the real instance splits the
# command across a backslash continuation and a per-line matcher sees neither
# half whole — the exact shape this issue exists to warn about.
MUTATION_WRITE = re.compile(
    r"""(?x) \b (sed|awk|perl|python3?) \b [^\n]*? (PROJECT_ROOT|REPO_ROOT)
             [^\n]*? > \s* "?\$\{?\w+ """)

# A JSON oracle looser than the contract it stands in for.
LOOSE_JSON = re.compile(r"\bjq\s+(-[a-zA-Z]+\s+)*empty\b")
HOOK_OUTPUT = re.compile(r"\.hookSpecificOutput\b|permissionDecision\b")

SECTION_MARK = re.compile(
    r"""(?x)
      ^\s* echo \s+ "-{2,}          # echo "--- section ---"
    | ^\s* \#\s* -{3,}              # # ---------
    | ^\s* \#\s* ={3,}              # # =========
    | ^\s* \#\s* \(\s*[0-9a-z]{1,3}\s*\)   # # (a) / # (1)
    | ^\s* \#\s* [0-9]{1,2}\.\s                # # 4. heading
    """)
FUNC_OPEN = re.compile(r"^(?P<indent>[ \t]*)(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{")


def _fold_continuations(text):
    out = []
    buf = ""
    for line in text.split("\n"):
        if line.endswith("\\"):
            buf += line[:-1] + " "
            continue
        out.append(buf + line)
        buf = ""
    if buf:
        out.append(buf)
    return "\n".join(out)


def _strip_comment(line):
    """Drop a trailing `#` comment, respecting quotes."""
    quote = None
    for i, ch in enumerate(line):
        if quote:
            if ch == "\\" and quote == '"':
                continue
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1].isspace()):
            return line[:i]
    return line


def _depth_delta(line):
    """Net { } depth of one line, ignoring quoted runs and trailing comments.

    Not a shell parser — a brace counter that knows about quotes, which is all
    the cell boundary needs. It exists because matching a closing brace by
    INDENTATION silently swallowed every one-line definition: `reset() { ...; }`
    has no later `^}`, so the cell ran to the next function hundreds of lines
    away and dragged unrelated code into its scope. Measured: that alone
    produced most of the false positives on the live suite.
    """
    depth = 0
    quote = None
    i = 0
    while i < len(line):
        ch = line[i]
        if quote:
            if ch == "\\" and quote == '"':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in ("'", '"'):
            quote = ch
        elif ch == "#" and (i == 0 or line[i - 1].isspace()):
            break
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        i += 1
    return depth


def _func_end(lines, start):
    depth = _depth_delta(lines[start])
    if depth <= 0:
        return start                      # one-line definition
    j = start + 1
    while j < len(lines):
        depth += _depth_delta(lines[j])
        if depth <= 0:
            return j
        j += 1
    return len(lines) - 1


class Cell(object):
    def __init__(self, kind, name, start, end, lines):
        self.kind = kind          # "function" | "section"
        self.name = name
        self.start = start        # 1-based, inclusive
        self.end = end            # 1-based, inclusive
        self.text = "\n".join(lines[start - 1:end])
        # CODE-ONLY view. Every pattern that describes what the cell DOES is
        # matched against this; only the label vocabulary reads the comments.
        # Without it the lint red-flags its own explanation: the fixed version
        # of the measured instance carries a comment saying "`jq empty` accepts
        # a STREAM", and a whole-text matcher reported the repaired cell as
        # still defective. That is the inverse hazard this repo's other lint
        # documents — loud rather than silent, but a false positive either way.
        self.code = "\n".join(_strip_comment(l) for l in lines[start - 1:end])
        # LOGICAL lines: backslash continuations folded. A shell command is the
        # unit here, not a source line.
        self.logical = _fold_continuations(self.code)


def cells(lines):
    """Split a shell file into function cells and top-level section cells."""
    out = []
    i = 0
    n = len(lines)
    while i < n:
        m = FUNC_OPEN.match(lines[i])
        if m:
            j = _func_end(lines, i)
            out.append(Cell("function", m.group("name"), i + 1, j + 1, lines))
        i += 1

    bounds = [i for i, ln in enumerate(lines) if SECTION_MARK.match(ln)]
    if not bounds or bounds[0] != 0:
        bounds = [0] + bounds
    bounds.append(n)
    for k in range(len(bounds) - 1):
        s, e = bounds[k], bounds[k + 1]
        if e > s:
            name = lines[s].strip()[:60]
            out.append(Cell("section", name, s + 1, e, lines))
    return out


def _tools_named(text):
    return set(t.lower() for t in TOOL_IN_LABEL.findall(text) if isinstance(t, str) and t)


def _near(c, label_re, code_re, in_code=False):
    """First label match that sits within PROXIMITY lines of an arrangement."""
    tlines = (c.code if in_code else c.text).split("\n")
    clines = c.code.split("\n")
    arrange = [i for i, ln in enumerate(clines) if code_re.search(ln)]
    if not arrange:
        return None
    for i, ln in enumerate(tlines):
        m = label_re.search(ln)
        if m and any(abs(i - a) <= PROXIMITY for a in arrange):
            return m
    return None


def scan_cell(c):
    found = []

    # R1 — a cell whose LABEL claims a tool is absent, that ARRANGES PATH and
    # never ASSERTS the tool is really unresolvable. Measured instance: a cell
    # labelled "no-jq emitter" set PATH="${NOJQ_BIN}:/usr/bin:/bin", and macOS
    # ships /usr/bin/jq — so it exercised the jq branch, and mutating the
    # fallback left all four assertions passing.
    m = _near(c, ABSENT_LABEL, PATH_ARRANGE)
    if m:
        tools = [t for t in _tools_named(m.group(0))]
        missing = [t for t in tools if not asserts_absent(c.code, t)]
        if missing:
            found.append(("arranged-absent-tool",
                          "label claims %s is absent and PATH is rearranged, but nothing "
                          "checks at run time that %s is actually unresolvable"
                          % (", ".join(missing), "it" if len(missing) == 1 else "they are")))

    # R2 — a mutation control that moves the ROOTS as well as the code. A
    # foreign CLAUDE_PLUGIN_ROOT resolves the gate to a different MODE, so the
    # mutant differs in two variables and any observed change is unattributable.
    # A DISPOSABLE ROOT IS NOT THE DEFECT, and the first cut treated it as one:
    # every hermetic harness in this suite does `cp -R hooks "${_TROOT}"` and
    # runs everything from there, which holds the root CONSTANT and is exactly
    # right. 11 of the first run's 24 findings were that idiom. What breaks
    # attribution is the root VARYING between the control run and the mutant
    # run — then the mutant differs in mode as well as code and the observed
    # change is unattributable. In the measured instance the probe took the root
    # as a positional parameter and was called once with the real checkout and
    # once with the copy.
    if MUTATION_WRITE.search(c.logical):
        for m in ROOT_ASSIGN.finditer(c.code):
            val = m.group("val").strip('"')
            if POSITIONAL.match(val):
                found.append(("mutation-control-moved-roots",
                              "%s is bound to the positional parameter %s in a cell that also "
                              "mutates a file, so the control and the mutant can run under "
                              "different roots — a difference in mode, not only in code"
                              % (m.group(1), val)))
                break

    # R3 — a JSON oracle looser than the contract. `jq empty` accepts a
    # STREAM, so two concatenated objects pass and the second one's empty
    # fields satisfy every field assertion below it.
    if LOOSE_JSON.search(c.code) and HOOK_OUTPUT.search(c.code):
        found.append(("loose-json-oracle",
                      "`jq empty` validates a STREAM, but the hook contract is exactly one "
                      "object; count them with `jq -s 'length'` instead"))
    return found


def scan(path):
    try:
        with open(path, "r") as fh:
            lines = fh.read().split("\n")
    except (IOError, OSError) as exc:
        return None, str(exc)
    hits = []
    for c in cells(lines):
        for rule, why in scan_cell(c):
            hits.append((path, c.start, c.end, c.kind, c.name, rule, why))
    return hits, None


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: precondition-lint.py <file.sh> [...]\n")
        return 2
    all_hits = []
    for p in argv[1:]:
        hits, err = scan(p)
        if err is not None:
            sys.stderr.write("CANNOT-CHECK %s: %s\n" % (p, err))
            return 3
        all_hits.extend(hits)
    # Dedupe: a function nested in a section is scanned twice by design, and
    # the same defect must be reported once.
    seen = set()
    for path, start, end, kind, name, rule, why in all_hits:
        key = (path, rule, name if kind == "function" else None)
        if kind == "section" and any(k[0] == path and k[1] == rule for k in seen):
            continue
        if key in seen:
            continue
        seen.add(key)
        print("%s:%d-%d [%s] %s (%s) — %s" % (path, start, end, rule, kind, name, why))
    return 1 if seen else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
