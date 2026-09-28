# Design

## Architecture

`session-start-hook.sh` already resolves `PLUGIN_ROOT` to an absolute path and
already injects a block of capability lines. It now also emits:

```
Plugin root: <abs>
  (… a skill names the plugin's own scripts as `<PLUGIN_ROOT>/...` — substitute
   the path above before running … do NOT re-derive it …)
```

Files under `skills/` reference `<PLUGIN_ROOT>/...`. The model performs the
substitution, exactly as it already does for `<plan-file>` and `<discovery-doc>`
in those same files.

## Trade-offs

**Why not derive from the `Base directory for this skill:` line the harness
prints?** Measured: the harness does emit it, for both a superpowers and an ACS
skill. It is free and already works. Rejected because it is undocumented output
this repo does not control and its suite cannot simulate — if that prefix
changes, all 19 sites break silently with no test able to see it — and because
it does not exist for `agent-team-execution/lead-prompt.md`, which is not a
SKILL.md. Injection is testable end to end, exactly like #306's fix.

**Why an angle-bracket placeholder rather than a `PLUGIN_ROOT="…"` assignment in
each block?** The assignment was built first and then withdrawn on a
measurement. `skills/incident-analysis/SKILL.md` sits at exactly its word-count
baseline with zero headroom, and the assignment cost **+12 words** there. The
repo's rule is extract-then-raise; raising a constant the repo treats as a
control, or performing an unrelated extraction, to pay for a one-line path fix
is disproportionate. The placeholder is **zero growth** (measured: 11531,
exactly baseline), shorter at every site, and matches the convention already in
these files.

The cost is real: nothing in a SKILL.md now says what to substitute, so the
injected context line carries the whole explanation. Two cells make that a loud
failure if the line ever stops naming the placeholder.

**Why lint the expansion rather than the known bad spellings?** Because the
enumeration was wrong twice inside this change — 9, then 13, then 19 — and the
shape that kept escaping was the bare `$CLAUDE_PLUGIN_ROOT` that nobody thought
to look for. A lint listing the shapes that shipped would have missed it the same
way. Re-deriving the root requires *expanding* the variable, so the expansion is
the property. It deliberately permits prose that names `CLAUDE_PLUGIN_ROOT`
without expanding it, because the per-file guidance has to be able to say what
not to do.

## Dissenting views

**"Just raise the word baseline by 12."** Rejected. The constant is a control the
repo documents a process for changing, and a fix's convenience is not a reason to
spend it. The placeholder made the question moot at zero cost, which is the
better outcome than winning the argument.

**"`{{PLUGIN_ROOT}}` worked for #306, reuse it."** Rejected, and pinned by a cell.
It works only because a hook renders that text and substitutes before emission.
Nothing renders a SKILL.md, so the literal braces would reach the reader —
strictly worse than the broken pair, which at least expanded to something.

## Decisions

1. Inject the root once from session-start; do not re-derive it anywhere.
2. Reference it as `<PLUGIN_ROOT>`, matching the existing placeholder convention.
3. Lint the expansion, not a list of spellings.
4. Fix all three shapes in one pass, so the lint need not tolerate a known-bad
   form.
5. Rekey the contradicting assertion in `test-checkpoint-validate.sh` to its
   stated intent rather than deleting it.
