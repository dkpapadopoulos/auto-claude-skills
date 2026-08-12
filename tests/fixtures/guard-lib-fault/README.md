# guard-lib-fault fixtures

Pinned baseline for issue #198 — **never delete**. Named as the permanent eval
set in that issue's pre-registered A/B contract.

`healthy-control.json` is the exact stdout of `hooks/openspec-guard.sh` for
`git push origin HEAD` with every gate-enforcement lib intact, captured from
the guard **at `main` (da651b5), before the degradation advisory landed**, run
against a plugin root holding that revision's `hooks/` while cwd is the branch
worktree.

The state it was captured under is **not** "no evidence of any kind": a clean
verdict bound to HEAD is seeded for token `session-t`, because this is a
routing repo and the branch's own diff touches `hooks/`, so without the seed
routing-governance denies and masks what the test measures. That seed is why
the message names only `requesting-code-review` and not
`verification-before-completion` — the verdict satisfies the VERIFY leg. A
regeneration that skips the seed produces a different string and will look
like drift.

`tests/test-push-gate-degradation-advisory.sh` asserts the healthy control is
byte-identical to this file. That is the no-regression clause: the advisory is
allowed to add output on fault cells, and nothing at all on a healthy one.

Regenerating this file to make a failing test pass defeats its only purpose.
If a deliberate change to the fail-closed deny message makes it stale, update
it in the same commit as that change and say so in the commit message.
