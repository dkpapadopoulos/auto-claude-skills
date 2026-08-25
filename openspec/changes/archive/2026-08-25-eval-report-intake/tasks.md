# Tasks: Eval-report intake repair

> Checkpoints reference branch commits. After squash-merge they are typically
> recoverable only via the feature's GitHub PR (`gh pr view <N> --json commits`)
> — plain clones and forks do not fetch PR refs.

No Superpowers plan artifact exists for this work: the plan was GitHub issue
#203 itself, which carried the reproduction, the suggested direction, and a
pre-registered A/B contract, approved at the improvement-miner human gate
before implementation began. Both `brainstorming` and `writing-plans` were
attested skips on that basis. Tasks below are reconstructed from the branch.

## Completed

- [x] 1.1 Capture the real `gh` author form and pin fixtures per spelling [checkpoint: a6d2baf]
- [x] 1.2 Match the normalised login, ANDed with `is_bot` [checkpoint: a6d2baf]
- [x] 1.3 Warn when the intake admits nothing [checkpoint: a6d2baf]
- [x] 2.1 Require `is_bot == true` rather than tolerating an absent field [checkpoint: ddca0ae]
- [x] 2.2 Pin the title-prefix clause, which had no coverage [checkpoint: ddca0ae]
- [x] 2.3 Repoint the hand-written allowlist test at a real-form fixture [checkpoint: ddca0ae]
- [x] 3.1 Restore title-drift detection as a separately-worded advisory [checkpoint: 743b3d1]
- [x] 3.2 Re-measure the fixture coverage claim [checkpoint: 743b3d1]
- [x] 4.1 Make the title test type-safe in the filter, not only the count [checkpoint: 9aa319a]
- [x] 4.2 Remove the unreachable cannot-count arm and the dead `.title?` [checkpoint: 9aa319a]
