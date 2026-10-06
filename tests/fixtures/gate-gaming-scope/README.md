# gate-gaming-scope fixtures

`issue-332/test_hidden_runner.py` is a byte copy (`cp`, never retyped) of
`docs/plans/2026-10-04-frontier-ablation/harness/test_hidden_runner.py` as merged
in PR #334. It is the file whose line 53 produced the false `suspect` reported in
issue #332: a skip decorator that is the INPUT of a test proving a skipped test is
not counted as a pass. It sits inside a string and skips nothing.

`tests/test-gate-gaming-scope.sh` plants it in a scratch repository at its
original path under `docs/`. It is a copy rather than a reference to the original
so that removing the evidence bundle under `docs/plans/` cannot turn the suite red.

Do not edit it, and do not reword the marker: the point of the fixture is that the
detector's text match DOES fire on it.
