# Tasks: Fix Token Singleton Race

## 1. TDD — regression tests (RED)

- [x] 1.1 `tests/test-session-token-race.sh`: lib unit checks + scenarios 1–6
      from the delta spec (two interleaved sessions; guard keys to payload
      token; singleton fallback; completion-hook keying; re-stamp)
- [x] 1.2 Verify RED under `/bin/bash`

## 2. Implementation (GREEN)

- [x] 2.1 `hooks/lib/session-token.sh` (new)
- [x] 2.2 `session-start-hook.sh` sources lib for token format
- [x] 2.3 Convert `openspec-guard.sh` (batched jq, payload-first)
- [x] 2.4 Convert `skill-activation-hook.sh` (capture-once stdin, single jq
      `\x1f` join, payload-first, singleton re-stamp)
- [x] 2.5 Convert `skill-completion-hook.sh` (merged jq extraction)
- [x] 2.6 Convert `consolidation-stop.sh` (read stdin, payload-first)
- [x] 2.7 Convert `compact-recovery-hook.sh` (move stdin read to top)
- [x] 2.8 `/bin/bash -n` every edited hook; verify GREEN; full suite
      `bash tests/run-tests.sh </dev/null`

## 3. Ship

- [x] 3.1 CHANGELOG entry under [Unreleased]
- [x] 3.2 Review → verification → openspec-ship sync → PR referencing #51
