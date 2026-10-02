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
loads only when you touch the files it governs. The first two bullets are
verbatim from that split; the consumer-check bullet was written here (2026-10-02).

- `[[ $P =~ $trigger ]]` returns exit 1 on regex non-match — never use `set -e` in routing hooks.

- Bash 3.2 (`/bin/bash`, every `#!/bin/bash` hook) rejects **quoted operands in `$(( ))`**: `$(( "604800" / 86400 ))` → `syntax error: operand expected`, and the error **aborts the script at that line** — in a fail-open hook this silently kills everything after it (e.g. registry building), violating fail-open. Use unquoted arithmetic on validated-numeric input: `[[ "$V" =~ ^[0-9]+$ ]] || V=<default>; N=$(( V / 86400 ))`. The model's Bash tool tolerates the quotes (measured: `zsh` prints `7`, `/bin/bash` 3.2 errors), so this passes manual testing and only fails under 3.2 — always syntax-check hook edits with `/bin/bash -n` and exercise them under `/bin/bash`. Bit `session-start-hook.sh` state-prune (PR #47). See the zsh bullet in `CLAUDE.md`: that tolerance is the *same* misconception — the Bash tool is not bash.

- **Before changing what an existing shared shell function promises (interface, return status, output, side effects), list its consumers, and treat no single tool as complete.** Run `git grep -nw <name>` with NO pathspec: skills call lib functions from bash blocks in `SKILL.md`, tests extract functions BY NAME (`sed -n '/^_json_escape()/,/^}/p'` in `tests/test-deny-reason-reaches-model.sh`), and a lint script and `.sh.txt` fixtures name them too, so a rename breaks consumers that never call it. Serena's `find_referencing_symbols` is a second view, not a substitute: measured 2026-10-02 on five functions it was never more complete than a grep over `*.sh` — it sees no markdown, missed one real call of 148, and is not scope-aware (callers of all five same-named `_json_escape` definitions came back as references to one) — so an empty result is not evidence of no callers. Check it is rooted in the checkout you are changing: it activates the directory the session started in. Use the list to choose the tests to run. Not needed for a new function, a comment, or a change no caller can observe.

