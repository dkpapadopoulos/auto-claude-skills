# guard-lib-fault fixtures

Pinned baseline for issue #198 — **never delete**. Named as the permanent eval
set in that issue's pre-registered A/B contract.

`healthy-control.json` is the exact stdout of `hooks/openspec-guard.sh` for a
`git push` with no evidence of any kind and every gate-enforcement lib intact,
captured at `da651b5` **before** the degradation advisory landed.

`tests/test-push-gate-degradation-advisory.sh` asserts the healthy control is
byte-identical to this file. That is the no-regression clause: the advisory is
allowed to add output on fault cells, and nothing at all on a healthy one.

Regenerating this file to make a failing test pass defeats its only purpose.
If a deliberate change to the fail-closed deny message makes it stale, update
it in the same commit as that change and say so in the commit message.
