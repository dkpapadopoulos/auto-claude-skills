# Tasks: Checkpoint Stamping

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

## Completed

- [x] 1.1 Validator TDD: red-first test suite + scripts/checkpoint-validate.sh integrity floor [checkpoint: b942d7a]
- [x] 1.2 openspec-ship SKILL.md: tasks.md template header, stamping guidance, mandatory validator step [checkpoint: b13ed1c]
- [x] 1.3 CHANGELOG entry for checkpoint stamping [checkpoint: d8d578d]
- [x] 1.4 Review fixes from Opus + Codex passes (plugin-root path, no-space stamps, loop guard, fixtures)
