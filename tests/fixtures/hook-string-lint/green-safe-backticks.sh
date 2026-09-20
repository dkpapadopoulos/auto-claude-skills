#!/bin/bash
# GREEN fixture — every backtick here is literal. All four shapes are harvested
# from the real hooks tree, not invented: each one was a false positive at some
# point while this lint was being written.
#
# 1. Markdown quoting in a comment: `verification-before-completion`.
RED_FLAGS='Do not claim completion without running `verification-before-completion` first.'

# 2. A single-quoted jq program. The backticks are inside shell single quotes,
#    so they are literal even though jq sees them inside a JSON string.
_out="$(printf '%s' '{}' | jq '.text = "Create `openspec/changes/<slug>/proposal.md` first."')"

# 3. A `)` inside a double-quoted string, nested in a command substitution —
#    harvested from hooks/openspec-guard.sh. Nothing here is a substitution, but
#    mis-handling the `)` unbalances the scanner, and every backticked word in
#    the comments BELOW it is then read as live. That was 48 false accusations.
_msg="$(printf '%s' "PUSH GATE (advisory): $1")"
# Commentary following it, in the real file's style: the `available:false` flag
# in the registry cache is not the authority; `_skill_available` reads disk.

# 4. A QUOTED heredoc delimiter — no expansion, so backticks are literal.
cat <<'INNER'
Run `project-verification` before pushing.
INNER

printf '%s %s %s\n' "${RED_FLAGS}" "${_out}" "${_msg}"
