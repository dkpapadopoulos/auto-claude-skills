# Files the model reads must name plugin paths it can open

## Why

19 places under `skills/` told the model to run one of the plugin's own scripts
by re-deriving the plugin root. `CLAUDE_PLUGIN_ROOT` is set for hook processes
and **unset in the model's Bash turn** (measured `<unset>`, zsh 5.9), so none of
them resolved to the plugin. They shipped in **three** shapes:

| Shape | n | Resolves to |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)}` | 9 | the USER's repo root |
| `${CLAUDE_PLUGIN_ROOT:-.}` | 4 | the current working directory |
| bare `$CLAUDE_PLUGIN_ROOT` | 6 | **empty** — the path starts at `/` |

The third is the worst and was the one nobody had counted: `bash
"${CLAUDE_PLUGIN_ROOT}/scripts/obs-preflight.sh"` becomes `bash
"/scripts/obs-preflight.sh"`. The second is next: which directory `.` names
depends on where the model happens to be standing, so it can pick up a
same-named script from an unrelated tree.

The count was wrong twice before the lint was written — reported as 9, measured
as 13, found to be 19 — which is the direct argument for how the lint is keyed
(see design.md).

`skills/project-verification/SKILL.md` additionally named
`scripts/coverage-adequacy-check.sh`, which is wrong even **inside** the plugin:
the script lives at `skills/project-verification/scripts/`.

This matters beyond a broken path. `project-verification`'s
`verify-and-record.sh` is the verdict writer the push gate reads. If an adopting
repo's agent cannot run it, it cannot produce a clean verdict, so the documented
remedy for a routing-governance deny is unreachable — the failure class #248 was
opened for.

## What Changes

- `session-start-hook.sh` emits `Plugin root: <abs>` into the session context,
  and states the substitution convention there.
- All 19 sites use `<PLUGIN_ROOT>/...`, an angle-bracket placeholder matching how
  these same files already mark substitution points (`<plan-file>`,
  `<discovery-doc>`).
- The wrong-inside-plugin path is corrected.
- A lint forbids any file under `skills/` from expanding `CLAUDE_PLUGIN_ROOT`,
  and forbids copying #306's `{{PLUGIN_ROOT}}` here — nothing substitutes it in a
  file the Skill tool hands over verbatim, so it would reach the reader as
  literal braces, which is worse than the pair it replaced.
- `tests/test-checkpoint-validate.sh` is rekeyed: it asserted SKILL.md *contain*
  `${CLAUDE_PLUGIN_ROOT:-.}` while its own comment forbade "a bare repo path" —
  the two contradicted each other, and the spelling it pinned was the defect.

## Capabilities

- Modified: `skill-routing`

## Impact

- `hooks/session-start-hook.sh` — one injected line.
- 12 files under `skills/` — 19 sites plus one corrected path.
- `tests/test-skill-plugin-root-reachable.sh` — new, 34 cells.
- `tests/test-checkpoint-validate.sh` — one assertion rekeyed to its intent.

No behaviour change for readers inside this repo, where plugin root and project
root are the same directory. That coincidence is why this survived alongside the
six hook-rendered surfaces #248/#305/#306 fixed.
