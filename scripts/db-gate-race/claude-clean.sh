#!/bin/bash
# Wrapper passed to the behavioral runner via CLAUDE_BIN. Forces the inner
# `claude -p` to load NO setting sources (strips this repo's plugin hooks/banner
# so the ONLY injected guidance is SKILL_PATH + the arm directive), while
# keeping OAuth auth (unlike --bare, which demands ANTHROPIC_API_KEY). See
# db-gate-race pilot: --bare -> "Not logged in"; --setting-sources "" -> works.
exec claude --setting-sources "" "$@"
