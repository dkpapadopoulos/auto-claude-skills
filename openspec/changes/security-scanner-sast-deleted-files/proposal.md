# Proposal: SAST scans survive deleted files; axe never downloads; hook paths are quoted

## Why

Three defects found while assessing four awesome-lists against ACS (2026-11-18),
each reproduced before the fix:

1. **The SAST fast scan read clean on any branch that deleted a file.** Step 2 of
   `skills/security-scanner/SKILL.md` fed `git diff --name-only` to
   opengrep/semgrep. That list includes deleted files, and one missing path makes
   opengrep scan nothing. Measured on opengrep 1.26.0: `broken.py` alone gave
   count 1; `broken.py missing.py` gave count 0, `paths.scanned: []` and
   `errors: ["File not found: missing.py"]`. The command dropped stderr and its jq
   read only `.results`, so the error never reached the agent.
2. **The runtime-validation a11y overlay ran `npx @axe-core/cli`.** Where the
   package is not installed, npx downloads whatever version npm serves, which is
   the unpinned-download the Lighthouse overlay in the same skill already refuses.
   Detection also reported "available via npx" for a package that was only listed
   in `package.json`.
3. **`hooks/hooks.json` left `${CLAUDE_PLUGIN_ROOT}` unquoted** in all 31
   commands. With a plugin path that contains a space, the shell splits the path
   and the hook never runs: measured with `/bin/sh -c`, both with the root
   expanded from the environment and substituted as text.

## What Changes

- The fast scan and its last-commit fallback pass `--diff-filter=d`. Every
  documented SAST command's jq now also prints `scanned` (`.paths.scanned |
  length`), `errors` (messages of `level: error` entries) and `warnings` (a count
  of the rest), and SKILL.md states the pass rule: `count: 0` is a pass only when
  `errors` is empty and `scanned` is above 0. Warnings stay out of the rule
  because a complete scan of this repo's own hooks reports `warn` partial
  parses. A guard line stops a branch with no changed file left, where BSD xargs
  would run nothing and GNU xargs would scan the whole directory. Measured on
  opengrep 1.26.0 only; semgrep's output was not re-measured.
- The axe overlay runs a global `axe` or `node_modules/.bin/axe` directly and
  otherwise prints that it skipped; detection reports only those two. It now
  uses `--stdout` and reads `.[0].violations`, the form the @axe-core/cli README
  documents; the old `--reporter json` is not a documented flag, so the overlay
  most likely parsed nothing even where axe was installed. Not run against a real
  axe here. Lighthouse detection likewise stops reporting a package that is
  only listed in `package.json`.
- Every `hooks.json` command quotes its plugin-root path
  (`"${CLAUDE_PLUGIN_ROOT}/hooks/x.sh" args`), the form other installed plugins
  already use. Six tests that matched the unquoted string were updated, and
  `tests/test-hook-file-modes.sh` now asserts every command is quoted.

## Capabilities

- **Modified:** `security-scanner` (the "Hybrid deterministic scanning"
  requirement; the Semgrep scenario).
- **Added:** `runtime-validation` (the a11y overlay runs only an installed axe);
  `skill-routing` (hook commands quote the plugin root).

## Impact

- Branches that delete files now get a real SAST result instead of a silent
  `count: 0`; a scan that covered nothing reads as "could not check".
- No network download from the a11y overlay; projects without axe installed get
  a skip line instead.
- Hooks run for users whose plugin path contains a space. No hook's behaviour
  changes.
