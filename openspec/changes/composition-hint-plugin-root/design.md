# Design

## Architecture

One function, `_expand_composition_hint_plugin_root`, sits beside the existing
`_expand_precondition_plugin_root` and is called from the `HINT:` branch that
accumulates `COMPOSITION_HINTS`.

It dispatches on how the placeholder is written in the text:

| Text shape | Treatment | Why |
|---|---|---|
| `'{{PLUGIN_ROOT}}/…'` | delegate to the precondition expander (single-quote escaped) | the text is a shell command the reader pastes |
| `{{PLUGIN_ROOT}}/…` (bare) | plain substitution, no escaping | the text NAMES a file; shell quotes handed to a Read tool are literal characters that make the path unopenable |

The escaped branch **delegates** rather than repeating the escape. The repo pins
exactly one `_pr_esc=` line (`tests/test-attest-remedy-reachable.sh`), because
hand-copying it is how the four #248 renderings drifted apart — one of them
emitting the malformed `a\'\\'\'b`, which breaks the whole pasted line and is
worse than the missing path it replaced.

## Trade-offs

**Why not one treatment for both?** The quoting asymmetry is explicitly pinned
in `skill-routing` ("a rendered path's quoting MUST follow its consumer") and in
the repo's rule files, which say in terms: *do not make them consistent*. This
field is the first to carry both kinds, so the dispatch has to live somewhere.

**Why let the text declare its consumer, rather than adding a second
placeholder?** A second placeholder (`{{PLUGIN_ROOT_QUOTED}}`) is a new config
vocabulary every future author must learn and can get wrong silently. Quoting
the placeholder is already how an author writes the surrounding command, so the
signal is one they produce anyway — and it is visible in the diff.

**Why widen the spec to be surface-agnostic instead of adding this field?**
Because adding the field is what the last three changes each did, and the count
went four → five → six → eight. An enumeration of surfaces is a claim that you
enumerated them, and that claim rots on the next field added. The property is
about *text that reaches a prompt*, so that is what the requirement now says.

## Dissenting views

**"The PLAN instance is prose, not a command — leave it relative."** Rejected on
the measurement, not on taste: `scripts/scope-conformance.sh` is a plugin file,
so a reader outside this repo cannot open it under any reading. It takes the
bare treatment because it is named rather than pasted, which is the asymmetry
working as designed, not an exception to it.

**"Fold the hardcoded intent directive into a later change."** Rejected. It is
the same defect, in the same hook, reachable by the same prompt. Shipping the
other surfaces while leaving it live would make "this surface is fixed" false,
and the next reader would trust the claim over the code.

## Decisions

1. Dispatch on the text's own quoting; no new placeholder vocabulary.
2. Delegate the escape; never copy it.
3. Fix all five sites in one change, including the two the issue did not name.
4. Make the spec's population a property, not a list.
5. The `SKILL.md` instances of the same broken pair (7 across 4 skills) are
   **out of scope** and filed separately: those are static files read by the
   Skill tool, with no substitution pass to hook into, so they need a different
   mechanism rather than a wider call site.
