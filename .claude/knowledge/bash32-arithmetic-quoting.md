---
type: gotcha
title: Bash 3.2 rejects quoted operands in arithmetic
description: Quoted operands in $(( )) abort the script under macOS /bin/bash, breaking fail-open hooks.
tags: [bash, hooks, fail-open]
source: CLAUDE.md:Gotchas
timestamp: 2026-06-18T00:00:00Z
---

Under Bash 3.2 (`/bin/bash`), `$(( "604800" / 86400 ))` raises `syntax error: operand
expected` and **aborts the script at that line**. In a fail-open hook this silently kills
everything after it. Validate-then-unquote instead:

    [[ "$V" =~ ^[0-9]+$ ]] || V=<default>; N=$(( V / 86400 ))

Newer bash (5.x) tolerates the quotes, so this passes manual testing and only fails under
3.2. Always syntax-check hook edits with `/bin/bash -n`.
