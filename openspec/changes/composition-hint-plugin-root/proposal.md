# Composition hints must name plugin files by a path the reader can open

## Why

`phase_compositions[*].hints[].text` is a rendering surface that reaches the
model's prompt, and it was rendered **verbatim** — no `{{PLUGIN_ROOT}}`
substitution. #248 wired the placeholder into `precondition`, #305 into
`methodology_hints[].hint`, and both missed this field.

Three live instances were unreachable, and they were NOT all the same shape —
worth stating, because a reader counting occurrences of the pair will find two,
not three. DISCOVER and DESIGN shipped the #248 broken pair; PLAN shipped a
plain relative `scripts/scope-conformance.sh`, which is unopenable for the same
reason but by a different route. The pair:

```
bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null)}/scripts/persist-state.sh"
```

`CLAUDE_PLUGIN_ROOT` is unset in the model's Bash turn, so that resolves to the
**user's** repo root, which has no `scripts/persist-state.sh` — measured
`rc=127` in an external repo under both shells.

The DISCOVER and DESIGN instances **are** the state-persist step. When they
fail, `discovery_path` / `design_path` are never written to session state, and
the PLAN-phase activation guard that reads them degrades with no diagnostic.
This fires on every DISCOVER/DESIGN/PLAN prompt in every adopting repo — more
often than the `hint` field #305 fixed.

Two surfaces beyond the three the issue named were found while fixing it, and
both would have made the fix a false claim:

1. **`hooks/session-start-hook.sh` rewrites this same field** under the
   `spec-driven` preset, carrying its own copy of the broken pair. Fixing the
   configs alone leaves every spec-driven repo broken — including this one.
2. **`hooks/skill-activation-hook.sh` hardcodes an INTENT EXTRACTION directive**
   into `SKILL_LINES` with a third copy. No config lint can reach it.

## What Changes

- The `HINT:` branch of the composition renderer substitutes `{{PLUGIN_ROOT}}`.
- The substitution honours the **pinned quoting asymmetry** by letting the text
  declare its own consumer: `'{{PLUGIN_ROOT}}/…'` is a pasted shell command and
  is single-quote-escaped; a bare `{{PLUGIN_ROOT}}/…` names a file to read and
  is emitted unescaped. This field carries both kinds.
- The three config instances, the preset's injected copy, and the hardcoded
  intent directive all move to the placeholder.
- The spec's population becomes **surface-agnostic**. This enumeration has been
  wrong three times (four surfaces → five → six → eight); requiring the property
  of *any* rendered text, with the known surfaces named as examples rather than
  as the definition, is what stops the next miss from being spec-compliant.

## Capabilities

- Modified: `skill-routing`

## Impact

- `hooks/skill-activation-hook.sh` — new `_expand_composition_hint_plugin_root`;
  `HINT:` branch; the hardcoded intent directive.
- `hooks/session-start-hook.sh` — the `spec-driven` injected hint text.
- `config/default-triggers.json`, `config/fallback-registry.json` — three
  instances each.
- `tests/test-composition-hint-plugin-root.sh` — new.

No behaviour change for readers inside this repo, where plugin root and project
root coincide. That coincidence is why the defect survived six surfaces.
