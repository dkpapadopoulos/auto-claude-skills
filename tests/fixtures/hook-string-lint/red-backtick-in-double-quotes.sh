#!/bin/bash
# RED fixture — reproduces the PR#38 class verbatim in shape.
#
# The author wrote markdown-style quoting inside a DOUBLE-quoted assignment.
# Bash runs `verification-before-completion` as a command substitution at
# assignment time: stderr gets a command-not-found, and the word vanishes from
# the rendered text. `bash -n` is clean because the substitution is valid.
RED_FLAGS="Do not claim completion without running `verification-before-completion` first."
printf '%s\n' "${RED_FLAGS}"
