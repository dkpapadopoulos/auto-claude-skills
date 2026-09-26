---
paths:
  - "hooks/**/*.sh"
  - "scripts/**/*.sh"
  - "tests/**/*.sh"
  - "skills/**/*.sh"
  - "assets/**/*.sh"
---

# Shell portability when writing hooks and scripts

Path-scoped rule, split out of the repo-root `CLAUDE.md` Gotchas section so it
loads only when you touch the files it governs. Every bullet is verbatim.

- `[[ $P =~ $trigger ]]` returns exit 1 on regex non-match — never use `set -e` in routing hooks.

- Bash 3.2 (`/bin/bash`, every `#!/bin/bash` hook) rejects **quoted operands in `$(( ))`**: `$(( "604800" / 86400 ))` → `syntax error: operand expected`, and the error **aborts the script at that line** — in a fail-open hook this silently kills everything after it (e.g. registry building), violating fail-open. Use unquoted arithmetic on validated-numeric input: `[[ "$V" =~ ^[0-9]+$ ]] || V=<default>; N=$(( V / 86400 ))`. The model's Bash tool tolerates the quotes (measured: `zsh` prints `7`, `/bin/bash` 3.2 errors), so this passes manual testing and only fails under 3.2 — always syntax-check hook edits with `/bin/bash -n` and exercise them under `/bin/bash`. Bit `session-start-hook.sh` state-prune (PR #47). See the zsh bullet below: that tolerance is the *same* misconception — the Bash tool is not bash.

