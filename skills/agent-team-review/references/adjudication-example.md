# agent-team-review — §4a worked failure (2026-08-12)

Read at SKILL.md §4a before calling a finding refuted because its pair did not flip. The rule it illustrates (an upstream fail-closed gate masks a downstream fall-open one) stays in SKILL.md. Moved verbatim from SKILL.md.

Observed failure this exists to prevent (2026-08-12): a reviewer reported that without `hooks/lib/git-command.sh` the mutate-then-push check stops firing. The reproduction harness had several faults active at once, an unrelated fail-closed leg produced the same visible verdict either way, and the finding read as refuted. Re-run with **that one lib removed and every other gate satisfied**, the effect appeared exactly as reported. The claim is now a documented invariant in `CLAUDE.md`.
