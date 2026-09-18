# auto-claude-skills — agent instructions

**Read `CLAUDE.md` in this directory and follow it.** It is the single source of truth for
this repo: architecture, style, the six canonical doc locations, and a long list of gotchas
that exist because each one already cost someone a day.

This file exists only because some agents look for `AGENTS.md` by convention. It is a
pointer on purpose.

**Do not copy `CLAUDE.md` into this file.** A duplicate drifts within days — the previous
version of this file was a verbatim copy that fell ten days behind and still described the
project under the wrong name, which is worse than having no file at all, because a stale
copy reads as authoritative.

Two things worth knowing before you touch anything:

- `bash tests/run-tests.sh` runs the whole suite. It is also the declared local gate, so
  one red file blocks every push that touches `skills/`, `config/` or `hooks/`.
- Hooks are Bash 3.2 (macOS `/bin/bash`) and fail open. Syntax-check any hook edit with
  `bash -n hooks/<name>.sh`, and read the gotchas in `CLAUDE.md` before changing one — the
  failure mode there is silence, not an error.
